-- Zpět k původnímu stavu zjištěnému auditem 2026-11-07 (včetně původně příliš širokých práv).
begin;
alter table private.platform_admins        disable row level security;
alter table private.ai_requests            disable row level security;
alter table private.feedback_mail_delivery disable row level security;
alter table private.push_deliveries        disable row level security;

grant all on public.ai_usage, public.company_invites, public.plan_requests to anon, authenticated;

grant execute on function public.clock_in(uuid, uuid)    to public, anon;
grant execute on function public.clock_out(uuid, uuid)   to public, anon;
grant execute on function public.shop_cancel_order(uuid) to public, anon;
notify pgrst, 'reload schema';
commit;
