import {
  createRemoteJWKSet,
  importPKCS8,
  jwtVerify,
  SignJWT,
} from "npm:jose@6.2.12";
import type { JWTVerifyGetKey } from "npm:jose@6.2.12";

const issuer = "https://appleid.apple.com";
const nativeClientId = "com.ismaeel.workloop";
const appleKeys = createRemoteJWKSet(new URL(`${issuer}/auth/keys`), {
  timeoutDuration: 5000,
});
export type AppleRevocationStatus =
  | "not_applicable"
  | "revoked"
  | "manual_action_required";
export class AppleIdentityMismatch extends Error {}

/** Only identities returned by Auth getUser are trusted, never user metadata. */
export function appleIdentity(
  identities: Array<
    { provider?: string; identity_data?: Record<string, unknown> }
  > = [],
) {
  const apple = identities.filter((identity) => identity.provider === "apple");
  const subjects = [
    ...new Set(
      apple.map((identity) => identity.identity_data?.sub)
        .filter((sub): sub is string =>
          typeof sub === "string" && sub.length > 0
        ),
    ),
  ];
  return {
    linked: apple.length > 0,
    subject: subjects.length === 1 ? subjects[0] : null,
  };
}

export async function verifyAppleDeletionIdentity(
  token: string,
  expectedSubject: string,
  keys: JWTVerifyGetKey = appleKeys,
) {
  const { payload } = await jwtVerify(token, keys, {
    algorithms: ["RS256"],
    issuer,
    audience: nativeClientId,
    requiredClaims: ["sub", "iat", "exp"],
    maxTokenAge: "10m",
    clockTolerance: 30,
  });
  if (payload.sub !== expectedSubject) {
    throw new AppleIdentityMismatch("apple_identity_mismatch");
  }
}

/** Exchanges a native code once; provider tokens never leave this request. */
export async function revokeAppleAccount(input: {
  linked: boolean;
  subject: string | null;
  authorizationCode?: string;
}, dependencies: {
  readEnv?: (name: string) => string | undefined;
  fetcher?: typeof fetch;
  verifyIdentity?: typeof verifyAppleDeletionIdentity;
} = {}): Promise<AppleRevocationStatus> {
  if (!input.linked) {
    if (input.authorizationCode) {
      throw new AppleIdentityMismatch("apple_identity_mismatch");
    }
    return "not_applicable";
  }
  if (!input.authorizationCode || !input.subject) {
    return "manual_action_required";
  }
  const env = dependencies.readEnv ?? Deno.env.get;
  const fetcher = dependencies.fetcher ?? fetch;
  const verifyIdentity = dependencies.verifyIdentity ??
    verifyAppleDeletionIdentity;
  const clientId = env("APPLE_SIGN_IN_CLIENT_ID");
  const team = env("APPLE_SIGN_IN_TEAM_ID");
  const keyId = env("APPLE_SIGN_IN_KEY_ID");
  const privateKey = env("APPLE_SIGN_IN_PRIVATE_KEY");
  if (clientId !== nativeClientId || !team || !keyId || !privateKey) {
    return "manual_action_required";
  }
  try {
    const key = await importPKCS8(privateKey.replace(/\\n/g, "\n"), "ES256");
    const secret = await new SignJWT({}).setProtectedHeader({
      alg: "ES256",
      kid: keyId,
    })
      .setIssuer(team).setSubject(clientId).setAudience(issuer)
      .setIssuedAt().setExpirationTime("5m").sign(key);
    const tokenResponse = await fetcher(`${issuer}/auth/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: secret,
        grant_type: "authorization_code",
        code: input.authorizationCode,
      }),
      signal: AbortSignal.timeout(8000),
    });
    if (!tokenResponse.ok) return "manual_action_required";
    const tokens = await tokenResponse.json();
    if (
      typeof tokens.id_token !== "string" ||
      typeof tokens.refresh_token !== "string" || !tokens.refresh_token
    ) return "manual_action_required";
    await verifyIdentity(tokens.id_token, input.subject);
    const revoked = await fetcher(`${issuer}/auth/revoke`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: secret,
        token: tokens.refresh_token,
        token_type_hint: "refresh_token",
      }),
      signal: AbortSignal.timeout(8000),
    });
    // Apple's empty 200 also covers a token already invalidated.
    return revoked.status === 200 ? "revoked" : "manual_action_required";
  } catch (error) {
    if (error instanceof AppleIdentityMismatch) throw error;
    // TN3194 requires deletion still work when provider credentials are absent.
    // No provider body/code/key/token is logged, stored, or returned.
    return "manual_action_required";
  }
}
