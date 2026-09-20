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
const uid = "a4500000-0000-4000-8000-000000000001";
const wid = "a4500000-0000-4000-8000-000000000021";
const requestId = "a4500000-0000-4000-8000-000000000031";
const adminToken = "deletion-fixture-credential-32-characters";
async function exercise(
  options: {
    workspace?: string | null;
    foreignMembership?: boolean;
    shared?: boolean;
    suppliedToken?: string;
    configuredToken?: string;
  } = {},
) {
  const names = [
    "SUPABASE_URL",
    "SUPABASE_SERVICE_ROLE_KEY",
    "ACCOUNT_DELETION_ADMIN_TOKEN",
  ];
  const values = [
    "https://project.example",
    "fixture-service",
    options.configuredToken ?? adminToken,
  ];
  const old = names.map((n) => Deno.env.get(n));
  const previousFetch = fetch;
  names.forEach((n, i) => Deno.env.set(n, values[i]));
  const calls: Array<
    {
      path: string;
      method: string;
      body: Record<string, unknown> | null;
      search: string;
    }
  > = [];
  const workspace = options.workspace ?? null;
  // deno-lint-ignore require-await
  globalThis.fetch = (async (input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const method = init?.method ?? "GET";
    const body = init?.body ? JSON.parse(String(init.body)) : null;
    calls.push({ path: url.pathname, method, body, search: url.search });
    if (url.pathname.endsWith("/account_deletion_requests")) {
      if (method === "GET") {
        return Response.json({
          id: requestId,
          workspace_id: workspace,
          user_id: uid,
          requested_by_user_id: uid,
          email: "fixture@example.invalid",
          status: "requested",
          requested_at: new Date().toISOString(),
          processing_started_at: null,
        });
      }
      return url.searchParams.has("select")
        ? Response.json({ id: requestId })
        : new Response(null, { status: 204 });
    }
    if (url.pathname.endsWith("/workspace_members")) {
      if (url.searchParams.has("user_id")) {
        return Response.json(
          options.foreignMembership
            ? [{ workspace_id: uid }]
            : workspace
            ? [{ workspace_id: workspace }]
            : [],
        );
      }
      return Response.json(
        options.shared
          ? [{ user_id: uid }, { user_id: wid }]
          : [{ user_id: uid }],
      );
    }
    if (url.pathname.endsWith("/workspace_payment_accounts")) {
      return Response.json(null);
    }
    if (url.pathname === `/auth/v1/admin/users/${uid}`) {
      return Response.json({ id: uid });
    }
    if (url.pathname.startsWith("/storage/v1/object/list/")) {
      return Response.json([]);
    }
    if (
      url.pathname.endsWith("/workspaces") ||
      url.pathname.endsWith("/account_deletion_audit")
    ) return new Response(null, { status: 204 });
    throw new Error(`Unexpected boundary ${url.pathname}`);
  }) as typeof fetch;
  try {
    const response = await handler!(
      new Request("https://edge.example/complete-account-deletion", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-admin-token": options.suppliedToken ?? adminToken,
        },
        body: JSON.stringify({ requestId }),
      }),
    );
    return { status: response.status, body: await response.json(), calls };
  } finally {
    globalThis.fetch = previousFetch;
    names.forEach((n, i) =>
      old[i] === undefined ? Deno.env.delete(n) : Deno.env.set(n, old[i]!)
    );
  }
}
Deno.test("pre-onboarding completion deletes only intended Auth and own logo namespace", async () => {
  const x = await exercise();
  assert(x.status === 200 && x.body.authUserDeleted === true);
  const objects = x.calls.filter((c) => c.path.startsWith("/storage/"));
  assert(
    objects.length === 1 && objects[0].path.endsWith("business-logos") &&
      objects[0].body?.prefix === uid,
  );
  assert(
    !x.calls.some((c) =>
      c.path.endsWith("/workspaces") || c.path.endsWith("expense-receipts") ||
      c.path.endsWith("record-attachments")
    ),
  );
  assert(
    x.calls.some((c) =>
      c.path === `/auth/v1/admin/users/${uid}` && c.method === "DELETE"
    ),
  );
});
Deno.test("account-only completion refuses late membership in any business", async () => {
  const x = await exercise({ foreignMembership: true });
  assert(x.status === 409);
  assert(!x.calls.some((c) => c.method !== "GET"));
});
Deno.test("workspace completion still refuses a shared workspace", async () => {
  const x = await exercise({ workspace: wid, shared: true });
  assert(x.status === 409);
  assert(!x.calls.some((c) => c.method !== "GET"));
});
Deno.test("existing sole-owned workspace completion retains scoped cleanup", async () => {
  const x = await exercise({ workspace: wid });
  assert(x.status === 200);
  const deletion = x.calls.find((c) =>
    c.path.endsWith("/workspaces") && c.method === "DELETE"
  );
  assert(deletion?.search.includes(wid));
  for (
    const c of x.calls.filter((c) =>
      c.path.endsWith("expense-receipts") ||
      c.path.endsWith("record-attachments")
    )
  ) assert(c.body?.prefix === wid);
});
Deno.test("invalid administrative token rejects before all account/provider work", async () => {
  const x = await exercise({ suppliedToken: "wrong" });
  assert(x.status === 401 && x.calls.length === 0);
});
Deno.test("unconfigured administrative token rejects even an empty supplied token", async () => {
  const x = await exercise({ configuredToken: "", suppliedToken: "" });
  assert(x.status === 401 && x.calls.length === 0);
});
Deno.test("existing nonempty administrative credentials remain compatible", async () => {
  const x = await exercise({
    configuredToken: "legacy-fixture-secret",
    suppliedToken: "legacy-fixture-secret",
  });
  assert(x.status === 200);
});
