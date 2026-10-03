import { Link, useLocation, useNavigate } from 'react-router';
import {
  Bell,
  BookOpen,
  HelpCircle,
  Briefcase,
  Building2,
  CalendarDays,
  ChevronDown,
  Clock3,
  FileText,
  Home,
  LogOut,
  Menu,
  MessageSquare,
  Radio,
  Music,
  Search,
  Settings,
  ShieldCheck,
  Star,
  User,
  UserRoundPlus,
  Users,
  WalletCards,
  Zap,
  Mic2,
  UserSearch,
  BriefcaseBusiness,
  Library,
  Layers,
  ScrollText,
  Inbox,
  Flag,
} from 'lucide-react';
import { Button } from './ui/button';
import { useAuth } from '../lib/authContext';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from './ui/dropdown-menu';
import { UserAvatar } from './kit/UserAvatar';
import { useEffect, useState } from 'react';
import { toast } from 'sonner';
import { SIGN_IN_CODE_TOAST } from '../lib/authToasts';
import { apiGet } from '../lib/api';
import { UNREAD_CHANGED_EVENT, useVisiblePolling } from '../lib/usePolling';
import { useRealtime, useRealtimeInterval } from '../lib/realtime';
import { ProductTour } from './ProductTour';
import { openProblemReport } from '../lib/problemReportEvent';
import { watchClientErrors } from '../lib/recentErrors';
import { BrandMark } from './BrandMark';
import { SkipLink } from './SkipLink';
import type { UnreadCounts } from '../lib/apiTypes';
import type { LucideIcon } from 'lucide-react';
import { ActingAsChip, IdentitySwitcher } from './showcase/IdentitySwitcher';
import { FEATURE_RESUMES, FEATURE_STAGE } from '../lib/features';
import { usePendingSuggestions } from './showcase/usePendingSuggestions';

const UNREAD_POLL_MS = 10_000;

type NavItem = { path: string; icon: LucideIcon; label: string };
type NavGroup = { label: string; icon: LucideIcon; items: NavItem[] };

export function Navigation() {
  const { user, logout } = useAuth();
  const location = useLocation();
  const navigate = useNavigate();
  const isJobSeeker = user?.role === 'jobseeker';
  const baseUrl = isJobSeeker ? '/jobseeker' : '/employer';
  const [unread, setUnread] = useState(0);
  const [tourOpen, setTourOpen] = useState(false);
  // The "check your email" toast is stale once the person is in and moving between pages (J-26).
  // Keep the last few error messages in memory for "Report a problem".
  useEffect(watchClientErrors, []);
  useEffect(() => {
    toast.dismiss(SIGN_IN_CODE_TOAST);
  }, [location.pathname]);
  const [unreadMessages, setUnreadMessages] = useState(0);
  // Unread badges: fetched on mount and on route change, refreshed at once on a live update (a new
  // notification or message) or when a page reports that the viewer read something, and polled
  // while the tab is visible: every 10 s, or every 30 s while the live connection is up.
  const refreshUnread = () =>
    apiGet<UnreadCounts>('/notifications/unread')
      .then((d) => {
        setUnread(Number(d.unread) || 0);
        setUnreadMessages(Number(d.unreadMessages) || 0);
      })
      .catch(() => {});
  useEffect(() => {
    void refreshUnread();
  }, [location.pathname]);
  useEffect(() => {
    const onChange = () => {
      void refreshUnread();
    };
    window.addEventListener(UNREAD_CHANGED_EVENT, onChange);
    return () => window.removeEventListener(UNREAD_CHANGED_EVENT, onChange);
  }, []);
  useRealtime('UserChannel', user ? {} : null, () => void refreshUnread());
  useVisiblePolling(refreshUnread, useRealtimeInterval(UNREAD_POLL_MS), Boolean(user));
  const messageBadge = (className: string) =>
    unreadMessages > 0 ? (
      <span
        data-testid="unread-messages-badge"
        className={`grid h-4 min-w-4 place-items-center rounded-full bg-fuchsia-700 px-1 text-xs font-bold text-white ${className}`}
        aria-hidden="true"
      >
        {unreadMessages > 9 ? '9+' : unreadMessages}
      </span>
    ) : null;
  const pendingReview = usePendingSuggestions(Boolean(user));
  const messagesLabel = unreadMessages > 0 ? `Messages, ${unreadMessages} unread` : 'Messages';

  const myWork: NavGroup = {
    label: 'My work',
    icon: Library,
    items: [
      { path: `${baseUrl}/library`, icon: Library, label: 'My work' },
      { path: `${baseUrl}/portfolios`, icon: Layers, label: 'Portfolios' },
      { path: `${baseUrl}/applications`, icon: Briefcase, label: 'Applications' },
      { path: `${baseUrl}/saved`, icon: Star, label: 'Saved' },
      { path: `${baseUrl}/availability`, icon: Clock3, label: 'Availability' },
      { path: `${baseUrl}/bookings`, icon: CalendarDays, label: 'Bookings' },
      { path: `${baseUrl}/resources`, icon: BookOpen, label: 'Resources' },
      ...(FEATURE_RESUMES ? [{ path: `${baseUrl}/resumes`, icon: ScrollText, label: 'Career record & resumes' }] : []),
    ],
  };
  // Musicians can hire and book too, but those tools live in the account menu, not the top bar.
  const hireSomeone: NavGroup = {
    label: 'Hire someone',
    icon: UserSearch,
    items: [
      { path: `${baseUrl}/hiring/post`, icon: Briefcase, label: 'Post an opportunity' },
      { path: `${baseUrl}/hiring/talent`, icon: Users, label: 'Find talent' },
      { path: `${baseUrl}/hiring/applicants`, icon: FileText, label: 'Applicants' },
      { path: `${baseUrl}/build-my-crew`, icon: Users, label: 'Build my crew' },
    ],
  };
  const performAndBook: NavGroup = {
    label: 'Perform & book',
    icon: Mic2,
    items: [
      { path: `${baseUrl}/acts`, icon: Music, label: 'My acts' },
      { path: `${baseUrl}/book-talent`, icon: Search, label: 'Book talent' },
      { path: `${baseUrl}/bookings`, icon: CalendarDays, label: 'Bookings' },
      { path: `${baseUrl}/band-builder`, icon: UserRoundPlus, label: 'Band builder' },
      { path: `${baseUrl}/urgent`, icon: Zap, label: 'Urgent replacement' },
    ],
  };
  const employerGroups: NavGroup[] = [
    {
      label: 'Post & hire',
      icon: BriefcaseBusiness,
      items: [
        { path: `${baseUrl}/post-job`, icon: Briefcase, label: 'Post an opportunity' },
        { path: `${baseUrl}/candidates`, icon: Users, label: 'Find talent' },
        { path: `${baseUrl}/applications`, icon: FileText, label: 'Applicants' },
        { path: `${baseUrl}/build-my-crew`, icon: Users, label: 'Build my crew' },
      ],
    },
    // Hirers book musicians; performing tools (acts, availability) belong to the musician workspace (J-16).
    {
      label: 'Book talent',
      icon: Mic2,
      items: [
        { path: `${baseUrl}/book-talent`, icon: Search, label: 'Book talent' },
        { path: `${baseUrl}/bookings`, icon: CalendarDays, label: 'Bookings' },
        { path: `${baseUrl}/band-builder`, icon: UserRoundPlus, label: 'Band builder' },
        { path: `${baseUrl}/urgent`, icon: Zap, label: 'Urgent replacement' },
      ],
    },
  ];
  // Top-bar dropdowns, the full mobile menu, and the extra groups in the account menu.
  const groups: NavGroup[] = isJobSeeker ? [myWork] : employerGroups;
  const menuGroups: NavGroup[] = isJobSeeker ? [myWork, performAndBook, hireSomeone] : employerGroups;
  // The musician's account menu: four short groups, twelve items in all. (The hirer-only tools
  // such as seats and the applicant list stay on the full menu / the hirer workspace.)
  const accountGroups: NavGroup[] = isJobSeeker
    ? [
        {
          label: 'You',
          icon: User,
          items: [
            { path: `${baseUrl}/profile`, icon: User, label: 'Profile & verification' },
            { path: `${baseUrl}/review`, icon: Inbox, label: 'Review changes' },
            { path: `${baseUrl}/reviews`, icon: Star, label: 'Hirer reviews' },
          ],
        },
        {
          label: 'Perform & book',
          icon: Mic2,
          items: performAndBook.items.filter(
            (item) => !item.path.endsWith('/book-talent') && !item.path.endsWith('/bookings'),
          ),
        },
        {
          label: 'Hire someone',
          icon: UserSearch,
          items: [
            hireSomeone.items[0],
            hireSomeone.items[1],
            { path: `${baseUrl}/book-talent`, icon: Search, label: 'Book talent' },
          ],
        },
        {
          label: 'Settings',
          icon: Settings,
          items: [
            { path: `${baseUrl}/settings`, icon: Settings, label: 'Account settings' },
            { path: `${baseUrl}/billing`, icon: WalletCards, label: 'Plan & billing' },
            { path: `${baseUrl}/account`, icon: ShieldCheck, label: 'Your data & account' },
          ],
        },
      ]
    : [];
  // Warm the Messages chunk before the click so the page does not paint empty.
  const preloadMessages = () => {
    void import('../pages/Messages').catch(() => undefined);
  };
  const active = (path: string) =>
    location.pathname === path || (path !== baseUrl && location.pathname.startsWith(`${path}/`));
  const quick = isJobSeeker
    ? [
        { path: baseUrl, icon: Home, label: 'Home' },
        { path: `${baseUrl}/jobs`, icon: Search, label: 'Explore' },
        { path: `${baseUrl}/applications`, icon: Briefcase, label: 'Activity' },
        { path: `${baseUrl}/messages`, icon: MessageSquare, label: 'Inbox' },
      ]
    : [
        { path: baseUrl, icon: Home, label: 'Home' },
        { path: `${baseUrl}/post-job`, icon: Briefcase, label: 'Post' },
        { path: `${baseUrl}/candidates`, icon: Users, label: 'Talent' },
        { path: `${baseUrl}/messages`, icon: MessageSquare, label: 'Inbox' },
      ];
  const handleLogout = async () => {
    navigate('/', { replace: true });
    await logout();
  };

  return (
    <>
      <nav
        className="fixed top-0 z-50 w-full border-b border-white/10 bg-[#070813]/88 backdrop-blur-2xl"
        aria-label="Workspace navigation"
      >
        <SkipLink />
        <div className="mx-auto flex h-[72px] max-w-[1500px] items-center gap-2 px-4 sm:gap-4 md:px-6">
          <Link to={baseUrl} aria-label="MusiLynk dashboard" className="inline-flex min-h-11 shrink-0 items-center">
            {/* The tagline costs ~70px; below sm the header must also fit the identity switcher, bell,
                account menu and the menu button inside 360px. */}
            <span className="sm:hidden">
              <BrandMark compact />
            </span>
            <span className="hidden sm:inline">
              <BrandMark />
            </span>
          </Link>
          <div className="ml-5 hidden items-center gap-1 lg:flex">
            <Button
              variant="ghost"
              size="sm"
              asChild
              className={location.pathname === baseUrl ? 'bg-white/10 text-white' : 'text-slate-300'}
            >
              <Link to={baseUrl}>
                <Home size={16} className="mr-2" />
                Overview
              </Link>
            </Button>
            {isJobSeeker && (
              <Button
                variant="ghost"
                size="sm"
                asChild
                className={active(`${baseUrl}/jobs`) ? 'bg-white/10 text-white' : 'text-slate-300'}
              >
                <Link to={`${baseUrl}/jobs`}>
                  <Search size={16} className="mr-2" aria-hidden="true" />
                  Find work
                </Link>
              </Button>
            )}
            {FEATURE_STAGE && (
              <Button
                variant="ghost"
                size="sm"
                asChild
                className={location.pathname.startsWith('/stage') ? 'bg-white/10 text-white' : 'text-slate-300'}
              >
                <Link to="/stage">
                  <Radio size={16} className="mr-2" aria-hidden="true" />
                  Stage
                </Link>
              </Button>
            )}
            {groups.map((group) => (
              <DropdownMenu key={group.label}>
                <DropdownMenuTrigger asChild>
                  <Button
                    variant="ghost"
                    size="sm"
                    className={group.items.some((x) => active(x.path)) ? 'bg-white/10 text-white' : 'text-slate-300'}
                  >
                    <group.icon size={16} className="mr-2" aria-hidden="true" />
                    {group.label}
                    <ChevronDown size={14} className="ml-1.5" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="start" className="w-64">
                  <DropdownMenuLabel className="text-xs uppercase tracking-wider text-muted-foreground">
                    {group.label}
                  </DropdownMenuLabel>
                  {group.items.map((item) => {
                    const Icon = item.icon;
                    return (
                      <DropdownMenuItem key={item.path} asChild className={active(item.path) ? 'bg-accent' : ''}>
                        <Link to={item.path} className="cursor-pointer">
                          <Icon className="mr-2 h-4 w-4" />
                          {item.label}
                        </Link>
                      </DropdownMenuItem>
                    );
                  })}
                </DropdownMenuContent>
              </DropdownMenu>
            ))}
            <Button
              variant="ghost"
              size="sm"
              asChild
              className={active(`${baseUrl}/messages`) ? 'bg-white/10 text-white' : 'text-slate-300'}
            >
              <Link
                to={`${baseUrl}/messages`}
                aria-label={messagesLabel}
                onMouseEnter={preloadMessages}
                onFocus={preloadMessages}
              >
                <MessageSquare size={16} className="mr-2" />
                Messages{messageBadge('ml-1.5')}
              </Link>
            </Button>
          </div>
          <div className="ml-auto flex items-center gap-1">
            <IdentitySwitcher />
            <Button variant="ghost" size="icon" asChild className="relative text-slate-300 hover:text-white">
              <Link
                to={`${baseUrl}/notifications`}
                aria-label={unread > 0 ? `Notifications, ${unread} unread` : 'Notifications'}
              >
                <Bell size={19} aria-hidden="true" />
                {unread > 0 && (
                  <span
                    data-testid="unread-notifications-badge"
                    aria-hidden="true"
                    className="absolute right-0.5 top-0.5 grid h-4 min-w-4 place-items-center rounded-full bg-fuchsia-700 px-1 text-xs font-bold text-white"
                  >
                    {unread > 9 ? '9+' : unread}
                  </span>
                )}
              </Link>
            </Button>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="ghost"
                  className="relative h-11 gap-2 rounded-full px-1.5 pr-2 hover:bg-white/10"
                  aria-label={
                    pendingReview > 0 ? `Open account menu, ${pendingReview} changes to review` : 'Open account menu'
                  }
                >
                  <UserAvatar
                    id={user?.id || 'me'}
                    name={user?.name || 'Account'}
                    size="sm"
                    photoUrl={user?.photoUrl}
                    eager
                  />
                  <span className="hidden max-w-28 truncate text-sm text-white sm:block">
                    {user?.name?.split(' ')[0]}
                  </span>
                  <ChevronDown size={14} className="hidden text-slate-400 sm:block" />
                  {pendingReview > 0 && (
                    <span
                      aria-hidden="true"
                      data-testid="review-badge"
                      className="absolute -right-0.5 top-0.5 grid h-4 min-w-4 place-items-center rounded-full bg-teal-600 px-1 text-xs font-bold text-white"
                    >
                      {pendingReview > 9 ? '9+' : pendingReview}
                    </span>
                  )}
                </Button>
              </DropdownMenuTrigger>
              {/* The items scroll; Sign out sits below them, never on top of them, so every item can be reached on a phone. */}
              <DropdownMenuContent align="end" className="flex max-h-[80vh] w-72 flex-col overflow-hidden">
                <div
                  className="min-h-0 flex-1 overflow-y-auto"
                  data-testid="account-menu-items"
                  role="group"
                  aria-label="Account"
                  tabIndex={0}
                >
                  <div className="px-2 py-2" role="group" aria-label="Signed in as">
                    <p className="text-sm font-semibold">{user?.name}</p>
                    <p className="text-xs text-muted-foreground">{user?.email}</p>
                  </div>
                  <DropdownMenuSeparator />
                  {accountGroups.map((group) => (
                    <DropdownMenuGroup key={group.label}>
                      <DropdownMenuLabel className="text-xs uppercase tracking-widest text-muted-foreground">
                        {group.label}
                      </DropdownMenuLabel>
                      {group.items.map((item) => {
                        const Icon = item.icon;
                        const isReview = item.path === `${baseUrl}/review`;
                        return (
                          <DropdownMenuItem key={item.path} asChild className={active(item.path) ? 'bg-accent' : ''}>
                            <Link to={item.path} data-testid={isReview ? 'review-menu-item' : undefined}>
                              <Icon className="mr-2 h-4 w-4" />
                              {item.label}
                              {isReview && pendingReview > 0 && (
                                <span className="ml-auto rounded-full bg-teal-600 px-1.5 text-xs font-bold text-white">
                                  {pendingReview}
                                  <span className="sr-only"> to review</span>
                                </span>
                              )}
                            </Link>
                          </DropdownMenuItem>
                        );
                      })}
                      <DropdownMenuSeparator />
                    </DropdownMenuGroup>
                  ))}
                  {!isJobSeeker && (
                    <>
                      <DropdownMenuItem asChild>
                        <Link to={`${baseUrl}/profile`}>
                          <User className="mr-2 h-4 w-4" />
                          Profile & verification
                        </Link>
                      </DropdownMenuItem>
                      <DropdownMenuItem asChild>
                        <Link to={`${baseUrl}/review`} data-testid="review-menu-item">
                          <Inbox className="mr-2 h-4 w-4" />
                          Review changes
                          {pendingReview > 0 && (
                            <span className="ml-auto rounded-full bg-teal-600 px-1.5 text-xs font-bold text-white">
                              {pendingReview}
                              <span className="sr-only"> to review</span>
                            </span>
                          )}
                        </Link>
                      </DropdownMenuItem>
                      <DropdownMenuItem asChild>
                        <Link to={`${baseUrl}/settings`}>
                          <Settings className="mr-2 h-4 w-4" />
                          Account settings
                        </Link>
                      </DropdownMenuItem>
                      <DropdownMenuItem asChild>
                        <Link to={`${baseUrl}/billing`}>
                          <WalletCards className="mr-2 h-4 w-4" />
                          Plan & billing
                        </Link>
                      </DropdownMenuItem>
                      <DropdownMenuItem asChild>
                        <Link to={`${baseUrl}/workspace`}>
                          <Building2 className="mr-2 h-4 w-4" />
                          Workspace & seats
                        </Link>
                      </DropdownMenuItem>
                      <DropdownMenuItem asChild>
                        <Link to={`${baseUrl}/account`}>
                          <ShieldCheck className="mr-2 h-4 w-4" />
                          Your data & account
                        </Link>
                      </DropdownMenuItem>
                      <DropdownMenuSeparator />
                    </>
                  )}
                  <DropdownMenuLabel className="text-xs uppercase tracking-widest text-muted-foreground">
                    Help
                  </DropdownMenuLabel>
                  <DropdownMenuItem onSelect={() => setTourOpen(true)} className="cursor-pointer">
                    <HelpCircle className="mr-2 h-4 w-4" />
                    Take product tour
                  </DropdownMenuItem>
                  <DropdownMenuItem asChild>
                    <Link to="/guide">
                      <BookOpen className="mr-2 h-4 w-4" />
                      How to use MusiLynk
                    </Link>
                  </DropdownMenuItem>
                  <DropdownMenuItem onSelect={() => openProblemReport({ role: user?.role })} className="cursor-pointer">
                    <Flag className="mr-2 h-4 w-4" />
                    Report a problem
                  </DropdownMenuItem>
                </div>
                <div className="shrink-0">
                  <DropdownMenuSeparator />
                  <DropdownMenuItem onClick={handleLogout} className="cursor-pointer text-rose-500">
                    <LogOut className="mr-2 h-4 w-4" />
                    Sign out
                  </DropdownMenuItem>
                </div>
              </DropdownMenuContent>
            </DropdownMenu>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" size="icon" className="lg:hidden" aria-label="Open all workspace tools">
                  <Menu size={20} />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" tabIndex={0} className="max-h-[72vh] w-72 overflow-y-auto">
                {menuGroups.map((group) => (
                  <DropdownMenuGroup key={group.label}>
                    <DropdownMenuLabel className="text-xs uppercase tracking-widest">{group.label}</DropdownMenuLabel>
                    {group.items.map((item) => {
                      const Icon = item.icon;
                      return (
                        <DropdownMenuItem key={item.path} asChild>
                          <Link to={item.path}>
                            <Icon className="mr-2 h-4 w-4" />
                            {item.label}
                          </Link>
                        </DropdownMenuItem>
                      );
                    })}
                    <DropdownMenuSeparator />
                  </DropdownMenuGroup>
                ))}
                {FEATURE_STAGE && (
                  <DropdownMenuItem asChild>
                    <Link to="/stage">
                      <Radio className="mr-2 h-4 w-4" />
                      Stage
                    </Link>
                  </DropdownMenuItem>
                )}
                <DropdownMenuItem asChild>
                  <Link to={`${baseUrl}/messages`}>
                    <MessageSquare className="mr-2 h-4 w-4" />
                    Messages
                  </Link>
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      </nav>
      {tourOpen && (
        <ProductTour role={isJobSeeker ? 'jobseeker' : 'employer'} forceOpen onClose={() => setTourOpen(false)} />
      )}
      <ActingAsChip />
      <nav
        className="fixed inset-x-3 bottom-3 z-50 grid grid-cols-4 rounded-2xl border border-white/15 bg-[#101221]/94 p-1.5 shadow-2xl backdrop-blur-2xl lg:hidden"
        aria-label="Quick navigation"
      >
        {quick.map((item) => {
          const Icon = item.icon;
          return (
            <Link
              key={item.path}
              to={item.path}
              aria-label={
                item.path === `${baseUrl}/messages` && unreadMessages > 0
                  ? `${item.label}, ${unreadMessages} unread`
                  : undefined
              }
              className={`relative flex min-h-12 flex-col items-center justify-center gap-1 rounded-xl text-xs font-semibold ${active(item.path) || location.pathname === item.path ? 'bg-violet-500/20 text-violet-200' : 'text-slate-400'}`}
            >
              <Icon size={18} />
              {item.label}
              {item.path === `${baseUrl}/messages` && messageBadge('absolute right-[22%] top-1')}
            </Link>
          );
        })}
      </nav>
    </>
  );
}
