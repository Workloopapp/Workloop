begin;
set local search_path=public,extensions;
set constraints all immediate;
select no_plan();
select ok(not has_table_privilege('anon','public.record_attachments','SELECT'),'attachment metadata is not public');
select ok(not has_table_privilege('authenticated','public.record_attachments','UPDATE'),'attachment metadata is immutable');
select is((select public from storage.buckets where id='record-attachments'),false,'attachment bucket is private');
select is((select file_size_limit from storage.buckets where id='record-attachments'),10485760::bigint,'attachment bytes capped');
select is((select allowed_mime_types from storage.buckets where id='record-attachments'),array['application/pdf','image/jpeg','image/png','image/webp','text/plain'],'only supported files accepted');
select ok(not has_function_privilege('authenticated','app_private.guard_record_attachment_object_write()','EXECUTE'),'upload trigger is not an exposed RPC');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,confirmation_token,recovery_token) values
('91000000-0000-4000-8000-000000000001','authenticated','authenticated','attachment-a@example.invalid','',now(),now(),now(),'',''),
('92000000-0000-4000-8000-000000000002','authenticated','authenticated','attachment-b@example.invalid','',now(),now(),now(),'','');

-- Authenticated fixtures use real sessions, as production access requires.
insert into auth.sessions(id,user_id,created_at,updated_at) values
('91000000-0000-4000-8000-000000000101','91000000-0000-4000-8000-000000000001',now(),now()),
('92000000-0000-4000-8000-000000000102','92000000-0000-4000-8000-000000000002',now(),now());
insert into public.workspaces(id,name) values ('91100000-0000-4000-8000-000000000001','Attachment A'),('92200000-0000-4000-8000-000000000002','Attachment B');
insert into public.workspace_members(workspace_id,user_id) values
('91100000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001'),
('92200000-0000-4000-8000-000000000002','92000000-0000-4000-8000-000000000002');
insert into public.notes(id,workspace_id,title) values
('91300000-0000-4000-8000-000000000001','91100000-0000-4000-8000-000000000001','Local note'),
('92300000-0000-4000-8000-000000000002','92200000-0000-4000-8000-000000000002','Other note');
insert into public.contacts(id,workspace_id,name) values ('91600000-0000-4000-8000-000000000001','91100000-0000-4000-8000-000000000001','Client');
insert into public.appointments(id,workspace_id,title,start_time,end_time) values ('91700000-0000-4000-8000-000000000001','91100000-0000-4000-8000-000000000001','Booking','2026-09-12 10:00Z','2026-09-12 11:00Z');
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"91000000-0000-4000-8000-000000000101"}',true);
select lives_ok($q$insert into public.record_attachments(id,workspace_id,appointment_id,object_path,file_name,mime_type,size_bytes,content_hash) values
('91800000-0000-4000-8000-000000000001','91100000-0000-4000-8000-000000000001','91700000-0000-4000-8000-000000000001','91100000-0000-4000-8000-000000000001/91700000-0000-4000-8000-000000000001/91800000-0000-4000-8000-000000000001.jpg','before.jpg','image/jpeg',10,repeat('a',64));
delete from public.record_attachments where id='91800000-0000-4000-8000-000000000001';$q$,'booking supports reserving and clearing a pending photo');
select lives_ok($q$insert into public.record_attachments(id,workspace_id,contact_id,object_path,file_name,mime_type,size_bytes,content_hash) values
('91800000-0000-4000-8000-000000000002','91100000-0000-4000-8000-000000000001','91600000-0000-4000-8000-000000000001','91100000-0000-4000-8000-000000000001/91600000-0000-4000-8000-000000000001/91800000-0000-4000-8000-000000000002.txt','instructions.txt','text/plain',10,repeat('a',64));
delete from public.record_attachments where id='91800000-0000-4000-8000-000000000002';$q$,'client supports reserving and clearing a pending document');
select throws_ok($q$insert into public.record_attachments(id,workspace_id,note_id,contact_id,object_path,file_name,mime_type,size_bytes,content_hash) values
('91800000-0000-4000-8000-000000000003','91100000-0000-4000-8000-000000000001','91300000-0000-4000-8000-000000000001','91600000-0000-4000-8000-000000000001','91100000-0000-4000-8000-000000000001/91300000-0000-4000-8000-000000000001/91800000-0000-4000-8000-000000000003.txt','instructions.txt','text/plain',10,repeat('a',64))$q$,'23514',null,'attachment cannot have two target records');
select throws_ok($q$insert into public.record_attachments(id,workspace_id,note_id,object_path,file_name,mime_type,size_bytes,content_hash) values
('91800000-0000-4000-8000-000000000004','91100000-0000-4000-8000-000000000001','91300000-0000-4000-8000-000000000001','other-workspace/file.txt','instructions.txt','text/plain',10,repeat('a',64))$q$,'23514',null,'file path must match workspace record and attachment identity');
select throws_ok($q$insert into public.record_attachments(id,workspace_id,note_id,object_path,file_name,mime_type,size_bytes,content_hash) values
('91800000-0000-4000-8000-000000000005','91100000-0000-4000-8000-000000000001','91300000-0000-4000-8000-000000000001','91100000-0000-4000-8000-000000000001/91300000-0000-4000-8000-000000000001/91800000-0000-4000-8000-000000000005.txt','large.txt','text/plain',10485761,repeat('a',64))$q$,'23514',null,'metadata cannot reserve oversized files');
select lives_ok($q$insert into public.record_attachments(id,workspace_id,note_id,object_path,file_name,mime_type,size_bytes,content_hash) values
('91400000-0000-4000-8000-000000000001','91100000-0000-4000-8000-000000000001','91300000-0000-4000-8000-000000000001','91100000-0000-4000-8000-000000000001/91300000-0000-4000-8000-000000000001/91400000-0000-4000-8000-000000000001.pdf','work.pdf','application/pdf',10,repeat('a',64))$q$,'member reserves private note file');
select throws_ok($q$insert into public.record_attachments(id,workspace_id,note_id,object_path,file_name,mime_type,size_bytes,content_hash) values
('91400000-0000-4000-8000-000000000002','91100000-0000-4000-8000-000000000001','92300000-0000-4000-8000-000000000002','91100000-0000-4000-8000-000000000001/92300000-0000-4000-8000-000000000002/91400000-0000-4000-8000-000000000002.pdf','work.pdf','application/pdf',10,repeat('a',64))$q$,'23503',null,'cannot attach to another workspace note');
select throws_ok($q$insert into storage.objects(bucket_id,name) values ('record-attachments','91100000-0000-4000-8000-000000000001/missing.pdf')$q$,'42501',null,'upload must have a metadata reservation');
select lives_ok($q$insert into storage.objects(bucket_id,name) values ('record-attachments','91100000-0000-4000-8000-000000000001/91300000-0000-4000-8000-000000000001/91400000-0000-4000-8000-000000000001.pdf')$q$,'member may upload reserved file');
select throws_ok($q$delete from public.record_attachments where id='91400000-0000-4000-8000-000000000001'$q$,'23503',null,'metadata remains until file bytes are removed');
select throws_ok($q$delete from public.notes where id='91300000-0000-4000-8000-000000000001'$q$,'23503',null,'note deletion cannot orphan an attachment');
select throws_ok($q$update public.record_attachments set file_name='changed.pdf'$q$,'42501',null,'client cannot change attachment identity');
reset role;
set local role service_role;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select lives_ok($q$update storage.objects set metadata='{"size":10,"mimetype":"application/pdf"}' where bucket_id='record-attachments'$q$,'privileged Storage completion accepts existing reservation');
reset role;
-- Native Storage writes run as its table owner, which has no application-table
-- privileges. The private trigger must still enforce its lookup safely.
set local role supabase_storage_admin;
select lives_ok($q$update storage.objects set metadata='{"size":10,"mimetype":"application/pdf"}' where bucket_id='record-attachments'$q$,'native Storage completion does not need application-table grants');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","session_id":"92000000-0000-4000-8000-000000000102"}',true);
select is((select count(*) from public.record_attachments),0::bigint,'another workspace cannot see metadata');
select is((select count(*) from storage.objects where bucket_id='record-attachments'),0::bigint,'another workspace cannot see file bytes');
select throws_ok($q$insert into public.record_attachments(id,workspace_id,note_id,object_path,file_name,mime_type,size_bytes,content_hash) values
('91400000-0000-4000-8000-000000000003','91100000-0000-4000-8000-000000000001','91300000-0000-4000-8000-000000000001','91100000-0000-4000-8000-000000000001/91300000-0000-4000-8000-000000000001/91400000-0000-4000-8000-000000000003.pdf','work.pdf','application/pdf',10,repeat('a',64))$q$,'42501',null,'cross-workspace reservation denied');
reset role;
insert into auth.mfa_factors(id,user_id,factor_type,status) values ('91500000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','totp','verified');
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"91000000-0000-4000-8000-000000000101"}',true);
select is((select count(*) from public.record_attachments),0::bigint,'MFA-enrolled owner must step up for metadata');
select is((select count(*) from storage.objects where bucket_id='record-attachments'),0::bigint,'MFA-enrolled owner must step up for bytes');
select set_config('request.jwt.claims','{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2","session_id":"91000000-0000-4000-8000-000000000101"}',true);
select is((select count(*) from public.record_attachments),1::bigint,'stepped-up owner can read file metadata');
reset role;
insert into public.account_deletion_requests(workspace_id,user_id,requested_by_user_id,email,status) values
('91100000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','attachment-a@example.invalid','requested');
set local role authenticated;
select throws_ok($q$insert into public.record_attachments(id,workspace_id,note_id,object_path,file_name,mime_type,size_bytes,content_hash) values
('91400000-0000-4000-8000-000000000004','91100000-0000-4000-8000-000000000001','91300000-0000-4000-8000-000000000001','91100000-0000-4000-8000-000000000001/91300000-0000-4000-8000-000000000001/91400000-0000-4000-8000-000000000004.pdf','work.pdf','application/pdf',10,repeat('a',64))$q$,'42501',null,'no new reservation during account deletion');
reset role;
set local role service_role;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select throws_ok($q$update storage.objects set metadata='{}' where bucket_id='record-attachments'$q$,'42501',null,'in-flight completion denied after deletion begins');
reset role;
set local role supabase_storage_admin;
select throws_ok($q$update storage.objects set metadata='{}' where bucket_id='record-attachments'$q$,'42501',null,'native Storage completion also respects account deletion');
reset role;
select * from finish();
rollback;
