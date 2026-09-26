import { useState } from 'react';
import { useParams, useNavigate, useLocation, Link } from 'react-router';
import { motion } from 'motion/react';
import { ArrowLeft, Briefcase, Eye, EyeOff, ShieldCheck, Users } from 'lucide-react';
import { Button } from '../components/ui/button';
import { Input } from '../components/ui/input';
import { Label } from '../components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '../components/ui/card';
import { useAuth } from '../lib/authContext';
import { consumeReturnTo } from '../lib/api';
import { toast } from 'sonner';
import { BrandMark } from '../components/BrandMark';

export default function AuthPage() {
  const { userType='jobseeker' } = useParams();
  const isAdmin = userType === 'admin';
  const role = userType === 'employer' ? 'employer' : 'jobseeker';
  const navigate = useNavigate();
  const location = useLocation();
  const { login, register } = useAuth();
  const [mode,setMode] = useState<'login'|'register'>('login');
  const [name,setName] = useState('');
  const [email,setEmail] = useState('');
  const [password,setPassword] = useState('');
  const [show,setShow] = useState(false);
  const [loading,setLoading] = useState(false);

  const go = (r:string, complete=true) => {
    const requested=(location.state as any)?.from??consumeReturnTo();
    const allowed=typeof requested==='string'&&(requested.startsWith(`/${r==='jobseeker'?'jobseeker':r}`)||r==='admin'&&requested.startsWith('/admin'));
    navigate(allowed?requested:r==='admin'?'/admin':r==='employer'?(complete?'/employer':'/employer/profile'):(complete?'/jobseeker':'/jobseeker/profile'),{replace:true});
  };
  async function submit(e:React.FormEvent) {
    e.preventDefault(); setLoading(true);
    try { const u=mode==='login'?await login(email,password):await register({name,email,password,role}); toast.success(mode==='login'?'Welcome back':'Your Verse profile is ready'); go(u.role,u.profileComplete); }
    catch(e:any) { toast.error(e.message||'Unable to continue'); }
    finally { setLoading(false); }
  }

  return <div className="relative min-h-screen overflow-hidden bg-slate-950 px-5 py-8 text-white">
    <div className="verse-grid absolute inset-0" /><div className="verse-orb absolute -left-32 -top-32 h-[30rem] w-[30rem] rounded-full bg-fuchsia-500/45" /><div className="verse-orb absolute -bottom-40 -right-20 h-[34rem] w-[34rem] rounded-full bg-cyan-400/25" />
    <div className="relative z-10 mx-auto flex min-h-[calc(100vh-4rem)] max-w-6xl flex-col">
      <div className="flex items-center justify-between"><Link to="/"><BrandMark /></Link><Link to="/" className="inline-flex items-center text-sm text-slate-300 hover:text-white"><ArrowLeft className="mr-2 h-4 w-4"/>Back to home</Link></div>
      <div className="grid flex-1 items-center gap-14 py-12 lg:grid-cols-[1fr_480px]">
        <div className="hidden lg:block"><div className="inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/[.05] px-3 py-1.5 text-sm text-slate-300"><ShieldCheck size={15} className="text-emerald-300"/>Your account and work stay protected</div><h1 className="mt-6 max-w-xl text-6xl font-black leading-[1] tracking-[-.05em]">One login. Your whole <span className="verse-gradient-text">music world.</span></h1><p className="mt-5 max-w-lg text-lg leading-8 text-slate-300">Discover work, prove your craft, build teams and manage every conversation in one professional home.</p></div>
        <motion.div initial={{opacity:0,y:16}} animate={{opacity:1,y:0}}>
          <Card className="verse-surface border-white/15 bg-transparent shadow-2xl">
            <CardHeader className="text-center"><div className="mx-auto grid h-12 w-12 place-items-center rounded-2xl bg-gradient-to-br from-fuchsia-500/30 to-violet-500/25 text-violet-200">{isAdmin?<ShieldCheck/>:role==='employer'?<Briefcase/>:<Users/>}</div><CardTitle className="mt-2 text-2xl font-black text-white">{mode==='login'?'Welcome back':'Create your Verse account'}</CardTitle><CardDescription className="text-slate-300">{isAdmin?'Verse trust and operations':role==='employer'?'Hire music talent and manage every candidate':'Find work and build a career people can hear'}</CardDescription></CardHeader>
            <CardContent>
              {!isAdmin&&<div className="mb-5 grid grid-cols-2 rounded-xl border border-white/10 bg-black/15 p-1"><Link to="/auth/jobseeker" className={`flex h-10 items-center justify-center gap-2 rounded-lg text-sm font-semibold ${role==='jobseeker'?'bg-white/10 text-white':'text-slate-400'}`}><Users size={15}/>Professional</Link><Link to="/auth/employer" className={`flex h-10 items-center justify-center gap-2 rounded-lg text-sm font-semibold ${role==='employer'?'bg-white/10 text-white':'text-slate-400'}`}><Briefcase size={15}/>Employer</Link></div>}
              <form onSubmit={submit} className="space-y-4">{mode==='register'&&<div><Label htmlFor="auth-name" className="text-slate-200">{role==='employer'?'Your or company name':'Full name'}</Label><Input id="auth-name" autoComplete="name" value={name} onChange={e=>setName(e.target.value)} required minLength={2} className="mt-2 border-white/15"/></div>}<div><Label htmlFor="auth-email" className="text-slate-200">Email</Label><Input id="auth-email" aria-label="Email" autoComplete="email" type="email" value={email} onChange={e=>setEmail(e.target.value)} required className="mt-2 border-white/15"/></div><div><Label htmlFor="auth-password" className="text-slate-200">Password</Label><div className="relative mt-2"><Input id="auth-password" aria-label="Password" autoComplete={mode==='login'?'current-password':'new-password'} type={show?'text':'password'} value={password} onChange={e=>setPassword(e.target.value)} required minLength={mode==='register'?10:undefined} aria-describedby={mode==='register'?'password-help':undefined} className="border-white/15 pr-12"/><button type="button" onClick={()=>setShow(!show)} className="absolute right-1 top-0 grid h-11 w-11 place-items-center rounded-lg text-slate-400 hover:text-white" aria-label={show?'Hide password':'Show password'}>{show?<EyeOff size={18}/>:<Eye size={18}/>}</button></div>{mode==='register'&&<p id="password-help" className="mt-1.5 text-xs text-slate-400">Use at least 10 characters. A longer passphrase is easiest to remember.</p>}</div><Button disabled={loading} className="w-full border-0 bg-gradient-to-r from-fuchsia-600 to-violet-600">{loading?'Tuning your workspace…':mode==='login'?'Sign in':'Create account'}</Button></form>
              {mode==='login'&&<Link to="/forgot-password" className="mt-3 block text-right text-xs text-slate-400 hover:text-white">Forgot password?</Link>}
              {!isAdmin&&<button onClick={()=>setMode(mode==='login'?'register':'login')} className="mt-5 min-h-11 w-full text-sm font-semibold text-violet-200 hover:text-white">{mode==='login'?`New to Verse? Create ${role==='employer'?'an employer':'a professional'} account`:'Already have an account? Sign in'}</button>}
              {mode==='register'&&<p className="mt-4 text-center text-xs leading-5 text-slate-400">By joining, you agree to our <Link className="text-slate-200 underline" to="/terms">Terms</Link> and <Link className="text-slate-200 underline" to="/privacy">Privacy Policy</Link>.</p>}
            </CardContent>
          </Card>
        </motion.div>
      </div>
    </div>
  </div>;
}
