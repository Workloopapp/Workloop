import { createClient } from "@supabase/supabase-js";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type PublicProfilePayload = {
  handle?: unknown;
};

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function stringValue(value: unknown, maxLength: number) {
  if (typeof value !== "string") return "";
  return value.replace(/\s+/g, " ").trim().slice(0, maxLength);
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
    return response(500, { error: "Public profile service is not configured" });
  }

  let payload: PublicProfilePayload;
  try {
    payload = await req.json();
  } catch (_) {
    return response(400, { error: "Invalid request body" });
  }

  const handle = stringValue(payload.handle, 80).toLowerCase();
  if (!/^[a-z0-9][a-z0-9-]{1,78}[a-z0-9]$/.test(handle)) {
    return response(400, { error: "Invalid profile handle" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: profile, error: profileError } = await supabase
    .from("business_profiles")
    .select(
      "id, workspace_id, handle, bio, cover_photo_url, gallery_image_urls, review_quotes, reviews_enabled, gallery_enabled, pay_now_enabled, booking_mode, notice_text, notice_start, notice_end",
    )
    .eq("handle", handle)
    .maybeSingle();

  if (profileError) return response(500, { error: "Could not load profile" });
  if (!profile) return response(404, { error: "Profile not found" });

  // Service-role reads need an explicit current owner/deletion boundary.
  const { data: member, error: memberError } = await supabase
    .rpc("is_public_workspace_active", {
      p_workspace_id: profile.workspace_id,
    });

  if (memberError) return response(500, { error: "Could not load profile" });
  if (member !== true) return response(404, { error: "Profile not found" });

  const { data: workspace, error: workspaceError } = await supabase
    .from("workspaces")
    .select("name, industry, logo_url")
    .eq("id", profile.workspace_id)
    .maybeSingle();

  if (workspaceError) {
    return response(500, { error: "Could not load profile" });
  }

  const { data: settings, error: settingsError } = await supabase
    .from("workspace_settings")
    .select("working_hours, timezone")
    .eq("workspace_id", profile.workspace_id)
    .maybeSingle();

  if (settingsError) {
    return response(500, { error: "Could not load profile" });
  }

  const { data: services, error: servicesError } = await supabase
    .from("services")
    .select(
      "id, name, duration_mins, price, description, show_on_profile, service_add_ons(id, name, description, duration_mins, price, position)",
    )
    .eq("workspace_id", profile.workspace_id)
    .eq("show_on_profile", true)
    .eq("active", true)
    .gte("duration_mins", 5)
    .lte("duration_mins", 1440)
    .eq("service_add_ons.active", true)
    .order("position", { foreignTable: "service_add_ons", ascending: true })
    .order("name", { ascending: true });

  if (servicesError) {
    return response(500, { error: "Could not load services" });
  }

  const { workspace_id: _workspaceId, ...safeProfile } = profile;
  return response(200, {
    profile: safeProfile,
    businessName: workspace?.name ?? "Business",
    logoUrl: workspace?.logo_url ?? null,
    industry: workspace?.industry ?? null,
    workingHours: settings?.working_hours ?? {},
    timezone: settings?.timezone ?? "Europe/London",
    services: services ?? [],
  });
});
