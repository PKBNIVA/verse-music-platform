import {useEffect, useMemo, useRef, useState} from 'react';
import {Navigation} from '../components/Navigation';
import {Card, CardContent} from '../components/ui/card';
import {Button} from '../components/ui/button';
import {Input} from '../components/ui/input';
import {Textarea} from '../components/ui/textarea';
import {Label} from '../components/ui/label';
import {Badge} from '../components/ui/badge';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '../components/ui/alert-dialog';
import {apiDelete, apiGet, apiPatch, apiPost, discardUpload, uploadContentType, UPLOAD_ACCEPT, uploadMedia, validateUploadFile} from '../lib/api';
import {toast} from 'sonner';
import {Music, Video, FolderKanban, Trash2, Plus, Star, Tag, Eye, EyeOff, Pencil, Filter, UploadCloud, RotateCcw, X, AlertCircle, CheckCircle2} from 'lucide-react';
import {describeWorkSample, WorkSamplePlayer} from '../components/WorkSamplePlayer';

const split = (s: string) => s.split(',').map((x) => x.trim()).filter(Boolean);
const join = (a: any[]) => (a || []).join(', ');
const blank = {type: 'audio', title: '', url: '', description: '', tags: '', genres: '', roles: '', instruments: '', creditedAs: '', year: '', featured: false, visibility: 'public', mediaMetadata: {}, thumbnailUrl: '', waveformUrl: ''};
const AUDIO_KINDS = ['audio', 'composition', 'production', 'mix', 'master'];
const VIDEO_KINDS = ['video', 'showreel', 'live'];

type UploadState =
  | {status: 'idle'}
  | {status: 'uploading'; file: File; pct: number}
  | {status: 'error'; file: File; message: string; retryable: boolean}
  | {status: 'done'; file: File; id?: string};

const formatSize = (bytes: number) => bytes >= 1024 * 1024 ? `${(bytes / 1024 / 1024).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;

function kindForUpload(current: string, contentType: string) {
  if (contentType.startsWith('audio/')) return AUDIO_KINDS.includes(current) ? current : 'audio';
  if (contentType.startsWith('video/')) return VIDEO_KINDS.includes(current) ? current : 'video';
  return AUDIO_KINDS.includes(current) || VIDEO_KINDS.includes(current) ? 'project' : current;
}

export default function Portfolio() {
  const [items, setItems] = useState<any[]>([]);
  const [f, setF] = useState<any>(blank);
  const [editId, setEditId] = useState<string | null>(null);
  const [filter, setFilter] = useState('all');
  const [upload, setUpload] = useState<UploadState>({status: 'idle'});
  const [pendingDelete, setPendingDelete] = useState<any | null>(null);
  const [saving, setSaving] = useState(false);
  const abortRef = useRef<AbortController | null>(null);

  const load = () => apiGet<any>('/portfolio').then((d) => setItems(d.items || [])).catch((e: any) => toast.error(e.message));
  useEffect(() => {
    load();
    return () => abortRef.current?.abort();
  }, []);

  const visible = useMemo(() => filter === 'all' ? items : items.filter((i) => i.type === filter || i.tags?.includes(filter) || i.genres?.includes(filter)), [items, filter]);
  const preview = useMemo(() => f.url ? describeWorkSample(f.url, f.mediaMetadata?.contentType) : null, [f.url, f.mediaMetadata]);
  const unsavedUploadId = upload.status === 'done' ? upload.id : undefined;

  function resetForm() {
    setF(blank);
    setEditId(null);
    setUpload({status: 'idle'});
  }

  async function startUpload(file: File) {
    try {
      validateUploadFile(file);
    } catch (error: any) {
      setUpload({status: 'error', file, message: error.message, retryable: false});
      return;
    }
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    setUpload({status: 'uploading', file, pct: 0});
    try {
      const out = await uploadMedia(file, {signal: controller.signal, onProgress: (pct) => setUpload({status: 'uploading', file, pct})});
      const contentType = out.contentType || uploadContentType(file) || '';
      setF((x: any) => ({
        ...x,
        url: out.url,
        type: kindForUpload(x.type, contentType),
        title: x.title || file.name.replace(/\.[^.]+$/, '').replace(/[_-]+/g, ' ').trim(),
        mediaMetadata: {contentType, byteSize: out.byteSize || file.size, filename: file.name, uploadId: out.id},
        thumbnailUrl: out.thumbnailUrl || '',
        waveformUrl: out.waveformUrl || '',
      }));
      setUpload({status: 'done', file, id: out.id});
      toast.success('File uploaded');
    } catch (error: any) {
      if (controller.signal.aborted) {
        setUpload({status: 'idle'});
        return;
      }
      const retryable = !['UNSUPPORTED_TYPE', 'FILE_TOO_LARGE', 'FILE_EMPTY', 'UPLOAD_REJECTED'].includes(error?.code) && error?.status !== 422;
      setUpload({status: 'error', file, message: error?.message || 'Upload failed.', retryable});
    } finally {
      if (abortRef.current === controller) abortRef.current = null;
    }
  }

  async function removeUploadedFile() {
    const id = unsavedUploadId;
    setF((x: any) => ({...x, url: '', mediaMetadata: {}, thumbnailUrl: '', waveformUrl: ''}));
    setUpload({status: 'idle'});
    if (id) await discardUpload(id).catch(() => undefined);
  }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (upload.status === 'uploading') return;
    const payload = {...f, tags: split(f.tags), genres: split(f.genres), roles: split(f.roles), instruments: split(f.instruments), year: f.year ? Number(f.year) : null};
    setSaving(true);
    try {
      if (editId) await apiPatch(`/portfolio/${editId}`, payload);
      else await apiPost('/portfolio', payload);
      toast.success(editId ? 'Work sample updated' : 'Work sample added');
      resetForm();
      load();
    } catch (error: any) {
      toast.error(error.message);
    } finally {
      setSaving(false);
    }
  }

  function edit(i: any) {
    setEditId(i.id);
    setUpload({status: 'idle'});
    setF({type: i.type, title: i.title, url: i.url, description: i.description || '', tags: join(i.tags), genres: join(i.genres), roles: join(i.roles), instruments: join(i.instruments), creditedAs: i.creditedAs || '', year: i.year || '', featured: !!i.featured, visibility: i.visibility || 'public', mediaMetadata: i.mediaMetadata || {}, thumbnailUrl: i.thumbnailUrl || '', waveformUrl: i.waveformUrl || ''});
    window.scrollTo({top: 0, behavior: 'smooth'});
  }

  async function confirmDelete() {
    const item = pendingDelete;
    setPendingDelete(null);
    if (!item) return;
    try {
      await apiDelete(`/portfolio/${item.id}`);
      if (editId === item.id) resetForm();
      toast.success('Work sample deleted');
      load();
    } catch (error: any) {
      toast.error(error.message);
    }
  }

  const Icon = ({type}: {type: string}) => AUDIO_KINDS.includes(type) ? <Music/> : VIDEO_KINDS.includes(type) ? <Video/> : <FolderKanban/>;
  const filters = ['all', ...Array.from(new Set(items.flatMap((i) => [i.type, ...(i.genres || [])]))).slice(0, 12)];
  const isUploaded = Boolean(f.mediaMetadata?.uploadId) || upload.status === 'done';

  return <div className="min-h-screen bg-slate-950 text-white">
    <Navigation/>
    <main className="max-w-7xl mx-auto px-5 pt-28 pb-16">
      <div className="max-w-3xl">
        <h1 className="text-4xl font-bold">Work samples</h1>
        <p className="text-slate-400 mt-2 mb-7 leading-7">Don’t use one generic reel for everything. Add several samples and tag each by genre, role and instrument so the right employer sees the right proof.</p>
      </div>
      <div className="grid xl:grid-cols-[390px_1fr] gap-6">
        <Card className="bg-white/[.06] border-white/10 h-fit">
          <CardContent className="p-5">
            <h2 className="font-semibold text-lg mb-4 flex">{editId ? <Pencil size={18} className="mr-2"/> : <Plus size={18} className="mr-2"/>}{editId ? 'Edit work sample' : 'Add work sample'}</h2>
            <form onSubmit={save} className="space-y-3">
              <div>
                <Label htmlFor="sample-kind">Kind of work</Label>
                <select id="sample-kind" value={f.type} onChange={(e) => setF({...f, type: e.target.value})} className="w-full h-10 mt-2 rounded-md bg-slate-900 border border-white/15 px-3">
                  <option value="audio">Audio / track</option><option value="video">Video</option><option value="live">Live performance</option><option value="showreel">Showreel</option>
                  <option value="composition">Composition</option><option value="production">Production</option><option value="mix">Mix</option><option value="master">Master</option>
                  <option value="technical">Technical / show work</option><option value="credit">Credit</option><option value="project">Project</option><option value="other">Other</option>
                </select>
              </div>
              <Input aria-label="Title" required value={f.title} onChange={(e) => setF({...f, title: e.target.value})} placeholder="Example: Live Sufi vocal — Jaipur 2026" className="bg-black/20 border-white/15"/>
              <Input aria-label="Link" required type="url" value={f.url} readOnly={upload.status === 'done'}
                onChange={(e) => setF({...f, url: e.target.value, mediaMetadata: {}, thumbnailUrl: '', waveformUrl: ''})}
                placeholder="https:// YouTube, Spotify, SoundCloud or website link" className="bg-black/20 border-white/15"/>

              <div className="rounded-lg border border-dashed border-white/15 p-3" aria-live="polite">
                <div className="text-xs text-slate-500 mb-2">Or upload a file — MP3, WAV, MP4, JPEG, PNG, WebP or PDF, up to 100 MB</div>
                {upload.status === 'uploading' ? <div>
                  <div className="flex justify-between text-xs text-slate-300 mb-1"><span className="truncate mr-2">Uploading {upload.file.name}</span><span>{upload.pct}%</span></div>
                  <div role="progressbar" aria-label="Upload progress" aria-valuemin={0} aria-valuemax={100} aria-valuenow={upload.pct} className="h-2 rounded bg-white/10 overflow-hidden">
                    <div className="h-full bg-violet-400 transition-[width]" style={{width: `${upload.pct}%`}}/>
                  </div>
                  <Button type="button" size="sm" variant="ghost" className="mt-2" onClick={() => abortRef.current?.abort()}><X size={14} className="mr-1"/>Cancel upload</Button>
                </div> : upload.status === 'done' ? <div className="flex items-center gap-2 text-sm text-emerald-300">
                  <CheckCircle2 size={16}/><span className="truncate flex-1">{upload.file.name} · {formatSize(upload.file.size)}</span>
                  <Button type="button" size="sm" variant="ghost" onClick={removeUploadedFile}><X size={14} className="mr-1"/>Remove file</Button>
                </div> : <label className="inline-flex items-center gap-2 text-sm text-violet-300 cursor-pointer">
                  <UploadCloud size={16}/>Choose file
                  <input className="sr-only" aria-label="Upload a work-sample file" type="file" accept={UPLOAD_ACCEPT}
                    onChange={(e) => { const file = e.target.files?.[0]; e.currentTarget.value = ''; if (file) startUpload(file); }}/>
                </label>}
                {upload.status === 'error' && <div role="alert" className="mt-2 text-sm text-rose-300 flex items-start gap-2">
                  <AlertCircle size={16} className="shrink-0 mt-0.5"/>
                  <div className="flex-1"><div>{upload.message}</div>
                    {upload.retryable && <Button type="button" size="sm" variant="outline" className="mt-2" onClick={() => startUpload(upload.file)}><RotateCcw size={14} className="mr-1"/>Retry upload</Button>}
                  </div>
                </div>}
              </div>

              {f.url && preview && <div data-testid="sample-preview">
                <div className="text-xs text-slate-500 mb-1">Preview</div>
                {preview.kind === 'link'
                  ? <div className="text-xs text-slate-400 rounded-lg border border-white/10 p-3">This link will be shown as an “open” link. YouTube, Spotify and SoundCloud links play inline.</div>
                  : <WorkSamplePlayer sample={{title: f.title || 'Preview', url: f.url, type: f.type, mediaMetadata: f.mediaMetadata, thumbnailUrl: f.thumbnailUrl, waveformUrl: f.waveformUrl}} compact/>}
              </div>}

              <Textarea aria-label="Description" value={f.description} onChange={(e) => setF({...f, description: e.target.value})} placeholder="What did you do on this work? What should a hirer notice?" className="bg-black/20 border-white/15"/>
              <Input aria-label="Roles" value={f.roles} onChange={(e) => setF({...f, roles: e.target.value})} placeholder="Roles: Lead Vocalist, Composer, FOH Engineer" className="bg-black/20 border-white/15"/>
              <Input aria-label="Genres" value={f.genres} onChange={(e) => setF({...f, genres: e.target.value})} placeholder="Genres: Bollywood, Sufi, Indie Pop" className="bg-black/20 border-white/15"/>
              <Input aria-label="Instruments" value={f.instruments} onChange={(e) => setF({...f, instruments: e.target.value})} placeholder="Instruments / voice: Vocals, Tabla, Bass" className="bg-black/20 border-white/15"/>
              <Input aria-label="Tags" value={f.tags} onChange={(e) => setF({...f, tags: e.target.value})} placeholder="Tags: live, studio, DiGiCo, playback, wedding" className="bg-black/20 border-white/15"/>
              <div className="grid grid-cols-2 gap-3">
                <Input aria-label="Credited as" value={f.creditedAs} onChange={(e) => setF({...f, creditedAs: e.target.value})} placeholder="Credited as" className="bg-black/20 border-white/15"/>
                <Input aria-label="Year" type="number" min="1900" max="2100" value={f.year} onChange={(e) => setF({...f, year: e.target.value})} placeholder="Year" className="bg-black/20 border-white/15"/>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <label className="flex items-center gap-2 text-sm rounded-md border border-white/10 px-3 h-10"><input type="checkbox" checked={f.featured} onChange={(e) => setF({...f, featured: e.target.checked})}/><Star size={15}/>Feature this</label>
                <select aria-label="Visibility" value={f.visibility} onChange={(e) => setF({...f, visibility: e.target.value})} className="h-10 rounded-md bg-slate-900 border border-white/15 px-3"><option value="public">Public</option><option value="private">Private</option></select>
              </div>
              <div className="flex gap-2">
                <Button className="flex-1" disabled={upload.status === 'uploading' || saving}>{upload.status === 'uploading' ? 'Waiting for upload…' : editId ? 'Save changes' : 'Add sample'}</Button>
                {editId && <Button type="button" variant="outline" onClick={resetForm}>Cancel</Button>}
              </div>
              {isUploaded && !editId && <p className="text-xs text-slate-500">Uploaded files you don’t save are deleted automatically after 24 hours.</p>}
            </form>
          </CardContent>
        </Card>

        <div>
          <div className="flex items-center gap-2 overflow-x-auto pb-3"><Filter size={16} className="text-slate-500 shrink-0"/>
            {filters.map((x) => <Button key={x} size="sm" variant={filter === x ? 'secondary' : 'outline'} onClick={() => setFilter(x)} className="whitespace-nowrap">{x}</Button>)}
          </div>
          {visible.length === 0 ? <Card className="bg-white/5 border-white/10"><CardContent className="p-10 text-center">
            <div className="text-slate-300 font-medium">No work samples in this view.</div>
            <div className="text-slate-500 text-sm mt-2">A useful starting portfolio is 3–6 strong, different samples rather than dozens of unlabelled links.</div>
          </CardContent></Card> : <div className="grid md:grid-cols-2 gap-4">
            {visible.map((i) => <Card key={i.id} className="bg-white/[.06] border-white/10" data-testid="work-sample"><CardContent className="p-5">
              <div className="flex justify-between">
                <div className="p-2 rounded-lg bg-violet-500/15 text-violet-300"><Icon type={i.type}/></div>
                <div className="flex gap-1">
                  {i.featured && <span title="Featured" className="p-2 text-amber-300"><Star size={16}/></span>}
                  {i.visibility === 'private' ? <span title="Private" className="p-2 text-slate-500"><EyeOff size={16}/></span> : <span title="Public" className="p-2 text-emerald-300"><Eye size={16}/></span>}
                  <Button size="icon" variant="ghost" aria-label={`Edit ${i.title}`} onClick={() => edit(i)}><Pencil size={16}/></Button>
                  <Button size="icon" variant="ghost" aria-label={`Delete ${i.title}`} onClick={() => setPendingDelete(i)}><Trash2 size={16}/></Button>
                </div>
              </div>
              <h3 className="font-semibold text-lg mt-4">{i.title}</h3>
              <div className="text-xs text-violet-300 mt-1">{[i.creditedAs, i.year].filter(Boolean).join(' · ')}</div>
              <p className="text-sm text-slate-400 mt-2 min-h-10 line-clamp-3">{i.description || 'No description added.'}</p>
              <div className="flex flex-wrap gap-1 mt-3">{[...(i.roles || []), ...(i.genres || []), ...(i.instruments || []), ...(i.tags || [])].slice(0, 8).map((x: string) => <Badge key={x} variant="secondary"><Tag size={10} className="mr-1"/>{x}</Badge>)}</div>
              <div className="mt-4"><WorkSamplePlayer sample={i} compact/></div>
            </CardContent></Card>)}
          </div>}
        </div>
      </div>
    </main>

    <AlertDialog open={Boolean(pendingDelete)} onOpenChange={(open) => { if (!open) setPendingDelete(null); }}>
      <AlertDialogContent className="bg-slate-900 text-white border-white/10">
        <AlertDialogHeader>
          <AlertDialogTitle>Delete “{pendingDelete?.title}”?</AlertDialogTitle>
          <AlertDialogDescription className="text-slate-400">
            The work sample is removed from your profile{pendingDelete?.mediaMetadata?.uploadId ? ' and the uploaded file is permanently deleted' : ''}. This cannot be undone.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel className="text-slate-900">Keep it</AlertDialogCancel>
          <AlertDialogAction className="bg-rose-600 hover:bg-rose-500" onClick={confirmDelete}>Delete work sample</AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  </div>;
}
