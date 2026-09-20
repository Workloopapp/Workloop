import { cleanServiceIds } from "../create-booking-request/request_validation.ts";

export type AvailabilityRequest = {
  handle: string;
  serviceId: string;
  serviceIds: string[];
  addOnIds: string[];
  targetDate: string | null;
};

function safeIsoDate(value: unknown) {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return undefined;
  }
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isNaN(parsed.valueOf()) ||
      parsed.toISOString().slice(0, 10) !== value
    ? undefined
    : value;
}

export function cleanAvailabilityRequest(
  value: unknown,
): AvailabilityRequest | null {
  if (value === null || typeof value !== "object") return null;
  const raw = value as Record<string, unknown>;
  const handle = typeof raw.handle === "string"
    ? raw.handle.replace(/\s+/g, " ").trim().toLowerCase().slice(0, 80)
    : "";
  const serviceId = typeof raw.serviceId === "string"
    ? raw.serviceId.trim().toLowerCase()
    : "";
  const serviceIds = cleanServiceIds(
    raw.serviceIds ?? raw.service_ids,
    serviceId,
  );
  if (serviceIds === null) return null;
  const rawAddOnIds = raw.addOnIds ?? [];
  const targetDate = safeIsoDate(raw.targetDate ?? raw.target_date);
  if (targetDate === undefined) return null;
  if (!Array.isArray(rawAddOnIds) || rawAddOnIds.length > 8) return null;
  const addOnIds = rawAddOnIds.map((entry) =>
    typeof entry === "string" ? entry.trim().toLowerCase() : ""
  );
  if (!/^[a-z0-9][a-z0-9-]{1,78}[a-z0-9]$/.test(handle)) return null;
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(serviceId)
  ) {
    return null;
  }
  if (
    addOnIds.some((id) =>
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
        .test(id)
    ) || new Set(addOnIds).size !== addOnIds.length
  ) return null;
  return { handle, serviceId, serviceIds, addOnIds, targetDate };
}

function safeInteger(value: unknown, minimum: number, maximum: number) {
  return typeof value === "number" && Number.isInteger(value) &&
      value >= minimum && value <= maximum
    ? value
    : null;
}

function safeIsoInstant(value: unknown) {
  if (typeof value !== "string" || value.length > 40) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.valueOf()) ? null : parsed.toISOString();
}

export function publicAvailabilityResponse(value: unknown): {
  status: number;
  body: Record<string, unknown>;
  retryAfterSeconds?: number;
} {
  if (value === null || typeof value !== "object") {
    return { status: 500, body: { error: "Could not load suggested times" } };
  }
  const raw = value as Record<string, unknown>;
  const outcome = raw.outcome;
  if (outcome === "profile_unavailable") {
    return { status: 404, body: { error: "Profile not found" } };
  }
  if (outcome === "invalid_service") {
    return { status: 400, body: { error: "Choose an available service" } };
  }
  if (outcome === "invalid_bundle_total") {
    return {
      status: 400,
      body: { error: "Choose services totalling no more than 24 hours" },
    };
  }
  if (outcome === "invalid_add_on") {
    return { status: 400, body: { error: "Choose available optional extras" } };
  }
  if (outcome === "configuration_unavailable") {
    return { status: 503, body: { error: "Suggested times are unavailable" } };
  }
  if (outcome === "rate_limited") {
    const retryAfterSeconds = safeInteger(raw.retryAfterSeconds, 1, 900) ?? 60;
    return {
      status: 429,
      retryAfterSeconds,
      body: { error: "Too many requests. Try again shortly." },
    };
  }
  if (outcome !== "ok") {
    return { status: 500, body: { error: "Could not load suggested times" } };
  }

  const timezone = typeof raw.timezone === "string" && raw.timezone.length <= 64
    ? raw.timezone
    : null;
  const durationMinutes = safeInteger(raw.durationMinutes, 5, 12960);
  const generatedAt = safeIsoInstant(raw.generatedAt);
  if (timezone === null || durationMinutes === null || generatedAt === null) {
    return { status: 500, body: { error: "Could not load suggested times" } };
  }

  const days = (Array.isArray(raw.days) ? raw.days : []).slice(0, 5).flatMap(
    (value): Array<Record<string, unknown>> => {
      if (value === null || typeof value !== "object") return [];
      const day = value as Record<string, unknown>;
      const date =
        typeof day.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(day.date)
          ? day.date
          : null;
      if (date === null) return [];
      const slots = (Array.isArray(day.slots) ? day.slots : [])
        .map(safeIsoInstant)
        .filter((slot): slot is string => slot !== null)
        .slice(0, 6);
      return slots.length === 0 ? [] : [{ date, slots }];
    },
  );

  return {
    status: 200,
    body: { timezone, durationMinutes, generatedAt, days },
  };
}

export function bestEffortPlatformIp(headers: Headers) {
  const valid = (value: string | null) => {
    const candidate = value?.trim() ?? "";
    return candidate.length > 0 && candidate.length <= 64 &&
        /^[0-9a-f:.]+$/i.test(candidate)
      ? candidate.toLowerCase()
      : null;
  };
  const direct = valid(headers.get("cf-connecting-ip")) ??
    valid(headers.get("x-real-ip"));
  if (direct !== null) return direct;
  const forwarded = (headers.get("x-forwarded-for") ?? "")
    .split(",")
    .map(valid)
    .filter((entry): entry is string => entry !== null);
  return forwarded.at(-1) ?? "unknown";
}

export async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
