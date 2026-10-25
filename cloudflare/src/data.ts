import {ApiError, Family, Identity, id, string, type Env} from './types.ts';

export async function familyFor(env:Env,user:Identity):Promise<Family|null> {
 return env.DB.prepare("SELECT f.id,f.name,m.role FROM members m JOIN families f ON f.id=m.family_id WHERE m.user_id=? AND m.status='active' AND f.deleted_at IS NULL LIMIT 1").bind(user.id).first<Family>();
}
export function writable(family:Family):void { if(family.role==='viewer') throw new ApiError(403,'FORBIDDEN'); }
export function owner(family:Family):void { if(family.role!=='owner') throw new ApiError(403,'FORBIDDEN'); }
export async function record(env:Env,family:Family,kind:string,rid:string):Promise<any> {
 return env.DB.prepare('SELECT * FROM records WHERE family_id=? AND kind=? AND id=? AND deleted_at IS NULL').bind(family.id,kind,rid).first<any>();
}
async function reference(env:Env,family:Family,kind:string,value:unknown):Promise<void> {
 if(!await record(env,family,kind,id(value))) throw new ApiError(400,'INVALID_REFERENCE');
}
function enumeration(value:unknown,values:string[]):string {
 if(typeof value!=='string'||!values.includes(value)) throw new ApiError(400,'INVALID_INPUT');return value;
}
function array(value:unknown,max:number):any[] { if(!Array.isArray(value)||value.length>max) throw new ApiError(400,'INVALID_INPUT');return value; }
function bool(value:unknown):boolean { if(typeof value!=='boolean') throw new ApiError(400,'INVALID_INPUT');return value; }
function amount(value:unknown):number|null { if(value===null)return null;if(!Number.isSafeInteger(value)||Number(value)<0||Number(value)>100000000)throw new ApiError(400,'INVALID_AMOUNT');return Number(value); }
export async function validateRecord(env:Env,family:Family,kind:string,rid:string,raw:any):Promise<Record<string,any>> {
 if(!raw || typeof raw!=='object' || Array.isArray(raw)) throw new ApiError(400,'INVALID_INPUT');
 const v:Record<string,any>={id:rid};
 const text=(key:string,max:number,required=false)=>v[key]=string(raw[key]??'',max,required);
 if(kind==='person') {
  text('name',120,true);for(const key of ['kana','nickname','posthumousName','religion','initials'])text(key,200);
  for(const key of ['relationship','lastMet','howToAddress','phone','email'])text(key,500);
  text('address',300);text('notes',4000);text('born',40);text('died',40);
  v.kind=enumeration(raw.kind,['family','contact']);v.lifeStatus=enumeration(raw.lifeStatus,['living','deceased','unknown']);
  v.consentConfirmed=bool(raw.consentConfirmed??false);
  v.placeIds=array(raw.placeIds??[],100).map(id);
  for(const placeId of v.placeIds)await reference(env,family,'place',placeId);
  v.deceasedVersion=raw.deceasedVersion??null;
  if(v.deceasedVersion!==null && (!Number.isSafeInteger(v.deceasedVersion)||v.deceasedVersion<1))throw new ApiError(400,'INVALID_INPUT');
 } else if(kind==='relationship') {
  v.fromPersonId=id(raw.fromPersonId);v.toPersonId=id(raw.toPersonId);
  if(v.fromPersonId===v.toPersonId)throw new ApiError(400,'SELF_RELATIONSHIP');
  await reference(env,family,'person',v.fromPersonId);await reference(env,family,'person',v.toPersonId);
  v.kind=enumeration(raw.kind,['parentChild','adoptedParentChild','stepParentChild','spouse','partner','sibling','relativeUnknown','acquaintance','workRelated','templeRelated','other']);
  text('label',80);text('notes',500);
 } else if(kind==='place') {
  text('name',160,true);text('type',100,true);text('address',300);text('section',200);text('landmark',500);text('directions',2000);text('mapUrl',1000);
  if(v.mapUrl && !/^https:\/\//.test(v.mapUrl))throw new ApiError(400,'INVALID_MAP_URL');
 } else if(kind==='event') {
  text('title',160,true);text('type',100,true);v.subjectPersonId=id(raw.subjectPersonId);await reference(env,family,'person',v.subjectPersonId);
  v.status=enumeration(raw.status,['planned','completed','cancelled']);v.date=raw.date??null;
  if(v.date!==null) {
   const date=string(v.date,40,true);const match=/^(\d{4})-(\d{2})-(\d{2})(?:T.*)?$/.exec(date);
   if(!match)throw new ApiError(400,'INVALID_DATE');
   const parsed=new Date(`${match[1]}-${match[2]}-${match[3]}T00:00:00Z`);
   if(!Number.isFinite(parsed.getTime())||parsed.toISOString().slice(0,10)!==date.slice(0,10))throw new ApiError(400,'INVALID_DATE');
   v.date=date.slice(0,10);
  }
  v.placeId=raw.placeId||null;if(v.placeId)await reference(env,family,'place',v.placeId);
  text('host',160);text('notes',4000);text('nextMemo',2000);v.isCandidate=bool(raw.isCandidate??false);
  v.notificationDays=array(raw.notificationDays??[30,7],20).map((n:any)=>{if(!Number.isInteger(n)||n<0||n>3650)throw new ApiError(400,'INVALID_INPUT');return n;});
  v.participants=array(raw.participants??[],300).map(p=>({name:string(p.name,120,true),relationshipAtTime:string(p.relationshipAtTime??'',200),attendance:p.attendance==null?null:string(p.attendance,40)}));
  v.expenses=array(raw.expenses??[],100).map(p=>({label:string(p.label,160,true),amount:amount(p.amount),payer:string(p.payer??'',160)}));
 } else throw new ApiError(404,'NOT_FOUND');
 if(JSON.stringify(v).length>50000)throw new ApiError(413,'INPUT_TOO_LARGE');
 return v;
}
export function audit(env:Env,family:Family,user:Identity,action:string,entity:string,fields:string[]=[]):D1PreparedStatement {
 return env.DB.prepare('INSERT INTO activity(family_id,actor_id,action,entity_type,changed_fields,occurred_at) VALUES(?,?,?,?,?,?)')
 .bind(family.id,user.id,action,entity,JSON.stringify(fields),Date.now());
}
export async function saveRecord(env:Env,family:Family,user:Identity,kind:string,rid:string,payload:any):Promise<{id:string,version:number}> {
 writable(family);id(rid);const value=await validateRecord(env,family,kind,rid,payload.data);
 const expected=payload.expectedVersion;
 if(expected!==null && (!Number.isSafeInteger(expected)||expected<1))throw new ApiError(400,'EXPECTED_VERSION_REQUIRED');
 const now=Date.now();const next=expected===null?1:expected+1;
 const write=expected===null?
 env.DB.prepare('INSERT INTO records(family_id,kind,id,data,version,created_at,updated_at) VALUES(?,?,?,?,1,?,?) ON CONFLICT(family_id,kind,id) DO NOTHING').bind(family.id,kind,rid,JSON.stringify(value),now,now):
 env.DB.prepare('UPDATE records SET data=?,version=version+1,updated_at=? WHERE family_id=? AND kind=? AND id=? AND version=? AND deleted_at IS NULL').bind(JSON.stringify(value),now,family.id,kind,rid,expected);
 const log=env.DB.prepare('INSERT INTO activity(family_id,actor_id,action,entity_type,changed_fields,occurred_at) SELECT ?,?,?,?,?,? WHERE changes()>0').bind(family.id,user.id,expected===null?'create':'update',kind,JSON.stringify(Object.keys(value).filter(k=>k!=='id')),now);
 const result=await env.DB.batch([write,log]);
 if(result[0].meta.changes!==1)throw new ApiError(409,'VERSION_CONFLICT');
 return {id:rid,version:next};
}
export async function state(env:Env,family:Family,user:Identity):Promise<Record<string,unknown>> {
 const [rows,members,invitations,attachments,activities,prefs]=await Promise.all([
  env.DB.prepare('SELECT kind,data,version FROM records WHERE family_id=? AND deleted_at IS NULL ORDER BY created_at,id').bind(family.id).all<any>(),
  env.DB.prepare('SELECT u.id,u.name,m.role,m.status AS state FROM members m JOIN users u ON u.id=m.user_id WHERE m.family_id=? AND u.deleted_at IS NULL').bind(family.id).all<any>(),
  family.role==='owner'?env.DB.prepare('SELECT id,role,status,expires_at,accepted_name FROM invitations WHERE family_id=? ORDER BY created_at DESC LIMIT 200').bind(family.id).all<any>():Promise.resolve({results:[]}),
  env.DB.prepare('SELECT * FROM attachments WHERE family_id=? AND deleted_at IS NULL ORDER BY created_at').bind(family.id).all<any>(),
  env.DB.prepare("SELECT coalesce(u.name,'退会したメンバー') AS actor_name,a.action,a.entity_type,a.changed_fields,a.occurred_at FROM activity a LEFT JOIN users u ON u.id=a.actor_id WHERE a.family_id=? ORDER BY a.occurred_at DESC LIMIT 100").bind(family.id).all<any>(),
  env.DB.prepare('SELECT center_person_id FROM preferences WHERE family_id=? AND user_id=?').bind(family.id,user.id).first<any>()
 ]);
 const list=(kind:string)=>rows.results.filter((r:any)=>r.kind===kind).map((r:any)=>({...JSON.parse(r.data),version:r.version}));
 return {family,user:{id:user.id,name:user.name,email:user.email},people:list('person'),relationships:list('relationship'),places:list('place'),events:list('event'),members:members.results,
  invitations:invitations.results.map((r:any)=>({id:r.id,role:r.role,status:r.status==='active'&&r.expires_at<Date.now()?'expired':r.status,expiresAt:new Date(r.expires_at).toISOString(),acceptedDisplayName:r.accepted_name})),
  attachments:attachments.results.map(attachmentDto),activities:activities.results.map((r:any)=>({actorName:r.actor_name,action:r.action,entityType:r.entity_type,changedFields:JSON.parse(r.changed_fields),occurredAt:new Date(r.occurred_at).toISOString()})),centerPersonId:prefs?.center_person_id||''};
}
export function attachmentDto(r:any):Record<string,unknown> {return {id:r.id,targetType:r.target_type,targetId:r.target_id,storagePath:r.storage_path,mimeType:r.mime_type,byteSize:r.byte_size,width:r.width,height:r.height,sha256:r.sha256,caption:r.caption,version:r.version,createdAt:new Date(r.created_at).toISOString()};}
