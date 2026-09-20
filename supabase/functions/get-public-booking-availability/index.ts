import { createClient } from "@supabase/supabase-js";

import {
  bestEffortPlatformIp,
  cleanAvailabilityRequest,
  publicAvailabilityResponse,
  sha256Hex,
} from "./availability_contract.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(
  status: number,
  body: Record<string, unknown>,
  retryAfterSeconds?: number,
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      ...(retryAfterSeconds === undefined
        ? {}
        : { "Retry-After": retryAfterSeconds.toString() }),
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return response(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (supabaseUrl.length === 0 || serviceRoleKey.length === 0) {
    return response(500, {
      error: "Suggested times service is not configured",
    });
  }

  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch (_) {
    return response(400, { error: "Invalid request body" });
  }
  const input = cleanAvailabilityRequest(rawBody);
  if (input === null) {
    return response(400, { error: "Choose an available service" });
  }

  const salt = Deno.env.get("BOOKING_AVAILABILITY_RATE_LIMIT_SALT") ??
    `workloop-public-availability:${serviceRoleKey}`;
  const sourceHash = await sha256Hex(
    `${salt}:${bestEffortPlatformIp(req.headers)}`,
  );
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: active, error: activeError } = await supabase.rpc(
    "is_public_profile_active",
    { p_handle: input.handle },
  );
  if (activeError) {
    return response(503, { error: "Could not verify public profile" });
  }
  if (active !== true) return response(404, { error: "Profile not found" });
  const { data, error } = await supabase.rpc(
    input.serviceIds.length > 1
      ? "get_public_booking_slot_suggestions_v4"
      : "get_public_booking_slot_suggestions_v3",
    {
      p_handle: input.handle,
      p_service_id: input.serviceId,
      ...(input.serviceIds.length > 1
        ? { p_service_ids: input.serviceIds }
        : {}),
      p_source_hash: sourceHash,
      p_add_on_ids: input.addOnIds,
      p_target_date: input.targetDate,
    },
  );
  if (error) {
    console.error("Public availability RPC failed", error.code);
    return response(500, { error: "Could not load suggested times" });
  }
  const mapped = publicAvailabilityResponse(data);
  return response(mapped.status, mapped.body, mapped.retryAfterSeconds);
});
