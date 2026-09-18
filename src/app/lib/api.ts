export const API_BASE = (import.meta as any).env?.VITE_API_URL || '/api';
export class ApiError extends Error { status:number; code?:string; constructor(message:string,status:number,code?:string){super(message);this.status=status;this.code=code;} }
export async function api<T=any>(path:string,options:RequestInit={}):Promise<T>{
  const headers=new Headers(options.headers||{}); if(options.body!==undefined)headers.set('Content-Type','application/json');
  const res=await fetch(`${API_BASE}${path}`,{...options,headers,credentials:'include'}); const data=await res.json().catch(()=>({}));
  if(!res.ok)throw new ApiError(data.error||`Request failed (${res.status})`,res.status,data.code); return data;
}
export const apiGet=<T=any>(p:string)=>api<T>(p);
export const apiPost=<T=any>(p:string,b?:unknown)=>api<T>(p,{method:'POST',body:JSON.stringify(b??{})});
export const apiPut=<T=any>(p:string,b?:unknown)=>api<T>(p,{method:'PUT',body:JSON.stringify(b??{})});
export const apiPatch=<T=any>(p:string,b?:unknown)=>api<T>(p,{method:'PATCH',body:JSON.stringify(b??{})});
export const apiDelete=<T=any>(p:string)=>api<T>(p,{method:'DELETE'});
export async function uploadMedia(file:File,onProgress?:(pct:number)=>void):Promise<{url:string;metadata?:any;thumbnailUrl?:string;waveformUrl?:string}>{
  const prep=await apiPost<any>('/uploads/presign',{filename:file.name,contentType:file.type,size:file.size});
  if(prep.mode==='direct'){
    const r=await fetch(prep.uploadUrl,{method:prep.method||'PUT',headers:prep.headers||{'Content-Type':file.type},body:file});
    if(!r.ok)throw new ApiError('Upload failed',r.status);onProgress?.(100);return {url:prep.publicUrl||prep.url};
  }
  const r=await fetch(prep.uploadUrl,{method:'PUT',headers:{'Content-Type':file.type},credentials:'include',body:file});
  const data=await r.json().catch(()=>({}));if(!r.ok)throw new ApiError(data.error||'Upload failed',r.status);onProgress?.(100);return data;
}
