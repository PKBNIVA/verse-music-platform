import { Link, useLocation, useNavigate } from 'react-router';
import { Briefcase, CalendarDays, ChevronDown, Compass, LogIn, Menu, Search, Users } from 'lucide-react';
import { Button } from './ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from './ui/dropdown-menu';
import { useState } from 'react';
import { BrandMark } from './BrandMark';

const links = [
  ['Music jobs', '/music-jobs', Briefcase],
  ['Professionals', '/music-professionals', Users],
  ['Book music', '/book-music', CalendarDays],
  ['How Verse works', '/guide', Compass]
] as const;

export function PublicNav() {
  const nav = useNavigate();
  const location = useLocation();
  const [q, setQ] = useState('');
  const go = (e: React.FormEvent) => { e.preventDefault(); if (q.trim()) nav(`/search?q=${encodeURIComponent(q.trim())}`); };
  const active = (to:string) => location.pathname === to || (to !== '/' && location.pathname.startsWith(`${to}/`));

  return <nav className="sticky top-0 z-50 border-b border-white/10 bg-[#070813]/88 backdrop-blur-2xl" aria-label="Public navigation">
    <div className="mx-auto flex h-[72px] max-w-7xl items-center gap-3 px-4 md:px-6">
      <Link to="/" aria-label="Verse home" className="shrink-0"><BrandMark /></Link>
      <form onSubmit={go} className="relative ml-3 hidden max-w-xs flex-1 lg:block" role="search">
        <label htmlFor="public-search" className="sr-only">Search jobs, people and acts</label>
        <Search size={16} className="absolute left-3.5 top-3 text-slate-400" />
        <input id="public-search" value={q} onChange={e => setQ(e.target.value)} placeholder="Search the music network" className="h-10 w-full rounded-xl border border-white/15 bg-white/[.055] pl-10 pr-3 text-sm outline-none focus:border-violet-300/60 focus:bg-white/[.08]" />
      </form>
      <div className="ml-auto hidden items-center gap-1 xl:flex">
        {links.map(([label,to,Icon]) => <Button key={to} variant="ghost" size="sm" asChild className={active(to)?'bg-white/10 text-white':'text-slate-300'}><Link to={to}><Icon size={15} className="mr-2" />{label}</Link></Button>)}
      </div>
      <DropdownMenu><DropdownMenuTrigger asChild><Button variant="ghost" size="icon" className="ml-auto xl:hidden" aria-label="Open navigation"><Menu size={20} /></Button></DropdownMenuTrigger><DropdownMenuContent align="end" className="w-60">{links.map(([label,to,Icon]) => <DropdownMenuItem key={to} asChild><Link to={to}><Icon size={16} className="mr-2" />{label}</Link></DropdownMenuItem>)}<DropdownMenuItem asChild><Link to="/search"><Search size={16} className="mr-2" />Search everything</Link></DropdownMenuItem></DropdownMenuContent></DropdownMenu>
      <DropdownMenu><DropdownMenuTrigger asChild><Button variant="ghost" size="sm" className="hidden sm:flex"><LogIn size={15} className="mr-2" />Sign in<ChevronDown size={14} className="ml-1" /></Button></DropdownMenuTrigger><DropdownMenuContent align="end"><DropdownMenuItem asChild><Link to="/auth/jobseeker"><Users size={15} className="mr-2" />Professional account</Link></DropdownMenuItem><DropdownMenuItem asChild><Link to="/auth/employer"><Briefcase size={15} className="mr-2" />Employer account</Link></DropdownMenuItem><DropdownMenuSeparator/><DropdownMenuItem asChild><Link to="/auth/admin">Operations</Link></DropdownMenuItem></DropdownMenuContent></DropdownMenu>
      <Button size="sm" asChild className="border-0 bg-gradient-to-r from-fuchsia-500 to-violet-500"><Link to="/start">Join Verse</Link></Button>
    </div>
  </nav>;
}
