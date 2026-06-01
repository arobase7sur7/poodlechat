import type { ChatMessage } from './types';

export function ensureString(value: unknown, fallback = ''): string {
  if (value === undefined || value === null) {
    return fallback;
  }
  return String(value);
}

export function normalizeKey(value: unknown): string {
  return ensureString(value).trim().toLowerCase();
}

export function escapeHtml(value: unknown): string {
  return ensureString(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

export function expandHex(hex: string): string | null {
  const raw = hex.replace(/^#/, '').trim();
  if (/^[0-9a-fA-F]{3}$/.test(raw)) {
    return `#${raw.split('').map((char) => char + char).join('').toLowerCase()}`;
  }
  if (/^[0-9a-fA-F]{6}$/.test(raw)) {
    return `#${raw.toLowerCase()}`;
  }
  return null;
}

export function renderRichText(value: unknown): string {
  const source = ensureString(value);
  let output = '';
  let openColor = false;
  let openBold = false;
  let openUnderline = false;
  let openStrike = false;
  let openItalic = false;

  const closeStyles = () => {
    if (openItalic) {
      output += '</em>';
      openItalic = false;
    }
    if (openStrike) {
      output += '</s>';
      openStrike = false;
    }
    if (openUnderline) {
      output += '</u>';
      openUnderline = false;
    }
    if (openBold) {
      output += '</strong>';
      openBold = false;
    }
  };

  const closeColor = () => {
    if (openColor) {
      output += '</span>';
      openColor = false;
    }
  };

  const reset = () => {
    closeStyles();
    closeColor();
  };

  for (let index = 0; index < source.length; index += 1) {
    const char = source[index];
    if (char === '^' && index + 1 < source.length) {
      const next = source[index + 1];
      if (next === '#') {
        const rest = source.slice(index + 2);
        const match = rest.match(/^([0-9a-fA-F]{6}|[0-9a-fA-F]{3})/);
        if (match) {
          const expanded = expandHex(match[1]);
          if (expanded) {
            closeColor();
            output += `<span style="color:${expanded}">`;
            openColor = true;
            index += match[1].length + 1;
            continue;
          }
        }
      }

      if (/^[0-9]$/.test(next)) {
        closeColor();
        output += `<span class="rich-color-${next}">`;
        openColor = true;
        index += 1;
        continue;
      }

      if (next === 'r') {
        reset();
        index += 1;
        continue;
      }

      if (next === '*' && !openBold) {
        output += '<strong>';
        openBold = true;
        index += 1;
        continue;
      }
      if (next === '_' && !openUnderline) {
        output += '<u>';
        openUnderline = true;
        index += 1;
        continue;
      }
      if (next === '~' && !openStrike) {
        output += '<s>';
        openStrike = true;
        index += 1;
        continue;
      }
      if (next === '/' && !openItalic) {
        output += '<em>';
        openItalic = true;
        index += 1;
        continue;
      }
      if (next === '=') {
        if (!openUnderline) {
          output += '<u>';
          openUnderline = true;
        }
        if (!openStrike) {
          output += '<s>';
          openStrike = true;
        }
        index += 1;
        continue;
      }
    }

    if (char === '\\' && source[index + 1] === 'n') {
      output += '<br>';
      index += 1;
    } else {
      output += escapeHtml(char);
    }
  }

  reset();

  return output.replace(/%gpslink\|([^|]+)\|(-?\d+(?:\.\d+)?)\|(-?\d+(?:\.\d+)?)\|(-?\d+(?:\.\d+)?)%/g, (_full, label, x, y, z) => {
    return `<button type="button" class="gps-link" data-gps-x="${x}" data-gps-y="${y}" data-gps-z="${z}">${escapeHtml(label)}</button>`;
  });
}

export function stripRichText(value: unknown): string {
  return ensureString(value)
    .replace(/%gpslink\|([^|]+)\|[^%]+%/g, '$1')
    .replace(/\^#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})/g, '')
    .replace(/\^([0-9]|_|\*|=|~|\/|r)/g, '')
    .replace(/\\n/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function formatTimestamp(value: unknown): string {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) {
    return '';
  }
  const date = new Date(numeric < 1000000000000 ? numeric * 1000 : numeric);
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

export function normalizeTimestamp(value: unknown): number {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) {
    return Date.now();
  }
  return numeric < 1000000000000 ? Math.floor(numeric * 1000) : Math.floor(numeric);
}

export function messageBody(message: ChatMessage): string {
  const args = Array.isArray(message.args) ? message.args : [];
  if (args.length > 1) {
    return ensureString(args.slice(1).join(' '));
  }
  if (args.length === 1) {
    return ensureString(args[0]);
  }
  return ensureString(message.text);
}

export function messageAuthor(message: ChatMessage): string {
  const args = Array.isArray(message.args) ? message.args : [];
  if (args.length > 1) {
    return ensureString(args[0], ensureString(message.label, 'Chat'));
  }
  return ensureString(message.label, 'Chat');
}

export function messageRawText(message: ChatMessage): string {
  const args = Array.isArray(message.args) ? message.args.map((entry) => ensureString(entry)) : [];
  if (args.length > 0) {
    return args.join(' ');
  }
  return ensureString(message.text);
}

export function colorToCss(color: unknown, fallback = '#f6f3ea'): string {
  if (typeof color === 'string') {
    return expandHex(color) || color;
  }
  if (Array.isArray(color)) {
    const [r, g, b] = color.map((entry) => Math.max(0, Math.min(255, Math.floor(Number(entry) || 0))));
    return `rgb(${r}, ${g}, ${b})`;
  }
  return fallback;
}

export function normalizeMessage(raw: ChatMessage, fallbackChannel: string, index: number): ChatMessage {
  const metadata = raw.metadata && typeof raw.metadata === 'object' ? { ...raw.metadata } : {};
  const timestamp = normalizeTimestamp(raw.timestamp);
  const channel = ensureString(raw.channel, fallbackChannel || 'global');
  const messageId = ensureString(raw.messageId || metadata.messageId, '').trim() || `ui:${channel}:${timestamp}:${index}`;
  metadata.messageId = messageId;

  return {
    ...raw,
    channel,
    label: ensureString(raw.label, channel),
    color: raw.color || [255, 255, 255],
    args: Array.isArray(raw.args) ? raw.args : [ensureString(raw.text, '')],
    timestamp,
    restored: raw.restored === true,
    messageId,
    metadata
  };
}
