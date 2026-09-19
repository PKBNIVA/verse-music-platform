import { Link, useLocation, useNavigate } from 'react-router';
import { Bell, BookOpen, Briefcase, Building2, CalendarDays, ChevronDown, Clock3, FileText, Home, LogOut, Menu, MessageSquare, Music, Search, Star, User, UserRoundPlus, Users, WalletCards, Zap } from 'lucide-react';
import { Button } from './ui/button';
import { useAuth } from '../lib/authContext';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from './ui/dropdown-menu';
import { Avatar, AvatarFallback } from './ui/avatar';
import { useEffect, useState } from 'react';
import { apiGet } from '../lib/api';
import { ProductTour, TourLauncher } from './ProductTour';
import { BrandMark } from './BrandMark';

type NavItem = { path:string; icon:any; label:string };
type NavGroup = { label:string; items:NavItem[] };

export function Navigation() {
  const { user, logout } = useAuth();
  const location = useLocation();
  const navigate = useNavigate();
  const isJobSeeker = user?.role === 'jobseeker';
  const baseUrl = isJobSeeker ? '/jobseeker' : '/employer';
  const [unread, setUnread] = useState(0);
  useEffect(() => { apiGet<any>('/notifications').then(d => setUnread(d.unread || 0)).catch(() => {}); }, [location.pathname]);

  const groups:NavGroup[] = isJobSeeker ? [
    { label:'Career', items:[{path:`${baseUrl}/jobs`,icon:Search,label:'Explore work'},{path:`${baseUrl}/saved`,icon:Star,label:'Saved'},{path:`${baseUrl}/applications`,icon:Briefcase,label:'Applications'},{path:`${baseUrl}/portfolio`,icon:FileText,label:'Portfolio'},{path:`${baseUrl}/availability`,icon:Clock3,label:'Availability'},{path:`${baseUrl}/resources`,icon:BookOpen,label:'Resources'}] },
    { label:'Perform & book', items:[{path:`${baseUrl}/acts`,icon:Music,label:'My acts'},{path:`${baseUrl}/book-talent`,icon:Search,label:'Book talent'},{path:`${baseUrl}/bookings`,icon:CalendarDays,label:'Bookings'},{path:`${baseUrl}/band-builder`,icon:UserRoundPlus,label:'Band builder'},{path:`${baseUrl}/urgent`,icon:Zap,label:'Urgent replacement'}] },
    { label:'Hire', items:[{path:`${baseUrl}/hiring/post`,icon:Briefcase,label:'Post opportunity'},{path:`${baseUrl}/hiring/talent`,icon:Users,label:'Find talent'},{path:`${baseUrl}/hiring/applicants`,icon:FileText,label:'Applicants'},{path:`${baseUrl}/build-my-crew`,icon:Users,label:'Build my crew'}] }
  ] : [
    { label:'Hiring', items:[{path:`${baseUrl}/post-job`,icon:Briefcase,label:'Create opportunity'},{path:`${baseUrl}/candidates`,icon:Users,label:'Find talent'},{path:`${baseUrl}/applications`,icon:FileText,label:'Applicants'},{path:`${baseUrl}/build-my-crew`,icon:Users,label:'Build my crew'}] },
    { label:'Book & perform', items:[{path:`${baseUrl}/book-talent`,icon:Search,label:'Book talent'},{path:`${baseUrl}/bookings`,icon:CalendarDays,label:'Bookings'},{path:`${baseUrl}/acts`,icon:Music,label:'My acts'},{path:`${baseUrl}/band-builder`,icon:UserRoundPlus,label:'Band builder'},{path:`${baseUrl}/urgent`,icon:Zap,label:'Urgent replacement'},{path:`${baseUrl}/availability`,icon:Clock3,label:'Availability'}] }
  ];
  const active = (path:string) => location.pathname === path || (path !== baseUrl && location.pathname.startsWith(`${path}/`));
  const quick = isJobSeeker ? [
    {path:baseUrl,icon:Home,label:'Home'},
    {path:`${baseUrl}/jobs`,icon:Search,label:'Explore'},
    {path:`${baseUrl}/applications`,icon:Briefcase,label:'Activity'},
    {path:`${baseUrl}/messages`,icon:MessageSquare,label:'Inbox'}
  ] : [
    {path:baseUrl,icon:Home,label:'Home'},
    {path:`${baseUrl}/post-job`,icon:Briefcase,label:'Create'},
    {path:`${baseUrl}/candidates`,icon:Users,label:'Talent'},
    {path:`${baseUrl}/applications`,icon:FileText,label:'Pipeline'}
  ];
  const handleLogout = async () => { await logout(); navigate('/'); };

  return <>
    <ProductTour role={isJobSeeker ? 'jobseeker' : 'employer'} />
    <nav className="fixed top-0 z-50 w-full border-b border-white/10 bg-[#070813]/88 backdrop-blur-2xl" aria-label="Workspace navigation">
      <div className="mx-auto flex h-[72px] max-w-[1500px] items-center gap-4 px-4 md:px-6">
        <Link to={baseUrl} aria-label="Verse dashboard" className="shrink-0"><BrandMark /></Link>
        <div className="ml-5 hidden items-center gap-1 lg:flex">
          <Button variant="ghost" size="sm" asChild className={location.pathname===baseUrl?'bg-white/10 text-white':'text-slate-300'}><Link to={baseUrl}><Home size={16} className="mr-2" />Overview</Link></Button>
          {groups.map(group => <DropdownMenu key={group.label}><DropdownMenuTrigger asChild><Button variant="ghost" size="sm" className={group.items.some(x=>active(x.path))?'bg-white/10 text-white':'text-slate-300'}>{group.label}<ChevronDown size={14} className="ml-1.5" /></Button></DropdownMenuTrigger><DropdownMenuContent align="start" className="w-64"><DropdownMenuLabel className="text-xs uppercase tracking-wider text-muted-foreground">{group.label}</DropdownMenuLabel>{group.items.map(item => { const Icon=item.icon; return <DropdownMenuItem key={item.path} asChild className={active(item.path)?'bg-accent':''}><Link to={item.path} className="cursor-pointer"><Icon className="mr-2 h-4 w-4" />{item.label}</Link></DropdownMenuItem>; })}</DropdownMenuContent></DropdownMenu>)}
          <Button variant="ghost" size="sm" asChild className={active(`${baseUrl}/messages`)?'bg-white/10 text-white':'text-slate-300'}><Link to={`${baseUrl}/messages`}><MessageSquare size={16} className="mr-2" />Messages</Link></Button>
        </div>
        <div className="ml-auto flex items-center gap-1">
          <Link to={`${baseUrl}/notifications`}><Button variant="ghost" size="icon" className="relative text-slate-300 hover:text-white" aria-label={`${unread} unread notifications`}><Bell size={19} />{unread>0&&<span className="absolute right-0.5 top-0.5 grid h-4 min-w-4 place-items-center rounded-full bg-fuchsia-500 px-1 text-[9px] font-bold text-white">{unread>9?'9+':unread}</span>}</Button></Link>
          <DropdownMenu><DropdownMenuTrigger asChild><Button variant="ghost" className="h-11 gap-2 rounded-full px-1.5 pr-2 hover:bg-white/10" aria-label="Open account menu"><Avatar className="h-8 w-8"><AvatarFallback className="bg-gradient-to-br from-fuchsia-500 to-violet-600 text-xs font-bold text-white">{user?.name?.charAt(0)||'U'}</AvatarFallback></Avatar><span className="hidden max-w-28 truncate text-sm text-white sm:block">{user?.name?.split(' ')[0]}</span><ChevronDown size={14} className="hidden text-slate-400 sm:block" /></Button></DropdownMenuTrigger><DropdownMenuContent align="end" className="w-72"><div className="px-2 py-2"><p className="text-sm font-semibold">{user?.name}</p><p className="text-xs text-muted-foreground">{user?.email}</p></div><DropdownMenuSeparator/><DropdownMenuItem asChild><Link to={`${baseUrl}/profile`}><User className="mr-2 h-4 w-4" />Profile & verification</Link></DropdownMenuItem>{isJobSeeker&&<DropdownMenuItem asChild><Link to={`${baseUrl}/reviews`}><Star className="mr-2 h-4 w-4" />Employer reviews</Link></DropdownMenuItem>}<DropdownMenuItem asChild><Link to={`${baseUrl}/billing`}><WalletCards className="mr-2 h-4 w-4" />Plan & billing</Link></DropdownMenuItem><DropdownMenuItem asChild><Link to={`${baseUrl}/workspace`}><Building2 className="mr-2 h-4 w-4" />Workspace & seats</Link></DropdownMenuItem><DropdownMenuSeparator/><div className="px-2 py-2"><TourLauncher role={isJobSeeker?'jobseeker':'employer'} /><Link to="/guide" className="mt-2 flex items-center gap-2 text-sm text-slate-400 hover:text-white"><BookOpen size={15} />How to use Verse</Link></div><DropdownMenuSeparator/><DropdownMenuItem onClick={handleLogout} className="cursor-pointer text-rose-500"><LogOut className="mr-2 h-4 w-4" />Sign out</DropdownMenuItem></DropdownMenuContent></DropdownMenu>
          <DropdownMenu><DropdownMenuTrigger asChild><Button variant="ghost" size="icon" className="lg:hidden" aria-label="Open all workspace tools"><Menu size={20}/></Button></DropdownMenuTrigger><DropdownMenuContent align="end" className="max-h-[72vh] w-72 overflow-y-auto">{groups.map(group => <div key={group.label}><DropdownMenuLabel className="text-[10px] uppercase tracking-widest">{group.label}</DropdownMenuLabel>{group.items.map(item=>{const Icon=item.icon;return <DropdownMenuItem key={item.path} asChild><Link to={item.path}><Icon className="mr-2 h-4 w-4"/>{item.label}</Link></DropdownMenuItem>})}<DropdownMenuSeparator/></div>)}</DropdownMenuContent></DropdownMenu>
        </div>
      </div>
    </nav>
    <nav className="fixed inset-x-3 bottom-3 z-50 grid grid-cols-4 rounded-2xl border border-white/15 bg-[#101221]/94 p-1.5 shadow-2xl backdrop-blur-2xl lg:hidden" aria-label="Quick navigation">{quick.map(item=>{const Icon=item.icon;return <Link key={item.path} to={item.path} className={`flex min-h-12 flex-col items-center justify-center gap-1 rounded-xl text-[10px] font-semibold ${active(item.path)||location.pathname===item.path?'bg-violet-500/20 text-violet-200':'text-slate-400'}`}><Icon size={18}/>{item.label}</Link>})}</nav>
  </>;
}
