import { useRef, type ReactNode } from 'react';
import { ChevronDown } from 'lucide-react';

export function Disclosure({ title, className, children }: {
  title: ReactNode;
  className: string;
  children: ReactNode;
}): React.JSX.Element {
  const body = useRef<HTMLDivElement>(null);
  return <details className={`disclosure ${className}`} onToggle={event => {
    const details = event.currentTarget;
    if (!details.open && body.current?.contains(document.activeElement)) details.querySelector('summary')?.focus();
    body.current?.toggleAttribute('inert', !details.open);
  }}>
    <summary><span className="disclosure-label">{title}</span><ChevronDown className="disclosure-chevron" size={15} aria-hidden="true" /></summary>
    <div className="disclosure-body" ref={body} inert>{children}</div>
  </details>;
}
