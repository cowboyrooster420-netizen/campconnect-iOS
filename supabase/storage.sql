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

-- Only operators upload counselor videos.
create policy "counselor videos operator write"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'counselor-videos'
  and exists (select 1 from profiles where id = auth.uid() and role = 'operator')
);
