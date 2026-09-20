import { type BookingSmsConfig, type SmsRpcClient } from "./booking_sms.ts";

type SignatureValidator = (
  token: string,
  signature: string,
  url: string,
  params: Record<string, string>,
) => boolean;
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const json = (status: number, data: Record<string, unknown>) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

export async function handleBookingSmsWebhook(input: {
  request: Request;
  config: BookingSmsConfig;
  client: SmsRpcClient;
  validateSignature: SignatureValidator;
}) {
  const { request, config } = input;
  if (
    request.method !== "POST" ||
    !request.headers.get("content-type")?.startsWith(
      "application/x-www-form-urlencoded",
    )
  ) {
    return json(415, { error: "Unsupported webhook" });
  }
  const url = new URL(request.url);
  const action = url.searchParams.get("action");
  if (action !== "status" && action !== "inbound") {
    return json(400, { error: "Unknown webhook" });
  }
  const body = await request.text();
  if (body.length > 16384) return json(413, { error: "Webhook too large" });
  const fields = new URLSearchParams(body);
  const params: Record<string, string> = {};
  for (const [key, value] of fields) {
    if (Object.prototype.hasOwnProperty.call(params, key)) {
      return json(400, { error: "Duplicate webhook parameter" });
    }
    params[key] = value;
  }
  // Supabase proxies may rewrite the host/path seen by the Edge runtime.
  // Verify against the exact public base configured in Twilio, retaining the
  // raw query string and every decoded POST value (including spaces).
  const canonical = config.webhookBase + url.search;
  if (
    !input.validateSignature(
      config.authToken,
      request.headers.get("x-twilio-signature") ?? "",
      canonical,
      params,
    ) ||
    params.AccountSid !== config.accountSid ||
    (params.MessagingServiceSid &&
      params.MessagingServiceSid !== config.messagingServiceSid)
  ) {
    return json(401, { error: "Invalid webhook signature" });
  }
  const call = async (name: string, args: Record<string, unknown>) => {
    const { error } = await input.client.rpc(name, args);
    if (error) throw new Error("sms_webhook_write_failed");
  };
  if (action === "status") {
    const id = url.searchParams.get("outbox") ?? "";
    const dispatch = url.searchParams.get("dispatch") ?? "";
    if (
      !uuid.test(id) || !uuid.test(dispatch) ||
      !/^SM[0-9a-f]{32}$/i.test(params.MessageSid ?? "")
    ) {
      return json(400, { error: "Invalid delivery reference" });
    }
    await call("record_booking_sms_status", {
      p_outbox_id: id,
      p_dispatch_token: dispatch,
      p_provider_message_id: params.MessageSid,
      p_status: params.MessageStatus ?? "",
      p_error: /^[0-9]{3,8}$/.test(params.ErrorCode ?? "")
        ? `provider_${params.ErrorCode}`
        : null,
    });
  } else {
    if (
      params.MessagingServiceSid !== config.messagingServiceSid ||
      !/^\+[1-9][0-9]{7,14}$/.test(params.From ?? "")
    ) {
      return json(400, { error: "Invalid sender" });
    }
    // Advanced Opt-Out sends its own confirmation. Do not send a second text.
    if (params.OptOutType === "STOP" || params.OptOutType === "START") {
      await call("record_booking_sms_opt_out", {
        p_phone: params.From,
        p_stopped: params.OptOutType === "STOP",
      });
    }
  }
  return new Response("<Response/>", {
    headers: { "Content-Type": "text/xml", "Cache-Control": "no-store" },
  });
}
