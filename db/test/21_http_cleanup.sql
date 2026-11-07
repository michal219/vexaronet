-- Úklid po 20_http_fixture.sql: smaže testovací firmu a (kaskádou) její profil, verze i události.
delete from public.companies where id = '00000000-0000-0000-0000-00000000f001';
