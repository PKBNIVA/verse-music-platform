import {DemoBadge} from '../../components/DemoBadge';
import {useCallback,useEffect,useState} from 'react';
import {Link,useParams} from 'react-router';
import {PublicNav} from '../../components/PublicNav';
import {PublicDetailState} from '../../components/PublicDetailState';
import {usePageMeta} from '../../components/PageMeta';
import {Card,CardContent} from '../../components/ui/card';
import {Badge} from '../../components/ui/badge';
import {Button} from '../../components/ui/button';
import {apiGet} from '../../lib/api';
import {ShieldCheck} from 'lucide-react';
import {useAuth} from '../../lib/authContext';

export default function PublicAct(){const{id}=useParams(),{user}=useAuth();
const[a,setA]=useState<any>(),[loading,setLoading]=useState(true),[error,setError]=useState<{message:string;status?:number}|null>(null);
const load=useCallback(async()=>{setLoading(true);setError(null);try{const d=await apiGet<any>(`/public/acts/${encodeURIComponent(id||'')}`);setA(d.act)}catch(e:any){setA(undefined);setError({message:e.message||'Unable to load this act.',status:e.status})}finally{setLoading(false)}},[id]);
useEffect(()=>{void load()},[load]);
usePageMeta(a?.name&&`${a.name} — book ${a.act_type||'live act'}`,a?[a.tagline,a.bio].filter(Boolean).join(' ')||`Request a quote from ${a.name} on Verse.`:undefined);
if(loading||error||!a)return <PublicDetailState loading={loading} error={error||(!loading&&!a?{message:'Not found',status:404}:null)} noun="act" backTo="/book-music" backLabel="Browse bookable acts" onRetry={()=>void load()}/>;
// Carry the act into the booking flow so the requester lands on the right enquiry.
const actQuery=`?act=${encodeURIComponent(a.id??id??'')}`;
const bookingPath=`${user?.role==='jobseeker'?'/jobseeker':'/employer'}/book-talent${actQuery}`;
return <div className="min-h-screen bg-slate-950 text-white"><PublicNav/><main className="max-w-5xl mx-auto px-5 py-12"><Card className="bg-white/[.055] border-white/10"><CardContent className="p-6 md:p-8"><div className="flex gap-2 items-center"><Badge>{a.act_type}</Badge><DemoBadge show={a.demo}/>{a.verified&&<ShieldCheck className="text-emerald-300" size={18} aria-label="Verified act"/>}</div><h1 className="text-4xl md:text-5xl font-bold mt-4 break-words">{a.name}</h1>{a.tagline&&<p className="text-violet-300 mt-2">{a.tagline}</p>}<p className="text-slate-300 mt-6 leading-7">{a.bio}</p><div className="grid md:grid-cols-2 gap-6 mt-8"><div><h2 className="font-semibold">Lineup</h2><div className="mt-3 space-y-2">{a.members?.length?a.members.map((m:any,i:number)=><div key={i} className="p-3 rounded-xl bg-white/5"><b>{m.displayName}</b><div className="text-sm text-slate-400">{m.roleName}{m.instrument?` · ${m.instrument}`:''}</div></div>):<p className="text-sm text-slate-400">Lineup shared on request.</p>}</div></div><div><h2 className="font-semibold">Booking range</h2><p className="text-slate-300 mt-3">{a.min_fee||a.max_fee?`${a.currency||'INR'} ${a.min_fee||'—'}${a.max_fee?`–${a.max_fee}`:''}${a.fee_basis?` / ${a.fee_basis}`:''}`:'Quote on request'}</p><div className="flex flex-wrap gap-2 mt-5">{a.genres?.map((x:string)=><Badge variant="secondary" key={x}>{x}</Badge>)}</div></div></div><Button className="mt-8" asChild>{user&&user.role!=='admin'?<Link to={bookingPath}>Request a quote</Link>:<Link to="/auth/employer" state={{from:`/employer/book-talent${actQuery}`}}>Sign in to request a quote</Link>}</Button></CardContent></Card></main></div>}
