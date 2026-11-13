// FROZEN shared UI primitive. Do not edit; ask the bootstrap owner for changes.

import clsx from 'clsx';

export type CardProps = React.HTMLAttributes<HTMLDivElement>;

export function Card({ className, children, ...rest }: CardProps) {
  return (
    <div className={clsx('rounded-card border border-line bg-paper p-6 shadow-soft', className)} {...rest}>
      {children}
    </div>
  );
}

export default Card;
