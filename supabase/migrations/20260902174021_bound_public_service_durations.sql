-- Service durations drive public availability, request snapshots and booking
-- end times. Quarantine legacy values that bypassed the app forms, then make
-- the database the authoritative boundary for every future write.

update public.services
   set duration_mins = 60,
       active = false,
       show_on_profile = false
 where duration_mins not between 5 and 1440;

alter table public.services
  add constraint services_duration_mins_check
  check (duration_mins between 5 and 1440);

comment on constraint services_duration_mins_check on public.services is
  'Base services last from 5 minutes to 24 hours. Invalid legacy rows were reset to 60 minutes and hidden pending owner review.';
