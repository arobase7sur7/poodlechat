import { X } from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { CSSProperties, PointerEvent as ReactPointerEvent } from 'react';

const swatches = ['68d8a7', 'f6d365', '8fc7ff', 'ff8f70', 'd891ef', 'fffaf0', '79d86f', 'f25555', '73a9ff', 'b7b7b0'];

type Rgb = [number, number, number];
type Hsl = { h: number; s: number; l: number };

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, Number.isFinite(value) ? value : min));
}

function cleanHex(value: string): string {
  return value.replace(/^#/, '').replace(/[^0-9a-f]/gi, '').slice(0, 6).toLowerCase();
}

function displayHex(value: string): string {
  const raw = cleanHex(value);
  if (raw.length === 3) {
    return raw.split('').map((char) => char + char).join('');
  }
  if (raw.length === 6) {
    return raw;
  }
  if (raw.length > 0) {
    return raw.padEnd(6, raw[raw.length - 1] || '0');
  }
  return '68d8a7';
}

function channelHex(value: number): string {
  return clamp(Math.round(value), 0, 255).toString(16).padStart(2, '0');
}

function rgbToHex(rgb: Rgb): string {
  return rgb.map(channelHex).join('');
}

function hexToRgb(value: string): Rgb {
  const expanded = displayHex(value);
  return [0, 2, 4].map((index) => parseInt(expanded.slice(index, index + 2), 16)) as Rgb;
}

function rgbToHsl([rInput, gInput, bInput]: Rgb): Hsl {
  const r = rInput / 255;
  const g = gInput / 255;
  const b = bInput / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const lightness = (max + min) / 2;
  let hue = 0;
  let saturation = 0;

  if (max !== min) {
    const delta = max - min;
    saturation = lightness > 0.5 ? delta / (2 - max - min) : delta / (max + min);
    if (max === r) {
      hue = (g - b) / delta + (g < b ? 6 : 0);
    } else if (max === g) {
      hue = (b - r) / delta + 2;
    } else {
      hue = (r - g) / delta + 4;
    }
    hue *= 60;
  }

  return {
    h: Math.round(hue),
    s: Math.round(saturation * 100),
    l: Math.round(lightness * 100)
  };
}

function hslToRgb({ h, s, l }: Hsl): Rgb {
  const hue = ((h % 360) + 360) % 360;
  const saturation = clamp(s, 0, 100) / 100;
  const lightness = clamp(l, 0, 100) / 100;
  const chroma = (1 - Math.abs(2 * lightness - 1)) * saturation;
  const x = chroma * (1 - Math.abs((hue / 60) % 2 - 1));
  const m = lightness - chroma / 2;
  let r = 0;
  let g = 0;
  let b = 0;

  if (hue < 60) {
    [r, g, b] = [chroma, x, 0];
  } else if (hue < 120) {
    [r, g, b] = [x, chroma, 0];
  } else if (hue < 180) {
    [r, g, b] = [0, chroma, x];
  } else if (hue < 240) {
    [r, g, b] = [0, x, chroma];
  } else if (hue < 300) {
    [r, g, b] = [x, 0, chroma];
  } else {
    [r, g, b] = [chroma, 0, x];
  }

  return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}

export default function HexColorPicker({
  hex,
  tokenLabel,
  onChange,
  onClose
}: {
  hex: string;
  tokenLabel: string;
  onChange: (hex: string) => void;
  onClose: () => void;
}) {
  const colorAreaRef = useRef<HTMLDivElement | null>(null);
  const display = displayHex(hex);
  const rgb = useMemo(() => hexToRgb(display), [display]);
  const [hsl, setHsl] = useState<Hsl>(() => rgbToHsl(rgb));
  const [manualHex, setManualHex] = useState(`#${display}`);
  const hueColor = useMemo(() => rgbToHex(hslToRgb({ h: hsl.h, s: 100, l: 50 })), [hsl.h]);

  useEffect(() => {
    setHsl(rgbToHsl(rgb));
  }, [rgb]);

  useEffect(() => {
    setManualHex(`#${display}`);
  }, [display]);

  const commitHsl = useCallback((nextHsl: Hsl) => {
    const normalized = {
      h: clamp(Math.round(nextHsl.h), 0, 360),
      s: clamp(Math.round(nextHsl.s), 0, 100),
      l: clamp(Math.round(nextHsl.l), 0, 100)
    };
    setHsl(normalized);
    onChange(rgbToHex(hslToRgb(normalized)));
  }, [onChange]);

  const commitRgb = useCallback((nextRgb: Rgb) => {
    onChange(rgbToHex(nextRgb));
  }, [onChange]);

  const pickFromPoint = useCallback((clientX: number, clientY: number) => {
    const rect = colorAreaRef.current?.getBoundingClientRect();
    if (!rect) {
      return;
    }
    const x = clamp(clientX - rect.left, 0, rect.width);
    const y = clamp(clientY - rect.top, 0, rect.height);
    commitHsl({
      h: hsl.h,
      s: Math.round((x / rect.width) * 100),
      l: Math.round(100 - (y / rect.height) * 100)
    });
  }, [commitHsl, hsl.h]);

  const beginPick = (event: ReactPointerEvent<HTMLDivElement>) => {
    event.preventDefault();
    const pointerId = event.pointerId;
    event.currentTarget.setPointerCapture(pointerId);
    pickFromPoint(event.clientX, event.clientY);
  };

  const movePick = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      pickFromPoint(event.clientX, event.clientY);
    }
  };

  const commitManualHex = useCallback((value: string) => {
    const cleaned = cleanHex(value);
    const normalized = displayHex(cleaned);
    setManualHex(`#${normalized}`);
    onChange(normalized);
  }, [onChange]);

  return (
    <div className="hex-picker" style={{ '--picker-color': `#${display}` } as CSSProperties}>
      <div className="hex-picker-head">
        <div className="hex-picker-title">
          <span className="hex-picker-dot" />
          <div>
            <strong>{tokenLabel}</strong>
            <span>Custom color</span>
          </div>
        </div>
        <button type="button" onClick={onClose} aria-label="Close color picker"><X size={15} /></button>
      </div>
      <div
        ref={colorAreaRef}
        className="hex-color-area"
        style={{
          background: `linear-gradient(to top, #000000 0%, rgba(0, 0, 0, 0) 100%), linear-gradient(to right, #ffffff 0%, rgba(255, 255, 255, 0) 100%), #${hueColor}`
        }}
        onPointerDown={beginPick}
        onPointerMove={movePick}
      >
        <span
          className="hex-color-handle"
          style={{
            left: `${hsl.s}%`,
            top: `${100 - hsl.l}%`,
            background: `#${display}`
          }}
        />
      </div>
      <label className="hex-hue-row">
        <span>Hue</span>
        <input min={0} max={360} type="range" value={hsl.h} onChange={(event) => commitHsl({ ...hsl, h: Number(event.target.value) })} />
        <strong>{hsl.h}</strong>
      </label>
      <div className="hex-picker-main">
        <div className="hex-current">
          <div className="hex-picker-preview" />
          <strong>{`#${display}`}</strong>
        </div>
        <label className="hex-manual">
          <span>Hex</span>
          <input
            value={manualHex}
            maxLength={7}
            spellCheck={false}
            onChange={(event) => {
              const cleaned = cleanHex(event.target.value);
              setManualHex(`#${cleaned}`);
              if (cleaned.length === 3 || cleaned.length === 6) {
                onChange(displayHex(cleaned));
              }
            }}
            onBlur={(event) => commitManualHex(event.target.value)}
          />
        </label>
      </div>
      <div className="hex-sliders">
        {(['R', 'G', 'B'] as const).map((label, index) => (
          <label key={`hex-slider:${label}`}>
            <span>{label}</span>
            <input
              min={0}
              max={255}
              type="range"
              value={rgb[index]}
              onChange={(event) => {
                const next: Rgb = [...rgb] as Rgb;
                next[index] = Number(event.target.value);
                commitRgb(next);
              }}
            />
            <input
              className="hex-channel-input"
              type="number"
              min={0}
              max={255}
              value={rgb[index]}
              onChange={(event) => {
                const next: Rgb = [...rgb] as Rgb;
                next[index] = clamp(Number(event.target.value), 0, 255);
                commitRgb(next);
              }}
            />
          </label>
        ))}
      </div>
      <div className="hex-swatches" aria-label="Preset colors">
        <span className="hex-swatches-label">Preset</span>
        {swatches.map((item) => (
          <button type="button" key={`hex-swatch:${item}`} style={{ background: `#${item}` }} onClick={() => onChange(item)} aria-label={`Use #${item}`} />
        ))}
      </div>
    </div>
  );
}
