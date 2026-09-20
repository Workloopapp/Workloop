import { removeWorkspaceReceiptFiles } from "./receipt_storage_cleanup.ts";
const workspace = "11111111-1111-4111-8111-111111111111";
function assert(value: boolean, message: string) {
  if (!value) throw new Error(message);
}

Deno.test("receipt deletion removes paginated nested files without skipping shrinking pages", async () => {
  const files = new Set(
    Array.from({ length: 225 }, (_, i) => `${workspace}/expense/file${i}.pdf`),
  );
  files.add("another-workspace/expense/keep.pdf");
  const store = {
    list: async (path: string, options: { limit: number; offset: number }) => {
      const rows = [...files].filter((file) => file.startsWith(`${path}/`));
      const names = [
        ...new Set(
          rows.map((file) => file.slice(path.length + 1).split("/")[0]),
        ),
      ];
      return {
        data: names.slice(options.offset, options.offset + options.limit).map(
          (name) => ({ name, id: files.has(`${path}/${name}`) ? name : null }),
        ),
        error: null,
      };
    },
    remove: async (paths: string[]) => {
      paths.forEach((path) => files.delete(path));
      return { error: null };
    },
  };
  await removeWorkspaceReceiptFiles(store, workspace);
  assert(
    files.size === 1 && files.has("another-workspace/expense/keep.pdf"),
    "only workspace receipts removed",
  );
  await removeWorkspaceReceiptFiles(store, workspace);
  assert(files.size === 1, "retry is idempotent");
});
Deno.test("receipt deletion failures block metadata deletion instead of pretending success", async () => {
  let failed = false;
  try {
    await removeWorkspaceReceiptFiles({
      list: async () => ({ data: null, error: "offline" }),
      remove: async () => ({ error: null }),
    }, workspace);
  } catch (_) {
    failed = true;
  }
  assert(failed, "listing failure is surfaced");
});
