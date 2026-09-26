import {useEffect, useState} from 'react';
import {Link, useNavigate} from 'react-router';
import {toast} from 'sonner';
import {Card, CardContent} from './ui/card';
import {Button} from './ui/button';
import {Badge} from './ui/badge';
import {ApiError, apiGet, apiPatch} from '../lib/api';
import {FormDialog} from './HiringDialog';

export const jobStatusLabel: Record<string, string> = {
  draft: 'Draft', pending: 'In review', published: 'Live', rejected: 'Changes requested', closed: 'Closed',
};
const statusClass: Record<string, string> = {
  published: 'bg-emerald-500/15 text-emerald-300', pending: 'bg-sky-500/15 text-sky-200',
  draft: 'bg-slate-500/20 text-slate-200', rejected: 'bg-amber-500/15 text-amber-200', closed: 'bg-slate-700/40 text-slate-400',
};

// Shows a plan-limit error with a way to the plans page instead of a dead end.
export function toastJobError(error: any, billingPath: string, nav: (to: string) => void) {
  if (error instanceof ApiError && error.status === 402) {
    toast.error(error.message, {action: {label: 'View plans', onClick: () => nav(billingPath)}});
  } else toast.error(error?.message || 'Something went wrong. Try again.');
}

// The poster's own opportunities with the actions their status allows (GET/PATCH /employer/jobs).
export function OpportunityPipeline({role, reloadKey = 0, onChanged, emptyHint}: {role?: string; reloadKey?: number; onChanged?: () => void; emptyHint?: string}) {
  const nav = useNavigate();
  const seeker = role === 'jobseeker';
  const editBase = seeker ? '/jobseeker/hiring/post' : '/employer/post-job';
  const applicantsBase = seeker ? '/jobseeker/hiring/applicants' : '/employer/applications';
  const billingPath = seeker ? '/jobseeker/billing' : '/employer/billing';
  const [jobs, setJobs] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState('');
  const [closing, setClosing] = useState<any | null>(null);

  const load = () => apiGet<any>('/employer/jobs')
    .then(d => { setJobs(d.jobs || []); setError(''); })
    .catch((e: any) => setError(e.message || 'Your opportunities could not be loaded.'))
    .finally(() => setLoading(false));
  useEffect(() => { load(); }, [reloadKey]);

  async function move(job: any, status: string, success: string) {
    if (busy) return false;
    setBusy(job.id);
    try {
      await apiPatch(`/employer/jobs/${job.id}`, {status});
      toast.success(success);
      await load();
      onChanged?.();
      return true;
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 422 && status === 'pending') {
        toast.error(`${e.message} Edit the opportunity to finish it.`, {action: {label: 'Edit', onClick: () => nav(`${editBase}?edit=${job.id}`)}});
      } else toastJobError(e, billingPath, nav);
      return false;
    } finally {
      setBusy('');
    }
  }

  if (loading) return <p role="status" className="text-slate-400 py-6">Loading your opportunities…</p>;
  if (error) return <Card className="bg-white/[.035] border-white/10"><CardContent className="p-6 text-center" role="alert"><p className="text-rose-300">{error}</p><Button className="mt-3" variant="outline" onClick={() => { setLoading(true); load(); }}>Try again</Button></CardContent></Card>;
  if (!jobs.length) return <Card className="bg-white/[.035] border-white/10"><CardContent className="p-8 text-center text-slate-400"><p>{emptyHint || 'You have not created any opportunities yet.'}</p>{!seeker && <Button className="mt-4" variant="outline" asChild><Link to={editBase}>Create your first opportunity</Link></Button>}</CardContent></Card>;

  return <div className="space-y-4">
    {jobs.map(j => {
      const allowed: string[] = j.allowedNextStatuses || [];
      const applications = Number(j.applications ?? j.applicationsCount ?? 0);
      return <Card key={j.id} className="bg-white/[.055] border-white/10" data-testid="pipeline-job">
        <CardContent className="p-5 flex flex-col md:flex-row justify-between gap-4 md:items-center">
          <div className="min-w-0">
            <div className="flex flex-wrap gap-2 items-center">
              <Badge variant="secondary">{j.opportunity_kind}</Badge>
              <h3 className="font-semibold text-lg break-words">{j.title}</h3>
              <Badge className={statusClass[j.status] || ''}>{jobStatusLabel[j.status] || j.status}</Badge>
            </div>
            <p className="text-sm text-slate-400 mt-2">{[j.location || 'Location to be added', j.workplace].filter(Boolean).join(' · ')} · {applications} application{applications === 1 ? '' : 's'}</p>
            {j.moderation_note && <p className="text-xs text-amber-300 mt-2">Review note: {j.moderation_note}</p>}
          </div>
          <div className="flex flex-wrap gap-2 md:justify-end">
            {applications > 0 && <Button size="sm" variant="secondary" asChild><Link to={`${applicantsBase}?jobId=${encodeURIComponent(j.id)}`}>Review applicants</Link></Button>}
            {j.status !== 'closed' && <Button size="sm" variant="outline" asChild><Link to={`${editBase}?edit=${encodeURIComponent(j.id)}`} aria-label={`Edit ${j.title}`}>Edit</Link></Button>}
            {j.status === 'draft' && allowed.includes('pending') && <Button size="sm" disabled={!!busy} aria-busy={busy === j.id} onClick={() => move(j, 'pending', 'Submitted for review')}>Submit for review</Button>}
            {j.status === 'closed' && allowed.includes('pending') && <Button size="sm" disabled={!!busy} aria-busy={busy === j.id} onClick={() => move(j, 'pending', 'Reopened and submitted for review')}>Reopen</Button>}
            {j.status !== 'closed' && allowed.includes('closed') && <Button size="sm" variant="outline" disabled={!!busy} onClick={() => setClosing(j)} aria-label={`Close ${j.title}`}>Close</Button>}
          </div>
        </CardContent>
      </Card>;
    })}
    <FormDialog open={!!closing} onOpenChange={o => { if (!o) setClosing(null); }} title="Close this opportunity?"
      description={closing ? `“${closing.title}” stops accepting applications and leaves search. You can reopen it later; reopening sends it back to review.` : undefined}
      submitLabel="Close opportunity" busy={!!busy} onSubmit={async () => { if (closing && await move(closing, 'closed', 'Opportunity closed')) setClosing(null); }}>
      <span className="sr-only">Confirm closing</span>
    </FormDialog>
  </div>;
}
