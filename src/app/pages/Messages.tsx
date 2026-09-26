import {useCallback, useEffect, useLayoutEffect, useRef, useState} from 'react';
import {Link, useSearchParams} from 'react-router';
import {ArrowLeft, MessageSquare, Send} from 'lucide-react';
import {toast} from 'sonner';
import {Navigation} from '../components/Navigation';
import {Card, CardContent} from '../components/ui/card';
import {Button} from '../components/ui/button';
import {apiGet, apiPost} from '../lib/api';
import {useAuth} from '../lib/authContext';
import {announceUnreadChanged, useVisiblePolling} from '../lib/usePolling';

type Conversation = {
  id: string; counterpartName?: string; candidateName?: string; employerName?: string; viewerSide?: 'candidate' | 'employer';
  jobTitle?: string | null; lastMessage?: string | null; lastMessageAt?: string | null; lastMessageFromMe?: boolean; unreadCount?: number;
};
type Message = {id: string; senderId: string; body: string; createdAt: string; readAt?: string | null};

const MESSAGE_MAX_LENGTH = 5000;
const THREAD_POLL_MS = 10_000;
const INBOX_POLL_MS = 30_000;

const errorMessage = (e: any, fallback: string) => {
  if (e?.status === 429) return 'You’re sending messages too quickly. Wait a few minutes, then try again — your draft is saved.';
  return e?.message || fallback;
};
const byTime = (a: Message, b: Message) => a.createdAt.localeCompare(b.createdAt) || a.id.localeCompare(b.id);
const formatTime = (value?: string | null) => { if (!value) return ''; const d = new Date(value); return Number.isNaN(d.getTime()) ? '' : d.toLocaleString(); };
const isDesktop = () => typeof window !== 'undefined' && typeof window.matchMedia === 'function' && window.matchMedia('(min-width: 768px)').matches;

export default function Messages() {
  const {user} = useAuth();
  const base = user?.role === 'employer' ? '/employer' : '/jobseeker';
  const [search, setSearch] = useSearchParams();
  // ?c=<id> is the canonical deep link; ?conversation=<id> is kept for older links.
  const activeId = search.get('c') || search.get('conversation');
  const [convs, setConvs] = useState<Conversation[]>([]);
  const [convsLoading, setConvsLoading] = useState(true);
  const [convsError, setConvsError] = useState('');
  const [msgs, setMsgs] = useState<Message[]>([]);
  const [threadState, setThreadState] = useState<'idle' | 'loading' | 'ready' | 'missing' | 'error'>('idle');
  const [threadError, setThreadError] = useState('');
  const [truncated, setTruncated] = useState(false);
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const [sendError, setSendError] = useState('');
  const convsRef = useRef(convs);
  convsRef.current = convs;
  const activeRef = useRef(activeId);
  const readThreadRef = useRef<string | null>(null);
  const seenIds = useRef(new Set<string>());
  activeRef.current = activeId;
  const scroller = useRef<HTMLDivElement>(null);
  const stickToBottom = useRef(true);

  const select = useCallback((id: string | null, replace = false) => {
    setSearch(prev => { const next = new URLSearchParams(prev); next.delete('conversation'); if (id) next.set('c', id); else next.delete('c'); return next; }, {replace});
  }, [setSearch]);

  const loadConvs = useCallback(async () => {
    try {
      const d = await apiGet<any>('/conversations');
      const rows: Conversation[] = d.conversations || [];
      // The open thread was marked read when it loaded; an inbox response computed earlier may still count it.
      setConvs(readThreadRef.current ? rows.map(c => c.id === readThreadRef.current ? {...c, unreadCount: 0} : c) : rows);
      setConvsError('');
      // Desktop shows list and thread side by side, so open the latest thread; phones keep the list.
      if (!activeRef.current && rows[0] && isDesktop()) select(rows[0].id, true);
    } catch (e: any) {
      setConvsError(errorMessage(e, 'Unable to load conversations.'));
    } finally {
      setConvsLoading(false);
    }
  }, [select]);

  const loadThread = useCallback(async (id: string, silent = false) => {
    if (!silent) { setThreadState('loading'); setThreadError(''); }
    try {
      const d = await apiGet<any>(`/conversations/${id}/messages`);
      if (activeRef.current !== id) return;
      const server: Message[] = [...(d.messages || [])].sort(byTime);
      const newest = server[server.length - 1]?.createdAt || '';
      // Keep anything sent locally after this response was produced; the next poll will include it.
      setMsgs(prev => [...server, ...prev.filter(m => m.createdAt > newest && !server.some(s => s.id === m.id))]);
      setTruncated(Boolean(d.truncated));
      setThreadState('ready');
      // A thread opened by deep link right after it was created may be missing from an earlier inbox fetch.
      if (!silent && !convsRef.current.some(c => c.id === id)) void loadConvsRef.current();
      // Opening a thread marks it read on the server.
      readThreadRef.current = id;
      const receivedUnread = server.some(m => m.senderId !== user?.id && !seenIds.current.has(m.id));
      server.forEach(m => seenIds.current.add(m.id));
      setConvs(prev => prev.map(c => c.id === id && c.unreadCount ? {...c, unreadCount: 0} : c));
      if (!silent || receivedUnread) announceUnreadChanged();
    } catch (e: any) {
      if (activeRef.current !== id || silent) return;
      if (e?.status === 404) setThreadState('missing');
      else { setThreadState('error'); setThreadError(errorMessage(e, 'Unable to load messages.')); }
    }
  }, [user?.id]);

  const loadConvsRef = useRef(loadConvs);
  loadConvsRef.current = loadConvs;
  useEffect(() => { void loadConvs(); }, [loadConvs]);
  useEffect(() => {
    setMsgs([]); setTruncated(false); setSendError(''); stickToBottom.current = true; readThreadRef.current = null;
    if (activeId) void loadThread(activeId); else setThreadState('idle');
  }, [activeId, loadThread]);
  useVisiblePolling(() => activeRef.current && loadThread(activeRef.current, true), THREAD_POLL_MS, Boolean(activeId));
  useVisiblePolling(loadConvs, INBOX_POLL_MS);

  useLayoutEffect(() => {
    const el = scroller.current;
    if (el && stickToBottom.current) el.scrollTop = el.scrollHeight;
  }, [msgs]);
  const onScroll = () => { const el = scroller.current; if (el) stickToBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80; };

  async function send(e?: React.FormEvent) {
    e?.preventDefault();
    const id = activeId;
    const body = text.trim();
    if (!id || !body || sending) return;
    if (body.length > MESSAGE_MAX_LENGTH) { setSendError(`Messages can be at most ${MESSAGE_MAX_LENGTH.toLocaleString()} characters.`); return; }
    setSending(true); setSendError('');
    try {
      const d = await apiPost<any>(`/conversations/${id}/messages`, {body});
      if (activeRef.current === id) { stickToBottom.current = true; setMsgs(xs => xs.some(m => m.id === d.message.id) ? xs : [...xs, d.message].sort(byTime)); }
      setText('');
      setConvs(prev => { const row = prev.find(c => c.id === id); return row ? [{...row, lastMessage: body.slice(0, 200), lastMessageAt: d.message.createdAt, lastMessageFromMe: true}, ...prev.filter(c => c.id !== id)] : prev; });
      void loadConvs();
    } catch (err: any) {
      const message = errorMessage(err, 'Unable to send your message.');
      setSendError(message);
      if (err?.status !== 429) toast.error(message);
    } finally {
      setSending(false);
    }
  }

  const onKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    // Enter sends; Shift+Enter inserts a newline; never send mid-IME composition.
    if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); void send(); }
  };

  const nameOf = (c?: Conversation) => !c ? 'Conversation' : c.counterpartName || (c.viewerSide === 'candidate' ? c.employerName : c.viewerSide === 'employer' ? c.candidateName : undefined) || 'Verse member';
  const active = convs.find(c => c.id === activeId);
  const trimmedLength = text.trim().length;
  const lastMineId = [...msgs].reverse().find(m => m.senderId === user?.id)?.id;

  return <div className="min-h-screen bg-slate-950 text-white"><Navigation/>
    <main className="max-w-6xl mx-auto px-4 md:px-6 pt-24 md:pt-28 pb-28 lg:pb-16">
      <h1 className={`text-3xl md:text-4xl font-bold mb-5 md:mb-7 ${activeId ? 'hidden md:block' : ''}`}>Messages</h1>
      <Card className="bg-white/[.05] border-white/10 overflow-hidden">
        <CardContent className="p-0 grid md:grid-cols-[320px_minmax(0,1fr)] md:h-[640px]">
          <aside aria-label="Conversations" className={`md:border-r border-white/10 md:h-full md:overflow-y-auto ${activeId ? 'hidden md:block' : ''}`}>
            {convsLoading ? <div className="p-6 text-sm text-slate-400" role="status">Loading conversations…</div>
              : convsError && convs.length === 0 ? <div className="p-6 text-sm" role="alert"><p className="text-rose-300">{convsError}</p><Button variant="outline" size="sm" className="mt-3" onClick={() => { setConvsLoading(true); void loadConvs(); }}>Try again</Button></div>
              : convs.length === 0 ? <div className="p-6 text-sm text-slate-400" data-testid="messages-empty">
                  <MessageSquare className="mb-3 text-slate-500" aria-hidden="true"/>
                  <p className="font-semibold text-slate-200">No conversations yet</p>
                  <p className="mt-2">Conversations start from an opportunity, an applicant, a talent profile or a booking.</p>
                  <div className="mt-4 flex flex-wrap gap-2">{user?.role === 'employer'
                    ? <><Button size="sm" asChild><Link to="/employer/applications">Review applicants</Link></Button><Button size="sm" variant="outline" asChild><Link to="/employer/candidates">Find talent</Link></Button></>
                    : <><Button size="sm" asChild><Link to="/jobseeker/jobs">Explore opportunities</Link></Button><Button size="sm" variant="outline" asChild><Link to="/jobseeker/bookings">Bookings</Link></Button></>}</div>
                </div>
              : <ul>{convs.map(c => <li key={c.id}><button type="button" onClick={() => select(c.id)} aria-current={activeId === c.id ? 'true' : undefined} className={`w-full text-left p-4 border-b border-white/10 ${activeId === c.id ? 'bg-violet-500/10' : 'hover:bg-white/5'}`}>
                  <div className="flex items-start justify-between gap-2"><span className="font-semibold truncate" data-testid="conversation-name">{nameOf(c)}</span>{(c.unreadCount || 0) > 0 && <span className="shrink-0 rounded-full bg-fuchsia-500 px-2 py-0.5 text-[11px] font-bold" aria-label={`${c.unreadCount} unread`}>{c.unreadCount}</span>}</div>
                  <div className="text-xs text-violet-300 mt-1 truncate">{c.jobTitle || 'General conversation'}</div>
                  <div className={`text-sm mt-2 truncate ${(c.unreadCount || 0) > 0 ? 'text-slate-200 font-medium' : 'text-slate-500'}`}>{c.lastMessage ? `${c.lastMessageFromMe ? 'You: ' : ''}${c.lastMessage}` : 'No messages yet'}</div>
                </button></li>)}</ul>}
          </aside>
          <section aria-label="Conversation" className={`flex-col min-w-0 md:h-full ${activeId ? 'flex' : 'hidden md:flex'}`}>
            {activeId && <header className="flex items-center gap-3 border-b border-white/10 p-3 md:p-4">
              <Button type="button" variant="ghost" size="icon" className="md:hidden" aria-label="Back to conversations" onClick={() => select(null)}><ArrowLeft size={18}/></Button>
              <div className="min-w-0"><div className="font-semibold truncate" data-testid="thread-name">{active ? nameOf(active) : threadState === 'missing' ? 'Conversation' : ' '}</div>{active && <div className="text-xs text-violet-300 truncate">{active.jobTitle || 'General conversation'}</div>}</div>
            </header>}
            <div ref={scroller} onScroll={onScroll} className="flex-1 p-4 md:p-5 space-y-3 overflow-y-auto h-[calc(100vh-330px)] min-h-[280px] md:h-auto md:min-h-0" role="log" aria-live="polite" aria-label="Messages">
              {!activeId ? <div className="h-full grid place-items-center text-slate-500">{convs.length ? 'Select a conversation' : 'Your messages will appear here'}</div>
                : threadState === 'loading' && msgs.length === 0 ? <div className="text-slate-400 text-sm" role="status">Loading messages…</div>
                : threadState === 'missing' ? <div className="h-full grid place-items-center text-center text-slate-400" role="alert"><div><p>This conversation is unavailable.</p><Button variant="outline" size="sm" className="mt-3" onClick={() => select(null)}>Back to conversations</Button></div></div>
                : threadState === 'error' ? <div className="text-center" role="alert"><p className="text-rose-300">{threadError}</p><Button variant="outline" size="sm" className="mt-3" onClick={() => void loadThread(activeId)}>Try again</Button></div>
                : msgs.length === 0 ? <div className="h-full grid place-items-center text-slate-500 text-center" data-testid="thread-empty">No messages yet. Say hello to {nameOf(active)}.</div>
                : <>
                    {truncated && <p className="text-center text-xs text-slate-500" data-testid="history-truncated">Showing the latest {msgs.length} messages.</p>}
                    {msgs.map(m => { const mine = m.senderId === user?.id; return <div key={m.id} data-testid="message" data-mine={mine ? 'true' : 'false'} className={`max-w-[85%] md:max-w-[75%] w-fit rounded-2xl px-4 py-3 ${mine ? 'ml-auto bg-violet-600' : 'bg-white/10'}`}>
                      <div className="text-sm whitespace-pre-wrap break-words [overflow-wrap:anywhere]" data-testid="message-body">{m.body}</div>
                      <div className="text-[11px] opacity-70 mt-1 flex gap-2 justify-end"><time dateTime={m.createdAt}>{formatTime(m.createdAt)}</time>{mine && m.id === lastMineId && <span data-testid="read-receipt">{m.readAt ? `Seen ${formatTime(m.readAt)}` : 'Sent'}</span>}</div>
                    </div>; })}
                  </>}
            </div>
            {activeId && threadState !== 'missing' && <form onSubmit={send} className="p-3 md:p-4 border-t border-white/10">
              <div className="flex gap-2 items-end">
                <textarea value={text} onChange={e => { setText(e.target.value); if (sendError) setSendError(''); }} onKeyDown={onKeyDown} rows={2}
                  placeholder="Write a message…" aria-label="Message" aria-describedby="message-hint"
                  className="flex-1 min-w-0 resize-none max-h-40 rounded-md bg-black/20 border border-white/15 px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-violet-400"/>
                <Button type="submit" aria-label="Send message" disabled={sending || trimmedLength === 0 || trimmedLength > MESSAGE_MAX_LENGTH} aria-busy={sending}><Send size={16} aria-hidden="true"/></Button>
              </div>
              <div className="mt-1 flex justify-between gap-3 text-[11px] text-slate-500"><span id="message-hint" className="hidden sm:inline">Enter to send · Shift+Enter for a new line</span>{trimmedLength > MESSAGE_MAX_LENGTH - 500 && <span className={trimmedLength > MESSAGE_MAX_LENGTH ? 'text-rose-300' : ''} data-testid="message-counter">{trimmedLength.toLocaleString()} / {MESSAGE_MAX_LENGTH.toLocaleString()}</span>}</div>
              {sendError && <p role="alert" className="mt-2 text-sm text-amber-200" data-testid="send-error">{sendError}</p>}
            </form>}
          </section>
        </CardContent>
      </Card>
    </main>
  </div>;
}
