const VOICE_RIBBON = Array.from({ length: 30 }, (_, row) =>
  Array.from({ length: 90 }, (_, column) => {
    const x = column / 89;
    const y = row / 29;
    const center = 0.5 + Math.sin(x * Math.PI * 2.1 - 0.8) * 0.23;
    const distance = Math.abs(y - center);
    const ribbon = 0.075 + Math.sin(x * Math.PI) * 0.13;
    const fold = Math.abs(y - (0.53 + Math.sin(x * Math.PI * 2.1 + 1.1) * 0.3));
    const density = Math.max(1 - distance / ribbon, (1 - fold / 0.09) * 0.7);
    if (density <= 0) return ' ';
    const characters = '.:+VOCO#';
    return characters[Math.min(characters.length - 1, Math.floor(density * characters.length))] ?? ' ';
  }).join(''),
).join('\n');

export function VoiceRibbon(): React.JSX.Element {
  return <div className="voice-art" aria-hidden="true"><pre>{VOICE_RIBBON}</pre></div>;
}
