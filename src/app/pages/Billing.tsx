import {useEffect, useRef, useState} from 'react';
import {Navigation} from '../components/Navigation';
import {ApiError, apiGet, apiPost} from '../lib/api';
import {openRazorpayCheckout} from '../lib/razorpayCheckout';
import {Card, CardContent} from '../components/ui/card';
import {Button} from '../components/ui/button';
import {Badge} from '../components/ui/badge';
import {AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle} from '../components/ui/alert-dialog';
import {AlertTriangle, Check, CreditCard, FlaskConical, ShieldCheck} from 'lucide-react';
import {toast} from 'sonner';

type Summary = {
  status: 'pending' | 'trialing' | 'active' | 'cancelling' | 'past_due' | 'cancelled';
  planCode: string; planName: string; provider: string; trialEndsAt?: string | null; currentPeriodEnd?: string | null;
  nextChargeAt?: string | null; accessEndsAt?: string | null; monthlyAmount?: number | null;
};
type BillingState = {subscription: any; plan: any; purchasedPlan: any; summary: Summary | null; history: any[]; testMode: boolean};

const inr = (value: number) => `₹${Number(value).toLocaleString('en-IN')}`;
const day = (value?: string | null) => value ? new Date(value).toLocaleDateString('en-IN', {day: 'numeric', month: 'short', year: 'numeric'}) : '';
const money = (currency: string, value: number) => currency === 'INR' ? inr(value) : `${currency} ${Number(value).toLocaleString('en-IN')}`;

const STATUS_LABEL: Record<Summary['status'], string> = {
  pending: 'Setup incomplete', trialing: 'Free trial', active: 'Active', cancelling: 'Cancellation scheduled', past_due: 'Payment failed', cancelled: 'Cancelled',
};

function statusCopy(s: Summary): string {
  const amount = s.monthlyAmount ? inr(s.monthlyAmount) : 'the plan price';
  switch (s.status) {
    case 'pending': return 'Checkout was not completed. Finish authorising the recurring payment to start your plan. Nothing has been charged.';
    case 'trialing': return `Your free trial ends on ${day(s.trialEndsAt)}. The first charge of ${amount} happens then unless you cancel before.`;
    case 'active': return s.nextChargeAt ? `Next charge: ${amount} on ${day(s.nextChargeAt)}.` : 'Your plan is active.';
    case 'cancelling': return `You will not be charged again. ${s.planName} features stay available until ${day(s.accessEndsAt)}, then your account moves to Free.`;
    case 'past_due': return 'We could not collect your latest payment, so paid features are paused. Razorpay retries automatically; use the payment link Razorpay emailed you to update your card, or cancel below.';
    case 'cancelled': return `Your ${s.planName} plan has ended. You are on the Free plan and can subscribe again at any time.`;
  }
}

function newIdempotencyKey() {
  const c: any = (globalThis as any).crypto;
  if (c?.randomUUID) return c.randomUUID() as string;
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`;
}

const wait = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

export default function Billing() {
  const [plans, setPlans] = useState<any[]>([]);
  const [state, setState] = useState<BillingState | null>(null);
  const [cancelling, setCancelling] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [pendingPlan, setPendingPlan] = useState<string | null>(null);
  // One Idempotency-Key per checkout intent. It is kept after a network/gateway failure so a retry replays the same intent instead of creating a second subscription.
  const intentKeys = useRef<Record<string, string>>({});
  const inFlight = useRef(false);

  const load = () => Promise.all([apiGet<any>('/billing/plans'), apiGet<BillingState>('/billing/subscription')])
    .then(([p, s]) => { setPlans(p.plans || []); setState(s); return s; });
  useEffect(() => { load().catch((e: any) => toast.error(e.message)); }, []);

  // Activation arrives by signed webhook, usually within seconds of checkout.
  async function waitForActivation() {
    for (let attempt = 0; attempt < 8; attempt += 1) {
      const next = await load();
      if (next.summary && next.summary.status !== 'pending') return true;
      await wait(1500);
    }
    return false;
  }

  async function choose(code: string) {
    if (inFlight.current) return;
    inFlight.current = true;
    setPendingPlan(code);
    const key = intentKeys.current[code] || (intentKeys.current[code] = newIdempotencyKey());
    try {
      const d: any = await apiPost('/billing/checkout', {planCode: code}, {headers: {'Idempotency-Key': key}});
      delete intentKeys.current[code];
      if (d.salesAssisted) { toast.info(d.message); return; }
      if (d.checkout?.mode === 'mock') {
        toast.success('Trial activated in development mode. Configure Razorpay environment keys for live billing.');
        await load();
        return;
      }
      if (d.checkout?.mode === 'razorpay') {
        const plan = plans.find(p => p.code === code);
        const result = await openRazorpayCheckout(d.checkout, {description: `${plan?.name || code} plan subscription`, amountLabel: plan?.monthly ? `${inr(plan.monthly)} / month${plan.trialDays ? ` after a ${plan.trialDays}-day trial` : ''}` : ''});
        if (result.status === 'success') {
          toast.success('Payment method authorised. Activating your plan…');
          const activated = await waitForActivation();
          if (!activated) toast.info('Razorpay is still confirming your mandate. This page updates once the confirmation arrives; refresh in a minute.');
        } else if (result.lastError) {
          toast.error(`Payment not completed: ${result.lastError}`);
          await load();
        } else {
          toast.info('Checkout closed. Nothing was charged. You can finish setup at any time.');
          await load();
        }
      }
    } catch (e: any) {
      const status = e instanceof ApiError ? e.status : 0;
      if (status !== 0 && status !== 502) delete intentKeys.current[code];
      toast.error(e.message);
    } finally {
      inFlight.current = false;
      setPendingPlan(null);
    }
  }

  async function cancel() {
    setCancelling(true);
    try {
      const d: any = await apiPost('/billing/cancel', {});
      toast.success(d.outcome === 'scheduled' ? `Cancellation scheduled. Access continues until ${day(d.accessEndsAt) || 'the end of the billing period'}.` : 'Subscription cancelled. You will not be charged.');
      setConfirmOpen(false);
      await load();
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setCancelling(false);
    }
  }

  const sub = state?.subscription;
  const summary = state?.summary || null;
  const currentCode = summary && !['cancelled'].includes(summary.status) ? summary.planCode : 'free';
  const cancellable = summary && ['pending', 'trialing', 'active', 'past_due'].includes(summary.status);
  const immediateCancel = summary && summary.status !== 'active';

  return <div className="min-h-screen bg-slate-950 text-white">
    <Navigation/>
    <main className="max-w-7xl mx-auto px-5 pt-28 pb-16">
      <div className="flex flex-col md:flex-row md:items-end justify-between gap-4">
        <div>
          <div className="text-xs uppercase tracking-[.2em] text-violet-300">SaaS billing</div>
          <h1 className="text-4xl font-bold mt-2">Plan & billing</h1>
          <p className="text-slate-400 mt-2">Core candidate applications remain free. Paid plans unlock operating capacity for hiring, sourcing, booking and teams.</p>
        </div>
        {state && <Badge className="w-fit" data-testid="plan-badge">{summary ? `${summary.planName} · ${STATUS_LABEL[summary.status]}` : `${state.plan?.name || 'Free'} plan`}</Badge>}
      </div>

      {state?.testMode && <div role="status" className="mt-6 flex gap-3 rounded-xl border border-amber-400/30 bg-amber-500/10 p-4 text-sm text-amber-100">
        <FlaskConical className="shrink-0 text-amber-300" size={18}/>
        <span><b>Test mode.</b> Payments on this environment use Razorpay test mode. No real money moves and no real cards are charged.</span>
      </div>}

      {summary && <Card className={`mt-6 border ${summary.status === 'past_due' ? 'bg-rose-500/[.07] border-rose-400/30' : summary.status === 'trialing' ? 'bg-emerald-500/[.06] border-emerald-400/20' : 'bg-white/[.05] border-white/10'}`} data-testid="billing-status">
        <CardContent className="p-5 flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div className="flex gap-3">
            {summary.status === 'past_due' ? <AlertTriangle className="text-rose-300 shrink-0"/> : summary.status === 'trialing' ? <ShieldCheck className="text-emerald-300 shrink-0"/> : <CreditCard className="text-violet-300 shrink-0"/>}
            <div>
              <h2 className="font-semibold text-lg">{summary.planName} plan · <span data-testid="billing-status-label">{STATUS_LABEL[summary.status]}</span></h2>
              <p className="text-sm text-slate-300 mt-1 max-w-3xl" data-testid="billing-status-copy">{statusCopy(summary)}</p>
              {summary.nextChargeAt && <p className="text-xs text-slate-400 mt-2">Next charge date: <span data-testid="next-charge-date">{day(summary.nextChargeAt)}</span></p>}
            </div>
          </div>
          <div className="flex gap-2 flex-wrap">
            {summary.status === 'pending' && <Button disabled={pendingPlan !== null} onClick={() => choose(summary.planCode)}>Complete setup</Button>}
            {cancellable && <Button variant="outline" className="text-rose-300" disabled={cancelling} onClick={() => setConfirmOpen(true)}>Cancel subscription</Button>}
          </div>
        </CardContent>
      </Card>}

      <div className="grid md:grid-cols-2 xl:grid-cols-4 gap-4 mt-7">{plans.map(p =>
        <Card key={p.code} className={`bg-white/[.055] border-white/10 ${currentCode === p.code ? 'ring-1 ring-violet-400' : ''}`} data-testid={`plan-${p.code}`}>
          <CardContent className="p-5">
            <h2 className="text-xl font-semibold">{p.name}</h2>
            <div className="text-3xl font-bold mt-3">{p.monthly === null ? 'Custom' : p.monthly === 0 ? 'Free' : inr(p.monthly)} {p.monthly > 0 && <span className="text-xs font-normal text-slate-500">/month</span>}</div>
            {p.trialDays > 0 && <div className="text-sm text-emerald-300 mt-1">{p.trialDays}-day free trial for your first paid plan</div>}
            <div className="space-y-2 text-sm text-slate-300 mt-5">{[`Up to ${p.activePosts} active opportunities`, `${p.seats} team seat${p.seats === 1 ? '' : 's'}`, `${p.shortlist} saved talent capacity`, `${p.bookings} active booking enquiries`].map(x =>
              <div className="flex gap-2" key={x}><Check size={15} className="text-emerald-300 mt-0.5"/>{x}</div>)}</div>
            {p.code !== 'free' && <Button className="w-full mt-6" variant={currentCode === p.code ? 'secondary' : 'default'}
              disabled={pendingPlan !== null || (currentCode === p.code && summary?.status !== 'pending')}
              aria-busy={pendingPlan === p.code} onClick={() => choose(p.code)}>
              {pendingPlan === p.code ? 'Preparing checkout…' : currentCode === p.code && summary?.status === 'pending' ? 'Complete setup' : currentCode === p.code ? 'Current plan' : p.code === 'enterprise' ? 'Contact sales' : sub ? `Switch to ${p.name}` : 'Start free trial'}
            </Button>}
          </CardContent>
        </Card>)}
      </div>

      {(state?.history?.length || 0) > 0 && <Card className="mt-8 bg-white/[.04] border-white/10">
        <CardContent className="p-5">
          <h2 className="font-semibold">Payment history</h2>
          <div className="mt-3 overflow-x-auto">
            <table className="w-full text-sm" data-testid="payment-history">
              <thead className="text-left text-slate-400"><tr><th className="py-2 pr-4 font-medium">Date</th><th className="py-2 pr-4 font-medium">Amount</th><th className="py-2 pr-4 font-medium">Status</th><th className="py-2 font-medium">Reference</th></tr></thead>
              <tbody>{state!.history.map(h => <tr key={h.paymentId} className="border-t border-white/10">
                <td className="py-2 pr-4">{day(h.at)}</td>
                <td className="py-2 pr-4">{money(h.currency, h.amount)}</td>
                <td className="py-2 pr-4">{h.status === 'captured' ? 'Paid' : h.status === 'failed' ? 'Failed' : h.status}</td>
                <td className="py-2 font-mono text-xs text-slate-400">{h.invoiceId || h.paymentId}</td>
              </tr>)}</tbody>
            </table>
          </div>
        </CardContent>
      </Card>}

      <div className="mt-8 text-xs text-slate-500 max-w-4xl">Plan changes: cancel your current plan first; you can subscribe to another plan once it has ended. Payment state is confirmed by signed Razorpay webhooks; closing or refreshing checkout never charges you twice.</div>
    </main>

    <AlertDialog open={confirmOpen} onOpenChange={open => { if (!cancelling) setConfirmOpen(open); }}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Cancel your {summary?.planName} subscription?</AlertDialogTitle>
          <AlertDialogDescription>
            {immediateCancel
              ? summary?.status === 'trialing'
                ? 'Your free trial ends now and you will not be charged. Paid features stop immediately.'
                : 'The recurring payment is cancelled now and you will not be charged again. Paid features stop immediately.'
              : `You will not be charged again. Your ${summary?.planName} features stay available until ${day(summary?.currentPeriodEnd) || 'the end of the current billing period'}.`}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={cancelling}>Keep subscription</AlertDialogCancel>
          <AlertDialogAction disabled={cancelling} className="bg-rose-600 hover:bg-rose-700" onClick={event => { event.preventDefault(); cancel(); }}>
            {cancelling ? 'Cancelling…' : immediateCancel ? 'Cancel now' : 'Cancel at period end'}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  </div>;
}
