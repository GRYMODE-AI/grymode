-- Try-on cache must include avatar.updated_at so replacing face.jpg at a fixed key
-- invalidates prior angles. Re-stamp succeeded try-ons to tryon-v4 without re-rendering.

update public.outfit_renders r
   set input_signature = 'tryon-v4:' || left(
         encode(
           digest(
             coalesce(a.face_object_key, '') || '|' ||
             trunc(extract(epoch from a.updated_at))::bigint::text || '|' ||
             a.height_cm::text || '|' || a.body_build || '|' || o.signature,
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
