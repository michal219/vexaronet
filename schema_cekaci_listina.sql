-- Vexaronet: čekací listina. Zájemci, kteří chtějí termín, jenž je právě obsazený, a ozvete se jim, až se něco uvolní.
-- Pouze PŘIDÁVÁ novou tabulku, nic existujícího nemění. Každá firma vidí jen svoje řádky; zapisovat smí členové s platným předplatným.
-- Zpět: drop table public.waitlist;

create table if not exists public.waitlist (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  name text not null check (char_length(btrim(name)) between 1 and 200),
  email text check (email is null or char_length(email) <= 254),
  phone text check (phone is null or char_length(phone) <= 40),
  service_id uuid references public.booking_services(id) on delete set null,
  wanted text check (wanted is null or char_length(wanted) <= 300),
  note text check (note is null or char_length(note) <= 2000),
  status text not null default 'waiting' check (status in ('waiting','offered','booked','dropped')),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (email is not null or phone is not null or customer_id is not null)
);
create index if not exists waitlist_company on public.waitlist (company_id, status, created_at);

-- zákazník a služba musí patřit do stejné firmy jako záznam
create or replace function private.waitlist_same_company() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.customer_id is not null and not exists (select 1 from public.customers c where c.id = new.customer_id and c.company_id = new.company_id) then
    raise exception 'Zákazník patří do jiné firmy.' using errcode = '42501';
  end if;
  if new.service_id is not null and not exists (select 1 from public.booking_services s where s.id = new.service_id and s.company_id = new.company_id) then
    raise exception 'Služba patří do jiné firmy.' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists waitlist_same_company on public.waitlist;
create trigger waitlist_same_company before insert or update on public.waitlist for each row execute function private.waitlist_same_company();

alter table public.waitlist enable row level security;
drop policy if exists waitlist_select on public.waitlist;
create policy waitlist_select on public.waitlist for select to authenticated using (private.member_role(company_id) is not null);
drop policy if exists waitlist_insert on public.waitlist;
create policy waitlist_insert on public.waitlist for insert to authenticated
  with check (private.member_role(company_id) is not null and private.writable(company_id));
drop policy if exists waitlist_update on public.waitlist;
create policy waitlist_update on public.waitlist for update to authenticated
  using (private.member_role(company_id) is not null and private.writable(company_id))
  with check (private.member_role(company_id) is not null and private.writable(company_id));
drop policy if exists waitlist_delete on public.waitlist;
create policy waitlist_delete on public.waitlist for delete to authenticated
  using (private.member_role(company_id) is not null and private.writable(company_id));
revoke all on public.waitlist from anon;
grant select, insert, update, delete on public.waitlist to authenticated;
