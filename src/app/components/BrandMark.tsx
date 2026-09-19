import { AudioWaveform, Disc3 } from 'lucide-react';

type BrandMarkProps = {
  compact?: boolean;
  inverse?: boolean;
};

export function BrandMark({ compact = false, inverse = true }: BrandMarkProps) {
  return (
    <span className="inline-flex items-center gap-2.5 select-none">
      <span className="verse-brand-icon" aria-hidden="true">
        <Disc3 className="h-5 w-5" />
        <AudioWaveform className="verse-brand-wave h-3 w-3" />
      </span>
      <span className="leading-none">
        <span className={`block text-lg font-black tracking-[-0.03em] ${inverse ? 'text-white' : 'text-slate-950'}`}>Verse</span>
        {!compact && <span className="mt-1 block text-[9px] font-semibold uppercase tracking-[0.18em] text-slate-400">music works here</span>}
      </span>
    </span>
  );
}
