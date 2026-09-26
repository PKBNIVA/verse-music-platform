import {useCallback,useEffect,useRef,useState} from 'react';
import {FlaskConical,Loader2,Trash2,Sparkles,CheckCircle2,AlertTriangle} from 'lucide-react';
import {toast} from 'sonner';
import {apiDelete,apiGet,apiPost} from '../../lib/api';
import {Button} from '../ui/button';
import {Card,CardContent,CardHeader,CardTitle} from '../ui/card';
import {AlertDialog,AlertDialogAction,AlertDialogCancel,AlertDialogContent,AlertDialogDescription,AlertDialogFooter,AlertDialogHeader,AlertDialogTitle} from '../ui/alert-dialog';

type Batch={name:string;demo:boolean;visibility:'public'|'hidden';artists:number;employers:number;users:number;createdAt:string};
type Job={id:string;kind:'seed'|'purge'|'purge_all';state:'queued'|'running'|'succeeded'|'failed';batch?:string;batches?:string[];size?:string;error?:string;result?:Record<string,any>;createdAt:string;updatedAt:string};
type Overview={batches:Batch[];jobs:Job[];busy:boolean;demoUsers:number;maxUsers:number;sizes:Record<string,{artists:number;employers:number}>};

const POLL_MS=2000;
const active=(job?:Job)=>job?.state==='queued'||job?.state==='running';

function describe(job:Job){
  if(job.state==='failed')return job.error||'The job failed.';
  if(job.id==='pending')return 'Sending request…';
  if(job.state!=='succeeded')return job.kind==='seed'?`Creating ${job.size||''} demo data${job.batch?` (${job.batch})`:''}…`:'Deleting demo data…';
  const r=job.result||{};
  return job.kind==='seed'
    ?`Demo data created: ${r.jobseekers??0} artists, ${r.employers??0} employers, ${r.jobs??0} opportunities and ${r.bookings??0} bookings.`
    :`Demo data deleted: ${r.usersRemoved??0} demo accounts and ${r.recordsRemoved??0} records removed.`;
}

export default function DemoDataPanel(){
  const[data,setData]=useState<Overview>(),[error,setError]=useState(''),[size,setSize]=useState('small'),[submitting,setSubmitting]=useState(false),[confirmOpen,setConfirmOpen]=useState(false);
  const[tracked,setTracked]=useState<string>();
  const announced=useRef<Set<string>>(new Set());
  const load=useCallback(async()=>{try{const d=await apiGet<Overview>('/admin/demo-data');setData(d);setError('');return d}catch(e:any){setError(e.message||'Unable to load demo data status.')}},[]);
  useEffect(()=>{void load()},[load]);

  const latest=data?.jobs?.[0];
  const trackedJob=data?.jobs?.find(j=>j.id===tracked);
  const busy=!!data?.busy||active(trackedJob)||submitting;

  useEffect(()=>{if(!data?.busy&&!active(trackedJob))return;const t=window.setTimeout(()=>{void load()},POLL_MS);return()=>window.clearTimeout(t)},[data,trackedJob,load]);
  useEffect(()=>{if(!trackedJob||active(trackedJob)||announced.current.has(trackedJob.id))return;announced.current.add(trackedJob.id);trackedJob.state==='succeeded'?toast.success(describe(trackedJob)):toast.error(describe(trackedJob))},[trackedJob]);

  const start=async(run:()=>Promise<{jobId:string}>)=>{setSubmitting(true);setError('');try{const r=await run();setTracked(r.jobId);await load()}catch(e:any){const msg=e.message||'Request failed.';setError(msg);toast.error(msg)}finally{setSubmitting(false)}};
  const create=()=>start(()=>apiPost<{jobId:string}>('/admin/demo-data',{size}));
  const purgeAll=()=>{setConfirmOpen(false);void start(()=>apiDelete<{jobId:string}>('/admin/demo-data'))};

  const demoBatches=(data?.batches||[]).filter(b=>b.demo),hiddenBatches=(data?.batches||[]).filter(b=>!b.demo);
  // While a request is in flight, never show the previous job's result as if it were this one.
  const shown:Job|undefined=submitting?{id:'pending',kind:'seed',state:'queued',createdAt:'',updatedAt:''}:tracked&&!trackedJob?undefined:trackedJob||latest;
  const sizes=data?.sizes||{small:{artists:20,employers:8},medium:{artists:60,employers:20},large:{artists:150,employers:50}};

  return <Card className="bg-white/[.05] border-amber-300/20 mb-6" data-testid="demo-data-panel"><CardHeader><CardTitle className="flex items-center gap-2 text-lg"><FlaskConical className="text-amber-300" size={20}/>Demo data</CardTitle><p className="text-sm text-slate-400">Fill the live site with sample artists, employers, opportunities, acts and bookings. Everything shows a “Demo” badge publicly, no one can sign in to these accounts, and one click deletes all of it.</p></CardHeader>
  <CardContent className="space-y-4">
    {error&&<div role="alert" className="rounded-lg border border-rose-300/30 bg-rose-500/10 p-3 text-sm text-rose-200">{error}</div>}
    {shown&&<div role="status" data-testid="demo-job-status" data-state={shown.state} className={`flex items-start gap-2 rounded-lg border p-3 text-sm ${shown.state==='failed'?'border-rose-300/30 bg-rose-500/10 text-rose-100':shown.state==='succeeded'?'border-emerald-300/30 bg-emerald-500/10 text-emerald-100':'border-sky-300/30 bg-sky-500/10 text-sky-100'}`}>{active(shown)?<Loader2 size={16} className="mt-0.5 animate-spin shrink-0"/>:shown.state==='succeeded'?<CheckCircle2 size={16} className="mt-0.5 shrink-0"/>:<AlertTriangle size={16} className="mt-0.5 shrink-0"/>}<span>{describe(shown)}</span></div>}
    <div className="flex flex-col md:flex-row md:items-end gap-3">
      <div><label htmlFor="demo-size" className="block text-xs text-slate-400 mb-1">Size</label><select id="demo-size" value={size} onChange={e=>setSize(e.target.value)} disabled={busy} className="h-9 rounded-md border border-white/15 bg-[#101323] px-3 text-sm">{Object.entries(sizes).map(([k,v])=><option key={k} value={k}>{k[0].toUpperCase()+k.slice(1)} — {v.artists} artists, {v.employers} employers</option>)}</select></div>
      <Button onClick={create} disabled={busy||!data}>{busy?<Loader2 size={15} className="mr-2 animate-spin"/>:<Sparkles size={15} className="mr-2"/>}Create demo data</Button>
      <Button variant="outline" className="border-rose-300/40 text-rose-200 hover:bg-rose-500/10" onClick={()=>setConfirmOpen(true)} disabled={busy||!demoBatches.length}><Trash2 size={15} className="mr-2"/>Delete all demo data</Button>
      {data&&<span className="text-xs text-slate-500 md:ml-auto">{data.demoUsers} of {data.maxUsers} demo accounts used</span>}
    </div>
    <div>{!data&&!error?<p className="text-sm text-slate-400" role="status">Loading demo data…</p>:demoBatches.length?<ul className="divide-y divide-white/10 rounded-lg border border-white/10" data-testid="demo-batches">{demoBatches.map(b=><li key={b.name} className="flex flex-wrap items-center justify-between gap-2 p-3 text-sm"><div><b className="font-mono">{b.name}</b><div className="text-xs text-slate-400">Created {new Date(b.createdAt).toLocaleString()} · public with Demo badge</div></div><div className="text-slate-300">{b.artists} artists · {b.employers} employers</div></li>)}</ul>:<p className="text-sm text-slate-500">No demo data on the site.</p>}
    {hiddenBatches.length>0&&<p className="mt-2 text-xs text-slate-500">Hidden QA batches (not public, managed with the synthetic_qa rake tasks): {hiddenBatches.map(b=>`${b.name} (${b.users})`).join(', ')}</p>}</div>
  </CardContent>
  <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}><AlertDialogContent className="bg-slate-900 border-white/15 text-white"><AlertDialogHeader><AlertDialogTitle>Delete all demo data?</AlertDialogTitle><AlertDialogDescription className="text-slate-300">This permanently removes {data?.demoUsers??0} demo accounts in {demoBatches.length} batch{demoBatches.length===1?'':'es'} and everything linked to them, including any applications, messages or shortlists real users made on demo content. Real accounts are never deleted.</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel className="text-slate-900">Cancel</AlertDialogCancel><AlertDialogAction className="bg-rose-600 hover:bg-rose-500 text-white" onClick={purgeAll}>Delete all demo data</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
  </Card>;
}
