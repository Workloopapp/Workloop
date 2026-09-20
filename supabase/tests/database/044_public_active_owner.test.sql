begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select plan(12);
insert into auth.users(id,email,email_confirmed_at) values
 ('a4400000-0000-4000-8000-000000000001','public-active@example.invalid',now()),
 ('a4400000-0000-4000-8000-000000000002','public-unverified@example.invalid',null);
insert into public.workspaces(id,name) values
 ('a4400000-0000-4000-8000-000000000021','Public owner'),
 ('a4400000-0000-4000-8000-000000000022','Orphan'),
 ('a4400000-0000-4000-8000-000000000023','Unverified');
insert into public.workspace_members(workspace_id,user_id) values
 ('a4400000-0000-4000-8000-000000000021','a4400000-0000-4000-8000-000000000001'),
 ('a4400000-0000-4000-8000-000000000023','a4400000-0000-4000-8000-000000000002');
insert into public.business_profiles(workspace_id,handle) values
 ('a4400000-0000-4000-8000-000000000021','active-owner'),
 ('a4400000-0000-4000-8000-000000000022','orphan-owner'),
 ('a4400000-0000-4000-8000-000000000023','unverified-owner');
select ok(not has_function_privilege('authenticated','public.is_public_profile_active(text)','EXECUTE'),'publication lookup only callable by trusted edge service');
set local role service_role;
select ok(public.is_public_profile_active('active-owner'),'verified owner can publish while signed out');
select ok(not public.is_public_profile_active('orphan-owner'),'ownerless profile remains unavailable');
select ok(not public.is_public_profile_active('unverified-owner'),'unverified owner cannot publish');
select lives_ok($$insert into public.booking_requests(workspace_id,name,phone) values('a4400000-0000-4000-8000-000000000021','Fixture customer','+447700900001')$$,'active public booking still works');
reset role;
update auth.users set banned_until=now()+interval '1 day' where id='a4400000-0000-4000-8000-000000000001';
set local role service_role;
select ok(not public.is_public_profile_active('active-owner'),'Auth ban removes profile from public availability');
select throws_ok($$insert into public.booking_requests(workspace_id,name,phone) values('a4400000-0000-4000-8000-000000000021','Fixture customer','+447700900002')$$,'42501','Public profile is not available','banned owner final booking insertion blocked despite service role');
reset role;
update auth.users set banned_until=null where id='a4400000-0000-4000-8000-000000000001';
insert into public.account_deletion_requests(workspace_id,user_id,requested_by_user_id,email,status) values
 ('a4400000-0000-4000-8000-000000000021','a4400000-0000-4000-8000-000000000001','a4400000-0000-4000-8000-000000000001','public-active@example.invalid','requested');
set local role service_role;
select ok(not public.is_public_profile_active('active-owner'),'pending deletion closes publication before worker cleanup');
select throws_ok($$insert into public.booking_requests(workspace_id,name,phone) values('a4400000-0000-4000-8000-000000000021','Fixture customer','+447700900003')$$,'42501','Public profile is not available','deletion pending final booking insertion blocked');
reset role;
select is((select count(*)::int from public.booking_requests),1,'only active-owner request was recorded');
select is((select count(*)::int from public.business_profiles),3,'privacy guard preserves all private profile records');
select is((select count(*)::int from public.workspaces),3,'guard does not clean up orphan or business data');
select * from finish();
rollback;
