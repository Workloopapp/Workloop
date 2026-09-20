import {
  approximateCoordinates,
  currentForecast,
  ForecastCache,
} from "./forecast.ts";

function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
function sample(now: Date, symbol = "rain") {
  return {
    properties: {
      meta: {
        units: { air_temperature: "celsius" },
        updated_at: now.toISOString(),
      },
      timeseries: [{
        time: new Date(now.getTime() - 30 * 60000).toISOString(),
        data: {
          instant: { details: { air_temperature: 14 } },
          next_1_hours: { summary: { symbol_code: symbol } },
        },
      }],
    },
  };
}
const now = new Date("2026-09-05T17:00:00Z");

Deno.test("coordinates are validated and rounded before upstream", () => {
  const area = approximateCoordinates(51.507351, -.127758);
  assert(area.lat === "51.51" && area.lon === "-0.13");
  for (const input of [NaN, Infinity, "51", 91]) {
    let failed = false;
    try {
      approximateCoordinates(input, 0);
    } catch {
      failed = true;
    }
    assert(failed);
  }
});
Deno.test("current-hour forecast rejects stale absent or different-unit data", () => {
  assert(
    currentForecast(sample(now), now, now.toISOString()).symbol === "rain",
  );
  for (
    const value of [sample(new Date(now.getTime() - 3 * 3600000)), {}, {
      properties: {
        ...sample(now).properties,
        meta: { units: { air_temperature: "fahrenheit" } },
      },
    }]
  ) {
    let failed = false;
    try {
      currentForecast(value, now, now.toISOString());
    } catch {
      failed = true;
    }
    assert(failed);
  }
});
Deno.test("cache coalesces calls, honors Expires and uses conditional requests", async () => {
  let calls = 0;
  let seenUrl = "";
  let conditional = "";
  const cache = new ForecastCache(
    (async (url: any, options: any) => {
      calls++;
      seenUrl = url.toString();
      conditional = options.headers["If-Modified-Since"];
      assert(options.headers["User-Agent"].includes("support@workloop.uk"));
      return new Response(calls === 1 ? JSON.stringify(sample(now)) : null, {
        status: calls === 1 ? 200 : 304,
        headers: {
          "Expires": new Date(now.getTime() + 20 * 60000).toUTCString(),
          "Last-Modified": now.toUTCString(),
        },
      });
    }) as typeof fetch,
  );
  await Promise.all([
    cache.get(51.50735, -.12775, now),
    cache.get(51.50735, -.12775, now),
  ]);
  await cache.get(51.50735, -.12775, new Date(now.getTime() + 19 * 60000));
  assert(calls === 1);
  assert(seenUrl.endsWith("lat=51.51&lon=-0.13"));
  await cache.get(51.50735, -.12775, new Date(now.getTime() + 21 * 60000));
  assert(Number(calls) === 2 && conditional === now.toUTCString());
});
Deno.test("upstream throttling backs off across areas rather than retrying aggressively", async () => {
  let calls = 0;
  const cache = new ForecastCache(
    (async () => {
      calls++;
      return new Response(null, { status: 429 });
    }) as typeof fetch,
  );
  for (const latitude of [51, 52]) {
    let failed = false;
    try {
      await cache.get(latitude, 0, now);
    } catch {
      failed = true;
    }
    assert(failed);
  }
  assert(calls === 1);
});
