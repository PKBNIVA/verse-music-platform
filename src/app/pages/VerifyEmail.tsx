import {useEffect,useRef,useState} from 'react';
import {Link,useSearchParams} from 'react-router';
import {PublicNav} from '../components/PublicNav';
import {usePageMeta} from '../components/PageMeta';
import {apiPost} from '../lib/api';
import {Button} from '../components/ui/button';

type State = {kind:'pending'|'ok'|'error'; message:string};

export default function VerifyEmail(){
  const[sp]=useSearchParams();
  const token=(sp.get('token')||'').trim();
  const[state,setState]=useState<State>(()=>token?{kind:'pending',message:'Verifying your email…'}:{kind:'error',message:'This verification link is incomplete.'});
  // A verification token is single-use: never send it twice (StrictMode / re-render).
  const sentFor=useRef<string|null>(null);
  usePageMeta('Verify your email','Confirm the email address on your Verse account.');
  useEffect(()=>{
    if(!token||sentFor.current===token)return;
    sentFor.current=token;
    setState({kind:'pending',message:'Verifying your email…'});
    apiPost('/auth/verify-email',{token},{skipAuthRedirect:true})
      .then(()=>setState({kind:'ok',message:'Email verified successfully.'}))
      .catch((e:any)=>setState({kind:'error',message:e?.message||'Verification link is invalid or expired.'}));
  },[token]);
  return <div className="min-h-screen bg-slate-950 text-white"><PublicNav/><main className="max-w-lg mx-auto px-5 py-24 text-center">
    <h1 className="text-3xl font-bold">{state.kind==='ok'?'Email verified':state.kind==='pending'?'Verifying your email':'We couldn’t verify your email'}</h1>
    <p className={`mt-4 ${state.kind==='error'?'text-rose-300':'text-slate-300'}`} role={state.kind==='pending'?'status':state.kind==='error'?'alert':undefined}>{state.message}</p>
    {state.kind==='error'&&<p className="mt-3 text-sm text-slate-400">Sign in and request a new verification email from your profile, or open the most recent link we sent you.</p>}
    {state.kind!=='pending'&&<Button className="mt-6" asChild><Link to="/auth/jobseeker">Continue to sign in</Link></Button>}
  </main></div>;
}
