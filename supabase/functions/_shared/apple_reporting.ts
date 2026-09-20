type JsonObject = Record<string, unknown>;

export type ReportingMetric = {
  metric_date: string;
  category: string;
  metric_name: string;
  metric_value: number;
  dimension_type: string;
  dimension_value: string;
};

type BetaTesterResource = {
  attributes?: {
    state?: string;
    inviteType?: string;
  };
};

type BetaUsageResource = {
  dataPoints?: Array<{
    values?: {
      crashCount?: number;
      feedbackCount?: number;
      sessionCount?: number;
    };
  }>;
};

function base64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/u, "");
}

function encodeJson(value: JsonObject) {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function pemToPkcs8(privateKeyPem: string) {
  const encoded = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/gu, "")
    .replace(/-----END PRIVATE KEY-----/gu, "")
    .replace(/\s/gu, "");
  if (!encoded) throw new Error("apple_private_key_invalid");
  const binary = atob(encoded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export async function createAppStoreConnectJwt(input: {
  issuerId: string;
  keyId: string;
  privateKeyPem: string;
  now?: Date;
}) {
  const issuedAt = Math.floor((input.now ?? new Date()).getTime() / 1000);
  const header = encodeJson({ alg: "ES256", kid: input.keyId, typ: "JWT" });
  const payload = encodeJson({
    iss: input.issuerId,
    iat: issuedAt,
    exp: issuedAt + 15 * 60,
    aud: "appstoreconnect-v1",
  });
  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(input.privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

function normalizedCount(value: unknown) {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.max(0, value)
    : 0;
}

export function buildTestFlightMetrics(input: {
  metricDate: string;
  testers: BetaTesterResource[];
  usages: BetaUsageResource[];
}): ReportingMetric[] {
  const states = new Map<string, number>();
  const inviteTypes = new Map<string, number>();
  for (const tester of input.testers) {
    const state = tester.attributes?.state?.toLowerCase() ?? "unknown";
    const inviteType = tester.attributes?.inviteType?.toLowerCase() ??
      "unknown";
    states.set(state, (states.get(state) ?? 0) + 1);
    inviteTypes.set(inviteType, (inviteTypes.get(inviteType) ?? 0) + 1);
  }

  let sessions = 0;
  let crashes = 0;
  let feedback = 0;
  for (const usage of input.usages) {
    for (const point of usage.dataPoints ?? []) {
      sessions += normalizedCount(point.values?.sessionCount);
      crashes += normalizedCount(point.values?.crashCount);
      feedback += normalizedCount(point.values?.feedbackCount);
    }
  }

  const metric = (
    category: string,
    metricName: string,
    metricValue: number,
  ): ReportingMetric => ({
    metric_date: input.metricDate,
    category,
    metric_name: metricName,
    metric_value: metricValue,
    dimension_type: "all",
    dimension_value: "all",
  });

  return [
    metric(
      "beta_distribution",
      "testflight_testers_total",
      input.testers.length,
    ),
    metric(
      "beta_distribution",
      "testflight_testers_invited",
      states.get("invited") ?? 0,
    ),
    metric(
      "beta_distribution",
      "testflight_testers_accepted",
      states.get("accepted") ?? 0,
    ),
    metric(
      "beta_distribution",
      "testflight_testers_installed",
      states.get("installed") ?? 0,
    ),
    metric(
      "beta_distribution",
      "testflight_testers_revoked",
      states.get("revoked") ?? 0,
    ),
    metric(
      "beta_distribution",
      "testflight_public_link_testers",
      inviteTypes.get("public_link") ?? 0,
    ),
    metric(
      "beta_distribution",
      "testflight_email_testers",
      inviteTypes.get("email") ?? 0,
    ),
    metric("beta_engagement", "testflight_sessions_365d", sessions),
    metric("beta_reliability", "testflight_crashes_365d", crashes),
    metric("beta_feedback", "testflight_feedback_365d", feedback),
  ];
}

type AppleCollectionPage<T> = {
  data?: T[];
  links?: { next?: string };
};

export async function fetchAppleCollection<T>(input: {
  initialUrl: string;
  token: string;
  fetcher?: typeof fetch;
}) {
  const fetcher = input.fetcher ?? fetch;
  const records: T[] = [];
  let nextUrl: string | undefined = input.initialUrl;
  let pages = 0;
  while (nextUrl && pages < 20) {
    const response = await fetcher(nextUrl, {
      headers: { Authorization: `Bearer ${input.token}` },
    });
    if (!response.ok) throw new Error(`apple_api_http_${response.status}`);
    const page = await response.json() as AppleCollectionPage<T>;
    records.push(...(Array.isArray(page.data) ? page.data : []));
    nextUrl = page.links?.next;
    pages += 1;
  }
  if (nextUrl) throw new Error("apple_api_pagination_limit");
  return records;
}

export type { BetaTesterResource, BetaUsageResource };
