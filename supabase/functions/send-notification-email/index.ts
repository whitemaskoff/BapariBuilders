import nodemailer from "npm:nodemailer@6.9.16";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

const GMAIL_USER = "sazzadzilanshifat102@gmail.com";

function buildEmailHtml(subject: string, body: string, actionUrl?: string, actionLabel?: string): string {
  const bodyHtml = (body || "").split('\n').map((line: string) => {
    if (line.startsWith('• ') || line.startsWith('- ')) {
      return `<tr><td style="padding: 6px 0 6px 24px; color: #5a6b62; font-size: 14px; line-height: 1.6;">${line}</td></tr>`;
    }
    if (line.trim() === '') return '<tr><td style="height: 12px;"></td></tr>';
    return `<tr><td style="padding: 6px 0; color: #5a6b62; font-size: 14px; line-height: 1.7;">${line}</td></tr>`;
  }).join('');

  return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="margin: 0; padding: 0; background-color: #f0f2f1;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f0f2f1; padding: 32px 16px;">
    <tr><td align="center">
      <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 12px rgba(38,55,44,0.08);">

        <tr>
          <td style="background: linear-gradient(135deg, #26372c 0%, #1a2820 100%); padding: 36px 40px 32px; text-align: center;">
            <h1 style="margin: 0; color: #ffffff; font-family: 'Helvetica Neue', Arial, sans-serif; font-size: 22px; font-weight: 700; letter-spacing: 0.06em;">
              BAPARI <span style="color: #df7a4c;">BUILDERS</span>
            </h1>
            <div style="width: 48px; height: 3px; background: #df7a4c; margin: 14px auto 0; border-radius: 2px;"></div>
          </td>
        </tr>

        <tr>
          <td style="padding: 36px 40px 0;">
            <h2 style="margin: 0; color: #26372c; font-family: 'Helvetica Neue', Arial, sans-serif; font-size: 20px; font-weight: 700; line-height: 1.3;">
              ${subject}
            </h2>
            <div style="width: 100%; height: 1px; background: #e8ece9; margin: 20px 0 0;"></div>
          </td>
        </tr>

        <tr>
          <td style="padding: 24px 40px 8px;">
            <table width="100%" cellpadding="0" cellspacing="0">
              ${bodyHtml}
            </table>
          </td>
        </tr>

        ${actionUrl ? `
        <tr>
          <td style="padding: 28px 40px 8px; text-align: center;">
            <a href="${actionUrl}" style="display: inline-block; background: linear-gradient(135deg, #df7a4c 0%, #cf6a3c 100%); color: #ffffff; padding: 16px 36px; text-decoration: none; font-family: 'Helvetica Neue', Arial, sans-serif; font-size: 14px; font-weight: 700; border-radius: 8px; letter-spacing: 0.03em; box-shadow: 0 4px 12px rgba(223,122,76,0.3);">
              ${actionLabel || "Open"}
            </a>
          </td>
        </tr>` : ''}

        <tr><td style="height: 28px;"></td></tr>

        <tr>
          <td style="padding: 0 40px;">
            <div style="width: 100%; height: 1px; background: #e8ece9;"></div>
          </td>
        </tr>

        <tr>
          <td style="padding: 24px 40px 36px; text-align: center;">
            <p style="margin: 0 0 6px; color: #8a9b92; font-family: 'Helvetica Neue', Arial, sans-serif; font-size: 12px; line-height: 1.6;">
              Bapari Builders &mdash; Building trust, one project at a time.
            </p>
            <p style="margin: 0; color: #b0c4b8; font-family: 'Helvetica Neue', Arial, sans-serif; font-size: 11px;">
              This email was sent as part of your order with Bapari Builders.
            </p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const { to_email, subject, body, action_url, action_label } = await req.json();

    if (!to_email || !subject) {
      return new Response(
        JSON.stringify({ error: "to_email and subject are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: passRow } = await admin.from("app_secrets").select("value").eq("key", "GMAIL_APP_PASSWORD").maybeSingle();
    const gmailPass = passRow?.value;

    if (!gmailPass) {
      return new Response(
        JSON.stringify({ error: "Gmail App Password not configured. Store it in app_secrets with key GMAIL_APP_PASSWORD." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: {
        user: GMAIL_USER,
        pass: gmailPass,
      },
    });

    const html = buildEmailHtml(subject, body, action_url, action_label);

    const info = await transporter.sendMail({
      from: `Bapari Builders <${GMAIL_USER}>`,
      to: to_email,
      subject,
      html,
      replyTo: GMAIL_USER,
    });

    return new Response(
      JSON.stringify({ success: true, id: info.messageId }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("send-notification-email error:", message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
