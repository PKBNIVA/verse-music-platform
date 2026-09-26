import {useEffect, useState} from 'react';
import {PLAN_LIMIT_EVENT} from '../lib/api';
import {router} from '../routes';
import {useAuth} from '../lib/authContext';
import {AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle} from './ui/alert-dialog';

// App-wide upgrade prompt shown whenever the API refuses an action because of a plan limit
// (active opportunities, saved talent, booking enquiries, workspace seats).
export function PlanLimitPrompt() {
  const [message, setMessage] = useState<string | null>(null);
  const {user} = useAuth();

  useEffect(() => {
    const onLimit = (event: Event) => setMessage((event as CustomEvent).detail?.message || 'You have reached a limit of your current plan.');
    window.addEventListener(PLAN_LIMIT_EVENT, onLimit);
    return () => window.removeEventListener(PLAN_LIMIT_EVENT, onLimit);
  }, []);

  return <AlertDialog open={message !== null} onOpenChange={open => { if (!open) setMessage(null); }}>
    <AlertDialogContent>
      <AlertDialogHeader>
        <AlertDialogTitle>Plan limit reached</AlertDialogTitle>
        <AlertDialogDescription>{message} Upgrade to add more capacity; your existing work is kept.</AlertDialogDescription>
      </AlertDialogHeader>
      <AlertDialogFooter>
        <AlertDialogCancel>Not now</AlertDialogCancel>
        <AlertDialogAction onClick={() => { setMessage(null); router.navigate(user?.role === 'employer' ? '/employer/billing' : '/jobseeker/billing'); }}>See plans</AlertDialogAction>
      </AlertDialogFooter>
    </AlertDialogContent>
  </AlertDialog>;
}
