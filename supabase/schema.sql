-- Run this once in the Supabase SQL Editor for the KYBP project.

create table if not exists public.kybp_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null default '',
  display_name text not null default '',
  role text not null default 'None' check (role in ('Admin', 'Editor', 'Viewer', 'None')),
  forms text not null default 'Both' check (forms in ('Both', 'Customer', 'Vendor')),
  created_at timestamptz not null default now()
);

create table if not exists public.kybp_records (
  id text primary key,
  data jsonb not null check (
    jsonb_typeof(data) = 'object'
    and coalesce(data ->> 'type' in ('Customer', 'Vendor'), false)
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists kybp_records_type_form_id_unique
  on public.kybp_records (
    (data ->> 'type'),
    (lower(btrim(coalesce(data ->> (case when data ->> 'type' = 'Vendor' then 'vid' else 'cid' end), ''))))
  )
  where coalesce(data ->> (case when data ->> 'type' = 'Vendor' then 'vid' else 'cid' end), '') <> '';

create table if not exists public.kybp_locations (
  id text primary key,
  data jsonb not null check (jsonb_typeof(data) = 'object')
);

create table if not exists public.kybp_submissions (
  id text primary key,
  form_type text not null check (form_type in ('Customer', 'Vendor')),
  data jsonb not null check (jsonb_typeof(data) = 'object'),
  created_at timestamptz not null default now()
);

create table if not exists public.kybp_activity_log (
  id text primary key,
  user_id uuid not null references auth.users(id),
  data jsonb not null check (jsonb_typeof(data) = 'object'),
  created_at timestamptz not null default now()
);

create or replace function public.create_kybp_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.kybp_profiles (user_id, email, display_name)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'name', new.email, '')
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists kybp_auth_user_created on auth.users;
create trigger kybp_auth_user_created
  after insert on auth.users
  for each row execute function public.create_kybp_profile();

insert into public.kybp_profiles (user_id, email, display_name)
select id, coalesce(email, ''), coalesce(raw_user_meta_data ->> 'name', email, '')
from auth.users
on conflict (user_id) do nothing;

create or replace function public.kybp_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.kybp_profiles p
  where p.user_id = (select auth.uid())
$$;

create or replace function public.kybp_can_access_form(form_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.kybp_profiles p
    where p.user_id = (select auth.uid())
      and (
        p.role in ('Admin', 'Editor', 'Viewer')
        and (
          p.role = 'Admin'
          or p.forms = 'Both'
          or p.forms = form_name
        )
      )
  )
$$;

create or replace function public.kybp_can_edit_form(form_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.kybp_profiles p
    where p.user_id = (select auth.uid())
      and p.role in ('Admin', 'Editor')
      and (
        p.role = 'Admin'
        or p.forms = 'Both'
        or p.forms = form_name
      )
  )
$$;

create or replace function public.kybp_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.kybp_role() = 'Admin', false)
$$;

alter table public.kybp_profiles enable row level security;
alter table public.kybp_records enable row level security;
alter table public.kybp_locations enable row level security;
alter table public.kybp_submissions enable row level security;
alter table public.kybp_activity_log enable row level security;

drop policy if exists "Profiles are visible to their user or admins" on public.kybp_profiles;
create policy "Profiles are visible to their user or admins"
  on public.kybp_profiles for select to authenticated
  using (user_id = (select auth.uid()) or (select public.kybp_is_admin()));

drop policy if exists "Admins manage profiles" on public.kybp_profiles;
create policy "Admins manage profiles"
  on public.kybp_profiles for all to authenticated
  using ((select public.kybp_is_admin()))
  with check ((select public.kybp_is_admin()));

drop policy if exists "Users read permitted records" on public.kybp_records;
create policy "Users read permitted records"
  on public.kybp_records for select to authenticated
  using ((select public.kybp_can_access_form(data ->> 'type')));

drop policy if exists "Editors insert permitted records" on public.kybp_records;
create policy "Editors insert permitted records"
  on public.kybp_records for insert to authenticated
  with check ((select public.kybp_can_edit_form(data ->> 'type')));

drop policy if exists "Editors update permitted records" on public.kybp_records;
create policy "Editors update permitted records"
  on public.kybp_records for update to authenticated
  using ((select public.kybp_can_edit_form(data ->> 'type')))
  with check ((select public.kybp_can_edit_form(data ->> 'type')));

drop policy if exists "Admins delete records" on public.kybp_records;
create policy "Admins delete records"
  on public.kybp_records for delete to authenticated
  using ((select public.kybp_is_admin()) and (select public.kybp_can_access_form(data ->> 'type')));

drop policy if exists "Anyone reads locations" on public.kybp_locations;
create policy "Anyone reads locations"
  on public.kybp_locations for select to anon, authenticated
  using (true);

drop policy if exists "Admins manage locations" on public.kybp_locations;
create policy "Admins manage locations"
  on public.kybp_locations for all to authenticated
  using ((select public.kybp_is_admin()))
  with check ((select public.kybp_is_admin()));

drop policy if exists "Public may submit forms" on public.kybp_submissions;
create policy "Public may submit forms"
  on public.kybp_submissions for insert to anon, authenticated
  with check (
    form_type in ('Customer', 'Vendor')
    and coalesce(data ->> 'type' = form_type, false)
    and jsonb_typeof(data) = 'object'
  );

drop policy if exists "Admins read submissions" on public.kybp_submissions;
create policy "Admins read submissions"
  on public.kybp_submissions for select to authenticated
  using ((select public.kybp_is_admin()));

drop policy if exists "Admins delete submissions" on public.kybp_submissions;
create policy "Admins delete submissions"
  on public.kybp_submissions for delete to authenticated
  using ((select public.kybp_is_admin()));

drop policy if exists "Admins read activity log" on public.kybp_activity_log;
create policy "Admins read activity log"
  on public.kybp_activity_log for select to authenticated
  using ((select public.kybp_is_admin()));

drop policy if exists "Authenticated users add own activity" on public.kybp_activity_log;
create policy "Authenticated users add own activity"
  on public.kybp_activity_log for insert to authenticated
  with check (user_id = (select auth.uid()));

grant select, insert, update, delete on public.kybp_profiles to authenticated;
grant select, insert, update, delete on public.kybp_records to authenticated;
grant select, insert, update, delete on public.kybp_locations to authenticated;
grant select, insert, delete on public.kybp_submissions to anon, authenticated;
grant select, insert on public.kybp_activity_log to authenticated;

do $$
declare
  tbl text;
begin
  foreach tbl in array array['kybp_profiles', 'kybp_records', 'kybp_locations', 'kybp_submissions', 'kybp_activity_log']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = tbl
    ) then
      execute format('alter publication supabase_realtime add table public.%I', tbl);
    end if;
  end loop;
end;
$$;
