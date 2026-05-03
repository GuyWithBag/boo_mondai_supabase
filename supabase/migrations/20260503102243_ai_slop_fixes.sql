ALTER VIEW leaderboard RENAME COLUMN quiz_score TO drill_score;

-- ══════════════════════════════════════════════════════
-- Drop email from profiles
-- Email already lives in auth.users. Duplicating it here
-- risks stale data and unnecessarily exposes it in the
-- publicly-readable profiles table.
-- ══════════════════════════════════════════════════════
ALTER TABLE profiles DROP COLUMN IF EXISTS email;

-- ══════════════════════════════════════════════════════
-- Rename quiz → drill (tables)
-- ══════════════════════════════════════════════════════
ALTER TABLE quiz_sessions RENAME TO drill_sessions;
ALTER TABLE quiz_answers  RENAME TO drill_answers;

-- ══════════════════════════════════════════════════════
-- Leaderboard view — SECURITY INVOKER
-- The default view security model runs as the view
-- creator (definer), bypassing the querying user's RLS.
-- WITH (security_invoker = true) makes the view respect
-- the querying user's own permissions instead.
-- Requires PostgreSQL 15+ (Supabase default).
-- ══════════════════════════════════════════════════════
CREATE OR REPLACE VIEW leaderboard WITH (security_invoker = true) AS
SELECT
  p.id AS user_id,
  p.display_name,
  p.target_language,
  COALESCE(SUM(qs.correct_count), 0)::int AS drill_score,
  COALESCE(rc.review_count, 0)::int       AS review_count,
  COALESCE(s.current_streak, 0)           AS current_streak
FROM profiles p
LEFT JOIN drill_sessions qs ON qs.user_id = p.id AND qs.completed_at IS NOT NULL
LEFT JOIN (
  SELECT user_id, COUNT(*)::int AS review_count
  FROM review_logs GROUP BY user_id
) rc ON rc.user_id = p.id
LEFT JOIN streaks s ON s.user_id = p.id
WHERE p.role = 'group_a_participant'
GROUP BY p.id, p.display_name, p.target_language, rc.review_count, s.current_streak
ORDER BY drill_score DESC;

-- ══════════════════════════════════════════════════════
-- RLS policy performance — (select auth.uid())
--
-- Calling auth.uid() directly in a policy causes
-- Postgres to re-evaluate it for every row scanned.
-- Wrapping it in (select auth.uid()) makes it a stable
-- scalar subquery evaluated once per query instead.
--
-- Also fixes "Multiple Permissive Policies" on tables
-- that had both a FOR SELECT policy AND a FOR ALL policy
-- (which implicitly includes SELECT). Those are split
-- into explicit FOR INSERT / FOR UPDATE / FOR DELETE so
-- that each action has exactly one permissive policy.
-- ══════════════════════════════════════════════════════

-- ── profiles ──────────────────────────────────────────
DROP POLICY IF EXISTS "profiles: users update own" ON profiles;
DROP POLICY IF EXISTS "profiles: users insert own" ON profiles;
CREATE POLICY "profiles: users update own" ON profiles
  FOR UPDATE
  USING     ((select auth.uid()) = id)
  WITH CHECK ((select auth.uid()) = id);
CREATE POLICY "profiles: users insert own" ON profiles
  FOR INSERT
  WITH CHECK ((select auth.uid()) = id);

-- ── decks ─────────────────────────────────────────────
DROP POLICY IF EXISTS "decks: anyone reads public" ON decks;
DROP POLICY IF EXISTS "decks: users manage own"    ON decks;
CREATE POLICY "decks: anyone reads public" ON decks
  FOR SELECT
  USING (is_public = true OR (select auth.uid()) = creator_id);
CREATE POLICY "decks: users manage own" ON decks
  FOR ALL
  USING     ((select auth.uid()) = creator_id)
  WITH CHECK ((select auth.uid()) = creator_id);

-- ── deck_cards ────────────────────────────────────────
-- Drop the old FOR ALL policy and split into write-only
-- policies so there is exactly one permissive SELECT.
DROP POLICY IF EXISTS "deck_cards: readable if deck accessible" ON deck_cards;
DROP POLICY IF EXISTS "deck_cards: creator manages"             ON deck_cards;
CREATE POLICY "deck_cards: readable if deck accessible" ON deck_cards
  FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM decks
    WHERE decks.id = deck_cards.deck_id
      AND (decks.is_public = true OR decks.creator_id = (select auth.uid()))
  ));
-- SELECT is covered above; only write operations below.
CREATE POLICY "deck_cards: creator manages" ON deck_cards
  FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM decks
    WHERE decks.id = deck_cards.deck_id AND decks.creator_id = (select auth.uid())
  ));
CREATE POLICY "deck_cards: creator updates" ON deck_cards
  FOR UPDATE
  USING     (EXISTS (SELECT 1 FROM decks WHERE decks.id = deck_cards.deck_id AND decks.creator_id = (select auth.uid())))
  WITH CHECK (EXISTS (SELECT 1 FROM decks WHERE decks.id = deck_cards.deck_id AND decks.creator_id = (select auth.uid())));
CREATE POLICY "deck_cards: creator deletes" ON deck_cards
  FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM decks
    WHERE decks.id = deck_cards.deck_id AND decks.creator_id = (select auth.uid())
  ));

-- ── notes ─────────────────────────────────────────────
DROP POLICY IF EXISTS "notes: readable if card accessible" ON notes;
DROP POLICY IF EXISTS "notes: creator manages"             ON notes;
CREATE POLICY "notes: readable if card accessible" ON notes
  FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = notes.card_id
      AND (d.is_public = true OR d.creator_id = (select auth.uid()))
  ));
CREATE POLICY "notes: creator manages" ON notes
  FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = notes.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE POLICY "notes: creator updates" ON notes
  FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = notes.card_id AND d.creator_id = (select auth.uid())
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = notes.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE POLICY "notes: creator deletes" ON notes
  FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = notes.card_id AND d.creator_id = (select auth.uid())
  ));

-- ── mc_options ────────────────────────────────────────
DROP POLICY IF EXISTS "mc_options: readable if card accessible" ON mc_options;
DROP POLICY IF EXISTS "mc_options: creator manages"             ON mc_options;
CREATE POLICY "mc_options: readable if card accessible" ON mc_options
  FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mc_options.card_id
      AND (d.is_public = true OR d.creator_id = (select auth.uid()))
  ));
CREATE POLICY "mc_options: creator manages" ON mc_options
  FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mc_options.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE POLICY "mc_options: creator updates" ON mc_options
  FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mc_options.card_id AND d.creator_id = (select auth.uid())
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mc_options.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE POLICY "mc_options: creator deletes" ON mc_options
  FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mc_options.card_id AND d.creator_id = (select auth.uid())
  ));

-- ── fitb_segments ─────────────────────────────────────
DROP POLICY IF EXISTS "fitb_segments: readable if card accessible" ON fitb_segments;
DROP POLICY IF EXISTS "fitb_segments: creator manages"             ON fitb_segments;
CREATE POLICY "fitb_segments: readable if card accessible" ON fitb_segments
  FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = fitb_segments.card_id
      AND (d.is_public = true OR d.creator_id = (select auth.uid()))
  ));
CREATE POLICY "fitb_segments: creator manages" ON fitb_segments
  FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = fitb_segments.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE POLICY "fitb_segments: creator updates" ON fitb_segments
  FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = fitb_segments.card_id AND d.creator_id = (select auth.uid())
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = fitb_segments.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE POLICY "fitb_segments: creator deletes" ON fitb_segments
  FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = fitb_segments.card_id AND d.creator_id = (select auth.uid())
  ));

-- ── mm_pairs ──────────────────────────────────────────
DROP POLICY IF EXISTS "mm_pairs: readable if card accessible" ON mm_pairs;
DROP POLICY IF EXISTS "mm_pairs: creator manages"             ON mm_pairs;
CREATE POLICY "mm_pairs: readable if card accessible" ON mm_pairs
  FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mm_pairs.card_id
      AND (d.is_public = true OR d.creator_id = (select auth.uid()))
  ));
CREATE POLICY "mm_pairs: creator manages" ON mm_pairs
  FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mm_pairs.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE POLICY "mm_pairs: creator updates" ON mm_pairs
  FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mm_pairs.card_id AND d.creator_id = (select auth.uid())
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mm_pairs.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE POLICY "mm_pairs: creator deletes" ON mm_pairs
  FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mm_pairs.card_id AND d.creator_id = (select auth.uid())
  ));

-- ── drill_sessions ───────────────────────────────────
DROP POLICY IF EXISTS "quiz_sessions: users manage own"  ON drill_sessions;
DROP POLICY IF EXISTS "drill_sessions: users manage own" ON drill_sessions;
CREATE POLICY "drill_sessions: users manage own" ON drill_sessions
  FOR ALL
  USING     ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

-- ── drill_answers ────────────────────────────────────
DROP POLICY IF EXISTS "quiz_answers: users manage own"  ON drill_answers;
DROP POLICY IF EXISTS "drill_answers: users manage own" ON drill_answers;
CREATE POLICY "drill_answers: users manage own" ON drill_answers
  FOR ALL
  USING  (EXISTS (SELECT 1 FROM drill_sessions WHERE drill_sessions.id = drill_answers.session_id AND drill_sessions.user_id = (select auth.uid())))
  WITH CHECK (EXISTS (SELECT 1 FROM drill_sessions WHERE drill_sessions.id = drill_answers.session_id AND drill_sessions.user_id = (select auth.uid())));

-- ── fsrs_cards ────────────────────────────────────────
DROP POLICY IF EXISTS "fsrs_cards: users manage own" ON fsrs_cards;
CREATE POLICY "fsrs_cards: users manage own" ON fsrs_cards
  FOR ALL
  USING     ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

-- ── review_logs ───────────────────────────────────────
DROP POLICY IF EXISTS "review_logs: users manage own" ON review_logs;
CREATE POLICY "review_logs: users manage own" ON review_logs
  FOR ALL
  USING     ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

-- ── streaks ───────────────────────────────────────────
DROP POLICY IF EXISTS "streaks: users manage own" ON streaks;
CREATE POLICY "streaks: users manage own" ON streaks
  FOR ALL
  USING     ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

-- ── research_users ────────────────────────────────────
DROP POLICY IF EXISTS "research_users: researchers manage" ON research_users;
DROP POLICY IF EXISTS "research_users: users read own"     ON research_users;
CREATE POLICY "research_users: researchers manage" ON research_users
  FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE POLICY "research_users: users read own" ON research_users
  FOR SELECT
  USING ((select auth.uid()) = user_id);

-- ── research_codes ────────────────────────────────────
DROP POLICY IF EXISTS "research_codes: researchers manage"    ON research_codes;
DROP POLICY IF EXISTS "research_codes: participants redeem"   ON research_codes;
DROP POLICY IF EXISTS "research_codes: participants read own" ON research_codes;
CREATE POLICY "research_codes: researchers manage" ON research_codes
  FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE POLICY "research_codes: participants redeem" ON research_codes
  FOR UPDATE
  USING (used_by IS NULL)
  WITH CHECK ((select auth.uid()) = used_by);
CREATE POLICY "research_codes: participants read own" ON research_codes
  FOR SELECT
  USING ((select auth.uid()) = used_by OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));

-- ── research_proficiency_screener ─────────────────────
DROP POLICY IF EXISTS "research_proficiency_screener: users insert own" ON research_proficiency_screener;
DROP POLICY IF EXISTS "research_proficiency_screener: read"             ON research_proficiency_screener;
CREATE POLICY "research_proficiency_screener: users insert own" ON research_proficiency_screener
  FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_proficiency_screener: read" ON research_proficiency_screener
  FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));

-- ── research_language_interest ────────────────────────
DROP POLICY IF EXISTS "research_language_interest: users insert own" ON research_language_interest;
DROP POLICY IF EXISTS "research_language_interest: read"             ON research_language_interest;
CREATE POLICY "research_language_interest: users insert own" ON research_language_interest
  FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_language_interest: read" ON research_language_interest
  FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));

-- ── research_vocabulary_test ──────────────────────────
DROP POLICY IF EXISTS "research_vocabulary_test: users insert own" ON research_vocabulary_test;
DROP POLICY IF EXISTS "research_vocabulary_test: read"             ON research_vocabulary_test;
CREATE POLICY "research_vocabulary_test: users insert own" ON research_vocabulary_test
  FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_vocabulary_test: read" ON research_vocabulary_test
  FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));

-- ── research_experience_survey ────────────────────────
DROP POLICY IF EXISTS "research_experience_survey: users insert own" ON research_experience_survey;
DROP POLICY IF EXISTS "research_experience_survey: read"             ON research_experience_survey;
CREATE POLICY "research_experience_survey: users insert own" ON research_experience_survey
  FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_experience_survey: read" ON research_experience_survey
  FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));

-- ── research_preview_usefulness ───────────────────────
DROP POLICY IF EXISTS "research_preview_usefulness: group_a insert own" ON research_preview_usefulness;
DROP POLICY IF EXISTS "research_preview_usefulness: read"               ON research_preview_usefulness;
CREATE POLICY "research_preview_usefulness: group_a insert own" ON research_preview_usefulness
  FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_preview_usefulness: read" ON research_preview_usefulness
  FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));

-- ── research_fsrs_usefulness ──────────────────────────
DROP POLICY IF EXISTS "research_fsrs_usefulness: group_a insert own" ON research_fsrs_usefulness;
DROP POLICY IF EXISTS "research_fsrs_usefulness: read"               ON research_fsrs_usefulness;
CREATE POLICY "research_fsrs_usefulness: group_a insert own" ON research_fsrs_usefulness
  FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_fsrs_usefulness: read" ON research_fsrs_usefulness
  FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));

-- ── research_ugc_perception ───────────────────────────
DROP POLICY IF EXISTS "research_ugc_perception: users insert own" ON research_ugc_perception;
DROP POLICY IF EXISTS "research_ugc_perception: read"             ON research_ugc_perception;
CREATE POLICY "research_ugc_perception: users insert own" ON research_ugc_perception
  FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_ugc_perception: read" ON research_ugc_perception
  FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));

-- ── research_sus ──────────────────────────────────────
DROP POLICY IF EXISTS "research_sus: group_a insert own" ON research_sus;
DROP POLICY IF EXISTS "research_sus: read"               ON research_sus;
CREATE POLICY "research_sus: group_a insert own" ON research_sus
  FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_sus: read" ON research_sus
  FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
