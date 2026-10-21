-- User-saved outfits from the generated library (premium core).

create table public.saved_looks (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    outfit_id uuid not null references public.outfits (id) on delete cascade,
    created_at timestamptz not null default now(),
    unique (user_id, outfit_id)
);

comment on table public.saved_looks is
    'Looks the owner has saved from their generated outfit library.';

create index saved_looks_user_created_idx on public.saved_looks (user_id, created_at desc);

alter table public.saved_looks enable row level security;

revoke all on public.saved_looks from anon, authenticated;
grant select, insert, delete on public.saved_looks to authenticated;
grant select, insert, delete on public.saved_looks to grymode_api;

create policy saved_looks_own on public.saved_looks
for all to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy saved_looks_api_all on public.saved_looks
for all to grymode_api
using (true)
with check (true);
