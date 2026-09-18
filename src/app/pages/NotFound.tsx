import { motion } from 'motion/react';
import { Button } from '../components/ui/button';
import { Music, Home } from 'lucide-react';
import { Link } from 'react-router';

export default function NotFound() {
  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-indigo-900 to-blue-900 flex items-center justify-center px-6">
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="text-center"
      >
        <motion.div
          animate={{
            rotate: [0, 10, -10, 0],
          }}
          transition={{
            duration: 2,
            repeat: Infinity,
            ease: "easeInOut",
          }}
          className="mb-8"
        >
          <Music className="w-32 h-32 text-purple-400 mx-auto" />
        </motion.div>
        <h1 className="text-9xl font-bold text-white mb-4">404</h1>
        <h2 className="text-3xl font-bold text-white mb-4">Page Not Found</h2>
        <p className="text-purple-200 mb-8 max-w-md mx-auto">
          Oops! Looks like this page hit a wrong note. Let's get you back on track.
        </p>
        <Link to="/">
          <Button className="bg-gradient-to-r from-purple-500 to-pink-500 hover:from-purple-600 hover:to-pink-600">
            <Home className="w-4 h-4 mr-2" />
            Back to Home
          </Button>
        </Link>
      </motion.div>
    </div>
  );
}
