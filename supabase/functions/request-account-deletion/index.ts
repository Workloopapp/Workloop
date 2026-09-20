import { createClient } from "@supabase/supabase-js";
import { isSoleWorkspaceOwner } from "../_shared/sole_workspace_owner.ts";
import {
  appleIdentity,
  AppleIdentityMismatch,
  revokeAppleAccount,
} from "../_shared/apple_account_revocation.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
async function requestBody(req: Request): Promise<Record<string, unknown>> {
  const reader = req.body?.getReader();
  if (!reader) throw new Error("body");
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > 16384) {
        await reader.cancel();
        throw new Error("body");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  const body = JSON.parse(new TextDecoder().decode(bytes));
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new Error("body");
  }
  return body;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return response(405, { error: "Method not allowed" });
  }
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !anon || !serviceKey) {
    return response(503, {
      error: "Deletion request service is not configured",
    });
  }
  let body: Record<string, unknown>;
  try {
    body = await requestBody(req);
  } catch {
    return response(400, { error: "Invalid request body" });
  }
  const requestedWorkspace = body.workspaceId;
  if (
    requestedWorkspace != null &&
    (typeof requestedWorkspace !== "string" || !uuid.test(requestedWorkspace))
  ) return response(400, { error: "Invalid workspace" });
  const code = body.appleAuthorizationCode;
  if (
    code != null &&
    (typeof code !== "string" || code.length < 1 || code.length > 4096)
  ) return response(400, { error: "Invalid Apple authorization" });
  const authorization = req.headers.get("Authorization") ?? "";
  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const service = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  const user = userData.user;
  if (userError || !user) return response(401, { error: "Unauthorized" });
  // Auth just verified this JWT. Only extract its session binding here.
  let claims: { session_id?: string; aal?: string };
  try {
    const part = authorization.replace(/^Bearer\s+/i, "").split(".")[1];
    claims = JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/")));
    if (!uuid.test(claims.session_id ?? "")) throw new Error("session");
  } catch {
    return response(401, { error: "An active session is required" });
  }
  const { data: active, error: activeError } = await userClient.rpc(
    "current_user_session_is_active",
  );
  if (activeError) {
    return response(503, { error: "Could not verify account security" });
  }
  if (active !== true) {
    return response(401, { error: "An active session is required" });
  }
  const { data: mfa, error: mfaError } = await userClient.rpc(
    "current_user_meets_mfa_policy",
  );
  if (mfaError) {
    return response(503, { error: "Could not verify account security" });
  }
  if (mfa !== true) {
    return response(403, {
      error: "Complete two-factor verification to delete this account",
      code: "mfa_required",
    });
  }
  const { data: ownMemberships, error: ownError } = await service.from(
    "workspace_members",
  )
    .select("workspace_id").eq("user_id", user.id).limit(2);
  if (ownError) {
    return response(503, { error: "Could not verify workspace ownership" });
  }
  if ((ownMemberships?.length ?? 0) > 1) {
    return response(409, {
      error: "Multiple workspaces require ownership review",
    });
  }
  const workspaceId: string | null = ownMemberships?.[0]?.workspace_id ?? null;
  if (requestedWorkspace != null && requestedWorkspace !== workspaceId) {
    return response(403, { error: "Workspace access denied" });
  }
  if (workspaceId) {
    const { data: members, error } = await service.from("workspace_members")
      .select("user_id").eq("workspace_id", workspaceId).limit(2);
    if (error) {
      return response(503, { error: "Could not verify workspace ownership" });
    }
    if (!isSoleWorkspaceOwner(members, user.id)) {
      return response(403, {
        error: "Only the sole workspace owner can delete this account",
      });
    }
  }
  let appleRevocation;
  try {
    appleRevocation = await revokeAppleAccount({
      ...appleIdentity(user.identities),
      authorizationCode: typeof code === "string" ? code : undefined,
    });
  } catch (error) {
    if (error instanceof AppleIdentityMismatch) {
      return response(409, {
        error:
          "Use the Apple account linked to Workloop, or continue with manual Apple unlinking.",
        code: "apple_identity_mismatch",
      });
    }
    return response(503, { error: "Could not prepare account deletion" });
  }
  // Service-only transaction repeats ownership/MFA/session checks, shares
  // onboarding's lock, and atomically records deletion plus revokes sessions.
  const { data, error } = await service.rpc(
    "request_account_deletion_for_user",
    {
      p_user_id: user.id,
      p_session_id: claims.session_id,
      p_aal: claims.aal ?? "",
      p_workspace_id: workspaceId,
      p_apple_revocation: appleRevocation,
    },
  );
  if (error) {
    return response(
      error.code === "28000" ? 401 : error.code === "42501" ? 403 : 503,
      {
        error:
          "Could not accept account deletion. Refresh your account and try again.",
      },
    );
  }
  // Pending-state RLS and deleted sessions already close data access. The Auth
  // ban also prevents fresh sign-ins; a transient failure cannot reopen RLS.
  const { error: banError } = await service.auth.admin.updateUserById(user.id, {
    ban_duration: "876000h",
  });
  if (banError) {
    console.error("account_deletion_ban_pending", { code: banError.code });
  }
  return response(200, data);
});
