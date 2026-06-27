-- CampConnect — Auto-badge engine migration
-- Apply this to a database that was provisioned BEFORE the auto-badge feature.
-- (Fresh setups already get everything from schema.sql + seed.sql.)
-- Safe to run more than once.

-- 1) Add the rule column to badges if it isn't there yet.
alter table badges add column if not exists criteria jsonb;

-- 2) Backfill criteria on the demo camp's seeded badges (match by name).
update badges set criteria = '{"type":"first_approval"}'
  where name = 'First Step' and criteria is null;
update badges set criteria = '{"type":"category_count","category":"outdoor","count":3}'
  where name = 'Trailblazer' and criteria is null;
update badges set criteria = '{"type":"category_count","category":"tradition","count":1}'
  where name = 'Camp Spirit' and criteria is null;
update badges set criteria = '{"type":"category_count","category":"reflection","count":1}'
  where name = 'Storyteller' and criteria is null;

-- 3) Trigger function: credit points + evaluate badge rules on approval.
create or replace function award_badges_on_approval()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_camper  uuid := new.camper_id;
  v_camp    uuid;
  v_points  int;
  b         record;
  v_count   int;
begin
  if new.status <> 'approved' or old.status is not distinct from 'approved' then
    return new;
  end if;

  select p.camp_id into v_camp from profiles p where p.id = v_camper;

  select ct.points into v_points
  from season_challenges sc
  join challenge_templates ct on ct.id = sc.template_id
  where sc.id = new.season_challenge_id;

  update profiles
    set total_points = total_points + coalesce(v_points, 0)
    where id = v_camper;

  for b in
    select * from badges
    where criteria is not null and (camp_id = v_camp or camp_id is null)
  loop
    if (b.criteria->>'type') = 'first_approval' then
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
