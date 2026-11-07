-- =====================================================================================
-- Vexaronet: profil firmy (ruční vyplnění, verzování, potvrzení)           2026-11-07
-- První část AI onboardingu. Žádná AI, žádné placené volání. Viz docs/ai-onboarding-spec.md.
--
-- STAV: PŘIPRAVENO, NEAPLIKOVÁNO NA PRODUKCI. Ověřeno jen v oddělené testovací databázi
-- (viz docs/TESTOVACI_PROSTREDI.md). Před aplikací na produkci: schválení vlastníkem.
--
-- Co migrace dělá:
--   * PŘIDÁVÁ 4 tabulky ve schématu private + funkce profile_* a vx_*. Nic existujícího
--     nemění, nemaže ani nepřepisuje (žádné ALTER existujících tabulek, žádné GRANT/REVOKE
--     na existující objekty, žádné změny AI limitů ani workspace_config).
--   * Tabulky jsou pro anon i authenticated nedostupné; klient chodí jen přes RPC public.profile_*.
--   * Společné údaje patří hlavní firmě (companies.parent_company_id is null); pobočka má
--     jen vlastní sekci "local" (lokalita, lokální odlišnosti).
--   * Konflikt revize: SQLSTATE PT409 (PostgREST ho vrací jako HTTP 409).
--     Neplatná data: PT422. Neshoda verze schématu: PT412. Oprávnění: 42501.
--
-- Závislosti (musí existovat, jinak migrace skončí chybou): public.companies,
--   private.member_role(uuid), private.writable(uuid), private.business_root(uuid), auth.uid().
-- Zpět: db/migrations/20261107120000_profil_firmy_rollback.sql
-- =====================================================================================
begin;

do $$ begin
  if to_regclass('public.companies') is null
     or to_regprocedure('private.member_role(uuid)') is null
     or to_regprocedure('private.writable(uuid)') is null
     or to_regprocedure('private.business_root(uuid)') is null then
    raise exception 'Chybí základ aplikace (companies, member_role, writable, business_root).';
  end if;
end $$;

-- ---------------------------------------------------------------------------------
-- 1) Sdílené schéma (generováno z src/onboarding_schema.json)
-- ---------------------------------------------------------------------------------
-- BEGIN GENERATED SCHEMA (neupravovat ručně; python3 tools/sync_profile_schema.py)
create or replace function private.profile_schema() returns jsonb
  language sql immutable set search_path = '' as $vxschema$select $vxjson$
{
 "version": 1,
 "title": "Profil firmy Vexaronet (ruční vyplnění, MVP)",
 "shared": {
  "type": "object",
  "additionalProperties": false,
  "properties": {
   "identity": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
     "displayName": {
      "type": "string",
      "minLength": 2,
      "maxLength": 120
     },
     "activity": {
      "type": "string",
      "maxLength": 1000
     },
     "website": {
      "type": [
       "string",
       "null"
      ],
      "format": "http-url",
      "maxLength": 300
     }
    }
   },
   "services": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
     "items": {
      "type": "array",
      "maxItems": 30,
      "items": {
       "type": "object",
       "additionalProperties": false,
       "required": [
        "name"
       ],
       "properties": {
        "name": {
         "type": "string",
         "minLength": 2,
         "maxLength": 120
        },
        "description": {
         "type": "string",
         "maxLength": 500
        },
        "priority": {
         "type": "string",
         "enum": [
          "low",
          "normal",
          "high"
         ]
        }
       }
      }
     },
     "notes": {
      "type": "string",
      "maxLength": 1000
     }
    }
   },
   "audience": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
     "description": {
      "type": "string",
      "maxLength": 1000
     },
     "segments": {
      "type": "array",
      "maxItems": 10,
      "items": {
       "type": "string",
       "minLength": 2,
       "maxLength": 120
      }
     }
    }
   },
   "positioning": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
     "claims": {
      "type": "array",
      "maxItems": 10,
      "items": {
       "type": "object",
       "additionalProperties": false,
       "required": [
        "text"
       ],
       "properties": {
        "text": {
         "type": "string",
         "minLength": 2,
         "maxLength": 300
        },
        "evidence": {
         "type": "string",
         "enum": [
          "none",
          "owner_statement",
          "documented"
         ]
        }
       }
      }
     }
    }
   },
   "brand": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
     "tone": {
      "type": "string",
      "maxLength": 200
     },
     "ordering": {
      "type": "string",
      "maxLength": 500
     },
     "assets": {
      "type": "string",
      "maxLength": 500
     },
     "forbidden": {
      "type": "array",
      "maxItems": 20,
      "items": {
       "type": "string",
       "minLength": 2,
       "maxLength": 120
      }
     }
    }
   },
   "financialContext": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
     "revenueMinor": {
      "type": [
       "integer",
       "null"
      ],
      "minimum": 0,
      "maximum": 1000000000000
     },
     "revenueCurrency": {
      "type": [
       "string",
       "null"
      ],
      "enum": [
       "CZK",
       "EUR",
       null
      ]
     },
     "revenuePeriod": {
      "type": [
       "string",
       "null"
      ],
      "enum": [
       "month",
       "year",
       null
      ]
     },
     "budgetMinor": {
      "type": [
       "integer",
       "null"
      ],
      "minimum": 0,
      "maximum": 1000000000000
     },
     "budgetCurrency": {
      "type": [
       "string",
       "null"
      ],
      "enum": [
       "CZK",
       "EUR",
       null
      ]
     },
     "budgetPeriod": {
      "type": [
       "string",
       "null"
      ],
      "enum": [
       "month",
       "quarter",
       "year",
       "one_time",
       null
      ]
     },
     "budgetIncludes": {
      "type": "array",
      "maxItems": 4,
      "items": {
       "type": "string",
       "enum": [
        "ads",
        "content",
        "tools",
        "other"
       ]
      }
     }
    }
   },
   "goals": {
    "type": "array",
    "maxItems": 5,
    "items": {
     "type": "object",
     "additionalProperties": false,
     "required": [
      "metric"
     ],
     "properties": {
      "metric": {
       "type": "string",
       "enum": [
        "revenue",
        "jobs",
        "new_customers",
        "leads",
        "other"
       ]
      },
      "label": {
       "type": "string",
       "maxLength": 120
      },
      "baselineMinor": {
       "type": [
        "integer",
        "null"
       ],
       "minimum": 0,
       "maximum": 1000000000000
      },
      "growthBp": {
       "type": [
        "integer",
        "null"
       ],
       "minimum": 0,
       "maximum": 100000
      },
      "targetMinor": {
       "type": [
        "integer",
        "null"
       ],
       "minimum": 0,
       "maximum": 1000000000000
      },
      "targetSource": {
       "type": "string",
       "enum": [
        "user",
        "calc"
       ]
      },
      "startDate": {
       "type": [
        "string",
        "null"
       ],
       "format": "date"
      },
      "dueDate": {
       "type": [
        "string",
        "null"
       ],
       "format": "date"
      }
     }
    }
   },
   "channels": {
    "type": "array",
    "maxItems": 10,
    "items": {
     "type": "object",
     "additionalProperties": false,
     "required": [
      "channel"
     ],
     "properties": {
      "channel": {
       "type": "string",
       "enum": [
        "facebook",
        "instagram",
        "google_business",
        "web",
        "email",
        "other"
       ]
      },
      "note": {
       "type": "string",
       "maxLength": 200
      }
     }
    }
   },
   "constraints": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
     "notes": {
      "type": "string",
      "maxLength": 1000
     }
    }
   },
   "unknowns": {
    "type": "array",
    "maxItems": 30,
    "items": {
     "type": "object",
     "additionalProperties": false,
     "required": [
      "field"
     ],
     "properties": {
      "field": {
       "type": "string",
       "minLength": 1,
       "maxLength": 80
      },
      "question": {
       "type": "string",
       "maxLength": 300
      },
      "blocking": {
       "type": "boolean"
      }
     }
    }
   }
  }
 },
 "local": {
  "type": "object",
  "additionalProperties": false,
  "properties": {
   "geography": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
     "city": {
      "type": "string",
      "maxLength": 120
     },
     "address": {
      "type": "string",
      "maxLength": 300
     },
     "serviceArea": {
      "type": "string",
      "maxLength": 300
     },
     "radiusKm": {
      "type": [
       "integer",
       "null"
      ],
      "minimum": 0,
      "maximum": 500
     }
    }
   },
   "localNotes": {
    "type": "string",
    "maxLength": 1000
   }
  }
 }
}
$vxjson$::jsonb$vxschema$;
-- END GENERATED SCHEMA

create or replace function private.profile_schema_version() returns integer
  language sql stable set search_path = '' as $$select (private.profile_schema()->>'version')::integer$$;

-- ---------------------------------------------------------------------------------
-- 2) Tabulky (private; RLS zapnuté; žádná práva pro anon ani authenticated)
-- ---------------------------------------------------------------------------------
create table if not exists private.company_profile_drafts (
  company_id     uuid primary key references public.companies(id) on delete cascade,
  revision       integer not null default 1 check (revision >= 1),
  schema_version integer not null,
  data           jsonb not null default '{}'::jsonb
                 check (jsonb_typeof(data) = 'object' and pg_column_size(data) <= 65536),
  updated_by     uuid references auth.users(id) on delete set null,
  updated_at     timestamptz not null default now()
);

create table if not exists private.company_profile_versions (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references public.companies(id) on delete cascade,
  version         integer not null check (version >= 1),
  schema_version  integer not null,
  data            jsonb not null check (jsonb_typeof(data) = 'object' and pg_column_size(data) <= 65536),
  content_hash    text not null check (content_hash ~ '^[0-9a-f]{64}$'),
  source_revision integer not null,
  confirmed_by    uuid references auth.users(id) on delete set null,
  confirmed_at    timestamptz not null default now(),
  unique (company_id, version),
  unique (company_id, id)
);

create table if not exists private.company_active_profile (
  company_id uuid primary key references public.companies(id) on delete cascade,
  version_id uuid not null,
  foreign key (company_id, version_id) references private.company_profile_versions (company_id, id)
);

create table if not exists private.company_profile_events (
  id          bigint generated always as identity primary key,
  company_id  uuid not null references public.companies(id) on delete cascade,
  actor       uuid,
  operation   text not null check (operation in ('draft_created', 'confirm')),
  version     integer,
  revision    integer,
  created_at  timestamptz not null default now()
);
create index if not exists company_profile_events_company_idx on private.company_profile_events (company_id, created_at);

alter table private.company_profile_drafts   enable row level security;
alter table private.company_profile_versions enable row level security;
alter table private.company_active_profile   enable row level security;
alter table private.company_profile_events   enable row level security;
revoke all on private.company_profile_drafts, private.company_profile_versions,
              private.company_active_profile, private.company_profile_events from public, anon, authenticated;

-- Potvrzené verze a události jsou neměnné (úprava = nová verze). Mazání je povoleno jen kaskádou
-- při smazání firmy (výmaz dat), proto trigger hlídá jen UPDATE.
create or replace function private.vx_block_update() returns trigger
  language plpgsql set search_path = '' as $$begin raise exception 'immutable_record'; end$$;
drop trigger if exists company_profile_versions_immutable on private.company_profile_versions;
create trigger company_profile_versions_immutable before update on private.company_profile_versions
  for each row execute function private.vx_block_update();
drop trigger if exists company_profile_events_immutable on private.company_profile_events;
create trigger company_profile_events_immutable before update on private.company_profile_events
  for each row execute function private.vx_block_update();

-- ---------------------------------------------------------------------------------
-- 3) Validátor podmnožiny JSON Schema (shodný s src/jsonschema_mini.js, hlídá tests/profile_parity.py)
-- ---------------------------------------------------------------------------------
create or replace function private.vx_sort(a text[]) returns text[]
  language sql immutable set search_path = '' as
$$select coalesce(array_agg(e order by e collate "C"), '{}'::text[]) from unnest(a) e$$;

create or replace function private.vx_json_validate(sch jsonb, doc jsonb, p text default '$') returns text[]
  language plpgsql immutable set search_path = '' as $$
declare
  errs text[] := '{}'; t text; ok boolean := false; tt text; k text; v jsonb; i integer; n integer;
  fmt text; str text; num numeric; allowed jsonb; auth_part text;
begin
  t := coalesce(jsonb_typeof(doc), 'null');
  if sch ? 'type' then
    allowed := case when jsonb_typeof(sch->'type') = 'array' then sch->'type' else jsonb_build_array(sch->'type') end;
    for tt in select jsonb_array_elements_text(allowed) loop
      if tt = t then ok := true;
      elsif tt = 'integer' and t = 'number' and (doc #>> '{}')::numeric = trunc((doc #>> '{}')::numeric) then ok := true;
      end if;
    end loop;
    if not ok then return array[p || ':type']; end if;
  end if;
  if sch ? 'enum' and not (sch->'enum' @> jsonb_build_array(doc)) then return array[p || ':enum']; end if;

  if t = 'string' then
    str := doc #>> '{}';
    if sch ? 'minLength' and char_length(str) < (sch->>'minLength')::integer then errs := errs || (p || ':minLength'); end if;
    if sch ? 'maxLength' and char_length(str) > (sch->>'maxLength')::integer then errs := errs || (p || ':maxLength'); end if;
    fmt := sch->>'format';
    if fmt = 'date' then
      if str !~ '^(19|20|21)[0-9]{2}-[0-9]{2}-[0-9]{2}$' then errs := errs || (p || ':format');
      else
        begin
          if to_char(str::date, 'YYYY-MM-DD') <> str then errs := errs || (p || ':format'); end if;
        exception when others then errs := errs || (p || ':format');
        end;
      end if;
    elsif fmt = 'http-url' then
      if str !~ '^[!-~]+$' or str !~ '^https?://' then errs := errs || (p || ':format');
      else
        auth_part := substring(str from '^https?://([^/?#]*)');
        if auth_part is null or auth_part = '' or position('@' in auth_part) > 0 then errs := errs || (p || ':format'); end if;
      end if;
    end if;
  elsif t = 'number' then
    num := (doc #>> '{}')::numeric;
    if sch ? 'minimum' and num < (sch->>'minimum')::numeric then errs := errs || (p || ':minimum'); end if;
    if sch ? 'maximum' and num > (sch->>'maximum')::numeric then errs := errs || (p || ':maximum'); end if;
  elsif t = 'array' then
    n := jsonb_array_length(doc);
    if sch ? 'minItems' and n < (sch->>'minItems')::integer then errs := errs || (p || ':minItems'); end if;
    if sch ? 'maxItems' and n > (sch->>'maxItems')::integer then errs := errs || (p || ':maxItems'); end if;
    if sch ? 'items' then
      for i in 0 .. n - 1 loop
        errs := errs || private.vx_json_validate(sch->'items', doc->i, p || '[' || i || ']');
      end loop;
    end if;
  elsif t = 'object' then
    if sch ? 'required' then
      for k in select jsonb_array_elements_text(sch->'required') loop
        if not (doc ? k) then errs := errs || (p || '.' || k || ':required'); end if;
      end loop;
    end if;
    for k, v in select * from jsonb_each(doc) loop
      if sch->'properties' ? k then
        errs := errs || private.vx_json_validate(sch->'properties'->k, v, p || '.' || k);
      elsif sch->'additionalProperties' = 'false'::jsonb then
        errs := errs || (p || '.' || k || ':additional');
      end if;
    end loop;
  end if;
  return private.vx_sort(errs);
end $$;

-- Dokument profilu = {shared:{…}, local:{…}}; pobočka smí mít jen local.
create or replace function private.vx_profile_validate(doc jsonb, is_root boolean) returns text[]
  language plpgsql stable set search_path = '' as $$
declare errs text[] := '{}'; k text; sch jsonb := private.profile_schema();
begin
  if coalesce(jsonb_typeof(doc), 'null') <> 'object' then return array['$:type']; end if;
  for k in select jsonb_object_keys(doc) loop
    if k not in ('shared', 'local') then errs := errs || ('$.' || k || ':additional'); end if;
  end loop;
  if doc ? 'shared' then
    if not is_root and jsonb_typeof(doc->'shared') = 'object' and doc->'shared' <> '{}'::jsonb then
      errs := errs || '$.shared:branch_not_allowed'::text;
    else
      errs := errs || private.vx_json_validate(sch->'shared', doc->'shared', '$.shared');
    end if;
  end if;
  if doc ? 'local' then
    errs := errs || private.vx_json_validate(sch->'local', doc->'local', '$.local');
  end if;
  return private.vx_sort(errs);
end $$;

-- ---------------------------------------------------------------------------------
-- 4) Normalizace a odvozené hodnoty (shodné s profile_core.js: trimDeep, applyDerived, goalTarget)
-- ---------------------------------------------------------------------------------
create or replace function private.vx_trim(j jsonb) returns jsonb
  language sql immutable set search_path = '' as
$$select case jsonb_typeof(j)
  when 'string' then to_jsonb(regexp_replace(j #>> '{}', '^[ \t\r\n]+|[ \t\r\n]+$', '', 'g'))
  when 'array'  then coalesce((select jsonb_agg(private.vx_trim(e) order by ord) from jsonb_array_elements(j) with ordinality t(e, ord)), '[]'::jsonb)
  when 'object' then coalesce((select jsonb_object_agg(k, private.vx_trim(v)) from jsonb_each(j) t(k, v)), '{}'::jsonb)
  else j end$$;

create or replace function private.vx_goal_target(baseline bigint, bp integer) returns bigint
  language sql immutable set search_path = '' as
$$select floor((baseline::numeric * (10000 + bp) + 5000) / 10000)::bigint$$;

create or replace function private.vx_apply_derived(doc jsonb) returns jsonb
  language plpgsql immutable set search_path = '' as $$
declare goals jsonb;
begin
  if jsonb_typeof(doc #> '{shared,goals}') is distinct from 'array' or jsonb_array_length(doc #> '{shared,goals}') = 0 then
    return doc;
  end if;
  select jsonb_agg(
    case
      when (g->>'baselineMinor') is not null and (g->>'growthBp') is not null then
        g || jsonb_build_object('targetMinor', private.vx_goal_target((g->>'baselineMinor')::bigint, (g->>'growthBp')::integer), 'targetSource', 'calc')
      when (g->>'targetMinor') is not null then g || '{"targetSource":"user"}'::jsonb
      else g - 'targetSource'
    end order by ord)
  into goals
  from jsonb_array_elements(doc #> '{shared,goals}') with ordinality t(g, ord);
  return jsonb_set(doc, '{shared,goals}', goals);
end $$;

create or replace function private.vx_hash(j jsonb) returns text
  language sql immutable set search_path = '' as $$select encode(sha256(convert_to(j::text, 'UTF8')), 'hex')$$;

-- ---------------------------------------------------------------------------------
-- 5) Úplnost pro potvrzení (shodná s profile_core.js: incomplete)
-- ---------------------------------------------------------------------------------
create or replace function private.vx_has(j jsonb) returns boolean
  language sql immutable set search_path = '' as $$select j is not null and jsonb_typeof(j) <> 'null'$$;
create or replace function private.vx_nonempty(j jsonb) returns boolean
  language sql immutable set search_path = '' as $$select coalesce(jsonb_typeof(j) = 'string' and (j #>> '{}') <> '', false)$$;

create or replace function private.vx_incomplete(doc jsonb, is_root boolean) returns text[]
  language plpgsql immutable set search_path = '' as $$
declare errs text[] := '{}'; g jsonb; ord integer;
begin
  if not private.vx_nonempty(doc #> '{local,geography,city}') and not private.vx_nonempty(doc #> '{local,geography,serviceArea}') then
    errs := errs || 'local.geography:required'::text;
  end if;
  if is_root then
    if not private.vx_nonempty(doc #> '{shared,identity,displayName}') then errs := errs || 'shared.identity.displayName:required'::text; end if;
    if not private.vx_nonempty(doc #> '{shared,identity,activity}')
       and not coalesce(jsonb_typeof(doc #> '{shared,services,items}') = 'array' and jsonb_array_length(doc #> '{shared,services,items}') > 0, false) then
      errs := errs || 'shared.services:required'::text;
    end if;
    if not private.vx_nonempty(doc #> '{shared,audience,description}') then errs := errs || 'shared.audience.description:required'::text; end if;
    if private.vx_has(doc #> '{shared,financialContext,revenueMinor}') then
      if not private.vx_has(doc #> '{shared,financialContext,revenueCurrency}') then errs := errs || 'shared.financialContext.revenueCurrency:required'::text; end if;
      if not private.vx_has(doc #> '{shared,financialContext,revenuePeriod}') then errs := errs || 'shared.financialContext.revenuePeriod:required'::text; end if;
    end if;
    if private.vx_has(doc #> '{shared,financialContext,budgetMinor}') then
      if not private.vx_has(doc #> '{shared,financialContext,budgetCurrency}') then errs := errs || 'shared.financialContext.budgetCurrency:required'::text; end if;
      if not private.vx_has(doc #> '{shared,financialContext,budgetPeriod}') then errs := errs || 'shared.financialContext.budgetPeriod:required'::text; end if;
    end if;
    if jsonb_typeof(doc #> '{shared,goals}') = 'array' then
      for g, ord in select e, o from jsonb_array_elements(doc #> '{shared,goals}') with ordinality t(e, o) loop
        if (private.vx_has(g->'baselineMinor') or private.vx_has(g->'growthBp') or private.vx_has(g->'targetMinor'))
           and not private.vx_has(g->'dueDate') then
          errs := errs || ('shared.goals[' || (ord - 1) || '].dueDate:required');
        end if;
        if private.vx_has(g->'growthBp') and not private.vx_has(g->'baselineMinor') then
          errs := errs || ('shared.goals[' || (ord - 1) || '].baselineMinor:required');
        end if;
      end loop;
    end if;
    if jsonb_typeof(doc #> '{shared,unknowns}') = 'array'
       and exists (select 1 from jsonb_array_elements(doc #> '{shared,unknowns}') u where u->'blocking' = 'true'::jsonb) then
      errs := errs || 'shared.unknowns:blocking'::text;
    end if;
  end if;
  return private.vx_sort(errs);
end $$;

-- ---------------------------------------------------------------------------------
-- 6) Oprávnění. Rozhoduje databáze podle přihlášené identity (JWT), ne podle parametrů od klienta.
--    Servisní klíč (role service_role) nemá uživatelskou identitu, proto tyto funkce nikdy
--    nepustí. Potvrzení profilu tedy nelze provést ani s privilegovaným klíčem.
-- ---------------------------------------------------------------------------------
create or replace function private.vx_jwt_role() returns text
  language sql stable set search_path = '' as
$$select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')$$;

create or replace function private.profile_actor(cid uuid, for_write boolean) returns uuid
  language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r text;
begin
  if uid is null or private.vx_jwt_role() <> 'authenticated' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  r := private.member_role(cid);
  if r is null or r not in ('owner', 'admin') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if for_write and not private.writable(cid) then
    raise exception 'read_only' using errcode = '42501';
  end if;
  return uid;
end $$;

create or replace function private.profile_conflict(current_rev integer) returns void
  language plpgsql immutable set search_path = '' as $$
begin
  raise exception 'revision_conflict' using errcode = 'PT409',
    detail = jsonb_build_object('current_revision', current_rev)::text;
end $$;

create or replace function private.profile_invalid(errs text[]) returns void
  language plpgsql immutable set search_path = '' as $$
begin
  raise exception 'validation_failed' using errcode = 'PT422', detail = to_jsonb(errs)::text;
end $$;

-- ---------------------------------------------------------------------------------
-- 7) Funkce pro klienta (jádro v private jako SECURITY DEFINER, obálka v public)
-- ---------------------------------------------------------------------------------
create or replace function private.profile_schema_info_core() returns jsonb
  language sql stable security definer set search_path = '' as
$$select jsonb_build_object('version', private.profile_schema_version(), 'schema', private.profile_schema())$$;

create or replace function private.profile_get_core(cid uuid) returns jsonb
  language plpgsql stable security definer set search_path = '' as $$
declare
  uid uuid; root uuid; is_root boolean; d record; a record; s record; res jsonb;
begin
  uid := private.profile_actor(cid, false);
  root := private.business_root(cid);
  is_root := (root = cid);
  select * into d from private.company_profile_drafts where company_id = cid;
  select v.* into a from private.company_active_profile ap
    join private.company_profile_versions v on v.id = ap.version_id and v.company_id = ap.company_id
    where ap.company_id = cid;
  res := jsonb_build_object(
    'company_id', cid, 'root_id', root, 'is_root', is_root,
    'schema_version', private.profile_schema_version(),
    'can_write', private.writable(cid),
    'draft', case when d.company_id is null then null else jsonb_build_object(
        'revision', d.revision, 'data', d.data, 'hash', private.vx_hash(d.data), 'updated_at', d.updated_at) end,
    'active', case when a.id is null then null else jsonb_build_object(
        'version', a.version, 'hash', a.content_hash, 'confirmed_at', a.confirmed_at, 'data', a.data) end,
    'versions', coalesce((
        select jsonb_agg(jsonb_build_object('version', x.version, 'hash', x.content_hash,
                 'confirmed_at', x.confirmed_at, 'by_me', x.confirmed_by = uid) order by x.version desc)
        from (select * from private.company_profile_versions where company_id = cid order by version desc limit 20) x), '[]'::jsonb));
  if not is_root then
    -- společné údaje hlavní firmy, jen pro čtení; finance a cíle jen pokud je uživatel správcem i hlavní firmy
    select v.* into s from private.company_active_profile ap
      join private.company_profile_versions v on v.id = ap.version_id and v.company_id = ap.company_id
      where ap.company_id = root;
    res := res || jsonb_build_object('shared_from_root', case when s.id is null then null else jsonb_build_object(
        'version', s.version,
        'data', case when private.member_role(root) in ('owner', 'admin')
                     then s.data->'shared'
                     else (s.data->'shared') - 'financialContext' - 'goals' end) end);
  end if;
  return res;
end $$;

create or replace function private.profile_version_get_core(cid uuid, ver integer) returns jsonb
  language plpgsql stable security definer set search_path = '' as $$
declare v record;
begin
  perform private.profile_actor(cid, false);
  select * into v from private.company_profile_versions where company_id = cid and version = ver;
  if not found then raise exception 'not_found' using errcode = 'PT404'; end if;
  return jsonb_build_object('version', v.version, 'hash', v.content_hash, 'confirmed_at', v.confirmed_at, 'data', v.data);
end $$;

create or replace function private.profile_save_draft_core(cid uuid, expected_revision integer, schema_version integer, doc jsonb) returns jsonb
  language plpgsql security definer set search_path = '' as $$
declare uid uuid; is_root boolean; cur record; nd jsonb; errs text[]; newrev integer; ts timestamptz := now();
begin
  uid := private.profile_actor(cid, true);
  if schema_version is distinct from private.profile_schema_version() then
    raise exception 'schema_mismatch' using errcode = 'PT412',
      detail = jsonb_build_object('server_version', private.profile_schema_version())::text;
  end if;
  if expected_revision is null or expected_revision < 0 then perform private.profile_invalid(array['$:expected_revision']); end if;
  is_root := (private.business_root(cid) = cid);
  nd := private.vx_trim(doc);
  errs := private.vx_profile_validate(nd, is_root);
  if array_length(errs, 1) is not null then perform private.profile_invalid(errs); end if;
  nd := private.vx_apply_derived(nd);
  if pg_column_size(nd) > 65536 then perform private.profile_invalid(array['$:size']); end if;

  perform pg_advisory_xact_lock(hashtextextended(cid::text, 7311));
  select * into cur from private.company_profile_drafts where company_id = cid for update;
  if not found then
    if expected_revision <> 0 then perform private.profile_conflict(0); end if;
    insert into private.company_profile_drafts (company_id, revision, schema_version, data, updated_by, updated_at)
      values (cid, 1, schema_version, nd, uid, ts);
    insert into private.company_profile_events (company_id, actor, operation, revision) values (cid, uid, 'draft_created', 1);
    newrev := 1;
  else
    if cur.revision <> expected_revision then perform private.profile_conflict(cur.revision); end if;
    if cur.data = nd then
      newrev := cur.revision; ts := cur.updated_at;               -- beze změny: revizi nezvyšujeme
    else
      newrev := cur.revision + 1;
      update private.company_profile_drafts
         set revision = newrev, schema_version = profile_save_draft_core.schema_version, data = nd, updated_by = uid, updated_at = ts
       where company_id = cid;
    end if;
  end if;
  return jsonb_build_object('revision', newrev, 'data', nd, 'hash', private.vx_hash(nd), 'updated_at', ts);
end $$;

create or replace function private.profile_confirm_core(cid uuid, expected_revision integer, expected_hash text) returns jsonb
  language plpgsql security definer set search_path = '' as $$
declare uid uuid; is_root boolean; d record; a record; errs text[]; h text; nextv integer; vid uuid; ts timestamptz := now();
begin
  uid := private.profile_actor(cid, true);      -- lidská identita + role owner/admin + zapisovatelná firma
  perform pg_advisory_xact_lock(hashtextextended(cid::text, 7311));
  select * into d from private.company_profile_drafts where company_id = cid for update;
  if not found then perform private.profile_invalid(array['$:no_draft']); end if;
  h := private.vx_hash(d.data);
  if d.revision is distinct from expected_revision or h is distinct from expected_hash then
    perform private.profile_conflict(d.revision);
  end if;
  is_root := (private.business_root(cid) = cid);
  errs := private.vx_profile_validate(d.data, is_root) || private.vx_incomplete(d.data, is_root);
  if array_length(errs, 1) is not null then perform private.profile_invalid(private.vx_sort(errs)); end if;

  select v.* into a from private.company_active_profile ap
    join private.company_profile_versions v on v.id = ap.version_id and v.company_id = ap.company_id
    where ap.company_id = cid;
  if found and a.content_hash = h then
    return jsonb_build_object('version', a.version, 'hash', h, 'confirmed_at', a.confirmed_at, 'unchanged', true);
  end if;
  select coalesce(max(version), 0) + 1 into nextv from private.company_profile_versions where company_id = cid;
  insert into private.company_profile_versions (company_id, version, schema_version, data, content_hash, source_revision, confirmed_by, confirmed_at)
    values (cid, nextv, d.schema_version, d.data, h, d.revision, uid, ts) returning id into vid;
  insert into private.company_active_profile (company_id, version_id) values (cid, vid)
    on conflict (company_id) do update set version_id = excluded.version_id;
  insert into private.company_profile_events (company_id, actor, operation, version, revision) values (cid, uid, 'confirm', nextv, d.revision);
  return jsonb_build_object('version', nextv, 'hash', h, 'confirmed_at', ts, 'unchanged', false);
end $$;

-- Veřejné obálky (SECURITY INVOKER; oprávnění řeší jádro).
create or replace function public.profile_schema_info() returns jsonb
  language sql set search_path = '' as $$select private.profile_schema_info_core()$$;
create or replace function public.profile_get(cid uuid) returns jsonb
  language sql set search_path = '' as $$select private.profile_get_core(cid)$$;
create or replace function public.profile_version_get(cid uuid, ver integer) returns jsonb
  language sql set search_path = '' as $$select private.profile_version_get_core(cid, ver)$$;
create or replace function public.profile_save_draft(cid uuid, expected_revision integer, schema_version integer, doc jsonb) returns jsonb
  language sql set search_path = '' as $$select private.profile_save_draft_core(cid, expected_revision, schema_version, doc)$$;
create or replace function public.profile_confirm(cid uuid, expected_revision integer, expected_hash text) returns jsonb
  language sql set search_path = '' as $$select private.profile_confirm_core(cid, expected_revision, expected_hash)$$;

-- ---------------------------------------------------------------------------------
-- 8) Práva na funkce. V public se nové funkce vytvářejí s EXECUTE pro anon, authenticated
--    i service_role (výchozí práva Supabase), proto je odebíráme výslovně.
--    Pomocné funkce (vx_*, profile_actor, …) nesmí volat nikdo mimo definery.
-- ---------------------------------------------------------------------------------
revoke all on function
  private.profile_schema(), private.profile_schema_version(), private.vx_block_update(),
  private.vx_sort(text[]), private.vx_json_validate(jsonb, jsonb, text), private.vx_profile_validate(jsonb, boolean),
  private.vx_trim(jsonb), private.vx_goal_target(bigint, integer), private.vx_apply_derived(jsonb), private.vx_hash(jsonb),
  private.vx_has(jsonb), private.vx_nonempty(jsonb), private.vx_incomplete(jsonb, boolean), private.vx_jwt_role(),
  private.profile_actor(uuid, boolean), private.profile_conflict(integer), private.profile_invalid(text[]),
  private.profile_schema_info_core(), private.profile_get_core(uuid), private.profile_version_get_core(uuid, integer),
  private.profile_save_draft_core(uuid, integer, integer, jsonb), private.profile_confirm_core(uuid, integer, text)
  from public, anon, authenticated, service_role;

-- jen jádra, která volají obálky jménem přihlášeného uživatele
grant execute on function
  private.profile_schema_info_core(), private.profile_get_core(uuid), private.profile_version_get_core(uuid, integer),
  private.profile_save_draft_core(uuid, integer, integer, jsonb), private.profile_confirm_core(uuid, integer, text)
  to authenticated;

revoke all on function
  public.profile_schema_info(), public.profile_get(uuid), public.profile_version_get(uuid, integer),
  public.profile_save_draft(uuid, integer, integer, jsonb), public.profile_confirm(uuid, integer, text)
  from public, anon, service_role;
grant execute on function
  public.profile_schema_info(), public.profile_get(uuid), public.profile_version_get(uuid, integer),
  public.profile_save_draft(uuid, integer, integer, jsonb), public.profile_confirm(uuid, integer, text)
  to authenticated;

notify pgrst, 'reload schema';
commit;
