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
import {MapPin,ShieldCheck,Wallet,CalendarDays} from 'lucide-react';

export default function PublicOpportunity(){const{id}=useParams();
const[j,setJ]=useState<any>(),[loading,setLoading]=useState(true),[error,setError]=useState<{message:string;status?:number}|null>(null);
const load=useCallback(async()=>{setLoading(true);setError(null);try{const d=await apiGet<any>(`/jobs/${encodeURIComponent(id||'')}`);setJ(d.job)}catch(e:any){setJ(undefined);setError({message:e.message||'Unable to load this opportunity.',status:e.status})}finally{setLoading(false)}},[id]);
useEffect(()=>{void load()},[load]);
usePageMeta(j?.title&&`${j.title}${j.company?` at ${j.company}`:''}`,j?`${j.opportunity_kind||'Opportunity'} in ${j.location||'India'}. ${j.description||''}`:undefined);
if(loading||error||!j)return <PublicDetailState loading={loading} error={error||(!loading&&!j?{message:'Not found',status:404}:null)} noun="opportunity" backTo="/music-jobs" backLabel="Browse music jobs" onRetry={()=>void load()}/>;
return <div className="min-h-screen bg-slate-950 text-white"><PublicNav/><main className="max-w-5xl mx-auto px-5 py-12"><Card className="bg-white/[.055] border-white/10"><CardContent className="p-7 md:p-10"><div className="flex flex-wrap gap-2"><Badge>{j.opportunity_kind}</Badge><DemoBadge show={j.demo}/>{j.employerVerified&&<Badge className="bg-emerald-500/10 text-emerald-300"><ShieldCheck size={13} className="mr-1"/>Verified hiring party</Badge>}</div><h1 className="text-4xl md:text-6xl font-bold mt-4 break-words">{j.title}</h1><p className="text-xl text-violet-300 mt-2">{j.company}</p><div className="grid sm:grid-cols-3 gap-3 mt-7 text-sm text-slate-300"><span className="flex gap-2"><MapPin size={17}/>{j.location}</span><span className="flex gap-2"><Wallet size={17}/>{j.salary||`${j.currency||'INR'} ${j.compensation_min||''}${j.compensation_max?`–${j.compensation_max}`:''}`}</span><span className="flex gap-2"><CalendarDays size={17}/>{j.application_deadline?`Apply by ${j.application_deadline}`:'Open until filled'}</span></div><div className="mt-8 pt-7 border-t border-white/10"><h2 className="text-xl font-semibold">About the opportunity</h2><p className="whitespace-pre-wrap leading-7 text-slate-300 mt-3">{j.description}</p>{j.requirements&&<><h2 className="text-xl font-semibold mt-8">Requirements</h2><p className="whitespace-pre-wrap leading-7 text-slate-300 mt-3">{j.requirements}</p></>}</div><div className="flex flex-wrap gap-2 mt-7">{j.skills?.map((x:string)=><Badge key={x} variant="outline">{x}</Badge>)}</div><Button size="lg" className="mt-8" asChild><Link to="/auth/jobseeker" state={{from:`/jobseeker/jobs/${encodeURIComponent(String(j.id??id))}`}}>Sign in to apply</Link></Button></CardContent></Card><p className="text-xs text-slate-500 mt-5">Never pay private application or audition fees. Verse listings can be reported after sign-in.</p></main></div>}
