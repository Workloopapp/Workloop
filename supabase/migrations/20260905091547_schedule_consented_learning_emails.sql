-- Uses the existing private Vault token; never embeds credentials in SQL.
-- Only confirmed opt-ins receive lessons. Pending requests receive confirmation.
select cron.schedule(
  'workloop-learning-series',
  '*/15 * * * *',
  $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name='booking_confirmation_project_url') || '/functions/v1/learning-series',
    headers := jsonb_build_object('Content-Type','application/json','x-workloop-drain-token',
      (select decrypted_secret from vault.decrypted_secrets where name='booking_confirmation_drain_token')),
    body := '{"action":"drain"}'::jsonb,
    timeout_milliseconds := 60000
  );
  $job$
);
