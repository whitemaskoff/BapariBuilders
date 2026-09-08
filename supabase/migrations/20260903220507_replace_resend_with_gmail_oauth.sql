-- Replace Resend API key with Google OAuth credentials for Gmail API
-- The send-notification-email edge function will use these to send emails via Gmail.

-- Remove old Resend key
DELETE FROM app_secrets WHERE key = 'RESEND_API_KEY';

-- Insert Google OAuth client credentials
INSERT INTO app_secrets (key, value) VALUES
  ('GMAIL_CLIENT_ID', '587039014466-6jerio5mn3srbogvsg5tl84704u8lt6l.apps.googleusercontent.com'),
  ('GMAIL_CLIENT_SECRET', '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'),
  ('GMAIL_REFRESH_TOKEN', ''),
  ('GMAIL_FROM_EMAIL', '')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;