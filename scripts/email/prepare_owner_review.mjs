// Prepare synthetic owner-review messages only. Sending is a separate authorized step.
import fs from 'node:fs';
import path from 'node:path';
import {operationalAlertEmailContent} from '../../supabase/functions/_shared/workloop_automations.ts';
import {escapeEmail} from '../../supabase/functions/_shared/learning_email_content.ts';
const [catalog,out]=process.argv.slice(2);
if(!catalog||!out)throw Error('Provide catalogue and review directories');
fs.mkdirSync(out,{recursive:true});
const templates=JSON.parse(fs.readFileSync(path.join(catalog,'manifest.json'),'utf8')).templates;
const auth={
 confirmation:['Confirm your Workloop email','Sent to a new email/password signup to verify that they own the address. The account welcome follows successful verification.'],
 email_change:['Confirm your new Workloop email','Sent when someone requests an account email-address change. The secure Auth flow may require confirmation at both the old and new addresses.'],
 email_changed:['Your Workloop email address was changed','Security notice after an account email address has actually changed.'],
 identity_linked:['A sign-in method was added to Workloop','Security notice when a sign-in identity, such as Google or Apple, is linked to an account.'],
 identity_unlinked:['A sign-in method was removed from Workloop','Security notice when a linked sign-in identity is removed.'],
 invite:['You’re invited to Workloop','Sent if an administrator explicitly invites a person through Supabase Auth. This is a supported Auth template, not an automatic marketing campaign or a team feature.'],
 magic_link:['Your secure Workloop sign-in link','Sent if passwordless email sign-in is explicitly requested through Auth. Template availability does not mean the current app offers this sign-in button.'],
 mfa_enrolled:['A verification method was added to Workloop','Security notice when an extra verification method is enrolled.'],
 mfa_unenrolled:['A verification method was removed from Workloop','Security notice when an extra verification method is removed.'],
 password_changed:['Your Workloop password was changed','Security notice after the password changes, including a completed password reset.'],
 phone_changed:['Your Workloop phone number was changed','Security notice if the Auth account phone number changes. Editing an ordinary customer contact does not trigger this.'],
 reauthentication:['123456 is your Workloop security code','Sent when the Auth flow asks the user to verify their identity again before a sensitive change. This preview code cannot authenticate anyone.'],
 recovery:['Reset your Workloop password','Sent when a password reset is requested, such as through Forgot password.']
};
for(const t of templates){
 t.recipient=t.audience==='operations'?'Workloop operations/support staff only — never customers':t.audience==='customer'?'The customer associated with the verified booking or payment':'The Workloop account holder';
 if(t.id.startsWith('security-')){
  [t.subject,t.trigger]=auth[t.id.slice(9)];
 }else if(t.id==='account-welcome')t.trigger='Automatically queued the first time an account email is verified. This is a service welcome, separate from marketing preferences.';
 else if(t.id==='deletion_requested')t.trigger='Sent when an authenticated account-deletion request is accepted. It says the account has not yet been deleted.';
 else if(t.id==='account_deleted')t.trigger='Sent only after the protected account-deletion workflow completes.';
 else if(t.id.startsWith('customer-'))t.recipient='The customer associated with the booking request, booking or payment';
 else if(t.id==='booking-confirmed'){t.recipient='The customer who requested the booking';t.trigger='Sent when the business accepts a public booking request and confirmation is queued. This does not mean every manually entered booking automatically sends a confirmation.';}
 else if(t.id.startsWith('booking-reminder-')){t.recipient='The booked customer';t.trigger+='; only if this interval is enabled, the booking is still scheduled, its email is valid, and the customer has not stopped reminders. Changed or cancelled bookings are rechecked. New businesses default to 24 hours and 1 hour; existing businesses choose their timings.';}
 else if(t.id==='launch-list-welcome'){t.recipient='The website launch-list subscriber';t.trigger='Queued after an accepted website launch-list signup. Joining the launch list does not by itself enrol someone in the ongoing account-tip programme.';}
 else if(t.id==='welcome-series-confirmation'){t.recipient='Someone requesting the website welcome series';t.trigger='Sent after someone explicitly requests the nine-part series. They must confirm the email link before lessons begin.';}
 else if(/^welcome-(using|exploring)-/.test(t.id)){
  const [,stage,n]=/^welcome-(using|exploring)-(\d+)$/.exec(t.id);
  t.recipient=stage==='using'?'A confirmed welcome-series subscriber who selected “using Workloop”':'A confirmed welcome-series subscriber who selected “exploring Workloop”';
  t.trigger=`Lesson ${Number(n)+1}, due ${[0,2,4,7,10,14,18,23,28][Number(n)]} days after confirming the separately requested series. Only the subscriber's selected version is sent. The series ends after lesson 9; unsubscribe stops the remaining lessons.`;
 }else if(t.id.startsWith('onboarding-'))t.trigger+='; requires a verified eligible account, a recorded signup notice or explicit consent, and no unsubscribe. Pauses after 14 days without activity. Existing unconsented accounts are not automatically added. The new app signup/settings controls remain local pending the held TestFlight update.';
 else if(t.id.startsWith('business-tip-'))t.trigger='One topic from a 12-topic rotation, about weekly after 37 days of eligible account enrolment while the user has been active within the last 14 days. Topic selection follows elapsed enrolment week; missed weeks are not sent as a backlog. Requires active email preference and at least 7 days since the previous tip.';
 else if(t.id.startsWith('inactive-'))t.trigger+='; for eligible account-journey users only, subject to at least 7 days since the previous message. Each of the three nudges is limited to once per contact. The 60-day message has a one-week eligibility window, then messages pause. Returning to the app cancels queued inactivity nudges.';
 t.htmlBody=fs.readFileSync(path.join(catalog,t.html),'utf8');
 t.textBody=fs.readFileSync(path.join(catalog,t.text),'utf8');
}
for(const severity of ['warning','critical']){
 if(templates.some(t=>t.id==='operations-'+severity))continue;
 const content=operationalAlertEmailContent({alert_id:'sample',alert_key:'example-email-worker-health',category:'email_delivery',severity,message:'SAMPLE ONLY: A background email delivery job needs investigation. No real service incident is being reported.',first_seen_at:'2026-09-05T12:00:00Z'});
 templates.push({id:'operations-'+severity,category:'Internal operations',recipient:'Workloop operations/support staff only — never customers',trigger:`Generated when monitoring records an open ${severity} operational alert, such as repeated delivery failures or stuck account deletion. Sent to the configured operations inbox; this is not a customer campaign.`,subject:content.subject,htmlBody:content.html,textBody:content.plainText});
}
const notes=[
 'Prepared exception templates are not automatic triggers. They require the stated verified event or a reviewed support case before use. No speculative payment, refund or outage notice is sent.',
 'Customer emails provide direct business contact information rather than asking customers to reply. Business email/phone settings override the verified non-relay owner email fallback.',
 'These are synthetic review files. No email is sent by this generator. Previously requested review deliveries used ismaeel1993@outlook.com; live messages retain their normal Workloop sender addresses.',
 'All names, dates, codes and booking details are samples. Security and unsubscribe links in these previews cannot change a real account or subscription. No event described in a preview has actually occurred.',
 'The coloured preview note above each design is for your review only; customers will not see it.',
 `This set contains ${templates.length-2} user/customer variants plus two internal operations variants. The guide covers all ${templates.length}; prepared previews are only sent when requested.`,
 'The backend and website email changes are live. New in-app settings and default signup-enrolment controls are local: TestFlight upload is still on hold as requested.',
 'Booking reminders use the minute worker. Account tips/series use the 15-minute worker. Times are eligibility targets, not guaranteed delivery to the exact second; provider delays, retry windows and frequency caps can affect arrival.',
 'Welcome-series subscribers get either the using or exploring version, not both. Account users follow their separate onboarding journey. Weekly advice goes to business owners, not their booking customers.',
 'Marketing unsubscribe stops tips and inactivity emails. Essential account/security and booking confirmations are separate. Customers can separately stop reminder emails from a business.',
 'Stripe generates payment receipts in its own system; those are not Workloop-owned templates in this collection. Human support replies use the saved signature rather than an automated campaign template.'
];
const markdown='# Workloop email collection: triggers and recipients\n\n'+notes.map(n=>'- '+n).join('\n')+'\n\n'+templates.map((t,i)=>`## ${String(i+1).padStart(2,'0')}. ${t.subject}\n\nRecipient: ${t.recipient}\n\nTrigger: ${t.trigger}\n`).join('\n');
fs.writeFileSync(path.join(out,'TRIGGERS.md'),markdown);
const guideHtml=`<!doctype html><html><body style="font:16px/1.6 Arial;color:#443c32;background:#f5edd9;padding:24px"><h1>Workloop email collection</h1>${notes.map(n=>`<p>${escapeEmail(n)}</p>`).join('')}<h2>Every email and its trigger</h2>${templates.map((t,i)=>`<h3>${String(i+1).padStart(2,'0')}. ${escapeEmail(t.subject)}</h3><p><strong>Who:</strong> ${escapeEmail(t.recipient)}<br><strong>Trigger:</strong> ${escapeEmail(t.trigger)}</p>`).join('')}</body></html>`;
function message(subject,text,html){return {to:'ismaeel1993@outlook.com',subject,payload:{mime_type:'multipart/alternative',parts:[{mime_type:'text/plain',charset:'UTF-8',body:{content:text}},{mime_type:'text/html',charset:'UTF-8',body:{content:html}}]}};}
fs.writeFileSync(path.join(out,'message-00.json'),JSON.stringify(message(`[Workloop review] All ${templates.length} emails and what triggers them`,markdown,guideHtml)));
for(let i=0;i<templates.length;i++){
 const t=templates[i],number=String(i+1).padStart(2,'0');
 const annotation=`<div style="background:#c3d7e4;color:#443c32;border-bottom:2px solid #8d8070;padding:20px;font:14px/1.6 Arial"><strong>WORKLOOP PREVIEW ${number}/${templates.length} — SAMPLE ONLY</strong><br><strong>Normally sent to:</strong> ${escapeEmail(t.recipient)}<br><strong>Trigger:</strong> ${escapeEmail(t.trigger)}<br>This note is only for your review. Sample data; no real account action or subscription change.</div>`;
 const html=t.htmlBody.replace(/<body\b[^>]*>/i,match=>match+annotation);
 if(html===t.htmlBody)throw Error('Missing body tag: '+t.id);
 if(/{{|[?&]token=|[?&]token_hash=|supabase\.co\/auth\/v1\/verify/.test(html))throw Error('Unsafe placeholder/action: '+t.id);
 const text=`WORKLOOP PREVIEW ${number}/${templates.length} — SAMPLE ONLY\nNormally sent to: ${t.recipient}\nTrigger: ${t.trigger}\nNo real account action or subscription change.\n\n${t.textBody}`;
 fs.writeFileSync(path.join(out,`message-${number}.json`),JSON.stringify(message(`[Workloop preview ${number}/${templates.length}] ${t.subject}`,text,html)));
}
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({created_at:new Date().toISOString(),recipient:'ismaeel1993@outlook.com',count:templates.length,messages:templates.map(({htmlBody,textBody,...t},i)=>({...t,number:i+1})),notes},null,2));
console.log(JSON.stringify({templates:templates.length,messages:templates.length+1,guide:path.join(out,'TRIGGERS.md')}));
