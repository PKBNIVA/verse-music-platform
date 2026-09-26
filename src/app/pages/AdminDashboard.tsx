import {useCallback,useEffect,useMemo,useState} from 'react';
import {ShieldCheck,Users,Briefcase,FileText,Activity,LogOut,Check,X,Ban,Undo2,Flag,UserCheck,RefreshCw,AlertTriangle,Gift,Search} from 'lucide-react';
import {Link,useNavigate} from 'react-router';
import {toast} from 'sonner';
import {apiGet,apiPatch,apiPost} from '../lib/api';
import {useAuth} from '../lib/authContext';
import {usePageMeta} from '../components/PageMeta';
import {Button} from '../components/ui/button';
import {Card,CardContent,CardHeader,CardTitle} from '../components/ui/card';
import {Tabs,TabsContent,TabsList,TabsTrigger} from '../components/ui/tabs';
import {Badge} from '../components/ui/badge';
import {Input} from '../components/ui/input';
import {Label} from '../components/ui/label';
import {Textarea} from '../components/ui/textarea';
import {Dialog,DialogContent,DialogDescription,DialogFooter,DialogHeader,DialogTitle} from '../components/ui/dialog';
import DemoDataPanel from '../components/admin/DemoDataPanel';
import {SignInDoctor} from '../components/admin/SignInDoctor';

// Each panel loads independently: one failing endpoint must not blank the whole console.
const SOURCES={
  stats:['/admin/stats',(d:any)=>d?.stats||{}],
  users:['/admin/users',(d:any)=>d?.users||[]],
  jobs:['/admin/jobs',(d:any)=>d?.jobs||[]],
  reviews:['/admin/reviews',(d:any)=>d?.reviews||[]],
  verifications:['/admin/verifications',(d:any)=>d?.requests||[]],
  reports:['/admin/reports',(d:any)=>d?.reports||[]],
  logs:['/admin/audit',(d:any)=>d?.logs||[]],
  subscriptions:['/admin/subscriptions',(d:any)=>d?.subscriptions||[]],
  bookings:['/admin/bookings',(d:any)=>d?.bookings||[]],
  attempts:['/admin/billing-attempts',(d:any)=>d?.attempts||[]],
} as const;
type Source=keyof typeof SOURCES;
type Data={stats:any}&Record<Exclude<Source,'stats'>,any[]>;
const EMPTY:Data={stats:{},users:[],jobs:[],reviews:[],verifications:[],reports:[],logs:[],subscriptions:[],bookings:[],attempts:[]};
const GRANTABLE_PLANS=[['pro','Pro'],['studio','Studio'],['enterprise','Enterprise']] as const;
const RECONCILABLE=new Set(['pending','ambiguous','failed']);
const USER_PAGE=150;

type Confirm={title:string;description:string;confirmLabel:string;reasonLabel?:string;reasonRequired?:boolean;destructive?:boolean;run:(reason:string)=>Promise<void>};
type Grant={id:string;name:string;email:string};

const date=(value:any,withTime=false)=>{if(!value)return '—';const d=new Date(value);return Number.isNaN(d.getTime())?'—':withTime?d.toLocaleString():d.toLocaleDateString()};
const entityLink=(type:string,id:string)=>type==='Job'||type==='job'?`/opportunities/${id}`:type==='User'||type==='user'?`/professionals/${id}`:type==='Act'||type==='act'?`/acts/${id}`:null;

export default function AdminDashboard(){
  const{user,logout}=useAuth(),nav=useNavigate();
  usePageMeta('Admin · Trust & Operations','Verse moderation, verification, marketplace health and audit.');
  const[data,setData]=useState<Data>(EMPTY);
  const[errors,setErrors]=useState<Partial<Record<Source,string>>>({});
  const[loading,setLoading]=useState(true);
  const[busy,setBusy]=useState<string|null>(null);
  const[confirm,setConfirm]=useState<Confirm|null>(null);
  const[grant,setGrant]=useState<Grant|null>(null);
  const[userQuery,setUserQuery]=useState('');

  const load=useCallback(async()=>{
    setLoading(true);
    const keys=Object.keys(SOURCES) as Source[];
    const settled=await Promise.allSettled(keys.map(k=>apiGet<any>(SOURCES[k][0])));
    const next:any={},nextErrors:Partial<Record<Source,string>>={};
    settled.forEach((result,i)=>{const k=keys[i];if(result.status==='fulfilled')next[k]=(SOURCES[k][1] as (d:any)=>any)(result.value);else nextErrors[k]=result.reason?.message||'Unable to load.'});
    setData(prev=>({...prev,...next}));setErrors(nextErrors);setLoading(false);
  },[]);
  useEffect(()=>{void load()},[load]);

  // Every moderation action goes through here: one in flight at a time, toast on result, then refresh.
  const act=async(key:string,request:()=>Promise<unknown>,message:string)=>{
    if(busy)return;setBusy(key);
    try{await request();toast.success(message);await load()}catch(e:any){toast.error(e?.message||'Action failed');throw e}finally{setBusy(null)}
  };
  const patch=(key:string,path:string,body:any,message:string)=>act(key,()=>apiPatch(path,body),message).catch(()=>{});

  const{stats,users,jobs,reviews,verifications,reports,logs,subscriptions,bookings,attempts}=data;
  const pendingJobs=useMemo(()=>jobs.filter(j=>j.status==='pending'),[jobs]);
  const pendingVerifications=useMemo(()=>verifications.filter(v=>v.status==='pending'),[verifications]);
  const openReports=useMemo(()=>reports.filter(r=>r.status==='open'),[reports]);
  const filteredUsers=useMemo(()=>{const q=userQuery.trim().toLowerCase();return q?users.filter(u=>`${u.name} ${u.email} ${u.role} ${u.status}`.toLowerCase().includes(q)):users},[users,userQuery]);
  const failedCount=Object.keys(errors).length;

  const Stat=({label,value,icon:I}:{label:string,value:any,icon:any})=><Card className="bg-white/[.055] border-white/10"><CardContent className="p-4 md:p-5 flex items-center gap-4"><div className="p-3 rounded-xl bg-violet-500/10"><I aria-hidden="true" className="text-violet-300"/></div><div><div className="text-2xl font-bold text-white">{errors.stats?'—':value??0}</div><div className="text-sm text-slate-400">{label}</div></div></CardContent></Card>;
  const retry=()=>void load();

  return <div className="min-h-screen bg-slate-950 text-white">
    <header className="border-b border-white/10 sticky top-0 bg-slate-950/95 backdrop-blur z-20"><div className="max-w-[1500px] mx-auto px-4 md:px-6 py-3 md:py-4 flex flex-wrap gap-3 justify-between items-center">
      <div className="flex items-center gap-3 min-w-0"><ShieldCheck aria-hidden="true" className="text-violet-400 shrink-0"/><div className="min-w-0"><div className="font-bold">Verse Trust &amp; Operations</div><div className="hidden sm:block text-xs text-slate-400">Moderation, verification, marketplace health &amp; audit</div></div></div>
      <div className="flex flex-wrap items-center gap-2 text-sm text-slate-300"><span className="hidden lg:inline">{user?.email}</span>
        <Button variant="outline" size="sm" asChild><Link to="/admin/tester">Live Tester</Link></Button>
        <Button variant="outline" size="sm" disabled={busy==='reindex'} onClick={()=>act('reindex',()=>apiPost('/admin/search/reindex'),'Search reindexed').catch(()=>{})}><RefreshCw aria-hidden="true" size={15} className="mr-2"/>Reindex<span className="hidden sm:inline">&nbsp;search</span></Button>
        <Button variant="ghost" size="icon" aria-label="Refresh dashboard" title="Refresh dashboard" disabled={loading} onClick={()=>void load()}><RefreshCw aria-hidden="true" size={16} className={loading?'motion-safe:animate-spin':''}/></Button>
        <Button variant="outline" size="icon" aria-label="Sign out" title="Sign out" onClick={async()=>{await logout();nav('/')}}><LogOut aria-hidden="true" size={16}/></Button>
      </div>
    </div></header>
    <main className="max-w-[1500px] mx-auto px-4 md:px-6 py-8">
      <div className="mb-7"><h1 className="text-3xl font-bold">Marketplace health</h1><p className="text-slate-400 mt-1">The admin job is not content approval alone. It is trust, quality, fraud prevention and marketplace liquidity.</p></div>
      {failedCount>0&&!loading&&<div role="alert" className="mb-6 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-amber-400/25 bg-amber-500/10 p-4 text-sm text-amber-100"><span className="flex items-center gap-2"><AlertTriangle aria-hidden="true" size={16}/>{failedCount} of {Object.keys(SOURCES).length} panels could not load. The rest of the console is up to date.</span><Button size="sm" variant="outline" onClick={()=>void load()}>Retry</Button></div>}
      <div className="grid grid-cols-2 lg:grid-cols-4 xl:grid-cols-7 gap-3 md:gap-4 mb-8"><Stat label="Users" value={stats.users} icon={Users}/><Stat label="Live opportunities" value={stats.liveJobs} icon={Briefcase}/><Stat label="Applications" value={stats.applications} icon={FileText}/><Stat label="Hires" value={stats.hires} icon={UserCheck}/><Stat label="Open reports" value={stats.openReports} icon={Flag}/><Stat label="Bookings" value={stats.bookings} icon={Activity}/><Stat label="Paid plans" value={stats.activeSubscriptions} icon={ShieldCheck}/></div>
      <Tabs defaultValue="queue"><TabsList className="bg-white/5 border border-white/10 flex flex-wrap justify-start h-auto w-full md:w-auto gap-1 p-1">
        <TabsTrigger value="queue" className="flex-none">Opportunity queue ({errors.jobs?'!':pendingJobs.length})</TabsTrigger>
        <TabsTrigger value="verification" className="flex-none">Verification ({errors.verifications?'!':pendingVerifications.length})</TabsTrigger>
        <TabsTrigger value="reports" className="flex-none">Reports ({errors.reports?'!':openReports.length})</TabsTrigger>
        <TabsTrigger value="users" className="flex-none">Users</TabsTrigger>
        <TabsTrigger value="reviews" className="flex-none">Reviews ({errors.reviews?'!':reviews.filter(r=>r.status==='pending').length})</TabsTrigger>
        <TabsTrigger value="signin" className="flex-none">Sign-in doctor</TabsTrigger>
        <TabsTrigger value="commerce" className="flex-none">Commerce</TabsTrigger>
        <TabsTrigger value="audit" className="flex-none">Audit</TabsTrigger>
        <TabsTrigger value="demo" className="flex-none">Demo data</TabsTrigger>
      </TabsList>

      <TabsContent value="queue" className="space-y-3 mt-5"><Panel error={errors.jobs} onRetry={retry} loading={loading}>{pendingJobs.length===0&&<Empty text="No opportunities waiting for review."/>}{pendingJobs.map(j=><Card key={j.id} className="bg-white/[.05] border-white/10"><CardContent className="p-5"><div className="flex flex-col xl:flex-row gap-5 justify-between"><div className="max-w-4xl min-w-0"><div className="flex flex-wrap items-center gap-2"><Badge variant="secondary">{j.opportunity_kind||'job'}</Badge><h2 className="font-semibold text-lg break-words">{j.title}</h2>{j.employerVerified&&<Badge className="bg-emerald-500/15 text-emerald-300">Verified employer</Badge>}</div><div className="text-sm text-slate-400 mt-2">{[j.company,j.location,j.workplace,j.type].filter(Boolean).join(' · ')}</div><p className="text-sm text-slate-300 mt-3 line-clamp-3">{j.description}</p><div className="mt-3 text-sm"><span className="text-slate-400">Compensation:</span> {j.salary||`${j.currency||'INR'} ${j.compensation_min||'?'}–${j.compensation_max||'?'}`}</div>{j.moderation_note&&<div className="mt-3 rounded-lg bg-amber-500/10 border border-amber-400/20 p-3 text-sm text-amber-200">Automated review hints: {j.moderation_note}</div>}</div><div className="flex xl:flex-col gap-2 shrink-0"><Button size="sm" disabled={!!busy} onClick={()=>patch(`job:${j.id}`,`/admin/jobs/${j.id}`,{status:'published'},'Opportunity published')}><Check aria-hidden="true" size={15} className="mr-1"/>Approve</Button><Button size="sm" variant="outline" disabled={!!busy} onClick={()=>setConfirm({title:`Reject “${j.title}”?`,description:'The employer is notified and sees your reason. Be specific about what needs to change.',confirmLabel:'Reject opportunity',reasonLabel:'Reason / changes needed',reasonRequired:true,destructive:true,run:note=>act(`job:${j.id}`,()=>apiPatch(`/admin/jobs/${j.id}`,{status:'rejected',note}),'Opportunity rejected')})}><X aria-hidden="true" size={15} className="mr-1"/>Reject</Button></div></div></CardContent></Card>)}</Panel></TabsContent>

      <TabsContent value="verification" className="space-y-3 mt-5"><Panel error={errors.verifications} onRetry={retry} loading={loading}>{pendingVerifications.length===0&&<Empty text="No verification requests waiting."/>}{pendingVerifications.map(v=><Card key={v.id} className="bg-white/[.05] border-white/10"><CardContent className="p-5 flex flex-col md:flex-row justify-between gap-4"><div className="min-w-0"><h2 className="font-semibold">{v.companyName||v.name}</h2><div className="text-sm text-slate-400 break-words">{v.email} · {v.role} · {v.kind}</div>{v.note&&<p className="text-sm text-slate-300 mt-3">{v.note}</p>}{v.evidence_url&&<a className="text-sm text-sky-300 mt-2 inline-block" href={v.evidence_url} target="_blank" rel="noreferrer noopener">Open evidence ↗<span className="sr-only"> (opens in a new tab)</span></a>}</div><div className="flex gap-2 shrink-0"><Button size="sm" disabled={!!busy} onClick={()=>patch(`ver:${v.id}`,`/admin/verifications/${v.id}`,{status:'approved'},'Verification approved')}>Approve</Button><Button size="sm" variant="outline" disabled={!!busy} onClick={()=>patch(`ver:${v.id}`,`/admin/verifications/${v.id}`,{status:'rejected'},'Verification rejected')}>Reject</Button></div></CardContent></Card>)}</Panel></TabsContent>

      <TabsContent value="reports" className="space-y-3 mt-5"><Panel error={errors.reports} onRetry={retry} loading={loading}>{openReports.length===0&&<Empty text="No open safety reports."/>}{openReports.map(r=>{const href=entityLink(r.entity_type,r.entity_id);return <Card key={r.id} className="bg-white/[.05] border-white/10"><CardContent className="p-5 flex flex-col md:flex-row justify-between gap-4"><div className="min-w-0"><h2 className="font-semibold break-all">{r.entity_type} · {href?<Link className="text-sky-300 underline underline-offset-4" to={href} target="_blank">{r.entity_id}</Link>:r.entity_id}</h2><div className="text-sm text-rose-300 mt-1">{r.reason}</div>{r.details&&<p className="text-sm text-slate-300 mt-2">{r.details}</p>}<p className="text-xs text-slate-400 mt-2">Reported by {r.reporterName||'Unknown'} · {date(r.created_at,true)}</p></div><div className="flex gap-2 shrink-0"><Button size="sm" disabled={!!busy} onClick={()=>patch(`rep:${r.id}`,`/admin/reports/${r.id}`,{status:'resolved'},'Report resolved')}>Resolve</Button><Button size="sm" variant="outline" disabled={!!busy} onClick={()=>patch(`rep:${r.id}`,`/admin/reports/${r.id}`,{status:'dismissed'},'Report dismissed')}>Dismiss</Button></div></CardContent></Card>})}</Panel></TabsContent>

      <TabsContent value="users" className="space-y-3 mt-5"><Panel error={errors.users} onRetry={retry} loading={loading}><div className="flex flex-col sm:flex-row sm:items-center gap-3"><div className="relative flex-1 max-w-md"><Label htmlFor="admin-user-filter" className="sr-only">Filter users</Label><Search aria-hidden="true" size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400"/><Input id="admin-user-filter" value={userQuery} onChange={e=>setUserQuery(e.target.value)} placeholder="Filter by name, email, role or status" className="pl-9 bg-white/5 border-white/15"/></div><p className="text-sm text-slate-400" aria-live="polite">{filteredUsers.length} of {users.length} users{filteredUsers.length>USER_PAGE?` · showing first ${USER_PAGE}`:''}</p></div>
        {filteredUsers.length===0&&<Empty text={users.length?'No users match this filter.':'No users yet.'}/>}
        {filteredUsers.slice(0,USER_PAGE).map(u=><Card key={u.id} className="bg-white/[.05] border-white/10"><CardContent className="p-4 md:p-5 flex flex-col sm:flex-row justify-between sm:items-center gap-4"><div className="min-w-0"><div className="flex items-center gap-2"><h2 className="font-semibold break-words">{u.name}</h2>{u.verified&&<ShieldCheck size={15} className="text-emerald-300" aria-label="Verified"/>}</div><div className="text-sm text-slate-400 break-all">{u.email} · {u.role} · joined {date(u.createdAt)}</div><Badge className="mt-2">{u.status}</Badge></div>{u.role!=='admin'&&<div className="flex flex-wrap gap-2 shrink-0"><Button size="sm" variant="secondary" disabled={!!busy} onClick={()=>setGrant({id:u.id,name:u.name,email:u.email})}><Gift aria-hidden="true" size={15} className="mr-1"/>Grant plan</Button>{u.status==='active'?<Button size="sm" variant="outline" disabled={!!busy} onClick={()=>setConfirm({title:`Suspend ${u.name}?`,description:`${u.email} will be signed out everywhere and cannot sign in until restored.`,confirmLabel:'Suspend user',destructive:true,run:()=>act(`user:${u.id}`,()=>apiPatch(`/admin/users/${u.id}`,{status:'suspended'}),'User suspended')})}><Ban aria-hidden="true" size={15} className="mr-1"/>Suspend</Button>:<Button size="sm" disabled={!!busy} onClick={()=>patch(`user:${u.id}`,`/admin/users/${u.id}`,{status:'active'},'User restored')}><Undo2 aria-hidden="true" size={15} className="mr-1"/>Restore</Button>}</div>}</CardContent></Card>)}</Panel></TabsContent>

      <TabsContent value="reviews" className="space-y-3 mt-5"><Panel error={errors.reviews} onRetry={retry} loading={loading}>{reviews.length===0&&<Empty text="No reviews yet."/>}{reviews.map(r=><Card key={r.id} className="bg-white/[.05] border-white/10"><CardContent className="p-5"><div className="flex flex-col sm:flex-row justify-between gap-4"><div className="min-w-0"><h2 className="font-semibold">{r.authorName} → {r.employerName} · {r.rating}/5</h2><p className="text-sm text-slate-300 mt-2 break-words">{r.body}</p><Badge className="mt-2">{r.status}</Badge></div>{r.status==='pending'&&<div className="flex gap-2 shrink-0"><Button size="sm" disabled={!!busy} onClick={()=>patch(`rev:${r.id}`,`/admin/reviews/${r.id}`,{status:'published'},'Review published')}>Publish</Button><Button size="sm" variant="outline" disabled={!!busy} onClick={()=>patch(`rev:${r.id}`,`/admin/reviews/${r.id}`,{status:'rejected'},'Review rejected')}>Reject</Button></div>}</div></CardContent></Card>)}</Panel></TabsContent>

      <TabsContent value="signin" className="mt-5"><SignInDoctor/></TabsContent>

      <TabsContent value="commerce" className="mt-5 grid xl:grid-cols-2 gap-5">
        <Card className="bg-white/[.05] border-white/10 xl:col-span-2"><CardHeader><CardTitle><h2>Billing attempts</h2></CardTitle><p className="text-sm text-slate-400">Provider calls that did not finish cleanly. Reconcile asks Razorpay for the real state and attaches it.</p></CardHeader><CardContent className="space-y-3 max-h-[520px] overflow-auto focus-visible:outline focus-visible:outline-2 focus-visible:outline-violet-400" tabIndex={0} role="region" aria-label="Billing attempts"><Panel error={errors.attempts} onRetry={retry} loading={loading}>{attempts.map(a=>{const canReconcile=RECONCILABLE.has(a.state)&&!!a.provider_resource_id;return <div key={a.id} className="border-b border-white/10 pb-3 flex flex-col md:flex-row md:items-center justify-between gap-3"><div className="min-w-0"><div className="flex flex-wrap items-center gap-2"><b>{a.operation}</b><Badge className={a.state==='succeeded'?'bg-emerald-500/15 text-emerald-300':a.state==='failed'?'bg-rose-500/15 text-rose-300':'bg-amber-500/15 text-amber-200'}>{a.state}</Badge></div><div className="text-xs text-slate-400 mt-1 break-all">{a.email} · {a.provider} · {a.provider_resource_id||'no provider id'} · {date(a.created_at,true)}</div>{a.error_message&&<div className="text-xs text-rose-300 mt-1">{a.error_code?`${a.error_code}: `:''}{a.error_message}</div>}</div>{RECONCILABLE.has(a.state)&&<Button size="sm" variant="outline" disabled={!!busy||!canReconcile} title={canReconcile?undefined:'No provider id was recorded, so there is nothing to look up.'} onClick={()=>act(`bill:${a.id}`,()=>apiPost(`/admin/billing-attempts/${a.id}/reconcile`),'Billing attempt reconciled').catch(()=>{})}><RefreshCw aria-hidden="true" size={14} className="mr-1"/>{busy===`bill:${a.id}`?'Reconciling…':'Reconcile'}</Button>}</div>})}{!attempts.length&&<Empty text="No billing attempts recorded."/>}</Panel></CardContent></Card>
        <Card className="bg-white/[.05] border-white/10"><CardHeader><CardTitle><h2>Subscriptions</h2></CardTitle></CardHeader><CardContent className="space-y-3 max-h-[650px] overflow-auto focus-visible:outline focus-visible:outline-2 focus-visible:outline-violet-400" tabIndex={0} role="region" aria-label="Subscriptions"><Panel error={errors.subscriptions} onRetry={retry} loading={loading}>{subscriptions.map(s=><div key={s.id} className="border-b border-white/10 pb-3"><div className="flex justify-between gap-3"><div className="min-w-0"><b>{s.name}</b><div className="text-xs text-slate-400 break-all">{s.email}</div></div><Badge>{s.plan_code} · {s.status}</Badge></div><div className="text-xs text-slate-400 mt-2">{s.provider} · created {date(s.created_at)}{s.current_period_end?` · until ${date(s.current_period_end)}`:''}</div></div>)}{!subscriptions.length&&<Empty text="No paid subscription history."/>}</Panel></CardContent></Card>
        <Card className="bg-white/[.05] border-white/10"><CardHeader><CardTitle><h2>Booking operations</h2></CardTitle></CardHeader><CardContent className="space-y-3 max-h-[650px] overflow-auto focus-visible:outline focus-visible:outline-2 focus-visible:outline-violet-400" tabIndex={0} role="region" aria-label="Booking operations"><Panel error={errors.bookings} onRetry={retry} loading={loading}>{bookings.map(b=><div key={b.id} className="border-b border-white/10 pb-3"><div className="flex justify-between gap-3"><div className="min-w-0"><b>{b.actName}</b><div className="text-xs text-slate-400">{b.requesterName} → {b.actOwner}</div></div><Badge>{b.status}</Badge></div><div className="text-xs text-slate-400 mt-2">{[b.event_type,b.event_date,b.city].filter(Boolean).join(' · ')}{Number(b.paidAmount)>0?` · paid ${b.currency||'INR'} ${Number(b.paidAmount).toLocaleString()}`:''}</div></div>)}{!bookings.length&&<Empty text="No bookings yet."/>}</Panel></CardContent></Card>
      </TabsContent>

      <TabsContent value="demo" className="mt-5"><DemoDataPanel/></TabsContent>

      <TabsContent value="audit" className="mt-5"><Card className="bg-white/[.05] border-white/10"><CardHeader><CardTitle><h2>Audit trail</h2></CardTitle></CardHeader><CardContent className="space-y-3 max-h-[700px] overflow-auto focus-visible:outline focus-visible:outline-2 focus-visible:outline-violet-400" tabIndex={0} role="region" aria-label="Audit trail"><Panel error={errors.logs} onRetry={retry} loading={loading}>{logs.map(l=><div key={l.id} className="border-b border-white/10 pb-3"><div className="text-sm"><b>{l.actorName||'System'}</b> · {l.action}</div><div className="text-xs text-slate-400 mt-1 break-all">{l.entity_type} {l.entity_id} · {date(l.created_at,true)}</div></div>)}{!logs.length&&<Empty text="No audit events yet."/>}</Panel></CardContent></Card></TabsContent></Tabs>
    </main>
    <ConfirmDialog value={confirm} onClose={()=>setConfirm(null)}/>
    <GrantPlanDialog value={grant} busy={!!busy} onClose={()=>setGrant(null)} onGrant={(g,planCode,days)=>act(`grant:${g.id}`,()=>apiPost(`/admin/users/${g.id}/grant-plan`,{planCode,days}),`${planCode} plan granted to ${g.name} for ${days} days`)}/>
  </div>;
}

function ConfirmDialog({value,onClose}:{value:Confirm|null;onClose:()=>void}){
  const[reason,setReason]=useState(''),[pending,setPending]=useState(false);
  useEffect(()=>{setReason('');setPending(false)},[value]);
  const trimmed=reason.trim(),invalid=!!value?.reasonRequired&&trimmed.length<5;
  const submit=async(e:React.FormEvent)=>{e.preventDefault();if(!value||invalid||pending)return;setPending(true);try{await value.run(trimmed);onClose()}catch{setPending(false)}};
  return <Dialog open={!!value} onOpenChange={open=>{if(!open&&!pending)onClose()}}><DialogContent className="bg-slate-950 border-white/15 text-white"><form onSubmit={submit} className="grid gap-4"><DialogHeader><DialogTitle>{value?.title}</DialogTitle><DialogDescription className="text-slate-400">{value?.description}</DialogDescription></DialogHeader>
    {value?.reasonLabel&&<div className="grid gap-2"><Label htmlFor="admin-confirm-reason">{value.reasonLabel}{value.reasonRequired&&<span aria-hidden="true"> *</span>}</Label><Textarea id="admin-confirm-reason" value={reason} onChange={e=>setReason(e.target.value)} required={value.reasonRequired} minLength={value.reasonRequired?5:undefined} maxLength={2000} aria-describedby="admin-confirm-reason-hint" className="bg-white/5 border-white/15 min-h-28" autoFocus/><p id="admin-confirm-reason-hint" className="text-xs text-slate-400">{value.reasonRequired?'At least 5 characters. ':''}Shown to the account owner.</p></div>}
    <DialogFooter><Button type="button" variant="ghost" onClick={onClose} disabled={pending}>Cancel</Button><Button type="submit" variant={value?.destructive?'destructive':'default'} disabled={invalid||pending} aria-busy={pending}>{pending?'Working…':value?.confirmLabel}</Button></DialogFooter></form></DialogContent></Dialog>;
}

function GrantPlanDialog({value,busy,onClose,onGrant}:{value:Grant|null;busy:boolean;onClose:()=>void;onGrant:(g:Grant,planCode:string,days:number)=>Promise<void>}){
  const[plan,setPlan]=useState('pro'),[days,setDays]=useState('30'),[pending,setPending]=useState(false);
  useEffect(()=>{setPlan('pro');setDays('30');setPending(false)},[value]);
  const n=Number(days),valid=/^\d+$/.test(days)&&n>=1&&n<=366;
  const submit=async(e:React.FormEvent)=>{e.preventDefault();if(!value||!valid||pending||busy)return;setPending(true);try{await onGrant(value,plan,n);onClose()}catch{setPending(false)}};
  return <Dialog open={!!value} onOpenChange={open=>{if(!open&&!pending)onClose()}}><DialogContent className="bg-slate-950 border-white/15 text-white"><form onSubmit={submit} className="grid gap-4"><DialogHeader><DialogTitle>Grant a plan to {value?.name}</DialogTitle><DialogDescription className="text-slate-400">{value?.email}. Any current subscription is cancelled and replaced by an internal, unpaid plan.</DialogDescription></DialogHeader>
    <div className="grid sm:grid-cols-2 gap-4"><div className="grid gap-2"><Label htmlFor="admin-grant-plan">Plan</Label><select id="admin-grant-plan" value={plan} onChange={e=>setPlan(e.target.value)} className="h-10 rounded-md bg-slate-900 border border-white/15 px-3">{GRANTABLE_PLANS.map(([code,name])=><option key={code} value={code}>{name}</option>)}</select></div>
    <div className="grid gap-2"><Label htmlFor="admin-grant-days">Days</Label><Input id="admin-grant-days" type="number" inputMode="numeric" min={1} max={366} value={days} onChange={e=>setDays(e.target.value)} aria-invalid={!valid} aria-describedby="admin-grant-days-hint" className="bg-white/5 border-white/15"/><p id="admin-grant-days-hint" className={`text-xs ${valid?'text-slate-400':'text-rose-300'}`}>Whole days, 1–366.</p></div></div>
    <DialogFooter><Button type="button" variant="ghost" onClick={onClose} disabled={pending}>Cancel</Button><Button type="submit" disabled={!valid||pending||busy} aria-busy={pending}>{pending?'Granting…':'Grant plan'}</Button></DialogFooter></form></DialogContent></Dialog>;
}

function Panel({error,onRetry,loading,children}:{error?:string;onRetry:()=>void;loading:boolean;children:React.ReactNode}){return error?<PanelError message={error} onRetry={onRetry} loading={loading}/>:<>{children}</>}
function PanelError({message,onRetry,loading}:{message:string;onRetry:()=>void;loading:boolean}){return <Card className="bg-rose-500/[.06] border-rose-400/20"><CardContent className="p-6 text-center" role="alert"><p className="text-rose-200">This panel could not load: {message}</p><Button size="sm" variant="outline" className="mt-4" disabled={loading} onClick={onRetry}>Try again</Button></CardContent></Card>}
function Empty({text}:{text:string}){return <Card className="bg-white/[.03] border-white/10"><CardContent className="p-10 text-center text-slate-400">{text}</CardContent></Card>}
