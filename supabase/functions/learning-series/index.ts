import { ownerContextEmail } from "../_shared/owner_context_email.ts";
import { createClient } from "@supabase/supabase-js";
import {
  confirmationEmail,
  emailFrame,
  escapeEmail,
  LEARNING_CONSENT_VERSION,
  learningEmail,
  type LearningStage,
} from "../_shared/learning_email_content.ts";
import { validBookingConfirmationDrainToken } from "../_shared/booking_confirmation_email.ts";

const cors = {
  "Access-Control-Allow-Origin": "https://workloop.uk",
  "Access-Control-Allow-Headers":
    "authorization,apikey,content-type,x-client-info",
  "Access-Control-Allow-Methods": "POST,GET,OPTIONS",
};
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (!["POST", "GET"].includes(req.method)) {
    return json(405, { error: "Method not allowed" });
  }
  const url = new URL(req.url);
  if (req.method === "GET") {
    const action = url.searchParams.get("action");
    const token = url.searchParams.get("token") ?? "";
    if (
      !["confirm", "unsubscribe", "stop-reminders"].includes(action ?? "") ||
      !uuid.test(token)
    ) return json(400, { error: "This email link is invalid" });
    const label = action === "confirm"
      ? "Confirm my welcome series"
      : action === "stop-reminders"
      ? "Stop booking reminders"
      : "Unsubscribe from Workloop tips and updates";
    // GET is deliberately read-only: email scanners cannot enroll or remove people.
    return new Response(
      emailFrame({
        heading: label,
        preview: label,
        body: `<p style="font-size:17px;line-height:1.6">${
          action === "confirm"
            ? "Confirm that you want the Workloop welcome pack and eight practical tips over four weeks."
            : action === "stop-reminders"
            ? "Stop reminder emails from this business. Your booking is not cancelled. Essential booking confirmations are unaffected."
            : "This stops Workloop tips, marketing and inactivity emails. Essential account and booking emails are unaffected."
        }</p><form method="post"><input type="hidden" name="action" value="${action}"><input type="hidden" name="token" value="${
          escapeEmail(token)
        }"><button style="padding:16px 20px;border:1px solid #443c32;border-radius:6px;background:#91b4c8;font-size:17px;color:#443c32" type="submit">${label}</button></form>`,
        footer: "Workloop · support@workloop.uk",
      }),
      {
        headers: {
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "no-store",
          "Referrer-Policy": "no-referrer",
          "Content-Security-Policy":
            "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'",
          "X-Content-Type-Options": "nosniff",
        },
      },
    );
  }
  const raw = await req.text();
  if (raw.length > 4096) return json(413, { error: "Request is too large" });
  let body: Record<string, unknown>;
  const isForm = req.headers.get("content-type")?.includes(
    "application/x-www-form-urlencoded",
  );
  try {
    body = isForm
      ? Object.fromEntries(new URLSearchParams(raw))
      : JSON.parse(raw);
  } catch {
    return json(400, { error: "Invalid request" });
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return json(400, { error: "Invalid request" });
  }
  const action = body.action ?? url.searchParams.get("action");
  if (
    action === "drain" &&
    !validBookingConfirmationDrainToken(
      Deno.env.get("BOOKING_CONFIRMATION_DRAIN_TOKEN") ?? "",
      req.headers.get("x-workloop-drain-token") ?? "",
    )
  ) return json(401, { error: "Unauthorized" });
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || key.length < 32) {
    return json(503, { error: "Email service is not configured" });
  }
  const client = createClient(supabaseUrl, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const result = async (name: string, args: Record<string, unknown>) => {
    const { data, error } = await client.rpc(name, args);
    if (error) throw new Error(`learning_rpc:${name}:${error.code}`);
    return data;
  };
  try {
    if (action === "subscribe") {
      if (typeof body.website === "string" && body.website.trim()) {
        return json(200, { ok: true });
      }
      const email = typeof body.email === "string"
        ? body.email.trim().toLowerCase()
        : "";
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
        return json(400, { error: "Enter a valid email address" });
      }
      if (
        body.consent !== true ||
        body.consent_version !== LEARNING_CONSENT_VERSION
      ) {
        return json(400, {
          error: "Please choose whether to receive the welcome series",
        });
      }
      if (!["exploring", "using"].includes(String(body.stage))) {
        return json(400, {
          error: "Choose whether you are exploring or using Workloop",
        });
      }
      const source = typeof body.source === "string" &&
          /^[a-z0-9_-]{1,80}$/.test(body.source)
        ? body.source
        : "welcome";
      await result("request_learning_series", {
        p_email: email,
        p_stage: body.stage,
        p_source: source,
        p_consent_version: LEARNING_CONSENT_VERSION,
      });
      return json(200, {
        ok: true,
        message:
          "If this address needs confirmation, an email will arrive shortly. Check your inbox and spam folder.",
      });
    }
    if (
      action === "confirm" || action === "unsubscribe" ||
      action === "stop-reminders"
    ) {
      const token = body.token ?? url.searchParams.get("token");
      if (typeof token !== "string" || !uuid.test(token)) {
        return json(400, { error: "This email link is invalid" });
      }
      if (action === "confirm") {
        const confirmed = await result("confirm_learning_series", {
          p_token: token,
        });
        if (!confirmed) {
          return json(400, {
            error:
              "This confirmation link has expired. Request the series again at workloop.uk/help/welcome.",
          });
        }
      } else {await result(
          action === "stop-reminders"
            ? "stop_booking_reminders"
            : "stop_learning_series",
          { p_token: token },
        );}
      if (isForm && body["List-Unsubscribe"] !== "One-Click") {
        return new Response(null, {
          status: 303,
          headers: {
            Location: action === "confirm"
              ? "https://workloop.uk/help/welcome?email=confirmed"
              : "https://workloop.uk/help/email-preferences?updated=1",
            "Cache-Control": "no-store",
          },
        });
      }
      return json(200, { ok: true });
    }
    if (action !== "drain") return json(400, { error: "Unknown action" });
    const apiKey = Deno.env.get("RESEND_API_KEY") ?? "";
    const from = Deno.env.get("LEARNING_EMAIL_FROM") ??
      Deno.env.get("WAITLIST_CONFIRMATION_EMAIL_FROM") ??
      Deno.env.get("BOOKING_CONFIRMATION_EMAIL_FROM") ?? "";
    if (apiKey.length < 16 || !from) {
      return json(503, { error: "Email provider is not configured" });
    }
    const claims = await result("claim_learning_emails", { p_limit: 5 });
    let sent = 0, failed = 0, skipped = 0;
    for (const claim of claims ?? []) {
      const allowed = await result("learning_email_still_allowed", {
        p_outbox_id: claim.outbox_id,
        p_lease_token: claim.lease_token,
      });
      if (!allowed) {
        skipped++;
        continue;
      }
      const endpoint = `${supabaseUrl}/functions/v1/learning-series`;
      const unsubscribeUrl =
        `${endpoint}?action=unsubscribe&token=${claim.unsubscribe_token}`;
      const context = claim.step >= 10
        ? await result("account_email_context", {
          p_contact_id: claim.contact_id,
          p_step: claim.step,
        })
        : {};
      const content = claim.step === -1
        ? confirmationEmail(
          `${endpoint}?action=confirm&token=${claim.confirm_token}`,
        )
        : claim.step >= 10
        ? ownerContextEmail({ step: claim.step, unsubscribeUrl, context })
        : learningEmail({
          step: claim.step,
          stage: claim.stage as LearningStage,
          unsubscribeUrl,
        });
      let providerId: string | null = null;
      let errorCode: string | null = null;
      try {
        const response = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
            "Idempotency-Key": `learning/${claim.outbox_id}`,
          },
          body: JSON.stringify({
            from,
            to: [claim.email],
            reply_to: "support@workloop.uk",
            subject: content.subject,
            text: content.text,
            html: content.html,
            ...(claim.step >= 0
              ? {
                headers: {
                  "List-Unsubscribe": `<${unsubscribeUrl}>`,
                  "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
                },
              }
              : {}),
          }),
          signal: AbortSignal.timeout(10000),
        });
        if (!response.ok) throw new Error(`provider_http_${response.status}`);
        const data = await response.json();
        if (typeof data.id !== "string") throw new Error("provider_missing_id");
        providerId = data.id;
        sent++;
      } catch (e) {
        errorCode = e instanceof Error
          ? e.message.slice(0, 160)
          : "provider_unavailable";
        failed++;
      }
      await result("finish_learning_email", {
        p_outbox_id: claim.outbox_id,
        p_lease_token: claim.lease_token,
        p_provider_message_id: providerId,
        p_error: errorCode,
      });
    }
    return json(failed ? 503 : 200, {
      ok: failed === 0,
      sent,
      failed,
      skipped,
    });
  } catch (e) {
    console.error(e instanceof Error ? e.message : "learning_failed");
    return json(500, {
      error: "Could not complete this request. Please try again later.",
    });
  }
});
