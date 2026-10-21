-- Durable counters for billable AI image work (look visuals + try-on angles).
-- Cache hits never insert a row. grymode_api is the only writer.

create table if not exists public.usage_events (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    kind text not null check (kind in ('look_render', 'try_on')),
    outfit_id uuid references public.outfits (id) on delete set null,
    units integer not null default 1 check (units > 0 and units <= 16),
    created_at timestamptz not null default now()
);

comment on table public.usage_events is
    'One row per newly claimed AI image unit (look visual or try-on angle). Used for daily/monthly quotas.';

create index if not exists usage_events_user_kind_created_idx
    on public.usage_events (user_id, kind, created_at desc);

alter table public.usage_events enable row level security;

revoke all on public.usage_events from anon, authenticated;
grant select, insert, update, delete on public.usage_events to grymode_api;

drop policy if exists usage_events_api_all on public.usage_events;
create policy usage_events_api_all on public.usage_events
for all to grymode_api
using (true)
with check (true);

-- Rebind existing paid renders to the stable signature scheme so opening them
-- does not re-bill. Look signatures are hashed to fit the 128-char column limit.
create extension if not exists pgcrypto;

update public.outfit_renders r
   set input_signature = 'look-v3:' || left(encode(digest(o.signature, 'sha256'), 'hex'), 40)
  from public.outfits o
 where r.outfit_id = o.id
   and r.kind = 'look'
   and r.input_signature is distinct from (
         'look-v3:' || left(encode(digest(o.signature, 'sha256'), 'hex'), 40)
       );

update public.outfit_renders r
   set input_signature = 'tryon-v3:' || left(
         encode(
           digest(
             coalesce(a.face_object_key, '') || '|' || a.height_cm::text || '|' || a.body_build || '|' || o.signature,
             'sha256'
           ),
           'hex'
         ),
         40
       )
  from public.avatar_profiles a, public.outfits o
 where r.user_id = a.user_id
   and r.outfit_id = o.id
   and r.kind = 'try_on'
   and a.face_object_key is not null;
