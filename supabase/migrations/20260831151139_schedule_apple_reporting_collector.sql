do $setup$
declare
  v_job_id bigint;
begin
  if not exists (
    select 1 from vault.secrets where name = 'apple_reporting_drain_token'
  ) then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'apple_reporting_drain_token',
      'Private token for the scheduled aggregate-only Apple reporting collector'
    );
  end if;

  if exists (
    select 1 from vault.secrets
    where name = 'booking_confirmation_project_url'
  ) then
    for v_job_id in
      select jobid from cron.job
      where jobname = 'collect-workloop-apple-reporting'
    loop
      perform cron.unschedule(v_job_id);
    end loop;

    perform cron.schedule(
      'collect-workloop-apple-reporting',
      '17 4 * * *',
      $job$
        select net.http_post(
          url := (
            select decrypted_secret
            from vault.decrypted_secrets
            where name = 'booking_confirmation_project_url'
          ) || '/functions/v1/collect-apple-reporting',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-workloop-reporting-token', (
              select decrypted_secret
              from vault.decrypted_secrets
              where name = 'apple_reporting_drain_token'
            )
          ),
          body := '{}'::jsonb,
          timeout_milliseconds := 30000
        );
      $job$
    );
  end if;
end
$setup$;
