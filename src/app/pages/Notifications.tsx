import {useEffect,useState} from 'react';
import {Navigation} from '../components/Navigation';
import {apiGet,apiPatch} from '../lib/api';
import {useAuth} from '../lib/authContext';
import {Card,CardContent} from '../components/ui/card';
import {Button} from '../components/ui/button';
import {Bell,CheckCircle2} from 'lucide-react';
import {Link} from 'react-router';
import {toast} from 'sonner';

export default function Notifications(){const{user}=useAuth();
const[items,setItems]=useState<any[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState('');
const load=async()=>{setLoading(true);setError('');try{const d=await apiGet<any>('/notifications');setItems(d.notifications||[])}catch(e:any){setError(e.message||'Unable to load notifications.')}finally{setLoading(false)}};
useEffect(()=>{void load()},[]);
const destination=(link:string)=>{const base=user?.role==='employer'?'/employer':'/jobseeker';
if(link==='/hiring/applicants')return user?.role==='employer'?'/employer/applications':'/jobseeker/hiring/applicants';
if(link==='/bookings')return `${base}/bookings`;
if(link==='/urgent-requests')return `${base}/urgent`;
return link};
async function read(n:any){if(n.readAt)return;const readAt=new Date().toISOString();setItems(xs=>xs.map(x=>x.id===n.id?{...x,readAt}:x));try{await apiPatch(`/notifications/${n.id}`,{})}catch(e:any){setItems(xs=>xs.map(x=>x.id===n.id?{...x,readAt:null}:x));toast.error(e.message||'Unable to mark notification as read')}}return <div className="min-h-screen bg-slate-950 text-white"><Navigation/><main className="max-w-4xl mx-auto px-6 pt-28 pb-16"><h1 className="text-4xl font-bold">Notifications</h1><p className="text-slate-400 mt-2 mb-7">Hiring updates, moderation, verification and messages.</p><div className="space-y-3">{loading?<div className="text-slate-400 text-center py-12" role="status">Loading notifications…</div>:error?<div className="text-center py-12" role="alert"><p className="text-rose-300">{error}</p><Button variant="outline" className="mt-4" onClick={()=>void load()}>Try again</Button></div>:items.length===0?<div className="text-slate-500 text-center py-12">No notifications yet.</div>:items.map(n=><Card key={n.id} onClick={()=>void read(n)} className={`${n.readAt?'bg-white/[.035]':'bg-violet-500/[.08]'} border-white/10 cursor-pointer`}><CardContent className="p-5 flex gap-4"><div className="mt-1">{n.readAt?<CheckCircle2 size={18} className="text-slate-600"/>:<Bell size={18} className="text-violet-300"/>}</div><div className="flex-1"><div className="font-semibold">{n.title}</div>{n.body&&<p className="text-sm text-slate-400 mt-1">{n.body}</p>}<div className="flex justify-between gap-4 mt-2"><span className="text-xs text-slate-600">{new Date(n.createdAt).toLocaleString()}</span>{n.link&&<Link to={destination(n.link)} className="text-xs text-violet-300">Open</Link>}</div></div></CardContent></Card>)}</div></main></div>}
