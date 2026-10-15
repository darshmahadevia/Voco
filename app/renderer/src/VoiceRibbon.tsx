import { useEffect, useRef } from 'react';
import { useReducedMotion } from 'motion/react';

const FRAME_COUNT = 80;
const FRAME_INTERVAL = 100;
const RIBBON_FRAMES = Array.from({ length: FRAME_COUNT }, (_, frame) => {
  const phase = frame / FRAME_COUNT * Math.PI * 2;
  return Array.from({ length: 30 }, (_, row) =>
    Array.from({ length: 90 }, (_, column) => {
      const x = column / 89;
      const y = row / 29;
      const center = 0.5 + Math.sin(x * Math.PI * 2.1 - 0.8 + Math.sin(phase) * 0.45) * 0.23;
      const distance = Math.abs(y - center);
      const ribbon = 0.075 + Math.sin(x * Math.PI + Math.cos(phase) * 0.3) * 0.13;
      const fold = Math.abs(y - (0.53 + Math.sin(x * Math.PI * 2.1 + 1.1 - Math.sin(phase) * 0.5) * 0.3));
      const density = Math.max(1 - distance / ribbon, (1 - fold / 0.09) * 0.7);
      if (density <= 0) return ' ';
      const characters = '.:+VOCO#';
      return characters[Math.min(characters.length - 1, Math.floor(density * characters.length))] ?? ' ';
    }).join(''),
  ).join('\n');
});

export function VoiceRibbon(): React.JSX.Element {
  const reducedMotion = useReducedMotion();
  const artwork = useRef<HTMLDivElement>(null);
  const text = useRef<HTMLPreElement>(null);
  useEffect(() => {
    const element = artwork.current;
    const pre = text.current;
    if (!element || !pre) return;
    let visible = false;
    let frame = 0;
    let timer: number | undefined;
    const reconcile = (): void => {
      window.clearInterval(timer);
      timer = undefined;
      const running = visible && !document.hidden && !reducedMotion;
      element.setAttribute('data-motion', running ? 'running' : 'paused');
      if (!running) return;
      timer = window.setInterval(() => {
        frame = (frame + 1) % FRAME_COUNT;
        pre.textContent = RIBBON_FRAMES[frame] ?? '';
        element.setAttribute('data-frame', String(frame));
      }, FRAME_INTERVAL);
    };
    const observer = new IntersectionObserver(entries => {
      visible = entries.some(entry => entry.isIntersecting);
      reconcile();
    });
    observer.observe(element);
    document.addEventListener('visibilitychange', reconcile);
    return () => {
      observer.disconnect();
      document.removeEventListener('visibilitychange', reconcile);
      window.clearInterval(timer);
    };
  }, [reducedMotion]);
  return <div ref={artwork} className="voice-art" aria-hidden="true" data-motion="paused"><pre ref={text}>{RIBBON_FRAMES[0]}</pre></div>;
}
