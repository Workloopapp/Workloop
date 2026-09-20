type StorageResult<T> = { data: T | null; error: unknown };
type ReceiptStorage = {
  list: (
    path: string,
    options: { limit: number; offset: number },
  ) => Promise<StorageResult<Array<{ name: string; id: string | null }>>>;
  remove: (paths: string[]) => Promise<{ error: unknown }>;
};

/** Remove actual bytes before workspace metadata cascades. Re-list from offset
 * zero after each delete; advancing an offset would skip shrinking pages.
 * Also finds uploaded bytes whose metadata was interrupted/removed. */
export async function removeWorkspaceReceiptFiles(
  storage: ReceiptStorage,
  workspaceId: string,
) {
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      workspaceId,
    )
  ) {
    throw new Error("Invalid workspace id");
  }
  async function clear(path: string, depth: number): Promise<void> {
    if (depth > 2) throw new Error("Unexpected receipt folder depth");
    for (;;) {
      const { data, error } = await storage.list(path, {
        limit: 100,
        offset: 0,
      });
      if (error || data == null) {
        throw new Error("Could not list receipt files");
      }
      if (data.length === 0) return;
      const files: string[] = [];
      for (const item of data) {
        if (
          !item.name || item.name.includes("/") || item.name === "." ||
          item.name === ".."
        ) throw new Error("Invalid receipt object name");
        const child = `${path}/${item.name}`;
        if (item.id == null) await clear(child, depth + 1);
        else files.push(child);
      }
      if (files.length > 0) {
        const removed = await storage.remove(files);
        if (removed.error) throw new Error("Could not remove receipt files");
      }
    }
  }
  await clear(workspaceId, 0);
}
