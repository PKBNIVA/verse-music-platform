import {useEffect,useState} from 'react';
import {Link} from 'react-router';
import {Check,ShieldCheck,Users,CalendarDays,BriefcaseBusiness} from 'lucide-react';
import {Button} from '../components/ui/button';
import {Card,CardContent} from '../components/ui/card';
import {PublicNav} from '../components/PublicNav';
import {usePageMeta} from '../components/PageMeta';
import {apiGet} from '../lib/api';

export type ApiPlan = {code:string;name:string;monthly:number|null;trialDays:number;activePosts:number;seats:number;shortlist:number;bookings:number};

// Mirrors Billing::BillingController::PLANS so the page still renders if the API is unreachable.
// The API is the source of truth: whatever /billing/plans returns replaces these values.
export const FALLBACK_PLANS:ApiPlan[]=[
  {code:'free',name:'Free',monthly:0,trialDays:0,activePosts:1,seats:1,shortlist:20,bookings:2},
  {code:'pro',name:'Pro',monthly:2499,trialDays:14,activePosts:10,seats:2,shortlist:250,bookings:20},
  {code:'studio',name:'Studio',monthly:5999,trialDays:14,activePosts:50,seats:8,shortlist:2000,bookings:100},
  {code:'enterprise',name:'Enterprise',monthly:null,trialDays:0,activePosts:9999,seats:999,shortlist:99999,bookings:9999},
];

const copy:Record<string,{who:string;extras:string[];cta:string;to:string}>={
  free:{who:'For getting started',extras:['Create and receive bookable-act enquiries'],cta:'Create free account',to:'/auth/employer'},
  pro:{who:'For active bands, managers and small teams',extras:['Band builder + structured role hiring','Priority sourcing workflow'],cta:'Start free trial',to:'/auth/employer'},
  studio:{who:'For studios, agencies, labels and production teams',extras:['Higher-volume hiring and booking operations','Advanced workflow capacity'],cta:'Start free trial',to:'/auth/employer'},
  enterprise:{who:'For large labels, festivals and multi-team organizations',extras:['Sales-assisted onboarding','Custom invoicing and controls','Priority support and migration planning'],cta:'Talk to sales',to:'/contact'},
};

const n=(value:number)=>value.toLocaleString('en-IN');
const plural=(value:number,one:string,many:string)=>`${n(value)} ${value===1?one:many}`;
const isCustom=(p:ApiPlan)=>p.monthly==null;

export function planFeatures(p:ApiPlan){
  if(isCustom(p))return ['Custom seats and limits',...(copy[p.code]?.extras||[])];
  return [
    plural(p.activePosts,'active hiring opportunity','active opportunities'),
    plural(p.bookings,'active booking enquiry','active booking enquiries'),
    plural(p.shortlist,'saved talent profile','saved talent profiles'),
    p.seats===1?'1 workspace seat':`${n(p.seats)} team seats`,
    ...(copy[p.code]?.extras||[]),
  ];
}

function price(p:ApiPlan){return isCustom(p)?'Custom':p.monthly===0?'Free':`₹${n(p.monthly!)}`}

export default function Pricing(){
  usePageMeta('Pricing','Verse plans for music hiring and booking teams. Professionals build profiles and apply free; paid plans add capacity, seats and trials.');
  const[plans,setPlans]=useState<ApiPlan[]>(FALLBACK_PLANS);
  const[live,setLive]=useState<boolean|null>(null);
  useEffect(()=>{let active=true;apiGet<{plans:ApiPlan[]}>('/billing/plans',{skipAuthRedirect:true}).then(d=>{if(!active)return;const valid=(d?.plans||[]).filter(p=>p&&typeof p.code==='string'&&typeof p.name==='string');if(valid.length){setPlans(valid);setLive(true)}else setLive(false)}).catch(()=>{if(active)setLive(false)});return()=>{active=false}},[]);
  return <div className="min-h-screen bg-slate-950 text-white"><PublicNav/><main className="max-w-7xl mx-auto px-5 md:px-6 py-16">
    <div className="text-center max-w-3xl mx-auto"><div className="inline-flex items-center gap-2 rounded-full bg-emerald-500/10 border border-emerald-400/20 px-3 py-1.5 text-sm text-emerald-200"><ShieldCheck size={15} aria-hidden="true"/>SaaS plans with server-enforced trials</div><h1 className="text-4xl md:text-5xl font-bold mt-5">Pay for operating capacity, not the right to apply</h1><p className="text-lg text-slate-400 mt-4">Music professionals can build a profile and apply without a subscription. Paid plans are for teams using Verse to recruit, source, book and manage talent at higher volume.</p></div>
    {live===false&&<p className="text-center text-xs text-slate-500 mt-6" role="status">Showing standard plan limits. Your workspace billing page always shows the current terms.</p>}
    <div className="grid md:grid-cols-2 xl:grid-cols-4 gap-4 mt-10" data-testid="pricing-plans">{plans.map(p=>{const c=copy[p.code]||{who:'',extras:[],cta:'Get started',to:'/auth/employer'};const featured=p.code==='pro';return <Card key={p.code} className={`bg-white/[.055] border-white/10 ${featured?'ring-1 ring-violet-400':''}`}><CardContent className="p-5 flex flex-col h-full"><h2 className="text-xl font-semibold">{p.code==='free'?'Starter':p.name}</h2><p className="text-xs text-slate-400 mt-1 min-h-8">{c.who}</p><div className="text-3xl font-bold mt-4">{price(p)}{!!p.monthly&&<span className="text-xs font-normal text-slate-400"> / month</span>}</div>{p.trialDays>0&&<div className="text-sm text-emerald-300 mt-1">{p.trialDays}-day free trial</div>}{p.code==='enterprise'&&<div className="text-sm text-emerald-300 mt-1">Pilot available</div>}<ul className="space-y-2.5 mt-5 flex-1">{planFeatures(p).map(x=><li key={x} className="flex gap-2 text-sm text-slate-300"><Check size={15} aria-hidden="true" className="text-emerald-300 mt-0.5 shrink-0"/>{x}</li>)}</ul><Button className="w-full mt-6" variant={featured?'default':'secondary'} asChild><Link to={c.to} state={c.to.startsWith('/auth')&&p.code!=='free'?{from:'/employer/billing'}:undefined}>{c.cta}</Link></Button></CardContent></Card>})}</div>
    <div className="grid md:grid-cols-3 gap-4 mt-8"><Value icon={BriefcaseBusiness} title="Hire" body="Jobs, sessions, tours, auditions, collaborations and exact seats inside a new band or live team."/><Value icon={CalendarDays} title="Book" body="Date-specific act enquiries, structured event briefs, quotes, deposits and booking status—separate from recruitment."/><Value icon={Users} title="Operate" body="Profiles, rosters, shortlists, team seats, verification, messaging and admin controls in one workspace."/></div>
    <Card className="mt-8 bg-amber-500/[.05] border-amber-400/15"><CardContent className="p-6 text-sm text-slate-300"><b>How billing works:</b> recurring plans are billed through Razorpay Subscriptions with server-side credentials and signed webhooks. Trials are enforced by the server. Booking deposits for live acts are a separate payment flow with their own quote, cancellation and refund rules—see <Link className="text-violet-300 underline underline-offset-4" to="/refund-policy">payments &amp; refunds</Link>.</CardContent></Card>
  </main></div>;
}
function Value({icon:I,title,body}:{icon:any;title:string;body:string}){return <Card className="bg-white/[.035] border-white/10"><CardContent className="p-5"><I className="text-violet-300" aria-hidden="true"/><h2 className="font-semibold mt-3">{title}</h2><p className="text-sm text-slate-400 mt-1">{body}</p></CardContent></Card>}
