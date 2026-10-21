-- StoreKit subscription ledger. Entitlements are derived from the latest active row.

create table public.subscriptions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    original_transaction_id text not null,
    transaction_id text not null,
    product_id text not null,
    environment text not null check (environment in ('Xcode', 'Sandbox', 'Production')),
    status text not null check (status in (
        'active', 'expired', 'revoked', 'billing_retry', 'grace_period'
    )),
    purchased_at timestamptz,
    expires_at timestamptz,
    revoked_at timestamptz,
    jws_sha256 text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (original_transaction_id)
);

comment on table public.subscriptions is
    'Verified App Store subscription transactions. Authoritative for premium access with entitlements.';

create index subscriptions_user_status_idx on public.subscriptions (user_id, status, expires_at desc);

create trigger subscriptions_set_updated_at
before update on public.subscriptions
for each row execute function public.set_updated_at();

alter table public.subscriptions enable row level security;

revoke all on public.subscriptions from anon, authenticated;
-- Clients never read the ledger directly; they use /v1/me/entitlement.
grant select, insert, update, delete on public.subscriptions to grymode_api;

create policy subscriptions_api_all on public.subscriptions
for all to grymode_api
using (true)
with check (true);
