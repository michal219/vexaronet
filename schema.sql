-- Vexaronet: NÁVRH databázového schématu pro Supabase (PostgreSQL). Etapa 2.
-- Stav: návrh, zatím nenasazeno do žádné ostré databáze.
-- Princip: každá firma (organizations) má oddělená data, přístup řídí členství (org_members) a RLS.

create extension if not exists pgcrypto;

create type org_role as enum ('owner','admin','accountant','sales','employee','viewer');
create type plan_code as enum ('starter','pro','business','enterprise');

create table organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  business_type text,                       -- služby, autoservis, e-shop, restaurace, jiný
  country char(2) not null default 'CZ',
  created_at timestamptz not null default now()
);

create table org_members (
  org_id uuid not null references organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role org_role not null default 'employee',
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);

create table subscriptions (
  org_id uuid primary key references organizations(id) on delete cascade,
  plan plan_code not null default 'pro',
  trial_ends_at timestamptz not null default now() + interval '30 days',
  status text not null default 'trial',     -- trial, active, past_due, canceled
  created_at timestamptz not null default now()
);

-- ceník upravitelný v administraci (ceny se doplní, nejsou v kódu napevno)
create table plan_prices (
  plan plan_code primary key,
  monthly_czk numeric(10,2),                -- null = individuální nebo zatím neurčeno
  updated_at timestamptz not null default now()
);

create table customers (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  name text not null, email text, phone text, ico text, address text, note text,
  created_at timestamptz not null default now()
);

create table jobs (                          -- zakázky
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  customer_id uuid references customers(id) on delete set null,
  title text not null, status text not null default 'nova',
  amount numeric(12,2), due_date date,
  created_at timestamptz not null default now()
);

create table tasks (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  job_id uuid references jobs(id) on delete cascade,
  assignee uuid references auth.users(id) on delete set null,
  title text not null, done boolean not null default false, due_date date,
  created_at timestamptz not null default now()
);

create table events (                        -- kalendář a rezervace
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  customer_id uuid references customers(id) on delete set null,
  title text not null, starts_at timestamptz not null, ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table invoices (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  customer_id uuid references customers(id) on delete set null,
  job_id uuid references jobs(id) on delete set null,
  number text not null, issued_on date not null default current_date, due_on date not null,
  currency char(3) not null default 'CZK', status text not null default 'draft', -- draft, sent, paid, void
  created_at timestamptz not null default now(),
  unique (org_id, number)
);
create table invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references invoices(id) on delete cascade,
  description text not null, quantity numeric(12,3) not null default 1,
  unit_price numeric(12,2) not null, vat_rate numeric(5,2) not null default 21
);

-- Fronta akcí AI: nic důležitého se neprovede bez schválení uživatele.
create table ai_actions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  kind text not null,                        -- např. send_reminder, create_invoice
  summary text not null, payload jsonb not null default '{}',
  status text not null default 'pending',    -- pending, approved, rejected, done, failed
  decided_by uuid references auth.users(id), decided_at timestamptz,
  created_at timestamptz not null default now()
);

-- pomocné funkce pro RLS
create function is_member(o uuid) returns boolean language sql stable security definer set search_path = public as
$$ select exists(select 1 from org_members where org_id = o and user_id = auth.uid()) $$;
create function has_role(o uuid, r org_role[]) returns boolean language sql stable security definer set search_path = public as
$$ select exists(select 1 from org_members where org_id = o and user_id = auth.uid() and role = any(r)) $$;

alter table organizations enable row level security;
alter table org_members enable row level security;
alter table subscriptions enable row level security;
alter table customers enable row level security;
alter table jobs enable row level security;
alter table tasks enable row level security;
alter table events enable row level security;
alter table invoices enable row level security;
alter table invoice_items enable row level security;
alter table ai_actions enable row level security;
alter table plan_prices enable row level security;

create policy org_read on organizations for select using (is_member(id));
create policy mem_read on org_members for select using (is_member(org_id));
create policy sub_read on subscriptions for select using (is_member(org_id));
create policy price_read on plan_prices for select using (true);

create policy customers_all on customers for all using (is_member(org_id)) with check (is_member(org_id));
create policy jobs_all on jobs for all using (is_member(org_id)) with check (is_member(org_id));
create policy tasks_all on tasks for all using (is_member(org_id)) with check (is_member(org_id));
create policy events_all on events for all using (is_member(org_id)) with check (is_member(org_id));

-- faktury jen role s účetním oprávněním
create policy inv_all on invoices for all
  using (has_role(org_id, array['owner','admin','accountant']::org_role[]))
  with check (has_role(org_id, array['owner','admin','accountant']::org_role[]));
create policy invi_all on invoice_items for all
  using (exists(select 1 from invoices i where i.id = invoice_id and has_role(i.org_id, array['owner','admin','accountant']::org_role[])))
  with check (exists(select 1 from invoices i where i.id = invoice_id and has_role(i.org_id, array['owner','admin','accountant']::org_role[])));

-- AI akce: čtení členové, schválení jen owner/admin; zápis nových návrhů dělá server (service role)
create policy ai_read on ai_actions for select using (is_member(org_id));
create policy ai_decide on ai_actions for update
  using (has_role(org_id, array['owner','admin']::org_role[]))
  with check (has_role(org_id, array['owner','admin']::org_role[]));

-- Vytvoření firmy + členství vlastníka + zkušební období dělá serverová funkce po registraci (viz ARCHITEKTURA.md).
