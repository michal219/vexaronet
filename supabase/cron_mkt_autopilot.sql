-- Plánovač AI Marketing Autopilota (spustit v produkci jednou, po schema_mkt_autopilot.sql).
-- Tajemství pro volání serverové funkce se vytvoří ve Vaultu, nikam se nevypisuje.
do $$ begin
  if not exists (select 1 from vault.secrets where name = 'vexaronet_mkt_dispatch') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'vexaronet_mkt_dispatch', 'AI Marketing Autopilot: volání mkt-autopilot z pg_cron');
  end if;
end $$;
select cron.unschedule('vexaronet-mkt-autopilot') where exists (select 1 from cron.job where jobname = 'vexaronet-mkt-autopilot');
select cron.schedule('vexaronet-mkt-autopilot', '*/5 * * * *', $cron$
select private.mkt_enqueue_routines();
select net.http_post(
  url := 'https://micymdbqgzeckiqyvvkn.supabase.co/functions/v1/mkt-autopilot',
  headers := jsonb_build_object('Content-Type','application/json','x-vexaronet-dispatch',(select decrypted_secret from vault.decrypted_secrets where name = 'vexaronet_mkt_dispatch')),
  body := '{"action":"dispatch"}'::jsonb,
  timeout_milliseconds := 120000)
where exists (select 1 from public.mkt_tasks where (status = 'queued' and run_after <= now()) or (status = 'running' and lease_until < now()));
$cron$);
