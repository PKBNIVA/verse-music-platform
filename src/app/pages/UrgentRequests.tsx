import { useEffect, useState } from "react";
import { Navigation } from "../components/Navigation";
import { Card, CardContent } from "../components/ui/card";
import { Input } from "../components/ui/input";
import { Button } from "../components/ui/button";
import { Badge } from "../components/ui/badge";
import { apiGet, apiPatch, apiPost } from "../lib/api";
import { toast } from "sonner";
import { useAuth } from "../lib/authContext";
import { Clock3, Zap } from "lucide-react";
export default function UrgentRequests() {
  const { user } = useAuth();
  const [items, setItems] = useState<any[]>([]),
    [city, setCity] = useState(""),
    [role, setRole] = useState(""),
    [responses, setResponses] = useState<Record<string, any[]>>({}),
    [expanded, setExpanded] = useState<string | null>(null);
  async function load() {
    const p = new URLSearchParams();
    if (city) p.set("city", city);
    if (role) p.set("role", role);
    const d = await apiGet<any>(`/urgent-requests?${p}`);
    setItems(d.requests || []);
  }
  useEffect(() => {
    load();
  }, []);
  async function create() {
    const title = prompt("Urgent requirement title");
    if (!title) return;
    const roleName = prompt("Role needed, e.g. Drummer / FOH Engineer");
    if (!roleName) return;
    const city = prompt("City");
    if (!city) return;
    const startAt = prompt(
      "Start date/time in ISO or local format, e.g. 2026-10-04T18:00",
    );
    if (!startAt) return;
    try {
      await apiPost("/urgent-requests", { title, roleName, city, startAt });
      toast.success("Urgent request published");
      load();
    } catch (e: any) {
      toast.error(e.message);
    }
  }
  async function respond(r: any) {
    const message = prompt("Short availability note");
    if (message === null) return;
    const rate = prompt("Your rate (optional)");
    try {
      await apiPost(`/urgent-requests/${r.id}/respond`, {
        message,
        rate: rate ? Number(rate) : null,
      });
      toast.success("Availability sent");
      load();
    } catch (e: any) {
      toast.error(e.message);
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
  async function closeRequest(id: string, status: "filled" | "cancelled") {
    try {
      await apiPatch(`/urgent-requests/${id}`, { status });
      toast.success(status === "filled" ? "Request marked filled" : "Request cancelled");
      setExpanded(null);
      load();
    } catch (e: any) {
      toast.error(e.message);
    }
  }
  return (
    <div className="min-h-screen bg-slate-950 text-white">
      <Navigation />
      <main className="max-w-6xl mx-auto px-5 pt-28 pb-16">
        <div className="flex flex-col md:flex-row md:items-end justify-between gap-4">
          <div>
            <p className="text-xs uppercase tracking-[.22em] text-orange-300">
              Urgent replacement network
            </p>
            <h1 className="text-4xl font-bold mt-2">Need someone fast?</h1>
            <p className="text-slate-400 mt-2">
              Find a last-minute musician or production professional by role,
              city and exact time.
            </p>
          </div>
          <Button onClick={create}>
            <Zap size={16} className="mr-2" />
            Post urgent need
          </Button>
        </div>
        <div className="grid md:grid-cols-[1fr_1fr_auto] gap-3 mt-7">
          <Input
            value={role}
            onChange={(e) => setRole(e.target.value)}
            placeholder="Drummer, playback engineer…"
            className="bg-white/5 border-white/15"
          />
          <Input
            value={city}
            onChange={(e) => setCity(e.target.value)}
            placeholder="City"
            className="bg-white/5 border-white/15"
          />
          <Button variant="outline" onClick={load}>
            Filter
          </Button>
        </div>
        <div className="grid gap-4 mt-7">
          {items.map((r) => (
            <Card key={r.id} className="bg-white/[.055] border-white/10">
              <CardContent className="p-5">
                <div className="flex justify-between gap-4">
                  <div>
                    <div className="flex gap-2">
                      <Badge className="bg-orange-500/15 text-orange-200 capitalize">
                        {r.status === "open" ? "Urgent" : r.status}
                      </Badge>
                      {r.requesterVerified && (
                        <Badge variant="secondary">Verified requester</Badge>
                      )}
                    </div>
                    <h2 className="text-xl font-semibold mt-3">{r.title}</h2>
                    <p className="text-violet-300">
                      {r.role_name}
                      {r.instrument ? ` · ${r.instrument}` : ""}
                    </p>
                    <p className="text-sm text-slate-400 mt-2">
                      {r.city} · <Clock3 size={14} className="inline mr-1" />
                      {new Date(r.start_at).toLocaleString()}
                    </p>
                  </div>
                  {r.requester_id === user?.id ? (
                    <div className="flex flex-wrap justify-end gap-2">
                      <Button variant="secondary" onClick={() => viewResponses(r.id)}>
                        Responses ({r.responseCount || 0})
                      </Button>
                      {r.status === "open" && <><Button variant="outline" onClick={() => closeRequest(r.id, "filled")}>Mark filled</Button><Button variant="ghost" onClick={() => closeRequest(r.id, "cancelled")}>Cancel</Button></>}
                    </div>
                  ) : user?.role === "jobseeker" && r.status === "open" && (
                    <Button
                      variant={r.myResponse ? "outline" : "default"}
                      onClick={() => respond(r)}
                    >
                      {r.myResponse ? "Update response" : "I’m available"}
                    </Button>
                  )}
                </div>
                {expanded === r.id && <div className="mt-5 border-t border-white/10 pt-4"><h3 className="font-semibold">Available professionals</h3><div className="mt-3 space-y-2">{(responses[r.id]||[]).map((response:any)=><div key={response.user_id} className="rounded-xl border border-white/10 bg-black/15 p-3"><div className="font-medium">{response.name}</div><div className="text-sm text-violet-300">{response.headline||"Music professional"}</div>{response.message&&<p className="mt-2 text-sm text-slate-300">{response.message}</p>}{response.rate&&<p className="mt-1 text-sm text-emerald-300">Rate: {r.currency} {Number(response.rate).toLocaleString()}</p>}</div>)}{!(responses[r.id]||[]).length&&<p className="text-sm text-slate-500">No responses yet.</p>}</div></div>}
              </CardContent>
            </Card>
          ))}
        </div>
      </main>
    </div>
  );
}
