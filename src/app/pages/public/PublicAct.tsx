import {useCallback,useEffect,useState} from 'react';
import {Link,useParams} from 'react-router';
import {PublicNav} from '../../components/PublicNav';
import {Card,CardContent} from '../../components/ui/card';
import {Badge} from '../../components/ui/badge';
import {Button} from '../../components/ui/button';
import {apiGet} from '../../lib/api';
import {ShieldCheck} from 'lucide-react';
import {useAuth} from '../../lib/authContext';
import {DemoBadge} from '../../components/DemoBadge';

export default function PublicAct(){const{id}=useParams(),{user}=useAuth();
const bookingPath=user?.role==='jobseeker'?'/jobseeker/book-talent':'/employer/book-talent';
const[a,setA]=useState<any>(),[loading,setLoading]=useState(true),[error,setError]=useState('');
const load=useCallback(async()=>{setLoading(true);setError('');try{const d=await apiGet<any>(`/public/acts/${id}`);setA(d.act)}catch(e:any){setA(undefined);setError(e.message||'Unable to load this act.')}finally{setLoading(false)}},[id]);
useEffect(()=>{void load()},[load]);
if(loading||error)return <div className="min-h-screen bg-slate-950 text-white"><PublicNav/><div className="p-20 text-center">{loading?<p className="text-slate-400" role="status">Loading act…</p>:<div role="alert"><p className="text-rose-300">{error}</p><Button variant="outline" className="mt-4" onClick={()=>void load()}>Try again</Button></div>}</div></div>;
return <div className="min-h-screen bg-slate-950 text-white"><PublicNav/><main className="max-w-5xl mx-auto px-5 py-12"><Card className="bg-white/[.055] border-white/10"><CardContent className="p-8"><div className="flex gap-2 items-center"><Badge>{a.act_type}</Badge><DemoBadge show={a.demo}/>{a.verified&&<ShieldCheck className="text-emerald-300" size={18}/>}</div><h1 className="text-5xl font-bold mt-4">{a.name}</h1><p className="text-violet-300 mt-2">{a.tagline}</p><p className="text-slate-300 mt-6 leading-7">{a.bio}</p><div className="grid md:grid-cols-2 gap-6 mt-8"><div><h2 className="font-semibold">Lineup</h2><div className="mt-3 space-y-2">{a.members?.map((m:any,i:number)=><div key={i} className="p-3 rounded-xl bg-white/5"><b>{m.displayName}</b><div className="text-sm text-slate-400">{m.roleName}{m.instrument?` · ${m.instrument}`:''}</div></div>)}</div></div><div><h2 className="font-semibold">Booking range</h2><p className="text-slate-300 mt-3">{a.currency} {a.min_fee||'—'}{a.max_fee?`–${a.max_fee}`:''} / {a.fee_basis}</p><div className="flex flex-wrap gap-2 mt-5">{a.genres?.map((x:string)=><Badge variant="secondary" key={x}>{x}</Badge>)}</div></div></div><Button className="mt-8" asChild>{user?<Link to={bookingPath}>Request a quote</Link>:<Link to="/auth/employer" state={{from:"/employer/book-talent"}}>Sign in to request a quote</Link>}</Button></CardContent></Card></main></div>}
