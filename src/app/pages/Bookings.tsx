import { useEffect, useState } from "react";
import { Link, useLocation, useNavigate } from "react-router";
import { Navigation } from "../components/Navigation";
import { apiGet, apiPost } from "../lib/api";
import { Card, CardContent } from "../components/ui/card";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Badge } from "../components/ui/badge";
import { Field, FormDialog, textareaClass, useConfirm } from "../components/booking/BookingDialogs";
import { toast } from "sonner";
import { BookingDepositPanel } from "../components/BookingDepositPanel";

const money = (currency: string, value: any) => `${currency || "INR"} ${Number(value || 0).toLocaleString("en-IN")}`;
const formatDate = (value: any) => {
  if (!value) return "Date to be confirmed";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? String(value) : date.toLocaleDateString(undefined, { dateStyle: "medium" } as any);
};

// Mirrors BookingRequest::OWNER_TRANSITIONS / REQUESTER_TRANSITIONS; the API also sends allowedTransitions.
const OWNER_TRANSITIONS: Record<string, string[]> = {
  requested: ["viewed", "negotiating", "declined"],
  viewed: ["negotiating", "declined"],
  quoted: ["negotiating", "declined"],
  negotiating: ["declined"],
  accepted: ["completed", "disputed"],
};
const REQUESTER_TRANSITIONS: Record<string, string[]> = {
  requested: ["negotiating", "cancelled"],
  viewed: ["negotiating", "cancelled"],
  quoted: ["accepted", "negotiating", "cancelled"],
  negotiating: ["accepted", "cancelled"],
  accepted: ["cancelled", "disputed"],
};
const QUOTABLE = ["requested", "viewed", "negotiating", "quoted"];
const STATUS_LABEL: Record<string, string> = {
  requested: "Enquiry sent",
  viewed: "Viewed",
  quoted: "Quote received",
  negotiating: "Negotiating",
  accepted: "Accepted · deposit due",
  completed: "Completed",
  disputed: "In dispute",
  declined: "Declined",
  cancelled: "Cancelled",
};

function allowed(b: any): string[] {
  if (Array.isArray(b.allowedTransitions)) return b.allowedTransitions;
  return (b.isOwner ? OWNER_TRANSITIONS : REQUESTER_TRANSITIONS)[b.status] || [];
}
function statusLabel(b: any) {
  if (b.status === "accepted" && b.depositPaid) return "Confirmed · deposit paid";
  return STATUS_LABEL[b.status] || b.status;
}
function nextStep(b: any): string {
  const quoted = Boolean(b.latestQuote);
  if (b.isOwner) {
    if (["requested", "viewed"].includes(b.status)) return "Send a quote or decline this enquiry.";
    if (b.status === "negotiating") return "The client asked for changes. Send a revised quote.";
    if (b.status === "quoted") return "Waiting for the client to accept your quote.";
    if (b.status === "accepted") return b.depositPaid ? "Deposit received. Mark the booking completed after the event." : "Waiting for the client to pay the deposit.";
  } else {
    if (["requested", "viewed"].includes(b.status)) return "Waiting for the act to send a quote.";
    if (b.status === "negotiating") return quoted ? "You asked for changes. Accept the current quote or wait for a revised one." : "Waiting for the act to send a quote.";
    if (b.status === "quoted") return "Review the quote, then accept it or ask for changes.";
    if (b.status === "accepted") return b.depositPaid ? "Your booking is confirmed." : "Pay the deposit to confirm the booking.";
  }
  return "";
}

type QuoteForm = {
  id: string;
  requesterName: string;
  performanceFee: string;
  travelFee: string;
  productionFee: string;
  otherFee: string;
  currency: string;
  depositPercent: string;
  validUntil: string;
  inclusions: string;
  exclusions: string;
  cancellationTerms: string;
};
const wholeNumber = (value: string) => /^\d+$/.test(value.trim());
function quoteProblem(q: QuoteForm): string {
  if (!wholeNumber(q.performanceFee) || Number(q.performanceFee) <= 0) return "Enter a performance fee as a whole number above zero.";
  for (const [label, value] of [["Travel", q.travelFee], ["Production", q.productionFee], ["Other", q.otherFee]] as const) {
    if (value.trim() && !wholeNumber(value)) return `${label} fee must be a whole number of 0 or more.`;
  }
  if (!/^[A-Z]{3}$/.test(q.currency.trim())) return "Currency must be a 3-letter code such as INR.";
  if (!wholeNumber(q.depositPercent) || Number(q.depositPercent) < 1 || Number(q.depositPercent) > 100) return "Deposit must be between 1% and 100%.";
  if (q.validUntil && new Date(`${q.validUntil}T23:59:59`).getTime() <= Date.now()) return "The quote must stay valid until a future date.";
  if (!q.cancellationTerms.trim()) return "Add cancellation and refund terms.";
  return "";
}

export default function Bookings() {
  const base = `/${useLocation().pathname.split("/")[1] || "employer"}`;
  const [rows, setRows] = useState<any[]>([]),
    [loading, setLoading] = useState(true),
    [loadError, setLoadError] = useState(""),
    [quote, setQuote] = useState<QuoteForm | null>(null),
    [quoteError, setQuoteError] = useState(""),
    [sendingQuote, setSendingQuote] = useState(false),
    [payments, setPayments] = useState<Record<string, any[]>>({}),
    [paymentOpen, setPaymentOpen] = useState<Record<string, boolean>>({});
  const { ask, element: confirmDialog } = useConfirm();
  async function load() {
    try {
      const d = await apiGet<any>("/bookings");
      setRows(d.bookings || []);
      setLoadError("");
    } catch (e: any) {
      setLoadError(e.message || "Unable to load bookings.");
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    void load();
  }, []);
  async function changeStatus(id: string, s: string, success: string) {
    await apiPost(`/bookings/${id}/status`, { status: s });
    toast.success(success);
    await load();
  }
  async function sendQuote() {
    if (!quote || sendingQuote) return;
    const problem = quoteProblem(quote);
    if (problem) return setQuoteError(problem);
    setSendingQuote(true);
    setQuoteError("");
    try {
      await apiPost(`/bookings/${quote.id}/quote`, {
        performanceFee: Number(quote.performanceFee),
        travelFee: Number(quote.travelFee) || 0,
        productionFee: Number(quote.productionFee) || 0,
        otherFee: Number(quote.otherFee) || 0,
        currency: quote.currency.trim() || "INR",
        depositPercent: Number(quote.depositPercent) || 50,
        validUntil: quote.validUntil || null,
        inclusions: quote.inclusions,
        exclusions: quote.exclusions,
        cancellationTerms: quote.cancellationTerms,
      });
      toast.success("Quote sent");
      setQuote(null);
      await load();
    } catch (e: any) {
      setQuoteError(e.message || "Unable to send the quote.");
    } finally {
      setSendingQuote(false);
    }
  }
  async function togglePayments(id: string) {
    if (paymentOpen[id]) {
      setPaymentOpen((x) => ({ ...x, [id]: false }));
      return;
    }
    try {
      const d = await apiGet<any>(`/bookings/${id}/payments`);
      setPayments((x) => ({ ...x, [id]: d.payments || [] }));
      setPaymentOpen((x) => ({ ...x, [id]: true }));
    } catch (e: any) {
      toast.error(e.message);
    }
  }
  async function paymentsChanged(id: string) {
    await load();
    if (paymentOpen[id]) {
      const d = await apiGet<any>(`/bookings/${id}/payments`).catch(() => null);
      if (d) setPayments((x) => ({ ...x, [id]: d.payments || [] }));
    }
  }
  const nav = useNavigate();
  async function message(id: string) {
    try {
      const d = await apiPost<any>("/conversations", { bookingId: id });
      nav(`${base}/messages?c=${d.id}`);
    } catch (e: any) {
      toast.error(e.message);
    }
  }
  const beginQuote = (b: any) => {
    const last = b.latestQuote;
    setQuoteError("");
    setQuote({
      id: b.id,
      requesterName: b.requesterName,
      performanceFee: last ? String(last.performanceFee ?? "") : "",
      travelFee: last ? String(last.travelFee ?? "") : "",
      productionFee: last ? String(last.productionFee ?? "") : "",
      otherFee: last ? String(last.otherFee ?? "") : "",
      currency: last?.currency || b.currency || "INR",
      depositPercent: String(last?.depositPercent ?? 50),
      validUntil: "",
      inclusions: last?.inclusions || "",
      exclusions: last?.exclusions || "",
      cancellationTerms: last?.cancellationTerms || "",
    });
  };
  const confirmStatus = (b: any, s: string) => {
    const q = b.latestQuote;
    const copy: Record<string, [string, string, string, boolean]> = {
      accepted: [
        "Accept this quote?",
        q
          ? `You agree to ${money(q.currency, q.total)} with a ${q.depositPercent}% deposit (${money(q.currency, Math.round((q.total * q.depositPercent) / 100))}) due next.`
          : "You agree to the latest quote.",
        "Accept quote",
        false,
      ],
      negotiating: ["Ask for a revised quote?", "The act is told you want changes. Use Messages to explain what should change.", "Ask for changes", false],
      cancelled: [
        b.status === "accepted" ? "Cancel this booking?" : "Cancel this enquiry?",
        b.depositPaid ? "Your deposit is handled under the act's cancellation terms. This cannot be undone." : "The act is notified and the enquiry closes. This cannot be undone.",
        b.status === "accepted" ? "Cancel booking" : "Cancel enquiry",
        true,
      ],
      declined: ["Decline this enquiry?", `${b.requesterName || "The client"} will see the enquiry as declined. This cannot be undone.`, "Decline", true],
      completed: [
        "Mark this booking completed?",
        b.depositPaid ? "Confirm the event took place." : "No deposit has been recorded for this booking. Only continue if the event took place.",
        "Mark completed",
        false,
      ],
      disputed: ["Report a problem with this booking?", "The booking moves to dispute so the Verse team can review it.", "Report problem", true],
    };
    const [title, description, confirmLabel, destructive] = copy[s];
    const success: Record<string, string> = {
      accepted: "Quote accepted. Pay the deposit to confirm.",
      negotiating: "Asked for a revised quote",
      cancelled: "Booking cancelled",
      declined: "Enquiry declined",
      completed: "Booking marked completed",
      disputed: "Problem reported",
    };
    ask({ title, description, confirmLabel, destructive, action: () => changeStatus(b.id, s, success[s]) });
  };
  const setQ = (key: keyof QuoteForm, value: string) => setQuote((current) => (current ? { ...current, [key]: value } : current));
  return (
    <div className="min-h-screen bg-slate-950 text-white">
      <Navigation />
      <main className="max-w-6xl mx-auto px-4 sm:px-5 pt-28 pb-24">
        <h1 className="text-3xl sm:text-4xl font-bold">Bookings</h1>
        <p className="text-slate-400 mt-2">Availability enquiries, complete commercial terms and payment records in one place.</p>
        {loading ? (
          <p className="text-slate-400 text-center py-16" role="status">
            Loading bookings…
          </p>
        ) : loadError ? (
          <div className="text-center py-16" role="alert">
            <p className="text-rose-300">{loadError}</p>
            <Button variant="outline" className="mt-4" onClick={() => void load()}>
              Try again
            </Button>
          </div>
        ) : rows.length === 0 ? (
          <div className="mt-7 rounded-xl border border-dashed border-white/15 p-10 text-center">
            <p className="text-slate-300 font-medium">No bookings yet</p>
            <p className="text-sm text-slate-500 mt-1">Enquiries you send, and enquiries for acts you own, appear here.</p>
            <div className="flex flex-wrap justify-center gap-3 mt-5">
              <Button asChild>
                <Link to={`${base}/book-talent`}>Book talent</Link>
              </Button>
              <Button asChild variant="outline">
                <Link to={`${base}/acts`}>Manage your acts</Link>
              </Button>
            </div>
          </div>
        ) : (
          <div className="space-y-4 mt-7">
            {rows.map((b) => {
              const can = allowed(b);
              const hint = nextStep(b);
              return (
                <Card key={b.id} className="bg-white/[.055] border-white/10" data-testid="booking-card">
                  <CardContent className="p-5">
                    <div className="flex flex-col md:flex-row justify-between gap-4">
                      <div className="min-w-0">
                        <div className="flex flex-wrap gap-2 items-center">
                          <h2 className="font-semibold text-lg break-words">{b.actName}</h2>
                          <Badge>{statusLabel(b)}</Badge>
                        </div>
                        <p className="text-sm text-slate-400 mt-2 break-words">
                          <span className="capitalize">{String(b.event_type || "event").replace(/-/g, " ")}</span> · {formatDate(b.event_date)} ·{" "}
                          {b.city}
                          {b.venue_name ? ` · ${b.venue_name}` : ""}
                        </p>
                        <p className="text-sm mt-2">{b.isOwner ? `Enquiry from ${b.requesterName}` : "Your booking enquiry"}</p>
                        {hint && <p className="text-sm text-violet-200 mt-2">{hint}</p>}
                      </div>
                      <div className="flex gap-2 flex-wrap items-start md:justify-end">
                        {b.isOwner && QUOTABLE.includes(b.status) && (
                          <Button size="sm" onClick={() => beginQuote(b)}>
                            {b.latestQuote ? "Revise quote" : "Send quote"}
                          </Button>
                        )}
                        {b.isRequester && can.includes("accepted") && b.latestQuote && (
                          <Button size="sm" onClick={() => confirmStatus(b, "accepted")}>
                            Accept quote
                          </Button>
                        )}
                        {b.isRequester && b.status === "quoted" && can.includes("negotiating") && (
                          <Button size="sm" variant="outline" onClick={() => confirmStatus(b, "negotiating")}>
                            Ask for changes
                          </Button>
                        )}
                        <BookingDepositPanel booking={b} onChanged={() => paymentsChanged(b.id)} />
                        {can.includes("completed") && (
                          <Button size="sm" onClick={() => confirmStatus(b, "completed")}>
                            Mark completed
                          </Button>
                        )}
                        {can.includes("declined") && (
                          <Button size="sm" variant="outline" onClick={() => confirmStatus(b, "declined")}>
                            Decline
                          </Button>
                        )}
                        {can.includes("cancelled") && (
                          <Button size="sm" variant="outline" onClick={() => confirmStatus(b, "cancelled")}>
                            {b.status === "accepted" ? "Cancel booking" : "Cancel enquiry"}
                          </Button>
                        )}
                        {can.includes("disputed") && (
                          <Button size="sm" variant="ghost" onClick={() => confirmStatus(b, "disputed")}>
                            Report a problem
                          </Button>
                        )}
                        <Button size="sm" variant="outline" className="max-w-full min-w-0" onClick={() => message(b.id)}>
                          <span className="truncate max-w-[16rem]">Message {b.isOwner ? b.requesterName : b.actName}</span>
                        </Button>
                        <Button size="sm" variant="ghost" onClick={() => togglePayments(b.id)} aria-expanded={Boolean(paymentOpen[b.id])}>
                          {paymentOpen[b.id] ? "Hide payments" : "Payment history"} ({b.paymentCount || 0})
                        </Button>
                      </div>
                    </div>
                    {b.latestQuote && (
                      <section className="mt-5 rounded-xl border border-white/10 bg-black/20 p-4">
                        <div className="flex flex-wrap justify-between gap-2">
                          <h3 className="font-semibold">Latest quote · {money(b.latestQuote.currency, b.latestQuote.total)}</h3>
                          <span className="text-sm text-emerald-300">
                            Deposit {b.latestQuote.depositPercent}%
                            {b.latestQuote.validUntil ? ` · valid until ${new Date(b.latestQuote.validUntil).toLocaleDateString()}` : ""}
                          </span>
                        </div>
                        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-2 mt-3 text-xs text-slate-400">
                          <span>Performance: {money(b.latestQuote.currency, b.latestQuote.performanceFee)}</span>
                          <span>Travel: {money(b.latestQuote.currency, b.latestQuote.travelFee)}</span>
                          <span>Production: {money(b.latestQuote.currency, b.latestQuote.productionFee)}</span>
                          <span>Other: {money(b.latestQuote.currency, b.latestQuote.otherFee)}</span>
                        </div>
                        {b.latestQuote.inclusions && (
                          <p className="text-sm mt-3 break-words">
                            <b>Includes:</b> {b.latestQuote.inclusions}
                          </p>
                        )}
                        {b.latestQuote.exclusions && (
                          <p className="text-sm mt-2 break-words">
                            <b>Excludes:</b> {b.latestQuote.exclusions}
                          </p>
                        )}
                        {b.latestQuote.cancellationTerms && (
                          <p className="text-sm mt-2 break-words">
                            <b>Cancellation:</b> {b.latestQuote.cancellationTerms}
                          </p>
                        )}
                      </section>
                    )}
                    {paymentOpen[b.id] && (
                      <section className="mt-4 border-t border-white/10 pt-4">
                        <h3 className="font-semibold text-sm">Payment history</h3>
                        {(payments[b.id] || []).length === 0 ? (
                          <p className="text-sm text-slate-500 mt-2">No payments recorded.</p>
                        ) : (
                          <div className="space-y-2 mt-2">
                            {payments[b.id].map((p) => (
                              <div key={p.id} className="flex flex-wrap justify-between gap-2 text-sm rounded-lg bg-white/[.04] p-3">
                                <span>
                                  {p.kind} · {money(p.currency, p.amount)}
                                </span>
                                <span>
                                  {p.status} · {new Date(p.created_at).toLocaleString()}
                                </span>
                              </div>
                            ))}
                          </div>
                        )}
                      </section>
                    )}
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}
        <FormDialog
          open={Boolean(quote)}
          onOpenChange={(open) => !open && setQuote(null)}
          title={`Quote ${quote?.requesterName || ""}`.trim()}
          description="Every quote is a new version; the client sees the latest one."
          submitLabel="Send quote"
          busyLabel="Sending…"
          busy={sendingQuote}
          error={quoteError}
          wide
          onSubmit={sendQuote}
        >
          {quote && (
            <>
              <div className="grid sm:grid-cols-2 gap-3">
                <Field label="Performance fee" htmlFor="quote-performance">
                  <Input id="quote-performance" inputMode="numeric" type="number" min="1" value={quote.performanceFee} onChange={(e) => setQ("performanceFee", e.target.value)} />
                </Field>
                <Field label="Currency" htmlFor="quote-currency">
                  <Input id="quote-currency" maxLength={3} value={quote.currency} onChange={(e) => setQ("currency", e.target.value.toUpperCase())} />
                </Field>
                <Field label="Travel fee" htmlFor="quote-travel">
                  <Input id="quote-travel" inputMode="numeric" type="number" min="0" value={quote.travelFee} onChange={(e) => setQ("travelFee", e.target.value)} />
                </Field>
                <Field label="Production fee" htmlFor="quote-production">
                  <Input id="quote-production" inputMode="numeric" type="number" min="0" value={quote.productionFee} onChange={(e) => setQ("productionFee", e.target.value)} />
                </Field>
                <Field label="Other fee" htmlFor="quote-other">
                  <Input id="quote-other" inputMode="numeric" type="number" min="0" value={quote.otherFee} onChange={(e) => setQ("otherFee", e.target.value)} />
                </Field>
                <Field label="Deposit %" htmlFor="quote-deposit">
                  <Input id="quote-deposit" inputMode="numeric" type="number" min="1" max="100" value={quote.depositPercent} onChange={(e) => setQ("depositPercent", e.target.value)} />
                </Field>
                <Field label="Valid until (optional)" htmlFor="quote-valid">
                  <Input id="quote-valid" type="date" value={quote.validUntil} onChange={(e) => setQ("validUntil", e.target.value)} />
                </Field>
              </div>
              <Field label="What the quote includes" htmlFor="quote-inclusions">
                <textarea id="quote-inclusions" className={textareaClass} value={quote.inclusions} onChange={(e) => setQ("inclusions", e.target.value)} />
              </Field>
              <Field label="What is excluded" htmlFor="quote-exclusions">
                <textarea id="quote-exclusions" className={textareaClass} value={quote.exclusions} onChange={(e) => setQ("exclusions", e.target.value)} />
              </Field>
              <Field label="Cancellation and refund terms" htmlFor="quote-cancellation">
                <textarea id="quote-cancellation" className={textareaClass} value={quote.cancellationTerms} onChange={(e) => setQ("cancellationTerms", e.target.value)} />
              </Field>
            </>
          )}
        </FormDialog>
        {confirmDialog}
      </main>
    </div>
  );
}
