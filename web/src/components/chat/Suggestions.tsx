import { useMemo } from 'react';
import { ensureString } from '../../richText';
import { asArray } from '../../utils';
import type { Suggestion, SuggestionParam } from '../../types';

function normalizeCommandName(value: string) {
  return value.startsWith('/') ? value : `/${value}`;
}

function paramType(param: SuggestionParam) {
  const value = `${param.type || ''} ${param.name || ''} ${param.help || ''}`.toLowerCase();
  if (value.includes('player') || value.includes('target') || value.includes('id')) {
    return 'player';
  }
  if (value.includes('number') || value.includes('integer') || value.includes('amount') || value.includes('count')) {
    return 'number';
  }
  return 'text';
}

export default function Suggestions({
  input,
  suggestions,
  onPickSuggestion,
  onPickParam
}: {
  input: string;
  suggestions: Suggestion[];
  onPickSuggestion: (suggestion: Suggestion) => void;
  onPickParam: (suggestion: Suggestion, param: SuggestionParam, type: string) => void;
}) {
  const current = useMemo(() => {
    if (!input.startsWith('/')) {
      return [];
    }
    const commandPart = input.split(/\s+/)[0].toLowerCase();
    return suggestions
      .filter((suggestion) => {
        const name = normalizeCommandName(ensureString(suggestion.name));
        if (!name) {
          return false;
        }
        const normalizedName = name.toLowerCase();
        return normalizedName.startsWith(commandPart) || normalizedName.startsWith(`/${commandPart.replace(/^\//, '')}`);
      })
      .slice(0, 8);
  }, [input, suggestions]);
  const exact = current.find((suggestion) => normalizeCommandName(ensureString(suggestion.name)).toLowerCase() === input.split(/\s+/)[0].toLowerCase());
  const inputParts = input.trimEnd().split(/\s+/);
  const enteredArgs = inputParts.length > 1 ? inputParts.slice(1) : [];

  if (current.length === 0) {
    return null;
  }

  return (
    <div className="suggestions">
      {current.map((suggestion) => (
        <button type="button" className="suggestion" key={suggestion.name} disabled={suggestion.disabled === true} onClick={() => onPickSuggestion(suggestion)}>
          <div className="suggestion-name">{suggestion.name}</div>
          <div className="suggestion-help">
            {suggestion.help || asArray<{ name?: string }>(suggestion.params).map((param) => `[${param.name}]`).join(' ')}
          </div>
        </button>
      ))}
      {exact && asArray<SuggestionParam>(exact.params).length > 0 && (
        <div className="suggestion-params">
          {asArray<SuggestionParam>(exact.params).map((param, index) => {
            const type = paramType(param);
            const state = index < enteredArgs.length ? 'filled' : index === enteredArgs.length ? 'next' : 'pending';
            return (
              <button type="button" className={state} key={`param:${exact.name}:${index}`} onClick={() => onPickParam(exact, param, type)}>
                <strong>{param.name || `arg${index + 1}`}</strong>
                <span>{state === 'filled' ? enteredArgs[index] : type}</span>
                {param.help && <small>{param.help}</small>}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
