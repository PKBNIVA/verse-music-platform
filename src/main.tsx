
  import { createRoot } from "react-dom/client";
  import App from "./app/App.tsx";
  import { initMonitoring, RELEASE } from "./app/lib/monitoring";
  import "./styles/index.css";

  // The deployed commit, for support and the live deploy check (also in <meta name="verse-release">).
  (window as any).__VERSE_RELEASE__ = RELEASE || "unknown";
  // No-op unless VITE_SENTRY_DSN was set at build time; Sentry itself loads after first render.
  initMonitoring();

  createRoot(document.getElementById("root")!).render(<App />);
