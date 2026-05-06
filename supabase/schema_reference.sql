-- ══════════════════════════════════════════════════════
-- BooMondai — Schema Reference
--
-- READ-ONLY reference. Do NOT apply this file directly.
-- The live schema is built by running all migrations in
-- supabase/migrations/ in order.
--
-- This file is kept up-to-date manually and reflects the
-- actual DB state after all migrations have been applied.
-- Use it to quickly understand the current schema without
-- having to mentally trace through every migration.
-- ══════════════════════════════════════════════════════

-- ── Extensions ────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS moddatetime SCHEMA extensions;

-- ══════════════════════════════════════════════════════
-- CORE TABLES
-- ══════════════════════════════════════════════════════

-- ── profiles ──────────────────────────────────────────
-- Email is intentionally omitted — read it from auth.users
-- via the session (supabase.auth.getUser()).
CREATE TABLE profiles (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  username        text NOT NULL,
  role            text NOT NULL DEFAULT 'group_a_participant'
                  CHECK (role IN ('group_a_participant', 'group_b_participant', 'researcher')),
  avatar_url      text,
  is_anonymous    bool NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "profiles: users read all"   ON profiles FOR SELECT USING (true);
CREATE POLICY "profiles: users update own" ON profiles FOR UPDATE
  USING     ((select auth.uid()) = id)
  WITH CHECK ((select auth.uid()) = id);
CREATE POLICY "profiles: users insert own" ON profiles FOR INSERT
  WITH CHECK ((select auth.uid()) = id);
CREATE TRIGGER set_updated_at BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

-- ── decks ─────────────────────────────────────────────
CREATE TABLE decks (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id        uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title             text NOT NULL,
  short_description text NOT NULL DEFAULT '',
  long_description  text NOT NULL DEFAULT '',
  target_language   text NOT NULL,
  tags              text[] NOT NULL DEFAULT '{}',
  is_premade        bool NOT NULL DEFAULT false,
  is_public         bool NOT NULL DEFAULT true,
  is_uneditable     bool NOT NULL DEFAULT false,
  -- When true the deck is excluded from the public browser.
  -- Researchers use this to distribute premade decks via codes only.
  hidden_in_browser bool NOT NULL DEFAULT false,
  card_count        int  NOT NULL DEFAULT 0,
  version           text NOT NULL DEFAULT '1.0.0',
  build_number      int  NOT NULL DEFAULT 1,
  -- When non-null this deck was copied from another public deck.
  -- Enables "Original by …" attribution in the online browser.
  source_deck_id    uuid REFERENCES decks(id) ON DELETE SET NULL,
  -- When true the deck is visible in the browser and sync-able.
  is_published      bool NOT NULL DEFAULT false,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE decks ENABLE ROW LEVEL SECURITY;
-- Single permissive SELECT — creator access covered by the OR branch.
CREATE POLICY "decks: anyone reads public" ON decks FOR SELECT
  USING (is_public = true OR (select auth.uid()) = creator_id);
CREATE POLICY "decks: creator manages" ON decks FOR INSERT
  WITH CHECK ((select auth.uid()) = creator_id);
CREATE POLICY "decks: creator updates" ON decks FOR UPDATE
  USING     ((select auth.uid()) = creator_id)
  WITH CHECK ((select auth.uid()) = creator_id);
CREATE POLICY "decks: creator deletes" ON decks FOR DELETE
  USING ((select auth.uid()) = creator_id);
CREATE INDEX ON decks (creator_id);
CREATE INDEX ON decks (target_language);
CREATE INDEX ON decks (is_public);
CREATE INDEX ON decks (source_deck_id);
CREATE INDEX ON decks USING gin (tags);
CREATE TRIGGER set_updated_at BEFORE UPDATE ON decks
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

-- ── deck_cards ────────────────────────────────────────
-- Stores type metadata only. All content lives in child tables.
--
-- question_type values:
--   flashcard          → show front, reveal back, self-grade
--   identification     → learner types answer (identification_answer)
--   multiple_choice    → pick from mc_options
--   fill_in_the_blanks → type missing words from fitb_segments
--   word_scramble      → tap chips to reconstruct sentence in note.front_text
--   match_madness      → drag-drop pairs from mm_pairs; no notes generated
CREATE TABLE deck_cards (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  deck_id               uuid NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  card_type             text NOT NULL DEFAULT 'normal'
                        CHECK (card_type IN ('normal', 'reversed', 'both')),
  question_type         text NOT NULL DEFAULT 'flashcard'
                        CHECK (question_type IN (
                          'flashcard', 'identification', 'multiple_choice',
                          'fill_in_the_blanks', 'word_scramble', 'match_madness'
                        )),
  -- Comma-separated acceptable answers for question_type = 'identification'.
  identification_answer text,
  sort_order            int  NOT NULL DEFAULT 0,
  source_card_id        uuid REFERENCES deck_cards(id) ON DELETE SET NULL,
  created_at            timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE deck_cards ENABLE ROW LEVEL SECURITY;
-- Single permissive SELECT — creator access covered by the OR branch.
CREATE POLICY "deck_cards: readable if deck accessible" ON deck_cards FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM decks
    WHERE decks.id = deck_cards.deck_id
      AND (decks.is_public = true OR decks.creator_id = (select auth.uid()))
  ));
CREATE POLICY "deck_cards: creator manages" ON deck_cards FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM decks
    WHERE decks.id = deck_cards.deck_id AND decks.creator_id = (select auth.uid())
  ));
CREATE POLICY "deck_cards: creator updates" ON deck_cards FOR UPDATE
  USING     (EXISTS (SELECT 1 FROM decks WHERE decks.id = deck_cards.deck_id AND decks.creator_id = (select auth.uid())))
  WITH CHECK (EXISTS (SELECT 1 FROM decks WHERE decks.id = deck_cards.deck_id AND decks.creator_id = (select auth.uid())));
CREATE POLICY "deck_cards: creator deletes" ON deck_cards FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM decks
    WHERE decks.id = deck_cards.deck_id AND decks.creator_id = (select auth.uid())
  ));
CREATE INDEX ON deck_cards (deck_id);
CREATE INDEX ON deck_cards (source_card_id);

-- ── notes ─────────────────────────────────────────────
-- Content node for a card. A normal card has 1 note;
-- a CardType.both card has 2 (is_reverse=false and is_reverse=true).
-- match_madness cards have NO notes.
CREATE TABLE notes (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id         uuid NOT NULL REFERENCES deck_cards(id) ON DELETE CASCADE,
  front_text      text NOT NULL DEFAULT '',
  back_text       text NOT NULL DEFAULT '',
  front_audio_url text,
  back_audio_url  text,
  front_image_url text,
  back_image_url  text,
  is_reverse      bool NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notes: readable if card accessible" ON notes FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = notes.card_id
      AND (d.is_public = true OR d.creator_id = (select auth.uid()))
  ));
CREATE POLICY "notes: creator manages" ON notes FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = notes.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE POLICY "notes: creator updates" ON notes FOR UPDATE
  USING     (EXISTS (SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id WHERE dc.id = notes.card_id AND d.creator_id = (select auth.uid())))
  WITH CHECK (EXISTS (SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id WHERE dc.id = notes.card_id AND d.creator_id = (select auth.uid())));
CREATE POLICY "notes: creator deletes" ON notes FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = notes.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE INDEX ON notes (card_id);

-- ── mc_options ────────────────────────────────────────
-- Answer options for question_type = 'multiple_choice'.
-- Exactly one row per card must have is_correct = true.
CREATE TABLE mc_options (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id       uuid NOT NULL REFERENCES deck_cards(id) ON DELETE CASCADE,
  option_text   text NOT NULL,
  is_correct    bool NOT NULL DEFAULT false,
  display_order int  NOT NULL DEFAULT 0
);
ALTER TABLE mc_options ENABLE ROW LEVEL SECURITY;
CREATE POLICY "mc_options: readable if card accessible" ON mc_options FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mc_options.card_id
      AND (d.is_public = true OR d.creator_id = (select auth.uid()))
  ));
CREATE POLICY "mc_options: creator manages" ON mc_options FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mc_options.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE POLICY "mc_options: creator updates" ON mc_options FOR UPDATE
  USING     (EXISTS (SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id WHERE dc.id = mc_options.card_id AND d.creator_id = (select auth.uid())))
  WITH CHECK (EXISTS (SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id WHERE dc.id = mc_options.card_id AND d.creator_id = (select auth.uid())));
CREATE POLICY "mc_options: creator deletes" ON mc_options FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mc_options.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE INDEX ON mc_options (card_id);

-- ── fitb_segments ─────────────────────────────────────
-- One blank per row for question_type = 'fill_in_the_blanks'.
-- full_text stores the complete sentence; blank_start/blank_end
-- are character indices (0-indexed, exclusive end) marking the hidden word.
CREATE TABLE fitb_segments (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id        uuid NOT NULL REFERENCES deck_cards(id) ON DELETE CASCADE,
  full_text      text NOT NULL,
  blank_start    int  NOT NULL,
  blank_end      int  NOT NULL,
  correct_answer text NOT NULL,
  CONSTRAINT fitb_blank_order CHECK (blank_start < blank_end)
);
ALTER TABLE fitb_segments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "fitb_segments: readable if card accessible" ON fitb_segments FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = fitb_segments.card_id
      AND (d.is_public = true OR d.creator_id = (select auth.uid()))
  ));
CREATE POLICY "fitb_segments: creator manages" ON fitb_segments FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = fitb_segments.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE POLICY "fitb_segments: creator updates" ON fitb_segments FOR UPDATE
  USING     (EXISTS (SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id WHERE dc.id = fitb_segments.card_id AND d.creator_id = (select auth.uid())))
  WITH CHECK (EXISTS (SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id WHERE dc.id = fitb_segments.card_id AND d.creator_id = (select auth.uid())));
CREATE POLICY "fitb_segments: creator deletes" ON fitb_segments FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = fitb_segments.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE INDEX ON fitb_segments (card_id);

-- ── mm_pairs ──────────────────────────────────────────
-- Term↔match pairs for question_type = 'match_madness'.
-- source_card_id references the card a pair was auto-generated from.
CREATE TABLE mm_pairs (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id        uuid NOT NULL REFERENCES deck_cards(id) ON DELETE CASCADE,
  source_card_id uuid REFERENCES deck_cards(id) ON DELETE SET NULL,
  term           text NOT NULL,
  match          text NOT NULL,
  is_auto_picked bool NOT NULL DEFAULT false,
  display_order  int  NOT NULL DEFAULT 0
);
ALTER TABLE mm_pairs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "mm_pairs: readable if card accessible" ON mm_pairs FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mm_pairs.card_id
      AND (d.is_public = true OR d.creator_id = (select auth.uid()))
  ));
CREATE POLICY "mm_pairs: creator manages" ON mm_pairs FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mm_pairs.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE POLICY "mm_pairs: creator updates" ON mm_pairs FOR UPDATE
  USING     (EXISTS (SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id WHERE dc.id = mm_pairs.card_id AND d.creator_id = (select auth.uid())))
  WITH CHECK (EXISTS (SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id WHERE dc.id = mm_pairs.card_id AND d.creator_id = (select auth.uid())));
CREATE POLICY "mm_pairs: creator deletes" ON mm_pairs FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id
    WHERE dc.id = mm_pairs.card_id AND d.creator_id = (select auth.uid())
  ));
CREATE INDEX ON mm_pairs (card_id);
CREATE INDEX ON mm_pairs (source_card_id);

-- ── drill_sessions ────────────────────────────────────
CREATE TABLE drill_sessions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  deck_id         uuid NOT NULL REFERENCES decks(id)    ON DELETE CASCADE,
  previewed       bool NOT NULL DEFAULT false,
  total_questions int  NOT NULL,
  correct_count   int  NOT NULL DEFAULT 0,
  started_at      timestamptz NOT NULL DEFAULT now(),
  completed_at    timestamptz
);
ALTER TABLE drill_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "drill_sessions: users manage own" ON drill_sessions FOR ALL
  USING     ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);
CREATE INDEX ON drill_sessions (user_id);
CREATE INDEX ON drill_sessions (deck_id);

-- ── drill_answers ─────────────────────────────────────
CREATE TABLE drill_answers (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  uuid NOT NULL REFERENCES drill_sessions(id) ON DELETE CASCADE,
  card_id     uuid NOT NULL REFERENCES deck_cards(id)     ON DELETE CASCADE,
  user_answer text NOT NULL,
  is_correct  bool NOT NULL,
  self_rating int  CHECK (self_rating BETWEEN 1 AND 4),
  answered_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE drill_answers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "drill_answers: users manage own" ON drill_answers FOR ALL
  USING  (EXISTS (SELECT 1 FROM drill_sessions WHERE drill_sessions.id = drill_answers.session_id AND drill_sessions.user_id = (select auth.uid())))
  WITH CHECK (EXISTS (SELECT 1 FROM drill_sessions WHERE drill_sessions.id = drill_answers.session_id AND drill_sessions.user_id = (select auth.uid())));
CREATE INDEX ON drill_answers (session_id);
CREATE INDEX ON drill_answers (card_id);

-- ── fsrs_cards ────────────────────────────────────────
-- One row per (user, card) — enforced by the UNIQUE constraint.
-- id is a plain uuid; do NOT construct composite keys in app code.
CREATE TABLE fsrs_cards (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES profiles(id)   ON DELETE CASCADE,
  card_id        uuid NOT NULL REFERENCES deck_cards(id) ON DELETE CASCADE,
  due            timestamptz NOT NULL,
  stability      double precision NOT NULL,
  difficulty     double precision NOT NULL,
  elapsed_days   int NOT NULL DEFAULT 0,
  scheduled_days int NOT NULL DEFAULT 0,
  reps           int NOT NULL DEFAULT 0,
  lapses         int NOT NULL DEFAULT 0,
  state          int NOT NULL DEFAULT 0,
  last_review    timestamptz,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, card_id)
);
ALTER TABLE fsrs_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "fsrs_cards: users manage own" ON fsrs_cards FOR ALL
  USING     ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);
CREATE INDEX ON fsrs_cards (user_id);
CREATE INDEX ON fsrs_cards (user_id, due);
CREATE TRIGGER set_updated_at BEFORE UPDATE ON fsrs_cards
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

-- ── review_logs ───────────────────────────────────────
CREATE TABLE review_logs (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES profiles(id)   ON DELETE CASCADE,
  card_id        uuid NOT NULL REFERENCES deck_cards(id) ON DELETE CASCADE,
  rating         int  NOT NULL CHECK (rating BETWEEN 1 AND 4),
  scheduled_days int  NOT NULL,
  elapsed_days   int  NOT NULL,
  review         timestamptz NOT NULL,
  state          int  NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE review_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "review_logs: users manage own" ON review_logs FOR ALL
  USING     ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);
CREATE INDEX ON review_logs (user_id);
CREATE INDEX ON review_logs (card_id);

-- ── streaks ───────────────────────────────────────────
CREATE TABLE streaks (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            uuid NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  current_streak     int  NOT NULL DEFAULT 0,
  longest_streak     int  NOT NULL DEFAULT 0,
  last_activity_date date,
  updated_at         timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE streaks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "streaks: users manage own" ON streaks FOR ALL
  USING     ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);
CREATE INDEX ON streaks (user_id);
CREATE TRIGGER set_updated_at BEFORE UPDATE ON streaks
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

-- ── leaderboard (view) ────────────────────────────────
CREATE OR REPLACE VIEW leaderboard WITH (security_invoker = true) AS
SELECT
  p.id AS user_id,
  COALESCE(SUM(qs.correct_count), 0)::int AS drill_score,
  COALESCE(rc.review_count, 0)::int       AS review_count
FROM profiles p
LEFT JOIN drill_sessions qs ON qs.user_id = p.id AND qs.completed_at IS NOT NULL
LEFT JOIN (
  SELECT user_id, COUNT(*)::int AS review_count
  FROM review_logs GROUP BY user_id
) rc ON rc.user_id = p.id
WHERE p.role = 'group_a_participant'
GROUP BY p.id, rc.review_count
ORDER BY drill_score DESC;

-- ══════════════════════════════════════════════════════
-- RESEARCH TABLES
-- ══════════════════════════════════════════════════════

-- ── research_profiles ────────────────────────────────
CREATE TABLE research_profiles (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  first_name      text NOT NULL DEFAULT '',
  last_name       text NOT NULL DEFAULT '',
  age             int  NOT NULL DEFAULT 0,
  role            text NOT NULL CHECK (role IN ('group_a_participant', 'group_b_participant')),
  goal            text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE research_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "research_profiles: researcher manages" ON research_profiles FOR ALL
  USING (EXISTS (
    SELECT 1 FROM profiles WHERE id = current_profile_id() AND role = 'researcher'
  ));
CREATE POLICY "research_profiles: read own" ON research_profiles FOR SELECT
  USING (user_id = current_profile_id());
CREATE INDEX ON research_profiles (user_id);

-- ── research_codes ────────────────────────────────────
CREATE TABLE research_codes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL UNIQUE,
  target_role text NOT NULL,
  unlocks     text NOT NULL,
  created_by  uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  used_by     uuid REFERENCES profiles(id),
  used_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE research_codes ENABLE ROW LEVEL SECURITY;
-- Participants see codes they've redeemed; researchers see all.
CREATE POLICY "research_codes: participants read own" ON research_codes FOR SELECT
  USING ((select auth.uid()) = used_by OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
-- Merged UPDATE: participants redeem unclaimed codes (must set used_by = self);
-- researchers may update any code to any value.
CREATE POLICY "research_codes: update" ON research_codes FOR UPDATE
  USING (
    used_by IS NULL
    OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher')
  )
  WITH CHECK (
    (select auth.uid()) = used_by
    OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher')
  );
CREATE POLICY "research_codes: researchers manages" ON research_codes FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE POLICY "research_codes: researchers deletes" ON research_codes FOR DELETE
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE INDEX ON research_codes (code);
CREATE INDEX ON research_codes (created_by);

-- ── research_proficiency_screener ─────────────────────
CREATE TABLE research_proficiency_screener (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  item_1            int NOT NULL CHECK (item_1 BETWEEN 1 AND 5),
  item_2            int NOT NULL CHECK (item_2 BETWEEN 1 AND 5),
  item_3            int NOT NULL CHECK (item_3 BETWEEN 1 AND 5),
  item_4            int NOT NULL CHECK (item_4 BETWEEN 1 AND 5),
  item_5            int NOT NULL CHECK (item_5 BETWEEN 1 AND 5),
  item_6            int NOT NULL CHECK (item_6 BETWEEN 1 AND 5),
  proficiency_level text NOT NULL CHECK (proficiency_level IN ('none','beginner','elementary','intermediate','advanced')),
  submitted_at      timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE research_proficiency_screener ENABLE ROW LEVEL SECURITY;
CREATE POLICY "research_proficiency_screener: users insert own" ON research_proficiency_screener FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_proficiency_screener: read" ON research_proficiency_screener FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE INDEX ON research_proficiency_screener (user_id);

-- ── research_language_interest ────────────────────────
CREATE TABLE research_language_interest (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  item_1       int NOT NULL CHECK (item_1 BETWEEN 1 AND 5),
  item_2       int NOT NULL CHECK (item_2 BETWEEN 1 AND 5),
  item_3       int NOT NULL CHECK (item_3 BETWEEN 1 AND 5),
  item_4       int NOT NULL CHECK (item_4 BETWEEN 1 AND 5),
  item_5       int NOT NULL CHECK (item_5 BETWEEN 1 AND 5),
  submitted_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE research_language_interest ENABLE ROW LEVEL SECURITY;
CREATE POLICY "research_language_interest: users insert own" ON research_language_interest FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_language_interest: read" ON research_language_interest FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE INDEX ON research_language_interest (user_id);

-- ── research_vocabulary_test ──────────────────────────
CREATE TABLE research_vocabulary_test (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  test_set     text NOT NULL CHECK (test_set IN ('A', 'B')),
  score        int  NOT NULL CHECK (score BETWEEN 0 AND 30),
  answers      jsonb NOT NULL,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, test_set)
);
ALTER TABLE research_vocabulary_test ENABLE ROW LEVEL SECURITY;
CREATE POLICY "research_vocabulary_test: users insert own" ON research_vocabulary_test FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_vocabulary_test: read" ON research_vocabulary_test FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE INDEX ON research_vocabulary_test (user_id);

-- ── research_experience_survey ────────────────────────
CREATE TABLE research_experience_survey (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  time_point   text NOT NULL CHECK (time_point IN ('short_term', 'long_term')),
  enjoyment_1  int NOT NULL CHECK (enjoyment_1  BETWEEN 1 AND 5),
  enjoyment_2  int NOT NULL CHECK (enjoyment_2  BETWEEN 1 AND 5),
  enjoyment_3  int NOT NULL CHECK (enjoyment_3  BETWEEN 1 AND 5),
  enjoyment_4  int NOT NULL CHECK (enjoyment_4  BETWEEN 1 AND 5),
  enjoyment_5  int NOT NULL CHECK (enjoyment_5  BETWEEN 1 AND 5),
  engagement_1 int NOT NULL CHECK (engagement_1 BETWEEN 1 AND 5),
  engagement_2 int NOT NULL CHECK (engagement_2 BETWEEN 1 AND 5),
  engagement_3 int NOT NULL CHECK (engagement_3 BETWEEN 1 AND 5),
  engagement_4 int NOT NULL CHECK (engagement_4 BETWEEN 1 AND 5),
  engagement_5 int NOT NULL CHECK (engagement_5 BETWEEN 1 AND 5),
  motivation_1 int NOT NULL CHECK (motivation_1 BETWEEN 1 AND 5),
  motivation_2 int NOT NULL CHECK (motivation_2 BETWEEN 1 AND 5),
  motivation_3 int NOT NULL CHECK (motivation_3 BETWEEN 1 AND 5),
  motivation_4 int NOT NULL CHECK (motivation_4 BETWEEN 1 AND 5),
  motivation_5 int NOT NULL CHECK (motivation_5 BETWEEN 1 AND 5),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, time_point)
);
ALTER TABLE research_experience_survey ENABLE ROW LEVEL SECURITY;
CREATE POLICY "research_experience_survey: users insert own" ON research_experience_survey FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_experience_survey: read" ON research_experience_survey FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE INDEX ON research_experience_survey (user_id);

-- ── research_preview_usefulness ───────────────────────
CREATE TABLE research_preview_usefulness (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  item_1       int NOT NULL CHECK (item_1 BETWEEN 1 AND 5),
  item_2       int NOT NULL CHECK (item_2 BETWEEN 1 AND 5),
  item_3       int NOT NULL CHECK (item_3 BETWEEN 1 AND 5),
  item_4       int NOT NULL CHECK (item_4 BETWEEN 1 AND 5),
  item_5       int NOT NULL CHECK (item_5 BETWEEN 1 AND 5),
  submitted_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE research_preview_usefulness ENABLE ROW LEVEL SECURITY;
CREATE POLICY "research_preview_usefulness: group_a insert own" ON research_preview_usefulness FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_preview_usefulness: read" ON research_preview_usefulness FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE INDEX ON research_preview_usefulness (user_id);

-- ── research_fsrs_usefulness ──────────────────────────
CREATE TABLE research_fsrs_usefulness (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  item_1       int NOT NULL CHECK (item_1 BETWEEN 1 AND 5),
  item_2       int NOT NULL CHECK (item_2 BETWEEN 1 AND 5),
  item_3       int NOT NULL CHECK (item_3 BETWEEN 1 AND 5),
  item_4       int NOT NULL CHECK (item_4 BETWEEN 1 AND 5),
  item_5       int NOT NULL CHECK (item_5 BETWEEN 1 AND 5),
  submitted_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE research_fsrs_usefulness ENABLE ROW LEVEL SECURITY;
CREATE POLICY "research_fsrs_usefulness: group_a insert own" ON research_fsrs_usefulness FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_fsrs_usefulness: read" ON research_fsrs_usefulness FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE INDEX ON research_fsrs_usefulness (user_id);

-- ── research_ugc_perception ───────────────────────────
CREATE TABLE research_ugc_perception (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  item_1       int NOT NULL CHECK (item_1 BETWEEN 1 AND 5),
  item_2       int NOT NULL CHECK (item_2 BETWEEN 1 AND 5),
  item_3       int NOT NULL CHECK (item_3 BETWEEN 1 AND 5),
  item_4       int NOT NULL CHECK (item_4 BETWEEN 1 AND 5),
  item_5       int NOT NULL CHECK (item_5 BETWEEN 1 AND 5),
  item_6       int NOT NULL CHECK (item_6 BETWEEN 1 AND 5),
  submitted_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE research_ugc_perception ENABLE ROW LEVEL SECURITY;
CREATE POLICY "research_ugc_perception: users insert own" ON research_ugc_perception FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_ugc_perception: read" ON research_ugc_perception FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE INDEX ON research_ugc_perception (user_id);

-- ── research_sus ──────────────────────────────────────
CREATE TABLE research_sus (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  item_1       int NOT NULL CHECK (item_1 BETWEEN 1 AND 5),
  item_2       int NOT NULL CHECK (item_2 BETWEEN 1 AND 5),
  item_3       int NOT NULL CHECK (item_3 BETWEEN 1 AND 5),
  item_4       int NOT NULL CHECK (item_4 BETWEEN 1 AND 5),
  item_5       int NOT NULL CHECK (item_5 BETWEEN 1 AND 5),
  item_6       int NOT NULL CHECK (item_6 BETWEEN 1 AND 5),
  item_7       int NOT NULL CHECK (item_7 BETWEEN 1 AND 5),
  item_8       int NOT NULL CHECK (item_8 BETWEEN 1 AND 5),
  item_9       int NOT NULL CHECK (item_9 BETWEEN 1 AND 5),
  item_10      int NOT NULL CHECK (item_10 BETWEEN 1 AND 5),
  sus_score    double precision NOT NULL,
  submitted_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE research_sus ENABLE ROW LEVEL SECURITY;
CREATE POLICY "research_sus: group_a insert own" ON research_sus FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "research_sus: read" ON research_sus FOR SELECT
  USING ((select auth.uid()) = user_id OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE INDEX ON research_sus (user_id);
