import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const config='wrangler.production.jsonc';
let value;
try{value=JSON.parse(readFileSync(config,'utf8'));}catch{throw new Error('Create cloudflare/wrangler.production.jsonc from the example and select the personal Cloudflare account first. JSON format is required.');}
if(value.name!=='family-memory-api'||value.vars?.APP_ENV!=='production'||!/^[a-f0-9]{32}$/.test(value.account_id??'')||value.account_id!==process.env.CLOUDFLARE_ACCOUNT_ID)throw new Error('The family-memory personal account and production configuration must match CLOUDFLARE_ACCOUNT_ID.');
if(!value.d1_databases?.[0]?.database_id||value.d1_databases[0].database_id.startsWith('00000000')||value.r2_buckets?.[0]?.bucket_name!=='family-memory-private')throw new Error('Family-memory D1 and private R2 bindings are required.');
const publicUrl=new URL(value.vars.PUBLIC_API_URL);if(publicUrl.protocol!=='https:'||publicUrl.hostname.endsWith('.invalid')||value.vars.APP_ORIGINS!==publicUrl.origin)throw new Error('The app and API must use the same real HTTPS origin.');
const execute=(args)=>{const result=spawnSync(process.execPath,args,{stdio:'inherit'});if(result.status!==0)process.exit(result.status??1);};
execute(['node_modules/typescript/bin/tsc','--noEmit']);
execute(['node_modules/tsx/dist/cli.mjs','--test','test/ai.test.ts','test/api.test.ts','test/media.test.ts']);
execute(['node_modules/wrangler/bin/wrangler.js','deploy','--config',config,'--dry-run']);
execute(['node_modules/wrangler/bin/wrangler.js','deploy','--config',config]);
