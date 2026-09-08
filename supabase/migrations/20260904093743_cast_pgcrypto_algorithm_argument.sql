/*
# Resolve pgcrypto algorithm overload

1. Purpose
- Explicitly cast the password-hashing algorithm name to text so PostgreSQL selects the installed `gen_salt(text)` function.
- This completes the fix for creating sellers and administrators from the team controller.

2. Modified functions
- `create_staff_account`: explicit text cast for `gen_salt`.
- `update_staff_account`: explicit text cast for `gen_salt`.

3. Tables and columns
- No tables or columns are created or modified.

4. Security
- Existing admin authorization, password hashing, and role validation remain unchanged.
- No RLS policies or privileges are changed.

5. Important notes
- This is non-destructive and only changes function overload resolution.
*/

CREATE OR REPLACE FUNCTION public.create_staff_account(
  p_email text,
  p_password text,
  p_role text DEFAULT 'seller',
  p_display_name text DEFAULT NULL,
  p_phone text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, auth, extensions
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  IF get_user_role() != 'admin' THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF p_role NOT IN ('admin', 'seller') THEN
    RAISE EXCEPTION 'Invalid role';
  END IF;

  IF p_password IS NULL OR length(p_password) < 6 THEN
    RAISE EXCEPTION 'Password must be at least 6 characters';
  END IF;

  INSERT INTO auth.users (
    id, email, encrypted_password, role, aud,
    email_confirmed_at, created_at, updated_at,
    raw_user_meta_data
  )
  VALUES (
    gen_random_uuid(),
    lower(p_email),
    extensions.crypt(p_password, extensions.gen_salt('bf'::text)),
    'authenticated',
    'authenticated',
    now(),
    now(),
    now(),
    jsonb_build_object('display_name', p_display_name, 'phone', p_phone)
  )
  RETURNING id INTO v_user_id;

  UPDATE profiles
  SET role = p_role, display_name = COALESCE(p_display_name, ''), phone = COALESCE(p_phone, '')
  WHERE id = v_user_id;

  RETURN v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_staff_account(
  p_user_id uuid,
  p_email text DEFAULT NULL,
  p_role text DEFAULT NULL,
  p_display_name text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_password text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, auth, extensions
AS $$
BEGIN
  IF get_user_role() != 'admin' THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF p_role IS NOT NULL AND p_role NOT IN ('admin', 'seller') THEN
    RAISE EXCEPTION 'Invalid role';
  END IF;

  IF p_email IS NOT NULL OR p_password IS NOT NULL THEN
    UPDATE auth.users SET
      email = COALESCE(lower(p_email), email),
      encrypted_password = CASE WHEN p_password IS NOT NULL AND length(p_password) >= 6
        THEN extensions.crypt(p_password, extensions.gen_salt('bf'::text))
        ELSE encrypted_password END,
      updated_at = now()
    WHERE id = p_user_id;
  END IF;

  UPDATE profiles SET
    email = COALESCE(lower(p_email), email),
    role = COALESCE(p_role, role),
    display_name = COALESCE(p_display_name, display_name),
    phone = COALESCE(p_phone, phone)
  WHERE id = p_user_id;
END;
$$;