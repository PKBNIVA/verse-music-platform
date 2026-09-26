import {useEffect,useState} from 'react';
import {Link,useNavigate,useParams} from 'react-router';
import {Navigation} from '../components/Navigation';
import {Card,CardContent} from '../components/ui/card';
import {Button} from '../components/ui/button';
import {Textarea} from '../components/ui/textarea';
import {Badge} from '../components/ui/badge';
import {apiDelete,apiGet,apiPost} from '../lib/api';
import {useAuth} from '../lib/authContext';
import {toast} from 'sonner';
import {Bookmark,BookmarkCheck,Flag,MapPin,ShieldCheck,CalendarDays,Wallet,BriefcaseBusiness,MessageSquare,Send} from 'lucide-react';

const title=(x:string)=>String(x||'').replace(/(^|\s)\S/g,m=>m.toUpperCase());

export default function JobDetails(){const{id}=useParams(),nav=useNavigate(),{user}=useAuth();
const[job,setJob]=useState<any>(),[cover,setCover]=useState(''),[answers,setAnswers]=useState<Record<number,string>>({}),[busy,setBusy]=useState(false),[loadError,setLoadError]=useState('');
const load=()=>{setLoadError('');return apiGet<any>(`/jobs/${id}`).then(d=>{if(!d?.job)throw new Error('Opportunity not found');setJob(d.job)}).catch((e:any)=>setLoadError(e?.message||'This opportunity could not be loaded.'))};
useEffect(()=>{setJob(undefined);load()},[id]);
const backTo=user?.role==='employer'?'/employer':'/jobseeker/jobs';
async function messageEmployer(){try{const d=await apiPost<any>('/conversations',{jobId:id});
nav(`/jobseeker/messages?conversation=${d.conversation.id}`)}catch(e:any){toast.error(e.message)}}async function apply(){setBusy(true);
try{await apiPost(`/jobs/${id}/apply`,{coverLetter:cover,screeningAnswers:(job.screeningQuestions||[]).map((q:string,i:number)=>`${q} :: ${answers[i]||''}`)});
setJob({...job,applied:true});
toast.success('Application submitted')}catch(e:any){toast.error(e.message)}finally{setBusy(false)}}async function save(){try{job.saved?await apiDelete(`/saved-jobs/${id}`):await apiPost(`/saved-jobs/${id}`);
setJob({...job,saved:!job.saved})}catch(e:any){toast.error(e.message)}}async function report(){const reason=window.prompt('What is wrong with this listing? e.g. asks for payment, misleading terms, unsafe contact request');
if(!reason)return;
try{await apiPost('/reports',{entityType:'job',entityId:id,reason});
toast.success('Report sent to moderation')}catch(e:any){toast.error(e.message)}}if(!job)return <div className="min-h-screen bg-slate-950 text-white">
<Navigation/>
{loadError?<main className="max-w-xl mx-auto px-5 pt-32 pb-16 text-center" role="alert">
<h1 className="text-2xl font-bold">{/not found/i.test(loadError)?'This opportunity is no longer available':'This opportunity could not be loaded'}</h1>
<p className="text-slate-400 mt-3">{/not found/i.test(loadError)?'It may have been filled, closed or removed by the employer.':loadError}</p>
<div className="flex justify-center gap-2 mt-6">{!/not found/i.test(loadError)&&<Button variant="outline" onClick={()=>load()}>Retry</Button>}<Button asChild><Link to={backTo}>Back to opportunities</Link></Button></div>
</main>:<div className="pt-32 text-center text-slate-400">Loading opportunity…</div>}
</div>;
const pay=job.salary||((job.compensation_min||job.compensation_max)?`${job.currency||'INR'} ${job.compensation_min||''}${job.compensation_max?`–${job.compensation_max}`:''}${job.compensation_period?` / ${job.compensation_period}`:''}`:'Not disclosed');
return <div className="min-h-screen bg-slate-950 text-white">
<Navigation/>
<main className="max-w-7xl mx-auto px-5 md:px-6 pt-28 pb-16">
<div className="grid lg:grid-cols-[minmax(0,1fr)_380px] gap-6">
<div className="space-y-5">
<Card className="bg-white/[.055] border-white/10">
<CardContent className="p-6 md:p-8">
<div className="flex flex-wrap gap-2">
<Badge variant="secondary">{title(job.opportunity_kind||'job')}</Badge>{job.employerVerified&&<Badge className="bg-emerald-500/15 text-emerald-300 border-emerald-400/20">
<ShieldCheck size={13} className="mr-1"/>Verified employer</Badge>}{job.fitScore&&<Badge className="bg-sky-500/15 text-sky-200 border-sky-400/20">{job.fitScore}% profile fit</Badge>}</div>
<h1 className="text-3xl md:text-5xl font-bold mt-4 leading-tight">{job.title}</h1>
<p className="text-xl text-violet-300 mt-2">{job.company}</p>
<div className="grid sm:grid-cols-2 gap-3 mt-6 text-sm text-slate-300">
<div className="flex gap-2">
<MapPin size={18} className="text-slate-500"/>{job.location} · {title(job.workplace)}</div>
<div className="flex gap-2">
<BriefcaseBusiness size={18} className="text-slate-500"/>{job.function_area||job.type}</div>
<div className="flex gap-2">
<Wallet size={18} className="text-slate-500"/>{pay}</div>
<div className="flex gap-2">
<CalendarDays size={18} className="text-slate-500"/>{job.application_deadline?`Apply by ${job.application_deadline}`:'Open until filled'}</div>
</div>
</CardContent>
</Card>
<Card className="bg-white/[.055] border-white/10">
<CardContent className="p-6 md:p-8">
<h2 className="text-xl font-semibold">About the opportunity</h2>
<p className="text-slate-300 mt-4 whitespace-pre-wrap leading-7">{job.description}</p>{job.requirements&&<>
<h2 className="text-xl font-semibold mt-8">Requirements</h2>
<p className="text-slate-300 mt-4 whitespace-pre-wrap leading-7">{job.requirements}</p>
</>}<div className="grid sm:grid-cols-2 gap-5 mt-8 pt-6 border-t border-white/10 text-sm">
<div>
<div className="text-slate-500 mb-1">Engagement</div>
<div>{job.type}</div>
</div>
<div>
<div className="text-slate-500 mb-1">Experience level</div>
<div>{title(job.experience_level||'Not specified')}</div>
</div>
<div>
<div className="text-slate-500 mb-1">Genre / repertoire</div>
<div>{job.genre}</div>
</div>
<div>
<div className="text-slate-500 mb-1">Openings</div>
<div>{job.slots||1}</div>
</div>{job.start_date&&<div>
<div className="text-slate-500 mb-1">Start date</div>
<div>{job.start_date}</div>
</div>}{job.duration&&<div>
<div className="text-slate-500 mb-1">Duration</div>
<div>{job.duration}</div>
</div>}</div>{job.skills?.length>0&&<div className="mt-7">
<div className="text-sm text-slate-500 mb-2">Skills</div>
<div className="flex flex-wrap gap-2">{job.skills.map((s:string)=>
<Badge key={s} variant="outline" className="border-white/15 text-slate-300">{s}</Badge>)}</div>
</div>}</CardContent>
</Card>
</div>
<aside className="space-y-4">
<Card className="bg-white/[.06] border-white/10 lg:sticky lg:top-24">
<CardContent className="p-5">
{user?.role==='jobseeker'&&<div className="flex gap-2 mb-5">
<Button variant="outline" className="flex-1" onClick={save}>{job.saved?<BookmarkCheck size={17} className="mr-2"/>:<Bookmark size={17} className="mr-2"/>}{job.saved?'Saved':'Save'}</Button>
<Button variant="ghost" size="icon" aria-label="Report listing" onClick={report}>
<Flag size={17}/>
</Button>
</div>}{user?.role==='jobseeker'&&<>{job.applied?<div className="rounded-xl bg-emerald-500/10 border border-emerald-400/20 p-4 text-emerald-200">
<b>Application submitted</b>
<p className="text-sm mt-1 text-emerald-100/75">Track its status from Applications.</p>
</div>:<>{job.screeningQuestions?.length>0&&<div className="space-y-3 mb-4">
<div className="text-sm font-medium">Screening questions</div>{job.screeningQuestions.map((q:string,i:number)=>
<div key={q}>
<div className="text-xs text-slate-400 mb-1">{q}</div>
<Textarea value={answers[i]||''} onChange={e=>setAnswers({...answers,[i]:e.target.value})} className="min-h-20 bg-black/20 border-white/15"/>
</div>)}</div>}<label className="text-sm font-medium">Short note to the employer <span className="text-slate-500">(optional)</span>
</label>
<Textarea value={cover} onChange={e=>setCover(e.target.value)} placeholder="Why this opportunity fits your work and what relevant proof should they review…" className="mt-2 min-h-32 bg-black/20 border-white/15"/>
<Button className="w-full mt-3" disabled={busy} onClick={apply}>
<Send size={16} className="mr-2"/>{busy?'Applying…':'Apply now'}</Button>
{job.portfolioRequired&&<p className="text-xs text-amber-200/90 mt-2">This opportunity requires at least one portfolio item. <Link to="/jobseeker/portfolio" className="underline">Add work samples</Link></p>}
</>}<Button variant="ghost" className="w-full mt-2" onClick={messageEmployer}>
<MessageSquare size={16} className="mr-2"/>Ask a question</Button>
</>}<div className="text-xs text-slate-500 mt-5 pt-4 border-t border-white/10">
<b className="text-slate-400">Trust note:</b> {user?.role==='jobseeker'?'Never pay an application/audition fee through private channels. Use Report if listing terms change materially or feel unsafe.':'Only publish terms your organization is prepared to honor, and keep applicant communication on Verse.'}</div>
</CardContent>
</Card>
</aside>
</div>
</main>
</div>}
