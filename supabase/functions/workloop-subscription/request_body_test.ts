import {
  SubscriptionBodyError,
  subscriptionRequestBody,
} from "./request_body.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
async function rejected(req: Request, status: number, maxBytes = 64000) {
  try {
    await subscriptionRequestBody(req, maxBytes);
  } catch (error) {
    if (!(error instanceof SubscriptionBodyError)) throw error;
    equal(error.status, status);
    return;
  }
  throw new Error("Expected request rejection");
}
const request = (body: BodyInit, headers?: HeadersInit) =>
  new Request("https://example.test/workloop-subscription", {
    method: "POST",
    body,
    headers,
  });

Deno.test("body at the exact byte limit is accepted", async () => {
  equal(await subscriptionRequestBody(request('{"x":"ok"}'), 10), { x: "ok" });
});
Deno.test("split multibyte UTF-8 is decoded without changing signed text", async () => {
  const bytes = new TextEncoder().encode('{"note":"£🎉"}');
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const byte of bytes) controller.enqueue(Uint8Array.of(byte));
      controller.close();
    },
  });
  equal(await subscriptionRequestBody(request(body), bytes.length), {
    note: "£🎉",
  });
});
Deno.test("byte limit is not a character-count limit", async () => {
  await rejected(request('{"x":"£££"}'), 413, 12);
});
Deno.test("oversized header is rejected without reading the body", async () => {
  let reads = 0;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      reads++;
      controller.close();
    },
  }, { highWaterMark: 0 });
  await rejected(request(stream, { "content-length": "64001" }), 413);
  equal(reads, 0);
});
for (const lengthHeader of [undefined, "1"]) {
  Deno.test(`stream stops at limit with ${lengthHeader ? "misleading" : "missing"} length header`, async () => {
    let reads = 0;
    let cancelled = false;
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        reads++;
        controller.enqueue(new Uint8Array(8).fill(32));
      },
      cancel() {
        cancelled = true;
      },
    }, { highWaterMark: 0 });
    await rejected(
      request(
        stream,
        lengthHeader ? { "content-length": lengthHeader } : undefined,
      ),
      413,
      10,
    );
    equal(reads, 2);
    equal(cancelled, true);
  });
}
for (const value of ["", "not-json", "null", "[]", '"string"']) {
  Deno.test(`invalid JSON object body ${JSON.stringify(value)} is rejected`, async () => {
    await rejected(request(value), 400);
  });
}
Deno.test("malformed UTF-8 is rejected rather than silently repaired", async () => {
  await rejected(
    request(Uint8Array.of(123, 34, 120, 34, 58, 34, 255, 34, 125)),
    400,
  );
});
