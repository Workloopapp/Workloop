import { escapeEmail } from "./learning_email_content.ts";
export function businessContactEmail(payload: Record<string, unknown>) {
  const c = payload.business_contact as Record<string, unknown> | undefined;
  const items: Array<{ label: string; value: string; url: string }> = [];
  const email = String(c?.email ?? "").trim();
  if (/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(email) && email.length <= 254) {
    items.push({
      label: "Email",
      value: email,
      url: "mailto:" + encodeURIComponent(email),
    });
  }
  const phone = String(c?.phone ?? "").trim();
  if (
    /^\+?[0-9 ()-]{7,40}$/.test(phone) && phone.replace(/\D/g, "").length >= 7
  ) {
    items.push({
      label: "Phone",
      value: phone,
      url: "tel:" + phone.replace(/[^+0-9]/g, ""),
    });
  }
  for (
    const [key, label, hosts] of [
      ["website", "Business page", ["workloop.uk"]],
      ["instagram", "Instagram", ["instagram.com", "www.instagram.com"]],
      ["facebook", "Facebook", ["facebook.com", "www.facebook.com"]],
      ["tiktok", "TikTok", ["tiktok.com", "www.tiktok.com"]],
    ] as const
  ) {
    const raw = String(c?.[key] ?? "");
    if (!raw) continue;
    try {
      const u = new URL(raw);
      if (
        u.protocol === "https:" && !u.username && !u.password &&
        hosts.some((h) => h === u.hostname)
      ) items.push({ label, value: u.toString(), url: u.toString() });
    } catch { /* Omit unsafe or incomplete links. */ }
  }
  const instruction = items.length
    ? "Please contact the business directly using the details below."
    : "Business contact details are unavailable. Please use the contact details the business gave you when arranging your booking.";
  return {
    text: instruction +
      (items.length
        ? "\n" + items.map((i) => `${i.label}: ${i.value}`).join("\n")
        : ""),
    html:
      `<div style="margin-top:24px;padding:18px;background:#c3d7e4;border:1px solid #8d8070;border-radius:6px;line-height:1.65"><strong>Contact the business directly</strong><p>${
        escapeEmail(instruction)
      }</p>${
        items.map((i) =>
          `<div>${i.label}: <a style="color:#286280;overflow-wrap:anywhere" href="${
            escapeEmail(i.url)
          }">${escapeEmail(i.value)}</a></div>`
        ).join("")
      }</div>`,
  };
}
export async function loadBusinessEmailContact(
  client: {
    rpc: (
      name: string,
      args: Record<string, unknown>,
    ) => PromiseLike<{ data: unknown; error: { code?: string } | null }>;
  },
  kind: string,
  id: string,
) {
  const { data, error } = await client.rpc("customer_email_contact", {
    p_kind: kind,
    p_id: id,
  });
  if (error) {
    throw Error(`business_contact_unavailable:${error.code ?? "unknown"}`);
  }
  return data && typeof data === "object" && !Array.isArray(data)
    ? data as Record<string, unknown>
    : {};
}
