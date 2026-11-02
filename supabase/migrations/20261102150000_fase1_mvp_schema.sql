-- GPS-FMRA Fase 1 — esquema MVP + RLS (default-deny)
-- Tablas: profiles, family_groups, group_memberships, invitations,
--         location_consents, location_updates, user_settings
-- Principio: admins NO eluden consentimiento de ubicación.

-- ---------------------------------------------------------------------------
-- Extensiones
-- ---------------------------------------------------------------------------
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.membership_role as enum ('member', 'group_admin', 'org_admin');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.membership_status as enum ('active', 'invited', 'left', 'removed');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.invitation_status as enum ('pending', 'accepted', 'revoked', 'expired');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.consent_scope as enum ('group', 'user');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.consent_status as enum ('active', 'paused', 'revoked');
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  photo_url text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'Perfil de app 1:1 con auth.users';

-- ---------------------------------------------------------------------------
-- family_groups
-- ---------------------------------------------------------------------------
create table if not exists public.family_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references public.profiles (id) on delete restrict,
  status text not null default 'active' check (status in ('active', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists family_groups_created_by_idx
  on public.family_groups (created_by);

-- ---------------------------------------------------------------------------
-- group_memberships
-- ---------------------------------------------------------------------------
create table if not exists public.group_memberships (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.family_groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role public.membership_role not null default 'member',
  status public.membership_status not null default 'active',
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (group_id, user_id)
);

create index if not exists group_memberships_user_idx
  on public.group_memberships (user_id)
  where status = 'active';

create index if not exists group_memberships_group_idx
  on public.group_memberships (group_id)
  where status = 'active';

-- ---------------------------------------------------------------------------
-- invitations (solo token_hash; nunca el token en claro)
-- ---------------------------------------------------------------------------
create table if not exists public.invitations (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.family_groups (id) on delete cascade,
  invited_by uuid not null references public.profiles (id) on delete cascade,
  token_hash text not null unique,
  email text,
  max_uses int not null default 1 check (max_uses > 0),
  uses_count int not null default 0 check (uses_count >= 0),
  expires_at timestamptz not null,
  status public.invitation_status not null default 'pending',
  created_at timestamptz not null default now(),
  accepted_by uuid references public.profiles (id) on delete set null,
  accepted_at timestamptz
);

create index if not exists invitations_group_idx
  on public.invitations (group_id);

create index if not exists invitations_status_expires_idx
  on public.invitations (status, expires_at);

-- ---------------------------------------------------------------------------
-- location_consents
-- ---------------------------------------------------------------------------
create table if not exists public.location_consents (
  id uuid primary key default gen_random_uuid(),
  sharer_id uuid not null references public.profiles (id) on delete cascade,
  scope public.consent_scope not null,
  group_id uuid references public.family_groups (id) on delete cascade,
  viewer_id uuid references public.profiles (id) on delete cascade,
  status public.consent_status not null default 'active',
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint location_consents_target_chk check (
    (scope = 'group' and group_id is not null and viewer_id is null)
    or (scope = 'user' and viewer_id is not null)
  )
);

create unique index if not exists location_consents_group_uniq
  on public.location_consents (sharer_id, group_id)
  where scope = 'group' and group_id is not null;

create unique index if not exists location_consents_user_uniq
  on public.location_consents (sharer_id, viewer_id, coalesce(group_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where scope = 'user' and viewer_id is not null;

create index if not exists location_consents_sharer_idx
  on public.location_consents (sharer_id)
  where status = 'active';

create index if not exists location_consents_group_idx
  on public.location_consents (group_id)
  where status = 'active' and scope = 'group';

-- ---------------------------------------------------------------------------
-- location_updates — ubicación ACTUAL / última conocida (no historial)
-- ---------------------------------------------------------------------------
create table if not exists public.location_updates (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  lat double precision not null check (lat between -90 and 90),
  lon double precision not null check (lon between -180 and 180),
  accuracy_m double precision,
  recorded_at timestamptz not null,
  server_received_at timestamptz not null default now(),
  battery_pct smallint check (battery_pct is null or (battery_pct between 0 and 100)),
  is_mocked boolean not null default false
);

create index if not exists location_updates_recorded_at_idx
  on public.location_updates (recorded_at desc);

-- ---------------------------------------------------------------------------
-- user_settings
-- ---------------------------------------------------------------------------
create table if not exists public.user_settings (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  share_location_globally_paused boolean not null default false,
  locale text not null default 'es',
  theme text not null default 'system' check (theme in ('system', 'light', 'dark')),
  map_provider text not null default 'google',
  notify_invites boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Helpers RLS (security definer; sin bypass de consentimiento)
-- ---------------------------------------------------------------------------
create or replace function public.is_active_member(p_group_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.group_memberships gm
    where gm.group_id = p_group_id
      and gm.user_id = p_user_id
      and gm.status = 'active'
  );
$$;

create or replace function public.is_group_admin(p_group_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.group_memberships gm
    where gm.group_id = p_group_id
      and gm.user_id = p_user_id
      and gm.status = 'active'
      and gm.role in ('group_admin', 'org_admin')
  );
$$;

create or replace function public.can_view_location(p_sharer_id uuid, p_viewer_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    p_sharer_id = p_viewer_id
    or exists (
      select 1
      from public.location_consents lc
      where lc.sharer_id = p_sharer_id
        and lc.status = 'active'
        and (lc.valid_until is null or lc.valid_until > now())
        and lc.valid_from <= now()
        and (
          (
            lc.scope = 'user'
            and lc.viewer_id = p_viewer_id
            and (
              lc.group_id is null
              or public.is_active_member(lc.group_id, p_viewer_id)
            )
          )
          or (
            lc.scope = 'group'
            and lc.group_id is not null
            and public.is_active_member(lc.group_id, p_viewer_id)
            and public.is_active_member(lc.group_id, p_sharer_id)
          )
        )
    )
    and not exists (
      select 1
      from public.user_settings us
      where us.user_id = p_sharer_id
        and us.share_location_globally_paused = true
        and p_sharer_id <> p_viewer_id
    );
$$;

revoke all on function public.is_active_member(uuid, uuid) from public;
revoke all on function public.is_group_admin(uuid, uuid) from public;
revoke all on function public.can_view_location(uuid, uuid) from public;
grant execute on function public.is_active_member(uuid, uuid) to authenticated;
grant execute on function public.is_group_admin(uuid, uuid) to authenticated;
grant execute on function public.can_view_location(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Trigger: perfil + settings al registrar en auth.users
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;

  insert into public.user_settings (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Al crear un grupo, el creador queda como group_admin activo
create or replace function public.handle_new_family_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.group_memberships (group_id, user_id, role, status)
  values (new.id, new.created_by, 'group_admin', 'active')
  on conflict (group_id, user_id) do update
    set role = excluded.role,
        status = 'active',
        updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_family_group_created on public.family_groups;
create trigger on_family_group_created
  after insert on public.family_groups
  for each row execute function public.handle_new_family_group();

-- ---------------------------------------------------------------------------
-- updated_at helper
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

drop trigger if exists family_groups_set_updated_at on public.family_groups;
create trigger family_groups_set_updated_at
  before update on public.family_groups
  for each row execute function public.set_updated_at();

drop trigger if exists group_memberships_set_updated_at on public.group_memberships;
create trigger group_memberships_set_updated_at
  before update on public.group_memberships
  for each row execute function public.set_updated_at();

drop trigger if exists location_consents_set_updated_at on public.location_consents;
create trigger location_consents_set_updated_at
  before update on public.location_consents
  for each row execute function public.set_updated_at();

drop trigger if exists user_settings_set_updated_at on public.user_settings;
create trigger user_settings_set_updated_at
  before update on public.user_settings
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS: enable + default deny (sin políticas = denegado)
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.family_groups enable row level security;
alter table public.group_memberships enable row level security;
alter table public.invitations enable row level security;
alter table public.location_consents enable row level security;
alter table public.location_updates enable row level security;
alter table public.user_settings enable row level security;

alter table public.profiles force row level security;
alter table public.family_groups force row level security;
alter table public.group_memberships force row level security;
alter table public.invitations force row level security;
alter table public.location_consents force row level security;
alter table public.location_updates force row level security;
alter table public.user_settings force row level security;

-- profiles
drop policy if exists profiles_select_authenticated on public.profiles;
create policy profiles_select_authenticated
  on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.group_memberships me
      join public.group_memberships other
        on other.group_id = me.group_id
       and other.user_id = profiles.id
       and other.status = 'active'
      where me.user_id = auth.uid()
        and me.status = 'active'
    )
  );

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
  on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own
  on public.profiles for insert to authenticated
  with check (id = auth.uid());

-- family_groups
drop policy if exists family_groups_select_member on public.family_groups;
create policy family_groups_select_member
  on public.family_groups for select to authenticated
  using (created_by = auth.uid() or public.is_active_member(id));

drop policy if exists family_groups_insert_auth on public.family_groups;
create policy family_groups_insert_auth
  on public.family_groups for insert to authenticated
  with check (created_by = auth.uid());

drop policy if exists family_groups_update_admin on public.family_groups;
create policy family_groups_update_admin
  on public.family_groups for update to authenticated
  using (public.is_group_admin(id))
  with check (public.is_group_admin(id));

-- group_memberships
drop policy if exists group_memberships_select_peer on public.group_memberships;
create policy group_memberships_select_peer
  on public.group_memberships for select to authenticated
  using (public.is_active_member(group_id) or user_id = auth.uid());

drop policy if exists group_memberships_insert_admin_or_self on public.group_memberships;
create policy group_memberships_insert_admin_or_self
  on public.group_memberships for insert to authenticated
  with check (
    user_id = auth.uid()
    or public.is_group_admin(group_id)
  );

drop policy if exists group_memberships_update_admin_or_self on public.group_memberships;
create policy group_memberships_update_admin_or_self
  on public.group_memberships for update to authenticated
  using (user_id = auth.uid() or public.is_group_admin(group_id))
  with check (user_id = auth.uid() or public.is_group_admin(group_id));

-- invitations: solo admins del grupo ven/gestionan; aceptación vía Edge Function (service role)
drop policy if exists invitations_select_admin on public.invitations;
create policy invitations_select_admin
  on public.invitations for select to authenticated
  using (public.is_group_admin(group_id) or invited_by = auth.uid());

drop policy if exists invitations_insert_admin on public.invitations;
create policy invitations_insert_admin
  on public.invitations for insert to authenticated
  with check (public.is_group_admin(group_id) and invited_by = auth.uid());

drop policy if exists invitations_update_admin on public.invitations;
create policy invitations_update_admin
  on public.invitations for update to authenticated
  using (public.is_group_admin(group_id))
  with check (public.is_group_admin(group_id));

-- location_consents: el emisor controla; viewers solo leen filas que les afectan
drop policy if exists location_consents_select on public.location_consents;
create policy location_consents_select
  on public.location_consents for select to authenticated
  using (
    sharer_id = auth.uid()
    or (
      scope = 'user' and viewer_id = auth.uid()
    )
    or (
      scope = 'group'
      and group_id is not null
      and public.is_active_member(group_id)
    )
  );

drop policy if exists location_consents_insert_own on public.location_consents;
create policy location_consents_insert_own
  on public.location_consents for insert to authenticated
  with check (sharer_id = auth.uid());

drop policy if exists location_consents_update_own on public.location_consents;
create policy location_consents_update_own
  on public.location_consents for update to authenticated
  using (sharer_id = auth.uid())
  with check (sharer_id = auth.uid());

drop policy if exists location_consents_delete_own on public.location_consents;
create policy location_consents_delete_own
  on public.location_consents for delete to authenticated
  using (sharer_id = auth.uid());

-- location_updates: sin consentimiento vigente → nadie (ni admin) ve la ubicación ajena
drop policy if exists location_updates_select_consented on public.location_updates;
create policy location_updates_select_consented
  on public.location_updates for select to authenticated
  using (public.can_view_location(user_id));

drop policy if exists location_updates_upsert_own on public.location_updates;
create policy location_updates_upsert_own
  on public.location_updates for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists location_updates_update_own on public.location_updates;
create policy location_updates_update_own
  on public.location_updates for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists location_updates_delete_own on public.location_updates;
create policy location_updates_delete_own
  on public.location_updates for delete to authenticated
  using (user_id = auth.uid());

-- user_settings
drop policy if exists user_settings_select_own on public.user_settings;
create policy user_settings_select_own
  on public.user_settings for select to authenticated
  using (user_id = auth.uid());

drop policy if exists user_settings_insert_own on public.user_settings;
create policy user_settings_insert_own
  on public.user_settings for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists user_settings_update_own on public.user_settings;
create policy user_settings_update_own
  on public.user_settings for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Realtime (ubicación actual) — publicación; RLS sigue aplicando
do $$
begin
  begin
    alter publication supabase_realtime add table public.location_updates;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end $$;
