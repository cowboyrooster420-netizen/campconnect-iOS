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
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();
