import type { SupabaseClient } from "@supabase/supabase-js";

/** Resolve only saved, workspace-scoped recipient details before reserving. */
export async function paymentLinkReceiptEmail(
  client: SupabaseClient,
  invoice: Record<string, unknown>,
  workspaceId: string,
): Promise<string> {
  if (invoice.source_document_id) {
    const { data, error } = await client.from("business_documents")
      .select("client_snapshot")
      .eq("id", invoice.source_document_id)
      .eq("workspace_id", workspaceId)
      .eq("invoice_id", invoice.id)
      .single();
    if (error) throw error;
    // Issued details remain authoritative even if a saved contact has changed.
    return String(data.client_snapshot?.email ?? "").trim();
  }
  if (invoice.appointment_id) {
    const { data, error } = await client.rpc(
      "payment_booking_recipient_email",
      {
        p_invoice_id: invoice.id,
      },
    );
    if (error) throw error;
    if (data) return String(data).trim();
  }
  if (!invoice.contact_id) return "";
  const { data, error } = await client.from("contacts")
    .select("email").eq("id", invoice.contact_id)
    .eq("workspace_id", workspaceId).maybeSingle();
  if (error) throw error;
  return String(data?.email ?? "").trim();
}
