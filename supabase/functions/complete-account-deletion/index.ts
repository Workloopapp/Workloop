import { createClient } from "@supabase/supabase-js";
import { closeWorkloopStripeAccount } from "../_shared/stripe_account_offboarding.ts";
import { StripeApiError, stripeRequest } from "../_shared/stripe_api.ts";
import { canCompleteAccountDeletion } from "../_shared/account_deletion_owner.ts";
import { removeWorkspaceReceiptFiles } from "../_shared/receipt_storage_cleanup.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-admin-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type CompletionPayload = {
  requestId?: unknown;
  notes?: unknown;
};

const textEncoder = new TextEncoder();

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function stringValue(value: unknown, maxLength: number) {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, maxLength);
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    textEncoder.encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return response(405, { error: "Method not allowed" });
  }

  const configuredAdminToken = Deno.env.get("ACCOUNT_DELETION_ADMIN_TOKEN") ??
    "";
  const suppliedAdminToken = req.headers.get("x-admin-token") ?? "";
  let tokenDifference = configuredAdminToken.length ^ suppliedAdminToken.length;
  for (let index = 0; index < configuredAdminToken.length; index++) {
    tokenDifference |= configuredAdminToken.charCodeAt(index) ^
      (suppliedAdminToken.charCodeAt(index) || 0);
  }
  if (!configuredAdminToken || tokenDifference !== 0) {
    return response(401, { error: "Unauthorized" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceRoleKey) {
    return response(500, {
      error: "Deletion completion service is not configured",
    });
  }

  let payload: CompletionPayload;
  try {
    payload = await req.json();
  } catch (_) {
    return response(400, { error: "Invalid request body" });
  }

  const requestId = stringValue(payload.requestId, 64);
  const notes = stringValue(payload.notes, 1000);
  if (!isUuid(requestId)) {
    return response(400, { error: "Invalid deletion request" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: request, error: requestError } = await supabase
    .from("account_deletion_requests")
    .select(
      "id, workspace_id, user_id, requested_by_user_id, email, status, requested_at, processing_started_at",
    )
    .eq("id", requestId)
    .maybeSingle();

  if (requestError) {
    return response(500, { error: "Could not load deletion request" });
  }
  if (!request) return response(404, { error: "Deletion request not found" });
  if (!["requested", "processing"].includes(request.status)) {
    return response(409, { error: "Deletion request is not open" });
  }

  const userId = request.requested_by_user_id ?? request.user_id;
  if (!userId) {
    return response(409, {
      error: "Deletion blocked because the request has no verified owner",
    });
  }

  // A NULL workspace can mean either pre-onboarding deletion or a retry after
  // the workspace was removed. Never delete Auth while another workspace still
  // references this account; this also guards late administrative changes.
  const { data: ownedMemberships, error: ownedMembershipError } = await supabase
    .from("workspace_members")
    .select("workspace_id")
    .eq("user_id", userId)
    .limit(2);
  if (ownedMembershipError) {
    return response(503, { error: "Could not verify account ownership" });
  }
  if (
    (ownedMemberships ?? []).some((membership) =>
      membership.workspace_id !== request.workspace_id
    )
  ) {
    return response(409, {
      error:
        "Deletion blocked because another workspace still uses this account",
    });
  }

  if (request.workspace_id) {
    const { data: memberships, error: membershipError } = await supabase
      .from("workspace_members")
      .select("user_id")
      .eq("workspace_id", request.workspace_id)
      .limit(2);

    if (membershipError) {
      return response(500, {
        error: "Could not verify workspace ownership",
      });
    }
    const { data: authUserResult, error: authUserLookupError } = await supabase
      .auth.admin.getUserById(userId);
    const authUserMissing = authUserLookupError &&
      (authUserLookupError.status === 404 ||
        /not found|does not exist/i.test(authUserLookupError.message));
    if (authUserLookupError && !authUserMissing) {
      return response(500, { error: "Could not verify the Auth owner" });
    }
    if (
      !canCompleteAccountDeletion({
        memberships,
        requestedUserId: userId,
        authUserExists: authUserResult?.user != null,
      })
    ) {
      return response(409, {
        error:
          "Deletion blocked because sole workspace ownership could not be verified",
      });
    }
  }

  const claimTime = new Date();
  const previousClaimTime = request.processing_started_at
    ? new Date(request.processing_started_at)
    : null;
  const retryLeaseMs = 5 * 60 * 1000;
  if (
    request.status === "processing" &&
    previousClaimTime &&
    claimTime.getTime() - previousClaimTime.getTime() < retryLeaseMs
  ) {
    return response(409, {
      error: "Deletion is already processing; retry after five minutes",
    });
  }

  let claimQuery = supabase
    .from("account_deletion_requests")
    .update({
      status: "processing",
      processing_started_at: claimTime.toISOString(),
      completed_by: "admin-token",
      completion_mode: "workspace_and_auth_user_delete",
      notes: notes || "Deletion completion started.",
    })
    .eq("id", request.id)
    .eq("status", request.status);
  if (request.status === "processing") {
    claimQuery = previousClaimTime
      ? claimQuery.eq("processing_started_at", request.processing_started_at)
      : claimQuery.is("processing_started_at", null);
  }
  const { data: claim, error: completionUpdateError } = await claimQuery
    .select("id")
    .maybeSingle();
  if (completionUpdateError) {
    return response(500, { error: "Could not start account deletion" });
  }
  if (!claim) {
    return response(409, { error: "Deletion request was claimed elsewhere" });
  }

  async function releaseClaim(note: string) {
    const { error } = await supabase.from("account_deletion_requests").update({
      status: "requested",
      processing_started_at: null,
      notes: note,
    }).eq("id", requestId).eq("status", "processing");
    return error == null;
  }

  // Workloop creates Accounts v2 merchant accounts. Provider offboarding must
  // be confirmed before local account/payment mappings are deleted; otherwise
  // Workloop could retain access to an account that the user believed removed.
  // The helper first reads the account and treats `closed: true` as an
  // idempotent success, so a retry is safe if the later DB delete fails.
  if (request.workspace_id) {
    const { data: paymentAccount, error: paymentAccountError } = await supabase
      .from("workspace_payment_accounts")
      .select("stripe_account_id, mode")
      .eq("workspace_id", request.workspace_id)
      .maybeSingle();
    if (paymentAccountError) {
      await releaseClaim("Stripe offboarding could not be prepared; retry.");
      return response(500, {
        error: "Could not prepare payment account offboarding",
      });
    }

    if (paymentAccount) {
      const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
      const accountId = stringValue(paymentAccount.stripe_account_id, 100);
      const mode = stringValue(paymentAccount.mode, 8);
      try {
        // Only service_role can write this audit table. Reuse the existing
        // audit for a durable provider checkpoint, scoped to this exact request,
        // owner, workspace and account. A later local failure can safely retry.
        const { data: checkpoint, error: checkpointError } = await supabase
          .from("account_deletion_audit")
          .select("id")
          .eq("request_id", request.id)
          .eq("workspace_id", request.workspace_id)
          .eq("user_id", userId)
          .eq("completion_mode", "stripe_access_revoked")
          .eq("notes", `${mode}:${accountId}`)
          .limit(1)
          .maybeSingle();
        if (checkpointError) {
          throw new Error("Could not read provider checkpoint");
        }
        if (!checkpoint) {
          await closeWorkloopStripeAccount(
            stripeSecretKey,
            accountId,
            mode,
            stripeRequest,
            Deno.env.get(
              mode === "live"
                ? "STRIPE_CONNECT_CLIENT_ID"
                : "STRIPE_CONNECT_TEST_CLIENT_ID",
            ) ?? "",
          );
          const { error: auditError } = await supabase.from(
            "account_deletion_audit",
          )
            .insert({
              request_id: request.id,
              workspace_id: request.workspace_id,
              user_id: userId,
              requested_at: request.requested_at,
              completed_by: "admin-token",
              completion_mode: "stripe_access_revoked",
              workspace_deleted: false,
              auth_user_deleted: false,
              notes: `${mode}:${accountId}`,
            });
          if (auditError) {
            throw new Error("Could not checkpoint provider offboarding");
          }
        }
      } catch (error) {
        console.error("account_deletion_stripe_offboarding_failed", {
          requestId: request.id,
          code: error instanceof StripeApiError
            ? error.code
            : "offboarding_not_confirmed",
        });
        const released = await releaseClaim(
          "Stripe offboarding was not confirmed; no local account data was deleted.",
        );
        return response(released ? 409 : 500, {
          error: released
            ? "Payment account offboarding must complete before deletion"
            : "Payment account offboarding failed and the request needs review",
          code: "stripe_offboarding_required",
        });
      }
    }
  }

  // Logo objects include uploads made during onboarding, before a workspace
  // exists. Remove the authenticated account's folder before deleting metadata.
  try {
    await removeWorkspaceReceiptFiles(
      supabase.storage.from("business-logos"),
      userId,
    );
  } catch (_) {
    await releaseClaim(
      "Business logo cleanup failed; retry before deleting account records.",
    );
    return response(500, {
      error: "Could not complete business logo deletion",
    });
  }

  let workspaceDeleted = false;
  if (request.workspace_id) {
    try {
      await removeWorkspaceReceiptFiles(
        supabase.storage.from("expense-receipts"),
        request.workspace_id,
      );
      await removeWorkspaceReceiptFiles(
        supabase.storage.from("record-attachments"),
        request.workspace_id,
      );
    } catch (_) {
      await releaseClaim(
        "Private file cleanup failed; retry before deleting workspace records.",
      );
      return response(500, {
        error: "Could not complete private file deletion",
      });
    }
  }
  let authUserDeleted = false;

  // The request survives workspace deletion (FK uses ON DELETE SET NULL), so
  // a later auth failure can be retried with the same request id.
  if (request.workspace_id) {
    const { error: workspaceDeleteError } = await supabase
      .from("workspaces")
      .delete()
      .eq("id", request.workspace_id);
    if (workspaceDeleteError) {
      await supabase.from("account_deletion_audit").insert({
        request_id: request.id,
        workspace_id: request.workspace_id,
        user_id: userId,
        email_hash: request.email
          ? await sha256(request.email.toLowerCase())
          : null,
        requested_at: request.requested_at,
        completed_by: "admin-token",
        completion_mode: "workspace_and_auth_user_delete",
        workspace_deleted: false,
        auth_user_deleted: false,
        notes: `Workspace deletion failed: ${workspaceDeleteError.message}`,
      });
      return response(500, { error: "Workspace deletion failed" });
    }
  }
  workspaceDeleted = true;

  if (userId) {
    // Prevent new sign-ins while the final delete is being completed. Existing
    // access JWTs are bounded separately by RLS and the app's server check.
    await supabase.auth.admin.updateUserById(userId, {
      ban_duration: "876000h",
    }).catch(() => null);
    const { error: authDeleteError } = await supabase.auth.admin.deleteUser(
      userId,
    );
    const authUserAlreadyDeleted = authDeleteError &&
      (authDeleteError.status === 404 ||
        /not found|does not exist/i.test(authDeleteError.message));
    if (authDeleteError && !authUserAlreadyDeleted) {
      await supabase.from("account_deletion_audit").insert({
        request_id: request.id,
        workspace_id: request.workspace_id,
        user_id: userId,
        email_hash: request.email
          ? await sha256(request.email.toLowerCase())
          : null,
        requested_at: request.requested_at,
        completed_by: "admin-token",
        completion_mode: "workspace_and_auth_user_delete",
        workspace_deleted: workspaceDeleted,
        auth_user_deleted: false,
        notes:
          `Workspace deleted, auth user deletion failed: ${authDeleteError.message}`,
      });
      return response(500, {
        error: "Auth user deletion failed after workspace deletion",
      });
    }
    authUserDeleted = true;
  }

  const { error: finalUpdateError } = await supabase
    .from("account_deletion_requests")
    .update({
      status: "completed",
      completed_at: new Date().toISOString(),
      notes: notes || "Workspace and auth user deleted.",
    })
    .eq("id", request.id);
  if (finalUpdateError) {
    return response(500, {
      error:
        "Account data was deleted, but completion could not be recorded; retry this request",
    });
  }

  const { error: auditError } = await supabase.from("account_deletion_audit")
    .insert({
      request_id: request.id,
      workspace_id: request.workspace_id,
      user_id: userId,
      email_hash: request.email
        ? await sha256(request.email.toLowerCase())
        : null,
      requested_at: request.requested_at,
      completed_by: "admin-token",
      completion_mode: "workspace_and_auth_user_delete",
      workspace_deleted: workspaceDeleted,
      auth_user_deleted: authUserDeleted,
      notes: notes || "Workspace and auth user deleted.",
    });
  if (auditError) {
    return response(500, {
      error:
        "Account data was deleted, but the deletion audit could not be recorded",
    });
  }

  return response(200, {
    ok: true,
    workspaceDeleted,
    authUserDeleted,
  });
});
