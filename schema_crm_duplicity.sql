-- Vexaronet: CRM, duplicity zákazníků a jejich slučování.
-- Vyžaduje schema_crm.sql (deals, quotes, client_notes). Do tabulky customers jen přidává jeden volitelný sloupec, nic nemění ani nemaže.
-- Zákazník se při sloučení nemaže: označí se jako archivovaný a odkáže na záznam, do kterého byl sloučen. Úplný obsah smazaného záznamu zůstane v customer_merges.
-- Souhlasy se zasíláním e-mailů (private.customer_care_consent) se nepřesouvají: souhlas patří k e-mailové adrese, ne k historii.
-- Zpět: drop function public.crm_merge_customers(uuid, uuid), public.crm_find_duplicates(uuid); drop table public.customer_merges; alter table public.customers drop column merged_into;

alter table public.customers add column if not exists merged_into uuid references public.customers(id) on delete set null;

create table if not exists public.customer_merges (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  kept_id uuid not null,
  merged_id uuid not null,
  merged_snapshot jsonb not null,
  moved jsonb not null default '{}'::jsonb,
  merged_by uuid,
  merged_at timestamptz not null default now()
);
create index if not exists customer_merges_company on public.customer_merges (company_id, merged_at);

alter table public.customer_merges enable row level security;
drop policy if exists customer_merges_select on public.customer_merges;
create policy customer_merges_select on public.customer_merges for select to authenticated
  using (private.member_role(company_id) = any (array['owner','admin']));
revoke all on public.customer_merges from anon;
revoke insert, update, delete on public.customer_merges from authenticated;
grant select on public.customer_merges to authenticated;

-- Najde skupiny zákazníků se stejným IČO, e-mailem nebo telefonem. Respektuje RLS volajícího.
create or replace function public.crm_find_duplicates(p_company uuid)
returns table (reason text, match_key text, customer_ids uuid[], customer_names text[])
language plpgsql stable security invoker set search_path = '' as $$
begin
  if private.member_role(p_company) is null then
    raise exception 'Nemáte přístup k této firmě.' using errcode = '42501';
  end if;
  return query
  with c as (
    select cu.id, cu.name,
      nullif(lower(btrim(coalesce(cu.email, ''))), '') as em,
      (case when length(regexp_replace(coalesce(cu.ico, ''), '\D', '', 'g')) between 1 and 8
            then lpad(regexp_replace(cu.ico, '\D', '', 'g'), 8, '0')
            else nullif(regexp_replace(coalesce(cu.ico, ''), '\D', '', 'g'), '') end) as ic,
      (case when length(regexp_replace(coalesce(cu.phone, ''), '\D', '', 'g')) >= 9
            then right(regexp_replace(cu.phone, '\D', '', 'g'), 9) end) as ph
    from public.customers cu
    where cu.company_id = p_company and not coalesce(cu.archived, false) and cu.merged_into is null
  )
  select 'ico'::text, g.k, g.ids, g.nms from (
    select c.ic as k, array_agg(c.id order by c.name, c.id) as ids, array_agg(coalesce(c.name, '') order by c.name, c.id) as nms
    from c where c.ic is not null group by c.ic having count(*) > 1) g
  union all
  select 'email'::text, g.k, g.ids, g.nms from (
    select c.em as k, array_agg(c.id order by c.name, c.id) as ids, array_agg(coalesce(c.name, '') order by c.name, c.id) as nms
    from c where c.em is not null group by c.em having count(*) > 1) g
  union all
  select 'phone'::text, g.k, g.ids, g.nms from (
    select c.ph as k, array_agg(c.id order by c.name, c.id) as ids, array_agg(coalesce(c.name, '') order by c.name, c.id) as nms
    from c where c.ph is not null group by c.ph having count(*) > 1) g;
end $$;

-- Sloučí zákazníka p_merge do zákazníka p_keep: přesune zakázky, rezervace, obchody, nabídky, poznámky, recenze, objednávky e-shopu a doplní prázdné údaje.
-- Smí jen vlastník nebo správce firmy s platným předplatným. Vše proběhne v jedné transakci.
create or replace function public.crm_merge_customers(p_keep uuid, p_merge uuid)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  k public.customers;
  m public.customers;
  v_uid uuid := auth.uid();
  n integer;
  moved jsonb := '{}'::jsonb;
  v_note text;
begin
  if v_uid is null then
    raise exception 'Nejste přihlášen(a).' using errcode = '42501';
  end if;
  if p_keep is null or p_merge is null or p_keep = p_merge then
    raise exception 'Vyberte dva různé zákazníky.' using errcode = '22023';
  end if;

  perform 1 from public.customers where id in (p_keep, p_merge) order by id for update;
  select * into k from public.customers where id = p_keep;
  select * into m from public.customers where id = p_merge;
  if k.id is null or m.id is null then
    raise exception 'Zákazník nebyl nalezen.' using errcode = 'P0002';
  end if;
  if k.company_id <> m.company_id then
    raise exception 'Zákazníci patří do různých firem.' using errcode = '42501';
  end if;
  if coalesce(private.member_role(k.company_id), '') not in ('owner', 'admin') then
    raise exception 'Slučovat zákazníky může jen vlastník nebo správce firmy.' using errcode = '42501';
  end if;
  if not coalesce(private.writable(k.company_id), false) then
    raise exception 'Předplatné neumožňuje úpravy dat.' using errcode = '42501';
  end if;
  if coalesce(k.archived, false) or k.merged_into is not null or coalesce(m.archived, false) or m.merged_into is not null then
    raise exception 'Archivované nebo už sloučené zákazníky nelze slučovat.' using errcode = '22023';
  end if;

  update public.customers set
    email = coalesce(nullif(btrim(email), ''), m.email),
    phone = coalesce(nullif(btrim(phone), ''), m.phone),
    billing_address = coalesce(nullif(btrim(billing_address), ''), m.billing_address),
    ico = coalesce(nullif(btrim(ico), ''), m.ico),
    dic = coalesce(nullif(btrim(dic), ''), m.dic),
    notes = case
      when nullif(btrim(m.notes), '') is null then notes
      when notes is not null and position(btrim(m.notes) in notes) > 0 then notes
      else coalesce(nullif(notes, '') || E'\n\n', '') || '[Ze sloučeného záznamu] ' || btrim(m.notes) end
  where id = k.id;

  update public.client_notes set customer_id = k.id where customer_id = m.id and company_id = k.company_id;
  get diagnostics n = row_count; moved := moved || jsonb_build_object('client_notes', n);
  update public.deals set customer_id = k.id where customer_id = m.id and company_id = k.company_id;
  get diagnostics n = row_count; moved := moved || jsonb_build_object('deals', n);
  update public.quotes set customer_id = k.id where customer_id = m.id and company_id = k.company_id;
  get diagnostics n = row_count; moved := moved || jsonb_build_object('quotes', n);
  update public.jobs set customer_id = k.id where customer_id = m.id and company_id = k.company_id;
  get diagnostics n = row_count; moved := moved || jsonb_build_object('jobs', n);
  update public.reservations set customer_id = k.id where customer_id = m.id and company_id = k.company_id;
  get diagnostics n = row_count; moved := moved || jsonb_build_object('reservations', n);
  update public.customer_reviews set customer_id = k.id where customer_id = m.id and company_id = k.company_id;
  get diagnostics n = row_count; moved := moved || jsonb_build_object('customer_reviews', n);
  update public.shop_orders set customer_id = k.id where customer_id = m.id and company_id = k.company_id;
  get diagnostics n = row_count; moved := moved || jsonb_build_object('shop_orders', n);
  update public.ai_saved_actions set customer_id = k.id where customer_id = m.id and company_id = k.company_id;
  get diagnostics n = row_count; moved := moved || jsonb_build_object('ai_saved_actions', n);

  v_note := left('Sloučeno se záznamem „' || coalesce(m.name, '') || '“'
    || coalesce(' (IČO ' || nullif(btrim(m.ico), '') || ')', '')
    || coalesce(', e-mail ' || nullif(btrim(m.email), ''), '')
    || '. Přesunuto: zakázky ' || (moved->>'jobs') || ', rezervace ' || (moved->>'reservations')
    || ', obchodní případy ' || (moved->>'deals') || ', nabídky ' || (moved->>'quotes')
    || ', poznámky ' || (moved->>'client_notes') || '.', 4000);
  insert into public.client_notes (company_id, customer_id, kind, body, created_by)
    values (k.company_id, k.id, 'note', v_note, v_uid);

  update public.customers set archived = true, merged_into = k.id where id = m.id;

  insert into public.customer_merges (company_id, kept_id, merged_id, merged_snapshot, moved, merged_by)
    values (k.company_id, k.id, m.id, to_jsonb(m), moved, v_uid);

  return jsonb_build_object('kept', k.id, 'merged', m.id, 'moved', moved);
end $$;

revoke all on function public.crm_find_duplicates(uuid) from public, anon;
revoke all on function public.crm_merge_customers(uuid, uuid) from public, anon;
grant execute on function public.crm_find_duplicates(uuid) to authenticated;
grant execute on function public.crm_merge_customers(uuid, uuid) to authenticated;
