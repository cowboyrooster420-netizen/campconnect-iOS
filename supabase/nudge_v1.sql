-- Campfire — Nudge migration
-- Reframes the feed:
--   * NEW 'nudge' type — a counselor check-in video tied to a challenge, dropped
--     mid-period ("done the camp song one yet? …off to lunch in the dining hall").
--   * Retires 'memory' (nostalgia now lives inside the nudge script) → folded into announcements.
--   * Feed media can be photo OR video (announcements support text/photo/video).
-- Idempotent; apply to the live DB.

-- New feed type. (ADD VALUE is safe here — we don't use 'nudge' later in this script.)
alter type feed_item_type add value if not exists 'nudge';

-- Distinguish photo vs video media on a feed item.
alter table feed_items add column if not exists media_type text;  -- 'photo' | 'video'

-- Existing media feed items are all videos.
update feed_items set media_type = 'video' where media_path is not null and media_type is null;

-- Retire 'memory' — fold any existing ones into announcements (which now allow media).
update feed_items set type = 'announcement' where type = 'memory';

-- Allow MANY nudges per challenge, while keeping one intro + one wrap-up (the shadow items).
drop index if exists feed_items_challenge_kind;
create unique index if not exists feed_items_challenge_kind
  on feed_items(season_challenge_id, type)
  where season_challenge_id is not null and type in ('challenge', 'wrap_up');
