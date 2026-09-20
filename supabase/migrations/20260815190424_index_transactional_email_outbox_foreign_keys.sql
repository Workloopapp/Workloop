-- Cover retained foreign keys used by cascades and lifecycle cleanup. These
-- small private queues are service-only, but indexed joins keep deletion and
-- cleanup predictable as delivery volume grows.

create index if not exists account_deletion_email_outbox_request_id_idx
  on app_private.account_deletion_email_outbox(request_id);

create index if not exists account_welcome_email_outbox_user_id_idx
  on app_private.account_welcome_email_outbox(user_id);

create index if not exists waitlist_email_outbox_waitlist_id_idx
  on app_private.waitlist_email_outbox(waitlist_id);
