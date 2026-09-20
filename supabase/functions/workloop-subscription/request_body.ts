export class SubscriptionBodyError extends Error {
  constructor(readonly status: 400 | 413, message: string) {
    super(message);
  }
}

/** Limit bytes while reading, including requests without Content-Length. */
export async function subscriptionRequestBody(
  req: Request,
  maxBytes = 64000,
): Promise<Record<string, unknown>> {
  if (Number(req.headers.get("content-length") ?? 0) > maxBytes) {
    throw new SubscriptionBodyError(413, "Request too large");
  }
  if (!req.body) throw new SubscriptionBodyError(400, "Invalid request");
  const reader = req.body.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  const parts: string[] = [];
  let bytes = 0;
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      bytes += chunk.value.byteLength;
      if (bytes > maxBytes) {
        await reader.cancel().catch(() => {});
        throw new SubscriptionBodyError(413, "Request too large");
      }
      parts.push(decoder.decode(chunk.value, { stream: true }));
    }
    parts.push(decoder.decode());
    const value: unknown = JSON.parse(parts.join(""));
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new SubscriptionBodyError(400, "Invalid request");
    }
    return value as Record<string, unknown>;
  } catch (error) {
    await reader.cancel().catch(() => {});
    if (error instanceof SubscriptionBodyError) throw error;
    throw new SubscriptionBodyError(400, "Invalid request");
  } finally {
    reader.releaseLock();
  }
}
