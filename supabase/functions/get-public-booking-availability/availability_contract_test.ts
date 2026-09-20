import { assertEquals, assertMatch } from "jsr:@std/assert@1";

import {
  bestEffortPlatformIp,
  cleanAvailabilityRequest,
  publicAvailabilityResponse,
  sha256Hex,
} from "./availability_contract.ts";

Deno.test("availability request requires a valid public service", () => {
  assertEquals(
    cleanAvailabilityRequest({ handle: "clearview", serviceId: "" }),
    null,
  );
  assertEquals(
    cleanAvailabilityRequest({ handle: "x", serviceId: crypto.randomUUID() }),
    null,
  );
  assertEquals(
    cleanAvailabilityRequest({
      handle: " Clearview ",
      serviceId: "c768f9f5-5551-4c8f-8986-5a8754f25b29",
    }),
    {
      handle: "clearview",
      serviceId: "c768f9f5-5551-4c8f-8986-5a8754f25b29",
      serviceIds: ["c768f9f5-5551-4c8f-8986-5a8754f25b29"],
      addOnIds: [],
      targetDate: null,
    },
  );
  assertEquals(
    cleanAvailabilityRequest({
      handle: "clearview",
      serviceId: "c768f9f5-5551-4c8f-8986-5a8754f25b29",
      addOnIds: ["c2499f36-c3f4-4f80-80dd-31ba2b581f78"],
    })?.addOnIds.length,
    1,
  );
  assertEquals(
    cleanAvailabilityRequest({
      handle: "clearview",
      serviceId: "c768f9f5-5551-4c8f-8986-5a8754f25b29",
      targetDate: "2026-10-14",
    })?.targetDate,
    "2026-10-14",
  );
  assertEquals(
    cleanAvailabilityRequest({
      handle: "clearview",
      serviceId: "c768f9f5-5551-4c8f-8986-5a8754f25b29",
      targetDate: "2026-02-30",
    }),
    null,
  );
});

Deno.test("safe response caps days and slots and strips diary metadata", () => {
  const mapped = publicAvailabilityResponse({
    outcome: "ok",
    timezone: "Europe/London",
    durationMinutes: 60,
    generatedAt: "2026-09-01T12:00:00Z",
    appointmentIds: ["private"],
    busyCount: 4,
    days: Array.from({ length: 8 }, (_, day) => ({
      date: `2026-09-${String(day + 2).padStart(2, "0")}`,
      slots: Array.from(
        { length: 9 },
        (_, slot) =>
          `2026-09-${String(day + 2).padStart(2, "0")}T${
            String(slot + 8).padStart(2, "0")
          }:00:00Z`,
      ),
      busyIntervals: ["private"],
    })),
  });
  assertEquals(mapped.status, 200);
  const body = mapped.body as { days: Array<{ slots: string[] }> };
  assertEquals(body.days.length, 5);
  assertEquals(body.days.every((day) => day.slots.length === 6), true);
  assertEquals(Object.keys(mapped.body).sort(), [
    "days",
    "durationMinutes",
    "generatedAt",
    "timezone",
  ]);
  assertEquals(JSON.stringify(mapped.body).includes("private"), false);
});

Deno.test("availability outcomes do not reveal why a profile is unavailable", () => {
  assertEquals(publicAvailabilityResponse({ outcome: "profile_unavailable" }), {
    status: 404,
    body: { error: "Profile not found" },
  });
  assertEquals(
    publicAvailabilityResponse({ outcome: "invalid_service" }).status,
    400,
  );
  assertEquals(
    publicAvailabilityResponse({ outcome: "invalid_add_on" }).status,
    400,
  );
  assertEquals(
    publicAvailabilityResponse({
      outcome: "rate_limited",
      retryAfterSeconds: 14,
    }),
    {
      status: 429,
      retryAfterSeconds: 14,
      body: { error: "Too many requests. Try again shortly." },
    },
  );
});

Deno.test("source selection prefers platform-observed addresses", () => {
  assertEquals(
    bestEffortPlatformIp(new Headers({ "cf-connecting-ip": "2001:db8::1" })),
    "2001:db8::1",
  );
  assertEquals(
    bestEffortPlatformIp(
      new Headers({ "x-forwarded-for": "bad value, 192.0.2.2" }),
    ),
    "192.0.2.2",
  );
});

Deno.test("source hashes are fixed-size hex and domain separated by caller", async () => {
  const digest = await sha256Hex("availability:test:192.0.2.2");
  assertMatch(digest, /^[0-9a-f]{64}$/);
});

Deno.test("bundle availability retains ordered services and rejects inconsistent primary", () => {
  const first = "c768f9f5-5551-4c8f-8986-5a8754f25b29";
  const second = "c2499f36-c3f4-4f80-80dd-31ba2b581f78";
  assertEquals(
    cleanAvailabilityRequest({
      handle: "clearview",
      serviceId: first,
      serviceIds: [first, second],
    })?.serviceIds,
    [first, second],
  );
  assertEquals(
    cleanAvailabilityRequest({
      handle: "clearview",
      serviceId: first,
      serviceIds: [first, first],
    })?.serviceIds,
    [first, first],
  );
  assertEquals(
    cleanAvailabilityRequest({
      handle: "clearview",
      serviceId: first,
      serviceIds: [second, first],
    }),
    null,
  );
  assertEquals(
    publicAvailabilityResponse({ outcome: "invalid_bundle_total" }).status,
    400,
  );
});
