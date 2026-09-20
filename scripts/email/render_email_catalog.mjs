// Run with Node >=22 --experimental-strip-types. No provider calls or real data.
import {customerEventEmail} from '../../supabase/functions/_shared/customer_event_email.ts';
import {exceptionEmail,exceptionEmailCases} from '../../supabase/functions/_shared/exception_email.ts';
import {ownerContextEmail} from '../../supabase/functions/_shared/owner_context_email.ts';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {accountJourneyEmail} from '../../supabase/functions/_shared/account_journey_email.ts';
import {bookingReminderEmail} from '../../supabase/functions/_shared/booking_reminder_email.ts';
import {bookingConfirmationEmailContent} from '../../supabase/functions/_shared/booking_confirmation_email.ts';
import {accountWelcomeEmailContent} from '../../supabase/functions/_shared/account_welcome_email.ts';
import {accountDeletionEmailContent} from '../../supabase/functions/_shared/account_deletion_email.ts';
import {waitlistWelcomeEmailContent} from '../../supabase/functions/_shared/waitlist_welcome_email.ts';
import {learningEmail,confirmationEmail,escapeEmail} from '../../supabase/functions/_shared/learning_email_content.ts';
import {operationalAlertEmailContent} from '../../supabase/functions/_shared/workloop_automations.ts';
import {WORKLOOP_OPERATOR_EFFECTIVE_DATE} from '../../supabase/functions/_shared/workloop_operator_email.ts';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const out=process.argv[2];if(!out)throw new Error('Provide an output directory');fs.mkdirSync(out,{recursive:true});
const manifest=[];
// Auth config accepts HTML. This readable text is a local review companion,
// not a claim about the provider's delivered MIME conversion.
function authPreviewText(html){
 return html.replace(/<head[\s\S]*?<\/head>/i,'').replace(/<style[\s\S]*?<\/style>/gi,'').replace(/<!--[^]*?-->/g,'').replace(/<a\b[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi,'$2 ($1)').replace(/<br\s*\/?\s*>/gi,'\n').replace(/<\/(?:p|h[1-6]|div|tr|table)>/gi,'\n\n').replace(/<[^>]+>/g,'').replace(/&(?:amp|lt|gt|quot|#39|nbsp);/g,x=>({'&amp;':'&','&lt;':'<','&gt;':'>','&quot;':'"','&#39;':"'",'&nbsp;':' '}[x])).replace(/\n{3,}/g,'\n\n').trim();
}
function save(id,category,trigger,content){fs.writeFileSync(path.join(out,id+'.html'),content.html);fs.writeFileSync(path.join(out,id+'.txt'),content.text??content.plainText??'See the HTML template.');manifest.push({id,category,trigger,subject:content.subject,html:id+'.html',text:id+'.txt'});}
const unsubscribeUrl='https://workloop.uk/help/email-preferences';
const payload={business_contact:{email:'hello@alex.example.test',phone:'+44 7700 900123',website:'https://workloop.uk/alex-services'},reply_email:'alex@example.test',business_name:'Alex Services',customer_name:'Jamie',booking_title:'Window clean',start_time:'2026-09-10T09:30:00Z',end_time:'2026-09-10T10:15:00Z',timezone:'Europe/London',location:'12 Example Road'};
for(const file of fs.readdirSync(path.join(root,'supabase/templates')).filter(x=>x.endsWith('.html'))){
 const html=fs.readFileSync(path.join(root,'supabase/templates',file),'utf8').replace(/{{\s*\.ConfirmationURL\s*}}/g,'https://workloop.uk/help/welcome').replace(/{{\s*\.Token\s*}}/g,'123456').replace(/{{\s*\.SiteURL\s*}}/g,'https://workloop.uk').replace(/{{\s*\.[\w]+\s*}}/g,'Example');
 save('security-'+file.replace('.html',''),'Account & security','Supabase Auth event',{subject:file.replace('.html','').replaceAll('_',' '),html,text:authPreviewText(html)});
}
save('account-welcome','Account & security','First verified account',accountWelcomeEmailContent());
for(const event of ['deletion_requested','account_deleted'])save(event,'Account & security',event,accountDeletionEmailContent(event));
save('booking-confirmed','Customer bookings','Accepted booking request',bookingConfirmationEmailContent({payload}));
for(const minutes of [1440,120,60])save('booking-reminder-'+minutes,'Customer bookings',`${minutes} minutes before a scheduled booking; business and customer preferences apply`,bookingReminderEmail({...payload,minutes_before:minutes},unsubscribeUrl));
save('launch-list-welcome','Launch list','Requested launch signup',waitlistWelcomeEmailContent());
save('welcome-series-confirmation','Requested welcome series','Visitor requests the finite series',confirmationEmail('https://workloop.uk/help/welcome'));
for(const stage of ['using','exploring'])for(let step=0;step<9;step++)save(`welcome-${stage}-${step}`,'Requested welcome series',`Confirmed subscription; lesson ${step+1}`,learningEmail({step,stage,unsubscribeUrl}));
for(let step=10;step<=18;step++)save(`onboarding-${step-9}`,'Automatic account journey',`Day ${[2,4,6,9,12,16,20,25,30][step-10]} after eligible enrolment`,accountJourneyEmail({step,unsubscribeUrl}));
for(let n=0;n<12;n++)save(`business-tip-${n+1}`,'Weekly business tips','Weekly after onboarding while active; unsubscribe and delivery caps apply',accountJourneyEmail({step:1005+n,unsubscribeUrl}));
for(let n=0;n<3;n++)save(`inactive-${[14,30,60][n]}`,'Return to Workloop',`${[14,30,60][n]} days without recent activity; cancel on return`,accountJourneyEmail({step:100+n,unsubscribeUrl}));
for(const [event,trigger] of Object.entries({request_received:'A new pending booking request with a valid customer email; explicitly not a booking confirmation',request_declined:'The business declines a booking request',booking_changed:'A future scheduled booking changes time, service, title, location or price',booking_cancelled:'A future booking is marked cancelled; this does not confirm a refund',payment_request:'The business reviews the saved customer email and deliberately selects Send email for a current unpaid Stripe payment link'})) save('customer-'+event,'Customer bookings & payments',trigger,customerEventEmail(event,{...payload,price:45,invoice_number:'PAY-001',amount_minor:4500,checkout_url:'https://checkout.stripe.com/c/pay/example'}));
for(const setup_step of ['finish_workspace','add_service','add_client','add_booking'])save('setup-'+setup_step,'Conditional setup help','Replaces the day-2 or day-6 onboarding email only when this is the next unfinished setup step; no extra send',ownerContextEmail({step:10,unsubscribeUrl,context:{setup_step}}));
save('weekly-business-summary','Weekly business summary','Included in the existing weekly advice email for an eligible active owner; latest business counts, no extra email',ownerContextEmail({step:1005,unsubscribeUrl,context:{business_name:'Alex Services',summary:{completed_bookings:7,upcoming_bookings:4,waiting_requests:2,overdue_tasks:1}}}));
for(const [id,audience,,,rule] of exceptionEmailCases){save('exception-'+id,'Prepared exception templates — reviewed event required','PREPARED, NOT AUTOMATIC: '+rule,exceptionEmail(id,{...payload,reference:'EXAMPLE-001',details:'Sample only: replace this section with the verified booking, amount, outcome or next step before sending.'}));manifest.at(-1).audience=audience;manifest.at(-1).delivery='prepared';}
for(const severity of ['warning','critical']){
 save('operations-'+severity,'Internal operations',`Monitoring records an open ${severity} operational alert; configured operations inbox only`,operationalAlertEmailContent({alert_id:'sample',alert_key:'example-email-worker-health',category:'email_delivery',severity,message:'SAMPLE ONLY: A background email delivery job needs investigation. No real incident is being reported.',first_seen_at:'2026-09-06T12:00:00Z'}));
 manifest.at(-1).audience='operations';
}
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({generated_at:new Date().toISOString(),operator_effective_date:WORKLOOP_OPERATOR_EFFECTIVE_DATE,templates:manifest,notes:['Synthetic examples only. Preview links do not change subscriptions.','Stripe generates payment receipts; its processor-managed layout is separate.','Support correspondence uses the configured Workloop signature.']},null,2));
fs.writeFileSync(path.join(out,'index.html'),`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Workloop email collection</title><style>body{margin:0;background:#f5edd9;color:#443c32;font:16px/1.5 Arial}header{padding:28px;background:#c3d7e4;border-bottom:1px solid #8d8070}main{padding:24px;max-width:1100px;margin:auto}h1{margin:0;font-size:36px}details{border:1px solid #8d8070;background:#fbf7ed;margin:12px 0;border-radius:6px}summary{cursor:pointer;padding:18px;font-weight:bold}p{margin:12px 18px}a{color:#286280}iframe{display:block;width:100%;height:820px;border:0;background:white}</style><header><h1>workloop · email collection</h1><p>${manifest.length} professional templates. Synthetic examples; no email is sent from this page.</p></header><main>${[...new Set(manifest.map(m=>m.category))].map(category=>`<h2>${category}</h2>${manifest.filter(m=>m.category===category).map(m=>`<details><summary>${escapeEmail(m.subject)}</summary><p>${escapeEmail(m.trigger)} · <a href="${m.html}" target="_blank">Open HTML</a> · <a href="${m.text}">Plain text</a></p><iframe loading="lazy" title="${escapeEmail(m.subject)}" src="${m.html}" sandbox=""></iframe></details>`).join('')}`).join('')}</main></html>`);
console.log(JSON.stringify({templates:manifest.length,path:path.resolve(out,'index.html')}));
