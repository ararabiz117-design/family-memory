export interface Env {
  DB: D1Database; PHOTOS: R2Bucket; AI: Ai;
  APP_ENV: string; PUBLIC_API_URL: string; APP_ORIGINS: string; AUTH_RETURN_URLS: string;
  GOOGLE_CLIENT_ID?: string; GOOGLE_CLIENT_SECRET?: string; AUTH_SECRET?: string;
  AI_ENABLED?: string; AI_MODEL?: string; ASSETS?: Fetcher;
}
export interface Identity { id: string; name: string; email: string; email_hash: string; authenticated_at: number; token_hash?: string }
export interface Family { id: string; name: string; role: 'owner'|'editor'|'viewer' }
export class ApiError extends Error {
 constructor(public status: number, public code: string) { super(code); }
}
export function json(value: unknown, status = 200): Response {
 return Response.json(value, { status, headers: { 'Cache-Control': 'no-store' } });
}
export async function body(request: Request): Promise<Record<string, any>> {
 const bytes=await boundedBytes(request,100000);
 let text:string;try{text=new TextDecoder('utf-8',{fatal:true,ignoreBOM:false}).decode(bytes);}catch{throw new ApiError(400,'INVALID_JSON');}
 try { const value=JSON.parse(text); if(!value || Array.isArray(value) || typeof value!=='object') throw 0; return value; }
 catch { throw new ApiError(400,'INVALID_JSON'); }
}
export async function boundedBytes(request:Request,max:number):Promise<Uint8Array> {
 if(Number(request.headers.get('content-length')||0)>max)throw new ApiError(413,'INPUT_TOO_LARGE');
 if(!request.body)return new Uint8Array();
 const reader=request.body.getReader();const chunks:Uint8Array[]=[];let size=0;
 try {while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>max){await reader.cancel();throw new ApiError(413,'INPUT_TOO_LARGE');}chunks.push(value);}}
 finally{reader.releaseLock();}
 const all=new Uint8Array(size);let offset=0;for(const chunk of chunks){all.set(chunk,offset);offset+=chunk.length;}return all;
}
export function string(value: unknown, max: number, required = false): string {
 if(typeof value!=='string' || value.length>max || (required && !value.trim())) throw new ApiError(400,'INVALID_INPUT');
 return value.trim();
}
export function id(value: unknown): string {
 const v=string(value,100,true); if(!/^[A-Za-z0-9_-]+$/.test(v)) throw new ApiError(400,'INVALID_ID'); return v;
}
export function randomToken(): string { return base64(crypto.getRandomValues(new Uint8Array(32))); }
export function base64(bytes: Uint8Array): string {
 return btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
}
export async function sha(value: string): Promise<string> {
 return base64(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value))));
}
export async function emailHash(env: Env, email: string): Promise<string> {
 if(!env.AUTH_SECRET || env.AUTH_SECRET.length<32) throw new ApiError(503,'AUTH_NOT_CONFIGURED');
 const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(env.AUTH_SECRET),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 return base64(new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(email.trim().toLowerCase()))));
}
export async function limit(env: Env, key: string, maximum: number, seconds: number): Promise<void> {
 const now=Date.now(); const bucket=Math.floor(now/(seconds*1000)); const hashed=await sha(`${key}:${bucket}`);
 const row=await env.DB.prepare('INSERT INTO rate_limits(key,count,reset_at) VALUES(?,1,?) ON CONFLICT(key) DO UPDATE SET count=count+1 RETURNING count')
 .bind(hashed,(bucket+1)*seconds*1000).first<{count:number}>();
 if(row!.count>maximum) throw new ApiError(429,'RATE_LIMITED');
}
