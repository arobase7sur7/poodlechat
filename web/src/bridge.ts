import type { AnyRecord, ManagerBootstrap, OnLoadPayload } from './types';

export function getResourceName(): string {
  const parent = window as Window & { GetParentResourceName?: () => string };
  return parent.GetParentResourceName ? parent.GetParentResourceName() : 'poodlechat';
}

export async function fetchNui<T = unknown>(eventName: string, data: unknown = {}): Promise<T> {
  const localMock = getDevNuiResponse(eventName, data);
  if (localMock !== undefined) {
    return localMock as T;
  }

  const resource = getResourceName();
  let response: Response;
  try {
    response = await fetch(`https://${resource}/${eventName}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json; charset=UTF-8'
      },
      body: JSON.stringify(data ?? {})
    });
  } catch (error) {
    const mocked = getDevNuiResponse(eventName, data);
    if (mocked !== undefined) {
      return mocked as T;
    }
    throw error;
  }

  const text = await response.text();
  if (!text) {
    return undefined as T;
  }

  try {
    return JSON.parse(text) as T;
  } catch {
    return text as T;
  }
}

function isDevBrowser(): boolean {
  const parent = window as Window & { GetParentResourceName?: () => string };
  return !parent.GetParentResourceName && ['localhost', '127.0.0.1'].includes(window.location.hostname);
}

function getDevNuiResponse(eventName: string, data: unknown): unknown {
  if (!isDevBrowser()) {
    return undefined;
  }

  if (eventName === 'onLoad') {
    return devOnLoadPayload;
  }

  if (eventName === 'managerGetBootstrap') {
    return devManagerPayload;
  }

  if (eventName === 'managerGetNicknameState') {
    return devNicknamePayload;
  }

  if (eventName === 'managerSetNickname') {
    const record = data && typeof data === 'object' ? data as AnyRecord : {};
    return {
      ...devNicknamePayload,
      nicknameState: {
        ...devNicknamePayload.nicknameState,
        nickname: String(record.nickname || '')
      }
    };
  }

  if (eventName === 'managerPinNickname') {
    return devNicknamePayload;
  }

  if (eventName === 'radioSendMessage') {
    return { ok: true, echo: data };
  }

  if (eventName.startsWith('manager') || eventName === 'loaded' || eventName === 'typingState' || eventName === 'closeInput' || eventName === 'chatResult') {
    return { ok: true };
  }

  return { ok: true };
}

const devOnLoadPayload: OnLoadPayload = {
  playerServerId: 42,
  activeChannel: 'global',
  channels: [
    { id: 'global', label: 'Global', color: [111, 211, 255], order: 1, visible: true, cycle: true, canSend: true, allowed: true },
    { id: 'staff', label: 'Staff', color: [255, 193, 111], order: 2, visible: true, cycle: true, canSend: true, allowed: true },
    { id: 'radio', label: 'Radio', color: [114, 255, 192], order: 3, visible: true, cycle: true, canSend: true, allowed: true },
    { id: 'whisper', label: 'Whisper', color: [244, 150, 255], order: 4, visible: true, cycle: true, canSend: true, allowed: true }
  ],
  tabs: {
    grouping: { global: 0, staff: 0, radio: 1, whisper: 1 },
    order: { global: 1, staff: 2, radio: 3, whisper: 4 },
    hidden: {},
    groupNames: { 1: 'Comms' },
    groupDisplayMode: { 1: 'folder-merged' }
  },
  notifications: {
    toggles: { global: true, staff: true, radio: true, whisper: true }
  },
  features: {
    typing: { enabled: true, allowToggle: true },
    bubbles: { enabled: true, allowToggle: true },
    autoScroll: { enabled: true, allowToggle: true },
    whisperSound: { enabled: true, allowToggle: true, volume: 0.7 },
    distance: { enabled: true, allowToggle: true }
  },
  radio: {
    enabled: true,
    available: true,
    channelId: 'radio',
    selectedSlot: 'primary',
    slots: {
      primary: { slot: 'primary', frequency: '32.5', label: 'Patrol', color: '#72ffc0' },
      secondary: { slot: 'secondary', frequency: '88.1', label: 'Tac', color: '#f6d365' }
    },
    historyByFrequency: {
      '32.5': [
        { frequency: '32.5', sender: 'Unit 42', senderId: 42, message: 'Radio check from the local mock.', timestamp: Date.now(), slot: 'primary' }
      ]
    }
  },
  distance: {
    enabled: true,
    available: true,
    label: 'Normal',
    color: '#72ffc0',
    range: 12,
    percent: 50
  },
  permissions: {
    staff: false,
    admin: false,
    manager: false,
    moderation: {
      builtInReportsEnabled: true,
      canDeleteMessages: false,
      canViewDeletedMessages: true
    }
  },
  ui: {
    fadeTimeout: 9000,
    suggestionLimit: 8,
    separateChannelTabs: true,
    opacity: 95,
    fontFamily: 'inter',
    fontScale: 1,
    autoScrollDefault: true
  }
};

const devManagerPayload: ManagerBootstrap = {
  ok: true,
  resource: 'poodlechat-dev',
  permissions: devOnLoadPayload.permissions,
  playerSettings: {
    opacity: 95,
    soundEnabled: true,
    soundVolume: 0.7,
    bubbles: true,
    typing: true,
    overhead: true,
    autoScroll: true,
    fontFamily: 'inter',
    fontScale: 1,
    tabGrouping: { global: 0, staff: 0, radio: 1, whisper: 1 },
    tabOrder: { global: 1, staff: 2, radio: 3, whisper: 4 },
    hiddenTabs: {},
    hideDeletedMessages: false,
    tabNotifications: { global: true, staff: true, radio: true, whisper: true },
    groupNames: { 1: 'Comms' },
    groupDisplayMode: { 1: 'folder-merged' }
  },
  warnings: ['Local browser mock is active. FiveM callbacks are not being called.']
};

const devNicknamePayload: ManagerBootstrap = {
  ok: true,
  nicknameState: {
    nickname: 'Local Preview',
    history: ['Local Preview', 'Unit 42', 'Downtown Dispatch'],
    pinned: ['Local Preview', 'Unit 42'],
    maxPinned: 5,
    canUse: true
  }
};

export function nuiMessageType(event: MessageEvent): string {
  const source = (event.data || (event as MessageEvent & { detail?: AnyRecord }).detail) as AnyRecord | undefined;
  return typeof source?.type === 'string' ? source.type : '';
}

export function nuiMessageData(event: MessageEvent): AnyRecord {
  const source = (event.data || (event as MessageEvent & { detail?: AnyRecord }).detail) as AnyRecord | undefined;
  return source && typeof source === 'object' ? source : {};
}

export function copyToClipboard(text: string): void {
  const fallbackCopy = () => {
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.left = '-9999px';
    textarea.style.top = '0';
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.select();
    try {
      document.execCommand('copy');
    } catch {
    }
    textarea.remove();
  };

  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).catch(fallbackCopy);
    return;
  }

  fallbackCopy();
}
