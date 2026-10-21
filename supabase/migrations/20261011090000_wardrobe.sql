-- Wardrobe media, extraction jobs, and confirmed garments. All user-owned; RLS enforced.
-- Original files live in the private `wardrobe` storage bucket at
-- `{user_id}/{media_id}/original.{ext}`. Access is only through short-lived signed URLs
-- issued by the Grymode API (service role). The authenticated role has no direct Storage grants.

create table public.wardrobe_media (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    object_key text not null,
    media_type text not null check (media_type in ('photo', 'video_frame')),
    content_type text not null,
    byte_size integer check (byte_size is null or (byte_size > 0 and byte_size <= 52428800)),
    processing_status text not null default 'awaiting_upload'
        check (processing_status in (
            'awaiting_upload', 'uploaded', 'processing', 'ready', 'failed'
        )),
    retention_status text not null default 'active'
        check (retention_status in ('active', 'pending_delete', 'deleted')),
    error_code text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id, object_key)
);

comment on table public.wardrobe_media is
    'Original wardrobe uploads (photos or frames extracted from video). Private Storage objects.';

create index wardrobe_media_user_created_idx on public.wardrobe_media (user_id, created_at desc);

create trigger wardrobe_media_set_updated_at
before update on public.wardrobe_media
for each row execute function public.set_updated_at();

create table public.generation_jobs (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    media_id uuid references public.wardrobe_media (id) on delete cascade,
    job_type text not null check (job_type in ('garment_extraction')),
    status text not null default 'pending'
        check (status in ('pending', 'running', 'succeeded', 'failed')),
    progress_stage text,
    attempt_count integer not null default 0 check (attempt_count >= 0 and attempt_count <= 20),
    idempotency_key text not null,
    error_code text,
    created_at timestamptz not null default now(),
    started_at timestamptz,
    completed_at timestamptz,
    unique (user_id, idempotency_key)
);

comment on table public.generation_jobs is
    'Async work items. Phase 3 uses garment_extraction; later phases add outfit generation.';

create index generation_jobs_user_status_idx on public.generation_jobs (user_id, status, created_at desc);
create index generation_jobs_media_idx on public.generation_jobs (media_id);

create table public.garments (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    media_id uuid references public.wardrobe_media (id) on delete set null,
    category text not null default 'uncategorised'
        check (category in (
            'tops', 'bottoms', 'dresses', 'outerwear', 'shoes', 'bags',
            'accessories', 'knitwear', 'activewear', 'uncategorised'
        )),
    subcategory text check (subcategory is null or char_length(subcategory) between 1 and 40),
    primary_color text check (primary_color is null or char_length(primary_color) between 1 and 40),
    secondary_colors text[] not null default '{}',
    pattern text check (pattern is null or char_length(pattern) between 1 and 40),
    material text check (material is null or char_length(material) between 1 and 40),
    silhouette text check (silhouette is null or char_length(silhouette) between 1 and 40),
    formality text check (formality is null or formality in ('casual', 'smartCasual', 'formal')),
    season_tags text[] not null default '{}',
    style_tags text[] not null default '{}',
    image_object_key text not null,
    confidence real check (confidence is null or (confidence >= 0 and confidence <= 1)),
    user_confirmed boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on table public.garments is
    'Individual wardrobe pieces. user_confirmed=false until the owner reviews the extraction.';

create index garments_user_confirmed_idx on public.garments (user_id, user_confirmed, created_at desc);
create index garments_user_category_idx on public.garments (user_id, category);

create trigger garments_set_updated_at
before update on public.garments
for each row execute function public.set_updated_at();

-- RLS -----------------------------------------------------------------

alter table public.wardrobe_media enable row level security;
alter table public.generation_jobs enable row level security;
alter table public.garments enable row level security;

revoke all on public.wardrobe_media from anon, authenticated;
revoke all on public.generation_jobs from anon, authenticated;
revoke all on public.garments from anon, authenticated;

grant select, insert, update, delete on public.wardrobe_media to authenticated;
grant select, insert, update on public.generation_jobs to authenticated;
grant select, insert, update, delete on public.garments to authenticated;

create policy wardrobe_media_own on public.wardrobe_media
for all to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy generation_jobs_own on public.generation_jobs
for all to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy garments_own on public.garments
for all to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Private Storage bucket. No policies for authenticated/anon: the API signs every URL. --

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'wardrobe',
    'wardrobe',
    false,
    52428800,
    array[
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/heic',
        'image/heif'
    ]
)
on conflict (id) do update set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
