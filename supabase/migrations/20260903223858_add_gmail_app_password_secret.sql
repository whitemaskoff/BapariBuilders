-- Store Gmail App Password for SMTP email sending
-- The send-notification-email edge function uses this with nodemailer to send via Gmail SMTP (free, no domain verification needed)
INSERT INTO app_secrets (key, value)
VALUES ('GMAIL_APP_PASSWORD', 'placeholder_replace_with_app_password')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;