-- ══════════════════════════════════════════════════════
-- BooMondai — Seed / Mock Data (Schema V2)
-- Runs automatically on `supabase db reset`.
--
--   Email                  Password     Role
--   researcher@test.com    password123  researcher
--   alice@test.com         password123  group_a_participant
--   bob@test.com           password123  group_a_participant
--   carol@test.com         password123  group_b_participant
--
-- NOTE: profiles.id is a LOCAL UUID distinct from the auth UUID.
--       profiles.user_id holds the auth.users UUID.
-- ══════════════════════════════════════════════════════

DO $$
DECLARE
  -- ── Auth UUIDs (go into auth.users) ───────────────
  auth_researcher uuid := gen_random_uuid();
  auth_alice      uuid := gen_random_uuid();
  auth_bob        uuid := gen_random_uuid();
  auth_carol      uuid := gen_random_uuid();

  -- ── Profile local UUIDs (profiles.id) ─────────────
  p_researcher uuid := gen_random_uuid();
  p_alice      uuid := gen_random_uuid();
  p_bob        uuid := gen_random_uuid();
  p_carol      uuid := gen_random_uuid();

  -- ── Decks ──────────────────────────────────────────
  deck_n5    uuid := gen_random_uuid();  -- JLPT N5 (premade, researcher)
  deck_alice uuid := gen_random_uuid();  -- Alice's extra vocab
  deck_bob   uuid := gen_random_uuid();  -- Bob's copy of N5

  -- ── Card Templates ─────────────────────────────────
  -- N5 deck
  ct_inu    uuid := gen_random_uuid();  -- 犬  flashcard      (card_type=normal)
  ct_neko   uuid := gen_random_uuid();  -- 猫  flashcard      (card_type=both)
  ct_tori   uuid := gen_random_uuid();  -- 鳥  multiple_choice
  ct_sakana uuid := gen_random_uuid();  -- 魚  fill_in_the_blanks
  ct_hana   uuid := gen_random_uuid();  -- 花  flashcard      (card_type=normal)
  -- Alice's deck
  ct_sora uuid := gen_random_uuid();    -- 空  flashcard (card_type=normal)
  ct_umi  uuid := gen_random_uuid();    -- 海  flashcard (card_type=both)
  -- Bob's deck (copies)
  ct_bob_inu  uuid := gen_random_uuid();
  ct_bob_neko uuid := gen_random_uuid();

  -- ── Review Cards ───────────────────────────────────
  rc_inu        uuid := gen_random_uuid();
  rc_neko       uuid := gen_random_uuid();
  rc_neko_rev   uuid := gen_random_uuid();  -- reversed
  rc_tori       uuid := gen_random_uuid();
  rc_sakana     uuid := gen_random_uuid();
  rc_hana       uuid := gen_random_uuid();
  rc_sora       uuid := gen_random_uuid();
  rc_umi        uuid := gen_random_uuid();
  rc_umi_rev    uuid := gen_random_uuid();  -- reversed
  rc_bob_inu    uuid := gen_random_uuid();
  rc_bob_neko   uuid := gen_random_uuid();

  -- ── FSRS Cards (Alice's schedule) ──────────────────
  fsrs_inu    uuid := gen_random_uuid();
  fsrs_neko   uuid := gen_random_uuid();
  fsrs_tori   uuid := gen_random_uuid();
  fsrs_hana   uuid := gen_random_uuid();

  -- ── Streaks ────────────────────────────────────────
  streak_alice uuid := gen_random_uuid();
  streak_bob   uuid := gen_random_uuid();

  -- ── Research ───────────────────────────────────────
  rp_alice uuid := gen_random_uuid();
  rp_bob   uuid := gen_random_uuid();
  rp_carol uuid := gen_random_uuid();

  -- ── Sessions ───────────────────────────────────────
  drill_session_alice  uuid := gen_random_uuid();
  review_session_alice uuid := gen_random_uuid();

BEGIN

-- ── Auth Users ────────────────────────────────────────
-- GoTrue requires all varchar token/change columns to be '' not NULL.
-- phone must remain NULL (unique constraint).
INSERT INTO auth.users (
  id, instance_id, aud, role,
  email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current,
  phone_change, phone_change_token,
  reauthentication_token,
  created_at, updated_at
) VALUES
  (auth_researcher, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'researcher@test.com', crypt('password123', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{}',
   '', '', '', '', '', '', '', '',
   now(), now()),
  (auth_alice,      '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'alice@test.com',      crypt('password123', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{}',
   '', '', '', '', '', '', '', '',
   now(), now()),
  (auth_bob,        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'bob@test.com',        crypt('password123', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{}',
   '', '', '', '', '', '', '', '',
   now(), now()),
  (auth_carol,      '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'carol@test.com',      crypt('password123', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{}',
   '', '', '', '', '', '', '', '',
   now(), now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO auth.identities (
  id, user_id, provider_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
) VALUES
  (auth_researcher, auth_researcher, 'researcher@test.com',
   jsonb_build_object('sub', auth_researcher::text, 'email', 'researcher@test.com'),
   'email', now(), now(), now()),
  (auth_alice,      auth_alice,      'alice@test.com',
   jsonb_build_object('sub', auth_alice::text,      'email', 'alice@test.com'),
   'email', now(), now(), now()),
  (auth_bob,        auth_bob,        'bob@test.com',
   jsonb_build_object('sub', auth_bob::text,        'email', 'bob@test.com'),
   'email', now(), now(), now()),
  (auth_carol,      auth_carol,      'carol@test.com',
   jsonb_build_object('sub', auth_carol::text,      'email', 'carol@test.com'),
   'email', now(), now(), now())
ON CONFLICT (id) DO NOTHING;

-- ── Profiles ──────────────────────────────────────────
-- id = local app UUID (p_*), user_id = auth UUID (auth_*)
INSERT INTO profiles (id, user_id, username, role, is_anonymous, created_at, updated_at) VALUES
  (p_researcher, auth_researcher, 'Dr. Test', 'researcher',          false, now(), now()),
  (p_alice,      auth_alice,      'Alice',    'group_a_participant',  false, now(), now()),
  (p_bob,        auth_bob,        'Bob',      'group_a_participant',  false, now(), now()),
  (p_carol,      auth_carol,      'Carol',    'group_b_participant',  false, now(), now())
ON CONFLICT (id) DO NOTHING;

-- ── Decks ─────────────────────────────────────────────
INSERT INTO decks (
  id, user_id, title, short_description, long_description,
  target_language, tags, is_premade, is_public, is_published, is_editable,
  card_count, created_at, updated_at
) VALUES
  (deck_n5, p_researcher,
   'JLPT N5 Vocabulary',
   'Basic Japanese vocabulary for beginners.',
   'A curated set of 5 essential JLPT N5 words covering animals and nature. '
   'Used as the premade deck for the BooMondai study.',
   'japanese', ARRAY['jlpt-n5', 'animals', 'nature'],
   true, true, true, false,  -- premade, public, published, NOT editable
   5, now(), now()),

  (deck_alice, p_alice,
   'My Extra Vocab',
   'Alice''s personal vocabulary deck.',
   'Extra words Alice has been studying alongside the N5 premade deck.',
   'japanese', ARRAY['nature'],
   false, true, false, true,
   2, now(), now()),

  (deck_bob, p_bob,
   'N5 Copy',
   'My copy of the N5 premade deck.',
   'Bob''s personal copy of the N5 deck with source links preserved.',
   'japanese', ARRAY['jlpt-n5', 'animals', 'nature'],
   false, true, false, true,
   2, now(), now())
ON CONFLICT (id) DO NOTHING;

-- Set source_deck_id for bob's copy
UPDATE decks SET source_deck_id = deck_n5 WHERE id = deck_bob;

-- ── Card Templates ────────────────────────────────────
-- N5 deck — flashcard type (inu)
INSERT INTO card_templates (
  id, deck_id, type, sort_order, front_text, back_text, card_type, created_at, updated_at
) VALUES
  (ct_inu, deck_n5, 'flashcard', 0, '犬', 'dog, いぬ, inu', 'normal', now(), now())
ON CONFLICT (id) DO NOTHING;

-- N5 deck — flashcard type (neko, card_type=both → gets 2 review cards)
INSERT INTO card_templates (
  id, deck_id, type, sort_order, front_text, back_text, card_type, created_at, updated_at
) VALUES
  (ct_neko, deck_n5, 'flashcard', 1, '猫', 'cat, ねこ, neko', 'both', now(), now())
ON CONFLICT (id) DO NOTHING;

-- N5 deck — multiple_choice type (tori)
INSERT INTO card_templates (
  id, deck_id, type, sort_order, question_prompt, created_at, updated_at
) VALUES
  (ct_tori, deck_n5, 'multiple_choice', 2, 'What does 鳥 mean?', now(), now())
ON CONFLICT (id) DO NOTHING;

-- N5 deck — fill_in_the_blanks type (sakana)
INSERT INTO card_templates (
  id, deck_id, type, sort_order, created_at, updated_at
) VALUES
  (ct_sakana, deck_n5, 'fill_in_the_blanks', 3, now(), now())
ON CONFLICT (id) DO NOTHING;

-- N5 deck — flashcard type (hana)
INSERT INTO card_templates (
  id, deck_id, type, sort_order, front_text, back_text, card_type, created_at, updated_at
) VALUES
  (ct_hana, deck_n5, 'flashcard', 4, '花', 'flower, はな, hana', 'normal', now(), now())
ON CONFLICT (id) DO NOTHING;

-- Alice's deck — flashcard type (sora)
INSERT INTO card_templates (
  id, deck_id, type, sort_order, front_text, back_text, card_type, created_at, updated_at
) VALUES
  (ct_sora, deck_alice, 'flashcard', 0, '空', 'sky, そら, sora', 'normal', now(), now())
ON CONFLICT (id) DO NOTHING;

-- Alice's deck — flashcard type (umi, card_type=both)
INSERT INTO card_templates (
  id, deck_id, type, sort_order, front_text, back_text, card_type, created_at, updated_at
) VALUES
  (ct_umi, deck_alice, 'flashcard', 1, '海', 'sea, うみ, umi', 'both', now(), now())
ON CONFLICT (id) DO NOTHING;

-- Bob's deck — copies, source_template_id set
INSERT INTO card_templates (
  id, deck_id, type, sort_order, source_template_id,
  front_text, back_text, card_type, created_at, updated_at
) VALUES
  (ct_bob_inu,  deck_bob, 'flashcard', 0, ct_inu,
   '犬', 'dog, いぬ, inu',  'normal', now(), now()),
  (ct_bob_neko, deck_bob, 'flashcard', 1, ct_neko,
   '猫', 'cat, ねこ, neko', 'normal', now(), now())
ON CONFLICT (id) DO NOTHING;

-- ── Multiple Choice Options (tori — 鳥) ───────────────
INSERT INTO multiple_choice_options
  (template_id, option_text, is_correct, display_order)
VALUES
  (ct_tori, 'bird',   true,  0),
  (ct_tori, 'fish',   false, 1),
  (ct_tori, 'flower', false, 2),
  (ct_tori, 'dog',    false, 3);

-- ── Fill-in-the-Blank Segments (sakana — 魚) ──────────
-- '魚 means fish in English' — blank covers 'fish' at char positions 8–12
INSERT INTO fill_in_the_blank_segments
  (card_id, full_text, blank_start, blank_end, correct_answer)
VALUES
  (ct_sakana, '魚 means fish in English', 8, 12, 'fish');

-- ── Review Cards ──────────────────────────────────────
INSERT INTO review_cards (id, template_id, is_reversed, deck_id) VALUES
  -- N5 deck
  (rc_inu,      ct_inu,    false, deck_n5),
  (rc_neko,     ct_neko,   false, deck_n5),
  (rc_neko_rev, ct_neko,   true,  deck_n5),   -- reversed (card_type=both)
  (rc_tori,     ct_tori,   false, deck_n5),
  (rc_sakana,   ct_sakana, false, deck_n5),
  (rc_hana,     ct_hana,   false, deck_n5),
  -- Alice's deck
  (rc_sora,    ct_sora, false, deck_alice),
  (rc_umi,     ct_umi,  false, deck_alice),
  (rc_umi_rev, ct_umi,  true,  deck_alice),   -- reversed (card_type=both)
  -- Bob's deck
  (rc_bob_inu,  ct_bob_inu,  false, deck_bob),
  (rc_bob_neko, ct_bob_neko, false, deck_bob)
ON CONFLICT (id) DO NOTHING;

-- ── Streaks ───────────────────────────────────────────
INSERT INTO streaks (id, user_id, current_streak, longest_streak, last_activity_date, created_at, updated_at)
VALUES
  (streak_alice, p_alice, 5, 12, '2026-03-25', now(), now()),
  (streak_bob,   p_bob,   0,  3, '2026-03-20', now(), now())
ON CONFLICT (id) DO NOTHING;

-- ── Research Profiles ─────────────────────────────────
INSERT INTO research_profiles
  (id, user_id, first_name, last_name, age, role, goal, created_at)
VALUES
  (rp_alice, p_alice, 'Alice', 'Smith', 21, 'group_a_participant', 'japanese', now()),
  (rp_bob,   p_bob,   'Bob',   'Jones', 22, 'group_a_participant', 'japanese', now()),
  (rp_carol, p_carol, 'Carol', 'Lee',   20, 'group_b_participant', 'japanese', now())
ON CONFLICT (id) DO NOTHING;

-- ── Research Codes ────────────────────────────────────
INSERT INTO research_codes (code, target_role, unlocks, created_by) VALUES
  ('ONBOARD-A-001', 'group_a_participant', 'onboarding_group_a',           p_researcher),
  ('ONBOARD-B-001', 'group_b_participant', 'onboarding_group_b',           p_researcher),
  ('VOCAB-A-001',   'group_a_participant', 'vocabulary_test_a',            p_researcher),
  ('VOCAB-B-001',   'group_b_participant', 'vocabulary_test_a',            p_researcher),
  ('VOCAB-A-002',   'group_a_participant', 'vocabulary_test_b',            p_researcher),
  ('VOCAB-B-002',   'group_b_participant', 'vocabulary_test_b',            p_researcher),
  ('EXP-SHORT-001', 'group_a_participant', 'experience_survey_short_term', p_researcher),
  ('EXP-LONG-001',  'group_a_participant', 'experience_survey_long_term',  p_researcher),
  ('PREVIEW-001',   'group_a_participant', 'preview_usefulness',           p_researcher),
  ('FSRS-001',      'group_a_participant', 'fsrs_usefulness',              p_researcher),
  ('UGC-A-001',     'group_a_participant', 'ugc_perception',               p_researcher),
  ('UGC-B-001',     'group_b_participant', 'ugc_perception',               p_researcher),
  ('SUS-001',       'group_a_participant', 'sus',                          p_researcher)
ON CONFLICT (code) DO NOTHING;

-- ── Drill Session (Alice completed one drill on N5 deck) ──
INSERT INTO drill_sessions (
  id, user_id, deck_id, session_type,
  previewed, total_questions, correct_count,
  started_at, completed_at
) VALUES (
  drill_session_alice, p_alice, deck_n5, 'drill',
  true, 5, 4,
  '2026-03-25 10:00:00+00', '2026-03-25 10:15:00+00'
) ON CONFLICT (id) DO NOTHING;

-- ── Drill Answers ─────────────────────────────────────
-- type uses the study_rating enum
INSERT INTO drill_answers (session_id, card_id, user_answer, type, created_at) VALUES
  (drill_session_alice, ct_inu,    'dog',    'good',      '2026-03-25 10:02:00+00'),
  (drill_session_alice, ct_neko,   'cat',    'easy',      '2026-03-25 10:04:00+00'),
  (drill_session_alice, ct_tori,   'bird',   'good',      '2026-03-25 10:06:00+00'),
  (drill_session_alice, ct_sakana, 'whale',  'incorrect', '2026-03-25 10:08:00+00'),
  (drill_session_alice, ct_hana,   'flower', 'hard',      '2026-03-25 10:10:00+00');

-- ── FSRS Cards (Alice's review schedule after her drill) ─
-- state is a JSONB snapshot of the fsrs package Card object
INSERT INTO fsrs_cards (id, user_id, review_card_id, state, created_at, updated_at) VALUES
  (fsrs_inu, auth_alice, rc_inu,
   '{"due":"2026-03-26T10:00:00Z","stability":4.5,"difficulty":5.0,"elapsed_days":1,"scheduled_days":3,"reps":1,"lapses":0,"state":2,"last_review":"2026-03-25T10:02:00Z"}'::jsonb,
   now(), now()),
  (fsrs_neko, auth_alice, rc_neko,
   '{"due":"2026-03-28T10:00:00Z","stability":8.0,"difficulty":4.0,"elapsed_days":1,"scheduled_days":5,"reps":1,"lapses":0,"state":2,"last_review":"2026-03-25T10:04:00Z"}'::jsonb,
   now(), now()),
  (fsrs_tori, auth_alice, rc_tori,
   '{"due":"2026-03-26T10:00:00Z","stability":4.5,"difficulty":5.0,"elapsed_days":1,"scheduled_days":3,"reps":1,"lapses":0,"state":2,"last_review":"2026-03-25T10:06:00Z"}'::jsonb,
   now(), now()),
  (fsrs_hana, auth_alice, rc_hana,
   '{"due":"2026-03-26T10:00:00Z","stability":2.0,"difficulty":7.0,"elapsed_days":1,"scheduled_days":1,"reps":1,"lapses":0,"state":1,"last_review":"2026-03-25T10:10:00Z"}'::jsonb,
   now(), now())
ON CONFLICT (id) DO NOTHING;

-- ── Review Logs ───────────────────────────────────────
-- log is a JSONB snapshot of the fsrs package ReviewLog object
INSERT INTO review_logs (fsrs_card_id, log, created_at) VALUES
  (fsrs_inu,  '{"rating":3,"scheduled_days":3,"elapsed_days":0,"review":"2026-03-25T10:02:00Z","state":0}'::jsonb, '2026-03-25 10:02:00+00'),
  (fsrs_neko, '{"rating":4,"scheduled_days":5,"elapsed_days":0,"review":"2026-03-25T10:04:00Z","state":0}'::jsonb, '2026-03-25 10:04:00+00'),
  (fsrs_tori, '{"rating":3,"scheduled_days":3,"elapsed_days":0,"review":"2026-03-25T10:06:00Z","state":0}'::jsonb, '2026-03-25 10:06:00+00'),
  (fsrs_hana, '{"rating":2,"scheduled_days":1,"elapsed_days":0,"review":"2026-03-25T10:10:00Z","state":0}'::jsonb, '2026-03-25 10:10:00+00');

-- ── Review Session (Alice reviewed 4 cards) ───────────
INSERT INTO review_sessions (
  id, user_id, deck_id, session_type,
  total_cards, cards_reviewed, started_at, completed_at
) VALUES (
  review_session_alice, p_alice, deck_n5, 'review',
  4, 4,
  '2026-03-25 11:00:00+00', '2026-03-25 11:10:00+00'
) ON CONFLICT (id) DO NOTHING;

-- ── Survey Responses (Alice completed Day 1 surveys) ──
INSERT INTO survey_responses (user_id, survey_type, time_point, responses, submitted_at)
VALUES
  (p_alice, 'proficiency_screener', NULL,
   '{"item_1":2,"item_2":2,"item_3":1,"item_4":3,"item_5":2,"item_6":4,"proficiency_level":"beginner"}'::jsonb,
   '2026-03-20 09:00:00+00'),
  (p_alice, 'language_interest', NULL,
   '{"item_1":5,"item_2":4,"item_3":4,"item_4":3,"item_5":5}'::jsonb,
   '2026-03-20 09:05:00+00')
ON CONFLICT (user_id, survey_type, time_point) DO NOTHING;

END $$;
