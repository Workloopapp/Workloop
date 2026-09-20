type Handler = (request: Request) => Promise<Response>;
let handler: Handler;
const serve = Deno.serve;
try {
  Deno.serve = ((callback: Handler) => {
    handler = callback;
  }) as unknown as typeof Deno.serve;
  await import("./index.ts");
} finally {
  Deno.serve = serve;
}
function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
const uid = "a4400000-0000-4000-8000-000000000001";
const sid = "a4400000-0000-4000-8000-000000000011";
const wid = "a4400000-0000-4000-8000-000000000021";
const jwt = `e30.${
  btoa(JSON.stringify({ sub: uid, session_id: sid, aal: "aal1" }))
}.fixture`;
async function exercise(
  options: {
    body?: unknown;
    raw?: string;
    auth?: boolean;
    active?: boolean;
    mfa?: boolean;
    workspaces?: string[];
    shared?: boolean;
    apple?: boolean;
    rpcError?: boolean;
    banError?: boolean;
  } = {},
) {
  const previousFetch = fetch;
  const names = [
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
  ];
  const oldEnv = names.map((n) => Deno.env.get(n));
  ["https://project.example", "fixture-anon", "fixture-service"].forEach((
    v,
    i,
  ) => Deno.env.set(names[i], v));
  const calls: string[] = [];
  let deletionParams: Record<string, unknown> | null = null;
  const json = (data: unknown, status = 200) => Response.json(data, { status });
  // deno-lint-ignore require-await
  globalThis.fetch = (async (input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    calls.push(url.pathname);
    if (url.pathname === "/auth/v1/user") {
      return options.auth === false
        ? json({ error: "unauthorized", message: "unauthorized" }, 401)
        : json({
          id: uid,
          email: "fixture@example.invalid",
          identities: options.apple
            ? [{
              provider: "apple",
              identity_data: { sub: "trusted-apple-owner" },
            }]
            : [{ provider: "email" }],
          user_metadata: { provider: "apple", sub: "untrusted" },
        });
    }
    if (url.pathname.endsWith("/current_user_session_is_active")) {
      return json(options.active ?? true);
    }
    if (url.pathname.endsWith("/current_user_meets_mfa_policy")) {
      return json(options.mfa ?? true);
    }
    if (url.pathname.endsWith("/workspace_members")) {
      if (url.searchParams.has("user_id")) {
        return json(
          (options.workspaces ?? []).map((id) => ({ workspace_id: id })),
        );
      }
      return json(
        options.shared
          ? [{ user_id: uid }, { user_id: "someone-else" }]
          : [{ user_id: uid }],
      );
    }
    if (url.pathname.endsWith("/request_account_deletion_for_user")) {
      deletionParams = JSON.parse(String(init?.body));
      if (options.rpcError) {
        return json({
          code: "28000",
          message: "session expired during exchange",
        }, 400);
      }
      return json({
        ok: true,
        requestId: "fixture-request",
        status: "requested",
        accessLocked: true,
        appleRevocation: deletionParams!.p_apple_revocation,
      });
    }
    if (url.pathname === `/auth/v1/admin/users/${uid}`) {
      return options.banError
        ? json({ message: "temporary unavailable" }, 503)
        : json({ id: uid });
    }
    throw new Error(
      `Unexpected network boundary ${url.hostname}${url.pathname}`,
    );
  }) as typeof fetch;
  try {
    const result = await handler!(
      new Request("https://edge.example/request-account-deletion", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${jwt}`,
          "Content-Type": "application/json",
        },
        body: options.raw ?? JSON.stringify(options.body ?? {}),
      }),
    );
    return {
      status: result.status,
      body: await result.json(),
      calls,
      deletionParams: deletionParams as Record<string, unknown> | null,
    };
  } finally {
    globalThis.fetch = previousFetch;
    names.forEach((n, i) =>
      oldEnv[i] === undefined ? Deno.env.delete(n) : Deno.env.set(n, oldEnv[i]!)
    );
  }
}
Deno.test("no-workspace account deletes through caller-bound transaction", async () => {
  const x = await exercise();
  assert(x.status === 200 && x.body.accessLocked === true);
  assert(
    x.deletionParams?.p_user_id === uid &&
      x.deletionParams?.p_session_id === sid,
  );
  assert(x.deletionParams?.p_workspace_id === null);
  assert(
    x.body.appleRevocation === "not_applicable",
    "metadata must not fake Apple provider linkage",
  );
});
Deno.test("omitting workspace still includes the server-derived existing business", async () => {
  const x = await exercise({ workspaces: [wid] });
  assert(x.status === 200 && x.deletionParams?.p_workspace_id === wid);
});
Deno.test("legacy explicit workspace contract remains accepted for its sole owner", async () => {
  const x = await exercise({ workspaces: [wid], body: { workspaceId: wid } });
  assert(x.status === 200);
});
for (
  const [name, options, status] of [
    ["unauthenticated", { auth: false }, 401],
    ["revoked session", { active: false }, 401],
    ["MFA incomplete", { mfa: false }, 403],
    ["foreign workspace", {
      body: { workspaceId: wid, appleAuthorizationCode: "unused" },
    }, 403],
    ["shared workspace", { workspaces: [wid], shared: true }, 403],
    ["multiple workspaces", { workspaces: [wid, uid] }, 409],
  ] as const
) {
  Deno.test(`${name} cannot queue deletion or ban Auth`, async () => {
    const x = await exercise(options as Parameters<typeof exercise>[0]);
    assert(x.status === status && x.deletionParams === null);
    assert(!x.calls.some((p) => p.includes("/admin/users/")));
  });
}
Deno.test("linked Apple account without code retains explicit manual unlink status", async () => {
  const x = await exercise({ apple: true });
  assert(
    x.status === 200 && x.body.appleRevocation === "manual_action_required",
  );
});
Deno.test("Apple credential for account without linked Apple identity cannot delete or revoke", async () => {
  const x = await exercise({
    body: { appleAuthorizationCode: "wrong-linked-account" },
  });
  assert(
    x.status === 409 && x.body.code === "apple_identity_mismatch" &&
      x.deletionParams === null,
  );
});
Deno.test("session race rejects final transaction before Auth ban", async () => {
  const x = await exercise({ rpcError: true });
  assert(x.status === 401 && !x.calls.some((p) => p.includes("/admin/users/")));
});
Deno.test("transient Auth-ban failure preserves successful atomic access lock", async () => {
  const x = await exercise({ banError: true });
  assert(x.status === 200 && x.body.accessLocked === true);
});
Deno.test("invalid or oversized deletion bodies fail before Auth/network work", async () => {
  for (
    const raw of [
      "[]",
      "null",
      "{",
      JSON.stringify({ padding: "x".repeat(20000) }),
    ]
  ) {
    const x = await exercise({ raw });
    assert(x.status === 400 && x.calls.length === 0);
  }
});
