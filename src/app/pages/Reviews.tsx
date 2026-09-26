import { useEffect, useState } from "react";
import { Navigation } from "../components/Navigation";
import { Card, CardContent } from "../components/ui/card";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Textarea } from "../components/ui/textarea";
import { apiGet, apiPost } from "../lib/api";
import { toast } from "sonner";
import { Star } from "lucide-react";
export default function Reviews() {
  const [reviews, setReviews] = useState<any[]>([]);
  const [employers, setEmployers] = useState<any[]>([]);
  const [employerId, setEmployerId] = useState("");
  const [rating, setRating] = useState(5);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [loadError, setLoadError] = useState("");
  const load = () =>
    apiGet<any>("/reviews").then((d) => {
      const eligible = d.eligibleEmployers || [];
      setLoadError("");
      setReviews(d.reviews || []);
      setEmployers(eligible);
      setEmployerId((current) =>
        eligible.some((employer: any) => employer.id === current)
          ? current
          : eligible[0]?.id || "",
      );
    }).catch((e: any) => setLoadError(e?.message || "Reviews could not be loaded."));
  useEffect(() => {
    load();
  }, []);
  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (submitting) return;
    setSubmitting(true);
    try {
      await apiPost("/reviews", { employerId, rating, title, body });
      setTitle("");
      setBody("");
      toast.success("Review submitted for moderation");
      await load();
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setSubmitting(false);
    }
  }
  return (
    <div className="min-h-screen bg-slate-950 text-white">
      <Navigation />
      <main className="max-w-6xl mx-auto px-6 pt-28 pb-16">
        <h1 className="text-4xl font-bold">Employer reviews</h1>
        <p className="text-slate-400 mt-2 mb-7">
          Published reviews are moderated to reduce abuse and spam.
        </p>
        <div className="grid lg:grid-cols-[360px_1fr] gap-6">
          <Card className="bg-white/[.06] border-white/10 h-fit">
            <CardContent className="p-5">
              <h2 className="font-semibold text-lg mb-4">Write a review</h2>
              <form onSubmit={submit} className="space-y-3">
                {employers.length === 0 && (
                  <p className="text-sm text-slate-400">
                    You can review an employer after a completed hire. Employers
                    you have already reviewed are not shown.
                  </p>
                )}
                {employers.length > 0 && <select
                  aria-label="Employer"
                  value={employerId}
                  onChange={(e) => setEmployerId(e.target.value)}
                  className="w-full h-10 rounded-md bg-slate-900 border border-white/15 px-3"
                >
                  {employers.map((e) => (
                    <option key={e.id} value={e.id}>
                      {e.companyName || e.name}
                    </option>
                  ))}
                </select>}
                <select
                  aria-label="Rating"
                  value={rating}
                  onChange={(e) => setRating(Number(e.target.value))}
                  className="w-full h-10 rounded-md bg-slate-900 border border-white/15 px-3"
                >
                  {[5, 4, 3, 2, 1].map((n) => (
                    <option key={n} value={n}>
                      {n} stars
                    </option>
                  ))}
                </select>
                <Input
                  aria-label="Review title"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="Optional title"
                  className="bg-black/20 border-white/15"
                />
                <Textarea
                  aria-label="Review"
                  required
                  value={body}
                  onChange={(e) => setBody(e.target.value)}
                  placeholder="Share a useful, factual experience…"
                  className="bg-black/20 border-white/15 min-h-28"
                />
                <Button
                  type="submit"
                  className="w-full"
                  disabled={!employerId || submitting}
                  aria-busy={submitting}
                >
                  {submitting ? "Submitting…" : "Submit review"}
                </Button>
              </form>
            </CardContent>
          </Card>
          <div className="space-y-4">
            {loadError && (
              <Card className="bg-rose-500/10 border-rose-400/20" role="alert">
                <CardContent className="p-5">
                  <p>{loadError}</p>
                  <Button className="mt-3" variant="outline" onClick={() => load()}>
                    Retry
                  </Button>
                </CardContent>
              </Card>
            )}
            {loadError ? null : reviews.length === 0 ? (
              <Card className="bg-white/5 border-white/10">
                <CardContent className="p-8 text-slate-400">
                  No published reviews yet.
                </CardContent>
              </Card>
            ) : (
              reviews.map((r) => (
                <Card key={r.id} className="bg-white/[.06] border-white/10">
                  <CardContent className="p-5">
                    <div className="flex items-center justify-between">
                      <div className="font-semibold">{r.employerName}</div>
                      <div className="flex items-center text-amber-300">
                        <Star size={15} className="mr-1 fill-current" />
                        {r.rating}/5
                      </div>
                    </div>
                    <div className="text-sm text-slate-500 mt-1">
                      by {r.authorName}
                    </div>
                    {r.title && <h3 className="font-medium mt-4">{r.title}</h3>}
                    <p className="text-slate-300 mt-2">{r.body}</p>
                  </CardContent>
                </Card>
              ))
            )}
          </div>
        </div>
      </main>
    </div>
  );
}
