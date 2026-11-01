-- Vexaronet: volba osobního odběru v e-shopu (pripraveno, NEPOUSTET automaticky na produkci).
-- Dopad: pridava sloupce shop_settings.pickup_enabled/pickup_text (default vypnuto), rozsiruje verejnou funkci public_shop
-- o pickup_enabled/pickup_text a nahrazuje public_shop_order variantou s volitelnym parametrem p_delivery ('ship'|'pickup').
-- Puvodni 5-parametrova funkce se maze, aby nevznikla nejednoznacnost pri volani pres PostgREST. Data se nemeni.
-- Klient pouziva p_delivery jen kdyz public_shop vrati pickup_enabled = true, takze pred spustenim migrace se nic nemeni.
begin;
alter table public.shop_settings add column if not exists pickup_enabled boolean not null default false;
alter table public.shop_settings add column if not exists pickup_text text;
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
    'shipping_fee', s.shipping_fee, 'pickup_enabled', s.pickup_enabled, 'pickup_text', s.pickup_text, 'products', res);
end $$;

drop function if exists public.public_shop_order(text, jsonb, jsonb, text, text);
-- Veřejné založení objednávky: sklad, zákazník, zakázka, objednávka, odpis ze skladu a faktura v jedné transakci.
create or replace function public.public_shop_order(p_slug text, p_items jsonb, p_buyer jsonb, p_note text default null, p_hp text default null, p_delivery text default 'ship')
returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare
  s public.shop_settings; p public.user_business_profiles; cid uuid; owner uuid; base_cur text;
  pr public.products; it jsonb; agg jsonb := '{}'::jsonb; k text; q numeric; stock numeric;
  total numeric := 0; n integer; cust public.customers; v_job uuid; v_order uuid; v_inv jsonb; v_num text;
  v_err text; old_claims text; inv_items jsonb := '[]'::jsonb; v_rate numeric; def_rate numeric; today date := (now() at time zone 'Europe/Prague')::date;
  bname text; bmail text; baddr text; bphone text; desc_txt text := ''; v_fee numeric; v_pick boolean;
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
  if coalesce(p_delivery,'ship') not in ('ship','pickup') then raise exception 'Zvolte způsob dodání.'; end if;
  v_pick := (p_delivery = 'pickup');
  if v_pick and not s.pickup_enabled then raise exception 'Osobní odběr tento obchod nenabízí.'; end if;
  v_fee := case when v_pick then 0 else s.shipping_fee end;
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
  if v_pick then desc_txt := desc_txt || 'Osobní odběr' || E'\n'; end if;
  if v_fee > 0 then
    total := total + v_fee;
    desc_txt := desc_txt || 'Doprava' || E'\n';
    inv_items := inv_items || jsonb_build_object('description', 'Doprava', 'quantity', 1, 'unit', 'ks', 'unit_gross', v_fee, 'vat_rate', case when p.vat_payer then def_rate else null end);
  end if;
  select * into cust from public.customers where company_id = cid and lower(email) = lower(bmail) and not archived limit 1;
  if cust.id is null then
    insert into public.customers(company_id, name, email, phone, billing_address, notes)
    values (cid, bname, bmail, bphone, baddr, 'Založeno z e-shopu') returning * into cust;
  end if;
  insert into public.jobs(company_id, customer_id, title, description, price, status, stage)
  values (cid, cust.id, 'E-shop objednávka č. ' || n, desc_txt, total, 'new', 'Nová') returning id into v_job;
  insert into public.shop_orders(company_id, order_no, customer_id, job_id, buyer, note, shipping_fee, total)
  values (cid, n, cust.id, v_job, jsonb_build_object('name', bname, 'email', bmail, 'phone', bphone, 'address', baddr, 'delivery', case when v_pick then 'pickup' else 'ship' end), left(p_note, 1000), v_fee, total)
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

grant execute on function public.public_shop(text) to anon, authenticated;
grant execute on function public.public_shop_order(text, jsonb, jsonb, text, text, text) to anon, authenticated;
commit;
