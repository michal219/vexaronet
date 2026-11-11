-- Výchozí stav pro migraci 20261115100000_ai_tym.sql: tabulky, které migrace čte nebo do nich zapisuje, ve tvaru produkce (katalog 2026-11-11).
alter table public.deals add column if not exists customer_id uuid, add column if not exists value numeric not null default 0, add column if not exists stage text not null default 'new',
  add column if not exists probability integer, add column if not exists expected_close date, add column if not exists note text, add column if not exists updated_at timestamptz not null default now();
alter table public.customers add column if not exists archived boolean not null default false, add column if not exists ico text;
alter table public.reservations add column if not exists starts_at timestamptz, add column if not exists canceled boolean not null default false;
alter table public.shop_orders add column if not exists total numeric not null default 0, add column if not exists status text not null default 'new';
alter table public.sites add column if not exists data jsonb not null default '{}'::jsonb;
create table if not exists public.tasks (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade, title text not null check (length(title) between 1 and 200),
  due_at timestamptz, assigned_to uuid, completed boolean not null default false, created_at timestamptz not null default now(), description text check (length(description) <= 4000));
create table if not exists public.client_notes (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade, customer_id uuid not null,
  kind text not null default 'note' check (kind in ('note','call','meeting','email')), body text not null check (char_length(body) between 1 and 4000), created_by uuid, created_at timestamptz not null default now());
create table if not exists public.quotes (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade, customer_id uuid, deal_id uuid, number text, title text,
  valid_until date, items jsonb not null default '[]'::jsonb, total numeric not null default 0, currency text not null default 'CZK', status text not null default 'draft' check (status in ('draft','sent','accepted','rejected')),
  note text, invoice_id uuid, created_by uuid, created_at timestamptz not null default now());
create table if not exists public.financial_entries (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade, title text not null check (length(title) between 1 and 200),
  amount numeric not null check (amount > 0), kind text not null check (kind in ('income','expense')), entry_date date not null, created_at timestamptz not null default now());
create table if not exists public.invoices (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade, lifecycle text not null default 'draft', number text,
  variable_symbol text, issued_on date, taxable_supply_on date, due_on date, vat_payer boolean not null default false, customer_snapshot jsonb, total numeric not null default 0, paid_at timestamptz, currency text not null default 'CZK', created_at timestamptz not null default now());
create table if not exists public.invoice_items (id uuid primary key default gen_random_uuid(), company_id uuid not null, invoice_id uuid not null references public.invoices(id) on delete cascade, vat_rate numeric not null default 0,
  gross numeric not null default 0, net numeric not null default 0, tax numeric not null default 0);
create table if not exists public.products (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade, name text not null, price numeric not null default 0,
  active boolean not null default true, shop_visible boolean not null default false, description text, created_at timestamptz not null default now());
create table if not exists public.jobs (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade, title text not null, price numeric not null default 0,
  status text not null default 'new', due_at timestamptz, created_at timestamptz not null default now());
create table if not exists private.bank_transactions (id uuid primary key default gen_random_uuid(), company_id uuid not null, status text not null default 'unmatched', amount_cents bigint not null default 1, created_at timestamptz not null default now());
do $$ declare t text; begin
  foreach t in array array['tasks','client_notes','quotes','financial_entries','invoices','invoice_items','products','jobs'] loop
    execute format('alter table public.%I enable row level security', t); execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop; end $$;
alter table private.bank_transactions enable row level security; revoke all on private.bank_transactions from public, anon, authenticated;
