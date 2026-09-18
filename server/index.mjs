import http from 'node:http';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openDatabase } from './db.mjs';
import { createApp } from './app.mjs';

const ROOT=resolve(fileURLToPath(new URL('..',import.meta.url)));
const db=openDatabase(ROOT);
const server=http.createServer(createApp({db,root:ROOT}));
const PORT=Number(process.env.PORT||4173);
server.listen(PORT,'0.0.0.0',()=>console.log(`Verse server running on port ${PORT}`));

let shuttingDown=false;
function shutdown(signal){
  if(shuttingDown)return;
  shuttingDown=true;
  console.log(`${signal} received; closing Verse cleanly`);
  const force=setTimeout(()=>process.exit(1),10_000);
  force.unref();
  server.close(()=>{
    try{db.close();}catch{}
    clearTimeout(force);
    process.exit(0);
  });
}
process.on('SIGTERM',()=>shutdown('SIGTERM'));
process.on('SIGINT',()=>shutdown('SIGINT'));
