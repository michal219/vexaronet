-- Vexaronet: smeny zamestnancu + verejna rezervacni stranka. Nic existujiciho nemeni ani nemaze.
-- Spousti se jednou v Supabase SQL Editoru (cele najednou).

create table if not exists public.shifts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  person text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists shifts_company_start on public.shifts (company_id, starts_at);

create table if not exists public.booking_profiles (
  company_id uuid primary key references public.companies(id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{2,40}$'),
  enabled boolean not null default false,
  title text,
  description text,
  address text,
  phone text,
  hours jsonb not null default '{}'::jsonb,
  slot_minutes int not null default 30 check (slot_minutes between 10 and 240),
  capacity int not null default 1 check (capacity between 1 and 50),
  updated_at timestamptz not null default now()
);

create table if not exists public.booking_services (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  duration_min int not null default 30 check (duration_min between 5 and 600),
  price numeric,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists booking_services_company on public.booking_services (company_id);

alter table public.shifts enable row level security;
alter table public.booking_profiles enable row level security;
alter table public.booking_services enable row level security;

drop policy if exists shifts_select on public.shifts;
create policy shifts_select on public.shifts for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = shifts.company_id and m.user_id = auth.uid()));
drop policy if exists shifts_write on public.shifts;
create policy shifts_write on public.shifts for all to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = shifts.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = shifts.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));

drop policy if exists bprof_select on public.booking_profiles;
create policy bprof_select on public.booking_profiles for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = booking_profiles.company_id and m.user_id = auth.uid()));
drop policy if exists bprof_write on public.booking_profiles;
create policy bprof_write on public.booking_profiles for all to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = booking_profiles.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = booking_profiles.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));

drop policy if exists bserv_select on public.booking_services;
create policy bserv_select on public.booking_services for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = booking_services.company_id and m.user_id = auth.uid()));
drop policy if exists bserv_write on public.booking_services;
create policy bserv_write on public.booking_services for all to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = booking_services.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = booking_services.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));

-- Verejne info o rezervacni strance (jen zapnute stranky, jen verejne udaje)
create or replace function public.public_booking_info(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare pr public.booking_profiles; cname text;
begin
  select * into pr from public.booking_profiles where slug = lower(p_slug) and enabled;
  if not found then return null; end if;
  select name into cname from public.companies where id = pr.company_id;
  return jsonb_build_object(
    'name', cname, 'title', pr.title, 'description', pr.description,
    'address', pr.address, 'phone', pr.phone, 'hours', pr.hours,
    'services', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'duration_min', s.duration_min, 'price', s.price) order by s.name)
                          from public.booking_services s where s.company_id = pr.company_id and s.active), '[]'::jsonb));
end $fn$;

-- Volne terminy v danem dni (cas Europe/Prague, vyhradni rezervace se pocitaji podle kapacity)
create or replace function public.public_slots(p_slug text, p_service uuid, p_day date)
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare pr public.booking_profiles; sv public.booking_services; h jsonb; o time; c time;
  t timestamptz; lim timestamptz; dur interval; stp interval; busy int; res jsonb := '[]'::jsonb; today date;
begin
  select * into pr from public.booking_profiles where slug = lower(p_slug) and enabled;
  if not found then return res; end if;
  select * into sv from public.booking_services where id = p_service and company_id = pr.company_id and active;
  if not found then return res; end if;
  today := (now() at time zone 'Europe/Prague')::date;
  if p_day < today or p_day > today + 60 then return res; end if;
  h := pr.hours -> (extract(isodow from p_day)::int)::text;
  if h is null or (h->>'o') is null or (h->>'c') is null then return res; end if;
  o := (h->>'o')::time; c := (h->>'c')::time;
  dur := make_interval(mins => sv.duration_min);
  stp := make_interval(mins => greatest(pr.slot_minutes, 10));
  t := (p_day + o) at time zone 'Europe/Prague';
  lim := (p_day + c) at time zone 'Europe/Prague';
  while t + dur <= lim loop
    if t > now() + interval '2 hours' then
      select count(*) into busy from public.reservations r
        where r.company_id = pr.company_id and coalesce(r.canceled, false) = false
          and r.starts_at < t + dur and r.ends_at > t;
      if busy < greatest(pr.capacity, 1) then res := res || to_jsonb(t); end if;
    end if;
    t := t + stp;
  end loop;
  return res;
end $fn$;

-- Vytvoreni rezervace zakaznikem (bez prihlaseni)
create or replace function public.public_book(p_slug text, p_service uuid, p_start timestamptz, p_name text, p_email text, p_phone text)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare pr public.booking_profiles; sv public.booking_services; cid uuid; rid uuid; nm text; em text; ph text;
  ok boolean; cname text; endt timestamptz; recent int;
begin
  nm := btrim(coalesce(p_name, '')); em := lower(btrim(coalesce(p_email, ''))); ph := nullif(btrim(coalesce(p_phone, '')), '');
  if length(nm) < 2 or length(nm) > 120 then raise exception 'bad_name'; end if;
  if em !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' or length(em) > 200 then raise exception 'bad_email'; end if;
  if ph is not null and length(ph) > 40 then raise exception 'bad_phone'; end if;
  select * into pr from public.booking_profiles where slug = lower(p_slug) and enabled;
  if not found then raise exception 'not_found'; end if;
  select * into sv from public.booking_services where id = p_service and company_id = pr.company_id and active;
  if not found then raise exception 'not_found'; end if;
  perform pg_advisory_xact_lock(hashtext(pr.company_id::text));
  select exists (select 1 from jsonb_array_elements_text(public.public_slots(p_slug, p_service, (p_start at time zone 'Europe/Prague')::date)) e
                 where e::timestamptz = p_start) into ok;
  if not ok then raise exception 'slot_taken'; end if;
  select count(*) into recent from public.customers cu join public.reservations r on r.customer_id = cu.id
    where cu.company_id = pr.company_id and lower(cu.email) = em and r.created_at > now() - interval '1 hour';
  if recent >= 3 then raise exception 'too_many'; end if;
  select id into cid from public.customers where company_id = pr.company_id and lower(email) = em limit 1;
  if cid is null then
    insert into public.customers (company_id, name, email, phone) values (pr.company_id, nm, em, ph) returning id into cid;
  end if;
  endt := p_start + make_interval(mins => sv.duration_min);
  insert into public.reservations (company_id, title, customer_id, starts_at, ends_at, canceled)
    values (pr.company_id, 'Online: ' || sv.name || ' - ' || nm, cid, p_start, endt, false) returning id into rid;
  select name into cname from public.companies where id = pr.company_id;
  return jsonb_build_object('ok', true, 'start', p_start, 'end', endt, 'service', sv.name, 'business', cname);
end $fn$;

revoke all on function public.public_booking_info(text) from public;
revoke all on function public.public_slots(text, uuid, date) from public;
revoke all on function public.public_book(text, uuid, timestamptz, text, text, text) from public;
grant execute on function public.public_booking_info(text) to anon, authenticated;
grant execute on function public.public_slots(text, uuid, date) to anon, authenticated;
grant execute on function public.public_book(text, uuid, timestamptz, text, text, text) to anon, authenticated;
