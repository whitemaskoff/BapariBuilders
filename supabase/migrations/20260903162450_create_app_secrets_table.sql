/*
# Create app_secrets table for storing third-party API keys

1. New Tables
- `app_secrets`
  - `key` (text, primary key) — the secret name, e.g. 'RESEND_API_KEY'
  - `value` (text, not null) — the secret value
  - `created_at` (timestamptz)

2. Security
- RLS enabled with NO policies — only the service role (which bypasses RLS) can read/write.
- The anon and authenticated roles get zero rows, so the key is never exposed to the browser.

3. Important Notes
- This table stores the Resend API key for the send-notification-email edge function.
- The edge function reads it using SUPABASE_SERVICE_ROLE_KEY which bypasses RLS.
- Never expose this table's contents to the frontend.
*/

CREATE TABLE IF NOT EXISTS app_secrets (
  key text PRIMARY KEY,
  value text NOT NULL,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE app_secrets ENABLE ROW LEVEL SECURITY;

-- Insert the Resend API key
INSERT INTO app_secrets (key, value)
VALUES ('RESEND_API_KEY', 're_3KdhEwUS_8TgfVHw4GrMHBQ7Qwge1tjQt')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
