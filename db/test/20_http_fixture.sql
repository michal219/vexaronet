-- Jen pro PRÁZDNÝ testovací projekt (po 01_base_stub.sql a migraci profilu).
-- Založí firmu pro testovacího uživatele, aby šlo z venku (přes HTTP) zkusit funkce profile_*.
-- 1) V Authentication → Users založte testovacího uživatele (e-mail + heslo, "Auto Confirm User").
-- 2) Níže změňte e-mail, spusťte, opište vypsané TEST_COMPANY_ID.
do $$
declare v_email text := 'ZMENTE-NA-TESTOVACI-EMAIL@example.com';
        v_uid uuid; v_cid uuid := '00000000-0000-0000-0000-00000000f001';
begin
  select id into v_uid from auth.users where lower(email) = lower(v_email);
  if v_uid is null then raise exception 'Uživatel % neexistuje. Založte ho v Authentication → Users.', v_email; end if;
  insert into public.companies (id, owner_id, name) values (v_cid, v_uid, 'HTTP test firma') on conflict do nothing;
  insert into public.company_members (company_id, user_id, role) values (v_cid, v_uid, 'owner') on conflict do nothing;
  insert into public.subscriptions (company_id, plan, status, trial_end) values (v_cid, 'pro', 'trial', now() + interval '10 days') on conflict do nothing;
  raise notice 'TEST_COMPANY_ID=%', v_cid;
end $$;
