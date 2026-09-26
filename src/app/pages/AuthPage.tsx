import { useEffect, useRef, useState } from 'react';
import { useParams, useNavigate, useLocation, Link } from 'react-router';
import { motion } from 'motion/react';
import { ArrowLeft, Briefcase, Eye, EyeOff, Mail, ShieldCheck, Users } from 'lucide-react';
import { Button } from '../components/ui/button';
import { Input } from '../components/ui/input';
import { Label } from '../components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '../components/ui/card';
import { useAuth } from '../lib/authContext';
import { consumeReturnTo, requestSignInCode } from '../lib/api';
import { toast } from 'sonner';
import { BrandMark } from '../components/BrandMark';

const RESEND_COOLDOWN_SECONDS = 60;
const CODE_LENGTH = 6;
const digitsOnly = (value: string) => value.replace(/\D/g, '').slice(0, CODE_LENGTH);

export default function AuthPage() {
  const { userType='jobseeker' } = useParams();
  const isAdmin = userType === 'admin';
  const role = userType === 'employer' ? 'employer' : 'jobseeker';
  const navigate = useNavigate();
  const location = useLocation();
  const { login, register, verifyCode } = useAuth();
  const [mode,setMode] = useState<'login'|'register'>('login');
  /* Email codes are the primary path; passwords remain a fallback until email delivery is proven in production. */
  const [method,setMethod] = useState<'code'|'password'>('code');
  const [codeStep,setCodeStep] = useState<'email'|'code'>('email');
  const [name,setName] = useState('');
  const [email,setEmail] = useState('');
  const [password,setPassword] = useState('');
  const [code,setCode] = useState('');
  const [debugCode,setDebugCode] = useState<string|undefined>();
  const [show,setShow] = useState(false);
  const [loading,setLoading] = useState(false);
  const [error,setError] = useState('');
  const [cooldown,setCooldown] = useState(0);
  /* Input does not forward refs, so the code field is focused by id. */
  const focusCode = () => document.getElementById('auth-code')?.focus();
  const verifying = useRef(false);

  useEffect(() => {
    if (cooldown <= 0) return;
    const timer = window.setTimeout(() => setCooldown(c => Math.max(0, c - 1)), 1000);
    return () => window.clearTimeout(timer);
  }, [cooldown]);
  useEffect(() => { if (codeStep === 'code') focusCode(); }, [codeStep]);

  const go = (r:string, complete=true) => {
    const requested=(location.state as any)?.from??consumeReturnTo();
    const allowed=typeof requested==='string'&&(requested.startsWith(`/${r==='jobseeker'?'jobseeker':r}`)||r==='admin'&&requested.startsWith('/admin'));
    navigate(allowed?requested:r==='admin'?'/admin':r==='employer'?(complete?'/employer':'/employer/profile'):(complete?'/jobseeker':'/jobseeker/profile'),{replace:true});
  };
  /* Code-flow errors are shown inline (role=alert) next to the field; password errors keep the existing toast. */
  const fail = (e:any, fallback:string) => setError(e?.message||fallback);
  const switchMethod = (next:'code'|'password') => { setMethod(next); setCodeStep('email'); setCode(''); setError(''); };
  const switchMode = () => { setMode(mode==='login'?'register':'login'); setCodeStep('email'); setCode(''); setError(''); };

  async function submit(e:React.FormEvent) {
    e.preventDefault(); setLoading(true); setError('');
    try { const u=mode==='login'?await login(email,password):await register({name,email,password,role}); toast.success(mode==='login'?'Welcome back':'Your Verse profile is ready'); go(u.role,u.profileComplete); }
    catch(e:any) { toast.error(e.message||'Unable to continue'); }
    finally { setLoading(false); }
  }

  async function sendCode(e?:React.FormEvent) {
    e?.preventDefault();
    if (loading || cooldown > 0) return;
    setLoading(true); setError('');
    try {
      const response = await requestSignInCode(mode==='register'&&!isAdmin ? {email, name, role} : {email});
      setDebugCode(response.debugCode);
      setCode(''); setCodeStep('code'); setCooldown(RESEND_COOLDOWN_SECONDS);
      toast.success('Check your email for a 6-digit code');
    } catch(e:any) { fail(e,'Could not send a code. Try again.'); }
    finally { setLoading(false); }
  }

  async function confirmCode(value=code) {
    if (verifying.current) return;
    if (value.length !== CODE_LENGTH) { setError(`Enter the ${CODE_LENGTH}-digit code from your email.`); return; }
    verifying.current = true; setLoading(true); setError('');
    try {
      const u = await verifyCode(email, value);
      toast.success(mode==='register'?'Your Verse profile is ready':'Welcome back');
      go(u.role, u.profileComplete);
    } catch(e:any) { setCode(''); focusCode(); fail(e,'Invalid or expired code.'); }
    finally { verifying.current = false; setLoading(false); }
  }

  const onCodeChange = (raw:string) => {
    const value = digitsOnly(raw);
    setCode(value);
    if (error) setError('');
    /* Typing or pasting the last digit submits, so a pasted code signs in in one step. */
    if (value.length === CODE_LENGTH && !loading) void confirmCode(value);
  };

  const inputClass = 'mt-2 border-white/15';
  const nameField = mode==='register'&&<div><Label htmlFor="auth-name" className="text-slate-200">{role==='employer'?'Your or company name':'Full name'}</Label><Input id="auth-name" autoComplete="name" value={name} onChange={e=>setName(e.target.value)} required minLength={2} maxLength={120} className={inputClass}/></div>;
  const emailField = <div><Label htmlFor="auth-email" className="text-slate-200">Email</Label><Input id="auth-email" aria-label="Email" autoComplete="email" type="email" value={email} onChange={e=>setEmail(e.target.value)} required className={inputClass}/></div>;
  const errorBox = error&&<p role="alert" className="rounded-lg border border-rose-400/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-100">{error}</p>;
  const linkButton = 'min-h-11 text-sm font-semibold text-violet-200 hover:text-white disabled:text-slate-500';

  const codeForms = codeStep==='email'
    ? <form onSubmit={sendCode} className="space-y-4" aria-busy={loading}>
        {nameField}{emailField}{errorBox}
        <Button disabled={loading} className="w-full border-0 bg-gradient-to-r from-fuchsia-600 to-violet-600"><Mail className="mr-2 h-4 w-4"/>{loading?'Sending code…':'Email me a sign-in code'}</Button>
        <p className="text-center text-xs leading-5 text-slate-400">We’ll email you a 6-digit code. No password needed.</p>
      </form>
    : <form onSubmit={e=>{e.preventDefault();void confirmCode();}} className="space-y-4" aria-busy={loading}>
        <p className="text-sm leading-6 text-slate-300" aria-live="polite">If <span className="font-semibold text-white">{email}</span> can be used on Verse, a 6-digit code is on its way. It expires in 10 minutes.</p>
        <div><Label htmlFor="auth-code" className="text-slate-200">Sign-in code</Label><Input id="auth-code" aria-label="Sign-in code" value={code} onChange={e=>onCodeChange(e.target.value)} onPaste={e=>{e.preventDefault();onCodeChange(e.clipboardData.getData('text'));}} inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={CODE_LENGTH} placeholder="••••••" aria-invalid={Boolean(error)} aria-describedby="auth-code-help" readOnly={loading} className="mt-2 border-white/15 text-center font-mono text-2xl tracking-[.5em]"/><p id="auth-code-help" className="mt-1.5 text-xs text-slate-400">Paste or type the code from your email.</p></div>
        {debugCode&&<p className="rounded-lg border border-amber-300/30 bg-amber-400/10 px-3 py-2 text-xs text-amber-100">Local testing: email is not configured, your code is <span className="font-mono font-bold" data-testid="debug-code">{debugCode}</span></p>}
        {errorBox}
        <Button disabled={loading||code.length!==CODE_LENGTH} className="w-full border-0 bg-gradient-to-r from-fuchsia-600 to-violet-600">{loading?'Checking code…':mode==='register'&&!isAdmin?'Verify and create account':'Verify and sign in'}</Button>
        <div className="flex items-center justify-between gap-3">
          <button type="button" onClick={()=>{setCodeStep('email');setCode('');setError('');}} className={linkButton}>Use a different email</button>
          <button type="button" onClick={()=>void sendCode()} disabled={loading||cooldown>0} className={linkButton}>{cooldown>0?`Resend code in ${cooldown}s`:'Resend code'}</button>
        </div>
      </form>;

  const passwordForm = <form onSubmit={submit} className="space-y-4">{nameField}{emailField}<div><Label htmlFor="auth-password" className="text-slate-200">Password</Label><div className="relative mt-2"><Input id="auth-password" aria-label="Password" autoComplete={mode==='login'?'current-password':'new-password'} type={show?'text':'password'} value={password} onChange={e=>setPassword(e.target.value)} required minLength={mode==='register'?10:undefined} aria-describedby={mode==='register'?'password-help':undefined} className="border-white/15 pr-12"/><button type="button" onClick={()=>setShow(!show)} className="absolute right-1 top-0 grid h-11 w-11 place-items-center rounded-lg text-slate-400 hover:text-white" aria-label={show?'Hide password':'Show password'}>{show?<EyeOff size={18}/>:<Eye size={18}/>}</button></div>{mode==='register'&&<p id="password-help" className="mt-1.5 text-xs text-slate-400">Use at least 10 characters. A longer passphrase is easiest to remember.</p>}</div><Button disabled={loading} className="w-full border-0 bg-gradient-to-r from-fuchsia-600 to-violet-600">{loading?'Tuning your workspace…':mode==='login'?'Sign in':'Create account'}</Button></form>;

  return <div className="relative min-h-screen overflow-hidden bg-slate-950 px-5 py-8 text-white">
    <div className="verse-grid absolute inset-0" /><div className="verse-orb absolute -left-32 -top-32 h-[30rem] w-[30rem] rounded-full bg-fuchsia-500/45" /><div className="verse-orb absolute -bottom-40 -right-20 h-[34rem] w-[34rem] rounded-full bg-cyan-400/25" />
    <div className="relative z-10 mx-auto flex min-h-[calc(100vh-4rem)] max-w-6xl flex-col">
      <div className="flex items-center justify-between"><Link to="/"><BrandMark /></Link><Link to="/" className="inline-flex items-center text-sm text-slate-300 hover:text-white"><ArrowLeft className="mr-2 h-4 w-4"/>Back to home</Link></div>
      <div className="grid flex-1 items-center gap-14 py-12 lg:grid-cols-[1fr_480px]">
        <div className="hidden lg:block"><div className="inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/[.05] px-3 py-1.5 text-sm text-slate-300"><ShieldCheck size={15} className="text-emerald-300"/>Your account and work stay protected</div><h1 className="mt-6 max-w-xl text-6xl font-black leading-[1] tracking-[-.05em]">One login. Your whole <span className="verse-gradient-text">music world.</span></h1><p className="mt-5 max-w-lg text-lg leading-8 text-slate-300">Discover work, prove your craft, build teams and manage every conversation in one professional home.</p></div>
        <motion.div initial={{opacity:0,y:16}} animate={{opacity:1,y:0}}>
          <Card className="verse-surface border-white/15 bg-transparent shadow-2xl">
            <CardHeader className="text-center"><div className="mx-auto grid h-12 w-12 place-items-center rounded-2xl bg-gradient-to-br from-fuchsia-500/30 to-violet-500/25 text-violet-200">{isAdmin?<ShieldCheck/>:role==='employer'?<Briefcase/>:<Users/>}</div><CardTitle className="mt-2 text-2xl font-black text-white">{method==='code'&&codeStep==='code'?'Check your email':mode==='login'?'Welcome back':'Create your Verse account'}</CardTitle><CardDescription className="text-slate-300">{isAdmin?'Verse trust and operations':role==='employer'?'Hire music talent and manage every candidate':'Find work and build a career people can hear'}</CardDescription></CardHeader>
            <CardContent>
              {!isAdmin&&codeStep==='email'&&<div className="mb-5 grid grid-cols-2 rounded-xl border border-white/10 bg-black/15 p-1"><Link to="/auth/jobseeker" className={`flex h-10 items-center justify-center gap-2 rounded-lg text-sm font-semibold ${role==='jobseeker'?'bg-white/10 text-white':'text-slate-400'}`}><Users size={15}/>Professional</Link><Link to="/auth/employer" className={`flex h-10 items-center justify-center gap-2 rounded-lg text-sm font-semibold ${role==='employer'?'bg-white/10 text-white':'text-slate-400'}`}><Briefcase size={15}/>Employer</Link></div>}
              {method==='code'?codeForms:passwordForm}
              {codeStep==='email'&&<div className="mt-3 flex items-center justify-between gap-3">
                <button type="button" onClick={()=>switchMethod(method==='code'?'password':'code')} className="min-h-11 text-sm text-slate-300 hover:text-white">{method==='code'?'Use password instead':'Email me a code instead'}</button>
                {method==='password'&&mode==='login'&&<Link to="/forgot-password" className="text-xs text-slate-400 hover:text-white">Forgot password?</Link>}
              </div>}
              {!isAdmin&&codeStep==='email'&&<button onClick={switchMode} className="mt-3 min-h-11 w-full text-sm font-semibold text-violet-200 hover:text-white">{mode==='login'?`New to Verse? Create ${role==='employer'?'an employer':'a professional'} account`:'Already have an account? Sign in'}</button>}
              {mode==='register'&&<p className="mt-4 text-center text-xs leading-5 text-slate-400">By joining, you agree to our <Link className="text-slate-200 underline" to="/terms">Terms</Link> and <Link className="text-slate-200 underline" to="/privacy">Privacy Policy</Link>.</p>}
            </CardContent>
          </Card>
        </motion.div>
      </div>
    </div>
  </div>;
}
