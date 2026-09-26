import {useEffect, useRef, useState} from 'react';
import {apiGet, apiPost} from '../lib/api';
import {openRazorpayCheckout} from '../lib/razorpayCheckout';
import {Button} from './ui/button';
import {Badge} from './ui/badge';
import {toast} from 'sonner';

// Requester-side deposit state and payment for one booking. The amount, currency and order
// always come from the server; the browser only relays the Razorpay handler payload back.
const money = (currency: string, value: any) => `${currency || 'INR'} ${Number(value || 0).toLocaleString('en-IN')}`;

export function BookingDepositPanel({booking, onChanged}: {booking: any; onChanged: () => unknown}) {
  const [payments, setPayments] = useState<any[] | null>(null);
  const [paying, setPaying] = useState(false);
  const [declined, setDeclined] = useState<string | null>(null);
  const inFlight = useRef(false);
  const eligible = booking.isRequester && ['accepted', 'completed', 'disputed'].includes(booking.status);

  const refresh = () => apiGet<any>(`/bookings/${booking.id}/payments`).then(d => setPayments(d.payments || [])).catch(() => setPayments([]));
  useEffect(() => { if (eligible) refresh(); }, [booking.id, booking.status, booking.paymentCount, eligible]);

  if (!eligible) return null;
  const deposit = (payments || []).find(p => p.kind === 'deposit' && ['paid', 'refunded', 'created'].includes(p.status));
  const quote = booking.latestQuote;
  const expected = quote ? Math.round(quote.total * quote.depositPercent / 100) : null;

  async function pay() {
    if (inFlight.current) return;
    inFlight.current = true;
    setPaying(true);
    setDeclined(null);
    try {
      const d: any = await apiPost(`/bookings/${booking.id}/payment-order`, {});
      if (d.checkout?.mode === 'mock') {
        await apiPost(`/booking-payments/${d.payment.id}/confirm`, {});
        toast.success('Mock deposit recorded');
      } else {
        const result = await openRazorpayCheckout(d.checkout, {description: `Booking deposit · ${booking.actName}`, amountLabel: money(d.payment.currency, d.payment.amount)});
        if (result.status === 'success') {
          const r = result.response;
          await apiPost(`/booking-payments/${d.payment.id}/confirm`, {orderId: r.razorpay_order_id, paymentId: r.razorpay_payment_id, signature: r.razorpay_signature});
          toast.success('Deposit paid. Your booking is confirmed.');
        } else if (result.lastError) {
          setDeclined(result.lastError);
          toast.error(`Payment declined: ${result.lastError}`);
        } else {
          toast.info('Checkout closed. Nothing was charged.');
        }
      }
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      inFlight.current = false;
      setPaying(false);
      await refresh();
      await onChanged();
    }
  }

  if (payments === null) return <span className="text-xs text-slate-500">Checking deposit…</span>;
  if (deposit?.status === 'paid') return <Badge className="bg-emerald-500/15 text-emerald-200 border-emerald-400/30" data-testid="deposit-status">Deposit paid · booking confirmed</Badge>;
  if (deposit?.status === 'refunded') return <Badge className="bg-sky-500/15 text-sky-200 border-sky-400/30" data-testid="deposit-status">Deposit refunded · {money(deposit.currency, deposit.amount)}</Badge>;
  if (booking.status !== 'accepted') return null;
  return <div className="flex flex-col items-start gap-1">
    <Button size="sm" disabled={paying} aria-busy={paying} onClick={pay}>
      {paying ? 'Processing payment…' : `${declined ? 'Retry deposit' : deposit?.status === 'created' ? 'Resume deposit payment' : 'Pay deposit'}${expected ? ` · ${money(quote.currency, expected)}` : ''}`}
    </Button>
    {declined && <span role="alert" className="text-xs text-rose-300" data-testid="deposit-declined">Payment declined: {declined}</span>}
  </div>;
}
