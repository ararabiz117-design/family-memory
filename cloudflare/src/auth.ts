import {createRemoteJWKSet, jwtVerify} from 'jose';
import {ApiError, body, emailHash, Identity, json, limit, randomToken, sha, string, type Env} from './types.ts';

const googleKeys=createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));
const cookieName='fm_session';
const DAY=86400000;
function cookies(request: Request): Record<string,string> {
 return Object.fromEntries((request.headers.get('cookie')||'').split(';').map(p=>p.trim().split(/=(.*)/s).slice(0,2)).filter(p=>p.length===2));
}
function secure(env:Env): string { return new URL(env.PUBLIC_API_URL).protocol==='https:' ? '; Secure' : ''; }
function callback(env: Env): string { return `${env.PUBLIC_API_URL.replace(/\/$/,'')}/api/auth/callback/google`; }
function configured(env: Env): void {
 if(!env.GOOGLE_CLIENT_ID || !env.GOOGLE_CLIENT_SECRET || !env.AUTH_SECRET || env.AUTH_SECRET.length<32) throw new ApiError(503,'AUTH_NOT_CONFIGURED');
 if(env.APP_ENV!=='local' && !env.PUBLIC_API_URL.startsWith('https://')) throw new ApiError(503,'HTTPS_REQUIRED');
}
function allowedReturn(env: Env, url: string): boolean {
 return env.AUTH_RETURN_URLS.split(',').map(v=>v.trim()).includes(url);
}

export async function authenticate(request: Request,env:Env):Promise<Identity> {
 const bearer=request.headers.get('authorization')?.match(/^Bearer ([A-Za-z0-9_-]{43})$/)?.[1];
 const token=bearer||cookies(request)[cookieName];
 if(!token || !/^[A-Za-z0-9_-]{43}$/.test(token)) throw new ApiError(401,'AUTH_REQUIRED');
 const tokenHash=await sha(token);
 const user=await env.DB.prepare('SELECT u.id,u.name,u.email,u.email_hash,s.authenticated_at FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>? AND u.deleted_at IS NULL')
 .bind(tokenHash,Date.now()).first<Identity>();
 if(!user) throw new ApiError(401,'AUTH_REQUIRED');
 if(!bearer && !['GET','HEAD'].includes(request.method)) {
  const origin=request.headers.get('origin');
  if(!origin || !env.APP_ORIGINS.split(',').includes(origin)) throw new ApiError(403,'ORIGIN_DENIED');
 }
 return {...user,token_hash:tokenHash};
}
export function requireRecent(user:Identity):void {
 if(Date.now()-user.authenticated_at>10*60*1000) throw new ApiError(403,'REAUTHENTICATION_REQUIRED');
}

export async function authRoute(request:Request,env:Env):Promise<Response|null> {
 const url=new URL(request.url); const path=url.pathname;
 if(path==='/api/auth/start' && request.method==='POST') {
  configured(env);
  await limit(env,`login:${request.headers.get('CF-Connecting-IP')||'local'}`,15,900);
  const data=await body(request);
  const returnTo=string(data.returnTo,1000,true);const challenge=string(data.challenge,43,true);
  if(!allowedReturn(env,returnTo) || !/^[A-Za-z0-9_-]{43}$/.test(challenge)) throw new ApiError(400,'INVALID_REDIRECT');
  const state=randomToken();const verifier=randomToken();const nonce=randomToken();
  await env.DB.prepare('INSERT INTO auth_flows(state_hash,nonce,google_verifier,challenge,return_to,expires_at) VALUES(?,?,?,?,?,?)')
  .bind(await sha(state),nonce,verifier,challenge,returnTo,Date.now()+600000).run();
  return json({url:`${env.PUBLIC_API_URL}/api/auth/redirect?flow=${state}`});
 }
 if(path==='/api/auth/redirect' && request.method==='GET') {
  configured(env);const state=url.searchParams.get('flow')||'';
  const flow=await env.DB.prepare('SELECT * FROM auth_flows WHERE state_hash=? AND expires_at>?').bind(await sha(state),Date.now()).first<any>();
  if(!flow) throw new ApiError(400,'LOGIN_EXPIRED');
  const target=new URL('https://accounts.google.com/o/oauth2/v2/auth');
  const params={client_id:env.GOOGLE_CLIENT_ID!,redirect_uri:callback(env),response_type:'code',scope:'openid email profile',state,nonce:flow.nonce,code_challenge:await sha(flow.google_verifier),code_challenge_method:'S256',prompt:'select_account'};
  Object.entries(params).forEach(([k,v])=>target.searchParams.set(k,v));
  return new Response(null,{status:302,headers:{Location:target.href,'Cache-Control':'no-store','Set-Cookie':`fm_oauth_state=${state}; HttpOnly; SameSite=Lax; Path=/api/auth; Max-Age=600${secure(env)}`}});
 }
 if(path==='/api/auth/callback/google' && request.method==='GET') {
  configured(env);const state=url.searchParams.get('state')||'';
  if(!state || cookies(request).fm_oauth_state!==state) throw new ApiError(400,'LOGIN_STATE_INVALID');
  const flow=await env.DB.prepare('DELETE FROM auth_flows WHERE state_hash=? AND expires_at>? RETURNING *').bind(await sha(state),Date.now()).first<any>();
  if(!flow || !allowedReturn(env,flow.return_to)) throw new ApiError(400,'LOGIN_EXPIRED');
  const returnUrl=new URL(flow.return_to);
  try {
   const code=url.searchParams.get('code'); if(!code) throw new Error('NO_CODE');
   const tokenResponse=await fetch('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({client_id:env.GOOGLE_CLIENT_ID!,client_secret:env.GOOGLE_CLIENT_SECRET!,grant_type:'authorization_code',code,code_verifier:flow.google_verifier,redirect_uri:callback(env)})});
   if(!tokenResponse.ok) throw new Error('TOKEN_EXCHANGE');
   const tokens=await tokenResponse.json() as {id_token?:string};
   if(!tokens.id_token) throw new Error('NO_ID_TOKEN');
   const {payload}=await jwtVerify(tokens.id_token,googleKeys,{issuer:['https://accounts.google.com','accounts.google.com'],audience:env.GOOGLE_CLIENT_ID});
   if(payload.nonce!==flow.nonce || payload.email_verified!==true || typeof payload.email!=='string' || !payload.sub) throw new Error('IDENTITY_INVALID');
   const email=payload.email.toLowerCase();const eid=await emailHash(env,email);
   let user=await env.DB.prepare('SELECT * FROM users WHERE google_sub=?').bind(payload.sub).first<any>();
   if(user?.deleted_at) throw new Error('ACCOUNT_DELETION_PENDING');
   if(!user) {
    const uid=crypto.randomUUID();const name=String(payload.name||'利用者').slice(0,80);
    await env.DB.prepare('INSERT INTO users(id,google_sub,email,email_hash,name,created_at) VALUES(?,?,?,?,?,?) ON CONFLICT(google_sub) DO NOTHING').bind(uid,payload.sub,email,eid,name,Date.now()).run();
    user=await env.DB.prepare('SELECT * FROM users WHERE google_sub=?').bind(payload.sub).first<any>();
   } else {
    await env.DB.prepare('UPDATE users SET email=?,email_hash=? WHERE id=?').bind(email,eid,user.id).run();
   }
   const ticket=randomToken();
   await env.DB.prepare('INSERT INTO login_tickets(ticket_hash,user_id,challenge,expires_at) VALUES(?,?,?,?)').bind(await sha(ticket),user.id,flow.challenge,Date.now()+60000).run();
   returnUrl.searchParams.set('login_ticket',ticket);
  } catch { returnUrl.searchParams.set('auth_error','google_sign_in_failed'); }
  return new Response(null,{status:302,headers:{Location:returnUrl.href,'Cache-Control':'no-store','Referrer-Policy':'no-referrer','Set-Cookie':`fm_oauth_state=; Path=/api/auth; HttpOnly; SameSite=Lax; Max-Age=0${secure(env)}`}});
 }
 if(path==='/api/auth/exchange' && request.method==='POST') {
  const data=await body(request);const ticket=string(data.ticket,100,true);const verifier=string(data.verifier,128,true);
  if(!/^[A-Za-z0-9_-]{43}$/.test(ticket) || !/^[A-Za-z0-9._~-]{43,128}$/.test(verifier)) throw new ApiError(400,'INVALID_LOGIN_TICKET');
  const challenge=await sha(verifier);const row=await env.DB.prepare('UPDATE login_tickets SET used_at=? WHERE ticket_hash=? AND challenge=? AND used_at IS NULL AND expires_at>? RETURNING user_id')
  .bind(Date.now(),await sha(ticket),challenge,Date.now()).first<{user_id:string}>();
  if(!row) throw new ApiError(401,'LOGIN_TICKET_EXPIRED');
  const user=await env.DB.prepare('SELECT id,name,email FROM users WHERE id=? AND deleted_at IS NULL').bind(row.user_id).first();
  if(!user) throw new ApiError(401,'AUTH_REQUIRED');
  const native=data.client==='native';
  if(native && request.headers.has('origin')) throw new ApiError(403,'ORIGIN_DENIED');
  const token=randomToken();
  await env.DB.prepare('INSERT INTO sessions(token_hash,user_id,expires_at,authenticated_at) VALUES(?,?,?,?)').bind(await sha(token),row.user_id,Date.now()+30*DAY,Date.now()).run();
  const response=json({user,...(native?{token}:{})});
  if(!native) response.headers.set('Set-Cookie',`${cookieName}=${token}; HttpOnly; SameSite=Lax; Path=/api; Max-Age=${30*86400}${secure(env)}`);
  return response;
 }
 return null;
}

export async function logout(request:Request,env:Env,user:Identity):Promise<Response> {
 if(user.token_hash) await env.DB.prepare('DELETE FROM sessions WHERE token_hash=?').bind(user.token_hash).run();
 const response=json({ok:true});response.headers.set('Set-Cookie',`${cookieName}=; HttpOnly; SameSite=Lax; Path=/api; Max-Age=0${secure(env)}`);return response;
}
