-- GPS-FMRA — RPC save_named_place (evita fallos RLS insert+returning)
-- APPLY: SQL Editor → Run. Éxito: save_named_place_ok = true

create or replace function public.save_named_place(
  p_name text,
  p_lat double precision,
  p_lon double precision,
  p_group_id uuid default null
)
returns public.named_places
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := trim(p_name);
  v_row public.named_places;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if v_name is null or char_length(v_name) = 0 or char_length(v_name) > 80 then
    raise exception 'invalid_name';
  end if;

  if p_lat is null or p_lon is null
     or p_lat < -90 or p_lat > 90
     or p_lon < -180 or p_lon > 180 then
    raise exception 'invalid_coordinates';
  end if;

  if p_group_id is not null and not public.is_active_member(p_group_id, v_uid) then
    raise exception 'not_group_member';
  end if;

  -- Asegura perfil (FK profiles).
  insert into public.profiles (id, display_name)
  values (v_uid, 'Usuario')
  on conflict (id) do nothing;

  insert into public.named_places (owner_id, group_id, name, lat, lon)
  values (v_uid, p_group_id, v_name, p_lat, p_lon)
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.save_named_place(text, double precision, double precision, uuid) from public;
grant execute on function public.save_named_place(text, double precision, double precision, uuid) to authenticated;

notify pgrst, 'reload schema';

select
  to_regclass('public.named_places') is not null
  and exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'save_named_place'
  ) as save_named_place_ok;
