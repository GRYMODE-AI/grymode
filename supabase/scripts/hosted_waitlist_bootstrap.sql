-- Hosted bootstrap for landing waitlist + backups.
-- Safe to re-run. Run in Supabase Dashboard → SQL Editor if CLI is not linked.
-- Does not require the grymode_api role (grants it only if the role exists).

create extension if not exists "pgcrypto";

create table if not exists public.waitlist_signups (
    id uuid primary key default gen_random_uuid(),
    email text not null,
    source text not null default 'landing'
        check (char_length(source) between 1 and 40),
    user_agent text check (user_agent is null or char_length(user_agent) <= 512),
    created_at timestamptz not null default now(),
    email_sent_at timestamptz,
    backed_up_at timestamptz,
    email_error text,
    constraint waitlist_signups_email_format check (
        email ~* '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'
        and char_length(email) <= 254
    )
);

alter table public.waitlist_signups
  add column if not exists email_sent_at timestamptz,
  add column if not exists backed_up_at timestamptz,
  add column if not exists email_error text;

create unique index if not exists waitlist_signups_email_lower_idx
  on public.waitlist_signups (lower(email));

alter table public.waitlist_signups enable row level security;

revoke all on public.waitlist_signups from anon, authenticated;
grant insert on public.waitlist_signups to anon, authenticated;
-- Edge Functions use the service_role JWT (bypasses RLS but still needs GRANTs).
grant select, insert, update, delete on public.waitlist_signups to service_role;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'grymode_api') then
    grant select, insert, update, delete on public.waitlist_signups to grymode_api;
  end if;
end $$;

drop policy if exists waitlist_signups_anon_insert on public.waitlist_signups;
create policy waitlist_signups_anon_insert on public.waitlist_signups
  for insert to anon, authenticated
  with check (true);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'waitlist-backups',
  'waitlist-backups',
  false,
  1048576,
  array['application/json']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
