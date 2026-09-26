import {useEffect, useRef, useState} from 'react';
import {Link, useSearchParams} from 'react-router';
import {MailX} from 'lucide-react';
import {PublicNav} from '../components/PublicNav';
import {Button} from '../components/ui/button';
import {apiPost} from '../lib/api';

type State = 'working' | 'done' | 'invalid' | 'error';

/** Target of the "Turn off these emails" link in notification emails. No sign-in: the signed token names the account. */
export default function Unsubscribe() {
  const [search] = useSearchParams();
  const token = search.get('token') || '';
  const [state, setState] = useState<State>(token ? 'working' : 'invalid');
  const started = useRef(false);

  const run = async () => {
    setState('working');
    try {
      await apiPost('/notifications/unsubscribe', {token}, {skipAuthRedirect: true});
      setState('done');
    } catch (e: any) {
      setState(e?.status === 400 ? 'invalid' : 'error');
    }
  };

  useEffect(() => {
    if (!token || started.current) return;
    started.current = true;
    void run();
  }, [token]);

  return <div className="min-h-screen bg-slate-950 text-white"><PublicNav/>
    <main className="max-w-lg mx-auto px-5 py-24 text-center">
      <MailX className="mx-auto text-violet-300" size={36} aria-hidden="true"/>
      <h1 className="text-3xl font-bold mt-4">Email notifications</h1>
      <div className="mt-4 text-slate-300" role={state === 'working' ? 'status' : 'alert'} data-testid="unsubscribe-status">
        {state === 'working' && 'Turning off notification emails…'}
        {state === 'done' && <>You won’t get emails about messages, bookings or application updates any more. Sign-in codes, verification and password emails still arrive.</>}
        {state === 'invalid' && 'This unsubscribe link is invalid or incomplete. You can turn notification emails off from Notifications after signing in.'}
        {state === 'error' && 'We couldn’t update your preference right now. Please try again.'}
      </div>
      <div className="mt-8 flex flex-wrap justify-center gap-3">
        {state === 'error' && <Button onClick={() => void run()}>Try again</Button>}
        <Button variant="outline" asChild><Link to="/auth/jobseeker">Sign in to change preferences</Link></Button>
      </div>
    </main>
  </div>;
}
