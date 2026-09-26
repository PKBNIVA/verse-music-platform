import {FlaskConical} from 'lucide-react';

/** Marks sample content created from the admin demo-data panel (API field `demo: true`). */
export function DemoBadge({show,className=''}:{show?:boolean;className?:string}){
  if(!show)return null;
  return <span data-testid="demo-badge" title="Sample content for previewing Verse. Not a real account." className={`inline-flex items-center gap-1 rounded-full border border-amber-300/40 bg-amber-400/15 px-2 py-0.5 text-[11px] font-bold uppercase tracking-wide text-amber-200 ${className}`}><FlaskConical size={11} aria-hidden="true"/>Demo</span>;
}
