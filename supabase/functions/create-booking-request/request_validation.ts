export function stringValue(value: unknown, maxLength: number) {
  if (typeof value !== "string") return "";
  return value.replace(/\s+/g, " ").trim().slice(0, maxLength);
}

export function nullableStringValue(value: unknown, maxLength: number) {
  const cleaned = stringValue(value, maxLength);
  return cleaned.length === 0 ? null : cleaned;
}

// A requested time is an instant, never a date-only or server-local clock.
// JavaScript Date otherwise silently rolls dates such as 30 February forward.
export function parseRequestedInstant(value: unknown): Date | null {
  if (typeof value !== "string" || value.length > 64) return null;
  const match =
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})$/
      .exec(value.trim());
  if (match === null) return null;
  const [
    ,
    yearText,
    monthText,
    dayText,
    hourText,
    minuteText,
    secondText,
    ,
    offset,
  ] = match;
  const [year, month, day, hour, minute, second] = [
    yearText,
    monthText,
    dayText,
    hourText,
    minuteText,
    secondText,
  ].map(Number);
  const leapYear = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const daysInMonth = [
    31,
    leapYear ? 29 : 28,
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ];
  if (
    year < 1 || month < 1 || month > 12 || day < 1 ||
    day > daysInMonth[month - 1] ||
    hour > 23 || minute > 59 || second > 59
  ) return null;
  if (offset !== "Z") {
    const offsetHours = Number(offset.slice(1, 3));
    const offsetMinutes = Number(offset.slice(4, 6));
    if (
      offsetHours > 14 || offsetMinutes > 59 ||
      (offsetHours === 14 && offsetMinutes !== 0)
    ) return null;
  }
  const instant = new Date(value.trim());
  return Number.isNaN(instant.getTime()) ? null : instant;
}

export function normalizePhoneDigits(value: string) {
  return value.replace(/\D/g, "");
}

export function normalizeEmail(value: string) {
  return value.trim().toLowerCase();
}

export function isValidEmail(value: string) {
  const email = normalizeEmail(value);
  return email.length >= 3 && email.length <= 254 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

export function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

export function cleanAddOnIds(value: unknown) {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.length > 8) return null;
  const ids = value.map((entry) => stringValue(entry, 64).toLowerCase());
  if (ids.some((id) => !isUuid(id)) || new Set(ids).size !== ids.length) {
    return null;
  }
  return ids;
}

// A primary ID remains in every payload for older clients and relationships.
export function cleanServiceIds(value: unknown, primaryId: string) {
  if (value === undefined || value === null) {
    return primaryId ? [primaryId] : [];
  }
  if (!Array.isArray(value) || value.length === 0 || value.length > 8) {
    return null;
  }
  const ids = value.map((entry) => stringValue(entry, 64).toLowerCase());
  if (
    ids.some((id) => !isUuid(id)) || ids[0] !== primaryId.toLowerCase()
  ) {
    return null;
  }
  return ids;
}

export function resolveRequestToken(
  value: unknown,
  createFallback: () => string = () => crypto.randomUUID(),
) {
  const supplied = stringValue(value, 64);
  return supplied.length > 0 ? supplied : createFallback();
}

export function bookingRequestValidationError(input: {
  handle: string;
  name: string;
  phone: string;
  email: string;
  serviceId: string;
  requestToken: string;
}) {
  if (!/^[a-z0-9][a-z0-9-]{1,78}[a-z0-9]$/.test(input.handle)) {
    return "Invalid profile handle";
  }
  if (
    input.name.length === 0 ||
    input.phone.length === 0 ||
    normalizePhoneDigits(input.phone).length < 7
  ) {
    return "Name and a valid phone are required";
  }
  if (!isValidEmail(input.email)) {
    return "A valid email is required";
  }
  if (input.serviceId.length > 0 && !isUuid(input.serviceId)) {
    return "Invalid service";
  }
  if (!isUuid(input.requestToken)) {
    return "Invalid request token";
  }
  return null;
}

export function bookingRequestOutcomeResponse(outcome: string): {
  status: number;
  body: Record<string, unknown>;
} {
  if (outcome === "rate_limited_source" || outcome === "rate_limited_phone") {
    return {
      status: 429,
      body: { error: "Too many requests. Try again later." },
    };
  }
  if (outcome === "profile_unavailable") {
    return { status: 409, body: { error: "Booking requests are closed" } };
  }
  if (outcome === "invalid_service") {
    return { status: 400, body: { error: "Invalid service" } };
  }
  if (outcome === "invalid_bundle_total") {
    return {
      status: 400,
      body: { error: "Choose services totalling no more than 24 hours" },
    };
  }
  if (outcome === "invalid_add_on") {
    return { status: 400, body: { error: "Invalid optional extra" } };
  }
  if (outcome === "created" || outcome === "duplicate") {
    return {
      status: 200,
      body: { ok: true, duplicate: outcome === "duplicate" },
    };
  }
  return { status: 500, body: { error: "Could not create request" } };
}

function validPlatformIp(value: string | null) {
  const candidate = value?.trim() ?? "";
  if (
    candidate.length === 0 ||
    candidate.length > 64 ||
    !/^[0-9a-f:.]+$/i.test(candidate)
  ) {
    return null;
  }
  return candidate.toLowerCase();
}

export function bestEffortPlatformIp(headers: Headers) {
  // The edge gateway is expected to overwrite these platform headers. The
  // right-most forwarded value is preferred over the caller-controlled first
  // value when a proxy appends its observed address.
  const direct = validPlatformIp(headers.get("cf-connecting-ip")) ??
    validPlatformIp(headers.get("x-real-ip"));
  if (direct) return direct;

  const forwarded = (headers.get("x-forwarded-for") ?? "")
    .split(",")
    .map((part) => validPlatformIp(part))
    .filter((part): part is string => part !== null);
  return forwarded.at(-1) ?? "unknown";
}
