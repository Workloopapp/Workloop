begin;
set local search_path = public, extensions;
select no_plan();
select is((select public from storage.buckets where id='business-logos'),true,'business logos are public branding');
select is((select file_size_limit from storage.buckets where id='business-logos'),2097152::bigint,'logo size is bounded');
select is((select allowed_mime_types from storage.buckets where id='business-logos'),array['image/png','image/jpeg'],'only static supported images');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,confirmation_token,recovery_token) values
('81000000-0000-4000-8000-000000000001','authenticated','authenticated','logo-a@example.invalid','',now(),now(),now(),'',''),
('82000000-0000-4000-8000-000000000002','authenticated','authenticated','logo-b@example.invalid','',now(),now(),now(),'','');

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('81000000-0000-4000-8000-000000000101','81000000-0000-4000-8000-000000000001',now(),now());
set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"81000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"81000000-0000-4000-8000-000000000101"}',true);
select lives_ok($q$insert into storage.objects(bucket_id,name) values ('business-logos','81000000-0000-4000-8000-000000000001/81100000-0000-4000-8000-000000000001.png')$q$,'onboarding user may upload own logo without workspace');
select throws_ok($q$insert into storage.objects(bucket_id,name) values ('business-logos','82000000-0000-4000-8000-000000000002/82100000-0000-4000-8000-000000000001.png')$q$,'42501',null,'cross-account upload is denied');
select throws_ok($q$insert into storage.objects(bucket_id,name) values ('business-logos','81000000-0000-4000-8000-000000000001/evil.svg')$q$,'42501',null,'unsupported path is denied');
update storage.objects set name='81000000-0000-4000-8000-000000000001/81100000-0000-4000-8000-000000000002.png' where bucket_id='business-logos';
select throws_ok($q$delete from storage.objects where bucket_id='business-logos'$q$,'42501',null,'direct object deletion is guarded by Storage');
reset role;
select is((select count(*) from storage.objects where bucket_id='business-logos' and name='81000000-0000-4000-8000-000000000001/81100000-0000-4000-8000-000000000001.png'),1::bigint,'issued logo cannot be overwritten or removed by client');
insert into auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at) values ('81400000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','totp','verified',now(),now());
set local role authenticated;
select throws_ok($q$insert into storage.objects(bucket_id,name) values ('business-logos','81000000-0000-4000-8000-000000000001/81100000-0000-4000-8000-000000000003.png')$q$,'42501',null,'MFA enrollment requires step up for upload');
select set_config('request.jwt.claims','{"sub":"81000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2","session_id":"81000000-0000-4000-8000-000000000101"}',true);
select lives_ok($q$insert into storage.objects(bucket_id,name) values ('business-logos','81000000-0000-4000-8000-000000000001/81100000-0000-4000-8000-000000000003.png')$q$,'stepped-up owner may upload');
reset role;
select * from finish();
rollback;
