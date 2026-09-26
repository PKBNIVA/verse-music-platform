import { useEffect, useState, type FormEvent } from "react";
import { Navigation } from "../components/Navigation";
import { Card, CardContent } from "../components/ui/card";
import { Input } from "../components/ui/input";
import { Button } from "../components/ui/button";
import { Badge } from "../components/ui/badge";
import { apiGet, apiPatch, apiPost } from "../lib/api";
import { toast } from "sonner";
import { useAuth } from "../lib/authContext";
import { Field, FormDialog, textareaClass, useConfirm } from "../components/booking/BookingDialogs";
import { Clock3, Zap } from "lucide-react";

type Draft = { title: string; roleName: string; instrument: string; city: string; startAt: string; endAt: string; budgetMin: string; budgetMax: string; requirements: string };
const emptyDraft: Draft = { title: "", roleName: "", instrument: "", city: "", startAt: "", endAt: "", budgetMin: "", budgetMax: "", requirements: "" };
const toIso = (local: string) => (local ? new Date(local).toISOString() : null);
const whole = (v: string) => /^\d+$/.test(v.trim());

function draftProblem(d: Draft): string {
  if (!d.title.trim() || !d.roleName.trim() || !d.city.trim() || !d.startAt) return "Add a title, role, city and start time.";
  const start = new Date(d.startAt).getTime();
  if (Number.isNaN(start)) return "Choose a valid start time.";
  if (start < Date.now() - 60_000) return "The start time cannot be in the past.";
  if (d.endAt && new Date(d.endAt).getTime() <= start) return "The end time must be after the start.";
  for (const v of [d.budgetMin, d.budgetMax]) if (v.trim() && !whole(v)) return "Budgets must be whole numbers.";
  if (d.budgetMin.trim() && d.budgetMax.trim() && Number(d.budgetMax) < Number(d.budgetMin)) return "Maximum budget must be at least the minimum.";
  return "";
}

export default function UrgentRequests() {
  const { user } = useAuth();
  const [items, setItems] = useState<any[]>([]),
    [loading, setLoading] = useState(true),
    [loadError, setLoadError] = useState(""),
    [city, setCity] = useState(""),
    [role, setRole] = useState(""),
    [responses, setResponses] = useState<Record<string, any[]>>({}),
    [expanded, setExpanded] = useState<string | null>(null),
    [draft, setDraft] = useState<Draft | null>(null),
    [reply, setReply] = useState<{ request: any; message: string; rate: string } | null>(null),
    [formError, setFormError] = useState(""),
    // The mutation in flight ("create" or a request id); others wait so nothing is submitted twice.
    [pending, setPending] = useState<string | null>(null);
  const { ask, element: confirmDialog } = useConfirm();
  async function load() {
    const p = new URLSearchParams();
    if (city.trim()) p.set("city", city.trim());
    if (role.trim()) p.set("role", role.trim());
    try {
      const d = await apiGet<any>(`/urgent-requests?${p}`);
      setItems(d.requests || []);
      setLoadError("");
    } catch (e: any) {
      setLoadError(e.message || "Unable to load urgent requests.");
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    void load();
  }, []);
  async function create() {
    if (!draft || pending) return;
    const problem = draftProblem(draft);
    if (problem) return setFormError(problem);
    setPending("create");
    setFormError("");
    try {
      await apiPost("/urgent-requests", {
        title: draft.title.trim(),
        roleName: draft.roleName.trim(),
        instrument: draft.instrument.trim() || null,
        city: draft.city.trim(),
        startAt: toIso(draft.startAt),
        endAt: toIso(draft.endAt),
        budgetMin: draft.budgetMin.trim() ? Number(draft.budgetMin) : null,
        budgetMax: draft.budgetMax.trim() ? Number(draft.budgetMax) : null,
        requirements: draft.requirements.trim() || null,
      });
      toast.success("Urgent request published");
      setDraft(null);
      await load();
    } catch (e: any) {
      setFormError(e.message || "Unable to publish this request.");
    } finally {
      setPending(null);
    }
  }
  async function respond() {
    if (!reply || pending) return;
    if (reply.rate.trim() && !whole(reply.rate)) return setFormError("Rate must be a whole number.");
    if (reply.message.length > 1000) return setFormError("Keep your note under 1,000 characters.");
    setPending(reply.request.id);
    setFormError("");
    try {
      await apiPost(`/urgent-requests/${reply.request.id}/respond`, {
        message: reply.message.trim(),
        rate: reply.rate.trim() ? Number(reply.rate) : null,
      });
      toast.success("Availability sent");
      setReply(null);
      await load();
    } catch (e: any) {
      setFormError(e.message || "Unable to send your availability.");
    } finally {
      setPending(null);
    }
  }
  async function viewResponses(id: string) {
    if (expanded === id) return setExpanded(null);
    try {
      const data = await apiGet<any>(`/urgent-requests/${id}/responses`);
      setResponses((current) => ({ ...current, [id]: data.responses || [] }));
      setExpanded(id);
    } catch (e: any) {
      toast.error(e.message);
    }
  }
  const closeRequest = (r: any, status: "filled" | "cancelled") =>
    ask({
      title: status === "filled" ? "Mark this request filled?" : "Cancel this request?",
      description: "It stops appearing to professionals and cannot be reopened.",
      confirmLabel: status === "filled" ? "Mark filled" : "Cancel request",
      destructive: status === "cancelled",
      action: async () => {
        await apiPatch(`/urgent-requests/${r.id}`, { status });
        toast.success(status === "filled" ? "Request marked filled" : "Request cancelled");
        setExpanded(null);
        await load();
      },
    });
  const filter = (e: FormEvent) => {
    e.preventDefault();
    setLoading(true);
    void load();
  };
  const setD = (key: keyof Draft, value: string) => setDraft((current) => (current ? { ...current, [key]: value } : current));
  return (
    <div className="min-h-screen bg-slate-950 text-white">
      <Navigation />
      <main className="max-w-6xl mx-auto px-4 sm:px-5 pt-28 pb-16">
        <div className="flex flex-col md:flex-row md:items-end justify-between gap-4">
          <div>
            <p className="text-xs uppercase tracking-[.22em] text-orange-300">Urgent replacement network</p>
            <h1 className="text-3xl sm:text-4xl font-bold mt-2">Need someone fast?</h1>
            <p className="text-slate-400 mt-2">Find a last-minute musician or production professional by role, city and exact time.</p>
          </div>
          <Button
            onClick={() => {
              setFormError("");
              setDraft({ ...emptyDraft });
            }}
            disabled={pending !== null}
          >
            <Zap size={16} className="mr-2" />
            Post urgent need
          </Button>
        </div>
        <form role="search" onSubmit={filter} className="grid md:grid-cols-[1fr_1fr_auto] gap-3 mt-7">
          <Input aria-label="Role" value={role} onChange={(e) => setRole(e.target.value)} placeholder="Drummer, playback engineer…" className="bg-white/5 border-white/15" />
          <Input aria-label="City" value={city} onChange={(e) => setCity(e.target.value)} placeholder="City" className="bg-white/5 border-white/15" />
          <Button type="submit" variant="outline">
            Filter
          </Button>
        </form>
        {loading ? (
          <p className="text-slate-400 text-center py-16" role="status">
            Loading urgent requests…
          </p>
        ) : loadError ? (
          <div className="text-center py-16" role="alert">
            <p className="text-rose-300">{loadError}</p>
            <Button variant="outline" className="mt-4" onClick={() => void load()}>
              Try again
            </Button>
          </div>
        ) : items.length === 0 ? (
          <div className="mt-7 rounded-xl border border-dashed border-white/15 p-10 text-center text-slate-500">
            {city || role ? "No open requests match these filters." : "No open urgent requests right now. Post one when you need cover fast."}
          </div>
        ) : (
          <div className="grid gap-4 mt-7">
            {items.map((r) => (
              <Card key={r.id} className="bg-white/[.055] border-white/10">
                <CardContent className="p-5">
                  <div className="flex flex-col sm:flex-row justify-between gap-4">
                    <div className="min-w-0">
                      <div className="flex flex-wrap gap-2">
                        <Badge className="bg-orange-500/15 text-orange-200 capitalize">{r.status === "open" ? "Urgent" : r.status}</Badge>
                        {r.requesterVerified && <Badge variant="secondary">Verified requester</Badge>}
                      </div>
                      <h2 className="text-xl font-semibold mt-3 break-words">{r.title}</h2>
                      <p className="text-violet-300">
                        {r.role_name}
                        {r.instrument ? ` · ${r.instrument}` : ""}
                      </p>
                      <p className="text-sm text-slate-400 mt-2">
                        {r.city} · <Clock3 size={14} className="inline mr-1" />
                        {new Date(r.start_at).toLocaleString()}
                      </p>
                      {Boolean(r.budget_min || r.budget_max) && (
                        <p className="text-sm text-emerald-300 mt-1">
                          Budget {r.currency} {[r.budget_min, r.budget_max].filter(Boolean).map((x: any) => Number(x).toLocaleString("en-IN")).join(" – ")}
                        </p>
                      )}
                      {r.requirements && <p className="text-sm text-slate-300 mt-2 break-words">{r.requirements}</p>}
                    </div>
                    {r.requester_id === user?.id ? (
                      <div className="flex flex-wrap sm:justify-end gap-2 items-start">
                        <Button variant="secondary" onClick={() => viewResponses(r.id)} aria-expanded={expanded === r.id}>
                          Responses ({r.responseCount || 0})
                        </Button>
                        {r.status === "open" && (
                          <>
                            <Button variant="outline" onClick={() => closeRequest(r, "filled")}>
                              Mark filled
                            </Button>
                            <Button variant="ghost" onClick={() => closeRequest(r, "cancelled")}>
                              Cancel request
                            </Button>
                          </>
                        )}
                      </div>
                    ) : user?.role === "jobseeker" && r.status === "open" ? (
                      <Button
                        className="self-start"
                        variant={r.myResponse ? "outline" : "default"}
                        onClick={() => {
                          setFormError("");
                          setReply({ request: r, message: "", rate: "" });
                        }}
                        disabled={pending !== null}
                      >
                        {r.myResponse ? "Update response" : "I’m available"}
                      </Button>
                    ) : (
                      r.status === "open" && <p className="text-xs text-slate-500 sm:max-w-40">Professionals respond to this request.</p>
                    )}
                  </div>
                  {expanded === r.id && (
                    <div className="mt-5 border-t border-white/10 pt-4">
                      <h3 className="font-semibold">Available professionals</h3>
                      <div className="mt-3 space-y-2">
                        {(responses[r.id] || []).map((response: any) => (
                          <div key={response.user_id} className="rounded-xl border border-white/10 bg-black/15 p-3">
                            <div className="font-medium">{response.name}</div>
                            <div className="text-sm text-violet-300">{response.headline || "Music professional"}</div>
                            {response.message && <p className="mt-2 text-sm text-slate-300 break-words">{response.message}</p>}
                            {response.rate != null && (
                              <p className="mt-1 text-sm text-emerald-300">
                                Rate: {r.currency} {Number(response.rate).toLocaleString("en-IN")}
                              </p>
                            )}
                          </div>
                        ))}
                        {!(responses[r.id] || []).length && <p className="text-sm text-slate-500">No responses yet.</p>}
                      </div>
                    </div>
                  )}
                </CardContent>
              </Card>
            ))}
          </div>
        )}
        <FormDialog
          open={Boolean(draft)}
          onOpenChange={(open) => !open && setDraft(null)}
          title="Post an urgent need"
          description="Visible to professionals until you mark it filled or cancel it."
          submitLabel="Publish request"
          busyLabel="Publishing…"
          busy={pending === "create"}
          error={formError}
          wide
          onSubmit={create}
        >
          {draft && (
            <>
              <Field label="Title" htmlFor="urgent-title">
                <Input id="urgent-title" placeholder="Drummer needed for tonight's show" value={draft.title} onChange={(e) => setD("title", e.target.value)} />
              </Field>
              <div className="grid sm:grid-cols-2 gap-3">
                <Field label="Role needed" htmlFor="urgent-role">
                  <Input id="urgent-role" placeholder="Drummer / FOH engineer" value={draft.roleName} onChange={(e) => setD("roleName", e.target.value)} />
                </Field>
                <Field label="Instrument (optional)" htmlFor="urgent-instrument">
                  <Input id="urgent-instrument" value={draft.instrument} onChange={(e) => setD("instrument", e.target.value)} />
                </Field>
                <Field label="City" htmlFor="urgent-city">
                  <Input id="urgent-city" value={draft.city} onChange={(e) => setD("city", e.target.value)} />
                </Field>
                <Field label="Starts" htmlFor="urgent-start">
                  <Input id="urgent-start" type="datetime-local" value={draft.startAt} onChange={(e) => setD("startAt", e.target.value)} />
                </Field>
                <Field label="Ends (optional)" htmlFor="urgent-end">
                  <Input id="urgent-end" type="datetime-local" min={draft.startAt} value={draft.endAt} onChange={(e) => setD("endAt", e.target.value)} />
                </Field>
                <div className="grid grid-cols-2 gap-3">
                  <Field label="Budget min" htmlFor="urgent-budget-min">
                    <Input id="urgent-budget-min" type="number" min="0" value={draft.budgetMin} onChange={(e) => setD("budgetMin", e.target.value)} />
                  </Field>
                  <Field label="Budget max" htmlFor="urgent-budget-max">
                    <Input id="urgent-budget-max" type="number" min="0" value={draft.budgetMax} onChange={(e) => setD("budgetMax", e.target.value)} />
                  </Field>
                </div>
              </div>
              <Field label="Details (optional)" htmlFor="urgent-requirements">
                <textarea id="urgent-requirements" className={textareaClass} value={draft.requirements} onChange={(e) => setD("requirements", e.target.value)} />
              </Field>
            </>
          )}
        </FormDialog>
        <FormDialog
          open={Boolean(reply)}
          onOpenChange={(open) => !open && setReply(null)}
          title={reply?.request?.myResponse ? "Update your availability" : "Tell them you're available"}
          description={reply?.request?.title}
          submitLabel="Send availability"
          busyLabel="Sending…"
          busy={Boolean(reply && pending === reply.request.id)}
          error={formError}
          onSubmit={respond}
        >
          {reply && (
            <>
              <Field label="Short availability note" htmlFor="urgent-reply-message">
                <textarea id="urgent-reply-message" maxLength={1000} className={textareaClass} value={reply.message} onChange={(e) => setReply({ ...reply, message: e.target.value })} />
              </Field>
              <Field label={`Your rate in ${reply.request.currency || "INR"} (optional)`} htmlFor="urgent-reply-rate">
                <Input id="urgent-reply-rate" type="number" min="0" value={reply.rate} onChange={(e) => setReply({ ...reply, rate: e.target.value })} />
              </Field>
            </>
          )}
        </FormDialog>
        {confirmDialog}
      </main>
    </div>
  );
}
