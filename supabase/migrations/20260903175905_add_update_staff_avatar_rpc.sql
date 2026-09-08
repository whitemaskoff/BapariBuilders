/*
# Add update_staff_avatar RPC function

1. New Functions
- `update_staff_avatar(p_user_id uuid, p_avatar_url text)`: Allows an admin to
  update any staff member's avatar_url in the profiles table. This is a
  SECURITY DEFINER function so the admin can update other users' profiles
  without needing direct UPDATE access to the profiles table.

2. Security
- SECURITY DEFINER, callable by authenticated users only.
- Internally checks that the caller is an admin before allowing the update.
- Search path set to public for safety.
*/

CREATE OR REPLACE FUNCTION update_staff_avatar(p_user_id uuid, p_avatar_url text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin') THEN
    RAISE EXCEPTION 'Only admins can update other staff avatars';
  END IF;
  UPDATE profiles SET avatar_url = p_avatar_url WHERE id = p_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_staff_avatar(uuid, text) TO authenticated;
