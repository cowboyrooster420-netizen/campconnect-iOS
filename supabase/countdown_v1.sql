-- Campfire — Countdown to camp
-- A camp's next session start date, for the "X days until camp!" hook on the
-- home feed. Idempotent; apply to the live DB.

alter table camps add column if not exists session_start_date date;

-- Demo: point Camp Birchwood at next summer so the countdown shows something.
update camps
  set session_start_date = '2027-06-21'
  where id = '00000000-0000-0000-0000-000000000001'
    and session_start_date is null;
