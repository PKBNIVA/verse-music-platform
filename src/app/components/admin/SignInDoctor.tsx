import {useState} from 'react';
import {AlertTriangle,CheckCircle2,Info,LogOut,Search,XCircle} from 'lucide-react';
import {toast} from 'sonner';
import {apiGet,apiPost} from '../../lib/api';
import {Button} from '../ui/button';
import {Card,CardContent,CardHeader,CardTitle} from '../ui/card';
import {Input} from '../ui/input';
import {Label} from '../ui/label';
import {Badge} from '../ui/badge';

type Diagnosis={level:'error'|'warn'|'info'|'ok';code:string;message:string};
type Lookup={
  email:string;exists:boolean;emailProviderConfigured?:boolean;diagnosis:Diagnosis[];
  user?:{id:string;name:string;role:string;status:string;emailVerified:boolean;profileComplete:boolean;passwordSet:boolean;createdAt:string;lastLoginAt?:string|null};
  sessions?:{active:number;createdLast7Days:number;cap:number};
  emailTokens?:Array<{purpose:string;createdAt:string;used:boolean;expired:boolean}>;
  recentAuthEvents?:Array<{action:string;at:string;ip?:string}>;
  recentFailedLogins?:{count:number|null;windowMinutes:number};
};

const tone:Record<Diagnosis['level'],{icon:any;cls:string;label:string}>={
  error:{icon:XCircle,cls:'border-rose-400/30 bg-rose-500/10 text-rose-100',label:'Blocker'},
  warn:{icon:AlertTriangle,cls:'border-amber-400/30 bg-amber-500/10 text-amber-100',label:'Warning'},
  info:{icon:Info,cls:'border-sky-400/25 bg-sky-500/10 text-sky-100',label:'Note'},
  ok:{icon:CheckCircle2,cls:'border-emerald-400/25 bg-emerald-500/10 text-emerald-100',label:'OK'},
};
const when=(value?:string|null)=>{if(!value)return 'Never';const d=new Date(value);return Number.isNaN(d.getTime())?'—':d.toLocaleString()};

/** Admin-only: explains why a person cannot sign in, from the account's own records. */
export function SignInDoctor(){
  const[email,setEmail]=useState(''),[result,setResult]=useState<Lookup|null>(null),[error,setError]=useState(''),[loading,setLoading]=useState(false),[revoking,setRevoking]=useState(false);
  const lookup=async(e?:React.FormEvent)=>{e?.preventDefault();const value=email.trim();if(!value||loading)return;setLoading(true);setError('');try{setResult(await apiGet<Lookup>(`/admin/users/lookup?email=${encodeURIComponent(value)}`))}catch(err:any){setResult(null);setError(err?.message||'Lookup failed.')}finally{setLoading(false)}};
  const revoke=async()=>{if(!result?.user||revoking)return;setRevoking(true);try{const d=await apiPost<{revoked:number}>(`/admin/users/${result.user.id}/revoke-sessions`);toast.success(`Signed out of ${d?.revoked??0} session(s)`);await lookup()}catch(err:any){toast.error(err?.message||'Could not revoke sessions')}finally{setRevoking(false)}};
  const u=result?.user;
  return <Card className="bg-white/[.05] border-white/10"><CardHeader><CardTitle><h2>Sign-in doctor</h2></CardTitle><p className="text-sm text-slate-400">Look up an account by email to see why sign-in fails. Lookups are audited; no passwords or tokens are shown.</p></CardHeader><CardContent className="space-y-5">
    <form onSubmit={lookup} className="flex flex-col sm:flex-row gap-3" role="search"><div className="flex-1"><Label htmlFor="signin-doctor-email" className="sr-only">Account email</Label><Input id="signin-doctor-email" type="email" autoComplete="off" value={email} onChange={e=>setEmail(e.target.value)} placeholder="person@example.com" className="bg-white/5 border-white/15"/></div><Button type="submit" disabled={loading||!email.trim()} aria-busy={loading}><Search aria-hidden="true" size={15} className="mr-2"/>{loading?'Checking…':'Diagnose'}</Button></form>
    {error&&<p role="alert" className="text-sm text-rose-300">{error}</p>}
    {result&&<div className="space-y-5" data-testid="signin-doctor-result">
      <ul className="space-y-2" aria-label="Diagnosis">{result.diagnosis.map(d=>{const t=tone[d.level]||tone.info;const I=t.icon;return <li key={d.code} className={`flex gap-3 rounded-lg border p-3 text-sm ${t.cls}`}><I aria-hidden="true" size={17} className="shrink-0 mt-0.5"/><span><span className="sr-only">{t.label}: </span>{d.message}</span></li>})}</ul>
      {u&&<>
        <dl className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">{([
          ['Name',u.name],['Role',u.role],['Status',u.status],['Email verified',u.emailVerified?'Yes':'No'],
          ['Password set',u.passwordSet?'Yes':'No'],['Profile complete',u.profileComplete?'Yes':'No'],['Created',when(u.createdAt)],['Last sign-in',when(u.lastLoginAt)],
          ['Active sessions',`${result.sessions?.active??0} / ${result.sessions?.cap??'—'}`],['Sign-ins (7 days)',String(result.sessions?.createdLast7Days??0)],
          ['Failed attempts',result.recentFailedLogins?.count==null?'Unknown':`${result.recentFailedLogins.count} in ${result.recentFailedLogins.windowMinutes} min`],['Email provider',result.emailProviderConfigured?'Configured':'Not configured'],
        ] as const).map(([k,v])=><div key={k} className="rounded-lg bg-white/[.04] p-3"><dt className="text-xs text-slate-400">{k}</dt><dd className="mt-1 font-medium break-words">{v}</dd></div>)}</dl>
        <div className="grid md:grid-cols-2 gap-4"><div><h3 className="font-semibold text-sm">Recent account events</h3>{result.recentAuthEvents?.length?<ul className="mt-2 space-y-1 text-xs text-slate-300">{result.recentAuthEvents.map((ev,i)=><li key={i}>{when(ev.at)} · {ev.action}{ev.ip?` · ${ev.ip}`:''}</li>)}</ul>:<p className="mt-2 text-xs text-slate-400">No sign-in events recorded.</p>}</div>
        <div><h3 className="font-semibold text-sm">Email links (7 days)</h3>{result.emailTokens?.length?<ul className="mt-2 space-y-1 text-xs text-slate-300">{result.emailTokens.map((t,i)=><li key={i}>{when(t.createdAt)} · {t.purpose.replace('_',' ')} · <Badge variant="secondary">{t.used?'used':t.expired?'expired':'unused'}</Badge></li>)}</ul>:<p className="mt-2 text-xs text-slate-400">No verification or reset emails requested.</p>}</div></div>
        {u.role!=='admin'&&(result.sessions?.active??0)>0&&<Button variant="outline" size="sm" onClick={revoke} disabled={revoking}><LogOut aria-hidden="true" size={15} className="mr-2"/>{revoking?'Signing out…':`Sign out of all ${result.sessions?.active} session(s)`}</Button>}
      </>}
    </div>}
  </CardContent></Card>;
}
