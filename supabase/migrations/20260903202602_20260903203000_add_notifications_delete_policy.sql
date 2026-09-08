-- Add missing DELETE policy on notifications table
-- Without this, RLS blocks all notification deletions (clear all, individual delete)

CREATE POLICY "notifications_delete_own"
  ON notifications FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);
