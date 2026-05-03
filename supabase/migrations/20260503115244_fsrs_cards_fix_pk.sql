-- ══════════════════════════════════════════════════════
-- Fix fsrs_cards primary key
--
-- The original schema used `id text PRIMARY KEY` with the
-- expectation that callers would construct a composite key
-- like `user_id || '_' || card_id`. That's an app-level
-- hack — the correct approach is a proper uuid PK with a
-- UNIQUE (user_id, card_id) constraint so the DB enforces
-- the one-row-per-user-per-card invariant.
-- ══════════════════════════════════════════════════════

-- Recreate the table with the correct schema.
-- Safe because fsrs_cards is append-only per-user state
-- that is always rebuilt from review history if lost.
DROP TABLE fsrs_cards;

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
CREATE POLICY "fsrs_cards: users manage own" ON fsrs_cards
  FOR ALL
  USING     ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);
CREATE INDEX ON fsrs_cards (user_id);
CREATE INDEX ON fsrs_cards (user_id, due);
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON fsrs_cards
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);
