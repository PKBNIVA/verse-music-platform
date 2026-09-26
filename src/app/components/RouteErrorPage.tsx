import { useEffect } from 'react';
import { isRouteErrorResponse, useRouteError } from 'react-router';
import { AlertTriangle, Home, RefreshCw } from 'lucide-react';
import { BrandMark } from './BrandMark';
import { Button } from './ui/button';

const CHUNK_RELOAD_KEY = 'verse_chunk_reload_at';
// A reload that fails again inside this window shows the error page instead of reloading forever.
const CHUNK_RELOAD_WINDOW_MS = 30_000;

/** True when a lazily loaded page's JS/CSS could not be fetched, typically after a redeploy removed old chunks. */
export function isChunkLoadError(error: unknown) {
  const message = error instanceof Error ? `${error.name} ${error.message}` : typeof error === 'string' ? error : '';
  return /Failed to fetch dynamically imported module|error loading dynamically imported module|Importing a module script failed|Unable to preload CSS|ChunkLoadError|Loading (CSS )?chunk \S+ failed/i.test(message);
}

let reloadScheduled = false;

/**
 * Claims the single automatic reload for this tab. Returns false when a reload was
 * already attempted recently or the guard cannot be stored (a reload could then loop).
 */
function claimChunkReload() {
  if (reloadScheduled) return true;
  try {
    const last = Number(sessionStorage.getItem(CHUNK_RELOAD_KEY) || 0);
    if (Date.now() - last < CHUNK_RELOAD_WINDOW_MS) return false;
    sessionStorage.setItem(CHUNK_RELOAD_KEY, String(Date.now()));
  } catch {
    return false;
  }
  reloadScheduled = true;
  return true;
}

export function RouteErrorPage() {
  const error = useRouteError();
  const chunkError = isChunkLoadError(error);
  const reloading = chunkError && claimChunkReload();

  useEffect(() => {
    if (reloading) window.location.reload();
    else console.error('Verse route error', error);
  }, [error, reloading]);

  if (reloading) {
    return <div className="min-h-screen bg-slate-950 text-white grid place-items-center px-5" role="status" aria-live="polite"><div className="text-center"><div className="mx-auto w-fit animate-pulse"><BrandMark /></div><p className="mt-4 text-sm text-slate-400">Loading the latest version of Verse…</p></div></div>;
  }

  const notFound = isRouteErrorResponse(error) && error.status === 404;
  const title = chunkError ? 'Verse has been updated.' : notFound ? 'This page could not be found.' : 'This screen missed a beat.';
  const body = chunkError
    ? 'A new version of Verse was released while this page was open. Reload to continue with the latest version.'
    : 'Your data is safe. Reload the page to try again, or head back home.';

  const reload = () => {
    // A deliberate reload may retry the automatic chunk recovery once more.
    try { sessionStorage.removeItem(CHUNK_RELOAD_KEY); } catch { /* storage blocked */ }
    window.location.reload();
  };

  return <main className="min-h-screen bg-slate-950 text-white grid place-items-center px-5"><div role="alert" className="verse-surface max-w-lg rounded-3xl p-8 text-center"><span className="mx-auto grid h-14 w-14 place-items-center rounded-2xl bg-rose-500/15 text-rose-300"><AlertTriangle aria-hidden="true" /></span><h1 className="mt-5 text-2xl font-black">{title}</h1><p className="mt-3 text-slate-300">{body}</p><div className="mt-6 flex flex-wrap justify-center gap-3"><Button onClick={reload}><RefreshCw size={16} className="mr-2" aria-hidden="true" />Reload</Button><Button variant="outline" onClick={() => window.location.assign('/')}><Home size={16} className="mr-2" aria-hidden="true" />Go home</Button></div></div></main>;
}
