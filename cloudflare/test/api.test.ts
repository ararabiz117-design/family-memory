import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import {URL as NodeURL,fileURLToPath} from 'node:url';
import {createApp,cleanup} from '../src/index.ts';
import {authenticate} from '../src/auth.ts';
import {ApiError,emailHash,randomToken,sha,type Env,type Identity} from '../src/types.ts';

function fixture() {
 const sql=new DatabaseSync(':memory:');sql.exec(readFileSync(fileURLToPath(new NodeURL('../migrations/0001_cloudflare.sql',import.meta.url)),'utf8'));
 const DB:any={prepare(query:string){let args:any[]=[];return {bind(...values:any[]){args=values;return this;},async first(){return sql.prepare(query).get(...args)||null;},async all(){return {success:true,results:sql.prepare(query).all(...args)};},async run(){const result=sql.prepare(query).run(...args);return {success:true,meta:{changes:Number(result.changes)}};}};},async batch(statements:any[]){sql.exec('BEGIN');try{const result=[];for(const s of statements)result.push(await s.run());sql.exec('COMMIT');return result;}catch(e){sql.exec('ROLLBACK');throw e;}}};
 const objects=new Map<string,Uint8Array>();const PHOTOS:any={async put(k:string,v:Uint8Array){objects.set(k,v);},async get(k:string){const b=objects.get(k);return b?{body:new ReadableStream({start(c){c.enqueue(b);c.close();}})}:null;},async delete(keys:string|string[]){for(const key of Array.isArray(keys)?keys:[keys])objects.delete(key);},async list(){return {objects:[],truncated:false};}};
 const env={DB,PHOTOS,APP_ENV:'local',PUBLIC_API_URL:'http://127.0.0.1:8787',APP_ORIGINS:'http://127.0.0.1:8765',AUTH_RETURN_URLS:'http://127.0.0.1:8765/,familymemory://login-callback/',AUTH_SECRET:'test-only-secret-with-at-least-32-characters',GOOGLE_CLIENT_ID:'test.apps.googleusercontent.com',GOOGLE_CLIENT_SECRET:'local-test-value',AI_ENABLED:'false'} as Env;
 const users=new Map<string,Identity>();
 const app=createApp({authenticate:async(req)=>{const user=users.get(req.headers.get('x-fixture-user')||'');if(!user)throw new ApiError(401,'AUTH_REQUIRED');return user;}});
 async function seed(uid:string,fid:string,role:string) {
  const email=`${uid}@example.invalid`;const user={id:uid,name:uid,email,email_hash:await emailHash(env,email),authenticated_at:Date.now()};users.set(uid,user);
  sql.prepare('INSERT INTO users(id,google_sub,email,email_hash,name,created_at) VALUES(?,?,?,?,?,?)').run(uid,uid,email,user.email_hash,uid,Date.now());
  sql.prepare('INSERT INTO families(id,name,created_at) VALUES(?,?,?) ON CONFLICT(id) DO NOTHING').run(fid,fid,Date.now());
  sql.prepare("INSERT INTO members(family_id,user_id,role,status) VALUES(?,?,?,'active')").run(fid,uid,role);return user;
 }
 async function req(path:string,uid='owner',method='GET',data?:any) {
  return app(new Request('http://127.0.0.1:8787'+path,{method,headers:{'x-fixture-user':uid,...(data===undefined?{}:{'content-type':'application/json'})},...(data===undefined?{}:{body:JSON.stringify(data)})}),env);
 }
 return {sql,env,users,app,seed,req,objects};
}
const person=(name='架空人物')=>({name,kana:'',relationship:'',kind:'family',lifeStatus:'living',consentConfirmed:true,placeIds:[]});
const event=(pid='p')=>({title:'架空法要',type:'法事・法要',subjectPersonId:pid,status:'planned',date:'2026-11-01',participants:[],expenses:[],notificationDays:[7],isCandidate:false});

test('family data, exports and writes reject anonymous/viewer/other-family access',async()=>{
 const f=fixture();await f.seed('owner','fa','owner');await f.seed('viewer','fa','viewer');await f.seed('other','fb','owner');
 assert.equal((await f.req('/api/family/state','')).status,401);
 assert.equal((await f.req('/api/records/person/p','owner','PUT',{data:person(),expectedVersion:null})).status,200);
 assert.equal((await f.req('/api/records/person/q','viewer','PUT',{data:person(),expectedVersion:null})).status,403);
 assert.equal((await (await f.req('/api/family/state','other')).json() as any).people.length,0);
 assert.equal((await f.req('/api/records/event/e','other','PUT',{data:event('p'),expectedVersion:null})).status,400);
 assert.equal((await f.req('/api/export?format=json','viewer')).status,403);
 assert.equal((await f.req('/api/members/owner','other','PUT',{role:'viewer'})).status,404);
 f.sql.close();
});
test('optimistic writes reject stale versions and do not silently overwrite',async()=>{
 const f=fixture();await f.seed('owner','fa','owner');
 await f.req('/api/records/person/p','owner','PUT',{data:person('初期'),expectedVersion:null});
 assert.equal((await f.req('/api/records/person/p','owner','PUT',{data:person('更新'),expectedVersion:1})).status,200);
 const conflict=await f.req('/api/records/person/p','owner','PUT',{data:person('上書き'),expectedVersion:1});assert.equal(conflict.status,409);
 const state=await (await f.req('/api/family/state')).json() as any;assert.equal(state.people[0].name,'更新');assert.equal(state.people[0].version,2);assert.equal(state.activities.length,2);
 f.sql.close();
});
test('parent cycles rejected at SQLite layer even after concurrent prevalidation',async()=>{
 const f=fixture();await f.seed('owner','fa','owner');
 for(const id of ['p','q','r'])await f.req('/api/records/person/'+id,'owner','PUT',{data:person(),expectedVersion:null});
 for(const [rid,from,to] of [['a','p','q'],['b','q','r']])assert.equal((await f.req('/api/records/relationship/'+rid,'owner','PUT',{data:{fromPersonId:from,toPersonId:to,kind:'parentChild'},expectedVersion:null})).status,200);
 const cycle=await f.req('/api/records/relationship/c','owner','PUT',{data:{fromPersonId:'r',toPersonId:'p',kind:'adoptedParentChild'},expectedVersion:null});assert.equal(cycle.status,409);assert.equal((await cycle.json() as any).error,'PARENT_CYCLE');f.sql.close();
});
test('invites enforce recipient, one-use, approval, cancellation and expiry',async()=>{
 const f=fixture();await f.seed('owner','fa','owner');await f.seed('guest','fb','owner');f.sql.prepare('UPDATE families SET deleted_at=? WHERE id=?').run(Date.now(),'fb');f.sql.prepare("UPDATE members SET status='suspended' WHERE user_id='guest'").run();
 const invite=await (await f.req('/api/invitations','owner','POST',{email:'guest@example.invalid',role:'editor'})).json() as any;
 assert.ok(invite.shortCode);assert.equal((await f.req('/api/invitations/accept','owner','POST',{shortCode:invite.shortCode})).status,409);
 assert.equal((await f.req('/api/invitations/accept','guest','POST',{shortCode:invite.shortCode})).status,200);
 assert.equal((await f.req('/api/family/state','guest')).status,403);
 assert.equal((await f.req('/api/invitations/accept','guest','POST',{shortCode:invite.shortCode})).status,400);
 assert.equal((await f.req(`/api/invitations/${invite.id}/approve`,'owner','POST',{})).status,200);
 assert.equal((await f.req('/api/family/state','guest')).status,200);
 const expired=await (await f.req('/api/invitations','owner','POST',{email:'nobody@example.invalid',role:'viewer'})).json() as any;
 f.sql.prepare('UPDATE invitations SET expires_at=0 WHERE id=?').run(expired.id);
 assert.equal((await f.req(`/api/invitations/${expired.id}/revoke`,'owner','POST',{})).status,200);f.sql.close();
});
test('last owner protection and recent Google reauthentication gate deletion',async()=>{
 const f=fixture();const user=await f.seed('owner','fa','owner');
 assert.equal((await f.req('/api/members/owner','owner','PUT',{role:'viewer'})).status,409);
 assert.equal((await f.req('/api/deletions/account','owner','POST',{})).status,409);
 user.authenticated_at=Date.now()-11*60000;
 assert.equal((await f.req('/api/deletions/family','owner','POST',{})).status,403);
 user.authenticated_at=Date.now();assert.equal((await f.req('/api/deletions/family','owner','POST',{})).status,200);
 assert.equal((await f.req('/api/family/state','owner')).status,403);
 f.sql.prepare('UPDATE deletion_jobs SET execute_after=0').run();await cleanup(f.env);assert.equal(f.sql.prepare('SELECT count(*) AS n FROM families').get()!.n,0);f.sql.close();
});
test('OAuth PKCE ticket one-use, expiry, cookie session, revocation and origin protection',async()=>{
 const f=fixture();await f.seed('owner','fa','owner');const verifier=randomToken(),ticket=randomToken();
 f.sql.prepare('INSERT INTO login_tickets(ticket_hash,user_id,challenge,expires_at) VALUES(?,?,?,?)').run(await sha(ticket),'owner',await sha(verifier),Date.now()+60000);
 const handler=createApp();
 const exchange=(v:string)=>handler(new Request('http://127.0.0.1:8787/api/auth/exchange',{method:'POST',headers:{'content-type':'application/json',origin:'http://127.0.0.1:8765'},body:JSON.stringify({ticket,verifier:v,client:'web'})}),f.env);
 assert.equal((await exchange(randomToken())).status,401);const result=await exchange(verifier);assert.equal(result.status,200);const cookie=result.headers.get('set-cookie')!;assert.ok(cookie.includes('HttpOnly'));assert.equal((await exchange(verifier)).status,401);
 const me=await handler(new Request('http://127.0.0.1:8787/api/me',{headers:{cookie}}),f.env);assert.equal(me.status,200);
 const denied=await handler(new Request('http://127.0.0.1:8787/api/profile',{method:'PUT',headers:{cookie,origin:'https://evil.example'},body:'{"name":"x"}'}),f.env);assert.equal(denied.status,403);
 assert.equal((await handler(new Request('http://127.0.0.1:8787/api/auth/logout',{method:'POST',headers:{cookie,origin:'http://127.0.0.1:8765'}}),f.env)).status,200);
 assert.equal((await handler(new Request('http://127.0.0.1:8787/api/me',{headers:{cookie}}),f.env)).status,401);f.sql.close();
});
test('OAuth start accepts exact redirects only and stores no plaintext state',async()=>{
 const f=fixture();const handler=createApp();const req=(returnTo:string)=>handler(new Request('http://127.0.0.1:8787/api/auth/start',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({returnTo,challenge:'a'.repeat(43)})}),f.env);
 assert.equal((await req('https://evil.example/')).status,400);const response=await req('familymemory://login-callback/');assert.equal(response.status,200);const url=(await response.json() as any).url;const token=new URL(url).searchParams.get('flow')!;assert.notEqual(f.sql.prepare('SELECT state_hash FROM auth_flows').get()!.state_hash,token);f.sql.close();
});
test('R2 links reject cross-family, tampering and soft-deleted image access',async()=>{
 const f=fixture();await f.seed('owner','fa','owner');await f.seed('other','fb','owner');await f.req('/api/records/person/p','owner','PUT',{data:person(),expectedVersion:null});
 const photo='a';f.objects.set('private/key',new Uint8Array([1]));f.sql.prepare('INSERT INTO attachments(id,family_id,target_type,target_id,storage_path,mime_type,byte_size,width,height,sha256,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)').run(photo,'fa','person','p','private/key','image/png',1,1,1,'00',Date.now());
 assert.equal((await f.req('/api/attachments/a/url','other')).status,404);const link=(await (await f.req('/api/attachments/a/url')).json() as any).url;
 assert.equal((await f.app(new Request(link),f.env)).status,200);assert.equal((await f.app(new Request(link+'&sig=x'),f.env)).status,200);const tampered=new URL(link);tampered.searchParams.set('sig','x');assert.equal((await f.app(new Request(tampered),f.env)).status,403);
 assert.equal((await f.req('/api/attachments/a','owner','DELETE',{expectedVersion:1})).status,200);assert.equal((await f.app(new Request(link),f.env)).status,403);f.sql.close();
});

test('revoked pending invitation cannot be approved and approved invitation cannot be revoked',async()=>{
 const f=fixture();await f.seed('owner','fa','owner');await f.seed('guest','fb','owner');
 f.sql.prepare('UPDATE families SET deleted_at=? WHERE id=?').run(Date.now(),'fb');
 f.sql.prepare("UPDATE members SET status='suspended' WHERE user_id='guest'").run();
 const invite=await (await f.req('/api/invitations','owner','POST',{email:'guest@example.invalid',role:'editor'})).json() as any;
 assert.equal((await f.req('/api/invitations/accept','guest','POST',{shortCode:invite.shortCode})).status,200);
 assert.equal((await f.req(`/api/invitations/${invite.id}/revoke`,'owner','POST',{})).status,200);
 assert.notEqual((await f.req(`/api/invitations/${invite.id}/approve`,'owner','POST',{})).status,200);
 assert.equal((await f.req('/api/family/state','guest')).status,403);
 const next=await (await f.req('/api/invitations','owner','POST',{email:'guest@example.invalid',role:'viewer'})).json() as any;
 assert.equal((await f.req('/api/invitations/accept','guest','POST',{shortCode:next.shortCode})).status,200);
 assert.equal((await f.req(`/api/invitations/${next.id}/approve`,'owner','POST',{})).status,200);
 assert.equal((await f.req(`/api/invitations/${next.id}/revoke`,'owner','POST',{})).status,409);
 assert.equal((await f.req('/api/family/state','guest')).status,200);f.sql.close();
});

test('oversized JSON is rejected even without a content-length header',async()=>{
 const f=fixture();await f.seed('owner','fa','owner');
 const response=await f.req('/api/profile','owner','PUT',{name:'a'.repeat(100001)});
 assert.equal(response.status,413);f.sql.close();
});
