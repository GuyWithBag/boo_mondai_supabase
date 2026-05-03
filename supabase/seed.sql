-- ══════════════════════════════════════════════════════
-- BooMondai — Seed / Mock Data
-- Run this in the Supabase SQL Editor AFTER schema.sql
-- ══════════════════════════════════════════════════════
--
-- STEP 1 — Create the 4 test users via the Auth dashboard
--          (Authentication → Users → Add user → Create new user)
--          or via the Auth API. Use these credentials:
--
--   Email                  Password     Role (set after seed)
--   researcher@test.com    password123  researcher
--   alice@test.com         password123  group_a_participant
--   bob@test.com           password123  group_a_participant
--   carol@test.com         password123  group_b_participant
--
-- STEP 2 — Copy the UUIDs Supabase assigned to each user from
--          Authentication → Users, then replace the placeholder
--          UUIDs below before running this file.
--
--   Placeholder → replace with your real UUID
--   RESEARCHER_UUID  → UUID for researcher@test.com
--   ALICE_UUID       → UUID for alice@test.com
--   BOB_UUID         → UUID for bob@test.com
--   CAROL_UUID       → UUID for carol@test.com
--
-- ══════════════════════════════════════════════════════

-- Change these 4 lines to match your real auth UUIDs:
DO $$
DECLARE
  researcher_id uuid := 'edc521e5-76cf-4879-bdc6-126c84f63e05';
  alice_id      uuid := '1f2d72d2-74ce-418d-9a7e-80d6f00ebf7c';
  bob_id        uuid := 'f1f55d61-11a6-4834-8a29-d4eb23873b3b';
  carol_id      uuid := '26f90ecf-33d7-471b-a86c-29576010ffb2';
BEGIN

-- ── Profiles ──────────────────────────────────────────
INSERT INTO profiles (id, email, display_name, role, target_language) VALUES
  (researcher_id, 'researcher@test.com', 'Dr. Test', 'researcher',          NULL),
  (alice_id,      'alice@test.com',      'Alice',    'group_a_participant',  'japanese'),
  (bob_id,        'bob@test.com',        'Bob',      'group_a_participant',  'japanese'),
  (carol_id,      'carol@test.com',      'Carol',    'group_b_participant',  'japanese')
ON CONFLICT (id) DO NOTHING;

-- ── Decks ──────────────────────────────────────────────
INSERT INTO decks (id, creator_id, title, short_description, long_description, target_language, tags, is_premade, is_uneditable, card_count) VALUES
  ('00000000-0000-0000-0000-000000000010', researcher_id, 'JLPT N5 Vocabulary',
    'Basic Japanese vocabulary for beginners',
    'A curated set of 5 essential JLPT N5 words covering animals and nature. Includes flashcards, multiple-choice, and fill-in-the-blank question types.',
    'japanese', ARRAY['jlpt-n5', 'animals', 'nature'], true, true, 5),
  ('00000000-0000-0000-0000-000000000011', alice_id, 'My Extra Vocab',
    'Alice''s personal vocabulary deck',
    'Extra words Alice has been studying alongside the N5 deck.',
    'japanese', ARRAY['nature'], false, false, 2),
  -- Bob's deck: a private copy of the N5 premade deck (source_card_id set on cards below)
  ('00000000-0000-0000-0000-000000000012', bob_id, 'N5 Copy',
    'My copy of the N5 premade deck',
    'Bob''s personal copy of the N5 deck with source_card_id links for future updates.',
    'japanese', ARRAY['jlpt-n5', 'animals', 'nature'], false, false, 2)
ON CONFLICT (id) DO NOTHING;

-- ── Deck Cards ─────────────────────────────────────────
-- Columns: id, deck_id, card_type, question_type, sort_order
--
-- Card 20 — 犬 (dog)        : normal   flashcard        → 1 Note
-- Card 21 — 猫 (cat)        : both     flashcard        → 2 Notes (fwd + reversed)
-- Card 22 — 鳥 (bird)       : normal   multiple_choice  → 1 Note + 4 mc_options
-- Card 23 — 魚 (fish)       : normal   fill_in_the_blanks → 1 fitb_segment
-- Card 24 — 花 (flower)     : normal   flashcard        → 1 Note
-- Card 25 — 空 (sky)        : normal   flashcard        → 1 Note
-- Card 26 — 海 (sea)        : reversed flashcard        → 1 Note
INSERT INTO deck_cards (id, deck_id, card_type, question_type, sort_order) VALUES
  ('00000000-0000-0000-0000-000000000020', '00000000-0000-0000-0000-000000000010', 'normal',   'flashcard',          0),
  ('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000010', 'both',     'flashcard',          1),
  ('00000000-0000-0000-0000-000000000022', '00000000-0000-0000-0000-000000000010', 'normal',   'multiple_choice',    2),
  ('00000000-0000-0000-0000-000000000023', '00000000-0000-0000-0000-000000000010', 'normal',   'fill_in_the_blanks', 3),
  ('00000000-0000-0000-0000-000000000024', '00000000-0000-0000-0000-000000000010', 'normal',   'flashcard',          4),
  ('00000000-0000-0000-0000-000000000025', '00000000-0000-0000-0000-000000000011', 'normal',   'flashcard',          0),
  ('00000000-0000-0000-0000-000000000026', '00000000-0000-0000-0000-000000000011', 'reversed', 'flashcard',          1),
  -- Bob's copied cards (source_card_id → original cards 20 and 21 from the N5 deck)
  ('00000000-0000-0000-0000-000000000027', '00000000-0000-0000-0000-000000000012', 'normal',   'flashcard',          0),
  ('00000000-0000-0000-0000-000000000028', '00000000-0000-0000-0000-000000000012', 'both',     'flashcard',          1)
ON CONFLICT (id) DO NOTHING;

-- Set source_card_id for Bob's copied cards (must be done in a second statement
-- because the rows need to exist first when there is a self-referencing FK)
UPDATE deck_cards SET source_card_id = '00000000-0000-0000-0000-000000000020' WHERE id = '00000000-0000-0000-0000-000000000027';
UPDATE deck_cards SET source_card_id = '00000000-0000-0000-0000-000000000021' WHERE id = '00000000-0000-0000-0000-000000000028';

-- ── Notes ──────────────────────────────────────────────
-- Each read_and_select / multiple_choice card needs at least one Note.
-- CardType.both (card 21) gets a second reversed Note.
-- fill_in_the_blanks (card 23) uses fitb_segments instead — no Note.
INSERT INTO notes (id, card_id, front_text, back_text, is_reverse, created_at) VALUES
  -- Card 20 — 犬: front=kanji, back=accepted answers
  ('00000000-0000-0000-0000-000000000120', '00000000-0000-0000-0000-000000000020', '犬',   'dog, いぬ, inu',       false, now()),
  -- Card 21 — 猫 (both): forward + reversed
  ('00000000-0000-0000-0000-000000000121', '00000000-0000-0000-0000-000000000021', '猫',   'cat, ねこ, neko',      false, now()),
  ('00000000-0000-0000-0000-000000000122', '00000000-0000-0000-0000-000000000021', 'cat',  '猫, ねこ',             true,  now()),
  -- Card 22 — 鳥: note is the question prompt shown above the MC options
  ('00000000-0000-0000-0000-000000000123', '00000000-0000-0000-0000-000000000022', '鳥',   'bird, とり, tori',     false, now()),
  -- Card 24 — 花
  ('00000000-0000-0000-0000-000000000124', '00000000-0000-0000-0000-000000000024', '花',   'flower, はな, hana',   false, now()),
  -- Card 25 — 空
  ('00000000-0000-0000-0000-000000000125', '00000000-0000-0000-0000-000000000025', '空',   'sky, そら, sora',      false, now()),
  -- Card 26 — 海 (reversible: learner can flip direction in settings)
  ('00000000-0000-0000-0000-000000000126', '00000000-0000-0000-0000-000000000026', '海',   'sea, うみ, umi',       false, now()),
  -- Bob's copied cards (identical content to the originals at copy time)
  ('00000000-0000-0000-0000-000000000127', '00000000-0000-0000-0000-000000000027', '犬',   'dog, いぬ, inu',       false, now()),
  ('00000000-0000-0000-0000-000000000128', '00000000-0000-0000-0000-000000000028', '猫',   'cat, ねこ, neko',      false, now()),
  ('00000000-0000-0000-0000-000000000129', '00000000-0000-0000-0000-000000000028', 'cat',  '猫, ねこ',             true,  now())
ON CONFLICT (id) DO NOTHING;

-- ── Multiple Choice Options (card 22 — 鳥) ─────────────
-- 4 options: one correct (bird), three distractors from other deck cards
INSERT INTO mc_options (id, card_id, option_text, is_correct, display_order) VALUES
  ('00000000-0000-0000-0000-000000000130', '00000000-0000-0000-0000-000000000022', 'bird',   true,  0),
  ('00000000-0000-0000-0000-000000000131', '00000000-0000-0000-0000-000000000022', 'fish',   false, 1),
  ('00000000-0000-0000-0000-000000000132', '00000000-0000-0000-0000-000000000022', 'flower', false, 2),
  ('00000000-0000-0000-0000-000000000133', '00000000-0000-0000-0000-000000000022', 'dog',    false, 3)
ON CONFLICT (id) DO NOTHING;

-- ── Fill-in-the-Blank Segments (card 23 — 魚) ──────────
-- full_text: "魚 means fish in English"
-- Character positions (0-indexed):
--   0=魚, 1=' ', 2=m, 3=e, 4=a, 5=n, 6=s, 7=' ', 8=f, 9=i, 10=s, 11=h, 12=' ', ...
-- blank covers "fish" → blank_start=8, blank_end=12 (exclusive)
INSERT INTO fitb_segments (id, card_id, full_text, blank_start, blank_end, correct_answer) VALUES
  ('00000000-0000-0000-0000-000000000140', '00000000-0000-0000-0000-000000000023', '魚 means fish in English', 8, 12, 'fish')
ON CONFLICT (id) DO NOTHING;

-- ── Streaks ────────────────────────────────────────────
INSERT INTO streaks (id, user_id, current_streak, longest_streak, last_activity_date) VALUES
  ('00000000-0000-0000-0000-000000000030', alice_id, 5, 12, '2026-03-25'),
  ('00000000-0000-0000-0000-000000000031', bob_id,   0, 3,  '2026-03-20')
ON CONFLICT (id) DO NOTHING;

-- ── Research Users ─────────────────────────────────────
INSERT INTO research_users (id, user_id, role, target_language) VALUES
  ('00000000-0000-0000-0000-000000000050', alice_id, 'group_a_participant', 'japanese'),
  ('00000000-0000-0000-0000-000000000051', bob_id,   'group_a_participant', 'japanese'),
  ('00000000-0000-0000-0000-000000000052', carol_id, 'group_b_participant', 'japanese')
ON CONFLICT (id) DO NOTHING;

-- ── Research Codes ─────────────────────────────────────
INSERT INTO research_codes (id, code, target_role, unlocks, created_by) VALUES
  ('00000000-0000-0000-0000-000000000060', 'VOCAB-A-001',   'group_a_participant', 'vocabulary_test_a',            researcher_id),
  ('00000000-0000-0000-0000-000000000061', 'VOCAB-B-001',   'group_b_participant', 'vocabulary_test_a',            researcher_id),
  ('00000000-0000-0000-0000-000000000062', 'EXP-SHORT-001', 'group_a_participant', 'experience_survey_short_term', researcher_id),
  ('00000000-0000-0000-0000-000000000063', 'EXP-LONG-001',  'group_a_participant', 'experience_survey_long_term',  researcher_id),
  ('00000000-0000-0000-0000-000000000064', 'PROF-001',      'group_a_participant', 'proficiency_screener',         researcher_id),
  ('00000000-0000-0000-0000-000000000065', 'LANG-INT-001',  'group_a_participant', 'language_interest',            researcher_id),
  ('00000000-0000-0000-0000-000000000066', 'PREVIEW-001',   'group_a_participant', 'preview_usefulness',           researcher_id),
  ('00000000-0000-0000-0000-000000000067', 'FSRS-001',      'group_a_participant', 'fsrs_usefulness',              researcher_id),
  ('00000000-0000-0000-0000-000000000068', 'UGC-A-001',     'group_a_participant', 'ugc_perception',               researcher_id),
  ('00000000-0000-0000-0000-000000000069', 'UGC-B-001',     'group_b_participant', 'ugc_perception',               researcher_id),
  ('00000000-0000-0000-0000-00000000006a', 'SUS-001',       'group_a_participant', 'sus',                          researcher_id),
  ('00000000-0000-0000-0000-00000000006b', 'VOCAB-B-002',   'group_b_participant', 'vocabulary_test_b',            researcher_id)
ON CONFLICT (id) DO NOTHING;

-- ── Sample Quiz Session (Alice completed one quiz) ──────
INSERT INTO quiz_sessions (id, user_id, deck_id, previewed, total_questions, correct_count, started_at, completed_at) VALUES
  ('00000000-0000-0000-0000-000000000040', alice_id, '00000000-0000-0000-0000-000000000010', true, 5, 4, '2026-03-25 10:00:00+00', '2026-03-25 10:15:00+00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO quiz_answers (id, session_id, card_id, user_answer, is_correct, self_rating, answered_at) VALUES
  ('00000000-0000-0000-0000-000000000070', '00000000-0000-0000-0000-000000000040', '00000000-0000-0000-0000-000000000020', 'dog',    true,  3,    '2026-03-25 10:02:00+00'),
  ('00000000-0000-0000-0000-000000000071', '00000000-0000-0000-0000-000000000040', '00000000-0000-0000-0000-000000000021', 'cat',    true,  4,    '2026-03-25 10:04:00+00'),
  ('00000000-0000-0000-0000-000000000072', '00000000-0000-0000-0000-000000000040', '00000000-0000-0000-0000-000000000022', 'bird',   true,  3,    '2026-03-25 10:06:00+00'),
  ('00000000-0000-0000-0000-000000000073', '00000000-0000-0000-0000-000000000040', '00000000-0000-0000-0000-000000000023', 'whale',  false, NULL, '2026-03-25 10:08:00+00'),
  ('00000000-0000-0000-0000-000000000074', '00000000-0000-0000-0000-000000000040', '00000000-0000-0000-0000-000000000024', 'flower', true,  2,    '2026-03-25 10:10:00+00')
ON CONFLICT (id) DO NOTHING;

-- ── Sample FSRS Cards (Alice's review schedule) ─────────
INSERT INTO fsrs_cards (id, user_id, card_id, due, stability, difficulty, elapsed_days, scheduled_days, reps, lapses, state, last_review) VALUES
  (alice_id::text || '_00000000-0000-0000-0000-000000000020', alice_id, '00000000-0000-0000-0000-000000000020', '2026-03-26 10:00:00+00', 4.5, 5.0, 1, 3, 1, 0, 2, '2026-03-25 10:02:00+00'),
  (alice_id::text || '_00000000-0000-0000-0000-000000000021', alice_id, '00000000-0000-0000-0000-000000000021', '2026-03-28 10:00:00+00', 8.0, 4.0, 1, 5, 1, 0, 2, '2026-03-25 10:04:00+00'),
  (alice_id::text || '_00000000-0000-0000-0000-000000000022', alice_id, '00000000-0000-0000-0000-000000000022', '2026-03-26 10:00:00+00', 4.5, 5.0, 1, 3, 1, 0, 2, '2026-03-25 10:06:00+00'),
  (alice_id::text || '_00000000-0000-0000-0000-000000000024', alice_id, '00000000-0000-0000-0000-000000000024', '2026-03-26 10:00:00+00', 2.0, 7.0, 1, 1, 1, 0, 1, '2026-03-25 10:10:00+00')
ON CONFLICT (id) DO NOTHING;

-- ── Sample Review Logs ──────────────────────────────────
INSERT INTO review_logs (id, user_id, card_id, rating, scheduled_days, elapsed_days, review, state) VALUES
  ('00000000-0000-0000-0000-000000000080', alice_id, '00000000-0000-0000-0000-000000000020', 3, 3, 0, '2026-03-25 10:02:00+00', 0),
  ('00000000-0000-0000-0000-000000000081', alice_id, '00000000-0000-0000-0000-000000000021', 4, 5, 0, '2026-03-25 10:04:00+00', 0),
  ('00000000-0000-0000-0000-000000000082', alice_id, '00000000-0000-0000-0000-000000000022', 3, 3, 0, '2026-03-25 10:06:00+00', 0),
  ('00000000-0000-0000-0000-000000000083', alice_id, '00000000-0000-0000-0000-000000000024', 2, 1, 0, '2026-03-25 10:10:00+00', 0)
ON CONFLICT (id) DO NOTHING;

END $$;
