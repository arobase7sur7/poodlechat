export type ChatFontOption = {
  id: string;
  label: string;
  css: string;
};

export const CHAT_FONT_OPTIONS: ChatFontOption[] = [
  { id: 'inter', label: 'Inter', css: 'Inter, "Segoe UI", system-ui, -apple-system, BlinkMacSystemFont, sans-serif' },
  { id: 'system', label: 'System UI', css: '"Segoe UI", system-ui, -apple-system, BlinkMacSystemFont, sans-serif' },
  { id: 'tahoma', label: 'Tahoma', css: 'Tahoma, Verdana, "Segoe UI", sans-serif' },
  { id: 'arial', label: 'Arial', css: 'Arial, Helvetica, sans-serif' },
  { id: 'georgia', label: 'Georgia', css: 'Georgia, "Times New Roman", serif' },
  { id: 'mono', label: 'Mono', css: '"Cascadia Mono", "Consolas", "Courier New", monospace' }
];

export function normalizeChatFontId(value: unknown): string {
  const id = typeof value === 'string' ? value.trim().toLowerCase() : '';
  return CHAT_FONT_OPTIONS.some((option) => option.id === id) ? id : 'inter';
}

export function chatFontCss(value: unknown): string {
  const id = normalizeChatFontId(value);
  return CHAT_FONT_OPTIONS.find((option) => option.id === id)?.css || CHAT_FONT_OPTIONS[0].css;
}

export function normalizeChatFontScale(value: unknown): number {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return 1;
  }
  const scale = numeric > 10 ? numeric / 100 : numeric;
  return Math.max(0.5, Math.min(1.5, scale));
}
