-- CampConnect — full setup (schema -> storage -> seed). Generated; run once on a fresh DB.
-- ============================================================ SCHEMA
-- CampConnect — Year-Round Engagement Platform
-- Supabase schema (Postgres + RLS)
--
-- Design principles baked into this schema:
--   * NO social-network surface: no likes, no comments, no public feed tables.
--     Engagement is a structured loop: released challenge -> camper submission -> operator review -> badge.
--   * Counselor-driven authenticity: each season challenge carries the counselor video captured in summer.
--   * Low operational burden: a single "operator" role drives scheduling/approval per camp.
--   * Identity-first: campers belong to a camp (and optionally a cabin) year-round.
--
-- COPPA NOTE: campers are typically under 13. Camper accounts are NOT self-serve.
-- They are provisioned by a camp operator (or a consenting parent/guardian).
-- See profiles.created_by and the guardian_consent fields below.

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type user_role as enum ('camper', 'counselor', 'operator', 'parent');
exception when duplicate_object then null; end $$;

do $$ begin
  create type challenge_category as enum ('outdoor', 'creative', 'reflection', 'tradition');
exception when duplicate_object then null; end $$;

do $$ begin
  create type submission_format as enum ('photo', 'video', 'text');
exception when duplicate_object then null; end $$;

do $$ begin
  create type submission_status as enum ('pending', 'approved', 'rejected');
exception when duplicate_object then null; end $$;

do $$ begin
  create type season_challenge_status as enum ('scheduled', 'active', 'closed');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Camps
-- ---------------------------------------------------------------------------
create table if not exists camps (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text not null unique,
  logo_url    text,
  primary_color text default '#2E7D5B',
  season_year int not null default extract(year from now()),
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Profiles  (1:1 with auth.users)
-- ---------------------------------------------------------------------------
create table if not exists profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  camp_id       uuid references camps(id) on delete set null,
  role          user_role not null default 'camper',
  display_name  text not null,
  cabin         text,
  avatar_url    text,
  -- COPPA: campers are provisioned by operators/parents, not self-registered.
  created_by    uuid references auth.users(id),
  guardian_consent_at  timestamptz,         -- when a guardian granted consent
  guardian_email       text,
  total_points  int not null default 0,
  created_at    timestamptz not null default now()
);

create index if not exists profiles_camp_idx on profiles(camp_id);

-- ---------------------------------------------------------------------------
-- Challenge templates  (the prebuilt ~100-item library, shared across camps)
-- ---------------------------------------------------------------------------
create table if not exists challenge_templates (
  id              uuid primary key default gen_random_uuid(),
  title           text not null,
  summary         text not null,
  category        challenge_category not null,
  instructions    text not null,            -- what the kid does
  counselor_script text not null,           -- the script the star counselor reads on camera
  submission_format submission_format not null default 'photo',
  points          int not null default 50,
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Season challenges  (a camp's selected + sequenced instances of templates)
-- ---------------------------------------------------------------------------
create table if not exists season_challenges (
  id            uuid primary key default gen_random_uuid(),
  camp_id       uuid not null references camps(id) on delete cascade,
  template_id   uuid not null references challenge_templates(id),
  sequence_order int not null,              -- the camp's chosen order
  -- The summer-captured counselor video for THIS camp's run of the challenge.
  counselor_video_url text,
  release_at    timestamptz,                -- when it unlocks for campers
  due_at        timestamptz,
  status        season_challenge_status not null default 'scheduled',
  created_at    timestamptz not null default now(),
  unique (camp_id, sequence_order)
);

create index if not exists season_challenges_camp_idx on season_challenges(camp_id, status);

-- ---------------------------------------------------------------------------
-- Submissions  (camper -> challenge). Private to camper + camp operators.
-- ---------------------------------------------------------------------------
create table if not exists submissions (
  id                 uuid primary key default gen_random_uuid(),
  season_challenge_id uuid not null references season_challenges(id) on delete cascade,
  camper_id          uuid not null references profiles(id) on delete cascade,
  content_type       submission_format not null,
  media_path         text,                  -- path in the 'submissions' storage bucket
  text_content       text,
  status             submission_status not null default 'pending',
  reviewed_by        uuid references profiles(id),
  reviewed_at        timestamptz,
  created_at         timestamptz not null default now(),
  unique (season_challenge_id, camper_id)   -- one submission per challenge per camper
);

create index if not exists submissions_camper_idx on submissions(camper_id);
create index if not exists submissions_review_idx on submissions(status, season_challenge_id);

-- ---------------------------------------------------------------------------
-- Badges + awards
-- ---------------------------------------------------------------------------
create table if not exists badges (
  id          uuid primary key default gen_random_uuid(),
  camp_id     uuid references camps(id) on delete cascade,  -- null = global badge
  name        text not null,
  description text not null,
  icon        text not null default 'star.fill',            -- SF Symbol name
  -- Auto-award rule (null = awarded manually only). Supported shapes:
  --   {"type":"first_approval"}
  --   {"type":"category_count","category":"outdoor","count":3}
  criteria    jsonb,
  created_at  timestamptz not null default now()
);

create table if not exists badge_awards (
  id            uuid primary key default gen_random_uuid(),
  badge_id      uuid not null references badges(id) on delete cascade,
  camper_id     uuid not null references profiles(id) on delete cascade,
  season_challenge_id uuid references season_challenges(id) on delete set null,
  awarded_at    timestamptz not null default now(),
  unique (badge_id, camper_id)
);

create index if not exists badge_awards_camper_idx on badge_awards(camper_id);

-- ===========================================================================
-- Row Level Security
-- ===========================================================================
alter table camps               enable row level security;
alter table profiles            enable row level security;
alter table challenge_templates enable row level security;
alter table season_challenges   enable row level security;
alter table submissions         enable row level security;
alter table badges              enable row level security;
alter table badge_awards        enable row level security;

-- Helper: the caller's profile row
create or replace function current_profile()
returns profiles language sql stable security definer set search_path = public as $$
  select * from profiles where id = auth.uid()
$$;

create or replace function current_camp_id()
returns uuid language sql stable security definer set search_path = public as $$
  select camp_id from profiles where id = auth.uid()
$$;

create or replace function is_operator()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'operator')
$$;

-- Camps: anyone authenticated can read their own camp; operators manage theirs.
create policy camps_read on camps for select using (
  id = current_camp_id()
);
create policy camps_write on camps for all using (
  id = current_camp_id() and is_operator()
) with check (id = current_camp_id() and is_operator());

-- Profiles: read others in your camp; write only your own (operators write any in camp).
create policy profiles_read on profiles for select using (
  camp_id = current_camp_id()
);
create policy profiles_self_update on profiles for update using (
  id = auth.uid() or (camp_id = current_camp_id() and is_operator())
);
create policy profiles_insert on profiles for insert with check (
  id = auth.uid() or is_operator()
);

-- Challenge templates: readable by all authenticated users (shared library).
create policy templates_read on challenge_templates for select using (auth.role() = 'authenticated');

-- Season challenges: campers see active/closed ones in their camp; operators manage.
create policy season_read on season_challenges for select using (
  camp_id = current_camp_id() and (status <> 'scheduled' or is_operator())
);
create policy season_write on season_challenges for all using (
  camp_id = current_camp_id() and is_operator()
) with check (camp_id = current_camp_id() and is_operator());

-- Submissions: a camper sees/writes only their own; operators see/review all in camp.
create policy submissions_camper on submissions for select using (
  camper_id = auth.uid()
  or exists (
    select 1 from season_challenges sc
    where sc.id = submissions.season_challenge_id
      and sc.camp_id = current_camp_id()
      and is_operator()
  )
);
create policy submissions_insert on submissions for insert with check (camper_id = auth.uid());
create policy submissions_update on submissions for update using (
  exists (
    select 1 from season_challenges sc
    where sc.id = submissions.season_challenge_id
      and sc.camp_id = current_camp_id()
      and is_operator()
  )
);

-- Badges: readable within camp (or global); operators manage camp badges.
create policy badges_read on badges for select using (
  camp_id is null or camp_id = current_camp_id()
);
create policy badges_write on badges for all using (
  camp_id = current_camp_id() and is_operator()
) with check (camp_id = current_camp_id() and is_operator());

-- Badge awards: camper sees own; operators award within camp.
create policy badge_awards_read on badge_awards for select using (
  camper_id = auth.uid() or (current_camp_id() is not null and is_operator())
);
create policy badge_awards_write on badge_awards for all using (is_operator())
  with check (is_operator());

-- ===========================================================================
-- Trigger: keep profiles.total_points in sync when a badge is awarded via a
-- challenge, and auto-create a profile row on signup.
-- ===========================================================================
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', 'New Camper'), 'camper')
  on conflict (id) do nothing;

  -- Award the signup badge.
  insert into badge_awards (badge_id, camper_id)
  select b.id, new.id from badges b where b.criteria->>'type' = 'signup'
  on conflict (badge_id, camper_id) do nothing;

  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ===========================================================================
-- Auto-badge engine
-- When a submission transitions into 'approved', credit the challenge's points
-- to the camper and evaluate data-driven badge rules (badges.criteria).
-- Runs as SECURITY DEFINER so it applies no matter who approves (operator via
-- the dashboard, or a service-role approval in Supabase Studio).
-- ===========================================================================
create or replace function award_badges_on_approval()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_camper   uuid := new.camper_id;
  v_camp     uuid;
  v_template uuid;
  b          record;
  v_count    int;
begin
  -- Only act on a transition INTO approved (ignore edits that were already approved).
  if new.status <> 'approved' or old.status is not distinct from 'approved' then
    return new;
  end if;

  select p.camp_id into v_camp from profiles p where p.id = v_camper;
  select sc.template_id into v_template
    from season_challenges sc where sc.id = new.season_challenge_id;

  -- Evaluate auto-badge rules for this camp (plus any global badges).
  for b in
    select * from badges
    where criteria is not null and (camp_id = v_camp or camp_id is null)
  loop
    -- One badge per challenge: award the badge tied to this challenge's template.
    if (b.criteria->>'type') = 'challenge'
       and (b.criteria->>'template_id')::uuid = v_template then
      insert into badge_awards (badge_id, camper_id, season_challenge_id)
        values (b.id, v_camper, new.season_challenge_id)
        on conflict (badge_id, camper_id) do nothing;

    elsif (b.criteria->>'type') = 'first_approval' then
      insert into badge_awards (badge_id, camper_id, season_challenge_id)
        values (b.id, v_camper, new.season_challenge_id)
        on conflict (badge_id, camper_id) do nothing;

    elsif (b.criteria->>'type') = 'category_count' then
      select count(*) into v_count
      from submissions s
      join season_challenges sc on sc.id = s.season_challenge_id
      join challenge_templates ct on ct.id = sc.template_id
      where s.camper_id = v_camper
        and s.status = 'approved'
        and ct.category::text = (b.criteria->>'category');

      if v_count >= (b.criteria->>'count')::int then
        insert into badge_awards (badge_id, camper_id, season_challenge_id)
          values (b.id, v_camper, new.season_challenge_id)
          on conflict (badge_id, camper_id) do nothing;
      end if;
    end if;
  end loop;

  return new;
end $$;

drop trigger if exists on_submission_approved on submissions;
create trigger on_submission_approved
  after update on submissions
  for each row execute function award_badges_on_approval();

-- ===========================================================================
-- Guard: a camper can update their own profile (name, avatar) but cannot change
-- their own role or camp. Operators and service-role/SQL-editor flows are exempt.
-- ===========================================================================
create or replace function prevent_profile_escalation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() = old.id
     and not is_operator()
     and (new.role is distinct from old.role
          or new.camp_id is distinct from old.camp_id) then
    raise exception 'Campers cannot change their own role or camp.';
  end if;
  return new;
end $$;

drop trigger if exists guard_profile_escalation on profiles;
create trigger guard_profile_escalation
  before update on profiles
  for each row execute function prevent_profile_escalation();

-- ============================================================ STORAGE
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

-- ============================================================ SEED
-- CampConnect — seed data for local development / demo
-- Run AFTER schema.sql. Creates one demo camp, a handful of challenge templates
-- (a slice of the eventual ~100-item library), badges, and a sequenced season.
--
-- Note: profiles are created via Supabase Auth signup (handle_new_user trigger),
-- so this seed does not insert campers. Create a user in the app, then run the
-- "promote to operator" snippet at the bottom if you want operator screens.

-- --- Demo camp -------------------------------------------------------------
insert into camps (id, name, slug, primary_color, season_year)
values ('00000000-0000-0000-0000-000000000001', 'Camp Birchwood', 'birchwood', '#2E7D5B', 2026)
on conflict (id) do nothing;

-- --- Challenge templates (library slice) -----------------------------------
insert into challenge_templates (title, summary, category, instructions, counselor_script, submission_format, points) values
('Sunrise Summit',        'Catch a sunrise and capture the moment.', 'outdoor',
 'Wake up early, find a spot with a clear view east, and photograph the sunrise. Bonus: do it with a family member.',
 'Hey Birchwood! Remember morning hikes up to Eagle Point? This month I want YOU to find your own sunrise. Send me what you see!',
 'photo', 60),
('Knot Master',           'Learn and tie three camp knots.', 'outdoor',
 'Tie a bowline, a clove hitch, and a figure-eight. Record a short video showing all three.',
 'You all crushed knots at the waterfront this summer. Show me you still got it — three knots, one video. Go!',
 'video', 50),
('Trail Cleanup',         'Leave a place better than you found it.', 'outdoor',
 'Spend 20 minutes picking up litter at a local park or trail. Photograph your bag of trash collected.',
 'Leave No Trace isnt just a summer thing. Pick a spot near you, clean it up, and show me the difference you made.',
 'photo', 70),
('Cabin Recipe',          'Recreate a camp meal at home.', 'creative',
 'Make a dish we ate at camp (or your version of it). Photograph the finished plate.',
 'Bug juice and bonfire smores forever. Recreate a Birchwood meal at home and send me a photo — I am hungry already!',
 'photo', 50),
('Camp Song Cover',       'Perform a camp song your way.', 'creative',
 'Record a 30-second video performing your favorite camp song. Solo, duet, kazoo — your call.',
 'The Birchwood anthem lives in you all year. Give me your best version — I want to hear those voices!',
 'video', 60),
('Friendship Bracelet',   'Make and gift a bracelet.', 'creative',
 'Make a friendship bracelet and give it to someone. Photograph the bracelet (or the hand-off).',
 'Arts and crafts cabin, assemble! Make a bracelet, give it away, and tell me who got it.',
 'photo', 40),
('Gratitude Letter',      'Write to someone from your camp summer.', 'reflection',
 'Write a short letter to a counselor, friend, or family member about a camp memory. Submit the text.',
 'This one is from the heart. Think of someone who made your summer special and tell them. I will be reading these.',
 'text', 50),
('One Good Thing',        'Reflect on a small daily win.', 'reflection',
 'Write a few sentences about one good thing that happened this week.',
 'Campfire reflections, off-season edition. One good thing — thats all. Whats yours this week?',
 'text', 30),
('Future Self',           'Set a goal for next summer.', 'reflection',
 'Write down one thing you want to be better at by next camp. Submit the text.',
 'Next summer you is counting on this summer you. Set one goal and write it down. I will check in!',
 'text', 40),
('Polar Bear Plunge',     'Brave the cold like a true camper.', 'tradition',
 'Recreate the camp polar plunge — a cold shower counts! Capture a (safe) photo or video of the moment.',
 'You know what time it is. The Birchwood Polar Plunge does NOT take winters off. Show me you are still brave!',
 'video', 80),
('Flag Raising',          'Honor the morning flag tradition.', 'tradition',
 'Recreate our morning flag ceremony — raise any flag, or make one. Photograph it.',
 'Every Birchwood morning started at the flagpole. Bring that tradition home and show me your colors.',
 'photo', 40),
('Color War Spirit',      'Rep your team color.', 'tradition',
 'Wear or display your color-war team color and photograph it proudly.',
 'GREEN TEAM, BLUE TEAM — the rivalry never sleeps! Rep your color and let me see that camp spirit!',
 'photo', 50)
on conflict do nothing;

-- --- Badges (with auto-award rules in `criteria`) --------------------------
-- Year-Rounder has no criteria (manual award — monthly-activity rule is future work).
insert into badges (camp_id, name, description, icon, criteria) values
('00000000-0000-0000-0000-000000000001', 'First Step',   'Completed your first off-season challenge.',   'figure.walk',     '{"type":"first_approval"}'),
('00000000-0000-0000-0000-000000000001', 'Trailblazer',  'Completed 3 outdoor challenges.',               'mountain.2.fill', '{"type":"category_count","category":"outdoor","count":3}'),
('00000000-0000-0000-0000-000000000001', 'Camp Spirit',  'Completed a tradition challenge.',              'flame.fill',      '{"type":"category_count","category":"tradition","count":1}'),
('00000000-0000-0000-0000-000000000001', 'Storyteller',  'Completed a reflection challenge.',             'book.fill',       '{"type":"category_count","category":"reflection","count":1}'),
('00000000-0000-0000-0000-000000000001', 'Year-Rounder', 'Stayed active every month of the off-season.',  'crown.fill',      null)
on conflict do nothing;

-- One badge per challenge (global; awarded when that challenge is approved).
insert into badges (camp_id, name, description, icon, criteria)
select null, t.title, 'Completed the ' || t.title || ' challenge.',
  case t.category when 'outdoor' then 'leaf' when 'creative' then 'color-palette'
                  when 'reflection' then 'book' when 'tradition' then 'flame' end,
  jsonb_build_object('type', 'challenge', 'template_id', t.id)
from challenge_templates t
where not exists (select 1 from badges b
  where b.criteria->>'type' = 'challenge' and (b.criteria->>'template_id')::uuid = t.id);

-- Signup badge (global).
insert into badges (camp_id, name, description, icon, criteria)
select null, 'Welcome to Camp!', 'Joined and started your year-round journey.', 'happy', '{"type":"signup"}'::jsonb
where not exists (select 1 from badges where criteria->>'type' = 'signup');

-- --- A sequenced season (challenges released over the off-season) -----------
-- Pull the first 6 templates and schedule them month-by-month.
insert into season_challenges (camp_id, template_id, sequence_order, release_at, due_at, status)
select '00000000-0000-0000-0000-000000000001',
       t.id,
       row_number() over (order by t.created_at),
       now() - interval '7 days',     -- demo: release the first few immediately
       now() + interval '30 days',
       case when row_number() over (order by t.created_at) <= 3 then 'active'::season_challenge_status
            else 'scheduled'::season_challenge_status end
from (select id, created_at from challenge_templates order by created_at limit 6) t
on conflict do nothing;

-- --- Promote a user to operator (run manually after creating an account) ----
-- update profiles
--   set role = 'operator', camp_id = '00000000-0000-0000-0000-000000000001'
--   where id = (select id from auth.users where email = 'you@example.com');
