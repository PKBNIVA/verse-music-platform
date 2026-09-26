import {FormEvent,useEffect,useState} from 'react';
import {Link,useSearchParams} from 'react-router';
import {MapPin,Search,ShieldCheck} from 'lucide-react';
import {PublicNav} from '../../components/PublicNav';
import {Badge} from '../../components/ui/badge';
import {Button} from '../../components/ui/button';
import {Card,CardContent} from '../../components/ui/card';
import {Input} from '../../components/ui/input';
import {apiGet} from '../../lib/api';
import {DemoBadge} from '../../components/DemoBadge';

export default function PublicTalent(){
  const[sp,setSp]=useSearchParams();const[items,setItems]=useState<any[]>([]),[q,setQ]=useState(sp.get('q')||''),[location,setLocation]=useState(sp.get('location')||''),[role]=useState(sp.get('role')||'');
  const[loading,setLoading]=useState(true),[error,setError]=useState('');
  async function load(){const p=new URLSearchParams();if(q)p.set('q',q);if(location)p.set('location',location);if(role)p.set('role',role);setSp(p,{replace:true});setLoading(true);setError('');try{const d=await apiGet<any>(`/public/talent?${p}`);setItems(d.talent||[])}catch(e:any){setError(e.message||'Unable to load professionals')}finally{setLoading(false)}}
  useEffect(()=>{void load()},[]);const submit=(e:FormEvent)=>{e.preventDefault();void load()};
  return <div className="min-h-screen bg-slate-950 text-white"><PublicNav/><main className="max-w-6xl mx-auto px-5 py-14"><p className="text-xs uppercase tracking-[.22em] text-violet-300">Music professional directory</p><h1 className="text-4xl md:text-6xl font-bold mt-2">Find musicians, creators & production professionals</h1><p className="text-slate-400 mt-4">Search singers, instrumentalists, composers, engineers, technical directors, tour crew, managers and more.</p>{role&&<Badge className="mt-4" variant="secondary">Filtered by: {role}</Badge>}
    <form onSubmit={submit} className="grid md:grid-cols-[1.3fr_1fr_auto] gap-3 mt-8"><label htmlFor="public-talent-query" className="sr-only">Search professionals</label><Input id="public-talent-query" value={q} onChange={e=>setQ(e.target.value)} placeholder="Tabla, playback singer, DiGiCo, composer…" className="bg-white/5 border-white/15"/><label htmlFor="public-talent-location" className="sr-only">Professional location</label><Input id="public-talent-location" value={location} onChange={e=>setLocation(e.target.value)} placeholder="City or region" className="bg-white/5 border-white/15"/><Button disabled={loading}><Search size={16} className="mr-2"/>Search</Button></form>
    {loading?<p className="text-slate-400 text-center py-16" role="status">Loading professionals…</p>:error?<div className="text-center py-16"><p className="text-rose-300">{error}</p><Button variant="outline" className="mt-4" onClick={load}>Try again</Button></div>:items.length?<div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4 mt-8">{items.map(c=><Link to={`/professionals/${c.id}`} key={c.id}><Card className="h-full bg-white/[.05] border-white/10 hover:bg-white/[.075]"><CardContent className="p-5"><div className="flex items-center gap-2"><h2 className="text-xl font-semibold">{c.name}</h2><DemoBadge show={c.demo}/>{c.verified&&<ShieldCheck size={16} className="text-emerald-300"/>}</div><p className="text-violet-300 mt-1">{c.headline||'Music professional'}</p>{c.location&&<p className="flex text-sm text-slate-400 mt-3"><MapPin size={15} className="mr-1"/>{c.location}</p>}<p className="text-sm text-slate-300 mt-3 line-clamp-3">{c.bio||'Professional profile on Verse.'}</p><div className="flex flex-wrap gap-2 mt-4">{[...(c.roles||[]),...(c.instruments||[])].slice(0,5).map((x:string)=><Badge variant="secondary" key={x}>{x}</Badge>)}</div></CardContent></Card></Link>)}</div>:<div className="text-center py-16"><p className="text-slate-500">No matching public professionals yet.</p><div className="flex flex-wrap justify-center gap-3 mt-5"><Link to="/auth/jobseeker"><Button>List your profile</Button></Link><Link to="/auth/employer"><Button variant="outline">Start hiring</Button></Link></div></div>}
  </main></div>;
}
