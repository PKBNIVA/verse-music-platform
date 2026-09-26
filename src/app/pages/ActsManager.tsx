import { useEffect, useState } from "react";
import { Navigation } from "../components/Navigation";
import { apiDelete, apiGet, apiPatch, apiPost } from "../lib/api";
import { Card, CardContent } from "../components/ui/card";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Badge } from "../components/ui/badge";
import { Music, Plus, Users } from "lucide-react";
import { toast } from "sonner";
export default function ActsManager() {
  const [acts, setActs] = useState<any[]>([]),
    [tax, setTax] = useState<any>({ actTypes: [] }),
    [f, setF] = useState<any>({
      name: "",
      actType: "band",
      city: "",
      genres: "",
      minFee: "",
      maxFee: "",
      lineupSize: 1,
      ownerRole: "Band Leader",
    }),
    [creating, setCreating] = useState(false);
  const load = () => apiGet<any>("/acts/me").then((d) => setActs(d.acts || []));
  useEffect(() => {
    load();
    apiGet("/taxonomy").then(setTax);
  }, []);
  async function create() {
    if (creating) return;
    setCreating(true);
    try {
      await apiPost("/acts", {
        ...f,
        genres: f.genres
          .split(",")
          .map((x: string) => x.trim())
          .filter(Boolean),
        minFee: Number(f.minFee) || null,
        maxFee: Number(f.maxFee) || null,
        lineupSize: Number(f.lineupSize) || 1,
      });
      toast.success("Bookable act created");
      setF((current: any) => ({ ...current, name: "", city: "", genres: "", minFee: "", maxFee: "" }));
      load();
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setCreating(false);
    }
  }
  async function addMember(act: any) {
    const displayName = prompt("Member name");
    if (!displayName) return;
    const roleName = prompt("Role in the act, e.g. Vocalist / Drummer");
    if (!roleName) return;
    const instrument = prompt("Instrument or voice (optional)");
    try {
      await apiPost(`/acts/${act.id}/members`, { displayName, roleName, instrument });
      toast.success("Lineup member added");
      load();
    } catch (e: any) {
      toast.error(e.message);
    }
  }
  async function removeMember(actId: string, member: any) {
    if (!confirm(`Remove ${member.displayName} from this act?`)) return;
    try {
      await apiDelete(`/acts/${actId}/members/${member.id}`);
      toast.success("Lineup member removed");
      load();
    } catch (e: any) {
      toast.error(e.message);
    }
  }
  async function changeStatus(act: any) {
    try {
      if (act.status === "active") await apiDelete(`/acts/${act.id}`);
      else await apiPatch(`/acts/${act.id}`, { status: "active" });
      toast.success(act.status === "active" ? "Act hidden from booking" : "Act published for booking");
      load();
    } catch (e: any) {
      toast.error(e.message);
    }
  }
  return (
    <div className="min-h-screen bg-slate-950 text-white">
      <Navigation />
      <main className="max-w-7xl mx-auto px-5 pt-28 pb-16">
        <div className="mb-7">
          <div className="text-xs uppercase tracking-[.2em] text-violet-300">
            Roster & booking identity
          </div>
          <h1 className="text-4xl font-bold mt-2">Your acts</h1>
          <p className="text-slate-400 mt-2">
            Create a solo, duo, band or ensemble once, then use that identity
            for enquiries, quotes and bookings.
          </p>
        </div>
        <div className="grid lg:grid-cols-[.9fr_1.1fr] gap-6">
          <Card className="bg-white/[.055] border-white/10">
            <CardContent className="p-6 space-y-4">
              <h2 className="text-xl font-semibold flex items-center gap-2">
                <Plus size={18} />
                Create act
              </h2>
              <Input
                placeholder="Act / stage name"
                value={f.name}
                onChange={(e) => setF({ ...f, name: e.target.value })}
              />
              <select
                className="w-full h-10 rounded-md bg-slate-900 border border-white/10 px-3"
                value={f.actType}
                onChange={(e) => setF({ ...f, actType: e.target.value })}
              >
                {tax.actTypes?.map((x: string) => (
                  <option key={x}>{x}</option>
                ))}
              </select>
              <Input
                placeholder="City / base"
                value={f.city}
                onChange={(e) => setF({ ...f, city: e.target.value })}
              />
              <Input
                placeholder="Genres, comma separated"
                value={f.genres}
                onChange={(e) => setF({ ...f, genres: e.target.value })}
              />
              <div className="grid grid-cols-2 gap-3">
                <Input
                  type="number"
                  placeholder="Min fee ₹"
                  value={f.minFee}
                  onChange={(e) => setF({ ...f, minFee: e.target.value })}
                />
                <Input
                  type="number"
                  placeholder="Max fee ₹"
                  value={f.maxFee}
                  onChange={(e) => setF({ ...f, maxFee: e.target.value })}
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <Input
                  type="number"
                  min="1"
                  placeholder="Lineup size"
                  value={f.lineupSize}
                  onChange={(e) => setF({ ...f, lineupSize: e.target.value })}
                />
                <Input
                  placeholder="Your role"
                  value={f.ownerRole}
                  onChange={(e) => setF({ ...f, ownerRole: e.target.value })}
                />
              </div>
              <Button
                className="w-full"
                onClick={create}
                disabled={creating || !f.name.trim()}
                aria-busy={creating}
              >
                <Music size={16} className="mr-2" />
                {creating ? "Creating…" : "Create bookable act"}
              </Button>
            </CardContent>
          </Card>
          <div className="space-y-4">
            {acts.map((a) => (
              <Card key={a.id} className="bg-white/[.055] border-white/10">
                <CardContent className="p-5">
                  <div className="flex justify-between gap-4">
                    <div>
                      <div className="flex items-center gap-2">
                        <h3 className="text-xl font-semibold">{a.name}</h3>
                        <Badge variant="secondary">{a.act_type}</Badge><Badge className="capitalize">{a.status}</Badge>
                      </div>
                      <p className="text-slate-400 text-sm mt-2">
                        {a.city || "Location not set"} · lineup {a.lineup_size}
                      </p>
                      <p className="text-sm mt-3">
                        {a.genres?.join(" · ") ||
                          "Add genres to improve discovery"}
                      </p>
                    </div>
                    <Users className="text-violet-300" />
                  </div>
                  {(a.min_fee || a.max_fee) && (
                    <div className="mt-4 text-sm text-emerald-300">
                      Indicative ₹{Number(a.min_fee || 0).toLocaleString()} – ₹
                      {Number(a.max_fee || a.min_fee || 0).toLocaleString()} /{" "}
                      {a.fee_basis}
                    </div>
                  )}
                  <div className="mt-5 border-t border-white/10 pt-4"><div className="flex items-center justify-between"><h4 className="font-semibold">Lineup</h4><Button size="sm" variant="outline" onClick={() => addMember(a)}><Plus size={14}/>Add member</Button></div><div className="mt-3 space-y-2">{a.members?.map((member:any)=><div key={member.id} className="flex items-center justify-between rounded-lg bg-black/15 p-3"><div><div className="font-medium">{member.displayName}</div><div className="text-xs text-slate-400">{member.roleName}{member.instrument?` · ${member.instrument}`:""}</div></div>{member.isLeader?<Badge variant="secondary">Leader</Badge>:<Button size="sm" variant="ghost" onClick={() => removeMember(a.id, member)}>Remove</Button>}</div>)}</div><Button className="mt-4" size="sm" variant="ghost" onClick={() => changeStatus(a)}>{a.status === "active" ? "Hide from booking" : "Publish for booking"}</Button></div>
                </CardContent>
              </Card>
            ))}
            {!acts.length && (
              <div className="text-slate-500 border border-dashed border-white/10 rounded-xl p-10 text-center">
                No act created yet.
              </div>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}
