-- Local development only. `supabase db reset` runs this after the migrations; it is never applied to
-- hosted projects.

alter role grymode_api with login password 'grymode-local-dev-only';
