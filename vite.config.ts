import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

// The deployed commit, so errors and the live deploy check can name the exact build.
// Vercel exposes VERCEL_GIT_COMMIT_SHA during builds; VITE_RELEASE overrides it.
const release = (process.env.VITE_RELEASE || process.env.VERCEL_GIT_COMMIT_SHA || '').trim().replace(/[^A-Za-z0-9._-]/g, '');
// Exposed to the app as import.meta.env.VITE_RELEASE (Vite reads VITE_* from process.env).
process.env.VITE_RELEASE = release;

// <meta name="verse-release"> lets the live QA run confirm which commit Vercel is serving.
function releaseMeta(): Plugin {
  return {
    name: 'verse-release-meta',
    transformIndexHtml: () => [{ tag: 'meta', attrs: { name: 'verse-release', content: release || 'unknown' }, injectTo: 'head' }],
  };
}

// `npm run dev` proxies /api to the Rails API (backend/, `bin/rails server -p 3000`).
// `vite preview` would inherit server.proxy by default, so it is disabled there: Playwright
// runs mock /api in the browser, and integration runs set VITE_API_URL explicitly.
export default defineConfig({
  plugins: [react(), tailwindcss(), releaseMeta()],
  server: { proxy: { '/api': 'http://127.0.0.1:3000' } },
  preview: { proxy: {} },
});
