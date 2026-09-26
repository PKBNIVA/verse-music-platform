import { useEffect, useState } from "react";
import { Navigation } from "../components/Navigation";
import { apiGet, apiPost } from "../lib/api";
import { Card, CardContent } from "../components/ui/card";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Badge } from "../components/ui/badge";
import { Field, FormDialog, selectClass, textareaClass } from "../components/booking/BookingDialogs";
import { Plus, Users } from "lucide-react";
import { toast } from "sonner";

const list = (value: unknown): string[] => (Array.isArray(value) ? value.map(String) : typeof value === "string" && value ? [value] : []);
type RoleDraft = { projectId: string; projectName: string; roleName: string; instrument: string; countNeeded: string; skillLevel: string; requirements: string; compensation: string };

export default function BandBuilder() {
  const [projects, setProjects] = useState<any[]>([]),
    [loading, setLoading] = useState(true),
    [loadError, setLoadError] = useState(""),
    [roleOptions, setRoleOptions] = useState<string[]>([]),
    [f, setF] = useState<any>({ name: "", concept: "", city: "", genres: "", commitmentType: "recurring-gig", compensationModel: "" }),
    [creating, setCreating] = useState(false),
    [role, setRole] = useState<RoleDraft | null>(null),
    [roleError, setRoleError] = useState(""),
    [savingRole, setSavingRole] = useState(false),
    [publishing, setPublishing] = useState<string | null>(null);
  async function load() {
    try {
      const d = await apiGet<any>("/band-projects");
      setProjects(d.projects || []);
      setLoadError("");
    } catch (e: any) {
      setLoadError(e.message || "Unable to load your projects.");
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    void load();
    apiGet<any>("/taxonomy")
      .then((t) => setRoleOptions(Array.from(new Set(Object.values(t?.roleCategories || {}).flatMap((x) => list(x))))))
      .catch(() => {});
  }, []);
  async function create() {
    if (creating || !f.name.trim()) return;
    setCreating(true);
    try {
      await apiPost("/band-projects", {
        ...f,
        name: f.name.trim(),
        genres: f.genres
          .split(",")
          .map((x: string) => x.trim())
          .filter(Boolean),
      });
      setF({ ...f, name: "", concept: "", city: "", genres: "", compensationModel: "" });
      toast.success("Band project created");
      await load();
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setCreating(false);
    }
  }
  async function addRole() {
    if (!role || savingRole) return;
    const count = Number(role.countNeeded);
    if (!role.roleName.trim()) return setRoleError("Choose the role you need.");
    if (!Number.isInteger(count) || count < 1 || count > 100) return setRoleError("How many people: a whole number from 1 to 100.");
    setSavingRole(true);
    setRoleError("");
    try {
      const { projectId, projectName: _name, ...body } = role;
      await apiPost(`/band-projects/${projectId}/roles`, { ...body, roleName: role.roleName.trim(), countNeeded: count });
      setRole(null);
      toast.success("Role added");
      await load();
    } catch (e: any) {
      setRoleError(e.message || "Unable to add this role.");
    } finally {
      setSavingRole(false);
    }
  }
  async function publish(projectId: string, roleId: string) {
    if (publishing) return;
    setPublishing(roleId);
    try {
      await apiPost(`/band-projects/${projectId}/roles/${roleId}/publish`, {});
      toast.success("Opening submitted for moderation");
      await load();
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setPublishing(null);
    }
  }
  const setR = (key: keyof RoleDraft, value: string) => setRole((current) => (current ? { ...current, [key]: value } : current));
  return (
    <div className="min-h-screen bg-slate-950 text-white">
      <Navigation />
      <main className="max-w-7xl mx-auto px-4 sm:px-5 pt-28 pb-16">
        <div className="mb-7">
          <div className="text-xs uppercase tracking-[.2em] text-violet-300">Roster builder</div>
          <h1 className="text-3xl sm:text-4xl font-bold mt-2">Build your band or live team</h1>
          <p className="text-slate-400 mt-2 max-w-3xl">
            Define the concept first, then the exact seats you need—lead singer, bassist, tabla player, playback engineer, FOH, technical director or any other
            music/live-production role.
          </p>
        </div>
        <div className="grid lg:grid-cols-[.85fr_1.15fr] gap-6">
          <Card className="bg-white/[.055] border-white/10">
            <CardContent className="p-6">
              <form
                className="space-y-4"
                onSubmit={(e) => {
                  e.preventDefault();
                  void create();
                }}
              >
                <h2 className="text-xl font-semibold">New project</h2>
                <Input aria-label="Band / project name" placeholder="Band / project name" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} />
                <Input aria-label="City / rehearsal base" placeholder="City / rehearsal base" value={f.city} onChange={(e) => setF({ ...f, city: e.target.value })} />
                <Input aria-label="Genres" placeholder="Genres, comma separated" value={f.genres} onChange={(e) => setF({ ...f, genres: e.target.value })} />
                <textarea
                  aria-label="Concept"
                  className={textareaClass}
                  placeholder="Sound, references, goals, current lineup…"
                  value={f.concept}
                  onChange={(e) => setF({ ...f, concept: e.target.value })}
                />
                <Input
                  aria-label="Compensation model"
                  placeholder="Compensation / revenue-share model"
                  value={f.compensationModel}
                  onChange={(e) => setF({ ...f, compensationModel: e.target.value })}
                />
                <Button type="submit" className="w-full" disabled={creating || !f.name.trim()} aria-busy={creating}>
                  <Users size={16} className="mr-2" />
                  {creating ? "Creating…" : "Create project"}
                </Button>
              </form>
            </CardContent>
          </Card>
          <div className="space-y-4">
            {loading ? (
              <p className="text-slate-400 text-center py-16" role="status">
                Loading projects…
              </p>
            ) : loadError ? (
              <div className="text-center py-16" role="alert">
                <p className="text-rose-300">{loadError}</p>
                <Button variant="outline" className="mt-4" onClick={() => void load()}>
                  Try again
                </Button>
              </div>
            ) : projects.length === 0 ? (
              <div className="text-slate-500 border border-dashed border-white/10 rounded-xl p-10 text-center">
                No projects yet. Create one, then add the seats you need to fill.
              </div>
            ) : (
              projects.map((p) => {
                const roles: any[] = Array.isArray(p.roles) ? p.roles : [];
                return (
                  <Card key={p.id} className="bg-white/[.055] border-white/10">
                    <CardContent className="p-5">
                      <div className="flex flex-wrap justify-between gap-3">
                        <div className="min-w-0">
                          <h3 className="text-xl font-semibold break-words">{p.name}</h3>
                          <p className="text-sm text-slate-400 mt-1">
                            {p.city || "Flexible base"} · {list(p.genres).join(" / ") || "genre open"}
                          </p>
                        </div>
                        <Button
                          size="sm"
                          onClick={() => {
                            setRoleError("");
                            setRole({
                              projectId: p.id,
                              projectName: p.name,
                              roleName: "",
                              instrument: "",
                              countNeeded: "1",
                              skillLevel: "professional",
                              requirements: "",
                              compensation: "",
                            });
                          }}
                        >
                          <Plus size={15} className="mr-1" />
                          Add seat
                        </Button>
                      </div>
                      <div className="space-y-2 mt-4">
                        {roles.length === 0 && <p className="text-sm text-slate-500">No seats yet. Add the roles this project needs.</p>}
                        {roles.map((r: any) => (
                          <div key={r.id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-black/20 border border-white/10 px-3 py-2">
                            <div className="min-w-0">
                              <Badge variant="secondary" className="whitespace-normal">
                                {r.role_name}
                                {r.instrument ? ` · ${r.instrument}` : ""} × {r.count_needed}
                              </Badge>
                              {r.compensation && <span className="text-xs text-slate-500 ml-2">{r.compensation}</span>}
                            </div>
                            {r.opportunity_id ? (
                              <span className="text-xs text-emerald-300">Hiring opportunity created</span>
                            ) : (
                              <Button size="sm" variant="outline" disabled={publishing === r.id} aria-busy={publishing === r.id} onClick={() => void publish(p.id, r.id)}>
                                {publishing === r.id ? "Publishing…" : "Publish opening"}
                              </Button>
                            )}
                          </div>
                        ))}
                      </div>
                    </CardContent>
                  </Card>
                );
              })
            )}
          </div>
        </div>
        <FormDialog
          open={Boolean(role)}
          onOpenChange={(open) => !open && setRole(null)}
          title="Add a seat"
          description={role ? `For ${role.projectName}` : undefined}
          submitLabel="Add role"
          busyLabel="Adding…"
          busy={savingRole}
          canSubmit={Boolean(role?.roleName.trim())}
          error={roleError}
          onSubmit={addRole}
        >
          {role && (
            <>
              <Field label="Role" htmlFor="seat-role">
                <input id="seat-role" list="music-roles" className={selectClass} placeholder="Lead vocalist, bassist, FOH…" value={role.roleName} onChange={(e) => setR("roleName", e.target.value)} />
              </Field>
              <datalist id="music-roles">
                {roleOptions.map((x) => (
                  <option key={x} value={x} />
                ))}
              </datalist>
              <Field label="Instrument / rig (optional)" htmlFor="seat-instrument">
                <Input id="seat-instrument" value={role.instrument} onChange={(e) => setR("instrument", e.target.value)} />
              </Field>
              <div className="grid grid-cols-2 gap-3">
                <Field label="How many" htmlFor="seat-count">
                  <Input id="seat-count" type="number" min="1" max="100" value={role.countNeeded} onChange={(e) => setR("countNeeded", e.target.value)} />
                </Field>
                <Field label="Skill level" htmlFor="seat-skill">
                  <select id="seat-skill" className={selectClass} value={role.skillLevel} onChange={(e) => setR("skillLevel", e.target.value)}>
                    {["developing", "intermediate", "professional", "touring", "elite"].map((x) => (
                      <option key={x}>{x}</option>
                    ))}
                  </select>
                </Field>
              </div>
              <Field label="Compensation for this seat" htmlFor="seat-compensation">
                <Input id="seat-compensation" value={role.compensation} onChange={(e) => setR("compensation", e.target.value)} />
              </Field>
              <Field label="Requirements" htmlFor="seat-requirements">
                <textarea
                  id="seat-requirements"
                  className={textareaClass}
                  placeholder="Audition material, gear, availability, repertoire…"
                  value={role.requirements}
                  onChange={(e) => setR("requirements", e.target.value)}
                />
              </Field>
            </>
          )}
        </FormDialog>
      </main>
    </div>
  );
}
