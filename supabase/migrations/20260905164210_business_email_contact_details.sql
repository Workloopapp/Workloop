-- Customer-facing business contact details, independent of marketing preferences.
-- Existing RLS/membership/MFA policies on workspace_settings remain in force.
alter table public.workspace_settings
 add column customer_contact_email text,
 add column customer_contact_phone text,
 add constraint customer_contact_email_valid check(customer_contact_email is null or
  (length(customer_contact_email)<=254 and customer_contact_email=lower(btrim(customer_contact_email)) and customer_contact_email ~ '^[^[:space:]@<>]+@[^[:space:]@<>]+\.[^[:space:]@<>]+$')),
 add constraint customer_contact_phone_valid check(customer_contact_phone is null or
  (length(customer_contact_phone) between 7 and 40 and customer_contact_phone ~ '^\+?[0-9 ()-]+$' and length(regexp_replace(customer_contact_phone,'[^0-9]','','g'))>=7));
comment on column public.workspace_settings.customer_contact_email is 'Customer-facing email printed in business booking and payment emails; null falls back to a verified non-relay owner email.';
comment on column public.workspace_settings.customer_contact_phone is 'Optional business phone printed in booking and payment emails. Never inferred from private Auth phone numbers.';

-- Reminder details are composed from the appointment; only the contact snapshot
-- needs storage to keep provider retries stable.
alter table app_private.booking_reminder_outbox add column business_contact jsonb
 check(business_contact is null or jsonb_typeof(business_contact)='object');

create function app_private.business_email_contact(wid uuid) returns jsonb
language sql security definer set search_path='' as $$
 select jsonb_strip_nulls(jsonb_build_object('name',w.name,
  'email',coalesce(s.customer_contact_email,(select lower(u.email::text) from public.workspace_members m join auth.users u on u.id=m.user_id
   where m.workspace_id=wid and u.email_confirmed_at is not null and u.deleted_at is null
   and lower(u.email) not like '%@privaterelay.appleid.com' order by m.user_id limit 1)),
  'phone',s.customer_contact_phone,
  'website',case when b.handle ~ '^[a-z0-9][a-z0-9-]{1,78}[a-z0-9]$' then 'https://workloop.uk/'||b.handle end,
  'instagram',b.social_instagram,'facebook',b.social_facebook,'tiktok',b.social_tiktok))
 from public.workspaces w left join public.workspace_settings s on s.workspace_id=w.id
 left join public.business_profiles b on b.workspace_id=w.id
 where w.id=wid and exists(select 1 from public.workspace_members where workspace_id=wid);
$$;
revoke all on function app_private.business_email_contact(uuid) from public,anon,authenticated,service_role;

-- Resolve by an existing queue item, not a caller-supplied workspace. Freeze contact
-- details on first composition so retries retain an identical Resend payload.
create function app_private.customer_email_contact(p_kind text,p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare wid uuid; p jsonb; contact jsonb;
begin
 if p_kind='event' then select workspace_id,payload into wid,p from app_private.customer_event_emails where id=p_id for update;
 elsif p_kind='reminder' then select a.workspace_id,case when q.business_contact is null then '{}'::jsonb else jsonb_build_object('business_contact',q.business_contact) end into wid,p from app_private.booking_reminder_outbox q join public.appointments a on a.id=q.appointment_id where q.id=p_id for update of q;
 elsif p_kind='confirmation' then select workspace_id,payload into wid,p from app_private.transactional_email_outbox where id=p_id for update;
 else raise exception 'Unknown email kind'; end if;
 if wid is null then raise exception 'Email intent unavailable'; end if;
 if p ? 'business_contact' then return p->'business_contact'; end if;
 contact:=coalesce(app_private.business_email_contact(wid),'{}'::jsonb);
 if p_kind='event' then update app_private.customer_event_emails set payload=payload||jsonb_build_object('business_contact',contact) where id=p_id;
 elsif p_kind='reminder' then update app_private.booking_reminder_outbox set business_contact=contact where id=p_id;
 else update app_private.transactional_email_outbox set payload=payload||jsonb_build_object('business_contact',contact) where id=p_id; end if;
 return contact;
end; $$;
revoke all on function app_private.customer_email_contact(text,uuid) from public,anon,authenticated;
grant execute on function app_private.customer_email_contact(text,uuid) to service_role;
create function public.customer_email_contact(p_kind text,p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select app_private.customer_email_contact(p_kind,p_id)$$;
revoke all on function public.customer_email_contact(text,uuid) from public,anon,authenticated;
grant execute on function public.customer_email_contact(text,uuid) to service_role;
