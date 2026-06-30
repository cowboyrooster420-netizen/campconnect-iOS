-- Campfire — Immersive announcements
-- Announcements become full-bleed cover-photo cards with an optional free-text
-- badge ("JUST POSTED", "TONIGHT · 8PM") and a single call-to-action button that
-- can link out (newsletter, registration, social). The cover photo reuses the
-- existing media_path (media_type='photo'). Idempotent; apply to the live DB.

alter table feed_items add column if not exists badge_label text;   -- free-text pill, e.g. "JUST POSTED"
alter table feed_items add column if not exists action_label text;  -- button text, e.g. "Read this issue"
alter table feed_items add column if not exists action_url text;    -- where the button links (opens externally)
