// Synchronise only the shared legal footer in local Supabase Auth HTML.
// Does not access provider settings or send email. Node >=22 required.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {withWorkloopOperatorHtml} from '../../supabase/functions/_shared/workloop_operator_email.ts';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const check=process.argv.includes('--check');
let count=0;
for(const file of fs.readdirSync(path.join(root,'supabase/templates')).filter(name=>name.endsWith('.html'))){
  const target=path.join(root,'supabase/templates',file);
  const original=fs.readFileSync(target,'utf8');
  const withoutFooter=original.replace(/<!-- workloop-operator:start -->[\s\S]*?<!-- workloop-operator:end -->/g,'');
  const next=withWorkloopOperatorHtml(withoutFooter);
  if(next!==original){
    if(check)throw new Error(`Operator footer is missing or stale: ${file}`);
    fs.writeFileSync(target,next);
  }
  count++;
}
console.log(JSON.stringify({templates:count,mode:check?'checked':'synchronised',sent:0}));
