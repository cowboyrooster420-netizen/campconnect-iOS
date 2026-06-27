-- CampConnect — Feed v1 migration
-- A one-way, operator-curated camp content feed (a "camp channel"): counselor
-- challenge videos, challenge wrap-ups, scheduled "camp memories", and
-- announcements. NO camper posting, NO likes/comments — broadcast only.
-- Idempotent; apply to the live DB.

-- ---------------------------------------------------------------------------
-- Types + tables
-- ---------------------------------------------------------------------------
do $$ begin
  create type feed_item_type as enum ('challenge', 'wrap_up', 'memory', 'announcement');
exception when duplicate_object then null; end $$;

create table if not exists feed_items (
  id          uuid primary key default gen_random_uuid(),
  camp_id     uuid not null references camps(id) on delete cascade,
  type        feed_item_type not null,
  title       text not null,
  caption     text,
  -- storage path in 'counselor-videos' bucket OR external URL; null = text-only
  media_path  text,
  -- challenge/wrap_up items link back to a challenge (tap → challenge screen)
  season_challenge_id uuid references season_challenges(id) on delete cascade,
  -- scheduling: campers see items once publish_at has passed
  publish_at  timestamptz not null default now(),
  created_by  uuid references profiles(id),
  created_at  timestamptz not null default now()
);

create index if not exists feed_items_camp_idx on feed_items(camp_id, publish_at desc);
-- one shadow feed entry per challenge per kind (so re-setting a video upserts)
create unique index if not exists feed_items_challenge_kind
  on feed_items(season_challenge_id, type)
  where season_challenge_id is not null;

-- Wrap-up video on the challenge itself (mirrors counselor_video_url).
alter table season_challenges add column if not exists recap_video_url text;

-- ---------------------------------------------------------------------------
-- RLS: campers read published items in their camp; operators manage all.
-- ---------------------------------------------------------------------------
alter table feed_items enable row level security;

drop policy if exists feed_read on feed_items;
create policy feed_read on feed_items for select using (
  camp_id = current_camp_id() and (publish_at <= now() or is_operator())
);

drop policy if exists feed_write on feed_items;
create policy feed_write on feed_items for all using (
  camp_id = current_camp_id() and is_operator()
) with check (camp_id = current_camp_id() and is_operator());

-- ---------------------------------------------------------------------------
-- Backfill shadow feed items for challenge videos that already exist.
-- ---------------------------------------------------------------------------
insert into feed_items (camp_id, type, title, caption, media_path, season_challenge_id, publish_at)
select sc.camp_id, 'challenge', t.title, 'New challenge unlocked', sc.counselor_video_url, sc.id,
       coalesce(sc.release_at, sc.created_at)
from season_challenges sc
join challenge_templates t on t.id = sc.template_id
where sc.counselor_video_url is not null
on conflict (season_challenge_id, type) where season_challenge_id is not null do nothing;
