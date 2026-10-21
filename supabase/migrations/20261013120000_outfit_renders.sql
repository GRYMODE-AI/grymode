-- AI-rendered visuals for looks: a styled look image and multi-angle personal try-on renders.
-- Images live in the private `wardrobe` bucket under {user_id}/renders/…; the API signs every URL.

create table public.outfit_renders (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    outfit_id uuid not null references public.outfits (id) on delete cascade,
    kind text not null check (kind in ('look', 'try_on')),
    view text not null check (view in ('front', 'three_quarter', 'side', 'back')),
    status text not null default 'pending'
        check (status in ('pending', 'running', 'succeeded', 'failed')),
    object_key text check (object_key is null or char_length(object_key) between 8 and 512),
    input_signature text check (input_signature is null or char_length(input_signature) <= 128),
    model text check (model is null or char_length(model) <= 80),
    error_code text check (error_code is null or char_length(error_code) <= 64),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (outfit_id, kind, view),
    check ((status = 'succeeded') = (object_key is not null))
);

comment on table public.outfit_renders is
    'AI-rendered look visuals and personal try-on angles for the owner''s outfits.';

create index outfit_renders_user_idx on public.outfit_renders (user_id, outfit_id);

create trigger outfit_renders_set_updated_at
before update on public.outfit_renders
for each row execute function public.set_updated_at();

alter table public.outfit_renders enable row level security;

revoke all on public.outfit_renders from anon, authenticated;
grant select on public.outfit_renders to authenticated;
grant select, insert, update, delete on public.outfit_renders to grymode_api;

create policy outfit_renders_own_read on public.outfit_renders
for select to authenticated
using ((select auth.uid()) = user_id);

create policy outfit_renders_api_all on public.outfit_renders
for all to grymode_api
using (true)
with check (true);
