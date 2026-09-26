import type {FormEvent, ReactNode} from 'react';
import {Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle} from './ui/dialog';
import {Button} from './ui/button';

// Accessible replacement for window.prompt in the hiring pages: a titled modal form that
// traps focus, closes on Escape and submits on Enter.
export function FormDialog({open, onOpenChange, title, description, submitLabel, busy = false, submitDisabled = false, onSubmit, children}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description?: ReactNode;
  submitLabel: string;
  busy?: boolean;
  submitDisabled?: boolean;
  onSubmit: () => void | Promise<void>;
  children: ReactNode;
}) {
  function submit(event: FormEvent) {
    event.preventDefault();
    if (!busy && !submitDisabled) void onSubmit();
  }
  return (
    <Dialog open={open} onOpenChange={next => { if (!busy) onOpenChange(next); }}>
      <DialogContent className="bg-slate-950 text-white border-white/15">
        <form onSubmit={submit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
            {description ? <DialogDescription className="text-slate-400">{description}</DialogDescription> : null}
          </DialogHeader>
          {children}
          <DialogFooter>
            <Button type="button" variant="outline" disabled={busy} onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button type="submit" disabled={busy || submitDisabled} aria-busy={busy}>{busy ? 'Saving…' : submitLabel}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export const fieldClass = 'mt-2 w-full h-10 rounded-md bg-black/20 border border-white/15 px-3 text-white';
