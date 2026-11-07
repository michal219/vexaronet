-- Pomocné funkce testů (existují jen v dané relaci, schéma pg_temp). Načítá se příkazem \i uvnitř transakce.
create function pg_temp.call_as(uid uuid, r text, q text) returns jsonb language plpgsql as $$
declare res jsonb;
begin
  perform set_config('request.jwt.claims',
    case when uid is null then json_build_object('role', r)::text else json_build_object('sub', uid, 'role', r)::text end, true);
  execute format('set local role %I', r);
  execute q into res;
  execute 'reset role';
  return res;
end $$;

create function pg_temp.expect_as(uid uuid, r text, q text, state text, label text, must_detail text default null) returns void language plpgsql as $$
declare d text;
begin
  begin
    perform pg_temp.call_as(uid, r, q);
    raise exception 'TEST_FAIL %: očekávána chyba %, ale příkaz proběhl', label, state using errcode = 'XX999';
  exception when others then
    execute 'reset role';
    if sqlstate = 'XX999' then raise; end if;
    get stacked diagnostics d = pg_exception_detail;
    if sqlstate <> state then
      raise exception 'TEST_FAIL %: očekáván SQLSTATE %, je % (%)', label, state, sqlstate, sqlerrm using errcode = 'XX999';
    end if;
    if must_detail is not null and position(must_detail in coalesce(d, '') || ' ' || sqlerrm) = 0 then
      raise exception 'TEST_FAIL %: v detailu chybí "%", detail="%"', label, must_detail, d using errcode = 'XX999';
    end if;
  end;
  raise notice 'ok  %', label;
end $$;

create function pg_temp.ok(cond boolean, label text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'TEST_FAIL %', label using errcode = 'XX999'; end if;
  raise notice 'ok  %', label;
end $$;

