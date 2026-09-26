import { useEffect, useState } from "react";
import { Building2, Plus, Trash2, UserPlus } from "lucide-react";
import { toast } from "sonner";
import { Navigation } from "../components/Navigation";
import { Badge } from "../components/ui/badge";
import { Button } from "../components/ui/button";
import { Card, CardContent } from "../components/ui/card";
import { Input } from "../components/ui/input";
import { apiDelete, apiGet, apiPost } from "../lib/api";
import { useAuth } from "../lib/authContext";
import { useConfirm } from "../components/booking/BookingDialogs";

export default function Workspace() {
  const { user } = useAuth();
  const [orgs, setOrgs] = useState<any[]>([]),
    [selected, setSelected] = useState<any>(null),
    [members, setMembers] = useState<any[]>([]);
  const [name, setName] = useState(""),
    [invite, setInvite] = useState({ email: "", role: "recruiter" });
  const [loading, setLoading] = useState(true),
    [membersLoading, setMembersLoading] = useState(false),
    [error, setError] = useState("");

  async function load() {
    setLoading(true);
    setError("");
    try {
      const data = await apiGet<any>("/organizations");
      const next = data.organizations || [];
      setOrgs(next);
      setSelected((current: any) => (current ? next.find((org: any) => org.id === current.id) || next[0] || null : next[0] || null));
    } catch (e: any) {
      setError(e.message || "Unable to load workspaces.");
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    void load();
  }, []);
  useEffect(() => {
    if (!selected) {
      setMembers([]);
      return;
    }
    setMembersLoading(true);
    apiGet<any>(`/organizations/${selected.id}/members`)
      .then((data) => setMembers(data.members || []))
      .catch((e: any) => {
        setMembers([]);
        toast.error(e.message || "Unable to load workspace members.");
      })
      .finally(() => setMembersLoading(false));
  }, [selected?.id]);

  async function create() {
    try {
      await apiPost("/organizations", { name: name.trim() });
      setName("");
      await load();
      toast.success("Workspace created.");
    } catch (e: any) {
      toast.error(e.message || "Unable to create workspace.");
    }
  }
  async function add() {
    if (!selected) return;
    try {
      await apiPost(`/organizations/${selected.id}/members`, { ...invite, email: invite.email.trim() });
      setInvite((current) => ({ ...current, email: "" }));
      const data: any = await apiGet(`/organizations/${selected.id}/members`);
      setMembers(data.members || []);
      setOrgs((current) => current.map((item) => (item.id === selected.id ? { ...item, memberCount: (data.members || []).length } : item)));
      toast.success("Team member added.");
    } catch (e: any) {
      toast.error(e.message || "Unable to add team member.");
    }
  }
  const { ask, element: confirmDialog } = useConfirm();
  function remove(member: any) {
    if (!selected) return;
    const org = selected;
    const self = member.id === user?.id;
    ask({
      title: self ? `Leave ${org.name}?` : `Remove ${member.name}?`,
      description: self ? "You will lose access to this workspace." : `${member.name} will lose access to ${org.name}.`,
      confirmLabel: self ? "Leave workspace" : "Remove member",
      destructive: true,
      action: async () => {
        await apiDelete(`/organizations/${org.id}/members/${member.id}`);
        toast.success(self ? "You left the workspace." : "Team member removed.");
        if (self) {
          setSelected(null);
          await load();
        } else {
          setMembers((current) => current.filter((item) => item.id !== member.id));
          setOrgs((current) => current.map((item) => (item.id === org.id ? { ...item, memberCount: Math.max(1, (item.memberCount || 1) - 1) } : item)));
        }
      },
    });
  }

  return (
    <div className="min-h-screen bg-slate-950 text-white">
      <Navigation />
      <main className="max-w-6xl mx-auto px-5 pt-28 pb-16">
        <div className="mb-7">
          <div className="text-xs uppercase tracking-[.2em] text-violet-300">Team SaaS workspace</div>
          <h1 className="text-4xl font-bold mt-2">Workspace & seats</h1>
          <p className="text-slate-400 mt-2">
            Bring recruiters, bookers and finance into the same operating account. Seat limits are enforced by the workspace owner's plan.
          </p>
        </div>
        {loading ? (
          <p className="text-center text-slate-400 py-16" role="status">
            Loading workspaces…
          </p>
        ) : error ? (
          <div className="text-center py-16" role="alert">
            <p className="text-rose-300">{error}</p>
            <Button variant="outline" className="mt-4" onClick={() => void load()}>
              Try again
            </Button>
          </div>
        ) : (
          <div className="grid lg:grid-cols-[.7fr_1.3fr] gap-6">
            <div className="space-y-4">
              <Card className="bg-white/[.055] border-white/10">
                <CardContent className="p-5">
                  <h2 className="font-semibold flex gap-2 items-center">
                    <Building2 size={17} />
                    Create workspace
                  </h2>
                  <div className="flex gap-2 mt-4">
                    <label htmlFor="workspace-name" className="sr-only">
                      Workspace name
                    </label>
                    <Input
                      id="workspace-name"
                      placeholder="Studio / label / band / agency"
                      value={name}
                      onChange={(e) => setName(e.target.value)}
                    />
                    <Button aria-label="Create workspace" size="icon" onClick={() => void create()} disabled={!name.trim()}>
                      <Plus size={16} />
                    </Button>
                  </div>
                </CardContent>
              </Card>
              {orgs.map((org) => (
                <button
                  key={org.id}
                  onClick={() => setSelected(org)}
                  className={`w-full text-left rounded-xl border p-4 ${selected?.id === org.id ? "border-violet-400 bg-violet-500/10" : "border-white/10 bg-white/[.035]"}`}
                >
                  <div className="font-semibold">{org.name}</div>
                  <div className="text-xs text-slate-500 mt-1">
                    {org.memberCount} member{org.memberCount === 1 ? "" : "s"} · you are {org.memberRole}
                  </div>
                </button>
              ))}
            </div>
            <Card className="bg-white/[.055] border-white/10">
              <CardContent className="p-6">
                {selected ? (
                  <>
                    <div className="flex justify-between items-start gap-3">
                      <div>
                        <h2 className="text-xl font-semibold">{selected.name}</h2>
                        <p className="text-sm text-slate-400">Team access is role-scoped and seat-limited.</p>
                      </div>
                      <Badge>{selected.memberRole}</Badge>
                    </div>
                    {["owner", "admin"].includes(selected.memberRole) && (
                      <div className="grid md:grid-cols-[1fr_150px_auto] gap-2 mt-5">
                        <label htmlFor="member-email" className="sr-only">
                          Existing Verse user email
                        </label>
                        <Input
                          id="member-email"
                          type="email"
                          placeholder="Existing Verse user email"
                          value={invite.email}
                          onChange={(e) => setInvite({ ...invite, email: e.target.value })}
                        />
                        <label htmlFor="member-role" className="sr-only">
                          Member role
                        </label>
                        <select
                          id="member-role"
                          className="h-10 rounded-md bg-slate-900 border border-white/10 px-3"
                          value={invite.role}
                          onChange={(e) => setInvite({ ...invite, role: e.target.value })}
                        >
                          {["admin", "recruiter", "booker", "finance", "member"]
                            .filter((role) => role !== "admin" || selected.memberRole === "owner")
                            .map((role) => (
                              <option key={role}>{role}</option>
                            ))}
                        </select>
                        <Button aria-label="Add team member" onClick={() => void add()} disabled={!invite.email.trim()}>
                          <UserPlus size={16} />
                        </Button>
                      </div>
                    )}
                    <div className="space-y-3 mt-6">
                      {membersLoading ? (
                        <p className="text-slate-400 text-center py-8" role="status">
                          Loading members…
                        </p>
                      ) : members.length ? (
                        members.map((member) => (
                          <div key={member.id} className="flex justify-between gap-3 items-center border-b border-white/10 pb-3">
                            <div>
                              <div className="font-medium">{member.name}</div>
                              <div className="text-xs text-slate-500">{member.email}</div>
                            </div>
                            <div className="flex items-center gap-2">
                              <Badge variant="secondary">{member.role}</Badge>
                              {member.role !== "owner" &&
                                (selected.memberRole === "owner" ||
                                  (selected.memberRole === "admin" && (member.role !== "admin" || member.id === user?.id))) && (
                                  <Button
                                    aria-label={`Remove ${member.name}`}
                                    variant="ghost"
                                    size="icon"
                                    onClick={() => remove(member)}
                                  >
                                    <Trash2 size={15} />
                                  </Button>
                                )}
                            </div>
                          </div>
                        ))
                      ) : (
                        <p className="text-slate-500 text-center py-8">No members found.</p>
                      )}
                    </div>
                  </>
                ) : (
                  <div className="text-slate-500 text-center py-16">Create or select a workspace.</div>
                )}
              </CardContent>
            </Card>
          </div>
        )}
        {confirmDialog}
      </main>
    </div>
  );
}
