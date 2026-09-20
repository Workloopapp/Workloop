import {
  createLocalJWKSet,
  exportJWK,
  exportPKCS8,
  generateKeyPair,
  jwtVerify,
  SignJWT,
} from "npm:jose@6.2.12";
import {
  appleIdentity,
  AppleIdentityMismatch,
  revokeAppleAccount,
  verifyAppleDeletionIdentity,
} from "./apple_account_revocation.ts";
function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
const appleKey = await generateKeyPair("RS256");
const jwk = await exportJWK(appleKey.publicKey);
const keys = createLocalJWKSet({
  keys: [{ ...jwk, kid: "apple-fixture", alg: "RS256" }],
});
const clientKey = await generateKeyPair("ES256", { extractable: true });
const pem = await exportPKCS8(clientKey.privateKey);
async function token(
  overrides: Record<string, unknown> = {},
  signingKey = appleKey.privateKey,
) {
  const now = Math.floor(Date.now() / 1000);
  return await new SignJWT({
    iss: "https://appleid.apple.com",
    aud: "com.ismaeel.workloop",
    sub: "trusted-apple-owner",
    iat: now,
    exp: now + 300,
    ...overrides,
  })
    .setProtectedHeader({ alg: "RS256", kid: "apple-fixture" }).sign(
      signingKey,
    );
}
const env: Record<string, string> = {
  APPLE_SIGN_IN_TEAM_ID: "TESTTEAM",
  APPLE_SIGN_IN_KEY_ID: "TESTKEY",
  APPLE_SIGN_IN_CLIENT_ID: "com.ismaeel.workloop",
  APPLE_SIGN_IN_PRIVATE_KEY: pem,
};
async function exercise(
  options: {
    signedToken?: string;
    exchangeStatus?: number;
    revokeStatus?: number;
    throwAt?: string;
    code?: string;
    linked?: boolean;
    missingConfig?: boolean;
  } = {},
) {
  const calls: string[] = [];
  const result = await revokeAppleAccount({
    linked: options.linked ?? true,
    subject: "trusted-apple-owner",
    authorizationCode: options.code ?? "single-use-fixture",
  }, {
    readEnv: (name) => options.missingConfig ? undefined : env[name],
    verifyIdentity: (value, subject) =>
      verifyAppleDeletionIdentity(value, subject, keys),
    fetcher: (async (url, init) => {
      const path = new URL(String(url)).pathname;
      calls.push(path);
      assert(init?.method === "POST");
      const form = new URLSearchParams(String(init?.body));
      assert(form.get("client_id") === "com.ismaeel.workloop");
      assert(
        !form.has("redirect_uri"),
        "native code must not use OAuth redirect URI",
      );
      const { payload } = await jwtVerify(
        form.get("client_secret")!,
        clientKey.publicKey,
        {
          algorithms: ["ES256"],
          issuer: "TESTTEAM",
          audience: "https://appleid.apple.com",
          subject: "com.ismaeel.workloop",
        },
      );
      assert(
        payload.exp! - payload.iat! === 300,
        "client secret must be short lived",
      );
      if (path === options.throwAt) throw new Error("fixture timeout");
      if (path === "/auth/token") {
        assert(form.get("grant_type") === "authorization_code");
        return new Response(
          JSON.stringify({
            id_token: options.signedToken ?? await token(),
            refresh_token: "ephemeral-refresh-fixture",
          }),
          { status: options.exchangeStatus ?? 200 },
        );
      }
      assert(form.get("token_type_hint") === "refresh_token");
      assert(form.get("token") === "ephemeral-refresh-fixture");
      return new Response(null, { status: options.revokeStatus ?? 200 });
    }) as typeof fetch,
  });
  return { result, calls };
}

Deno.test("Apple identity derives from linked server identities, including mixed providers", () => {
  assert(
    appleIdentity([{ provider: "email" }, {
      provider: "apple",
      identity_data: { sub: "owner" },
    }]).subject === "owner",
  );
  assert(
    !appleIdentity([{
      provider: "email",
      identity_data: { sub: "apple-looking" },
    }]).linked,
  );
  assert(
    appleIdentity([{ provider: "apple", identity_data: { sub: "a" } }, {
      provider: "apple",
      identity_data: { sub: "b" },
    }]).subject === null,
  );
});
Deno.test("native Apple exchange verifies identity and revokes only returned refresh token", async () => {
  const { result, calls } = await exercise();
  assert(result === "revoked");
  assert(calls.join() === "/auth/token,/auth/revoke");
});
Deno.test("Apple missing code or configuration preserves truthful manual deletion route", async () => {
  assert(
    await revokeAppleAccount({ linked: true, subject: "owner" }) ===
      "manual_action_required",
  );
  const x = await exercise({ missingConfig: true });
  assert(x.result === "manual_action_required" && x.calls.length === 0);
  assert(
    await revokeAppleAccount({ linked: false, subject: null }) ===
      "not_applicable",
  );
});
Deno.test("wrong Apple subject is a hard stop before revoking any credential", async () => {
  const value = await token({ sub: "someone-else" });
  let revokeCalled = false;
  try {
    await revokeAppleAccount({
      linked: true,
      subject: "trusted-apple-owner",
      authorizationCode: "fixture",
    }, {
      readEnv: (n) => env[n],
      verifyIdentity: (v, s) => verifyAppleDeletionIdentity(v, s, keys),
      // deno-lint-ignore require-await
      fetcher: (async (url) => {
        if (String(url).endsWith("/revoke")) revokeCalled = true;
        return Response.json({ id_token: value, refresh_token: "fixture" });
      }) as typeof fetch,
    });
    throw new Error("wrong subject accepted");
  } catch (e) {
    assert(e instanceof AppleIdentityMismatch);
  }
  assert(!revokeCalled);
});
for (
  const [name, claims] of Object.entries({
    issuer: { iss: "https://wrong.example" },
    audience: { aud: "web-service-id" },
    expired: { exp: 1 },
    stale: { iat: 1 },
    future: { iat: Math.floor(Date.now() / 1000) + 600 },
  })
) {
  Deno.test(`invalid Apple ${name} never reaches revocation`, async () => {
    const x = await exercise({ signedToken: await token(claims) });
    assert(
      x.result === "manual_action_required" && x.calls.join() === "/auth/token",
    );
  });
}
Deno.test("wrong Apple signature never reaches revocation", async () => {
  const other = await generateKeyPair("RS256");
  const x = await exercise({ signedToken: await token({}, other.privateKey) });
  assert(x.result === "manual_action_required" && x.calls.length === 1);
});
for (
  const options of [{ exchangeStatus: 400 }, { throwAt: "/auth/token" }, {
    revokeStatus: 503,
  }, { throwAt: "/auth/revoke" }]
) {
  Deno.test(`provider failure has manual fallback with no code re-exchange: ${JSON.stringify(options)}`, async () => {
    const x = await exercise(options);
    assert(x.result === "manual_action_required");
    assert(x.calls.filter((p) => p === "/auth/token").length === 1);
  });
}
