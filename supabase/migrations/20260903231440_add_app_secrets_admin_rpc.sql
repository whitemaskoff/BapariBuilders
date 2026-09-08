/*
# Admin-only RPC functions for app_secrets table

1. New Functions
- `get_app_secrets()` — SECURITY DEFINER function that returns all rows from app_secrets.
  Only callable by authenticated users whose role is 'admin' (checked via is_admin()).
  This lets the admin frontend read all stored API keys and integration secrets
  without exposing the table through RLS policies to anon or non-admin users.
- `upsert_app_secret(p_key text, p_value text)` — SECURITY DEFINER function that
  inserts or updates a single row in app_secrets by primary key. Only callable by
  admin-role users. Returns the updated row.

2. Security
- Both functions are SECURITY DEFINER so they run with elevated privileges and
  bypass RLS on app_secrets (which has no policies — only the service role could
  access it before).
- Both functions check `is_admin()` at the start and raise an exception if the
  caller is not an admin, so non-admin authenticated users and anon users get
  nothing.
- EXECUTE is granted to `authenticated` only (not anon), so the browser must
  have a signed-in admin session to call them.

3. Important Notes
- The app_secrets table itself still has RLS enabled with NO policies, so direct
  SELECT/INSERT/UPDATE from the anon-key client still returns nothing.
- These functions are the ONLY way the frontend can read or write secrets, and
  they enforce admin-only access server-side.
- The send-notification-email edge function already reads app_secrets using the
  service role key, which bypasses RLS — that flow is unaffected.
*/

CREATE OR REPLACE FUNCTION get_app_secrets()
RETURNS TABLE (key text, value text, created_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Permission denied: admin access required';
  END IF;
  RETURN QUERY SELECT s.key, s.value, s.created_at FROM app_secrets s ORDER BY s.key;
END;
$$;

CREATE OR REPLACE FUNCTION upsert_app_secret(p_key text, p_value text)
RETURNS TABLE (key text, value text, created_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Permission denied: admin access required';
  END IF;
  IF p_key IS NULL OR btrim(p_key) = '' THEN
    RAISE EXCEPTION 'Secret key cannot be empty';
  END IF;
  IF p_value IS NULL OR btrim(p_value) = '' THEN
    RAISE EXCEPTION 'Secret value cannot be empty';
  END IF;
  INSERT INTO app_secrets (key, value)
  VALUES (p_key, p_value)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value
  RETURNING app_secrets.key, app_secrets.value, app_secrets.created_at INTO key, value, created_at;
  RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION get_app_secrets TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_app_secret TO authenticated;