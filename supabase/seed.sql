-- ══════════════════════════════════════════════════════
-- BooMondai — Seed / Mock Data
-- Automatically creates 4 test auth users and all sample
-- data on every `supabase db reset`. No manual steps needed.
--
--   Email                  Password     Role
--   researcher@test.com    password123  researcher
--   alice@test.com         password123  group_a_participant
--   bob@test.com           password123  group_a_participant
--   carol@test.com         password123  group_b_participant
-- ══════════════════════════════════════════════════════

DO $$
DECLARE
  -- ── Users ────────────────────────────────────────────
  researcher_id uuid := gen_random_uuid();
  alice_id      uuid := gen_random_uuid();
  bob_id        uuid := gen_random_uuid();
  carol_id      uuid := gen_random_uuid();

  -- ── Decks ─────────────────────────────────────────────
  deck_n5_id    uuid := gen_random_uuid(); -- JLPT N5 Vocabulary (premade, researcher)
  deck_alice_id uuid := gen_random_uuid(); -- My Extra Vocab (alice)
  deck_bob_id   uuid := gen_random_uuid(); -- N5 Copy (bob)

  -- ── Deck Cards ────────────────────────────────────────
  card_inu_id    uuid := gen_random_uuid(); -- 犬  flashcard        (N5)
  card_neko_id   uuid := gen_random_uuid(); -- 猫  flashcard both   (N5)
  card_tori_id   uuid := gen_random_uuid(); -- 鳥  multiple_choice  (N5)
  card_sakana_id uuid := gen_random_uuid(); -- 魚  fill_in_blanks   (N5)
  card_hana_id   uuid := gen_random_uuid(); -- 花  flashcard        (N5)
  card_sora_id   uuid := gen_random_uuid(); -- 空  flashcard        (alice)
  card_umi_id    uuid := gen_random_uuid(); -- 海  flashcard rev    (alice)
  card_bob_inu_id  uuid := gen_random_uuid(); -- copy of 犬 (bob)
  card_bob_neko_id uuid := gen_random_uuid(); -- copy of 猫 (bob)

  -- ── Streaks ───────────────────────────────────────────
  streak_alice_id uuid := gen_random_uuid();
  streak_bob_id   uuid := gen_random_uuid();

  -- ── Research ──────────────────────────────────────────
  ru_alice_id uuid := gen_random_uuid();
  ru_bob_id   uuid := gen_random_uuid();
  ru_carol_id uuid := gen_random_uuid();

  -- ── Drill Session ─────────────────────────────────────
  drill_session_alice_id uuid := gen_random_uuid();

BEGIN

-- ── Auth Users ────────────────────────────────────────
-- Insert directly into auth schema so the profiles FK is
-- satisfied on a fresh db reset without any manual steps.
INSERT INTO auth.users (
  id, instance_id, aud, role,
  email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) VALUES
  (researcher_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'researcher@test.com', crypt('password123', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  (alice_id,      '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'alice@test.com',      crypt('password123', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  (bob_id,        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'bob@test.com',        crypt('password123', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  (carol_id,      '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'carol@test.com',      crypt('password123', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now())
ON CONFLICT (id) DO NOTHING;

-- auth.identities is required for email/password sign-in.
INSERT INTO auth.identities (
  id, user_id, provider_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
) VALUES
  (researcher_id, researcher_id, 'researcher@test.com', jsonb_build_object('sub', researcher_id::text, 'email', 'researcher@test.com'), 'email', now(), now(), now()),
  (alice_id,      alice_id,      'alice@test.com',      jsonb_build_object('sub', alice_id::text,      'email', 'alice@test.com'),      'email', now(), now(), now()),
  (bob_id,        bob_id,        'bob@test.com',        jsonb_build_object('sub', bob_id::text,        'email', 'bob@test.com'),        'email', now(), now(), now()),
  (carol_id,      carol_id,      'carol@test.com',      jsonb_build_object('sub', carol_id::text,      'email', 'carol@test.com'),      'email', now(), now(), now())
ON CONFLICT (id) DO NOTHING;

-- ── Profiles ──────────────────────────────────────────
INSERT INTO profiles (id, display_name, role, target_language) VALUES
  (researcher_id, 'Dr. Test', 'researcher',         NULL),
  (alice_id,      'Alice',    'group_a_participant', 'japanese'),
  (bob_id,        'Bob',      'group_a_participant', 'japanese'),
  (carol_id,      'Carol',    'group_b_participant', 'japanese')
ON CONFLICT (id) DO NOTHING;

-- ── Decks ─────────────────────────────────────────────
INSERT INTO decks (id, creator_id, title, short_description, long_description, target_language, tags, is_premade, is_uneditable, card_count) VALUES
  (deck_n5_id, researcher_id, 'JLPT N5 Vocabulary',
    'Basic Japanese vocabulary for beginners',
    'A curated set of 5 essential JLPT N5 words covering animals and nature. Includes flashcards, multiple-choice, and fill-in-the-blank question types.',
    'japanese', ARRAY['jlpt-n5', 'animals', 'nature'], true, true, 5),
  (deck_alice_id, alice_id, 'My Extra Vocab',
    'Alice''s personal vocabulary deck',
    'Extra words Alice has been studying alongside the N5 deck.',
    'japanese', ARRAY['nature'], false, false, 2),
  (deck_bob_id, bob_id, 'N5 Copy',
    'My copy of the N5 premade deck',
    'Bob''s personal copy of the N5 deck with source_card_id links for future updates.',
    'japanese', ARRAY['jlpt-n5', 'animals', 'nature'], false, false, 2)
ON CONFLICT (id) DO NOTHING;

-- ── Deck Cards ────────────────────────────────────────
-- Card       Deck      Type      Question type         sort
-- inu        N5        normal    flashcard              0
-- neko       N5        both      flashcard              1  (→ 2 notes)
-- tori       N5        normal    multiple_choice        2
-- sakana     N5        normal    fill_in_the_blanks     3
-- hana       N5        normal    flashcard              4
-- sora       alice     normal    flashcard              0
-- umi        alice     reversed  flashcard              1
-- bob_inu    bob       normal    flashcard              0  (copy of inu)
-- bob_neko   bob       both      flashcard              1  (copy of neko)
INSERT INTO deck_cards (id, deck_id, card_type, question_type, sort_order) VALUES
  (card_inu_id,    deck_n5_id,    'normal',   'flashcard',          0),
  (card_neko_id,   deck_n5_id,    'both',     'flashcard',          1),
  (card_tori_id,   deck_n5_id,    'normal',   'multiple_choice',    2),
  (card_sakana_id, deck_n5_id,    'normal',   'fill_in_the_blanks', 3),
  (card_hana_id,   deck_n5_id,    'normal',   'flashcard',          4),
  (card_sora_id,   deck_alice_id, 'normal',   'flashcard',          0),
  (card_umi_id,    deck_alice_id, 'reversed', 'flashcard',          1),
  (card_bob_inu_id,  deck_bob_id, 'normal',   'flashcard',          0),
  (card_bob_neko_id, deck_bob_id, 'both',     'flashcard',          1)
ON CONFLICT (id) DO NOTHING;

UPDATE deck_cards SET source_card_id = card_inu_id  WHERE id = card_bob_inu_id;
UPDATE deck_cards SET source_card_id = card_neko_id WHERE id = card_bob_neko_id;

-- ── Notes ─────────────────────────────────────────────
-- fill_in_the_blanks (sakana) has no note — content lives in fitb_segments.
-- match_madness cards have no notes either.
INSERT INTO notes (card_id, front_text, back_text, is_reverse, created_at) VALUES
  (card_inu_id,      '犬',   'dog, いぬ, inu',      false, now()),
  (card_neko_id,     '猫',   'cat, ねこ, neko',     false, now()),
  (card_neko_id,     'cat',  '猫, ねこ',            true,  now()),
  (card_tori_id,     '鳥',   'bird, とり, tori',    false, now()),
  (card_hana_id,     '花',   'flower, はな, hana',  false, now()),
  (card_sora_id,     '空',   'sky, そら, sora',     false, now()),
  (card_umi_id,      '海',   'sea, うみ, umi',      false, now()),
  (card_bob_inu_id,  '犬',   'dog, いぬ, inu',      false, now()),
  (card_bob_neko_id, '猫',   'cat, ねこ, neko',     false, now()),
  (card_bob_neko_id, 'cat',  '猫, ねこ',            true,  now())
ON CONFLICT (id) DO NOTHING;

-- ── Multiple Choice Options (tori — 鳥) ──────────────
INSERT INTO mc_options (card_id, option_text, is_correct, display_order) VALUES
  (card_tori_id, 'bird',   true,  0),
  (card_tori_id, 'fish',   false, 1),
  (card_tori_id, 'flower', false, 2),
  (card_tori_id, 'dog',    false, 3)
ON CONFLICT (id) DO NOTHING;

-- ── Fill-in-the-Blank Segments (sakana — 魚) ─────────
-- full_text: "魚 means fish in English"
-- blank covers "fish": blank_start=8, blank_end=12
INSERT INTO fitb_segments (card_id, full_text, blank_start, blank_end, correct_answer) VALUES
  (card_sakana_id, '魚 means fish in English', 8, 12, 'fish')
ON CONFLICT (id) DO NOTHING;

-- ── Streaks ───────────────────────────────────────────
INSERT INTO streaks (id, user_id, current_streak, longest_streak, last_activity_date) VALUES
  (streak_alice_id, alice_id, 5, 12, '2026-03-25'),
  (streak_bob_id,   bob_id,   0, 3,  '2026-03-20')
ON CONFLICT (id) DO NOTHING;

-- ── Research Users ────────────────────────────────────
INSERT INTO research_users (id, user_id, role, target_language) VALUES
  (ru_alice_id, alice_id, 'group_a_participant', 'japanese'),
  (ru_bob_id,   bob_id,   'group_a_participant', 'japanese'),
  (ru_carol_id, carol_id, 'group_b_participant', 'japanese')
ON CONFLICT (id) DO NOTHING;

-- ── Research Codes ────────────────────────────────────
INSERT INTO research_codes (id, code, target_role, unlocks, created_by) VALUES
  (gen_random_uuid(), 'VOCAB-A-001',   'group_a_participant', 'vocabulary_test_a',            researcher_id),
  (gen_random_uuid(), 'VOCAB-B-001',   'group_b_participant', 'vocabulary_test_a',            researcher_id),
  (gen_random_uuid(), 'EXP-SHORT-001', 'group_a_participant', 'experience_survey_short_term', researcher_id),
  (gen_random_uuid(), 'EXP-LONG-001',  'group_a_participant', 'experience_survey_long_term',  researcher_id),
  (gen_random_uuid(), 'PROF-001',      'group_a_participant', 'proficiency_screener',         researcher_id),
  (gen_random_uuid(), 'LANG-INT-001',  'group_a_participant', 'language_interest',            researcher_id),
  (gen_random_uuid(), 'PREVIEW-001',   'group_a_participant', 'preview_usefulness',           researcher_id),
  (gen_random_uuid(), 'FSRS-001',      'group_a_participant', 'fsrs_usefulness',              researcher_id),
  (gen_random_uuid(), 'UGC-A-001',     'group_a_participant', 'ugc_perception',               researcher_id),
  (gen_random_uuid(), 'UGC-B-001',     'group_b_participant', 'ugc_perception',               researcher_id),
  (gen_random_uuid(), 'SUS-001',       'group_a_participant', 'sus',                          researcher_id),
  (gen_random_uuid(), 'VOCAB-B-002',   'group_b_participant', 'vocabulary_test_b',            researcher_id)
ON CONFLICT (id) DO NOTHING;

-- ── Sample Drill Session (Alice completed one drill) ──
INSERT INTO drill_sessions (id, user_id, deck_id, previewed, total_questions, correct_count, started_at, completed_at) VALUES
  (drill_session_alice_id, alice_id, deck_n5_id, true, 5, 4, '2026-03-25 10:00:00+00', '2026-03-25 10:15:00+00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO drill_answers (session_id, card_id, user_answer, is_correct, self_rating, answered_at) VALUES
  (drill_session_alice_id, card_inu_id,    'dog',    true,  3,    '2026-03-25 10:02:00+00'),
  (drill_session_alice_id, card_neko_id,   'cat',    true,  4,    '2026-03-25 10:04:00+00'),
  (drill_session_alice_id, card_tori_id,   'bird',   true,  3,    '2026-03-25 10:06:00+00'),
  (drill_session_alice_id, card_sakana_id, 'whale',  false, NULL, '2026-03-25 10:08:00+00'),
  (drill_session_alice_id, card_hana_id,   'flower', true,  2,    '2026-03-25 10:10:00+00')
ON CONFLICT (id) DO NOTHING;

-- ── FSRS Cards (Alice's review schedule) ──────────────
INSERT INTO fsrs_cards (user_id, card_id, due, stability, difficulty, elapsed_days, scheduled_days, reps, lapses, state, last_review) VALUES
  (alice_id, card_inu_id,  '2026-03-26 10:00:00+00', 4.5, 5.0, 1, 3, 1, 0, 2, '2026-03-25 10:02:00+00'),
  (alice_id, card_neko_id, '2026-03-28 10:00:00+00', 8.0, 4.0, 1, 5, 1, 0, 2, '2026-03-25 10:04:00+00'),
  (alice_id, card_tori_id, '2026-03-26 10:00:00+00', 4.5, 5.0, 1, 3, 1, 0, 2, '2026-03-25 10:06:00+00'),
  (alice_id, card_hana_id, '2026-03-26 10:00:00+00', 2.0, 7.0, 1, 1, 1, 0, 1, '2026-03-25 10:10:00+00')
ON CONFLICT (user_id, card_id) DO NOTHING;

-- ── Review Logs ───────────────────────────────────────
INSERT INTO review_logs (user_id, card_id, rating, scheduled_days, elapsed_days, review, state) VALUES
  (alice_id, card_inu_id,  3, 3, 0, '2026-03-25 10:02:00+00', 0),
  (alice_id, card_neko_id, 4, 5, 0, '2026-03-25 10:04:00+00', 0),
  (alice_id, card_tori_id, 3, 3, 0, '2026-03-25 10:06:00+00', 0),
  (alice_id, card_hana_id, 2, 1, 0, '2026-03-25 10:10:00+00', 0);

END $$;
