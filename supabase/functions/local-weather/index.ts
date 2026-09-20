import "jsr:@supabase/functions-js@2.110.5/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import { approximateCoordinates, ForecastCache } from "./forecast.ts";

const cache = new ForecastCache();
const callers = new Map<string, { started: number; count: number }>();
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
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
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization) return json(401, { error: "sign_in_required" });
    const client = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: { headers: { Authorization: authorization } },
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );
    const { data, error } = await client.auth.getUser();
    if (error || !data.user || data.user.is_anonymous) {
      return json(401, { error: "sign_in_required" });
    }
    const now = Date.now();
    let caller = callers.get(data.user.id);
    if (!caller || now - caller.started > 60000) {
      caller = { started: now, count: 0 };
    }
    if (++caller.count > 6) return json(429, { error: "try_later" });
    if (callers.size >= 1000) callers.delete(callers.keys().next().value!);
    callers.set(data.user.id, caller);
    const text = await req.text();
    if (text.length > 256) return json(400, { error: "invalid_request" });
    let body: any;
    try {
      body = JSON.parse(text);
      approximateCoordinates(body.latitude, body.longitude);
    } catch {
      return json(400, { error: "invalid_coordinates" });
    }
    const reading = await cache.get(body.latitude, body.longitude);
    return json(200, reading);
  } catch {
    // Do not log location, request bodies, IPs, or identifying auth data.
    return json(503, { error: "weather_unavailable" });
  }
});
