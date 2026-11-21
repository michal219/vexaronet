-- Vexaronet: CRM 2 + podpora zemí EU u zákazníků.
-- PŘIDÁVÁ sloupce a funkce a pouze ROZŠIŘUJE dvě kontroly (DIČ a IČO zákazníka, měna nabídky). Nic nemaže ani nemění existující data.
-- Zpět (v případě potřeby): drop function public.crm_merge_customers(uuid,uuid,uuid); alter table customers drop column country_code, ... (viz sloupce níže).

-- ===== Zákazníci =====
alter table public.customers add column if not exists country_code text;
alter table public.customers add column if not exists status text not null default 'active';
alter table public.customers add column if not exists source text;
alter table public.customers add column if not exists website text;
alter table public.customers add column if not exists tags text;
alter table public.customers add column if not exists next_contact_on date;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'customers_country_eu') then
    alter table public.customers add constraint customers_country_eu check (country_code is null or country_code in
      ('AT','BE','BG','HR','CY','CZ','DK','EE','FI','FR','DE','GR','HU','IE','IT','LV','LT','LU','MT','NL','PL','PT','RO','SK','SI','ES','SE'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'customers_status_ok') then
    alter table public.customers add constraint customers_status_ok check (status in ('lead','active','inactive'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'customers_crm_len') then
    alter table public.customers add constraint customers_crm_len check (
      (source is null or char_length(source) <= 100) and (website is null or char_length(website) <= 300) and (tags is null or char_length(tags) <= 300));
  end if;
end $$;

-- DIČ a IČO zákazníka: dosud jen české tvary. Rozšíření na IČ DPH libovolného státu EU a registrační číslo firmy v zahraničí.
do $$ declare r record; begin
  for r in select conname from pg_constraint where conrelid = 'public.customers'::regclass and contype = 'c'
      and (pg_get_constraintdef(oid) like '%CZ[0-9]{8,10}%' or pg_get_constraintdef(oid) like '%^[0-9]{8}$%') loop
    execute format('alter table public.customers drop constraint %I', r.conname);
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'customers_dic_eu') then
    alter table public.customers add constraint customers_dic_eu check (dic = '' or dic ~ '^[A-Z]{2}[A-Z0-9]{2,14}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'customers_ico_any') then
    alter table public.customers add constraint customers_ico_any check (ico = '' or ico ~ '^[A-Za-z0-9][A-Za-z0-9 ./-]{1,19}$');
  end if;
end $$;

create index if not exists customers_follow on public.customers (company_id, next_contact_on) where next_contact_on is not null;

-- ===== Obchodní případy: důvod prohry, datum uzavření =====
alter table public.deals add column if not exists lost_reason text check (lost_reason is null or char_length(lost_reason) <= 300);
alter table public.deals add column if not exists closed_at timestamptz;
create or replace function public.deals_set_closed() returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if new.stage in ('won','lost') then
    if tg_op = 'INSERT' then new.closed_at := coalesce(new.closed_at, now());
    elsif old.stage is distinct from new.stage then new.closed_at := now();
    else new.closed_at := coalesce(new.closed_at, now()); end if;
  else
    new.closed_at := null;
  end if;
  if new.stage <> 'lost' then new.lost_reason := null; end if;
  return new;
end $$;
drop trigger if exists deals_closed on public.deals;
create trigger deals_closed before insert or update on public.deals for each row execute function public.deals_set_closed();

-- ===== Úkoly navázané na zákazníka a případ =====
alter table public.tasks add column if not exists customer_id uuid references public.customers(id) on delete set null;
alter table public.tasks add column if not exists deal_id uuid references public.deals(id) on delete set null;
create index if not exists tasks_customer on public.tasks (company_id, customer_id) where customer_id is not null;
create or replace function public.tasks_same_company() returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if new.customer_id is not null and not exists (select 1 from public.customers c where c.id = new.customer_id and c.company_id = new.company_id) then
    raise exception 'Zákazník nepatří do této firmy.';
  end if;
  if new.deal_id is not null and not exists (select 1 from public.deals d where d.id = new.deal_id and d.company_id = new.company_id) then
    raise exception 'Obchodní případ nepatří do této firmy.';
  end if;
  return new;
end $$;
drop trigger if exists tasks_same on public.tasks;
create trigger tasks_same before insert or update on public.tasks for each row execute function public.tasks_same_company();

-- ===== Nabídky: další měny =====
do $$ declare r record; begin
  for r in select conname from pg_constraint where conrelid = 'public.quotes'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%currency%' loop
    execute format('alter table public.quotes drop constraint %I', r.conname);
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'quotes_currency_eu') then
    alter table public.quotes add constraint quotes_currency_eu check (currency in ('CZK','EUR','PLN','HUF','RON','SEK','DKK'));
  end if;
end $$;

-- ===== Sloučení duplicitních zákazníků =====
-- Přesune návaznosti (zakázky, rezervace, případy, nabídky, záznamy, úkoly) na zákazníka, kterého ponecháte,
-- doplní prázdná pole a duplicitu ARCHIVUJE (nemaže). Běží jako jedna transakce. Oprávnění (vlastník nebo správce firmy s aktivním přístupem) se kontroluje uvnitř funkce, protože záznamy napsané jinými uživateli RLS jinak nedovolí přesunout.
create or replace function public.crm_merge_customers(cid uuid, keep_id uuid, drop_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare k public.customers; d public.customers; n_jobs int; n_res int; n_deals int; n_q int; n_notes int; n_tasks int; tg text;
begin
  if auth.uid() is null or private.member_role(cid) is null or private.member_role(cid) not in ('owner','admin') or not private.writable(cid) then
    raise exception 'Nemáte oprávnění nebo aktivní přístup.';
  end if;
  if keep_id = drop_id then raise exception 'Vyberte dva různé zákazníky.'; end if;
  select * into k from public.customers where id = keep_id and company_id = cid for update;
  select * into d from public.customers where id = drop_id and company_id = cid for update;
  if k.id is null or d.id is null then raise exception 'Zákazník nebyl nalezen.'; end if;

  update public.jobs set customer_id = keep_id where company_id = cid and customer_id = drop_id; get diagnostics n_jobs = row_count;
  update public.reservations set customer_id = keep_id where company_id = cid and customer_id = drop_id; get diagnostics n_res = row_count;
  update public.deals set customer_id = keep_id where company_id = cid and customer_id = drop_id; get diagnostics n_deals = row_count;
  update public.quotes set customer_id = keep_id where company_id = cid and customer_id = drop_id; get diagnostics n_q = row_count;
  update public.client_notes set customer_id = keep_id where company_id = cid and customer_id = drop_id; get diagnostics n_notes = row_count;
  update public.tasks set customer_id = keep_id where company_id = cid and customer_id = drop_id; get diagnostics n_tasks = row_count;

  -- štítky se sloučí bez opakování
  select string_agg(distinct trim(t), ', ') into tg from unnest(string_to_array(coalesce(k.tags,'') || ',' || coalesce(d.tags,''), ',')) t where trim(t) <> '';
  update public.customers set
    email = coalesce(nullif(k.email,''), d.email), phone = coalesce(nullif(k.phone,''), d.phone),
    billing_address = coalesce(nullif(k.billing_address,''), d.billing_address),
    ico = case when coalesce(k.ico,'') = '' then coalesce(d.ico,'') else k.ico end,
    dic = case when coalesce(k.dic,'') = '' then coalesce(d.dic,'') else k.dic end,
    country_code = coalesce(k.country_code, d.country_code), website = coalesce(nullif(k.website,''), d.website),
    source = coalesce(nullif(k.source,''), d.source), tags = left(nullif(tg,''), 300),
    next_contact_on = least(k.next_contact_on, d.next_contact_on),
    notes = left(nullif(trim(both E'\n' from coalesce(k.notes,'') || case when coalesce(d.notes,'') <> '' then E'\n' || 'Z duplicity „' || d.name || '“: ' || d.notes else '' end), ''), 4000)
  where id = keep_id;
  update public.customers set archived = true,
    notes = left('Sloučeno do zákazníka „' || k.name || '“ dne ' || to_char(now() at time zone 'Europe/Prague', 'DD.MM.YYYY') || E'\n' || coalesce(d.notes,''), 4000)
  where id = drop_id;
  return jsonb_build_object('jobs', n_jobs, 'reservations', n_res, 'deals', n_deals, 'quotes', n_q, 'notes', n_notes, 'tasks', n_tasks);
end $$;
revoke all on function public.crm_merge_customers(uuid, uuid, uuid) from public, anon;
grant execute on function public.crm_merge_customers(uuid, uuid, uuid) to authenticated;
