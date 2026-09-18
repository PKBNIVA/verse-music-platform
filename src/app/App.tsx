import { RouterProvider } from 'react-router';
import { router } from './routes';
import { AuthProvider } from './lib/authContext';
import { Toaster } from './components/ui/sonner';
import { CursorGlow } from './components/CursorGlow';
import { useEffect } from 'react';

export default function App() {
  useEffect(() => {
    console.log('App mounted successfully');
  }, []);

  return (
    <AuthProvider>
      <CursorGlow />
      <RouterProvider router={router} />
      <Toaster position="top-right" />
    </AuthProvider>
  );
}