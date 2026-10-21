-- Private avatar profile for personal try-on previews (foundation; full 3D/VR is post-MVP).

create table public.avatar_profiles (
    user_id uuid primary key references auth.users (id) on delete cascade,
    height_cm smallint not null
        check (height_cm between 120 and 230),
    body_build text not null
        check (body_build in ('slim', 'regular', 'athletic', 'broad')),
    face_object_key text
        check (face_object_key is null or char_length(face_object_key) between 8 and 512),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on table public.avatar_profiles is
    'Owner-stated height/build and optional private face photo for personal outfit previews.';

create trigger avatar_profiles_set_updated_at
before update on public.avatar_profiles
for each row execute function public.set_updated_at();

alter table public.avatar_profiles enable row level security;

revoke all on public.avatar_profiles from anon, authenticated;
grant select, insert, update, delete on public.avatar_profiles to authenticated;
grant select, insert, update, delete on public.avatar_profiles to grymode_api;

create policy avatar_profiles_own on public.avatar_profiles
for all to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy avatar_profiles_api_all on public.avatar_profiles
for all to grymode_api
using (true)
with check (true);
