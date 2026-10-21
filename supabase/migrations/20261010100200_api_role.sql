-- Database role used by the Grymode API.
--
-- The API never connects as a superuser. For user-facing work it switches to `authenticated` with the
-- caller's verified JWT claims, so Row Level Security applies to every query. It has direct access
-- only to backend-owned tables.
--
-- The role is created without a password. Set one per environment, outside version control:
--   alter role grymode_api with login password '<from Secret Manager>';

create role grymode_api nologin noinherit;

grant authenticated to grymode_api;
grant usage on schema public to grymode_api;

grant select, insert, update on public.privacy_requests to grymode_api;

create policy privacy_requests_api_all on public.privacy_requests
for all to grymode_api
using (true)
with check (true);
