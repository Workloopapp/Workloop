import {
  bestEffortPlatformIp,
  bookingRequestOutcomeResponse,
  bookingRequestValidationError,
  cleanAddOnIds,
  cleanServiceIds,
  isUuid,
  isValidEmail,
  normalizeEmail,
  normalizePhoneDigits,
  nullableStringValue,
  parseRequestedInstant,
  resolveRequestToken,
  stringValue,
} from "./request_validation.ts";

Deno.test("requested instants preserve explicit offsets and autumn repeated times", () => {
  assertEquals(
    parseRequestedInstant("2026-10-25T01:30:00+01:00")?.toISOString(),
    "2026-10-25T00:30:00.000Z",
  );
  assertEquals(
    parseRequestedInstant("2026-10-25T01:30:00+00:00")?.toISOString(),
    "2026-10-25T01:30:00.000Z",
  );
  assertEquals(
    parseRequestedInstant("2026-09-06T10:30:12.345678Z")?.toISOString(),
    "2026-09-06T10:30:12.345Z",
  );
  assertEquals(
    parseRequestedInstant("2028-02-29T09:00:00Z")?.toISOString(),
    "2028-02-29T09:00:00.000Z",
  );
});

Deno.test("requested instants reject calendar rollover, missing zones and invalid offsets", () => {
  for (
    const value of [
      "2026-02-30T09:00:00Z",
      "2026-02-29T09:00:00Z",
      "2026-04-31T09:00:00Z",
      "2026-09-06",
      "2026-09-06T09:00:00",
      "2026-09-06T24:00:00Z",
      "2026-09-06T09:60:00Z",
      "2026-09-06T09:00:60Z",
      "2026-09-06T09:00:00+14:30",
      "2026-09-06T09:00:00+25:00",
      "September 6, 2026 09:00 UTC",
      null,
      123,
    ]
  ) assertEquals(parseRequestedInstant(value), null);
});

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("normalises public text and optional values", () => {
  assertEquals(stringValue("  Ada   Lovelace  ", 80), "Ada Lovelace");
  assertEquals(nullableStringValue("   ", 80), null);
});

Deno.test("normalises equivalent phone formats to the same digits", () => {
  assertEquals(normalizePhoneDigits("+44 (0) 7123-456-789"), "4407123456789");
  assertEquals(normalizePhoneDigits("44 0 7123 456 789"), "4407123456789");
});

Deno.test("normalises and validates public booking email", () => {
  assertEquals(normalizeEmail("  ADA@Example.COM "), "ada@example.com");
  assertEquals(isValidEmail("ada@example.com"), true);
  assertEquals(isValidEmail("ada example.com"), false);
  assertEquals(isValidEmail("ada@localhost"), false);
  assertEquals(isValidEmail(`${"a".repeat(242)}@example.com`), true);
  assertEquals(isValidEmail(`${"a".repeat(243)}@example.com`), false);
});

Deno.test("accepts UUID request tokens and rejects arbitrary identifiers", () => {
  assertEquals(isUuid("c2499f36-c3f4-4f80-80dd-31ba2b581f78"), true);
  assertEquals(isUuid("retry-me"), false);
});

Deno.test("preserves a supplied retry token across duplicate submissions", () => {
  const token = "c2499f36-c3f4-4f80-80dd-31ba2b581f78";
  assertEquals(resolveRequestToken(token, () => "unused"), token);
  assertEquals(resolveRequestToken(token, () => "different"), token);
  assertEquals(resolveRequestToken("", () => token), token);
});

Deno.test("accepts at most eight unique add-on IDs", () => {
  const id = "c2499f36-c3f4-4f80-80dd-31ba2b581f78";
  assertEquals(cleanAddOnIds(undefined), []);
  assertEquals(cleanAddOnIds([id]), [id]);
  assertEquals(cleanAddOnIds([id, id]), null);
  assertEquals(cleanAddOnIds(["not-an-id"]), null);
  assertEquals(cleanAddOnIds(Array(9).fill(id)), null);
});

Deno.test("rejects invalid booking fields before any database call", () => {
  const valid = {
    handle: "ada-studio",
    name: "Ada",
    phone: "+44 7123 456 789",
    email: "ada@example.com",
    serviceId: "c2499f36-c3f4-4f80-80dd-31ba2b581f78",
    requestToken: "e72d0756-7440-4ae3-88f2-c6dce8bcbdf7",
  };
  assertEquals(bookingRequestValidationError(valid), null);
  assertEquals(
    bookingRequestValidationError({ ...valid, email: "missing-at.example" }),
    "A valid email is required",
  );
  assertEquals(
    bookingRequestValidationError({ ...valid, handle: "../admin" }),
    "Invalid profile handle",
  );
  assertEquals(
    bookingRequestValidationError({ ...valid, phone: "123" }),
    "Name and a valid phone are required",
  );
  assertEquals(
    bookingRequestValidationError({ ...valid, serviceId: "other-workspace" }),
    "Invalid service",
  );
  assertEquals(
    bookingRequestValidationError({ ...valid, requestToken: "retry-me" }),
    "Invalid request token",
  );
});

Deno.test("maps duplicate and guarded database outcomes safely", () => {
  assertEquals(bookingRequestOutcomeResponse("duplicate"), {
    status: 200,
    body: { ok: true, duplicate: true },
  });
  assertEquals(bookingRequestOutcomeResponse("invalid_service"), {
    status: 400,
    body: { error: "Invalid service" },
  });
  assertEquals(bookingRequestOutcomeResponse("invalid_add_on"), {
    status: 400,
    body: { error: "Invalid optional extra" },
  });
  assertEquals(
    bookingRequestOutcomeResponse("profile_unavailable").status,
    409,
  );
  assertEquals(bookingRequestOutcomeResponse("rate_limited_phone").status, 429);
  assertEquals(bookingRequestOutcomeResponse("unknown").status, 500);
});

Deno.test("prefers gateway IP headers over caller-forwarded values", () => {
  const headers = new Headers({
    "cf-connecting-ip": "2001:db8::7",
    "x-forwarded-for": "198.51.100.10, 203.0.113.8",
  });
  assertEquals(bestEffortPlatformIp(headers), "2001:db8::7");
});

Deno.test("uses the right-most valid forwarded address as a fallback", () => {
  const headers = new Headers({
    "x-forwarded-for": "not-an-ip, 198.51.100.10, 203.0.113.8",
  });
  assertEquals(bestEffortPlatformIp(headers), "203.0.113.8");
});

Deno.test("service selection keeps legacy intake and repeated ordered services", () => {
  const first = "c768f9f5-5551-4c8f-8986-5a8754f25b29";
  const second = "c2499f36-c3f4-4f80-80dd-31ba2b581f78";
  assertEquals(cleanServiceIds(undefined, first), [first]);
  assertEquals(cleanServiceIds(undefined, ""), []);
  assertEquals(cleanServiceIds([first, second], first), [first, second]);
  assertEquals(cleanServiceIds([first, first], first), [first, first]);
  assertEquals(cleanServiceIds([second], first), null);
  assertEquals(cleanServiceIds([], first), null);
  assertEquals(cleanServiceIds([first, "bad-id"], first), null);
  assertEquals(
    cleanServiceIds(
      Array.from({ length: 9 }, () => crypto.randomUUID()),
      first,
    ),
    null,
  );
  assertEquals(
    bookingRequestOutcomeResponse("invalid_bundle_total").status,
    400,
  );
});
