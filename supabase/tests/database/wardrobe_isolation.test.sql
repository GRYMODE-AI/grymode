-- Wardrobe RLS: a user can only see and change their own media and garments.
-- grymode_api (background extraction / deletion) can manage all wardrobe rows.
begin;
select plan(11);

insert into auth.users (id, email) values
    ('00000000-0000-4000-8000-0000000000aa', 'wardrobe-a@example.test'),
    ('00000000-0000-4000-8000-0000000000bb', 'wardrobe-b@example.test');

insert into public.wardrobe_media (id, user_id, object_key, media_type, content_type, processing_status)
values
    ('11111111-1111-1111-1111-111111111111', '00000000-0000-4000-8000-0000000000aa',
     '00000000-0000-4000-8000-0000000000aa/11111111-1111-1111-1111-111111111111/original.jpg',
     'photo', 'image/jpeg', 'ready'),
    ('22222222-2222-2222-2222-222222222222', '00000000-0000-4000-8000-0000000000bb',
     '00000000-0000-4000-8000-0000000000bb/22222222-2222-2222-2222-222222222222/original.jpg',
     'photo', 'image/jpeg', 'ready');

insert into public.garments (id, user_id, media_id, category, image_object_key, user_confirmed)
values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '00000000-0000-4000-8000-0000000000aa',
     '11111111-1111-1111-1111-111111111111', 'tops',
     '00000000-0000-4000-8000-0000000000aa/11111111-1111-1111-1111-111111111111/original.jpg', false),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '00000000-0000-4000-8000-0000000000bb',
     '22222222-2222-2222-2222-222222222222', 'shoes',
     '00000000-0000-4000-8000-0000000000bb/22222222-2222-2222-2222-222222222222/original.jpg', true);

set local role authenticated;
select set_config(
    'request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-0000000000aa","role":"authenticated"}',
    true
);

select is((select count(*)::int from public.wardrobe_media), 1, 'user A sees only their media');
select is((select count(*)::int from public.garments), 1, 'user A sees only their garments');
select is((select category from public.garments), 'tops', 'user A reads their garment');

update public.garments
   set category = 'bags'
 where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

select lives_ok(
    $$ insert into public.garments (user_id, category, image_object_key)
       values ('00000000-0000-4000-8000-0000000000aa', 'bottoms', 'a/b/original.jpg') $$,
    'user A can insert their own garment'
);

select throws_ok(
    $$ insert into public.garments (user_id, category, image_object_key)
       values ('00000000-0000-4000-8000-0000000000bb', 'bottoms', 'a/b/original.jpg') $$,
    '42501',
    null,
    'user A cannot insert a garment for user B'
);

reset role;
select is(
    (select category from public.garments where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
    'shoes',
    'user A cannot modify user B garments'
);

set local role authenticated;
select set_config(
    'request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-0000000000bb","role":"authenticated"}',
    true
);
select is((select count(*)::int from public.wardrobe_media), 1, 'user B sees one media row');
select is((select count(*)::int from public.garments), 1, 'user B sees one garment');
select is((select category from public.garments), 'shoes', 'user B sees their shoes');

reset role;
grant grymode_api to postgres;
set local role grymode_api;
select lives_ok(
    $$ insert into public.garments (user_id, media_id, category, image_object_key)
       values (
         '00000000-0000-4000-8000-0000000000aa',
         '11111111-1111-1111-1111-111111111111',
         'uncategorised',
         '00000000-0000-4000-8000-0000000000aa/11111111-1111-1111-1111-111111111111/draft.jpg'
       ) $$,
    'grymode_api can insert draft garments for extraction'
);
select is(
    (select count(*)::int from public.garments where user_id = '00000000-0000-4000-8000-0000000000aa'),
    3,
    'grymode_api sees all garments for a user during extraction'
);

select * from finish();
rollback;
