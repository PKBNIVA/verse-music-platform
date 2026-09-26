import {useEffect, useState} from 'react';
import {ExternalLink, FileText, Image as ImageIcon, Link2, Music, Video} from 'lucide-react';
import {Badge} from './ui/badge';

type Sample = {
  id?: string; title: string; url: string; type?: string; description?: string; thumbnailUrl?: string; waveformUrl?: string;
  mediaMetadata?: any; tags?: string[]; genres?: string[]; roles?: string[]; instruments?: string[]; creditedAs?: string; year?: number;
};

export type WorkSampleMedia =
  | {kind: 'youtube' | 'spotify' | 'soundcloud'; embedUrl: string; height: number}
  | {kind: 'audio' | 'video' | 'image' | 'pdf'; src: string}
  | {kind: 'link'; src: string};

const YOUTUBE_ID = /^[A-Za-z0-9_-]{11}$/;
const SPOTIFY_TYPES = new Set(['track', 'album', 'playlist', 'episode', 'show', 'artist']);
const EXTENSION_KINDS: Record<string, 'audio' | 'video' | 'image' | 'pdf'> = {
  mp3: 'audio', wav: 'audio', m4a: 'audio', aac: 'audio', ogg: 'audio', oga: 'audio', flac: 'audio',
  mp4: 'video', m4v: 'video', webm: 'video', mov: 'video',
  jpg: 'image', jpeg: 'image', png: 'image', webp: 'image', gif: 'image', avif: 'image',
  pdf: 'pdf',
};

function youtubeId(u: URL) {
  const host = u.hostname.replace(/^(www\.|m\.|music\.)/, '');
  let id: string | null = null;
  if (host === 'youtu.be') id = u.pathname.split('/')[1] || null;
  else if (host === 'youtube.com' || host === 'youtube-nocookie.com') {
    const [first, second] = u.pathname.split('/').filter(Boolean);
    id = first === 'watch' || !first ? u.searchParams.get('v') : ['shorts', 'embed', 'live', 'v'].includes(first) ? second || null : null;
  }
  return id && YOUTUBE_ID.test(id) ? id : null;
}

function startSeconds(u: URL) {
  const raw = u.searchParams.get('t') || u.searchParams.get('start') || '';
  const match = raw.match(/^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?$/);
  if (!raw || !match) return 0;
  return Number(match[1] || 0) * 3600 + Number(match[2] || 0) * 60 + Number(match[3] || 0);
}

function kindFromContentType(type?: string) {
  if (!type) return null;
  if (type === 'application/pdf') return 'pdf' as const;
  const family = type.split('/')[0];
  return family === 'audio' || family === 'video' || family === 'image' ? family : null;
}

/** Works out how a work-sample URL should be shown. Exported for the editor preview. */
export function describeWorkSample(url: string, contentType?: string): WorkSampleMedia | null {
  let u: URL;
  try {
    u = new URL(url);
  } catch {
    return null;
  }
  if (!/^https?:$/.test(u.protocol)) return null;

  const yt = youtubeId(u);
  if (yt) {
    const start = startSeconds(u);
    return {kind: 'youtube', embedUrl: `https://www.youtube-nocookie.com/embed/${yt}${start ? `?start=${start}` : ''}`, height: u.pathname.startsWith('/shorts/') ? 360 : 208};
  }
  if (u.hostname === 'open.spotify.com') {
    const parts = u.pathname.split('/').filter(Boolean).filter((part) => !part.startsWith('intl-'));
    const [type, id] = parts[0] === 'embed' ? parts.slice(1) : parts;
    if (SPOTIFY_TYPES.has(type) && id && /^[A-Za-z0-9]+$/.test(id)) {
      return {kind: 'spotify', embedUrl: `https://open.spotify.com/embed/${type}/${id}`, height: type === 'track' || type === 'episode' ? 152 : 352};
    }
  }
  if (/(^|\.)soundcloud\.com$/.test(u.hostname) && u.hostname !== 'w.soundcloud.com' && u.pathname.split('/').filter(Boolean).length >= 1) {
    const isSet = u.pathname.includes('/sets/');
    return {
      kind: 'soundcloud',
      embedUrl: `https://w.soundcloud.com/player/?url=${encodeURIComponent(`${u.origin}${u.pathname}`)}&auto_play=false&visual=false`,
      height: isSet ? 300 : 166,
    };
  }
  const extension = decodeURIComponent(u.pathname).split('.').pop()?.toLowerCase() || '';
  const kind = kindFromContentType(contentType) || EXTENSION_KINDS[extension];
  return kind ? {kind, src: url} : {kind: 'link', src: url};
}

function MediaView({sample, media}: {sample: Sample; media: WorkSampleMedia | null}) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [sample.url]);
  if (!media || media.kind === 'link') {
    return sample.thumbnailUrl ? <img src={sample.thumbnailUrl} alt="" className="w-full max-h-64 object-cover"/> : null;
  }
  if (failed) {
    return <div role="status" className="p-4 text-sm text-amber-200 bg-amber-500/10">This file could not be played here. Use the open link to view it.</div>;
  }
  switch (media.kind) {
    case 'youtube':
    case 'spotify':
    case 'soundcloud':
      return <iframe title={`${sample.title} (${media.kind} player)`} src={media.embedUrl} loading="lazy" style={{height: media.height}}
        allow="autoplay; clipboard-write; encrypted-media; fullscreen; picture-in-picture" referrerPolicy="strict-origin-when-cross-origin"
        className="w-full border-0 bg-black"/>;
    case 'video':
      return <video controls preload="metadata" poster={sample.thumbnailUrl || undefined} className="w-full max-h-80 bg-black" src={media.src}
        onError={() => setFailed(true)} aria-label={sample.title}/>;
    case 'audio':
      return <div className="p-4">
        {sample.waveformUrl && <img src={sample.waveformUrl} alt="Audio waveform" className="w-full h-20 object-cover opacity-70 rounded-lg mb-3"/>}
        <audio controls preload="metadata" className="w-full" src={media.src} onError={() => setFailed(true)} aria-label={sample.title}/>
      </div>;
    case 'image':
      return <img src={media.src} alt={sample.title} loading="lazy" className="w-full max-h-80 object-contain bg-black" onError={() => setFailed(true)}/>;
    case 'pdf':
      return <a href={media.src} target="_blank" rel="noreferrer" className="flex items-center gap-3 p-4 hover:bg-white/5">
        <FileText size={28} className="text-rose-300 shrink-0"/>
        <span className="text-sm"><span className="block font-medium">PDF document</span><span className="text-slate-400">Open in a new tab</span></span>
      </a>;
  }
}

export function WorkSamplePlayer({sample, compact = false}: {sample: Sample; compact?: boolean}) {
  const media = describeWorkSample(sample.url, sample.mediaMetadata?.contentType);
  const kind = media?.kind;
  const KindIcon = kind === 'audio' || kind === 'spotify' || kind === 'soundcloud' ? Music
    : kind === 'video' || kind === 'youtube' ? Video
    : kind === 'image' ? ImageIcon
    : kind === 'pdf' ? FileText : Link2;
  return <div className="rounded-xl border border-white/10 bg-black/20 overflow-hidden" data-media-kind={kind || 'none'}>
    <MediaView sample={sample} media={media}/>
    <div className={compact ? 'p-3' : 'p-4'}>
      <div className="flex gap-3 items-start">
        <div className="mt-0.5 text-violet-300"><KindIcon size={17}/></div>
        <div className="min-w-0 flex-1">
          <div className="font-medium">{sample.title}</div>
          {(sample.creditedAs || sample.year) && <div className="text-xs text-violet-300 mt-1">{[sample.creditedAs, sample.year].filter(Boolean).join(' · ')}</div>}
          {!compact && sample.description && <p className="text-sm text-slate-400 mt-2 line-clamp-3">{sample.description}</p>}
          <div className="flex flex-wrap gap-1 mt-2">
            {[...(sample.roles || []), ...(sample.genres || []), ...(sample.instruments || []), ...(sample.tags || [])].slice(0, 8).map((x) => <Badge key={x} variant="secondary">{x}</Badge>)}
          </div>
        </div>
        <a href={sample.url} target="_blank" rel="noreferrer" className="text-slate-400 hover:text-white" title={kind === 'pdf' ? 'Open document' : 'Open source'} aria-label={`Open ${sample.title} in a new tab`}>
          <ExternalLink size={16}/>
        </a>
      </div>
    </div>
  </div>;
}
