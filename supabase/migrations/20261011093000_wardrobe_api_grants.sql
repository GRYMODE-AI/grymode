-- Background extraction and account deletion run as grymode_api (NOINHERIT),
-- so they need explicit table grants + RLS policies — same pattern as privacy_requests.

grant select, insert, update, delete on public.wardrobe_media to grymode_api;
grant select, insert, update on public.generation_jobs to grymode_api;
grant select, insert, update, delete on public.garments to grymode_api;

create policy wardrobe_media_api_all on public.wardrobe_media
for all to grymode_api
using (true)
with check (true);

create policy generation_jobs_api_all on public.generation_jobs
for all to grymode_api
using (true)
with check (true);

create policy garments_api_all on public.garments
for all to grymode_api
using (true)
with check (true);
