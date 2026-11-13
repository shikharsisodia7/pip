import clsx from 'clsx';

/** Placeholder speech bubble. */
export default function SpeechBubble({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={clsx('rounded-card border border-line bg-paper px-6 py-4 font-display text-2xl shadow-soft', className)}>
      {children}
    </div>
  );
}
