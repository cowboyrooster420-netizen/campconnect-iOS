-- Campfire — Announcement scene picker
-- Lets the operator choose the illustrated background ('sunrise' | 'lake' | 'dusk')
-- for an announcement that has no cover photo. Null = auto (deterministic by id).
-- Idempotent; apply to the live DB.

alter table feed_items add column if not exists scene text;  -- 'sunrise' | 'lake' | 'dusk'
