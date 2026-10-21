-- Operational record of privacy requests such as account deletion.
--
-- `user_id` deliberately has no foreign key: the row must outlive the deleted account so support can
-- confirm a deletion happened. It holds only the random account UUID, no personal data.

create table public.privacy_requests (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,
    request_type text not null check (request_type in ('account_deletion')),
    status text not null default 'pending' check (status in ('pending', 'processing', 'completed', 'failed')),
    created_at timestamptz not null default now(),
    completed_at timestamptz,
    check ((status = 'completed') = (completed_at is not null))
);

comment on table public.privacy_requests is 'Minimal audit trail for privacy requests. Backend access only.';

create index privacy_requests_user_id_idx on public.privacy_requests (user_id);

-- At most one open request of each type per user, so retries never start duplicate deletions.
create unique index privacy_requests_one_open_per_type
on public.privacy_requests (user_id, request_type)
where status in ('pending', 'processing');

-- RLS on with no policies: client roles can never read or write this table.
alter table public.privacy_requests enable row level security;
revoke all on public.privacy_requests from anon, authenticated;
