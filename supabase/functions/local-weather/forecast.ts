export type ForecastReading = {
  temperature: number;
  symbol: string;
  validAt: string;
  updatedAt: string;
  expiresAt: string;
};

export function approximateCoordinates(latitude: unknown, longitude: unknown) {
  if (
    typeof latitude !== "number" || typeof longitude !== "number" ||
    !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
    Math.abs(latitude) > 90 || Math.abs(longitude) > 180
  ) {
    throw new Error("invalid_coordinates");
  }
  return { lat: latitude.toFixed(2), lon: longitude.toFixed(2) };
}

export function currentForecast(
  body: any,
  now: Date,
  expiresAt: string,
): ForecastReading {
  const properties = body?.properties;
  if (
    properties?.meta?.units?.air_temperature !== "celsius" ||
    !Array.isArray(properties.timeseries)
  ) throw new Error("invalid_forecast");
  const updated = Date.parse(properties.meta.updated_at);
  if (
    !Number.isFinite(updated) || now.getTime() - updated > 12 * 3600000 ||
    updated - now.getTime() > 3600000
  ) throw new Error("outdated_forecast");
  // Select the current hour, never an arbitrary future forecast or old day.
  const point = properties.timeseries.filter((item: any) => {
    const age = now.getTime() - Date.parse(item.time);
    return age >= 0 && age <= 90 * 60000;
  }).sort((a: any, b: any) => Date.parse(b.time) - Date.parse(a.time))[0];
  const temperature = point?.data?.instant?.details?.air_temperature;
  const symbol = point?.data?.next_1_hours?.summary?.symbol_code ??
    point?.data?.next_6_hours?.summary?.symbol_code;
  if (
    typeof temperature !== "number" || !Number.isFinite(temperature) ||
    temperature < -100 || temperature > 65 || typeof symbol !== "string" ||
    !/^[a-z_]{2,60}$/.test(symbol)
  ) throw new Error("missing_current_forecast");
  return {
    temperature,
    symbol,
    validAt: point.time,
    updatedAt: properties.meta.updated_at,
    expiresAt,
  };
}

type CacheEntry = { body: unknown; expires: number; modified: string | null };

/** Bounded warm-instance cache, backed by foreground-only client caching. */
export class ForecastCache {
  private entries = new Map<string, CacheEntry>();
  private pending = new Map<string, Promise<CacheEntry>>();
  private backoffUntil = 0;

  private fetcher: typeof fetch;
  constructor(fetcher: typeof fetch = fetch) {
    this.fetcher = fetcher;
  }

  async get(latitude: number, longitude: number, now = new Date()) {
    const { lat, lon } = approximateCoordinates(latitude, longitude);
    const key = `${lat},${lon}`;
    let entry = this.entries.get(key);
    if (!entry || entry.expires <= now.getTime()) {
      if (now.getTime() < this.backoffUntil) throw new Error("weather_backoff");
      let pending = this.pending.get(key);
      if (!pending) {
        pending = this.refresh(key, lat, lon, entry, now);
        this.pending.set(key, pending);
      }
      try {
        entry = await pending;
      } finally {
        this.pending.delete(key);
      }
    }
    return currentForecast(
      entry.body,
      now,
      new Date(entry.expires).toISOString(),
    );
  }

  private async refresh(
    key: string,
    lat: string,
    lon: string,
    previous: CacheEntry | undefined,
    now: Date,
  ) {
    const headers: Record<string, string> = {
      "User-Agent": "Workloop/1.0 https://workloop.uk support@workloop.uk",
      "Accept": "application/json",
    };
    if (previous?.modified) headers["If-Modified-Since"] = previous.modified;
    const response = await this.fetcher(
      `https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=${lat}&lon=${lon}`,
      { headers, signal: AbortSignal.timeout(6000) },
    );
    if (response.status === 429 || response.status === 403) {
      const retry = Number(response.headers.get("Retry-After"));
      this.backoffUntil = now.getTime() +
        Math.max(15 * 60000, Number.isFinite(retry) ? retry * 1000 : 0);
      throw new Error("weather_backoff");
    }
    if (
      response.status !== 200 && response.status !== 203 &&
      !(response.status === 304 && previous)
    ) throw new Error("weather_unavailable");
    const expiry = Date.parse(response.headers.get("Expires") ?? "");
    // Never refresh sooner than the upstream Expires header, or ten minutes.
    const expires = Math.max(
      now.getTime() + 10 * 60000,
      Number.isFinite(expiry) ? expiry : 0,
    );
    const body = response.status === 304
      ? previous!.body
      : await response.json();
    currentForecast(body, now, new Date(expires).toISOString());
    const entry = {
      body,
      expires,
      modified: response.headers.get("Last-Modified") ?? previous?.modified ??
        null,
    };
    this.entries.delete(key);
    if (this.entries.size >= 100) {
      this.entries.delete(this.entries.keys().next().value!);
    }
    this.entries.set(key, entry);
    return entry;
  }
}
