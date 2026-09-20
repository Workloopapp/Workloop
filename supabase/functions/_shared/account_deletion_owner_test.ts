import { canCompleteAccountDeletion } from "./account_deletion_owner.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("deletion accepts the verified sole owner", () => {
  assert(
    canCompleteAccountDeletion({
      memberships: [{ user_id: "owner" }],
      requestedUserId: "owner",
      authUserExists: true,
    }),
    "sole owner accepted",
  );
});

Deno.test("deletion recovers an orphan only after the Auth user is gone", () => {
  assert(
    canCompleteAccountDeletion({
      memberships: [],
      requestedUserId: "deleted-owner",
      authUserExists: false,
    }),
    "manual Auth deletion can be recovered",
  );
  assert(
    !canCompleteAccountDeletion({
      memberships: [],
      requestedUserId: "active-owner",
      authUserExists: true,
    }),
    "active user without ownership is blocked",
  );
});

Deno.test("deletion never crosses into another member's workspace", () => {
  assert(
    !canCompleteAccountDeletion({
      memberships: [{ user_id: "someone-else" }],
      requestedUserId: "owner",
      authUserExists: false,
    }),
    "mismatched membership blocked",
  );
});
