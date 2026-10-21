-- User isolation and least-privilege checks. Run with: supabase test db
begin;
select plan(17);

-- Two users. Profiles must be created by the sign-up trigger.
insert into auth.users (id, email) values
    ('00000000-0000-4000-8000-00000000000a', 'alice@example.test'),
    ('00000000-0000-4000-8000-00000000000b', 'bob@example.test');

select is(
    (select count(*)::int from public.profiles where id in (
        '00000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000b')),
    2,
    'a profile is created for every new user'
);

-- Act as Alice.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}', true);

select results_eq(
    'select id from public.profiles',
    $$values ('00000000-0000-4000-8000-00000000000a'::uuid)$$,
    'a user can read only their own profile'
);

select lives_ok(
    $$update public.profiles set display_name = 'Alice', style_profile = '{"axes":{}}' where id = '00000000-0000-4000-8000-00000000000a'$$,
    'a user can update their own profile'
);

update public.profiles set display_name = 'Mallory' where id = '00000000-0000-4000-8000-00000000000b';

select throws_ok(
    $$insert into public.profiles (id) values ('00000000-0000-4000-8000-00000000000c')$$,
    '42501',
    null,
    'a user cannot create profiles'
);

select throws_ok(
    $$update public.profiles set id = '00000000-0000-4000-8000-00000000000c' where id = '00000000-0000-4000-8000-00000000000a'$$,
    '42501',
    null,
    'a user cannot change a profile id'
);

select throws_ok(
    $$update public.profiles set created_at = now() where id = '00000000-0000-4000-8000-00000000000a'$$,
    '42501',
    null,
    'a user cannot change server-managed timestamps'
);

select throws_ok(
    'delete from public.profiles',
    '42501',
    null,
    'a user cannot delete profiles directly'
);

select throws_ok(
    'select * from public.privacy_requests',
    '42501',
    null,
    'a user cannot read privacy requests'
);

select throws_ok(
    $$update public.profiles set style_profile = '[]' where id = '00000000-0000-4000-8000-00000000000a'$$,
    '23514',
    null,
    'style_profile must be a JSON object'
);

-- Anonymous callers see nothing.
reset role;
set local role anon;
select throws_ok('select * from public.profiles', '42501', null, 'anonymous callers cannot read profiles');

-- Verify as the table owner that Bob's row was untouched and Alice's update landed.
reset role;
select is(
    (select display_name from public.profiles where id = '00000000-0000-4000-8000-00000000000b'),
    null,
    'a user cannot modify another user''s profile'
);
select is(
    (select display_name from public.profiles where id = '00000000-0000-4000-8000-00000000000a'),
    'Alice',
    'own update persisted'
);

-- The API role: no direct table access to user data, but may act as the caller.
-- Supabase's postgres role isn't a superuser, so it needs membership to impersonate the API role
-- (rolled back with the rest of the test). The backend integration suite logs in as grymode_api for real.
grant grymode_api to postgres;
-- pgTAP's functions live in the extensions schema, which the API role can't otherwise see.
grant usage on schema extensions to grymode_api;
set local role grymode_api;
select throws_ok('select * from public.profiles', '42501', null, 'the API role cannot read profiles without acting as a user');
select lives_ok(
    $$insert into public.privacy_requests (user_id, request_type) values ('00000000-0000-4000-8000-00000000000a', 'account_deletion')$$,
    'the API role can record a privacy request'
);
select throws_ok(
    $$insert into public.privacy_requests (user_id, request_type) values ('00000000-0000-4000-8000-00000000000a', 'account_deletion')$$,
    '23505',
    null,
    'only one open deletion request per user'
);
set local role authenticated;
select is((select count(*)::int from public.profiles), 1, 'the API role can switch to the caller and is then bound by RLS');

-- Deleting the Auth user removes the profile.
reset role;
delete from auth.users where id = '00000000-0000-4000-8000-00000000000a';
select is(
    (select count(*)::int from public.profiles where id = '00000000-0000-4000-8000-00000000000a'),
    0,
    'deleting the account deletes the profile'
);

select * from finish();
rollback;
