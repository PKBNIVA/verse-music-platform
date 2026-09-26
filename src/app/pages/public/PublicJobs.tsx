import {FormEvent,useEffect,useState} from 'react';
import {Link,useSearchParams} from 'react-router';
import {Briefcase,MapPin,Search,ShieldCheck} from 'lucide-react';
import {PublicNav} from '../../components/PublicNav';
import {Badge} from '../../components/ui/badge';
import {Button} from '../../components/ui/button';
import {Card,CardContent} from '../../components/ui/card';
import {Input} from '../../components/ui/input';
import {apiGet} from '../../lib/api';
import {DemoBadge} from '../../components/DemoBadge';

const kinds=['jobs','gigs','auditions','sessions','tours'] as const;

export default function PublicJobs(){
  const[sp,setSp]=useSearchParams();
  const[jobs,setJobs]=useState<any[]>([]),[q,setQ]=useState(sp.get('q')||''),[location,setLocation]=useState(sp.get('location')||''),[kind,setKind]=useState(sp.get('kind')||'');
  const[loading,setLoading]=useState(true),[error,setError]=useState('');
  async function load(nextKind=kind){
    const p=new URLSearchParams();if(q)p.set('q',q);if(location)p.set('location',location);if(nextKind)p.set('kind',nextKind.replace(/s$/,''));
    setSp(p,{replace:true});setLoading(true);setError('');
    try{const d=await apiGet<any>(`/jobs?${p}`);setJobs(d.jobs||[])}catch(e:any){setError(e.message||'Unable to load opportunities')}finally{setLoading(false)}
  }
  useEffect(()=>{void load(kind)},[]);
  const chooseKind=(next:string)=>{setKind(next);void load(next)};
  const submit=(e:FormEvent)=>{e.preventDefault();void load()};
  return <div className="min-h-screen bg-slate-950 text-white"><PublicNav/><main className="max-w-6xl mx-auto px-5 py-14">
    <p className="text-xs uppercase tracking-[.22em] text-violet-300">Open music opportunities</p><h1 className="text-4xl md:text-6xl font-bold mt-2">Music jobs, gigs, sessions, auditions & tours</h1><p className="text-slate-400 mt-4 max-w-3xl">Discover public opportunities across performance, production, engineering, live shows, management, rights, labels and more.</p>
    <div className="flex flex-wrap gap-2 mt-6"><Button size="sm" variant={!kind?'secondary':'outline'} onClick={()=>chooseKind('')}>All</Button>{kinds.map(x=><Button key={x} size="sm" variant={kind===x?'secondary':'outline'} onClick={()=>chooseKind(x)} className="capitalize">{x}</Button>)}</div>
    <form onSubmit={submit} className="grid md:grid-cols-[1.3fr_1fr_auto] gap-3 mt-5"><label htmlFor="public-job-query" className="sr-only">Search opportunities</label><Input id="public-job-query" value={q} onChange={e=>setQ(e.target.value)} placeholder="Bassist, FOH engineer, composer, vocalist…" className="bg-white/5 border-white/15"/><label htmlFor="public-job-location" className="sr-only">Opportunity location</label><Input id="public-job-location" value={location} onChange={e=>setLocation(e.target.value)} placeholder="Mumbai, Delhi, remote…" className="bg-white/5 border-white/15"/><Button disabled={loading}><Search size={16} className="mr-2"/>Search</Button></form>
    {loading?<p className="text-slate-400 text-center py-16" role="status">Loading opportunities…</p>:error?<div className="text-center py-16"><p className="text-rose-300">{error}</p><Button variant="outline" className="mt-4" onClick={()=>load()}>Try again</Button></div>:<><div className="grid gap-4 mt-8">{jobs.map(j=><Link key={j.id} to={`/opportunities/${j.id}`}><Card className="bg-white/[.05] border-white/10 hover:bg-white/[.075]"><CardContent className="p-5"><div className="flex items-start justify-between gap-4"><div><div className="flex gap-2 flex-wrap"><Badge variant="secondary">{j.opportunity_kind||'job'}</Badge><DemoBadge show={j.demo}/>{j.employerVerified&&<Badge className="bg-emerald-500/10 text-emerald-300"><ShieldCheck size={12} className="mr-1"/>Verified</Badge>}</div><h2 className="text-xl font-semibold mt-3">{j.title}</h2><p className="text-violet-300">{j.company}</p><div className="flex flex-wrap gap-4 text-sm text-slate-400 mt-3"><span className="flex items-center"><MapPin size={15} className="mr-1"/>{j.location}</span><span className="flex items-center"><Briefcase size={15} className="mr-1"/>{j.function_area||j.type}</span></div></div><div className="text-sm text-right text-slate-300">{j.salary||((j.compensation_min||j.compensation_max)?`${j.currency||'INR'} ${j.compensation_min||''}${j.compensation_max?`–${j.compensation_max}`:''}`:'Terms disclosed in listing')}</div></div></CardContent></Card></Link>)}</div>{!jobs.length&&<div className="text-center py-16"><p className="text-slate-500">No matching public opportunities yet.</p><div className="flex flex-wrap justify-center gap-3 mt-5"><Link to="/auth/jobseeker"><Button>Create professional account</Button></Link><Link to="/auth/employer"><Button variant="outline">Post an opportunity</Button></Link></div></div>}</>}
  </main></div>;
}
