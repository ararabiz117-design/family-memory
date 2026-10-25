import {authRoute,authenticate,logout,requireRecent} from './auth.ts';
import {ApiError,body,boundedBytes,emailHash,id,Identity,json,limit,randomToken,sha,string,type Env} from './types.ts';
import {attachmentDto,audit,familyFor,owner,record,saveRecord,state,writable} from './data.ts';
import {sanitizeImage} from './media.ts';
import {extractInvitation,answerGuide} from './ai.ts';

const DAY=86400000;
async function sign(env:Env,value:string):Promise<string> {return emailHash(env,value);}
function same(a:string,b:string):boolean {if(a.length!==b.length)return false;let value=0;for(let i=0;i<a.length;i++)value|=a.charCodeAt(i)^b.charCodeAt(i);return value===0;}
function checkVersion(value:any):number {if(!Number.isSafeInteger(value)||value<1)throw new ApiError(400,'EXPECTED_VERSION_REQUIRED');return value;}
export function createApp(options:{authenticate?:(request:Request,env:Env)=>Promise<Identity>}={}) {
 const identity=options.authenticate||authenticate;
 return async function handle(request:Request,env:Env):Promise<Response> {
  let response:Response;
  const origin=request.headers.get('origin');const origins=env.APP_ORIGINS.split(',').map(v=>v.trim());
  try {
   if(origin && !origins.includes(origin))throw new ApiError(403,'ORIGIN_DENIED');
   if(request.method==='OPTIONS')response=new Response(null,{status:204});
   else response=await route(request,env,identity);
  } catch(error) {
   const known=error instanceof ApiError;const message=String(error);
   const code=known?error.code:message.includes('LAST_OWNER_REQUIRED')?'LAST_OWNER_REQUIRED':message.includes('PARENT_CYCLE')?'PARENT_CYCLE':message.includes('one_active_family')||message.includes('UNIQUE constraint')?'CONFLICT':'INTERNAL_ERROR';
   response=json({error:code},known?error.status:code==='INTERNAL_ERROR'?500:409);
  }
  response=new Response(response.body,response);
  if(origin && origins.includes(origin)) {
   response.headers.set('Access-Control-Allow-Origin',origin);response.headers.set('Access-Control-Allow-Credentials','true');response.headers.set('Vary','Origin');
   response.headers.set('Access-Control-Allow-Headers','content-type,authorization,x-caption,x-requested-with');response.headers.set('Access-Control-Allow-Methods','GET,POST,PUT,DELETE,OPTIONS');
  }
  response.headers.set('X-Content-Type-Options','nosniff');response.headers.set('Referrer-Policy','no-referrer');response.headers.set('X-Frame-Options','DENY');
  return response;
 };
}
async function route(request:Request,env:Env,identity:(r:Request,e:Env)=>Promise<Identity>):Promise<Response> {
 const url=new URL(request.url),path=url.pathname,method=request.method;
 if(path==='/api/health')return json({ok:true,backend:'cloudflare',version:'0.5.0'});
 const authResponse=await authRoute(request,env);if(authResponse)return authResponse;
 // Only short-lived, HMAC-signed image links may be used without a session.
 if(path.startsWith('/api/media/')&&method==='GET') {
  const aid=id(path.slice('/api/media/'.length));const expires=Number(url.searchParams.get('expires'));const signature=url.searchParams.get('sig')||'';
  if(!Number.isSafeInteger(expires)||expires<Date.now()||expires>Date.now()+301000)throw new ApiError(403,'LINK_EXPIRED');
  const row=await env.DB.prepare('SELECT a.* FROM attachments a JOIN families f ON f.id=a.family_id WHERE a.id=? AND a.deleted_at IS NULL AND f.deleted_at IS NULL').bind(aid).first<any>();
  if(!row || !same(signature,await sign(env,`${row.family_id}:${aid}:${row.version}:${expires}`)))throw new ApiError(403,'LINK_EXPIRED');
  const object=await env.PHOTOS.get(row.storage_path);if(!object)throw new ApiError(404,'NOT_FOUND');
  return new Response(object.body,{headers:{'Content-Type':row.mime_type,'Cache-Control':'no-store','Content-Security-Policy':"default-src 'none'"}});
 }
 if(!path.startsWith('/api/')) {
  if(env.ASSETS)return env.ASSETS.fetch(request);
  throw new ApiError(404,'NOT_FOUND');
 }
 const user=await identity(request,env);let family=await familyFor(env,user);
 if(path==='/api/auth/logout'&&method==='POST')return logout(request,env,user);
 if(path==='/api/me'&&method==='GET') {
  const pending=await env.DB.prepare("SELECT 1 AS pending FROM members m JOIN families f ON f.id=m.family_id WHERE m.user_id=? AND m.status='pending' AND f.deleted_at IS NULL LIMIT 1").bind(user.id).first();
  return json({user:{id:user.id,name:user.name,email:user.email},family,pendingApproval:!!pending});
 }
 if(path==='/api/profile'&&method==='PUT') {const data=await body(request);const name=string(data.name,80,true);await env.DB.prepare('UPDATE users SET name=? WHERE id=?').bind(name,user.id).run();return json({ok:true});}
 if(path==='/api/families'&&method==='POST') {
  if(family)throw new ApiError(409,'ALREADY_HAS_FAMILY');
  const data=await body(request);const name=string(data.name,80,true);const fid=crypto.randomUUID();
  await env.DB.batch([env.DB.prepare('INSERT INTO families(id,name,created_at) VALUES(?,?,?)').bind(fid,name,Date.now()),env.DB.prepare("INSERT INTO members(family_id,user_id,role,status) VALUES(?,?,'owner','active')").bind(fid,user.id)]);
  return json({id:fid},201);
 }
 if(path==='/api/invitations/accept'&&method==='POST') {
  if(family)throw new ApiError(409,'ALREADY_HAS_FAMILY');
  await limit(env,`accept:${user.id}`,5,900);const data=await body(request);
  const hashed=await sha(data.token?string(data.token,100,true):string(data.shortCode,30,true).toUpperCase());
  const invitation=await env.DB.prepare("SELECT i.* FROM invitations i JOIN families f ON f.id=i.family_id WHERE (i.token_hash=? OR i.code_hash=?) AND i.email_hash=? AND i.status='active' AND i.expires_at>? AND f.deleted_at IS NULL").bind(hashed,hashed,user.email_hash,Date.now()).first<any>();
  if(!invitation)throw new ApiError(400,'INVITATION_INVALID');
  const results=await env.DB.batch([
   env.DB.prepare("UPDATE invitations SET status='accepted',accepted_by=?,accepted_name=? WHERE id=? AND status='active' AND expires_at>? AND EXISTS(SELECT 1 FROM families WHERE id=family_id AND deleted_at IS NULL)").bind(user.id,user.name,invitation.id,Date.now()),
   env.DB.prepare("INSERT INTO members(family_id,user_id,role,status,invitation_id) SELECT family_id,?,role,'pending',id FROM invitations WHERE id=? AND status='accepted' AND accepted_by=? AND changes()>0 ON CONFLICT(family_id,user_id) DO UPDATE SET role=excluded.role,status=excluded.status,invitation_id=excluded.invitation_id WHERE members.status<>'active'").bind(user.id,invitation.id,user.id)
  ]);if(results[0].meta.changes!==1)throw new ApiError(409,'INVITATION_INVALID');return json({pendingApproval:true});
 }
 if(path==='/api/deletions/account'&&method==='POST') {
  requireRecent(user);const now=Date.now();
  await env.DB.batch([
   env.DB.prepare("UPDATE members SET status='suspended' WHERE user_id=?").bind(user.id),
   env.DB.prepare('UPDATE users SET deleted_at=? WHERE id=?').bind(now,user.id),
   env.DB.prepare('DELETE FROM sessions WHERE user_id=?').bind(user.id),
   env.DB.prepare("INSERT INTO deletion_jobs(id,scope,user_id,execute_after) VALUES(?,'account',?,?)").bind(crypto.randomUUID(),user.id,now+30*DAY)
  ]);return json({ok:true,deleteAfter:new Date(now+30*DAY).toISOString()});
 }
 if(!family)throw new ApiError(403,'NO_ACTIVE_FAMILY');
 if(path==='/api/family/state'&&method==='GET')return json(await state(env,family,user));
 const records=/^\/api\/records\/(person|relationship|place|event)\/([A-Za-z0-9_-]{1,100})$/.exec(path);
 if(records&&method==='PUT')return json(await saveRecord(env,family,user,records[1],records[2],await body(request)));
 if(records&&method==='DELETE'&&records[1]==='event') {
  writable(family);const expected=checkVersion((await body(request)).expectedVersion);
  const result=await env.DB.prepare('UPDATE records SET deleted_at=?,updated_at=?,version=version+1 WHERE family_id=? AND kind=? AND id=? AND version=? AND deleted_at IS NULL').bind(Date.now(),Date.now(),family.id,'event',records[2],expected).run();
  if(result.meta.changes!==1)throw new ApiError(409,'VERSION_CONFLICT');await audit(env,family,user,'soft_delete','event').run();return json({ok:true});
 }
 if(path==='/api/preferences'&&method==='POST') {const data=await body(request);const center=id(data.centerPersonId);if(!await record(env,family,'person',center))throw new ApiError(400,'INVALID_REFERENCE');await env.DB.prepare('INSERT INTO preferences(family_id,user_id,center_person_id) VALUES(?,?,?) ON CONFLICT(family_id,user_id) DO UPDATE SET center_person_id=excluded.center_person_id').bind(family.id,user.id,center).run();return json({ok:true});}
 if(path==='/api/invitations'&&method==='POST') {
  owner(family);await limit(env,`invite:${user.id}`,20,3600);const data=await body(request);const email=string(data.email,254,true).toLowerCase();const role=data.role;
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||!['editor','viewer'].includes(role))throw new ApiError(400,'INVALID_INPUT');
  const token=randomToken();const shortCode=randomToken().slice(0,12).toUpperCase();const iid=crypto.randomUUID();const expires=Date.now()+DAY;
  await env.DB.batch([env.DB.prepare("INSERT INTO invitations(id,family_id,token_hash,code_hash,email_hash,role,status,expires_at,created_at) VALUES(?,?,?,?,?,?,'active',?,?)").bind(iid,family.id,await sha(token),await sha(shortCode),await emailHash(env,email),role,expires,Date.now()),audit(env,family,user,'invite','family_invitations')]);
  const base=env.AUTH_RETURN_URLS.split(',').find(v=>v.startsWith('https://'))||env.AUTH_RETURN_URLS.split(',')[0];const link=new URL('/invite',base);link.searchParams.set('token',token);return json({id:iid,shortCode,inviteUrl:link.href,expiresAt:new Date(expires).toISOString()},201);
 }
 const invitationAction=/^\/api\/invitations\/([A-Za-z0-9_-]+)\/(approve|revoke)$/.exec(path);
 if(invitationAction&&method==='POST') {
  owner(family);const row=await env.DB.prepare('SELECT * FROM invitations WHERE id=? AND family_id=?').bind(invitationAction[1],family.id).first<any>();if(!row)throw new ApiError(404,'NOT_FOUND');
  if(invitationAction[2]==='approve') {
   if(row.status!=='accepted'||!row.accepted_by)throw new ApiError(409,'INVITATION_INVALID');
   const result=await env.DB.batch([
    env.DB.prepare("UPDATE invitations SET status='approved' WHERE id=? AND family_id=? AND status='accepted'").bind(row.id,family.id),
    env.DB.prepare("UPDATE members SET status='active',role=? WHERE family_id=? AND user_id=? AND invitation_id=? AND status='pending' AND changes()>0").bind(row.role,family.id,row.accepted_by,row.id)
   ]);if(result[0].meta.changes!==1)throw new ApiError(409,'INVITATION_INVALID');await audit(env,family,user,'approve','family_members').run();
  } else {
   if(!['active','accepted'].includes(row.status))throw new ApiError(409,'INVITATION_INVALID');
   const result=await env.DB.batch([env.DB.prepare("UPDATE invitations SET status='revoked' WHERE id=? AND family_id=? AND status IN ('active','accepted')").bind(row.id,family.id),env.DB.prepare("DELETE FROM members WHERE family_id=? AND invitation_id=? AND status='pending' AND changes()>0").bind(family.id,row.id)]);
   if(result[0].meta.changes!==1)throw new ApiError(409,'INVITATION_INVALID');await audit(env,family,user,'revoke','family_invitations').run();
  }return json({ok:true});
 }
 const member=/^\/api\/members\/([A-Za-z0-9_-]+)$/.exec(path);
 if(member&&method==='PUT') {owner(family);const role=(await body(request)).role;if(!['owner','editor','viewer'].includes(role))throw new ApiError(400,'INVALID_ROLE');const result=await env.DB.prepare("UPDATE members SET role=? WHERE family_id=? AND user_id=? AND status='active'").bind(role,family.id,member[1]).run();if(!result.meta.changes)throw new ApiError(404,'NOT_FOUND');await audit(env,family,user,'role_change','family_members').run();return json({ok:true});}
 if(path==='/api/attachments'&&method==='POST') {
  writable(family);await limit(env,`upload:${user.id}`,100,DAY/1000);
  const targetType=url.searchParams.get('targetType')||'',targetId=id(url.searchParams.get('targetId'));
  if(!['person','place','event'].includes(targetType)||!await record(env,family,targetType,targetId))throw new ApiError(400,'INVALID_REFERENCE');
  if(Number(request.headers.get('content-length')||0)>5242880)throw new ApiError(413,'IMAGE_TOO_LARGE');
  const bytes=await boundedBytes(request,5242880);const image=await sanitizeImage(bytes,request.headers.get('content-type')?.split(';')[0]||'');
  const aid=crypto.randomUUID();const key=`${family.id}/${targetType}/${targetId}/${aid}.${image.mime==='image/png'?'png':'jpg'}`;
  let caption='';const rawCaption=request.headers.get('x-caption');if(rawCaption){try{caption=new TextDecoder('utf-8',{fatal:true,ignoreBOM:false}).decode(Uint8Array.from(atob(rawCaption.replaceAll('-','+').replaceAll('_','/')),c=>c.charCodeAt(0)));}catch{throw new ApiError(400,'INVALID_INPUT');}caption=string(caption,300);}
  await env.PHOTOS.put(key,image.bytes,{httpMetadata:{contentType:image.mime}});
  try {await env.DB.batch([env.DB.prepare('INSERT INTO attachments(id,family_id,target_type,target_id,storage_path,mime_type,byte_size,width,height,sha256,caption,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)').bind(aid,family.id,targetType,targetId,key,image.mime,image.bytes.length,image.width,image.height,image.sha256,caption,Date.now()),audit(env,family,user,'create','attachments')]);}
  catch(error){await env.PHOTOS.delete(key);throw error;}
  const row=await env.DB.prepare('SELECT * FROM attachments WHERE id=? AND family_id=?').bind(aid,family.id).first<any>();return json(attachmentDto(row),201);
 }
 const attachment=/^\/api\/attachments\/([A-Za-z0-9_-]+)(\/url)?$/.exec(path);
 if(attachment) {
  const row=await env.DB.prepare('SELECT * FROM attachments WHERE id=? AND family_id=? AND deleted_at IS NULL').bind(attachment[1],family.id).first<any>();if(!row)throw new ApiError(404,'NOT_FOUND');
  if(attachment[2]&&method==='GET') {const expires=Date.now()+300000;const sig=await sign(env,`${family.id}:${row.id}:${row.version}:${expires}`);return json({url:`${env.PUBLIC_API_URL}/api/media/${row.id}?expires=${expires}&sig=${sig}`});}
  if(method==='DELETE'&&!attachment[2]){writable(family);const expected=checkVersion((await body(request)).expectedVersion);const result=await env.DB.prepare('UPDATE attachments SET deleted_at=?,version=version+1 WHERE id=? AND family_id=? AND version=? AND deleted_at IS NULL').bind(Date.now(),row.id,family.id,expected).run();if(!result.meta.changes)throw new ApiError(409,'VERSION_CONFLICT');await audit(env,family,user,'soft_delete','attachments').run();return json({ok:true});}
 }
 if(path==='/api/export'&&method==='GET') {
  owner(family);const data=await state(env,family,user);await audit(env,family,user,'export','families').run();
  if(url.searchParams.get('format')==='csv') {const quote=(v:any)=>`"${String(v??'').replaceAll('"','""')}"`;const lines=['entity,id,version,data'];for(const key of ['people','relationships','places','events','attachments'])for(const item of data[key] as any[])lines.push([key,item.id,item.version,JSON.stringify(item)].map(quote).join(','));return new Response('\uFEFF'+lines.join('\r\n'),{headers:{'Content-Type':'text/csv; charset=utf-8','Cache-Control':'no-store'}});}
  return json({format:'family_memory_cloudflare_v1',exportedAt:new Date().toISOString(),...data});
 }
 if(path==='/api/deletions/family'&&method==='POST') {owner(family);requireRecent(user);const now=Date.now();await env.DB.batch([env.DB.prepare('UPDATE families SET deleted_at=? WHERE id=? AND deleted_at IS NULL').bind(now,family.id),env.DB.prepare("UPDATE members SET status='suspended' WHERE family_id=?").bind(family.id),env.DB.prepare("INSERT INTO deletion_jobs(id,scope,family_id,execute_after) VALUES(?,'family',?,?)").bind(crypto.randomUUID(),family.id,now+30*DAY),audit(env,family,user,'deletion_request','families')]);return json({ok:true,deleteAfter:new Date(now+30*DAY).toISOString()});}
 if(['/api/ai/invitation','/api/ai/guide'].includes(path)&&method==='POST') {
  if(env.AI_ENABLED!=='true')throw new ApiError(503,'AI_NOT_CONFIGURED');await limit(env,`ai:${user.id}`,10,DAY/1000);const data=await body(request);
  if(data.consent!==true)throw new ApiError(400,'AI_CONSENT_REQUIRED');
  const binding={run:(model:string,input:Record<string,unknown>)=>env.AI.run(model as any,input as any)};
  const result=path.endsWith('invitation')?await extractInvitation(binding,{text:data.text,consent:true,model:env.AI_MODEL}):await answerGuide(binding,{question:data.question,consent:true,model:env.AI_MODEL});return json(result);
 }
 throw new ApiError(404,'NOT_FOUND');
}
export async function cleanup(env:Env):Promise<void> {
 const now=Date.now();
 const jobs=await env.DB.prepare('SELECT * FROM deletion_jobs WHERE execute_after<=? LIMIT 20').bind(now).all<any>();
 for(const job of jobs.results) {
  if(job.scope==='family') {
   const photos=await env.DB.prepare('SELECT storage_path FROM attachments WHERE family_id=? LIMIT 500').bind(job.family_id).all<any>();
   if(photos.results.length){await env.PHOTOS.delete(photos.results.map((p:any)=>p.storage_path));await env.DB.prepare('DELETE FROM attachments WHERE family_id=? AND storage_path IN (SELECT storage_path FROM attachments WHERE family_id=? LIMIT 500)').bind(job.family_id,job.family_id).run();}
   const remaining=await env.DB.prepare('SELECT 1 FROM attachments WHERE family_id=? LIMIT 1').bind(job.family_id).first();
   if(!remaining)await env.DB.prepare('DELETE FROM families WHERE id=? AND deleted_at IS NOT NULL').bind(job.family_id).run();
  } else {await env.DB.prepare('DELETE FROM users WHERE id=? AND deleted_at IS NOT NULL').bind(job.user_id).run();}
 }
 const photos=await env.DB.prepare('SELECT id,storage_path FROM attachments WHERE deleted_at IS NOT NULL AND deleted_at<? LIMIT 500').bind(now-30*DAY).all<any>();
 for(const photo of photos.results){await env.PHOTOS.delete(photo.storage_path);await env.DB.prepare('DELETE FROM attachments WHERE id=?').bind(photo.id).run();}
 const cursor=await env.DB.prepare("SELECT value FROM maintenance WHERE key='r2_cursor'").first<{value:string}>();
 const listing=await env.PHOTOS.list({limit:500,...(cursor?.value?{cursor:cursor.value}:{})});
 for(const object of listing.objects)if(object.uploaded.getTime()<now-DAY){const exists=await env.DB.prepare('SELECT 1 FROM attachments WHERE storage_path=?').bind(object.key).first();if(!exists)await env.PHOTOS.delete(object.key);}
 await env.DB.batch([
  env.DB.prepare("INSERT INTO maintenance(key,value) VALUES('r2_cursor',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").bind(listing.truncated?listing.cursor:''),
  ...['sessions','auth_flows','login_tickets'].map(table=>env.DB.prepare(`DELETE FROM ${table} WHERE expires_at<?`).bind(now)),
  env.DB.prepare('DELETE FROM rate_limits WHERE reset_at<?').bind(now)
 ]);
}
const fetchHandler=createApp();
export default {fetch:fetchHandler,scheduled:(_event:ScheduledController,env:Env,context:ExecutionContext)=>context.waitUntil(cleanup(env))} satisfies ExportedHandler<Env>;
