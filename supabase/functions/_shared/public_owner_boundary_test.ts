type Handler = (request: Request) => Promise<Response>;
const handlers: Record<string, Handler> = {};
const serve = Deno.serve;
for (
  const name of [
    "get-public-profile",
    "create-booking-request",
    "get-public-booking-availability",
  ]
) {
  try {
    Deno.serve = ((callback: Handler) => {
      handlers[name] = callback;
    }) as unknown as typeof Deno.serve;
    await import(`../${name}/index.ts`);
  } finally {
    Deno.serve = serve;
  }
}
function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
const wid = "a4600000-0000-4000-8000-000000000001";
async function exercise(name: string, failingLookup = false) {
  const oldFetch = fetch;
  const names = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"];
  const old = names.map((n) => Deno.env.get(n));
  Deno.env.set(names[0], "https://project.example");
  Deno.env.set(
    names[1],
    "fixture-service-with-more-than-thirty-two-characters",
  );
  const calls: string[] = [];
  // deno-lint-ignore require-await
  globalThis.fetch = (async (input) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    calls.push(url.pathname);
    if (url.pathname.endsWith("/business_profiles")) {
      return Response.json({
        id: wid,
        workspace_id: wid,
        handle: "fixture-owner",
        bio: "private fixture content",
      });
    }
    if (url.pathname.includes("/is_public_")) {
      return failingLookup
        ? Response.json(
          { code: "unavailable", message: "fixture unavailable" },
          { status: 503 },
        )
        : Response.json(false);
    }
    throw new Error(`Inactive owner reached protected work: ${url.pathname}`);
  }) as typeof fetch;
  try {
    const response = await handlers[name](
      new Request(`https://edge.example/${name}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          handle: "fixture-owner",
          serviceId: wid,
          name: "Fixture Customer",
          phone: "+447700900001",
          email: "fixture@example.invalid",
          requestToken: wid,
          preferredTimeText: "Tomorrow",
        }),
      }),
    );
    return { status: response.status, body: await response.text(), calls };
  } finally {
    globalThis.fetch = oldFetch;
    names.forEach((n, i) =>
      old[i] === undefined ? Deno.env.delete(n) : Deno.env.set(n, old[i]!)
    );
  }
}
for (const name of Object.keys(handlers)) {
  Deno.test(`${name} hides an inactive owner before business reads or writes`, async () => {
    const x = await exercise(name);
    assert(x.status === 404, `expected404 got${x.status}`);
    assert(
      !x.body.includes("private fixture content") && !x.body.includes(wid),
    );
    assert(x.calls.some((p) => p.includes("/is_public_")));
  });
  Deno.test(`${name} fails closed if owner verification is unavailable`, async () => {
    const x = await exercise(name, true);
    assert(x.status >= 500);
    assert(!x.body.includes("private fixture content"));
  });
}
