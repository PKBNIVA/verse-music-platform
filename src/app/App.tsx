import { RouterProvider } from 'react-router';
import { router } from './routes';
import { AuthProvider } from './lib/authContext';
import { Toaster } from './components/ui/sonner';
import { AppErrorBoundary } from './components/ExperienceStates';

export default function App() {
  return (
    <AppErrorBoundary>
      <AuthProvider>
        <RouterProvider router={router} />
        <Toaster position="top-right" richColors closeButton />
      </AuthProvider>
    </AppErrorBoundary>
  );
}
