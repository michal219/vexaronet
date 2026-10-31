-- Vexaronet: e-shop (objednávky, automatická faktura, odepsání ze skladu).
-- Spouští se jednou v Supabase SQL Editoru. Nic existujícího nemění ani nemaže (jen přidává sloupce a tabulky).
-- Kupující se neregistruje: objednávku zakládá veřejná funkce public_shop_order, která v jedné transakci
-- zkontroluje sklad, založí zákazníka, zakázku, objednávku, odepíše zboží ze skladu a vystaví fakturu.

alter table public.products
  add column if not exists shop_visible boolean not null default false,
  add column if not exists description text,
  add column if not exists image_url text,
  add column if not exists vat_rate numeric default 21;

create table if not exists public.shop_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9-]{3,40}$'),
  enabled boolean not null default false,
  title text,
  description text,
  contact_email text,
  contact_phone text,
  payment_text text,
  shipping_text text,
  shipping_fee numeric(10,2) not null default 0 check (shipping_fee >= 0),
  updated_at timestamptz not null default now()
);
alter table public.shop_settings enable row level security;
drop policy if exists shs_select on public.shop_settings;
create policy shs_select on public.shop_settings for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = shop_settings.company_id and m.user_id = auth.uid()));
drop policy if exists shs_write on public.shop_settings;
create policy shs_write on public.shop_settings for all to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = shop_settings.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = shop_settings.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));

create table if not exists public.shop_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  order_no integer not null,
  status text not null default 'new' check (status in ('new','paid','shipped','done','canceled')),
  customer_id uuid references public.customers(id) on delete set null,
  job_id uuid,
  invoice_id uuid,
  buyer jsonb not null,
  note text,
  shipping_fee numeric(10,2) not null default 0,
  total numeric(12,2) not null,
  invoice_error text,
  restocked boolean not null default false,
  created_at timestamptz not null default now(),
  unique (company_id, order_no)
);
create table if not exists public.shop_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.shop_orders(id) on delete cascade,
  company_id uuid not null,
  product_id uuid references public.products(id) on delete set null,
  name text not null,
  qty numeric(10,3) not null,
  unit_price numeric(12,2) not null
);
create index if not exists shop_orders_company_created on public.shop_orders (company_id, created_at desc);
create index if not exists shop_order_items_order on public.shop_order_items (order_id);
alter table public.shop_orders enable row level security;
alter table public.shop_order_items enable row level security;
drop policy if exists sho_select on public.shop_orders;
create policy sho_select on public.shop_orders for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = shop_orders.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));
drop policy if exists sho_update on public.shop_orders;
create policy sho_update on public.shop_orders for update to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = shop_orders.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = shop_orders.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));
drop policy if exists shi_select on public.shop_order_items;
create policy shi_select on public.shop_order_items for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = shop_order_items.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));

-- Veřejný výpis obchodu (bez přihlášení). Obchod se zobrazí jen když je zapnutý a firma má vyplněné fakturační údaje.
create or replace function public.public_shop(p_slug text)
returns jsonb
language plpgsql stable security definer set search_path to ''
as $$
declare s public.shop_settings; cname text; res jsonb;
begin
  select * into s from public.shop_settings where slug = lower(p_slug) and enabled;
  if not found then return null; end if;
  if not exists (select 1 from public.user_business_profiles where company_id = s.company_id) then return null; end if;
  select name into cname from public.companies where id = s.company_id;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'description', x.description, 'image_url', x.image_url,
           'price', x.price, 'unit', x.unit, 'available', x.av) order by x.name), '[]'::jsonb) into res
  from (select p.id, p.name, p.description, p.image_url, p.price, p.unit,
               greatest(0, least(50, coalesce((select sum(m.qty) from public.stock_moves m where m.product_id = p.id), 0)))::numeric as av
        from public.products p
        where p.company_id = s.company_id and p.active and p.shop_visible and coalesce(p.price,0) > 0) x;
  return jsonb_build_object('name', cname, 'title', s.title, 'description', s.description, 'contact_email', s.contact_email,
    'contact_phone', s.contact_phone, 'payment_text', s.payment_text, 'shipping_text', s.shipping_text,
    'shipping_fee', s.shipping_fee, 'products', res);
end $$;

-- Veřejné založení objednávky: sklad, zákazník, zakázka, objednávka, odpis ze skladu a faktura v jedné transakci.
create or replace function public.public_shop_order(p_slug text, p_items jsonb, p_buyer jsonb, p_note text default null, p_hp text default null)
returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare
  s public.shop_settings; p public.user_business_profiles; cid uuid; owner uuid; base_cur text;
  pr public.products; it jsonb; agg jsonb := '{}'::jsonb; k text; q numeric; stock numeric;
  total numeric := 0; n integer; cust public.customers; v_job uuid; v_order uuid; v_inv jsonb; v_num text;
  v_err text; old_claims text; inv_items jsonb := '[]'::jsonb; v_rate numeric; def_rate numeric; today date := (now() at time zone 'Europe/Prague')::date;
  bname text; bmail text; baddr text; bphone text; desc_txt text := '';
begin
  if coalesce(p_hp,'') <> '' then raise exception 'Objednávku se nepodařilo odeslat.'; end if;
  select * into s from public.shop_settings where slug = lower(p_slug) and enabled;
  if not found then raise exception 'Obchod není dostupný.'; end if;
  cid := s.company_id;
  select * into p from public.user_business_profiles where company_id = cid;
  if p.company_id is null then raise exception 'Obchod není dostupný.'; end if;
  select owner_id, currency into owner, base_cur from public.companies where id = cid;
  perform pg_advisory_xact_lock(hashtextextended(cid::text, 552));
  if (select count(*) from public.shop_orders where company_id = cid and created_at > now() - interval '1 hour') >= 30 then
    raise exception 'Obchod je dočasně přetížený, zkuste to prosím později.'; end if;
  bname := btrim(coalesce(p_buyer->>'name','')); bmail := btrim(coalesce(p_buyer->>'email',''));
  baddr := btrim(coalesce(p_buyer->>'address','')); bphone := btrim(coalesce(p_buyer->>'phone',''));
  if length(bname) not between 2 and 200 then raise exception 'Vyplňte jméno.'; end if;
  if bmail !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' or length(bmail) > 200 then raise exception 'Zkontrolujte e-mail.'; end if;
  if length(baddr) not between 5 and 500 then raise exception 'Vyplňte adresu (ulice, město a PSČ).'; end if;
  if length(bphone) > 40 then raise exception 'Zkontrolujte telefon.'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 30 then raise exception 'Košík je prázdný.'; end if;
  for it in select value from jsonb_array_elements(p_items) loop
    q := (it->>'qty')::numeric;
    if q is null or q < 1 or q > 100 or q <> trunc(q) then raise exception 'Zkontrolujte množství.'; end if;
    k := it->>'product_id';
    agg := jsonb_set(agg, array[k], to_jsonb(coalesce((agg->>k)::numeric, 0) + q));
  end loop;
  def_rate := case when p.country_code = 'SK' then 23 else 21 end;
  select coalesce(max(order_no), 0) + 1 into n from public.shop_orders where company_id = cid;
  for k in select jsonb_object_keys(agg) loop
    q := (agg->>k)::numeric;
    select * into pr from public.products where id = k::uuid and company_id = cid and active and shop_visible and coalesce(price,0) > 0;
    if pr.id is null then raise exception 'Některé zboží už není v nabídce.'; end if;
    select coalesce(sum(qty), 0) into stock from public.stock_moves where product_id = pr.id;
    if stock < q then raise exception 'Zboží „%“ už není v požadovaném množství skladem (zbývá %).', pr.name, greatest(0, trunc(stock)); end if;
    total := total + round(pr.price * q, 2);
    desc_txt := desc_txt || pr.name || ' × ' || q::text || E'\n';
    v_rate := case when not p.vat_payer then null
                   when p.country_code = 'SK' then (case when pr.vat_rate in (5,19,23) then pr.vat_rate else 23 end)
                   else (case when pr.vat_rate in (12,21) then pr.vat_rate else 21 end) end;
    inv_items := inv_items || jsonb_build_object('description', pr.name, 'quantity', q, 'unit', left(coalesce(pr.unit,'ks'),20), 'unit_gross', pr.price, 'vat_rate', v_rate);
  end loop;
  if s.shipping_fee > 0 then
    total := total + s.shipping_fee;
    desc_txt := desc_txt || 'Doprava' || E'\n';
    inv_items := inv_items || jsonb_build_object('description', 'Doprava', 'quantity', 1, 'unit', 'ks', 'unit_gross', s.shipping_fee, 'vat_rate', case when p.vat_payer then def_rate else null end);
  end if;
  select * into cust from public.customers where company_id = cid and lower(email) = lower(bmail) and not archived limit 1;
  if cust.id is null then
    insert into public.customers(company_id, name, email, phone, billing_address, notes)
    values (cid, bname, bmail, bphone, baddr, 'Založeno z e-shopu') returning * into cust;
  end if;
  insert into public.jobs(company_id, customer_id, title, description, price, status, stage)
  values (cid, cust.id, 'E-shop objednávka č. ' || n, desc_txt, total, 'new', 'Nová') returning id into v_job;
  insert into public.shop_orders(company_id, order_no, customer_id, job_id, buyer, note, shipping_fee, total)
  values (cid, n, cust.id, v_job, jsonb_build_object('name', bname, 'email', bmail, 'phone', bphone, 'address', baddr), left(p_note, 1000), s.shipping_fee, total)
  returning id into v_order;
  for k in select jsonb_object_keys(agg) loop
    q := (agg->>k)::numeric;
    select * into pr from public.products where id = k::uuid;
    insert into public.shop_order_items(order_id, company_id, product_id, name, qty, unit_price) values (v_order, cid, pr.id, pr.name, q, pr.price);
    insert into public.stock_moves(company_id, product_id, qty, kind, note, created_by) values (cid, pr.id, -q, 'out', 'E-shop objednávka č. ' || n, null);
  end loop;
  -- faktura: vystaví se jménem majitele firmy stejnou funkcí jako při ručním vystavení (stejné kontroly a číslování)
  old_claims := current_setting('request.jwt.claims', true);
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', owner, 'role', 'authenticated')::text, true);
    v_inv := private.invoice_action_core(cid, 'start', jsonb_build_object('job_id', v_job));
    v_inv := private.invoice_action_core(cid, 'issue', jsonb_build_object('id', v_inv->>'id', 'job_id', v_job,
      'customer', jsonb_build_object('name', bname, 'email', bmail, 'address_text', baddr, 'country_code', p.country_code),
      'items', inv_items, 'issued_on', today, 'taxable_supply_on', today, 'due_on', today + coalesce(p.default_due_days, 14),
      'currency', base_cur, 'language', p.invoice_language));
    update public.shop_orders set invoice_id = (v_inv->>'id')::uuid where id = v_order;
    v_num := v_inv->>'number';
  exception when others then
    v_err := sqlerrm; v_inv := null;
  end;
  perform set_config('request.jwt.claims', coalesce(old_claims, ''), true);
  if v_err is not null then update public.shop_orders set invoice_error = left(v_err, 500) where id = v_order; end if;
  return jsonb_build_object('order_no', n, 'total', total, 'currency', base_cur, 'invoice_number', v_num,
    'invoice_ok', v_inv is not null, 'iban', p.iban, 'bank_account', p.bank_account,
    'due_on', case when v_inv is null then null else v_inv->>'due_on' end, 'payment_text', s.payment_text, 'email', bmail);
end $$;

-- Zrušení objednávky: vrátí zboží na sklad (jen jednou). Vystavenou fakturu je nutné stornovat ručně.
create or replace function public.shop_cancel_order(p_order uuid)
returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare o public.shop_orders; i public.shop_order_items;
begin
  select * into o from public.shop_orders where id = p_order for update;
  if o.id is null then raise exception 'Objednávka nebyla nalezena.'; end if;
  if auth.uid() is null or private.member_role(o.company_id) not in ('owner','admin') then raise exception 'Nemáte oprávnění.'; end if;
  if o.status = 'canceled' then return jsonb_build_object('status', 'canceled', 'restocked', o.restocked); end if;
  if not o.restocked then
    for i in select * from public.shop_order_items where order_id = o.id and product_id is not null loop
      insert into public.stock_moves(company_id, product_id, qty, kind, note) values (o.company_id, i.product_id, i.qty, 'in', 'Zrušení e-shop objednávky č. ' || o.order_no);
    end loop;
  end if;
  update public.shop_orders set status = 'canceled', restocked = true where id = o.id;
  return jsonb_build_object('status', 'canceled', 'restocked', true, 'invoice_id', o.invoice_id);
end $$;

grant execute on function public.public_shop(text) to anon, authenticated;
grant execute on function public.public_shop_order(text, jsonb, jsonb, text, text) to anon, authenticated;
grant execute on function public.shop_cancel_order(uuid) to authenticated;
