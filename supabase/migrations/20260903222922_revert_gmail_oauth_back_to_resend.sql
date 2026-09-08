-- Revert Gmail OAuth credentials back to Resend API key
DELETE FROM app_secrets WHERE key IN ('GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET', 'GMAIL_REFRESH_TOKEN', 'GMAIL_FROM_EMAIL');

-- Insert the new Resend API key
INSERT INTO app_secrets (key, value)
VALUES ('RESEND_API_KEY', 're_F1wpvvVE_BSc8NmiZ4K6VpNFmX4i4XJjU')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;