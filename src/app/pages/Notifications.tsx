import {useEffect, useState} from 'react';
import {Link} from 'react-router';
import {toast} from 'sonner';
import {Bell, CheckCircle2} from 'lucide-react';
import {Navigation} from '../components/Navigation';
import {apiGet, apiPatch, apiPost} from '../lib/api';
import {useAuth} from '../lib/authContext';
import {Card, CardContent} from '../components/ui/card';
import {Button} from '../components/ui/button';
import {announceUnreadChanged} from '../lib/usePolling';
import {Switch} from '../components/ui/switch';

type Role = 'jobseeker' | 'employer';
type Item = {id: string; type?: string; title?: string; body?: string; link?: string | null; readAt?: string | null; createdAt: string};

// Role-neutral links stored by the API (see backend Notifier) mapped to routes that exist for each workspace.
const SHARED: Record<string, string> = {
  '/bookings': 'bookings', '/urgent-requests': 'urgent', '/messages': 'messages', '/notifications': 'notifications',
  '/workspace': 'workspace', '/profile': 'profile', '/billing': 'billing', '/acts': 'acts', '/availability': 'availability',
};
// Where a notification without a link should take the viewer, by kind.
const KIND_FALLBACK: Record<string, Record<Role, string>> = {
  verification: {jobseeker: '/jobseeker/profile', employer: '/employer/profile'},
  workspace: {jobseeker: '/jobseeker/workspace', employer: '/employer/workspace'},
  moderation: {jobseeker: '/jobseeker/hiring/applicants', employer: '/employer'},
  message: {jobseeker: '/jobseeker/messages', employer: '/employer/messages'},
};

/** Maps a stored notification link to a route that exists for the viewer's role; null when there is nowhere to go. */
export function notificationDestination(link: string | null | undefined, role: Role, kind?: string): string | null {
  const base = role === 'employer' ? '/employer' : '/jobseeker';
  if (!link) return (kind && KIND_FALLBACK[kind]?.[role]) || null;
  const cut = link.search(/[?#]/);
  const path = cut < 0 ? link : link.slice(0, cut);
  const suffix = cut < 0 ? '' : link.slice(cut);
  if (SHARED[path]) return `${base}/${SHARED[path]}${suffix}`;
  if (path === '/hiring/applicants') return role === 'employer' ? '/employer/applications' : '/jobseeker/hiring/applicants';
  if (/^\/jobs\/[^/]+$/.test(path)) return `${base}${path}${suffix}`;
  // Workspace-specific links written for the other role: keep the page when both workspaces have it.
  const other = role === 'employer' ? '/jobseeker' : '/employer';
  if (path === other) return (kind && KIND_FALLBACK[kind]?.[role]) || base;
  if (path.startsWith(`${other}/`)) {
    const rest = path.slice(other.length + 1);
    if (/^jobs\/[^/]+$/.test(rest) || Object.values(SHARED).includes(rest)) return `${base}/${rest}${suffix}`;
    if (role === 'employer' && rest === 'hiring/applicants') return '/employer/applications';
    if (role === 'jobseeker' && rest === 'applications') return '/jobseeker/hiring/applicants';
    return (kind && KIND_FALLBACK[kind]?.[role]) || base;
  }
  if (path === base || path.startsWith(`${base}/`)) return link;
  return (kind && KIND_FALLBACK[kind]?.[role]) || base;
}

export default function Notifications() {
  const {user} = useAuth();
  const role: Role = user?.role === 'employer' ? 'employer' : 'jobseeker';
  const [items, setItems] = useState<Item[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [markingAll, setMarkingAll] = useState(false);
  const load = async () => {
    setLoading(true); setError('');
    try { const d = await apiGet<any>('/notifications'); setItems(d.notifications || []); }
    catch (e: any) { setError(e.message || 'Unable to load notifications.'); }
    finally { setLoading(false); }
  };
  useEffect(() => { void load(); }, []);

  // null until loaded; saving is optimistic and rolls back on failure.
  const [emailOn, setEmailOn] = useState<boolean | null>(null);
  const [savingPref, setSavingPref] = useState(false);
  useEffect(() => { apiGet<any>('/notifications/preferences').then(d => setEmailOn(d.emailNotifications !== false)).catch(() => setEmailOn(null)); }, []);
  async function toggleEmail(next: boolean) {
    if (savingPref) return;
    const previous = emailOn;
    setEmailOn(next); setSavingPref(true);
    try {
      const d = await apiPatch<any>('/notifications/preferences', {emailNotifications: next});
      setEmailOn(d.emailNotifications !== false);
      toast.success(next ? 'Notification emails turned on' : 'Notification emails turned off');
    } catch (e: any) {
      setEmailOn(previous);
      toast.error(e.message || 'Unable to save your email preference');
    } finally {
      setSavingPref(false);
    }
  }

  async function read(n: Item) {
    if (n.readAt) return;
    const readAt = new Date().toISOString();
    setItems(xs => xs.map(x => x.id === n.id ? {...x, readAt} : x));
    try { await apiPatch(`/notifications/${n.id}`, {}); announceUnreadChanged(); }
    catch (e: any) { setItems(xs => xs.map(x => x.id === n.id ? {...x, readAt: null} : x)); toast.error(e.message || 'Unable to mark notification as read'); }
  }

  async function readAll() {
    if (markingAll) return;
    const previous = items;
    const readAt = new Date().toISOString();
    setMarkingAll(true);
    setItems(xs => xs.map(x => x.readAt ? x : {...x, readAt}));
    try { await apiPost('/notifications/read-all', {}); announceUnreadChanged(); }
    catch (e: any) { setItems(previous); toast.error(e.message || 'Unable to mark notifications as read'); }
    finally { setMarkingAll(false); }
  }

  const unread = items.filter(n => !n.readAt).length;
  return <div className="min-h-screen bg-slate-950 text-white"><Navigation/>
    <main className="max-w-4xl mx-auto px-4 md:px-6 pt-28 pb-28 lg:pb-16">
      <div className="flex flex-wrap items-end justify-between gap-3 mb-7">
        <div><h1 className="text-4xl font-bold">Notifications</h1><p className="text-slate-400 mt-2">Hiring updates, bookings, moderation, verification and messages.</p></div>
        {unread > 0 && <Button variant="outline" size="sm" onClick={() => void readAll()} disabled={markingAll} aria-busy={markingAll}>Mark all as read</Button>}
      </div>
      <Card className="bg-white/[.035] border-white/10 mb-6"><CardContent className="p-5 flex items-start justify-between gap-4">
        <div>
          <label htmlFor="email-notifications" className="font-semibold cursor-pointer">Email me about messages, bookings and application updates</label>
          <p id="email-notifications-hint" className="text-sm text-slate-400 mt-1">Sign-in codes, email verification and password emails are always sent.</p>
        </div>
        <Switch id="email-notifications" aria-describedby="email-notifications-hint" checked={emailOn ?? false} disabled={emailOn === null || savingPref} aria-busy={savingPref}
          onCheckedChange={v => void toggleEmail(v)} className="mt-1"/>
      </CardContent></Card>
      <div className="space-y-3">
        {loading ? <div className="text-slate-400 text-center py-12" role="status">Loading notifications…</div>
          : error ? <div className="text-center py-12" role="alert"><p className="text-rose-300">{error}</p><Button variant="outline" className="mt-4" onClick={() => void load()}>Try again</Button></div>
          : items.length === 0 ? <div className="text-center py-12" data-testid="notifications-empty"><Bell className="mx-auto text-slate-600" aria-hidden="true"/><p className="text-slate-300 mt-3 font-semibold">You’re all caught up</p><p className="text-slate-500 text-sm mt-1">Updates about applications, bookings and messages will appear here.</p></div>
          : <ul className="space-y-3">{items.map(n => { const to = notificationDestination(n.link, role, n.type); return <li key={n.id}><Card data-testid="notification" data-read={n.readAt ? 'true' : 'false'} className={`${n.readAt ? 'bg-white/[.035]' : 'bg-violet-500/[.08]'} border-white/10`}>
              <CardContent className="p-5 flex gap-4">
                <div className="mt-1" aria-hidden="true">{n.readAt ? <CheckCircle2 size={18} className="text-slate-600"/> : <Bell size={18} className="text-violet-300"/>}</div>
                <div className="flex-1 min-w-0">
                  <div className="font-semibold break-words">{n.title}{!n.readAt && <span className="sr-only"> (unread)</span>}</div>
                  {n.body && <p className="text-sm text-slate-400 mt-1 break-words">{n.body}</p>}
                  <div className="flex flex-wrap items-center justify-between gap-3 mt-2">
                    <span className="text-xs text-slate-500">{new Date(n.createdAt).toLocaleString()}</span>
                    <span className="flex gap-3">
                      {!n.readAt && <button type="button" className="text-xs text-slate-300 hover:text-white" onClick={() => void read(n)}>Mark as read</button>}
                      {to && <Link to={to} onClick={() => void read(n)} className="text-xs text-violet-300 hover:text-violet-200">Open</Link>}
                    </span>
                  </div>
                </div>
              </CardContent>
            </Card></li>; })}</ul>}
      </div>
    </main>
  </div>;
}
