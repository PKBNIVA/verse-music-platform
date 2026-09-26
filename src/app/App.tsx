import { RouterProvider } from 'react-router';
import { MotionConfig } from 'motion/react';
import { router } from './routes';
import { AuthProvider } from './lib/authContext';
import { Toaster } from './components/ui/sonner';
import { AppErrorBoundary } from './components/ExperienceStates';
import { PlanLimitPrompt } from './components/PlanLimitPrompt';

export default function App() {
  return (
    <AppErrorBoundary>
      {/* Honour the operating system's reduced-motion setting for every motion animation. */}
      <MotionConfig reducedMotion="user">
        <AuthProvider>
          <RouterProvider router={router} />
          <Toaster position="top-right" richColors closeButton />
          <PlanLimitPrompt />
        </AuthProvider>
      </MotionConfig>
    </AppErrorBoundary>
  );
}
