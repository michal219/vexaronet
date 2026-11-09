-- Návrat migrace 20261114100000_registrace_limit.
drop trigger if exists registration_limit_check on public.companies;
drop function if exists private.registration_limit_check();
drop function if exists public.registration_status();
drop function if exists private.registration_used();
drop table if exists private.registration_limit;
notify pgrst, 'reload schema';
