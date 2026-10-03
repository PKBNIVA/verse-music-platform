import { useCallback, useEffect, useState } from 'react';
import { useLocation, useNavigate } from 'react-router';
import { PublicNav } from '../components/PublicNav';
import { PhotoHeader } from '../components/landing/PhotoHeader';
import { usePageMeta } from '../components/PageMeta';
import { PUBLIC_PAGE_META } from '../lib/siteMeta';
import { Card, CardContent } from '../components/ui/card';
import { Button } from '../components/ui/button';
import { Badge } from '../components/ui/badge';
import { PushOptIn } from '../components/push/PushOptIn';
import { UrgentRequestFields } from '../components/urgent/UrgentRequestFields';
import { URGENT_PROMISE, useUrgentForm } from '../lib/urgentForm';
import { apiGet, apiPost } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { useAuth } from '../lib/authContext';
import { saveUrgentDraft } from '../lib/urgentDraft';
import { toast } from 'sonner';
import { CheckCircle2, Clock3, MessageCircle, Zap } from 'lucide-react';
import type { UrgentRequest, UrgentRequestResponse } from '../lib/apiTypes';
import { useVisiblePolling } from '../lib/usePolling';
import { useRealtime, useRealtimeInterval } from '../lib/realtime';

type Confirmed = { id: string; notifiedCount: number; matchStatus?: string; responseTimePromise: string };
// Passed via navigate(..., { state }) either directly (signed-in submit) or after the
// sign-up hop completes and AuthPage submits the saved draft on this person's behalf.
type LocationState = { confirmed?: Confirmed } | null;

export default function UrgentHire() {
  usePageMeta(PUBLIC_PAGE_META['/urgent'].title, PUBLIC_PAGE_META['/urgent'].description, {
    canonicalPath: '/urgent',
  });
  const { user } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [confirmed, setConfirmed] = useState<Confirmed | null>((location.state as LocationState)?.confirmed || null);
  // A hire page's "Post an urgent request" CTA prefills the role and city it was already showing.
  const prefill = new URLSearchParams(location.search);
  const urgent = useUrgentForm({ role: prefill.get('role') || undefined, city: prefill.get('city') || undefined });
  const { form } = urgent;
  const [submitting, setSubmitting] = useState(false);
  // The landing page's "Need someone by tomorrow" band passes the date it showed along.
  const askedStartAt = prefill.get('startAt') || '';
  const setStartAt = urgent.set;
  useEffect(() => {
    if (/^\d{4}-\d\d-\d\dT\d\d:\d\d$/.test(askedStartAt)) setStartAt('startAt', askedStartAt);
  }, [askedStartAt]); // eslint-disable-line react-hooks/exhaustive-deps

  async function submit() {
    const body = urgent.validate();
    if (!body) return;
    if (!user) {
      // Sign-in gated at submit: the draft survives the hop through the two-minute join flow (or
      // sign-in for existing hirers) and is submitted the moment they're signed in.
      saveUrgentDraft(body);
      toast.message("Create a free hirer account and we'll post this right away.");
      navigate('/join/hiring');
      return;
    }
    setSubmitting(true);
    try {
      const d = await apiPost<{ id: string; notifiedCount: number; matchStatus?: string; responseTimePromise: string }>(
        '/urgent-requests',
        body,
      );
      setConfirmed({
        id: d.id,
        notifiedCount: d.notifiedCount,
        matchStatus: d.matchStatus,
        responseTimePromise: d.responseTimePromise,
      });
    } catch (e: unknown) {
      if (form.setFromApi(e, 'Could not publish this request. Please try again.')) form.focusFirst();
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="min-h-screen bg-slate-950 text-white">
      <PublicNav />
      <main className="max-w-2xl mx-auto px-4 sm:px-5 pt-8 pb-20">
        {confirmed ? (
          <StatusCard confirmed={confirmed} onNewRequest={() => setConfirmed(null)} />
        ) : (
          <>
            <PhotoHeader
              photo="rehearsal-room"
              eyebrow="Need someone by tomorrow"
              title="Find a verified musician, fast."
            >
              <p>
                Tell us who you need and where. We notify verified musicians nearby right away — most requests get a
                first response within 2 hours.
              </p>
            </PhotoHeader>
            <Card className="bg-white/[.055] border-white/10 mt-6">
              <CardContent className="p-5 sm:p-6 space-y-4">
                {form.formError && (
                  <p role="alert" className="text-sm text-rose-300">
                    {form.formError}
                  </p>
                )}
                <UrgentRequestFields values={urgent.values} errors={form.errors} onChange={urgent.set} />
                <Button className="w-full" size="lg" disabled={submitting} onClick={() => void submit()}>
                  <Zap size={16} className="mr-2" />
                  {submitting ? 'Publishing…' : user ? 'Post urgent need' : 'Continue to sign up'}
                </Button>
                <p className="text-center text-sm text-slate-300" data-testid="urgent-promise">
                  <Clock3 size={14} className="mr-1 inline" aria-hidden="true" />
                  Expect a first response {URGENT_PROMISE}.
                </p>
                {!user && (
                  <p className="text-xs text-slate-500 text-center">
                    We'll save this and post it the moment your free hirer account is ready.
                  </p>
                )}
              </CardContent>
            </Card>
          </>
        )}
      </main>
    </div>
  );
}

function StatusCard({ confirmed, onNewRequest }: { confirmed: Confirmed; onNewRequest: () => void }) {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [item, setItem] = useState<UrgentRequest | null>(null);
  const [responses, setResponses] = useState<UrgentRequestResponse[]>([]);

  const status = item?.match_status ?? confirmed.matchStatus;
  const matching = status === 'pending' || status === 'matching';
  // After ~90 s of matching, stop promising an imminent count and fall back to calmer copy.
  const [slow, setSlow] = useState(false);
  useEffect(() => {
    if (!matching) return;
    const timer = setTimeout(() => setSlow(true), 90_000);
    return () => clearTimeout(timer);
  }, [matching]);

  const refresh = useCallback(async () => {
    try {
      const d = await apiGet<{ request: UrgentRequest }>(`/urgent-requests/${confirmed.id}`);
      setItem(d.request);
      if ((d.request.responseCount || 0) > 0) {
        const r = await apiGet<{ responses?: UrgentRequestResponse[] }>(`/urgent-requests/${confirmed.id}/responses`);
        setResponses(r.responses || []);
      }
    } catch {
      /* the status card degrades gracefully to the confirmation numbers we already have */
    }
  }, [confirmed.id]);

  useEffect(() => {
    void refresh();
  }, [refresh]);
  // Status, matching progress and responses arrive live; polling is the fallback. Matching runs in
  // the background right after posting, so without a live connection check often until it finishes.
  useRealtime('UrgentRequestChannel', user ? { id: confirmed.id } : null, () => void refresh());
  useVisiblePolling(refresh, useRealtimeInterval(matching && !slow ? 4_000 : 15_000));

  async function message(userId: string) {
    try {
      const d = await apiPost<{ conversation: { id: string } }>('/conversations', { candidateId: userId });
      navigate(`${user?.role === 'jobseeker' ? '/jobseeker' : '/employer'}/messages?conversation=${d.conversation.id}`);
    } catch (e: unknown) {
      toast.error(errorMessage(e));
    }
  }

  const notifiedCount = item?.notified_count ?? confirmed.notifiedCount;
  const responseCount = item?.responseCount ?? 0;

  return (
    <Card className="bg-gradient-to-br from-emerald-500/10 to-violet-500/[.06] border-emerald-400/20">
      <CardContent className="p-6 sm:p-8">
        <Badge className="bg-emerald-500/15 text-emerald-300">
          <CheckCircle2 size={13} className="mr-1" /> We're on it
        </Badge>
        <h1 className="text-2xl sm:text-3xl font-bold mt-3">Your urgent request is live.</h1>
        <p className="text-slate-300 mt-2 flex items-center gap-1.5">
          <Clock3 size={15} /> Expect your first response {confirmed.responseTimePromise}.
        </p>
        {matching && slow && (
          <p className="text-slate-300 mt-3 text-sm" data-testid="urgent-matching-fallback">
            Your request is live. We're still lining up musicians — the count will appear here, and we'll email you when
            someone responds.
          </p>
        )}
        <div className="grid grid-cols-2 gap-3 mt-6">
          <div className="rounded-xl border border-white/10 bg-black/20 p-4 text-center">
            <div className="text-2xl font-bold" data-testid="urgent-notified-count">
              {matching ? '…' : notifiedCount}
            </div>
            <div className="text-xs text-slate-400 mt-1">
              {matching ? (slow ? 'Musicians being notified' : 'Finding musicians for you') : 'Musicians notified'}
            </div>
          </div>
          <div className="rounded-xl border border-white/10 bg-black/20 p-4 text-center">
            <div className="text-2xl font-bold">{responseCount}</div>
            <div className="text-xs text-slate-400 mt-1">Responses so far</div>
          </div>
        </div>
        {responses.length > 0 && (
          <div className="mt-6 space-y-2">
            <h2 className="font-semibold">Who's available</h2>
            {responses.map((r) => (
              <div
                key={r.user_id}
                className="rounded-xl border border-white/10 bg-black/15 p-3 flex justify-between items-center gap-3"
              >
                <div className="min-w-0">
                  <div className="font-medium">{r.name}</div>
                  {r.headline && <div className="text-sm text-violet-300 truncate">{r.headline}</div>}
                </div>
                <Button size="sm" variant="outline" onClick={() => void message(r.user_id)}>
                  <MessageCircle size={14} className="mr-1.5" /> Message
                </Button>
              </div>
            ))}
          </div>
        )}
        {user?.role !== 'jobseeker' && <PushOptIn variant="hirer" className="mt-6" />}
        <div className="flex flex-wrap gap-2 mt-7">
          <Button
            variant="outline"
            onClick={() => navigate(user?.role === 'jobseeker' ? '/jobseeker/urgent' : '/employer/urgent')}
          >
            Manage all urgent requests
          </Button>
          <Button variant="ghost" onClick={onNewRequest}>
            Post another
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
