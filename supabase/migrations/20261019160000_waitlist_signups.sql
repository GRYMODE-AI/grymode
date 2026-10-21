-- Public pre-launch waitlist for grymode.ai. Inserts are allowed for anon;
-- only the service role can read rows (no authenticated select policy).

create table public.waitlist_signups (
    id uuid primary key default gen_random_uuid(),
    email text not null,
    source text not null default 'landing'
        check (char_length(source) between 1 and 40),
    user_agent text check (user_agent is null or char_length(user_agent) <= 512),
    created_at timestamptz not null default now(),
    constraint waitlist_signups_email_format check (
        email ~* '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'
        and char_length(email) <= 254
    )
);

comment on table public.waitlist_signups is
  'Pre-launch email waitlist collected from the marketing site.';

create unique index waitlist_signups_email_lower_idx
  on public.waitlist_signups (lower(email));

alter table public.waitlist_signups enable row level security;

revoke all on public.waitlist_signups from anon, authenticated;
grant insert on public.waitlist_signups to anon, authenticated;
grant select, insert, update, delete on public.waitlist_signups to service_role;
grant select, insert, update, delete on public.waitlist_signups to grymode_api;

-- Anyone can join; nobody (except service/API role) can read the list via PostgREST.
create policy waitlist_signups_anon_insert on public.waitlist_signups
  for insert to anon, authenticated
  with check (true);
