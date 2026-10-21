-- Waitlist delivery tracking + durable object-store backup bucket.
-- Primary source of truth remains public.waitlist_signups; Storage holds
-- per-signup JSON mirrors so a table wipe/corruption is recoverable.

alter table public.waitlist_signups
  add column if not exists email_sent_at timestamptz,
  add column if not exists backed_up_at timestamptz,
  add column if not exists email_error text;

comment on column public.waitlist_signups.email_sent_at is
  'When the Resend welcome email was accepted by the provider.';
comment on column public.waitlist_signups.backed_up_at is
  'When a JSON mirror was written to the waitlist-backups Storage bucket.';
comment on column public.waitlist_signups.email_error is
  'Last Resend error message, if sending failed after insert.';

-- Private bucket: service role / Edge Function only (no public policies).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'waitlist-backups',
  'waitlist-backups',
  false,
  1048576, -- 1 MiB per object (single signup JSON is tiny)
  array['application/json']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Explicitly lock the bucket down for anon/authenticated.
drop policy if exists waitlist_backups_no_anon on storage.objects;
-- No SELECT/INSERT policies for anon/authenticated → only service_role can access.
