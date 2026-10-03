import React, { createContext, startTransition, useContext, useEffect, useMemo, useRef, useState } from 'react';
import {
  ApiError,
  apiGet,
  apiPost,
  hasAccessToken,
  onAccessTokenChange,
  rememberSessionRole,
  setAccessToken,
} from './api';

/**
 * A full-page "Continue with Google" round trip lands back on whatever page the backend
 * chose (see GoogleAuthController), not necessarily AuthPage. The redirect carries only a
 * one-time, 60-second `code` (never a session token, which would leak via history, Referer
 * and request logs); it is stripped from the URL at once, then traded for the real session
 * over POST /api/auth/exchange. Runs once here, for every route.
 */
async function consumeGoogleRedirectCode(): Promise<void> {
  let code: string | null = null;
  try {
    const url = new URL(window.location.href);
    if (url.searchParams.get('auth') !== 'google') return;
    code = url.searchParams.get('code');
    if (!code) return;
    url.searchParams.delete('code');
    url.searchParams.delete('auth');
    window.history.replaceState({}, '', `${url.pathname}${url.search}${url.hash}`);
  } catch {
    return;
  }
  try {
    const d = await apiPost<{ accessToken: string }>('/auth/exchange', { code });
    setAccessToken(d.accessToken);
    // Dynamically imported so this eagerly loaded module never pulls analytics into the entry chunk.
    void import('./analytics').then((m) => m.track('auth_google_success'));
  } catch {
    /* an invalid, reused or expired code: stay signed out; nothing else to recover */
  }
}
import type { StarterPayload } from './onboarding';
import { setRealtimeAvailable } from './realtimeAvailability';
export type Role = 'jobseeker' | 'employer' | 'admin';
export interface User {
  id: string;
  name: string;
  email: string;
  role: Role;
  status: string;
  profileComplete: boolean;
  headline?: string | null;
  location?: string | null;
  companyName?: string | null;
  verified?: boolean;
  skills?: string[];
  genres?: string[];
  /** The roles on the musician's profile ("Tabla Player", …). */
  roles?: string[];
  credits?: string[];
  openTo?: string[];
  /** The photo the person uploaded (or their Google picture); UserAvatar falls back to initials. */
  photoUrl?: string | null;
  /** False for an account that signs in with an emailed code or Google and has no password yet. */
  passwordSet?: boolean;
  phoneE164?: string | null;
  whatsappConsentedAt?: string | null;
  verificationPending?: boolean;
  verificationRequestedAt?: string | null;
}
/* Admin password sign-in answers with this instead of a session; the code emailed to the admin completes it. */
export interface SecondFactorChallenge {
  secondFactorRequired: true;
  method: 'email_code';
  challengeToken: string;
  message: string;
  expiresIn: number;
  debugCode?: string;
}
export const isSecondFactorChallenge = (value: unknown): value is SecondFactorChallenge => {
  const candidate = value as Partial<SecondFactorChallenge> | null | undefined;
  return Boolean(candidate && candidate.secondFactorRequired === true && typeof candidate.challengeToken === 'string');
};
export interface RegisterPayload extends StarterPayload {
  name: string;
  email: string;
  password: string;
  role: 'jobseeker' | 'employer';
  /** The sign-up's "I agree to the Terms and Privacy Policy" box; recorded as consented_at. */
  consent?: boolean;
}
/** Hydration status for the stored session: 'loading' until the boot-time /me call (or its
 * absence) resolves, then 'signedIn' or 'signedOut'. Header/nav components branch on this
 * instead of `loading`/`isAuthenticated` so they never flash the signed-out variant while a
 * stored token is still being verified. */
export type AuthStatus = 'loading' | 'signedIn' | 'signedOut';
interface AuthContextType {
  user: User | null;
  loading: boolean;
  status: AuthStatus;
  isAuthenticated: boolean;
  login: (email: string, password: string) => Promise<User | SecondFactorChallenge>;
  completeSecondFactor: (challengeToken: string, code: string) => Promise<User>;
  register: (p: RegisterPayload) => Promise<User>;
  verifyCode: (email: string, code: string) => Promise<User>;
  logout: () => Promise<void>;
  refresh: () => Promise<void>;
  setUser: (u: User | null) => void;
}
const AuthContext = createContext<AuthContextType | undefined>(undefined);
export const AuthProvider = ({ children }: { children: React.ReactNode }) => {
  const [user, setUser] = useState<User | null>(null),
    [loading, setLoading] = useState(true);
  /* Each session change bumps the generation so a slower, older /me response can never overwrite a newer sign-in or sign-out. */
  const generation = useRef(0);
  const refresh = async () => {
    const current = ++generation.current;
    /* The session answer re-renders the whole app. As a transition it waits for any pre-rendered page
       (src/entry-server.tsx) that is still hydrating instead of making React throw that HTML away
       (React error #421) and render the page again from scratch. */
    const settle = (next: User | null) =>
      startTransition(() => {
        setUser(next);
        setLoading(false);
      });
    if (!hasAccessToken()) {
      setRealtimeAvailable(false);
      settle(null);
      return;
    }
    try {
      const d = await apiGet<{ user: User; realtime?: boolean }>('/me');
      if (current === generation.current) {
        setRealtimeAvailable(d.realtime === true);
        settle(d.user);
      }
    } catch (e) {
      /* Only a rejected session (expired, revoked or inactive account) ends it; timeouts and outages keep the token so the user can retry. A 401 is cleared by api() itself, and only if no other tab has signed in since. */ if (
        current !== generation.current
      )
        return;
      if (e instanceof ApiError && e.status === 403) setAccessToken(null);
      settle(null);
    }
  };
  useEffect(() => {
    void consumeGoogleRedirectCode().then(() => refresh());
  }, []);
  /* An expired session on a role-less page (the Stage) signs in again as the same kind of account. The role (never the token) is remembered at sign-in, so a cold load whose token has already expired still knows it; only sign-out forgets it, not a failed or slow /me. */
  useEffect(() => {
    if (user) rememberSessionRole(user.role);
  }, [user]);
  /* Sign-in or sign-out in another tab updates this one; a cleared token drops to signed-out state and protected routes send the user to sign-in. */
  useEffect(
    () =>
      onAccessTokenChange((signedIn) => {
        if (signedIn) {
          void refresh();
          return;
        }
        generation.current += 1;
        rememberSessionRole(null);
        setUser(null);
        setLoading(false);
      }),
    [],
  );
  const login = async (email: string, password: string) => {
    const d = await apiPost<{ user: User; accessToken: string; realtime?: boolean } | SecondFactorChallenge>(
      '/auth/login',
      {
        email,
        password,
      },
    );
    if (isSecondFactorChallenge(d)) return d;
    generation.current += 1;
    setAccessToken(d.accessToken);
    rememberSessionRole(d.user.role);
    setRealtimeAvailable(d.realtime === true);
    setUser(d.user);
    setLoading(false);
    return d.user;
  };
  const register = async (payload: RegisterPayload) => {
    const d = await apiPost<{ user: User; accessToken: string; realtime?: boolean }>('/auth/register', payload);
    generation.current += 1;
    setAccessToken(d.accessToken);
    rememberSessionRole(d.user.role);
    setRealtimeAvailable(d.realtime === true);
    setUser(d.user);
    setLoading(false);
    return d.user;
  };
  /* Email sign-in code: same response as /auth/login; creates the account when the code was requested as a sign-up. */ const verifyCode =
    async (email: string, code: string) => {
      const d = await apiPost<{ user: User; accessToken: string; realtime?: boolean }>('/auth/otp/verify', {
        email,
        code,
      });
      generation.current += 1;
      setAccessToken(d.accessToken);
      rememberSessionRole(d.user.role);
      setRealtimeAvailable(d.realtime === true);
      setUser(d.user);
      setLoading(false);
      return d.user;
    };
  const completeSecondFactor = async (challengeToken: string, code: string) => {
    const d = await apiPost<{ user: User; accessToken: string; realtime?: boolean }>('/auth/second-factor', {
      challengeToken,
      code,
    });
    generation.current += 1;
    setAccessToken(d.accessToken);
    rememberSessionRole(d.user.role);
    setRealtimeAvailable(d.realtime === true);
    setUser(d.user);
    setLoading(false);
    return d.user;
  };
  const logout = async () => {
    try {
      await apiPost('/auth/logout');
    } finally {
      generation.current += 1;
      setAccessToken(null);
      rememberSessionRole(null);
      setRealtimeAvailable(false);
      setUser(null);
    }
  };
  return (
    <AuthContext.Provider
      value={useMemo(
        () => ({
          user,
          loading,
          status: (loading ? 'loading' : user ? 'signedIn' : 'signedOut') as AuthStatus,
          isAuthenticated: !!user,
          login,
          register,
          verifyCode,
          completeSecondFactor,
          logout,
          refresh,
          setUser,
        }),
        [user, loading],
      )}
    >
      {children}
    </AuthContext.Provider>
  );
};
export const useAuth = () => {
  const c = useContext(AuthContext);
  if (!c) throw new Error('useAuth must be used within AuthProvider');
  return c;
};
