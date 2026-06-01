import { useCallback, useRef, useState } from 'react';

export function useCommandHistory(limit = 30) {
  const [history, setHistory] = useState<string[]>([]);
  const [historyIndex, setHistoryIndex] = useState(-1);
  const scratchDraftRef = useRef('');

  const commitHistory = useCallback((message: string) => {
    const normalized = message.trim();
    if (!normalized) {
      return;
    }
    setHistory((current) => [normalized, ...current.filter((entry) => entry !== normalized)].slice(0, limit));
    setHistoryIndex(-1);
    scratchDraftRef.current = '';
  }, [limit]);

  const browseHistory = useCallback((direction: 'up' | 'down', currentDraft: string): string | null => {
    if (history.length === 0) {
      return null;
    }

    if (direction === 'up') {
      const nextIndex = historyIndex < 0 ? 0 : Math.min(history.length - 1, historyIndex + 1);
      if (historyIndex < 0) {
        scratchDraftRef.current = currentDraft;
      }
      setHistoryIndex(nextIndex);
      return history[nextIndex] || '';
    }

    if (historyIndex < 0) {
      return null;
    }

    const nextIndex = historyIndex - 1;
    setHistoryIndex(nextIndex);
    return nextIndex >= 0 ? history[nextIndex] || '' : scratchDraftRef.current;
  }, [history, historyIndex]);

  const resetHistoryBrowse = useCallback(() => {
    setHistoryIndex(-1);
    scratchDraftRef.current = '';
  }, []);

  return {
    history,
    historyIndex,
    commitHistory,
    browseHistory,
    resetHistoryBrowse
  };
}
