import {usePageMeta} from '../components/PageMeta';
import {FormEvent,useEffect,useState} from 'react';
import {Link,useSearchParams} from 'react-router';
import {AudioLines,Briefcase,Music,PlayCircle,Search,Sparkles,Users} from 'lucide-react';
import {PublicNav} from '../components/PublicNav';
import {Input} from '../components/ui/input';
import {Button} from '../components/ui/button';
import {Card,CardContent} from '../components/ui/card';
import {Badge} from '../components/ui/badge';
import {apiGet} from '../lib/api';
import {DemoBadge} from '../components/DemoBadge';

const icons:any={jobs:Briefcase,talent:Users,acts:Music,samples:PlayCircle};
const suggestions=['Playback singer','FOH engineer','Session guitarist','Wedding band','Music producer'];

export default function GlobalSearch(){
  const[sp,setSp]=useSearchParams();
  const metaQuery=(sp.get('q')||'').trim();
  usePageMeta(metaQuery?`Search: ${metaQuery.slice(0,60)}`:'Search Verse','Search music jobs, professionals, bookable acts and work samples across the Verse network.');
  const[q,setQ]=useState(sp.get('q')||'');
  const[type,setType]=useState(sp.get('type')||'all');
  const[results,setResults]=useState<any[]>([]);
  const[interpreted,setInterpreted]=useState<string[]>([]);
  const[loading,setLoading]=useState(false);
  const[error,setError]=useState('');
  const[recent,setRecent]=useState<string[]>(()=>{try{return JSON.parse(localStorage.getItem('verse_recent_searches')||'[]')}catch{return []}});

  useEffect(()=>{
    const query=sp.get('q')||'';
    const selectedType=sp.get('type')||'all';
    setQ(query);setType(selectedType);
    if(!query.trim()){setResults([]);setInterpreted([]);setError('');return}
    setLoading(true);setError('');
    apiGet<any>(`/search?q=${encodeURIComponent(query)}&type=${encodeURIComponent(selectedType)}`)
      .then(d=>{setResults(d.results||[]);setInterpreted(d.interpretedAs||[]);const next=[query.trim(),...recent.filter(x=>x!==query.trim())].slice(0,6);setRecent(next);try{localStorage.setItem('verse_recent_searches',JSON.stringify(next))}catch{/* storage blocked: keep in memory */}})
      .catch(()=>setError('Search is taking a breather. Please try again in a moment.'))
      .finally(()=>setLoading(false));
  },[sp.toString()]);

  const searchFor=(value:string)=>setSp({q:value,...(type!=='all'?{type}:{})});
  const submit=(event:FormEvent)=>{event.preventDefault();if(q.trim())searchFor(q.trim())};

  return <div className="min-h-screen bg-slate-950 text-white"><PublicNav/><main className="mx-auto max-w-6xl px-5 py-12">
    <div className="max-w-3xl"><div className="mb-4 inline-flex items-center gap-2 rounded-full border border-fuchsia-300/20 bg-fuchsia-400/10 px-3 py-1.5 text-xs font-bold text-fuchsia-200"><Sparkles size={14}/>One search. The whole music network.</div><h1 className="text-4xl font-black tracking-tight md:text-5xl">Find the people and work that <span className="verse-gradient-text">move music forward.</span></h1><p className="mt-3 text-lg text-slate-300">Explore opportunities, professionals, bookable acts and real work samples.</p></div>
    <form onSubmit={submit} className="verse-surface mt-8 flex flex-col gap-3 rounded-2xl p-3 md:flex-row" role="search"><div className="relative flex-1"><label htmlFor="network-search" className="sr-only">Search Verse</label><Search className="absolute left-3.5 top-3.5 text-slate-400" size={18}/><Input id="network-search" value={q} onChange={e=>setQ(e.target.value)} className="h-12 border-white/15 bg-black/20 pl-11" placeholder="Role, instrument, genre, city or skill…"/></div><label htmlFor="search-type" className="sr-only">Result type</label><select id="search-type" value={type} onChange={e=>setType(e.target.value)} className="h-12 rounded-xl border border-white/15 bg-[#101323] px-4"><option value="all">Everything</option><option value="jobs">Opportunities</option><option value="talent">Professionals</option><option value="acts">Acts</option><option value="samples">Work samples</option></select><Button className="h-12 px-6" disabled={!q.trim()||loading}>{loading?'Searching…':'Search'}</Button></form>
    {!sp.get('q')&&<div className="mt-5"><div className="text-xs font-bold uppercase tracking-[.16em] text-slate-400">Popular right now</div><div className="mt-3 flex flex-wrap gap-2">{suggestions.map(x=><button key={x} onClick={()=>searchFor(x)} className="rounded-full border border-white/15 bg-white/[.055] px-3.5 py-2 text-sm text-slate-300 hover:border-violet-300/40 hover:bg-violet-400/10 hover:text-white">{x}</button>)}</div></div>}
    {interpreted.length>1&&<div className="mt-4 text-sm text-violet-200">Related terms included: {interpreted.slice(1).join(' · ')}</div>}
    {recent.length>0&&<div className="mt-4 flex flex-wrap items-center gap-2 text-sm text-slate-400"><span>Recent</span>{recent.map(x=><button key={x} onClick={()=>searchFor(x)} className="rounded-lg px-2 py-1 text-slate-300 hover:bg-white/10 hover:text-white">{x}</button>)}</div>}
    {error&&<div className="mt-8 rounded-2xl border border-rose-300/25 bg-rose-400/10 p-5 text-rose-100" role="alert">{error}</div>}
    <div className="mt-8 grid gap-3" aria-live="polite">{!loading&&!error&&sp.get('q')&&results.length===0?<div className="verse-surface rounded-2xl p-10 text-center"><AudioLines className="mx-auto text-violet-300" size={30}/><h2 className="mt-4 text-xl font-bold">No exact match yet</h2><p className="mt-2 text-slate-300">Try a broader role, instrument, genre or city.</p></div>:results.map((r:any)=>{const Icon=icons[r.type]||Search;return <Link key={`${r.type}-${r.id}`} to={r.url} className="group"><Card className="verse-card-lift border-white/15 bg-white/[.045]"><CardContent className="flex gap-4 p-5"><div className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-gradient-to-br from-violet-500/25 to-cyan-400/10"><Icon size={19} className="text-violet-200"/></div><div className="min-w-0"><div className="flex items-center gap-2 text-xs font-bold uppercase tracking-[.14em] text-slate-400">{r.type}<DemoBadge show={r.demo}/></div><h2 className="mt-1 text-lg font-bold group-hover:text-violet-200">{r.title}</h2>{r.subtitle&&<div className="mt-0.5 text-sm text-violet-200">{r.subtitle}</div>}{r.description&&<p className="mt-2 line-clamp-2 text-sm text-slate-300">{r.description}</p>}<div className="mt-3 flex flex-wrap gap-1.5">{(r.tags||[]).slice(0,6).map((x:string)=><Badge key={x} variant="secondary">{x}</Badge>)}</div></div></CardContent></Card></Link>})}</div>
  </main></div>
}
