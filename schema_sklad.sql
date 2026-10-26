-- Vexaronet: Sklad a produkty (karty zbozi + pohyby skladu). Nic existujiciho nemaze.
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  sku text,
  unit text not null default 'ks',
  cost numeric,
  price numeric,
  min_qty numeric not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists products_company on public.products (company_id);

create table if not exists public.stock_moves (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  qty numeric not null,
  kind text not null default 'in' check (kind in ('in','out','adjust')),
  note text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists stock_moves_company on public.stock_moves (company_id, created_at);
create index if not exists stock_moves_product on public.stock_moves (product_id);

alter table public.products enable row level security;
drop policy if exists prod_select on public.products;
create policy prod_select on public.products for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = products.company_id and m.user_id = auth.uid()));
drop policy if exists prod_write on public.products;
create policy prod_write on public.products for all to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = products.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = products.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));

alter table public.stock_moves enable row level security;
drop policy if exists smv_select on public.stock_moves;
create policy smv_select on public.stock_moves for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = stock_moves.company_id and m.user_id = auth.uid()));
drop policy if exists smv_write on public.stock_moves;
create policy smv_write on public.stock_moves for all to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = stock_moves.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = stock_moves.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')) and exists (select 1 from public.products p where p.id = stock_moves.product_id and p.company_id = stock_moves.company_id));
