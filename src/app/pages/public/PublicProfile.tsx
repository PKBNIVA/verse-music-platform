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
import {MapPin,ShieldCheck} from 'lucide-react';
import {WorkSamplePlayer} from '../../components/WorkSamplePlayer';

export default function PublicProfile(){const{id}=useParams();
const[d,setD]=useState<any>(),[loading,setLoading]=useState(true),[error,setError]=useState<{message:string;status?:number}|null>(null);
const load=useCallback(async()=>{setLoading(true);setError(null);try{setD(await apiGet<any>(`/public/talent/${encodeURIComponent(id||'')}`))}catch(e:any){setD(undefined);setError({message:e.message||'Unable to load this profile.',status:e.status})}finally{setLoading(false)}},[id]);
useEffect(()=>{void load()},[load]);
const p=d?.professional;usePageMeta(p?.name&&`${p.name}${p.headline?` — ${p.headline}`:''}`,p?(p.bio||`${p.name} on Verse${p.location?`, ${p.location}`:''}.`):undefined);
if(loading||error||!p)return <PublicDetailState loading={loading} error={error||(!loading&&!p?{message:'Not found',status:404}:null)} noun="profile" backTo="/music-professionals" backLabel="Browse professionals" onRetry={()=>void load()}/>;
const c=d.professional;
return <div className="min-h-screen bg-slate-950 text-white"><PublicNav/><main className="max-w-5xl mx-auto px-5 py-12"><Card className="bg-white/[.055] border-white/10"><CardContent className="p-7 md:p-10"><div className="flex items-center gap-3"><h1 className="text-4xl md:text-5xl font-bold break-words">{c.name}</h1><DemoBadge show={c.demo}/>{c.verified&&<ShieldCheck className="text-emerald-300" aria-label="Verified professional"/>}</div><p className="text-xl text-violet-300 mt-2">{c.headline}</p>{c.location&&<p className="text-slate-400 mt-3 flex"><MapPin size={17} className="mr-2"/>{c.location}</p>}<p className="text-slate-300 leading-7 mt-6">{c.bio}</p><div className="grid md:grid-cols-2 gap-6 mt-8"><div><h2 className="font-semibold">Roles & instruments</h2><div className="flex flex-wrap gap-2 mt-3">{[...(c.roles||[]),...(c.instruments||[])].map((x:string)=><Badge key={x}>{x}</Badge>)}</div></div><div><h2 className="font-semibold">Capabilities</h2><div className="text-sm text-slate-300 mt-3 space-y-1">{c.remoteRecording&&<div>Remote recording ready</div>}{c.sightReading&&<div>Sight-reading</div>}{c.travelsNationally&&<div>Travels nationally</div>}{c.passportReady&&<div>Passport / international touring ready</div>}</div></div></div>{c.credits?.length>0&&<div className="mt-8"><h2 className="font-semibold">Selected credits</h2><div className="mt-3 space-y-2 text-sm text-slate-300">{c.credits.map((x:string)=><div key={x}>• {x}</div>)}</div></div>}<div className="mt-8"><h2 className="font-semibold">Work samples</h2>{d.portfolio?.length?<div className="mt-3 grid md:grid-cols-2 gap-3">{d.portfolio.map((x:any)=><WorkSamplePlayer key={x.id} sample={x}/>)}</div>:<p className="mt-3 text-sm text-slate-400">No public work samples yet.</p>}</div><Button className="mt-8" asChild><Link to="/auth/employer" state={{from:'/employer/candidates'}}>Sign in to hire or message</Link></Button></CardContent></Card></main></div>}
