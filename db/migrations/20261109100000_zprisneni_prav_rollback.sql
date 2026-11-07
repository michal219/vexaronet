-- Zpět k 20261109100000_zprisneni_prav.sql: vrátí práva, dvě politiky formulářů a search_path ze záloh private.deploy_backup_20261109_*.
-- Data se nemění. Zálohy se ponechají (smazat ručně, až nebudou potřeba).
begin;
do $$
declare r record;
begin
  if to_regclass('private.deploy_backup_20261109_acl') is null then raise exception 'Chybí záloha private.deploy_backup_20261109_acl.'; end if;
  for r in select obj, grantee, privilege from private.deploy_backup_20261109_acl loop
    if to_regclass(r.obj) is not null then execute format('grant %s on %s to %I', r.privilege, r.obj, r.grantee); end if;
  end loop;
  for r in select tbl, policyname, cmd, roles, qual, with_check from private.deploy_backup_20261109_policy loop
    execute format('drop policy if exists %I on %s', r.policyname, r.tbl);
    execute format('create policy %I on %s for %s to %s%s%s', r.policyname, r.tbl, r.cmd,
      (select string_agg(quote_ident(x), ', ') from unnest(string_to_array(r.roles, ',')) x),
      case when r.qual is not null then ' using (' || r.qual || ')' else '' end,
      case when r.with_check is not null then ' with check (' || r.with_check || ')' else '' end);
  end loop;
  for r in select fn, search_path from private.deploy_backup_20261109_config loop
    execute format('alter function %s set search_path = %s', r.fn, r.search_path);
  end loop;
end $$;
-- migrace výslovně přidala tato práva anon (byla zahrnuta v "arwdDxtm"), záloha je obnoví v plném rozsahu výše
notify pgrst, 'reload schema';
commit;
