-- Outfit library + outfit_generation jobs. Outfits only reference the owner's garments.

alter table public.generation_jobs
    drop constraint if exists generation_jobs_job_type_check;

alter table public.generation_jobs
    add constraint generation_jobs_job_type_check
    check (job_type in ('garment_extraction', 'outfit_generation'));

comment on table public.generation_jobs is
    'Async work items: garment_extraction (Phase 3) and outfit_generation (Phase 4).';

create table public.outfits (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    title text not null check (char_length(title) between 1 and 80),
    signature text not null check (char_length(signature) between 1 and 200),
    occasion_tags text[] not null default '{}',
    style_tags text[] not null default '{}',
    contextual_tags text[] not null default '{}',
    score real not null check (score >= 0 and score <= 1),
    is_free_reveal boolean not null default false,
    generation_job_id uuid references public.generation_jobs (id) on delete set null,
    created_at timestamptz not null default now(),
    unique (user_id, signature)
);

comment on table public.outfits is
    'Persisted, validated outfit looks built only from the owner''s confirmed garments.';

create index outfits_user_created_idx on public.outfits (user_id, created_at desc);
create index outfits_user_score_idx on public.outfits (user_id, score desc);
create unique index outfits_one_free_reveal_per_user
    on public.outfits (user_id)
    where is_free_reveal;

create table public.outfit_garments (
    outfit_id uuid not null references public.outfits (id) on delete cascade,
    garment_id uuid not null references public.garments (id) on delete restrict,
    slot text not null check (slot in (
        'primary', 'bottom', 'footwear', 'outerwear', 'bag', 'accessory'
    )),
    position integer not null check (position >= 0 and position < 20),
    primary key (outfit_id, garment_id),
    unique (outfit_id, position)
);

comment on table public.outfit_garments is
    'Membership of a garment in an outfit. Cascade deletes with the outfit; garments are restrict-deleted.';

create index outfit_garments_garment_idx on public.outfit_garments (garment_id);

alter table public.outfits enable row level security;
alter table public.outfit_garments enable row level security;

revoke all on public.outfits from anon, authenticated;
revoke all on public.outfit_garments from anon, authenticated;

grant select, insert, update, delete on public.outfits to authenticated;
grant select, insert, update, delete on public.outfit_garments to authenticated;
grant select, insert, update, delete on public.outfits to grymode_api;
grant select, insert, update, delete on public.outfit_garments to grymode_api;

create policy outfits_own on public.outfits
for all to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy outfit_garments_own on public.outfit_garments
for all to authenticated
using (
    exists (
        select 1 from public.outfits o
         where o.id = outfit_id and o.user_id = (select auth.uid())
    )
)
with check (
    exists (
        select 1 from public.outfits o
         where o.id = outfit_id and o.user_id = (select auth.uid())
    )
);

create policy outfits_api_all on public.outfits
for all to grymode_api
using (true)
with check (true);

create policy outfit_garments_api_all on public.outfit_garments
for all to grymode_api
using (true)
with check (true);
