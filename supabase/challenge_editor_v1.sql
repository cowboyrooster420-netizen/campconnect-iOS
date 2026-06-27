-- Campfire — Challenge editor + relative nudge scheduling
-- Nudges are now authored inside a challenge's setup and scheduled RELATIVE to
-- the challenge's release ("drop 2 days after release"). We store the offset so
-- the drop time can be recomputed if the release date changes.
-- Idempotent; apply to the live DB.

alter table feed_items add column if not exists release_offset_days int;  -- nudges: days after challenge release
