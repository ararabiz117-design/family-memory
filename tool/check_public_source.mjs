import {execFileSync} from 'node:child_process';
import {readFileSync,statSync} from 'node:fs';
const files=execFileSync('git',['ls-files','--cached','-z'],{encoding:'utf8'}).split('\0').filter(Boolean);
const banned=/(?:^|\/)(?:node_modules|\.wrangler|\.dart_tool|build|release)(?:\/|$)|(?:\.dev\.vars(?!\.example)|\.env(?!\.example)|key\.properties|local\.properties|\.(?:jks|keystore|p12|mobileprovision|aab|apk|sqlite|db))$/;
const secret=/(?:-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|github_pat_[A-Za-z0-9_]{30,}|gh[pousr]_[A-Za-z0-9]{30,}|GOCSPX-[A-Za-z0-9_-]{20,}|sb_secret_[A-Za-z0-9_-]{20,}|eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,})/;
const failures=[];
for(const file of files){if(banned.test(file))failures.push(file+': private artifact');if(statSync(file).size>10*1024*1024)failures.push(file+': oversized artifact');if(!/\.(png|jpg|jpeg|ico|webp|gif|ttf|woff2?|jar)$/i.test(file)&&secret.test(readFileSync(file,'utf8')))failures.push(file+': possible credential');}
if(failures.length){console.error(failures.join('\n'));process.exit(1);}console.log(`Public source scan passed: ${files.length} staged files. No credentials or local data artifacts found by this scan.`);
