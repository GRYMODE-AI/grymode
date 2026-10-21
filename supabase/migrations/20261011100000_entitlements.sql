-- Server-authoritative access plan. No row means free. Premium rows land with StoreKit (Phase 6).

create table public.entitlements (
    user_id uuid primary key references auth.users (id) on delete cascade,
    plan text not null default 'free' check (plan in ('free', 'premium')),
    source text not null default 'default' check (char_length(source) between 1 and 40),
    expires_at timestamptz,
    updated_at timestamptz not null default now()
);

comment on table public.entitlements is
    'Authoritative Grymode access plan. Free users omit a row or use plan=free; premium is set after verified purchase.';

create trigger entitlements_set_updated_at
before update on public.entitlements
for each row execute function public.set_updated_at();

alter table public.entitlements enable row level security;

revoke all on public.entitlements from anon, authenticated;
grant select on public.entitlements to authenticated;
grant select, insert, update, delete on public.entitlements to grymode_api;

create policy entitlements_own_select on public.entitlements
for select to authenticated
using ((select auth.uid()) = user_id);

create policy entitlements_api_all on public.entitlements
for all to grymode_api
using (true)
with check (true);
