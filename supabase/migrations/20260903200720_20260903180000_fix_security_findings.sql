-- ============================================================
-- 1. Fix mutable search_path on trigger functions
-- ============================================================

CREATE OR REPLACE FUNCTION update_orders_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION update_deals_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION update_site_content_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ============================================================
-- 2. Revoke EXECUTE from anon on staff-only SECURITY DEFINER functions
--    These functions check get_user_role() internally, but anon should
--    not even be able to invoke them.
-- ============================================================

REVOKE EXECUTE ON FUNCTION accept_order(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION pick_up_order(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION reject_order(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION set_deal_terms(uuid, numeric, numeric) FROM anon;
REVOKE EXECUTE ON FUNCTION record_payment(uuid, numeric, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION propose_modification(uuid, jsonb, numeric) FROM anon;
REVOKE EXECUTE ON FUNCTION create_staff_account(text, text, text, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION update_staff_account(uuid, text, text, text, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION delete_staff_account(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION update_staff_avatar(uuid, text) FROM anon;

-- handle_new_user is a trigger function, not callable via RPC — revoke from both
REVOKE EXECUTE ON FUNCTION handle_new_user() FROM anon;
REVOKE EXECUTE ON FUNCTION handle_new_user() FROM authenticated;

-- get_user_role and is_admin are helper functions used internally by RLS policies
-- and by the frontend to determine role. They are safe for authenticated users
-- (they only return the caller's own role), but anon doesn't need them.
REVOKE EXECUTE ON FUNCTION get_user_role() FROM anon;
REVOKE EXECUTE ON FUNCTION is_admin() FROM anon;

-- ============================================================
-- 3. Add explicit deny-all RLS policy on app_secrets
--    RLS is enabled with no policies, which already blocks anon/authenticated.
--    Adding an explicit policy makes the intent clear to the advisor.
-- ============================================================

DROP POLICY IF EXISTS "app_secrets_deny_all" ON app_secrets;
CREATE POLICY "app_secrets_deny_all"
  ON app_secrets FOR ALL
  TO anon, authenticated
  USING (false)
  WITH CHECK (false);
