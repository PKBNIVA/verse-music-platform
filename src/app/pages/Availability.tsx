import { useEffect, useState } from "react";
import { CalendarPlus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Navigation } from "../components/Navigation";
import { Button } from "../components/ui/button";
import { Card, CardContent } from "../components/ui/card";
import { Input } from "../components/ui/input";
import { apiDelete, apiGet, apiPost } from "../lib/api";

type AvailabilityForm = { startAt?: string; endAt?: string; city?: string; status: string };

export default function Availability() {
  const [items, setItems] = useState<any[]>([]);
  const [form, setForm] = useState<AvailabilityForm>({ status: "available" });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const set = (key: keyof AvailabilityForm, value: string) => setForm((current) => ({ ...current, [key]: value }));
  const validRange = Boolean(form.startAt && form.endAt && new Date(form.endAt).getTime() > new Date(form.startAt).getTime());

  async function load() {
    setLoading(true);
    setError("");
    try {
      const data = await apiGet<any>("/availability");
      setItems(data.windows || []);
    } catch (e: any) {
      setError(e.message || "Unable to load availability.");
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    void load();
  }, []);

  async function add() {
    if (!validRange) return toast.error("Choose an end time after the start time.");
    setSaving(true);
    try {
      // datetime-local has no zone; send an absolute instant so the server does not read it as UTC.
      await apiPost("/availability", {
        ...form,
        startAt: new Date(form.startAt!).toISOString(),
        endAt: new Date(form.endAt!).toISOString(),
        city: form.city?.trim() || null,
      });
      setForm({ status: "available" });
      await load();
      toast.success("Availability added.");
    } catch (e: any) {
      toast.error(e.message || "Unable to add availability.");
    } finally {
      setSaving(false);
    }
  }
  async function remove(id: string) {
    try {
      await apiDelete(`/availability/${id}`);
      setItems((current) => current.filter((item) => item.id !== id));
      toast.success("Availability removed.");
    } catch (e: any) {
      toast.error(e.message || "Unable to remove availability.");
    }
  }

  return (
    <div className="min-h-screen bg-slate-950 text-white">
      <Navigation />
      <main className="max-w-5xl mx-auto px-4 sm:px-5 pt-28 pb-16">
        <h1 className="text-4xl font-bold">Availability calendar</h1>
        <p className="text-slate-400 mt-2">Publish when you are available, on hold, tentative, booked or unavailable.</p>
        <Card className="bg-white/[.055] border-white/10 mt-7">
          <CardContent className="p-5 grid md:grid-cols-5 gap-3">
            <label className="sr-only" htmlFor="availability-start">
              Start time
            </label>
            <Input
              id="availability-start"
              type="datetime-local"
              value={form.startAt || ""}
              onChange={(e) => set("startAt", e.target.value)}
              className="bg-white/5 border-white/15"
            />
            <label className="sr-only" htmlFor="availability-end">
              End time
            </label>
            <Input
              id="availability-end"
              type="datetime-local"
              min={form.startAt}
              value={form.endAt || ""}
              onChange={(e) => set("endAt", e.target.value)}
              className="bg-white/5 border-white/15"
            />
            <label className="sr-only" htmlFor="availability-city">
              City
            </label>
            <Input
              id="availability-city"
              value={form.city || ""}
              onChange={(e) => set("city", e.target.value)}
              placeholder="City"
              className="bg-white/5 border-white/15"
            />
            <label className="sr-only" htmlFor="availability-status">
              Status
            </label>
            <select
              id="availability-status"
              value={form.status}
              onChange={(e) => set("status", e.target.value)}
              className="rounded-md bg-slate-900 border border-white/15 px-3"
            >
              {["available", "hold", "tentative", "booked", "unavailable"].map((x) => (
                <option key={x}>{x}</option>
              ))}
            </select>
            <Button onClick={add} disabled={!validRange || saving}>
              <CalendarPlus size={16} className="mr-2" />
              {saving ? "Adding…" : "Add"}
            </Button>
          </CardContent>
        </Card>
        {loading ? (
          <p className="text-slate-400 text-center py-14" role="status">
            Loading availability…
          </p>
        ) : error ? (
          <div className="text-center py-14" role="alert">
            <p className="text-rose-300">{error}</p>
            <Button variant="outline" className="mt-4" onClick={() => void load()}>
              Try again
            </Button>
          </div>
        ) : items.length ? (
          <div className="grid gap-3 mt-6">
            {items.map((item) => (
              <div key={item.id} className="flex items-center justify-between gap-3 p-4 rounded-xl bg-white/5 border border-white/10">
                <div>
                  <b className="capitalize">{item.status}</b>
                  <div className="text-sm text-slate-400">
                    {new Date(item.startAt).toLocaleString()} → {new Date(item.endAt).toLocaleString()} {item.city ? `· ${item.city}` : ""}
                  </div>
                </div>
                <Button aria-label="Remove availability" size="icon" variant="ghost" onClick={() => void remove(item.id)}>
                  <Trash2 size={16} />
                </Button>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-slate-500 text-center py-14">
            No availability published yet. Choose a start and end time above to add your first window.
          </p>
        )}
      </main>
    </div>
  );
}
