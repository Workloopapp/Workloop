begin;
set local search_path = public, extensions;
select no_plan();
insert into public.workspaces(id,name) values('83100000-0000-4000-8000-000000000001','Annual mileage QA');
insert into public.workspace_tax_estimates(workspace_id,tax_year,rules_version,jurisdiction,turnover_minor,non_vehicle_expenses_minor,actual_vehicle_expenses_minor,paid_to_hmrc_minor,reserve_minor,vehicle_method)
values('83100000-0000-4000-8000-000000000001','2026/27','uk-ewni-2026-27-v1','england',5000000,1000000,0,0,0,'mileage');
select is((select annual_car_van_miles_hundredths from public.workspace_tax_estimates where workspace_id='83100000-0000-4000-8000-000000000001'),null::bigint,'legacy estimates do not invent an annual mileage forecast');
select lives_ok($$update public.workspace_tax_estimates set annual_car_van_miles_hundredths=1100000,annual_motorcycle_miles_hundredths=0 where workspace_id='83100000-0000-4000-8000-000000000001'$$,'whole-year mileage inputs can be saved separately from journeys');
select throws_ok($$update public.workspace_tax_estimates set annual_car_van_miles_hundredths=-1 where workspace_id='83100000-0000-4000-8000-000000000001'$$,'23514',null,'negative annual mileage is rejected');
select throws_ok($$update public.workspace_tax_estimates set annual_motorcycle_miles_hundredths=100000001 where workspace_id='83100000-0000-4000-8000-000000000001'$$,'23514',null,'unbounded annual mileage is rejected');
select throws_ok($$update public.workspace_tax_estimates set annual_motorcycle_miles_hundredths=null where workspace_id='83100000-0000-4000-8000-000000000001'$$,'23514',null,'partial annual review cannot be saved');
select is((select count(*) from public.mileage_entries where workspace_id='83100000-0000-4000-8000-000000000001'),0::bigint,'annual forecast creates no fake actual journeys');
select ok((select relrowsecurity from pg_class where oid='public.workspace_tax_estimates'::regclass),'existing tax-input RLS remains enabled');
select * from finish();
rollback;
