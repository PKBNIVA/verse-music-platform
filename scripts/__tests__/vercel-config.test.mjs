import { afterAll, describe, expect, it } from 'vitest';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { adminRoutePaths, readSeoPages } from '../prerender-heads.mjs';

// vercel.json is the production router: a wrong rewrite 404s real pages, and a missing one lets unknown
// URLs return 200 (a soft 404). These tests pin the contract without needing a deployment.
const root = process.cwd();
const config = JSON.parse(readFileSync(resolve(root, 'vercel.json'), 'utf8'));

/** The SPA rewrites (no `has` condition), compiled the way Vercel's path-to-regexp does for these shapes. */
const spaRules = config.rewrites
  .filter((rule) => !rule.has && /^\/(index|app-shell|[a-z]+\/shell)\.html$/.test(rule.destination))
  .map((rule) => new RegExp(`^${rule.source}$`));
const servedAsApp = (path) => spaRules.some((re) => re.test(path));

describe('vercel.json SPA rewrites', () => {
  it('serve the app for every route the public build declares', () => {
    const source = readFileSync(resolve(root, 'src/app/routes.tsx'), 'utf8');
    // Public build only: stop before the separate admin site's route table.
    const publicBlock = source.slice(0, source.indexOf('// The separate admin site'));
    const paths = new Set();
    for (const match of publicBlock.matchAll(/(?:path:\s*|\[\s*)'(\/[^']*)'/g)) paths.add(match[1]);
    expect(paths.size).toBeGreaterThan(30);
    const missing = [...paths]
      .map((path) => path.replace(/:[a-zA-Z]+/g, 'sample'))
      // hire and rates are listed role by role and city by city, so use real slugs.
      .map((path) =>
        path.replace(/^\/hire\/sample\/sample$/, '/hire/drummer/mumbai').replace(/^\/rates\/sample$/, '/rates/mumbai'),
      )
      .filter((path) => !servedAsApp(path));
    expect(missing).toEqual([]);
  });

  it('return a real 404 for unknown URLs, missing assets and unknown role or city combinations', () => {
    for (const path of [
      '/nonexistent',
      '/admin',
      '/assets/missing.js',
      '/hire/violin/mumbai',
      '/hire/drummer/atlantis',
      '/hire/drummer',
      '/rates/nowhere',
      '/index.htm',
    ])
      expect(servedAsApp(path), path).toBe(false);
  });

  it('serve the app for the home page and for deep links into record pages', () => {
    for (const path of [
      '/',
      '/pricing',
      '/professionals/user_1',
      '/opportunities/job_1',
      '/acts/act_1',
      '/p/some-slug',
      '/jobseeker/profile',
      '/stage/posts/1',
    ])
      expect(servedAsApp(path), path).toBe(true);
  });

  it('list exactly the roles and cities in backend/config/seo_pages.yml', () => {
    const { roles, cities } = readSeoPages(readFileSync(resolve(root, 'backend/config/seo_pages.yml'), 'utf8'));
    for (const [role] of roles)
      for (const [city] of cities) expect(servedAsApp(`/hire/${role}/${city}`), `${role}/${city}`).toBe(true);
    for (const [city] of cities) expect(servedAsApp(`/rates/${city}`), city).toBe(true);
    const hireRule = config.rewrites.find((rule) => rule.source.startsWith('/hire/'));
    const listed = hireRule.source.match(/^\/hire\/\(([^)]*)\)\/\(([^)]*)\)$/);
    expect(listed[1].split('|')).toEqual(roles.map(([slug]) => slug));
    expect(listed[2].split('|')).toEqual(cities.map(([slug]) => slug));
  });
});

describe('vercel.json edge-cached API rewrites', () => {
  // The landing page's three anonymous reads go through same-origin paths that Vercel proxies to the
  // API and caches per s-maxage (docs/ops/edge-caching.md). Nothing else under /api may be proxied:
  // a signed-in endpoint on the edge would be a mistake even though Vercel skips caching with a token.
  const API_HOST = 'https://musilynk-api-production.up.railway.app';
  const EDGE_READS = ['/api/public/stats', '/api/public/talent', '/api/stage/authors/system/:id/posts'];
  const apiRules = config.rewrites.filter((rule) => rule.source.startsWith('/api/'));
  /** Vercel's path-to-regexp for the shapes vercel.json uses: `:name*` (rest), `:name` (one segment), groups. */
  const compile = (source) =>
    new RegExp(`^${source.replace(/:[a-zA-Z]+\*/g, '(.*)').replace(/:[a-zA-Z]+/g, '([^/]+)')}$`);
  /** The first rewrite whose source matches `path` (its `has` condition assumed met), as Vercel applies them. */
  const firstMatch = (path) => config.rewrites.find((rule) => compile(rule.source).test(path));

  it('proxies exactly the three landing reads to the API host, path preserved', () => {
    expect(apiRules.map((rule) => rule.source)).toEqual(EDGE_READS);
    for (const rule of apiRules) {
      expect(rule.destination).toBe(`${API_HOST}${rule.source}`);
      expect(rule.has).toBeUndefined();
    }
  });

  it('wins over the crawler and SPA rules for the paths the landing page calls', () => {
    for (const path of ['/api/public/stats', '/api/public/talent', '/api/stage/authors/system/musilynk/posts']) {
      const rule = firstMatch(path);
      expect(rule?.destination, path).toMatch(new RegExp(`^${API_HOST}/api/`));
      expect(servedAsApp(path), path).toBe(false);
    }
    const lastApiIndex = Math.max(...apiRules.map((rule) => config.rewrites.indexOf(rule)));
    const firstOtherIndex = config.rewrites.findIndex(
      (rule) => rule.has || rule.destination === '/index.html' || rule.destination === '/app-shell.html',
    );
    expect(lastApiIndex).toBeLessThan(firstOtherIndex);
  });

  it('proxies no other /api path, so signed-in and non-landing endpoints never reach the edge', () => {
    for (const path of [
      '/api/me',
      '/api/jobs',
      '/api/jobs/job_1',
      '/api/public/talent/user_1',
      '/api/public/acts',
      '/api/public/portfolios/some-slug',
      '/api/public/hire-pages/drummer/mumbai',
      '/api/public/rates/mumbai',
      '/api/stage/feed',
      '/api/stage/authors/user/user_1/posts',
      '/api/stage/authors/system/musilynk',
      '/api/admin/stats',
      '/api/health',
    ]) {
      expect(firstMatch(path), path).toBeUndefined();
      expect(servedAsApp(path), path).toBe(false);
    }
  });
});

describe('vercel.json crawler routing and headers', () => {
  const crawlerRules = config.rewrites.filter((rule) => rule.has);
  const agentFor = (source) => crawlerRules.find((rule) => rule.source === source).has[0].value;

  it('sends Googlebot to the server-rendered share page for every record type with structured data', () => {
    for (const source of ['/opportunities/:id', '/professionals/:id', '/acts/:id', '/p/:slug']) {
      expect(
        new RegExp(agentFor(source)).test('Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'),
        source,
      ).toBe(true);
      expect(new RegExp(agentFor(source)).test('facebookexternalhit/1.1'), source).toBe(true);
      expect(new RegExp(agentFor(source)).test('Mozilla/5.0 (Windows NT 10.0) Chrome/124 Safari/537.36'), source).toBe(
        false,
      );
    }
  });

  it('redirects a trailing slash and /index.html to the canonical URL', () => {
    expect(config.trailingSlash).toBe(false);
    expect(config.redirects).toContainEqual({ source: '/index.html', destination: '/', permanent: true });
  });

  it('marks signed-in and account-flow areas noindex via X-Robots-Tag', () => {
    const rule = config.headers.find((entry) => entry.headers.some((header) => header.key === 'X-Robots-Tag'));
    const re = new RegExp(`^${rule.source}$`);
    for (const path of ['/jobseeker/profile', '/employer', '/auth/jobseeker', '/search', '/reset-password'])
      expect(re.test(path), path).toBe(true);
    for (const path of ['/', '/pricing', '/hire/drummer/mumbai', '/professionals/user_1'])
      expect(re.test(path), path).toBe(false);
  });

  it('serves the push service worker as a real file, uncached and allowed to control the whole site', () => {
    expect(existsSync(resolve(root, 'public/sw.js'))).toBe(true);
    expect(servedAsApp('/sw.js')).toBe(false);
    const rule = config.headers.find((entry) => entry.source === '/sw.js');
    const value = (key) => rule.headers.find((header) => header.key === key)?.value;
    expect(value('Service-Worker-Allowed')).toBe('/');
    expect(value('Cache-Control')).toMatch(/max-age=0/);
    // The worker script loads under script-src 'self' (worker-src falls back to it).
    const csp = config.headers
      .flatMap((entry) => entry.headers)
      .find((header) => header.key === 'Content-Security-Policy');
    expect(csp.value).not.toMatch(/worker-src/);
    expect(csp.value).toMatch(/script-src 'self'/);
  });

  it('lets the app open the real-time socket on the API host, and no other socket', () => {
    const csp = config.headers
      .flatMap((entry) => entry.headers)
      .find((header) => header.key === 'Content-Security-Policy');
    const connect = csp.value.match(/connect-src ([^;]*)/)[1].split(' ');
    expect(connect).toContain('wss://musilynk-api-production.up.railway.app');
    expect(connect.filter((source) => source.startsWith('ws'))).toEqual([
      'wss://musilynk-api-production.up.railway.app',
    ]);
  });

  it('never marks an asset immutable unless it is a hashed build file', () => {
    const immutable = config.headers.filter((entry) => entry.headers.some((header) => /immutable/.test(header.value)));
    expect(immutable.map((entry) => entry.source)).toEqual(['/assets/(.*)']);
  });
});

describe('public/robots.txt and the web manifest', () => {
  const robots = readFileSync(resolve(root, 'public/robots.txt'), 'utf8');
  const disallowed = robots
    .split('\n')
    .filter((line) => line.startsWith('Disallow:'))
    .map((line) => line.slice(9).trim());

  it('disallows the signed-in areas, account flows and the internal shell files', () => {
    for (const path of [
      '/admin',
      '/employer',
      '/jobseeker',
      '/auth/',
      '/search',
      '/forgot-password',
      '/app-shell.html',
      '/404.html',
    ])
      expect(disallowed, path).toContain(path);
    expect(robots).toMatch(/^Sitemap: https:\/\/\S+\/sitemap\.xml$/m);
  });

  it('never blocks a page the sitemap lists or the OG image function', () => {
    const publicPaths = [
      '/',
      '/music-jobs',
      '/music-professionals',
      '/book-music',
      '/pricing',
      '/guide',
      '/hire/drummer/mumbai',
      '/rates/mumbai',
      '/professionals/user_1',
      '/opportunities/job_1',
      '/acts/act_1',
      '/api/og/professional/user_1.png',
    ];
    for (const path of publicPaths)
      expect(
        disallowed.some((rule) => path.startsWith(rule)),
        path,
      ).toBe(false);
  });

  it('has a manifest with an id, language and the two install icons', () => {
    const manifest = JSON.parse(readFileSync(resolve(root, 'public/manifest.webmanifest'), 'utf8'));
    expect(manifest.id).toBe('/');
    expect(manifest.lang).toBe('en-IN');
    expect(manifest.icons.map((icon) => icon.sizes)).toEqual(expect.arrayContaining(['192x192', '512x512']));
  });
});

// The same vercel.json routes both Vercel projects: the public site and the admin site
// (VITE_APP_TARGET=admin). Build each for real and resolve URLs the way Vercel does: a file in the output
// wins, then the first matching rewrite whose destination exists, otherwise 404.html with status 404.
describe('built output resolved through vercel.json', () => {
  const sandbox = mkdtempSync(join(tmpdir(), 'musilynk-vercel-'));
  afterAll(() => rmSync(sandbox, { recursive: true, force: true }));

  function build(target) {
    const out = join(sandbox, target);
    const env = { ...process.env, VITE_APP_TARGET: target, VITE_PUBLIC_URL: 'https://musilynk.example' };
    execFileSync(
      process.execPath,
      [
        resolve(root, 'node_modules/vite/bin/vite.js'),
        'build',
        '--outDir',
        out,
        '--emptyOutDir',
        '--logLevel',
        'silent',
      ],
      { cwd: root, env },
    );
    execFileSync(process.execPath, [resolve(root, 'scripts/prerender-heads.mjs'), out], { cwd: root, env });
    return out;
  }

  function resolveUrl(out, url) {
    const path = url.split('?')[0];
    const fileFor = (p) => {
      const file = join(out, p);
      if (existsSync(file) && statSync(file).isFile()) return p;
      if (existsSync(join(file, 'index.html'))) return `${p.replace(/\/$/, '')}/index.html`;
      return null;
    };
    const direct = fileFor(path);
    if (direct) return { status: 200, file: direct };
    for (const rule of config.rewrites) {
      if (rule.has || /^https?:/.test(rule.destination)) continue;
      if (new RegExp(`^${rule.source}$`).test(path) && fileFor(rule.destination))
        return { status: 200, file: fileFor(rule.destination) };
    }
    return { status: 404, file: '/404.html' };
  }

  it('serves every admin route and any unknown admin path as the admin app, never a bare 404', () => {
    const out = build('admin');
    const adminIndex = readFileSync(join(out, 'index.html'), 'utf8');
    expect(adminIndex).toContain('noindex');
    for (const url of ['/', '/admin', '/admin?tab=users', '/admin/tester', '/account']) {
      const result = resolveUrl(out, url);
      expect(result.status, url).toBe(200);
      expect(readFileSync(join(out, result.file), 'utf8'), url).toBe(adminIndex);
    }
    // Unknown path: status 404, but the body is the app so its own not-found page renders.
    const unknown = resolveUrl(out, '/some/unknown/path');
    expect(unknown.status).toBe(404);
    expect(readFileSync(join(out, unknown.file), 'utf8')).toBe(adminIndex);
    // Every route in the admin route table has a file: a new admin route cannot be forgotten.
    const source = readFileSync(resolve(root, 'src/app/routes.tsx'), 'utf8');
    for (const path of adminRoutePaths(source)) expect(existsSync(join(out, path, 'index.html')), path).toBe(true);
  }, 120_000);

  it('keeps /admin and unknown URLs a 404 on the public site, while its routes resolve', () => {
    const out = build('public');
    for (const url of [
      '/admin',
      '/admin/tester',
      '/account',
      '/nonexistent',
      '/assets/missing.js',
      '/hire/violin/mumbai',
    ])
      expect(resolveUrl(out, url).status, url).toBe(404);
    expect(resolveUrl(out, '/pricing')).toEqual({ status: 200, file: '/pricing/index.html' });
    expect(resolveUrl(out, '/hire/drummer/mumbai').status).toBe(200);
    expect(resolveUrl(out, '/professionals/user_1')).toEqual({ status: 200, file: '/app-shell.html' });
    expect(resolveUrl(out, '/jobseeker/profile')).toEqual({ status: 200, file: '/app-shell.html' });
  }, 120_000);
});
