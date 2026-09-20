import {
  buildTestFlightMetrics,
  createAppStoreConnectJwt,
  fetchAppleCollection,
} from "./apple_reporting.ts";

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("buildTestFlightMetrics stores aggregates without tester identity", () => {
  const metrics = buildTestFlightMetrics({
    metricDate: "2026-08-31",
    testers: [
      { attributes: { state: "INSTALLED", inviteType: "PUBLIC_LINK" } },
      { attributes: { state: "ACCEPTED", inviteType: "EMAIL" } },
    ],
    usages: [
      {
        dataPoints: [{
          values: { sessionCount: 8, crashCount: 1, feedbackCount: 2 },
        }],
      },
      {
        dataPoints: [{
          values: { sessionCount: 3, crashCount: 0, feedbackCount: 1 },
        }],
      },
    ],
  });
  const values = Object.fromEntries(
    metrics.map((item) => [item.metric_name, item.metric_value]),
  );
  assertEquals(values.testflight_testers_total, 2);
  assertEquals(values.testflight_testers_installed, 1);
  assertEquals(values.testflight_sessions_365d, 11);
  assertEquals(values.testflight_crashes_365d, 1);
  assertEquals(values.testflight_feedback_365d, 3);
  assertEquals(JSON.stringify(metrics).includes("email"), true);
  assertEquals(JSON.stringify(metrics).includes("PUBLIC_LINK"), false);
});

Deno.test("fetchAppleCollection follows bounded pagination", async () => {
  const urls: string[] = [];
  const fetcher = ((url: string | URL | Request) => {
    urls.push(String(url));
    const body = String(url).endsWith("page=2")
      ? { data: [{ id: "second" }], links: {} }
      : {
        data: [{ id: "first" }],
        links: { next: "https://example.test?page=2" },
      };
    return Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));
  }) as typeof fetch;
  const records = await fetchAppleCollection<{ id: string }>({
    initialUrl: "https://example.test?page=1",
    token: "token",
    fetcher,
  });
  assertEquals(records, [{ id: "first" }, { id: "second" }]);
  assertEquals(urls.length, 2);
});

Deno.test("createAppStoreConnectJwt creates a short-lived ES256 token", async () => {
  const keyPair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", keyPair.privateKey),
  );
  let binary = "";
  for (const byte of pkcs8) binary += String.fromCharCode(byte);
  const encoded = btoa(binary).match(/.{1,64}/gu)?.join("\n") ?? "";
  const token = await createAppStoreConnectJwt({
    issuerId: "issuer",
    keyId: "key",
    privateKeyPem:
      `-----BEGIN PRIVATE KEY-----\n${encoded}\n-----END PRIVATE KEY-----`,
    now: new Date("2026-08-31T12:00:00Z"),
  });
  const [header, payload, signature] = token.split(".");
  const decode = (value: string) =>
    JSON.parse(
      atob(value.replaceAll("-", "+").replaceAll("_", "/")),
    );
  assertEquals(decode(header).alg, "ES256");
  assertEquals(decode(payload).aud, "appstoreconnect-v1");
  assertEquals(decode(payload).exp - decode(payload).iat, 900);
  assertEquals(Boolean(signature), true);
});
