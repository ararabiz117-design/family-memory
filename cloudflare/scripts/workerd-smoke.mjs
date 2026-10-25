import {Miniflare} from 'miniflare';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
const mf=new Miniflare({modules:true,scriptPath:'dist/index.js',compatibilityDate:'2026-07-30',compatibilityFlags:['nodejs_compat'],d1Databases:['DB'],r2Buckets:['PHOTOS'],bindings:{APP_ENV:'local',PUBLIC_API_URL:'http://localhost',APP_ORIGINS:'http://localhost',AUTH_RETURN_URLS:'http://localhost/',AUTH_SECRET:'runtime-test-only-secret-32-characters-long',AI_ENABLED:'false'}});
try {
 const db=await mf.getD1Database('DB');
 const schema=readFileSync('migrations/0001_cloudflare.sql','utf8');
 // D1 exec executes one statement per line. Keep trigger bodies as one statement.
 const statements=[];let current='';let trigger=false;
 for(const line of schema.split('\n')) {current+=line+'\n';if(/^CREATE TRIGGER/.test(line))trigger=true;if((trigger&&/^END;/.test(line))||(!trigger&&line.trimEnd().endsWith(';'))){statements.push(current);current='';trigger=false;}}
 for(const statement of statements)await db.prepare(statement).run();
 assert.equal((await mf.dispatchFetch('http://localhost/api/health')).status,200);
 assert.equal((await mf.dispatchFetch('http://localhost/api/family/state')).status,401);
 await db.batch([
  db.prepare('INSERT INTO users(id,google_sub,email,email_hash,name,created_at) VALUES(?,?,?,?,?,?)').bind('fixture-user','fixture-sub','fixture@example.invalid','test-hash','架空利用者',Date.now()),
  db.prepare('INSERT INTO families(id,name,created_at) VALUES(?,?,?)').bind('fixture-family','架空の家族',Date.now()),
  db.prepare("INSERT INTO members(family_id,user_id,role,status) VALUES(?,?,'owner','active')").bind('fixture-family','fixture-user')
 ]);
 const token=Buffer.from(webcrypto.getRandomValues(new Uint8Array(32))).toString('base64url');
 const hash=Buffer.from(await webcrypto.subtle.digest('SHA-256',new TextEncoder().encode(token))).toString('base64url');
 await db.prepare('INSERT INTO sessions(token_hash,user_id,expires_at,authenticated_at) VALUES(?,?,?,?)').bind(hash,'fixture-user',Date.now()+60000,Date.now()).run();
 const headers={authorization:`Bearer ${token}`,'content-type':'application/json'};
 const save=await mf.dispatchFetch('http://localhost/api/records/person/runtime-person',{method:'PUT',headers,body:JSON.stringify({data:{name:'架空人物',kind:'family',lifeStatus:'unknown'},expectedVersion:null})});
 assert.equal(save.status,200,await save.text());
 const state=await (await mf.dispatchFetch('http://localhost/api/family/state',{headers})).json();
 assert.equal(state.people[0].name,'架空人物');assert.equal(state.activities.length,1);
 const conflict=await mf.dispatchFetch('http://localhost/api/records/person/runtime-person',{method:'PUT',headers,body:JSON.stringify({data:{name:'不正上書き',kind:'family',lifeStatus:'unknown'},expectedVersion:null})});assert.equal(conflict.status,409);
 console.log('workerd + real local D1: authentication, family state, optimistic writes passed');
} finally {await mf.dispose();}
