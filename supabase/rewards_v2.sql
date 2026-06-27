-- CampConnect — Rewards v2 migration
-- Shifts the reward model from points to badges:
--   * one badge per challenge (awarded when that challenge is approved)
--   * a signup badge (awarded when a camper account is created)
--   * profile avatars (new private 'avatars' storage bucket)
--   * stops crediting points on approval (kept the column; just not the focus)
--   * closes the RLS hole that let campers self-promote to operator
-- Idempotent — safe to run more than once. Apply to the live DB.

-- ---------------------------------------------------------------------------
-- 1) Avatars storage bucket (private; camper writes own folder, camp can read)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false)
on conflict (id) do nothing;

drop policy if exists "avatars owner rw" on storage.objects;
create policy "avatars owner rw"
on storage.objects for all to authenticated
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars camp read" on storage.objects;
create policy "avatars camp read"
on storage.objects for select to authenticated
using (bucket_id = 'avatars');

-- ---------------------------------------------------------------------------
-- 2) One badge per challenge template (global badges; criteria.type='challenge')
-- ---------------------------------------------------------------------------
insert into badges (camp_id, name, description, icon, criteria)
select
  null,
  t.title,
  'Completed the ' || t.title || ' challenge.',
  case t.category
    when 'outdoor'    then 'leaf'
    when 'creative'   then 'color-palette'
    when 'reflection' then 'book'
    when 'tradition'  then 'flame'
  end,
  jsonb_build_object('type', 'challenge', 'template_id', t.id)
from challenge_templates t
where not exists (
  select 1 from badges b
  where b.criteria->>'type' = 'challenge'
    and (b.criteria->>'template_id')::uuid = t.id
);

-- ---------------------------------------------------------------------------
-- 3) Signup badge (global; criteria.type='signup')
-- ---------------------------------------------------------------------------
insert into badges (camp_id, name, description, icon, criteria)
select null, 'Welcome to Camp!', 'Joined and started your year-round journey.', 'happy',
       '{"type":"signup"}'::jsonb
where not exists (select 1 from badges where criteria->>'type' = 'signup');

-- ---------------------------------------------------------------------------
-- 4) Approval trigger: award the challenge's badge (no more points)
-- ---------------------------------------------------------------------------
create or replace function award_badges_on_approval()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_camper   uuid := new.camper_id;
  v_camp     uuid;
  v_template uuid;
  b          record;
  v_count    int;
begin
  if new.status <> 'approved' or old.status is not distinct from 'approved' then
    return new;
  end if;

  select p.camp_id into v_camp from profiles p where p.id = v_camper;
  select sc.template_id into v_template
    from season_challenges sc where sc.id = new.season_challenge_id;

  for b in
    select * from badges
    where criteria is not null and (camp_id = v_camp or camp_id is null)
  loop
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
      where s.camper_id = v_camper and s.status = 'approved'
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

-- ---------------------------------------------------------------------------
-- 5) Signup badge on account creation (extends the existing handle_new_user)
-- ---------------------------------------------------------------------------
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', 'New Camper'), 'camper')
  on conflict (id) do nothing;

  insert into badge_awards (badge_id, camper_id)
  select b.id, new.id from badges b where b.criteria->>'type' = 'signup'
  on conflict (badge_id, camper_id) do nothing;

  return new;
end $$;

-- ---------------------------------------------------------------------------
-- 6) Close the RLS hole: campers can't change their own role/camp via self-update
--    (operators and service-role/SQL-editor flows are unaffected)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 7) Backfill so existing data reflects the new model
-- ---------------------------------------------------------------------------
-- Challenge badges for already-approved submissions:
insert into badge_awards (badge_id, camper_id, season_challenge_id)
select b.id, s.camper_id, s.season_challenge_id
from submissions s
join season_challenges sc on sc.id = s.season_challenge_id
join badges b on b.criteria->>'type' = 'challenge'
            and (b.criteria->>'template_id')::uuid = sc.template_id
where s.status = 'approved'
on conflict (badge_id, camper_id) do nothing;

-- Signup badge for everyone who already has an account:
insert into badge_awards (badge_id, camper_id)
select b.id, p.id
from badges b cross join profiles p
where b.criteria->>'type' = 'signup'
on conflict (badge_id, camper_id) do nothing;
