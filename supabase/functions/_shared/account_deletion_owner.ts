import { isSoleWorkspaceOwner } from "./sole_workspace_owner.ts";

export function canCompleteAccountDeletion(input: {
  memberships: Array<{ user_id?: unknown }> | null;
  requestedUserId: string;
  authUserExists: boolean;
}) {
  if (isSoleWorkspaceOwner(input.memberships, input.requestedUserId)) {
    return true;
  }
  return (input.memberships?.length ?? 0) === 0 && !input.authUserExists;
}
