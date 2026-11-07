-- =====================================================================================
-- Vexaronet: bezpečnostní opravy z auditu (2026-11-07), připraveno 2026-11-08
-- STAV: PŘIPRAVENO, NEAPLIKOVÁNO NA PRODUKCI. Aplikovat jen po výslovném souhlasu vlastníka,
--       předtím vyzkoušet na testovacím projektu (docs/BEZPECNOSTNI_OPRAVY.md).
--
-- Mění POUZE práva a RLS na 10 pojmenovaných objektech. Nemění data, tabulky, funkce ani politiky.
--   A) zapíná RLS na 4 tabulkách ve schématu private (druhá pojistka; přístup k nim už nikdo
--      z anon/authenticated nemá, funkce SECURITY DEFINER vlastněné postgres RLS obcházejí)
--   B) odebírá anon všechna práva na ai_usage, company_invites, plan_requests a authenticated
--      práva, která RLS stejně neumožňuje (UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER)
--   C) odebírá PUBLIC a anon právo EXECUTE na clock_in, clock_out, shop_cancel_order
--      (volá je jen přihlášená aplikace; anon je beztak odmítne, ale nemá je mít dosažitelné)
-- NEŘEŠÍ (jiná místa): ochranu proti uniklým heslům (dashboard Supabase Auth), sjednocení
--   limitů týmu a limity reserve_ai (viz docs/BEZPECNOSTNI_OPRAVY.md).
-- Zpět: db/migrations/20261108100000_bezpecnostni_opravy_rollback.sql
-- =====================================================================================
begin;

do $$ begin
  if to_regclass('private.platform_admins') is null or to_regclass('private.ai_requests') is null
     or to_regclass('private.feedback_mail_delivery') is null or to_regclass('private.push_deliveries') is null
     or to_regclass('public.ai_usage') is null or to_regclass('public.company_invites') is null
     or to_regclass('public.plan_requests') is null
     or to_regprocedure('public.clock_in(uuid,uuid)') is null or to_regprocedure('public.clock_out(uuid,uuid)') is null
     or to_regprocedure('public.shop_cancel_order(uuid)') is null then
    raise exception 'Chybí některý z očekávaných objektů. Toto není databáze, pro kterou byla migrace napsána.';
  end if;
end $$;

-- A) RLS jako druhá pojistka (bez politik = nikdo kromě vlastníka tabulky a rolí s BYPASSRLS)
alter table private.platform_admins        enable row level security;
alter table private.ai_requests            enable row level security;
alter table private.feedback_mail_delivery enable row level security;
alter table private.push_deliveries        enable row level security;

-- B) nejmenší nutná práva (RLS politiky těchto tabulek jsou jen pro authenticated: SELECT a INSERT)
revoke all on public.ai_usage, public.company_invites, public.plan_requests from anon;
revoke all on public.ai_usage, public.company_invites, public.plan_requests from authenticated;
grant select, insert on public.ai_usage      to authenticated;   -- AI Účetní: čtení počítadla, zápis zpracovaného dokladu
grant select         on public.company_invites to authenticated;   -- seznam pozvánek; zápis jen přes invite_member/cancel_invite
grant select, insert on public.plan_requests to authenticated;   -- žádost o změnu tarifu

-- C) funkce jen pro přihlášené (PUBLIC musí pryč, jinak by anon právo dědil)
revoke all on function public.clock_in(uuid, uuid)    from public, anon;
revoke all on function public.clock_out(uuid, uuid)   from public, anon;
revoke all on function public.shop_cancel_order(uuid) from public, anon;
grant execute on function public.clock_in(uuid, uuid)    to authenticated, service_role;
grant execute on function public.clock_out(uuid, uuid)   to authenticated, service_role;
grant execute on function public.shop_cancel_order(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';
commit;
