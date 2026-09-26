import { useEffect, useRef, useState, type FormEvent } from "react";
import { Link, useLocation, useNavigate, useSearchParams } from "react-router";
import { Navigation } from "../components/Navigation";
import { apiGet, apiPost } from "../lib/api";
import { useAuth } from "../lib/authContext";
import { Card, CardContent } from "../components/ui/card";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Badge } from "../components/ui/badge";
import { Field, FormDialog, selectClass, textareaClass } from "../components/booking/BookingDialogs";
import { Calendar, MapPin, ShieldCheck } from "lucide-react";
import { toast } from "sonner";

const EVENT_TYPES = ["wedding", "sangeet", "reception", "corporate", "festival", "concert", "private-party", "college", "brand-activation", "other"];
const today = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};

type Enquiry = {
  id: string;
  name: string;
  eventType: string;
  eventDate: string;
  eventCity: string;
  venueName: string;
  budgetMin: string;
  budgetMax: string;
  requirements: string;
};

function enquiryProblem(b: Enquiry): string {
  if (!b.eventDate) return "Choose the event date.";
  if (b.eventDate < today()) return "The event date cannot be in the past.";
  if (!b.eventCity.trim()) return "Add the event city.";
  for (const value of [b.budgetMin, b.budgetMax]) if (value.trim() && !/^\d+$/.test(value.trim())) return "Budgets must be whole numbers.";
  if (b.budgetMin.trim() && b.budgetMax.trim() && Number(b.budgetMax) < Number(b.budgetMin)) return "Maximum budget must be at least the minimum.";
  return "";
}

export default function BookTalent() {
  const { user } = useAuth();
  const base = `/${useLocation().pathname.split("/")[1] || "employer"}`;
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const [acts, setActs] = useState<any[]>([]),
    [loading, setLoading] = useState(true),
    [loadError, setLoadError] = useState(""),
    [q, setQ] = useState(""),
    [city, setCity] = useState(""),
    [booking, setBooking] = useState<Enquiry | null>(null),
    [formError, setFormError] = useState(""),
    [sending, setSending] = useState(false);
  const preselected = useRef<string | null>(null);

  async function load() {
    setLoading(true);
    try {
      const d = await apiGet<any>(`/acts?q=${encodeURIComponent(q.trim())}&city=${encodeURIComponent(city.trim())}`);
      setActs(d.acts || []);
      setLoadError("");
    } catch (e: any) {
      setLoadError(e.message || "Unable to load acts.");
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    void load();
  }, []);

  const openEnquiry = (a: any) => {
    setFormError("");
    setBooking({ id: a.id, name: a.name, eventType: "wedding", eventDate: "", eventCity: city || a.city || "", venueName: "", budgetMin: "", budgetMax: "", requirements: "" });
  };

  // Coming from a public act page (?act=<id>): open the enquiry for that act straight away.
  const actParam = params.get("act");
  useEffect(() => {
    if (!actParam || preselected.current === actParam) return;
    preselected.current = actParam;
    apiGet<any>(`/acts/${encodeURIComponent(actParam)}`)
      .then((d) => {
        const act = d.act;
        if (!act || act.status !== "active") throw new Error("This act is not currently taking bookings.");
        if (user && act.owner_id === user.id) throw new Error("This is your own act, so it cannot be booked.");
        openEnquiry(act);
      })
      .catch((e: any) => toast.error(e?.status === 404 ? "That act is no longer available for booking." : e.message || "Unable to open that act."));
  }, [actParam, user?.id]);

  const closeEnquiry = () => {
    setBooking(null);
    if (params.has("act")) {
      params.delete("act");
      setParams(params, { replace: true });
    }
  };

  async function send() {
    if (!booking || sending) return;
    const problem = enquiryProblem(booking);
    if (problem) return setFormError(problem);
    setSending(true);
    setFormError("");
    try {
      await apiPost("/bookings", {
        actId: booking.id,
        eventType: booking.eventType || "other",
        eventDate: booking.eventDate,
        city: booking.eventCity.trim(),
        venueName: booking.venueName.trim(),
        budgetMin: booking.budgetMin.trim() ? Number(booking.budgetMin) : null,
        budgetMax: booking.budgetMax.trim() ? Number(booking.budgetMax) : null,
        requirements: booking.requirements,
      });
      toast.success("Booking enquiry sent", { action: { label: "View bookings", onClick: () => navigate(`${base}/bookings`) } });
      closeEnquiry();
    } catch (e: any) {
      setFormError(e.message || "Unable to send the enquiry.");
    } finally {
      setSending(false);
    }
  }
  const setB = (key: keyof Enquiry, value: string) => setBooking((current) => (current ? { ...current, [key]: value } : current));
  const search = (e: FormEvent) => {
    e.preventDefault();
    void load();
  };

  return (
    <div className="min-h-screen bg-slate-950 text-white">
      <Navigation />
      <main className="max-w-7xl mx-auto px-4 sm:px-5 pt-28 pb-16">
        <div>
          <div className="text-xs uppercase tracking-[.2em] text-violet-300">Live entertainment marketplace</div>
          <h1 className="text-3xl sm:text-4xl font-bold mt-2">Book an artist, duo, band or ensemble</h1>
          <p className="text-slate-400 mt-2 max-w-3xl">
            Search a bookable act, then send one structured event brief with date, venue, budget and production details. Quotes stay comparable instead of
            disappearing into WhatsApp threads.
          </p>
        </div>
        <form role="search" onSubmit={search} className="grid md:grid-cols-[1fr_1fr_auto] gap-3 mt-7">
          <Input aria-label="Search acts" placeholder="Singer, jazz trio, wedding band…" value={q} onChange={(e) => setQ(e.target.value)} />
          <Input aria-label="City" placeholder="City" value={city} onChange={(e) => setCity(e.target.value)} />
          <Button type="submit" disabled={loading}>
            Search
          </Button>
        </form>
        {loading ? (
          <p className="text-slate-400 text-center py-16" role="status">
            Loading acts…
          </p>
        ) : loadError ? (
          <div className="text-center py-16" role="alert">
            <p className="text-rose-300">{loadError}</p>
            <Button variant="outline" className="mt-4" onClick={() => void load()}>
              Try again
            </Button>
          </div>
        ) : acts.length === 0 ? (
          <div className="mt-7 rounded-xl border border-dashed border-white/15 p-10 text-center">
            <p className="text-slate-300 font-medium">No acts match this search</p>
            <p className="text-sm text-slate-500 mt-1">Try a broader style, another city, or clear the filters.</p>
            {(q || city) && (
              <Button
                variant="outline"
                className="mt-4"
                onClick={() => {
                  setQ("");
                  setCity("");
                  setLoading(true);
                  apiGet<any>("/acts?q=&city=")
                    .then((d) => setActs(d.acts || []))
                    .catch((e: any) => setLoadError(e.message || "Unable to load acts."))
                    .finally(() => setLoading(false));
                }}
              >
                Clear filters
              </Button>
            )}
          </div>
        ) : (
          <div className="grid md:grid-cols-2 xl:grid-cols-3 gap-4 mt-7">
            {acts.map((a) => {
              const own = Boolean(user && a.owner_id && a.owner_id === user.id);
              return (
                <Card key={a.id} className="bg-white/[.055] border-white/10">
                  <CardContent className="p-5">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <Badge variant="secondary">{a.act_type}</Badge>
                        <h3 className="text-xl font-semibold mt-2 break-words">{a.name}</h3>
                      </div>
                      {(a.verified || a.ownerVerified) && <ShieldCheck aria-label="Verified" className="text-emerald-300 shrink-0" size={18} />}
                    </div>
                    <div className="text-sm text-slate-400 mt-3 flex gap-2 items-center">
                      <MapPin size={14} />
                      {a.city || "Flexible location"}
                    </div>
                    <div className="text-sm mt-3">{(Array.isArray(a.genres) && a.genres.slice(0, 5).join(" · ")) || "Multi-genre"}</div>
                    <div className="text-sm text-emerald-300 mt-4">{a.min_fee ? `From ${a.currency || "INR"} ${Number(a.min_fee).toLocaleString("en-IN")}` : "Ask for quote"}</div>
                    <div className="flex gap-2 mt-5">
                      <Button className="flex-1" onClick={() => openEnquiry(a)}>
                        <Calendar size={16} className="mr-2" />
                        Request availability
                      </Button>
                      <Button asChild variant="outline">
                        <Link to={`/acts/${a.id}`} aria-label={`View ${a.name}`}>
                          View
                        </Link>
                      </Button>
                    </div>
                    {own && <p className="text-xs text-slate-500 mt-2">This is one of your acts.</p>}
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}
        <FormDialog
          open={Boolean(booking)}
          onOpenChange={(open) => !open && closeEnquiry()}
          title={`Enquire for ${booking?.name || "this act"}`}
          description="No payment is taken until you accept a quote."
          submitLabel="Send enquiry"
          busyLabel="Sending…"
          busy={sending}
          error={formError}
          onSubmit={send}
        >
          {booking && (
            <>
              <Field label="Event type" htmlFor="enquiry-type">
                <select id="enquiry-type" className={selectClass} value={booking.eventType} onChange={(e) => setB("eventType", e.target.value)}>
                  {EVENT_TYPES.map((x) => (
                    <option key={x} value={x}>
                      {x.replace(/-/g, " ")}
                    </option>
                  ))}
                </select>
              </Field>
              <div className="grid sm:grid-cols-2 gap-3">
                <Field label="Event date" htmlFor="enquiry-date">
                  <Input id="enquiry-date" type="date" min={today()} value={booking.eventDate} onChange={(e) => setB("eventDate", e.target.value)} />
                </Field>
                <Field label="Event city" htmlFor="enquiry-city">
                  <Input id="enquiry-city" value={booking.eventCity} onChange={(e) => setB("eventCity", e.target.value)} />
                </Field>
              </div>
              <Field label="Venue (optional)" htmlFor="enquiry-venue">
                <Input id="enquiry-venue" value={booking.venueName} onChange={(e) => setB("venueName", e.target.value)} />
              </Field>
              <div className="grid grid-cols-2 gap-3">
                <Field label="Budget min" htmlFor="enquiry-budget-min">
                  <Input id="enquiry-budget-min" type="number" min="0" inputMode="numeric" value={booking.budgetMin} onChange={(e) => setB("budgetMin", e.target.value)} />
                </Field>
                <Field label="Budget max" htmlFor="enquiry-budget-max">
                  <Input id="enquiry-budget-max" type="number" min="0" inputMode="numeric" value={booking.budgetMax} onChange={(e) => setB("budgetMax", e.target.value)} />
                </Field>
              </div>
              <Field label="Requirements" htmlFor="enquiry-requirements">
                <textarea
                  id="enquiry-requirements"
                  className={textareaClass}
                  placeholder="Timing, audience size, songs/genre, production available, travel/accommodation…"
                  value={booking.requirements}
                  onChange={(e) => setB("requirements", e.target.value)}
                />
              </Field>
            </>
          )}
        </FormDialog>
      </main>
    </div>
  );
}
