import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
// `npm run dev` proxies /api to the Rails API (backend/, `bin/rails server -p 3000`).
// `vite preview` would inherit server.proxy by default, so it is disabled there: Playwright
// runs mock /api in the browser, and integration runs set VITE_API_URL explicitly.
export default defineConfig({plugins:[react(),tailwindcss()],server:{proxy:{'/api':'http://127.0.0.1:3000'}},preview:{proxy:{}}});
