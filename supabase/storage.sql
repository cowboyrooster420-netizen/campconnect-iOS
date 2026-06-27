-- CampConnect — Storage buckets + policies
-- Run in the Supabase SQL editor after schema.sql.
--
-- Two private buckets:
--   submissions      : camper-uploaded photos/videos (private to camper + operators)
--   counselor-videos : summer-captured counselor content (read by camp members)

insert into storage.buckets (id, name, public)
values ('submissions', 'submissions', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('counselor-videos', 'counselor-videos', false)
on conflict (id) do nothing;

-- avatars : camper profile photos (private; camper writes own folder, camp can read)
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false)
on conflict (id) do nothing;

-- Campers may upload/read only files under their own user-id folder.
-- Paths are "<auth.uid>/<challenge-id>.<ext>".
create policy "submissions camper rw"
on storage.objects for all
to authenticated
using (
  bucket_id = 'submissions'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'submissions'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Operators may read every submission in their camp (review queue).
create policy "submissions operator read"
on storage.objects for select
to authenticated
using (
  bucket_id = 'submissions'
  and exists (select 1 from profiles where id = auth.uid() and role = 'operator')
);

-- Any authenticated camp member can read counselor videos.
create policy "counselor videos read"
on storage.objects for select
to authenticated
using (bucket_id = 'counselor-videos');

-- Only operators upload/replace/remove counselor videos.
-- `for all` (not just insert) so re-uploading a video (upsert) and clearing it work.
-- Drop-if-exists so this file is safe to re-run after the original insert-only policy.
drop policy if exists "counselor videos operator write" on storage.objects;
create policy "counselor videos operator write"
on storage.objects for all
to authenticated
using (
  bucket_id = 'counselor-videos'
  and exists (select 1 from profiles where id = auth.uid() and role = 'operator')
)
with check (
  bucket_id = 'counselor-videos'
  and exists (select 1 from profiles where id = auth.uid() and role = 'operator')
);

-- Avatars: camper reads/writes only files under their own user-id folder.
drop policy if exists "avatars owner rw" on storage.objects;
create policy "avatars owner rw"
on storage.objects for all to authenticated
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- Any authenticated camp member can read avatars.
drop policy if exists "avatars camp read" on storage.objects;
create policy "avatars camp read"
on storage.objects for select to authenticated
using (bucket_id = 'avatars');
