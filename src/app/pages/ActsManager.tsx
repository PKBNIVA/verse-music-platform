import { useEffect, useState } from "react";
import { Link, useLocation } from "react-router";
import { Navigation } from "../components/Navigation";
import { apiDelete, apiGet, apiPatch, apiPost } from "../lib/api";
import { Card, CardContent } from "../components/ui/card";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Badge } from "../components/ui/badge";
import { Field, FormDialog, selectClass, useConfirm } from "../components/booking/BookingDialogs";
import { Music, Plus, Users } from "lucide-react";
import { toast } from "sonner";

const FALLBACK_ACT_TYPES = ["solo", "duo", "trio", "band", "ensemble", "dj"];
const list = (value: unknown): string[] => (Array.isArray(value) ? value.map(String) : []);

export default function ActsManager() {
  const base = `/${useLocation().pathname.split("/")[1] || "jobseeker"}`;
  const [acts, setActs] = useState<any[]>([]),
    [loading, setLoading] = useState(true),
    [loadError, setLoadError] = useState(""),
    [actTypes, setActTypes] = useState<string[]>(FALLBACK_ACT_TYPES),
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
    [creating, setCreating] = useState(false),
    [member, setMember] = useState<{ actId: string; actName: string; displayName: string; roleName: string; instrument: string } | null>(null),
    [memberError, setMemberError] = useState(""),
    [savingMember, setSavingMember] = useState(false),
    [togglingId, setTogglingId] = useState<string | null>(null);
  const { ask, element: confirmDialog } = useConfirm();
  async function load() {
    try {
      const d = await apiGet<any>("/acts/me");
      setActs(d.acts || []);
      setLoadError("");
    } catch (e: any) {
      setLoadError(e.message || "Unable to load your acts.");
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    void load();
    apiGet<any>("/taxonomy")
      .then((t) => {
        const types = list(t?.actTypes);
        if (types.length) setActTypes(types);
      })
      .catch(() => {});
  }, []);
  async function create() {
    if (creating) return;
    const minFee = f.minFee === "" ? null : Number(f.minFee);
    const maxFee = f.maxFee === "" ? null : Number(f.maxFee);
    if ((minFee !== null && (!Number.isInteger(minFee) || minFee < 0)) || (maxFee !== null && (!Number.isInteger(maxFee) || maxFee < 0)))
      return toast.error("Fees must be whole numbers of 0 or more.");
    if (minFee !== null && maxFee !== null && maxFee < minFee) return toast.error("Max fee must be at least the min fee.");
    setCreating(true);
    try {
      await apiPost("/acts", {
        ...f,
        name: f.name.trim(),
        genres: f.genres
          .split(",")
          .map((x: string) => x.trim())
          .filter(Boolean),
        minFee,
        maxFee,
        lineupSize: Math.max(1, Math.floor(Number(f.lineupSize)) || 1),
      });
      toast.success("Bookable act created");
      setF((current: any) => ({ ...current, name: "", city: "", genres: "", minFee: "", maxFee: "" }));
      await load();
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setCreating(false);
    }
  }
  async function saveMember() {
    if (!member || savingMember) return;
    if (!member.displayName.trim() || !member.roleName.trim()) return setMemberError("Add the member's name and role.");
    setSavingMember(true);
    setMemberError("");
    try {
      await apiPost(`/acts/${member.actId}/members`, {
        displayName: member.displayName.trim(),
        roleName: member.roleName.trim(),
        instrument: member.instrument.trim() || null,
      });
      toast.success("Lineup member added");
      setMember(null);
      await load();
    } catch (e: any) {
      setMemberError(e.message || "Unable to add this member.");
    } finally {
      setSavingMember(false);
    }
  }
  const removeMember = (actId: string, m: any) =>
    ask({
      title: `Remove ${m.displayName}?`,
      description: "They will no longer appear in this act's public lineup.",
      confirmLabel: "Remove member",
      destructive: true,
      action: async () => {
        await apiDelete(`/acts/${actId}/members/${m.id}`);
        toast.success("Lineup member removed");
        await load();
      },
    });
  async function changeStatus(act: any) {
    if (togglingId) return;
    setTogglingId(act.id);
    try {
      if (act.status === "active") await apiDelete(`/acts/${act.id}`);
      else await apiPatch(`/acts/${act.id}`, { status: "active" });
      toast.success(act.status === "active" ? "Act hidden from booking" : "Act published for booking");
      await load();
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setTogglingId(null);
    }
  }
  const setM = (key: "displayName" | "roleName" | "instrument", value: string) => setMember((current) => (current ? { ...current, [key]: value } : current));
  return (
    <div className="min-h-screen bg-slate-950 text-white">
      <Navigation />
      <main className="max-w-7xl mx-auto px-4 sm:px-5 pt-28 pb-16">
        <div className="mb-7">
          <div className="text-xs uppercase tracking-[.2em] text-violet-300">Roster & booking identity</div>
          <h1 className="text-3xl sm:text-4xl font-bold mt-2">Your acts</h1>
          <p className="text-slate-400 mt-2">Create a solo, duo, band or ensemble once, then use that identity for enquiries, quotes and bookings.</p>
        </div>
        <div className="grid lg:grid-cols-[.9fr_1.1fr] gap-6">
          <Card className="bg-white/[.055] border-white/10">
            <CardContent className="p-6">
              <form
                className="space-y-4"
                onSubmit={(e) => {
                  e.preventDefault();
                  void create();
                }}
              >
                <h2 className="text-xl font-semibold flex items-center gap-2">
                  <Plus size={18} />
                  Create act
                </h2>
                <Input aria-label="Act / stage name" placeholder="Act / stage name" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} />
                <select aria-label="Act type" className={selectClass} value={f.actType} onChange={(e) => setF({ ...f, actType: e.target.value })}>
                  {(actTypes.includes(f.actType) ? actTypes : [f.actType, ...actTypes]).map((x: string) => (
                    <option key={x}>{x}</option>
                  ))}
                </select>
                <Input aria-label="City / base" placeholder="City / base" value={f.city} onChange={(e) => setF({ ...f, city: e.target.value })} />
                <Input aria-label="Genres" placeholder="Genres, comma separated" value={f.genres} onChange={(e) => setF({ ...f, genres: e.target.value })} />
                <div className="grid grid-cols-2 gap-3">
                  <Input aria-label="Min fee" type="number" min="0" placeholder="Min fee ₹" value={f.minFee} onChange={(e) => setF({ ...f, minFee: e.target.value })} />
                  <Input aria-label="Max fee" type="number" min="0" placeholder="Max fee ₹" value={f.maxFee} onChange={(e) => setF({ ...f, maxFee: e.target.value })} />
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <Input aria-label="Lineup size" type="number" min="1" placeholder="Lineup size" value={f.lineupSize} onChange={(e) => setF({ ...f, lineupSize: e.target.value })} />
                  <Input aria-label="Your role" placeholder="Your role" value={f.ownerRole} onChange={(e) => setF({ ...f, ownerRole: e.target.value })} />
                </div>
                <Button type="submit" className="w-full" disabled={creating || !f.name.trim()} aria-busy={creating}>
                  <Music size={16} className="mr-2" />
                  {creating ? "Creating…" : "Create bookable act"}
                </Button>
              </form>
            </CardContent>
          </Card>
          <div className="space-y-4">
            {loading ? (
              <p className="text-slate-400 text-center py-16" role="status">
                Loading your acts…
              </p>
            ) : loadError ? (
              <div className="text-center py-16" role="alert">
                <p className="text-rose-300">{loadError}</p>
                <Button variant="outline" className="mt-4" onClick={() => void load()}>
                  Try again
                </Button>
              </div>
            ) : acts.length === 0 ? (
              <div className="text-slate-500 border border-dashed border-white/10 rounded-xl p-10 text-center">No act created yet. Use the form to create your first bookable act.</div>
            ) : (
              acts.map((a) => (
                <Card key={a.id} className="bg-white/[.055] border-white/10">
                  <CardContent className="p-5">
                    <div className="flex justify-between gap-4">
                      <div className="min-w-0">
                        <div className="flex flex-wrap items-center gap-2">
                          <h3 className="text-xl font-semibold break-words">{a.name}</h3>
                          <Badge variant="secondary">{a.act_type}</Badge>
                          <Badge className="capitalize">{a.status}</Badge>
                        </div>
                        <p className="text-slate-400 text-sm mt-2">
                          {a.city || "Location not set"} · lineup {a.lineup_size}
                        </p>
                        <p className="text-sm mt-3">{list(a.genres).join(" · ") || "Add genres to improve discovery"}</p>
                      </div>
                      <Users className="text-violet-300 shrink-0" />
                    </div>
                    {Boolean(a.min_fee || a.max_fee) && (
                      <div className="mt-4 text-sm text-emerald-300">
                        Indicative ₹{Number(a.min_fee || 0).toLocaleString("en-IN")} – ₹{Number(a.max_fee || a.min_fee || 0).toLocaleString("en-IN")} / {a.fee_basis}
                      </div>
                    )}
                    <div className="mt-5 border-t border-white/10 pt-4">
                      <div className="flex items-center justify-between">
                        <h4 className="font-semibold">Lineup</h4>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => {
                            setMemberError("");
                            setMember({ actId: a.id, actName: a.name, displayName: "", roleName: "", instrument: "" });
                          }}
                        >
                          <Plus size={14} />
                          Add member
                        </Button>
                      </div>
                      <div className="mt-3 space-y-2">
                        {(a.members || []).map((m: any) => (
                          <div key={m.id} className="flex items-center justify-between gap-2 rounded-lg bg-black/15 p-3">
                            <div className="min-w-0">
                              <div className="font-medium break-words">{m.displayName}</div>
                              <div className="text-xs text-slate-400">
                                {m.roleName}
                                {m.instrument ? ` · ${m.instrument}` : ""}
                              </div>
                            </div>
                            {m.isLeader ? (
                              <Badge variant="secondary">Leader</Badge>
                            ) : (
                              <Button size="sm" variant="ghost" aria-label={`Remove ${m.displayName}`} onClick={() => removeMember(a.id, m)}>
                                Remove
                              </Button>
                            )}
                          </div>
                        ))}
                      </div>
                      <div className="flex flex-wrap gap-2 mt-4">
                        <Button size="sm" variant="ghost" disabled={togglingId === a.id} aria-busy={togglingId === a.id} onClick={() => void changeStatus(a)}>
                          {togglingId === a.id ? "Saving…" : a.status === "active" ? "Hide from booking" : "Publish for booking"}
                        </Button>
                        {a.status === "active" && (
                          <Button size="sm" variant="ghost" asChild>
                            <Link to={`/acts/${a.id}`}>View public page</Link>
                          </Button>
                        )}
                        <Button size="sm" variant="ghost" asChild>
                          <Link to={`${base}/bookings`}>Bookings</Link>
                        </Button>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              ))
            )}
          </div>
        </div>
        <FormDialog
          open={Boolean(member)}
          onOpenChange={(open) => !open && setMember(null)}
          title="Add a lineup member"
          description={member ? `Shown on ${member.actName}'s lineup.` : undefined}
          submitLabel="Add member"
          busyLabel="Adding…"
          busy={savingMember}
          canSubmit={Boolean(member?.displayName.trim() && member?.roleName.trim())}
          error={memberError}
          onSubmit={saveMember}
        >
          {member && (
            <>
              <Field label="Member name" htmlFor="member-name">
                <Input id="member-name" value={member.displayName} onChange={(e) => setM("displayName", e.target.value)} />
              </Field>
              <Field label="Role in the act" htmlFor="member-role" hint="For example Vocalist or Drummer">
                <Input id="member-role" value={member.roleName} onChange={(e) => setM("roleName", e.target.value)} />
              </Field>
              <Field label="Instrument or voice (optional)" htmlFor="member-instrument">
                <Input id="member-instrument" value={member.instrument} onChange={(e) => setM("instrument", e.target.value)} />
              </Field>
            </>
          )}
        </FormDialog>
        {confirmDialog}
      </main>
    </div>
  );
}
