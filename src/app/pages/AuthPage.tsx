import { useState } from 'react';
import { useParams, useNavigate, useLocation, Link } from 'react-router';
import { motion } from 'motion/react';
import { Music, ArrowLeft, Eye, EyeOff } from 'lucide-react';
import { Button } from '../components/ui/button';
import { Input } from '../components/ui/input';
import { Label } from '../components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '../components/ui/card';
import { useAuth } from '../lib/authContext';
import { toast } from 'sonner';

export default function AuthPage(){
 const {userType='jobseeker'}=useParams(); const role=userType==='employer'?'employer':'jobseeker'; const navigate=useNavigate(); const location=useLocation(); const {login,register}=useAuth();
 const [mode,setMode]=useState<'login'|'register'>('login'); const [name,setName]=useState(''); const [email,setEmail]=useState(''); const [password,setPassword]=useState(''); const [show,setShow]=useState(false); const [loading,setLoading]=useState(false);
 const go=(r:string,complete=true)=>{const requested=(location.state as any)?.from;const allowed=typeof requested==='string'&&(requested.startsWith(`/${r==='jobseeker'?'jobseeker':r}`)||r==='admin'&&requested.startsWith('/admin'));navigate(allowed?requested:r==='admin'?'/admin':r==='employer'?(complete?'/employer':'/employer/profile'):(complete?'/jobseeker':'/jobseeker/profile'),{replace:true});};
 async function submit(e:React.FormEvent){e.preventDefault();setLoading(true);try{const u=mode==='login'?await login(email,password):await register({name,email,password,role});toast.success(mode==='login'?'Welcome back':'Account created');go(u.role,u.profileComplete);}catch(e:any){toast.error(e.message||'Unable to continue');}finally{setLoading(false);}}
 return <div className="min-h-screen bg-slate-950 flex items-center justify-center p-6 relative overflow-hidden">
  <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_left,rgba(124,58,237,.3),transparent_34%),radial-gradient(circle_at_bottom_right,rgba(37,99,235,.25),transparent_30%)]"/>
  <div className="w-full max-w-md relative z-10"><Link to="/" className="inline-flex items-center text-slate-300 hover:text-white mb-7"><ArrowLeft className="w-4 h-4 mr-2"/>Back</Link>
   <motion.div initial={{opacity:0,y:16}} animate={{opacity:1,y:0}}><Card className="bg-white/[0.07] border-white/15 backdrop-blur-xl shadow-2xl">
    <CardHeader className="text-center"><div className="mx-auto w-12 h-12 rounded-2xl bg-violet-500/20 grid place-items-center mb-2"><Music className="text-violet-300"/></div><CardTitle className="text-2xl text-white">{mode==='login'?'Welcome back':'Create your Verse account'}</CardTitle><CardDescription className="text-slate-300">{role==='employer'?'Hire music talent and manage applications':'Discover opportunities built for music professionals'}</CardDescription></CardHeader>
    <CardContent><form onSubmit={submit} className="space-y-4">{mode==='register'&&<div><Label className="text-slate-200">{role==='employer'?'Your / company name':'Full name'}</Label><Input value={name} onChange={e=>setName(e.target.value)} required minLength={2} className="mt-2 bg-black/20 border-white/15 text-white"/></div>}<div><Label className="text-slate-200">Email</Label><Input type="email" value={email} onChange={e=>setEmail(e.target.value)} required className="mt-2 bg-black/20 border-white/15 text-white"/></div><div><Label className="text-slate-200">Password</Label><div className="relative mt-2"><Input type={show?'text':'password'} value={password} onChange={e=>setPassword(e.target.value)} required minLength={10} className="bg-black/20 border-white/15 text-white pr-11"/><button type="button" onClick={()=>setShow(!show)} className="absolute right-3 top-2.5 text-slate-400">{show?<EyeOff size={18}/>:<Eye size={18}/>}</button></div></div><Button disabled={loading} className="w-full bg-violet-600 hover:bg-violet-500">{loading?'Please wait…':mode==='login'?'Sign in':'Create account'}</Button></form>{mode==='login'&&<Link to="/forgot-password" className="block text-right mt-3 text-xs text-slate-400 hover:text-white">Forgot password?</Link>}
    <button onClick={()=>setMode(mode==='login'?'register':'login')} className="w-full mt-5 text-sm text-violet-300 hover:text-violet-200">{mode==='login'?`New to Verse? Create ${role==='employer'?'an employer':'a talent'} account`:'Already have an account? Sign in'}</button>
   </CardContent></Card></motion.div></div></div>
}
