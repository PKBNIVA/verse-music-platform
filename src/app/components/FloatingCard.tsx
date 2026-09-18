import { motion } from 'motion/react';
import { ReactNode } from 'react';
import ReactParallaxTilt from 'react-parallax-tilt';

interface FloatingCardProps {
  children: ReactNode;
  delay?: number;
  className?: string;
  tiltEnabled?: boolean;
}

export function FloatingCard({ children, delay = 0, className = '', tiltEnabled = true }: FloatingCardProps) {
  if (!tiltEnabled) {
    return (
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay }}
        whileHover={{ y: -5, scale: 1.02 }}
        className={className}
      >
        {children}
      </motion.div>
    );
  }

  return (
    <ReactParallaxTilt
      tiltMaxAngleX={8}
      tiltMaxAngleY={8}
      perspective={1000}
      scale={1.02}
      transitionSpeed={2000}
    >
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay }}
        whileHover={{ y: -5 }}
        className={className}
      >
        {children}
      </motion.div>
    </ReactParallaxTilt>
  );
}