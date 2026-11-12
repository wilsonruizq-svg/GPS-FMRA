-- GPS-FMRA — género en perfil (figuritas mujer/hombre en el mapa)
-- APPLY: pegar en SQL Editor → Run (ver APPLY_ES.md).
-- Éxito: profiles_gender_ok = true

alter table public.profiles
  add column if not exists gender text;

alter table public.profiles
  drop constraint if exists profiles_gender_check;

alter table public.profiles
  add constraint profiles_gender_check
  check (
    gender is null
    or gender in ('female', 'male')
  );

comment on column public.profiles.gender is
  'female | male | null. Usado para figurita en el mapa; null → heurística por nombre.';

notify pgrst, 'reload schema';

select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'gender'
  ) as profiles_gender_ok;
