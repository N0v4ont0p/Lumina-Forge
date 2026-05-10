import { motion } from 'framer-motion';

export function ProgressRing({ completed, total }: { completed: number; total: number }) {
  const safeTotal = total || 1;
  const progress = Math.min(completed / safeTotal, 1);
  const radius = 56;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - progress * circumference;
  const done = total > 0 && completed >= total;

  return (
    <div className="relative mx-auto w-[140px] h-[140px] flex items-center justify-center">
      <svg width="140" height="140" viewBox="0 0 140 140" className="-rotate-90">
        <circle cx="70" cy="70" r={radius} stroke="rgba(255,255,255,0.15)" strokeWidth="10" fill="none" />
        <motion.circle
          cx="70"
          cy="70"
          r={radius}
          stroke="url(#luminaGradient)"
          strokeWidth="10"
          strokeLinecap="round"
          fill="none"
          initial={{ strokeDashoffset: circumference }}
          animate={{ strokeDashoffset: offset }}
          transition={{ type: 'spring', stiffness: 240, damping: 28 }}
          strokeDasharray={circumference}
        />
        <defs>
          <linearGradient id="luminaGradient" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#60a5fa" />
            <stop offset="50%" stopColor="#a78bfa" />
            <stop offset="100%" stopColor="#22d3ee" />
          </linearGradient>
        </defs>
      </svg>
      <div className="absolute text-center">
        <div className="text-2xl font-bold">{Math.round(progress * 100)}%</div>
        <div className="text-xs text-white/65">{completed} / {total}</div>
      </div>
      {done && (
        <div className="absolute inset-0 pointer-events-none">
          {Array.from({ length: 18 }).map((_, i) => {
            const angle = (i / 18) * Math.PI * 2;
            return (
              <motion.span
                key={i}
                className="absolute left-1/2 top-1/2 h-2 w-2 rounded-sm bg-cyan-300"
                initial={{ x: 0, y: 0, opacity: 1, scale: 1 }}
                animate={{ x: Math.cos(angle) * 74, y: Math.sin(angle) * 74, opacity: 0, scale: 0.2 }}
                transition={{ duration: 0.8, ease: 'easeOut' }}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}
