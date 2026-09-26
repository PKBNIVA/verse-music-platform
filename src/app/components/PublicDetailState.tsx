import {Link} from 'react-router';
import {PublicNav} from './PublicNav';
import {Button} from './ui/button';
import {usePageMeta} from './PageMeta';

type Props = {
  loading: boolean;
  error?: {message: string; status?: number} | null;
  noun: string;
  backTo: string;
  backLabel: string;
  onRetry: () => void;
};

/** Loading / not-found / failure screen shared by the public detail pages. */
export function PublicDetailState({loading, error, noun, backTo, backLabel, onRetry}: Props) {
  const missing = !loading && (error?.status === 404 || error?.status === 400);
  usePageMeta(loading ? undefined : missing ? `${noun[0].toUpperCase()}${noun.slice(1)} not found` : `Unable to load ${noun}`);
  return <div className="min-h-screen bg-slate-950 text-white"><PublicNav/><main className="px-5 py-20 text-center">
    {loading
      ? <p className="text-slate-400" role="status">Loading {noun}…</p>
      : missing
        ? <div><h1 className="text-3xl font-bold">This {noun} isn’t available</h1><p className="text-slate-400 mt-3">It may have been removed, filled or made private.</p><Button className="mt-6" asChild><Link to={backTo}>{backLabel}</Link></Button></div>
        : <div role="alert"><h1 className="text-3xl font-bold">We couldn’t load this {noun}</h1><p className="text-rose-300 mt-3">{error?.message || 'Something went wrong.'}</p><div className="flex flex-wrap justify-center gap-3 mt-6"><Button variant="outline" onClick={onRetry}>Try again</Button><Button variant="ghost" asChild><Link to={backTo}>{backLabel}</Link></Button></div></div>}
  </main></div>;
}
