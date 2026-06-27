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

-- --- Badges ----------------------------------------------------------------
insert into badges (camp_id, name, description, icon) values
('00000000-0000-0000-0000-000000000001', 'First Step',     'Completed your first off-season challenge.', 'figure.walk'),
('00000000-0000-0000-0000-000000000001', 'Trailblazer',    'Completed 3 outdoor challenges.',            'mountain.2.fill'),
('00000000-0000-0000-0000-000000000001', 'Camp Spirit',    'Completed a tradition challenge.',           'flame.fill'),
('00000000-0000-0000-0000-000000000001', 'Storyteller',    'Completed a reflection challenge.',          'book.fill'),
('00000000-0000-0000-0000-000000000001', 'Year-Rounder',   'Stayed active every month of the off-season.', 'crown.fill')
on conflict do nothing;

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
