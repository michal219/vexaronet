-- Vexaronet: CRM rozšíření (obchodní případy, nabídky, poznámky ke klientovi).
-- Pouze PŘIDÁVÁ nové tabulky, nic existujícího nemění ani nemaže. Každá firma vidí jen svoje řádky (RLS podle company_members).
-- Zpět: drop table public.client_notes, public.quotes, public.deals cascade;

create table if not exists public.deals (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  title text not null check (char_length(title) between 1 and 200),
  value numeric not null default 0 check (value >= 0),
  stage text not null default 'new' check (stage in ('new','contact','offer','negotiation','won','lost')),
  probability integer not null default 10 check (probability between 0 and 100),
  expected_close date,
  note text check (note is null or char_length(note) <= 4000),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists deals_company on public.deals (company_id, stage);

create table if not exists public.quotes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  deal_id uuid references public.deals(id) on delete set null,
  number text,
  title text check (title is null or char_length(title) <= 200),
  valid_until date,
  items jsonb not null default '[]'::jsonb check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) <= 200),
  total numeric not null default 0 check (total >= 0),
  currency text not null default 'CZK' check (currency in ('CZK','EUR')),
  status text not null default 'draft' check (status in ('draft','sent','accepted','rejected')),
  note text check (note is null or char_length(note) <= 4000),
  invoice_id uuid references public.invoices(id) on delete set null,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (company_id, number)
);
create index if not exists quotes_company on public.quotes (company_id, created_at);

create table if not exists public.client_notes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  kind text not null default 'note' check (kind in ('note','call','meeting','email')),
  body text not null check (char_length(body) between 1 and 4000),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists client_notes_cust on public.client_notes (company_id, customer_id, created_at);

-- Číslo nabídky NYYYY-0001, přidělí databáze (bez duplicit při souběžném zápisu).
create or replace function public.quotes_set_number() returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if new.number is null or new.number = '' then
    perform pg_advisory_xact_lock(hashtext('quotes:' || new.company_id::text));
    new.number := 'N' || extract(year from now())::int || '-' ||
      lpad((coalesce((select max(substring(q.number from '-(\d+)$')::int) from public.quotes q
        where q.company_id = new.company_id and q.number like 'N' || extract(year from now())::int || '-%'), 0) + 1)::text, 4, '0');
  end if;
  return new;
end $$;
drop trigger if exists quotes_number on public.quotes;
create trigger quotes_number before insert on public.quotes for each row execute function public.quotes_set_number();

-- Zákazník a obchodní případ musí patřit do stejné firmy.
create or replace function public.crm_same_company() returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if new.customer_id is not null and not exists (select 1 from public.customers c where c.id = new.customer_id and c.company_id = new.company_id) then
    raise exception 'Zákazník nepatří do této firmy.';
  end if;
  return new;
end $$;
create or replace function public.quotes_same_deal() returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if new.deal_id is not null and not exists (select 1 from public.deals d where d.id = new.deal_id and d.company_id = new.company_id) then
    raise exception 'Obchodní případ nepatří do této firmy.';
  end if;
  return new;
end $$;
drop trigger if exists deals_same on public.deals;
create trigger deals_same before insert or update on public.deals for each row execute function public.crm_same_company();
drop trigger if exists quotes_same on public.quotes;
create trigger quotes_same before insert or update on public.quotes for each row execute function public.crm_same_company();
drop trigger if exists quotes_same_deal on public.quotes;
create trigger quotes_same_deal before insert or update on public.quotes for each row execute function public.quotes_same_deal();
drop trigger if exists notes_same on public.client_notes;
create trigger notes_same before insert or update on public.client_notes for each row execute function public.crm_same_company();

alter table public.deals enable row level security;
alter table public.quotes enable row level security;
alter table public.client_notes enable row level security;

drop policy if exists deals_select on public.deals;
create policy deals_select on public.deals for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = deals.company_id and m.user_id = (select auth.uid())));
drop policy if exists deals_write on public.deals;
create policy deals_write on public.deals for all to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = deals.company_id and m.user_id = (select auth.uid()) and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = deals.company_id and m.user_id = (select auth.uid()) and m.role in ('owner','admin')));

drop policy if exists quotes_select on public.quotes;
create policy quotes_select on public.quotes for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = quotes.company_id and m.user_id = (select auth.uid()) and m.role in ('owner','admin')));
drop policy if exists quotes_write on public.quotes;
create policy quotes_write on public.quotes for all to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = quotes.company_id and m.user_id = (select auth.uid()) and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = quotes.company_id and m.user_id = (select auth.uid()) and m.role in ('owner','admin')));

drop policy if exists notes_select on public.client_notes;
create policy notes_select on public.client_notes for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = client_notes.company_id and m.user_id = (select auth.uid())));
drop policy if exists notes_insert on public.client_notes;
create policy notes_insert on public.client_notes for insert to authenticated
  with check (created_by = (select auth.uid()) and exists (select 1 from public.company_members m where m.company_id = client_notes.company_id and m.user_id = (select auth.uid())));
drop policy if exists notes_manage on public.client_notes;
create policy notes_manage on public.client_notes for update to authenticated
  using (created_by = (select auth.uid())) with check (created_by = (select auth.uid()));
drop policy if exists notes_delete on public.client_notes;
create policy notes_delete on public.client_notes for delete to authenticated
  using (created_by = (select auth.uid()) or exists (select 1 from public.company_members m where m.company_id = client_notes.company_id and m.user_id = (select auth.uid()) and m.role in ('owner','admin')));
