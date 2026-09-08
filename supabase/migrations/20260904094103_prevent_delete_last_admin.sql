/*
# Prevent deleting the last admin account

1. Purpose
- Stop an administrator from accidentally deleting the final admin account, which would lock everyone out of admin-only features.
- If the targeted account is an admin and no other admin profiles exist, the delete is rejected with a clear error.

2. Modified functions
- `delete_staff_account`: adds a last-admin guard before performing the delete.

3. Tables and columns
- No tables or columns are created or modified.

4. Security
- Existing admin-only authorization and self-delete prevention are preserved.
- No RLS policies or privileges are changed.

5. Important notes
- Non-destructive: only changes the delete function's logic.
- The guard counts profiles with role 'admin' excluding the account being deleted; if that count is zero, the delete is blocked.
*/

CREATE OR REPLACE FUNCTION public.delete_staff_account(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, auth, extensions
AS $$
DECLARE
  v_target_role text;
  v_admin_count int;
BEGIN
  IF get_user_role() != 'admin' THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot delete your own account';
  END IF;

  SELECT role INTO v_target_role FROM profiles WHERE id = p_user_id;

  IF v_target_role = 'admin' THEN
    SELECT count(*) INTO v_admin_count
    FROM profiles
    WHERE role = 'admin' AND id != p_user_id;

    IF v_admin_count = 0 THEN
      RAISE EXCEPTION 'Cannot delete the last admin account. Promote another member to admin first.';
    END IF;
  END IF;

  DELETE FROM auth.users WHERE id = p_user_id;
END;
$$;