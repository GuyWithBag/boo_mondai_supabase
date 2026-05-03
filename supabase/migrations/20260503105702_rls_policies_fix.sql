-- ══════════════════════════════════════════════════════
-- Fix: Multiple Permissive Policies
--
-- A FOR ALL policy implicitly includes SELECT. When a
-- separate FOR SELECT policy also exists on the same
-- table, Postgres must evaluate both for every SELECT
-- query — doubling the policy overhead.
--
-- Fix pattern:
--   • If the existing FOR SELECT already covers the FOR
--     ALL condition (or a superset of it), split FOR ALL
--     into explicit FOR INSERT / FOR UPDATE / FOR DELETE.
--   • If the two SELECT conditions are disjoint, merge
--     them into a single FOR SELECT policy with OR.
-- ══════════════════════════════════════════════════════

-- ── decks ─────────────────────────────────────────────
-- "anyone reads public"  FOR SELECT: is_public OR creator_id = uid
-- "users manage own"     FOR ALL:    creator_id = uid  ← redundant SELECT
-- The FOR SELECT already covers the creator via its OR branch.
DROP POLICY IF EXISTS "decks: users manage own"  ON decks;
DROP POLICY IF EXISTS "decks: creator manages"   ON decks;
DROP POLICY IF EXISTS "decks: creator updates"   ON decks;
DROP POLICY IF EXISTS "decks: creator deletes"   ON decks;
-- SELECT is covered by "decks: anyone reads public"; write operations only.
CREATE POLICY "decks: creator manages" ON decks
  FOR INSERT
  WITH CHECK ((select auth.uid()) = creator_id);
CREATE POLICY "decks: creator updates" ON decks
  FOR UPDATE
  USING     ((select auth.uid()) = creator_id)
  WITH CHECK ((select auth.uid()) = creator_id);
CREATE POLICY "decks: creator deletes" ON decks
  FOR DELETE
  USING ((select auth.uid()) = creator_id);

-- ── research_users ────────────────────────────────────
-- "researchers manage"  FOR ALL:    researcher check  ← SELECT conflicts
-- "users read own"      FOR SELECT: user_id = uid
-- Conditions are disjoint — merge into one SELECT with OR, then
-- keep researcher write operations in separate policies.
DROP POLICY IF EXISTS "research_users: researchers manage" ON research_users;
DROP POLICY IF EXISTS "research_users: users read own"     ON research_users;
DROP POLICY IF EXISTS "research_users: read"               ON research_users;
DROP POLICY IF EXISTS "research_users: researchers update" ON research_users;
DROP POLICY IF EXISTS "research_users: researchers delete" ON research_users;
CREATE POLICY "research_users: read" ON research_users
  FOR SELECT
  USING (
    (select auth.uid()) = user_id
    OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher')
  );
CREATE POLICY "research_users: researchers manage" ON research_users
  FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE POLICY "research_users: researchers update" ON research_users
  FOR UPDATE
  USING     (EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE POLICY "research_users: researchers delete" ON research_users
  FOR DELETE
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));

-- ── research_codes ────────────────────────────────────
-- "researchers manage"    FOR ALL:    researcher check  ← SELECT conflicts
-- "participants read own"  FOR SELECT: used_by = uid OR researcher check
-- "participants read own" already includes the researcher check via OR,
-- so it covers all SELECT cases. Split "researchers manage" into write-only.
DROP POLICY IF EXISTS "research_codes: researchers manage"  ON research_codes;
DROP POLICY IF EXISTS "research_codes: researchers manages" ON research_codes;
DROP POLICY IF EXISTS "research_codes: researchers updates" ON research_codes;
DROP POLICY IF EXISTS "research_codes: researchers deletes" ON research_codes;
-- SELECT is covered by "research_codes: participants read own"; write operations only.
CREATE POLICY "research_codes: researchers manages" ON research_codes
  FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE POLICY "research_codes: researchers updates" ON research_codes
  FOR UPDATE
  USING     (EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
CREATE POLICY "research_codes: researchers deletes" ON research_codes
  FOR DELETE
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher'));
