create index if not exists push_delivery_outbox_push_token_idx on app_private.push_delivery_outbox(push_token_id);
create index if not exists push_delivery_outbox_workspace_idx on app_private.push_delivery_outbox(workspace_id);
