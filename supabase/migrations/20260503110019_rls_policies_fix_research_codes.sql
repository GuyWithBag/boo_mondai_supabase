-- ══════════════════════════════════════════════════════
-- Fix: Multiple Permissive UPDATE Policies — research_codes
--
-- After the previous migration split "researchers manage"
-- (FOR ALL) into explicit write policies, research_codes
-- ended up with two permissive UPDATE policies:
--
--   "participants redeem"   USING (used_by IS NULL)
--                           WITH CHECK (uid = used_by)
--
--   "researchers updates"   USING (is_researcher)
--                           WITH CHECK (is_researcher)
--
-- Postgres evaluates every permissive policy that could
-- apply to a role, so every UPDATE is checked twice.
-- Fix: merge them into a single UPDATE policy with OR.
--
-- Note: "decks" multiple-SELECT lint is already resolved
-- by 20260503105702_rls_policies_fix.sql — no action needed.
-- ══════════════════════════════════════════════════════

DROP POLICY IF EXISTS "research_codes: participants redeem"  ON research_codes;
DROP POLICY IF EXISTS "research_codes: researchers updates"  ON research_codes;
DROP POLICY IF EXISTS "research_codes: update"               ON research_codes;

CREATE POLICY "research_codes: update" ON research_codes
  FOR UPDATE
  USING (
    -- Participants may redeem codes that have not yet been claimed.
    used_by IS NULL
    -- Researchers may update any code regardless of state.
    OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher')
  )
  WITH CHECK (
    -- Participants must set used_by to their own uid.
    (select auth.uid()) = used_by
    -- Researchers may set any value.
    OR EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()) AND role = 'researcher')
  );
