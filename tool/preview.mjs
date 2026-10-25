import http from 'node:http';
import {createReadStream,existsSync,statSync} from 'node:fs';
import {resolve,extname,sep} from 'node:path';
const root=resolve(process.argv[2]||'build/web-preview');const port=Number(process.argv[3]||8766);
const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.svg':'image/svg+xml','.css':'text/css','.ttf':'font/ttf'};
http.createServer((req,res)=>{
 let path;try{path=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://127.0.0.1').pathname));}catch{res.writeHead(400).end();return;}
 if(path!==root&&!path.startsWith(root+sep)){res.writeHead(403).end();return;}
 if(!existsSync(path)||statSync(path).isDirectory())path=resolve(root,'index.html');
 if(!existsSync(path)){res.writeHead(404).end();return;}
 res.writeHead(200,{'Content-Type':mime[extname(path)]||'application/octet-stream','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});createReadStream(path).pipe(res);
}).listen(port,'127.0.0.1',()=>console.log(`Preview: http://127.0.0.1:${port}/`));
