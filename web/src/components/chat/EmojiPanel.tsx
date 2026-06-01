import { useEffect, useMemo, useState } from 'react';
import { Car, Clock3, Flag, Flame, Hand, Leaf, Lightbulb, Search, Shapes, SmilePlus, Trophy, UserRound, Utensils } from 'lucide-react';
import { ensureString } from '../../richText';
import type { EmojiEntry } from '../../types';

const htmlDecodeCache = new Map<string, string>();

function decodeHtmlEntity(html: string): string {
  const cached = htmlDecodeCache.get(html);
  if (cached) {
    return cached;
  }
  const textarea = document.createElement('textarea');
  textarea.innerHTML = html;
  const decoded = textarea.value;
  htmlDecodeCache.set(html, decoded);
  return decoded;
}

export default function EmojiPanel({
  emojis,
  recent,
  top,
  query,
  setQuery,
  onPick
}: {
  emojis: EmojiEntry[];
  recent: EmojiEntry[];
  top: EmojiEntry[];
  query: string;
  setQuery: (value: string) => void;
  onPick: (emoji: string, entry: EmojiEntry) => void;
}) {
  const [category, setCategory] = useState('history');
  const categories = useMemo(() => {
    const list = Array.from(new Set(emojis.map((emoji) => ensureString(emoji.category, 'other')).filter(Boolean)));
    return [
      ...(recent.length > 0 ? ['history'] : []),
      ...(top.length > 0 ? ['top'] : []),
      ...list
    ];
  }, [emojis, recent.length, top.length]);

  const visible = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const sourceByCategory = category === 'history'
      ? recent
      : category === 'top'
        ? top
        : emojis.filter((emoji) => ensureString(emoji.category, 'other') === category);
    const source = needle
      ? emojis.filter((emoji) => ensureString(emoji.search || emoji.name || emoji.aliases?.join(' ')).toLowerCase().includes(needle))
      : sourceByCategory;
    return source.slice(0, needle ? 180 : 96);
  }, [category, emojis, query, recent, top]);

  useEffect(() => {
    if (categories.length === 0) {
      return;
    }
    if (!categories.includes(category)) {
      setCategory(categories[0]);
    }
  }, [categories, category]);

  const categoryIcon = (item: string) => {
    if (item === 'history') {
      return <Clock3 size={15} />;
    }
    if (item === 'top') {
      return <Flame size={15} />;
    }
    const normalized = item.toLowerCase();
    if (normalized.includes('people') || normalized.includes('person') || normalized.includes('smile')) {
      return <SmilePlus size={15} />;
    }
    if (normalized.includes('gesture') || normalized.includes('hand')) {
      return <Hand size={15} />;
    }
    if (normalized.includes('nature') || normalized.includes('plant')) {
      return <Leaf size={15} />;
    }
    if (normalized.includes('food') || normalized.includes('drink')) {
      return <Utensils size={15} />;
    }
    if (normalized.includes('activity') || normalized.includes('sport')) {
      return <Trophy size={15} />;
    }
    if (normalized.includes('travel') || normalized.includes('place')) {
      return <Car size={15} />;
    }
    if (normalized.includes('object')) {
      return <Lightbulb size={15} />;
    }
    if (normalized.includes('flag')) {
      return <Flag size={15} />;
    }
    return <Shapes size={15} />;
  };

  const categoryLabel = (item: string) => {
    if (item === 'history') {
      return 'Recent';
    }
    if (item === 'top') {
      return 'Most used';
    }
    return item.replace(/[-_]+/g, ' ').replace(/\b\w/g, (char) => char.toUpperCase());
  };

  const emojiGlyph = (emoji: EmojiEntry): string => {
    const html = ensureString(emoji.emoji || emoji.htmlCode?.[0] || emoji.unicode?.[0] || emoji.aliases?.[0] || '');
    return html.startsWith('&') ? decodeHtmlEntity(html) : html;
  };

  return (
    <div className="emoji-panel">
      <div className="emoji-search">
        <Search size={14} />
        <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search emoji" />
      </div>
      <div className="emoji-categories">
        {categories.map((item) => (
          <button
            key={`emoji-category:${item}`}
            type="button"
            className={category === item ? 'active' : ''}
            title={categoryLabel(item)}
            aria-label={categoryLabel(item)}
            onClick={() => setCategory(item)}
          >
            {categoryIcon(item)}
          </button>
        ))}
      </div>
      <div className="emoji-grid">
        {visible.map((emoji, index) => {
          const char = emojiGlyph(emoji);
          return (
            <button key={`${emoji.name || 'emoji'}:${index}`} type="button" title={emoji.name} onClick={() => onPick(char, emoji)}>
              {char}
            </button>
          );
        })}
        {visible.length === 0 && <div className="emoji-empty">No emoji here yet.</div>}
      </div>
    </div>
  );
}
