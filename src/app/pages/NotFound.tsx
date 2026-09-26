import { Button } from '../components/ui/button';
import { Music, Home, Search } from 'lucide-react';
import { Link, useLocation } from 'react-router';
import { usePageMeta } from '../components/PageMeta';

export default function NotFound() {
  const { pathname } = useLocation();
  usePageMeta('Page not found', 'This Verse page does not exist. Search music jobs, professionals and bookable acts instead.');
  return (
    <main className="min-h-screen bg-gradient-to-br from-purple-900 via-indigo-900 to-blue-900 flex items-center justify-center px-6">
      <div className="text-center">
        <Music aria-hidden="true" className="w-24 h-24 text-purple-300 mx-auto mb-8 motion-safe:animate-pulse" />
        <p className="text-7xl md:text-9xl font-bold text-white mb-4" aria-hidden="true">404</p>
        <h1 className="text-3xl font-bold text-white mb-4">Page not found</h1>
        <p className="text-purple-100 mb-8 max-w-md mx-auto break-words">
          <span className="font-mono text-sm">{pathname}</span> hit a wrong note. Let’s get you back on track.
        </p>
        <div className="flex flex-wrap justify-center gap-3">
          <Button className="bg-gradient-to-r from-purple-500 to-pink-500 hover:from-purple-600 hover:to-pink-600" asChild>
            <Link to="/"><Home className="w-4 h-4 mr-2" />Back to home</Link>
          </Button>
          <Button variant="outline" className="border-white/30 bg-white/10 text-white" asChild>
            <Link to="/search"><Search className="w-4 h-4 mr-2" />Search Verse</Link>
          </Button>
          <Button variant="ghost" className="text-purple-100" asChild>
            <Link to="/sitemap">Site map</Link>
          </Button>
        </div>
      </div>
    </main>
  );
}
