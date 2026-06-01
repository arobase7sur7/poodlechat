import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { PointerEvent as ReactPointerEvent } from 'react';
import {
  ArrowLeft,
  ArrowRight,
  ArrowDown,
  ArrowUp,
  Check,
  GripVertical,
  History,
  Layers3,
  Paintbrush,
  Pin,
  PinOff,
  Plus,
  Sparkles,
  Trash2,
  UserRound,
  X,
  Eye,
  EyeOff,
  Bell,
  BellOff
} from 'lucide-react';
import { colorToCss, ensureString, renderRichText } from '../../richText';
import { CHAT_FONT_OPTIONS, normalizeChatFontId, normalizeChatFontScale } from '../../fontOptions';
import {
  asArray,
  asRecord,
  nextUniqueGrouping,
  normalizeOpacity,
  responseReason
} from '../../utils';
import type {
  Channel,
  ManagerBootstrap,
  NicknameState,
  PermissionState,
  PlayerSettings,
  SaveState
} from '../../types';

type PersonalTab = 'profile' | 'appearance' | 'behavior' | 'tabs';
type WorkspaceDropTarget = { groupId: number; beforeChannelId: string };

function stableValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(stableValue);
  }
  if (value && typeof value === 'object') {
    return Object.keys(value as Record<string, unknown>)
      .sort()
      .reduce<Record<string, unknown>>((result, key) => {
        const next = stableValue((value as Record<string, unknown>)[key]);
        if (next !== undefined) {
          result[key] = next;
        }
        return result;
      }, {});
  }
  return value;
}

function comparableSettings(settings: PlayerSettings): unknown {
  return stableValue({
    opacity: normalizeOpacity(settings.opacity, 88),
    soundEnabled: settings.soundEnabled,
    soundVolume: settings.soundVolume,
    bubbles: settings.bubbles,
    typing: settings.typing,
    overhead: settings.overhead,
    autoScroll: settings.autoScroll,
    fontFamily: settings.fontFamily,
    fontScale: settings.fontScale,
    tabGrouping: asRecord(settings.tabGrouping),
    tabOrder: asRecord(settings.tabOrder),
    hiddenTabs: asRecord(settings.hiddenTabs),
    tabNotifications: asRecord(settings.tabNotifications),
    hideDeletedMessages: settings.hideDeletedMessages,
    groupNames: asRecord(settings.groupNames),
    groupDisplayMode: asRecord(settings.groupDisplayMode)
  });
}

function ToggleSwitch({ checked, onChange }: { checked: boolean; onChange: (checked: boolean) => void }) {
  return (
    <label className="pml-switch">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} />
      <span className="pml-slider-round"></span>
    </label>
  );
}

function RangeSlider({
  label,
  value,
  min,
  max,
  step,
  suffix,
  onChange
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step?: number;
  suffix?: string;
  onChange: (value: number) => void;
}) {
  return (
    <div className="pml-range-group">
      <div className="pml-range-header">
        <label>{label}</label>
        <span>{value}{suffix || ''}</span>
      </div>
      <input
        type="range"
        className="pml-range"
        min={min}
        max={max}
        step={step || 1}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
      />
    </div>
  );
}

function channelGroupingFor(channels: Channel[], settings: PlayerSettings): Record<string, number> {
  const grouping = { ...(asRecord(settings.tabGrouping) as Record<string, number>) };
  let next = nextUniqueGrouping(channels, grouping);
  channels.forEach((channel) => {
    const groupId = Number(grouping[channel.id]);
    if (!Number.isFinite(groupId) || groupId <= 0) {
      grouping[channel.id] = next;
      next += 1;
    }
  });
  return grouping;
}

export default function ManagerPanel({
  open,
  channels,
  permissions,
  playerSettings,
  managerState,
  onClose,
  onRefresh,
  onSavePlayerSettings,
  onManagerRequest,
  returnToChat
}: {
  open: boolean;
  channels: Channel[];
  permissions: PermissionState;
  playerSettings: PlayerSettings;
  managerState: ManagerBootstrap;
  onClose: (returnToChat?: boolean) => void;
  onRefresh: () => Promise<void>;
  onSavePlayerSettings: (settings: PlayerSettings) => void;
  onManagerRequest: (name: string, payload?: unknown) => Promise<ManagerBootstrap>;
  returnToChat: boolean;
}) {
  const [localSettings, setLocalSettings] = useState<PlayerSettings>(playerSettings);
  const [settingsStatus, setSettingsStatus] = useState<SaveState>({});
  
  const [activeTab, setActiveTab] = useState<PersonalTab>('profile');
  
  const [dragChannel, setDragChannel] = useState('');
  const [dragTarget, setDragTarget] = useState<WorkspaceDropTarget | null>(null);
  const [dragStartPosition, setDragStartPosition] = useState({ x: 0, y: 0 });
  const [extraGroups, setExtraGroups] = useState<number[]>([]);
  const [groupOrder, setGroupOrder] = useState<Record<number, number>>({});
  const [nicknameState, setNicknameState] = useState<NicknameState>({});
  const [nicknameDraft, setNicknameDraft] = useState('');
  const dragGhostRef = useRef<HTMLDivElement | null>(null);

  const grouping = useMemo(() => channelGroupingFor(channels, localSettings), [channels, localSettings]);
  const order = useMemo(() => {
    const source = asRecord(localSettings.tabOrder) as Record<string, number>;
    const result: Record<string, number> = {};
    channels.forEach((channel, index) => {
      const value = Number(source[channel.id]);
      result[channel.id] = Number.isFinite(value) && value > 0 ? value : Number(channel.order || index + 1);
    });
    return result;
  }, [channels, localSettings.tabOrder]);
  
  const groups = useMemo(() => {
    const grouped = new Map<number, Channel[]>();
    extraGroups.forEach((groupId) => grouped.set(groupId, grouped.get(groupId) || []));
    channels.forEach((channel) => {
      const groupId = Number(grouping[channel.id]) || 0;
      grouped.set(groupId, [...(grouped.get(groupId) || []), channel]);
    });
    return Array.from(grouped.entries())
      .map(([groupId, groupChannels]) => [
        groupId,
        [...groupChannels].sort((a, b) => (order[a.id] || 0) - (order[b.id] || 0))
      ] as [number, Channel[]])
      .sort(([aId, aChannels], [bId, bChannels]) => {
        const aFirst = groupOrder[aId] ?? (aChannels[0] ? order[aChannels[0].id] || aId : aId + 1000);
        const bFirst = groupOrder[bId] ?? (bChannels[0] ? order[bChannels[0].id] || bId : bId + 1000);
        return aFirst - bFirst;
      });
  }, [channels, extraGroups, groupOrder, grouping, order]);

  const fontId = normalizeChatFontId(localSettings.fontFamily);
  const fontScale = normalizeChatFontScale(localSettings.fontScale);
  const draggedChannelDef = useMemo(() => channels.find((channel) => channel.id === dragChannel) || null, [channels, dragChannel]);
  const pinnedNicknames = asArray<string>(nicknameState.pinned).filter(Boolean).slice(0, Number(nicknameState.maxPinned) || 5);
  const nicknameHistoryRaw = asArray<string>(nicknameState.history).filter(Boolean);
  const uniqueNicknameHistory = Array.from(new Set(nicknameHistoryRaw));
  const hasUnsavedSettings = useMemo(
    () => JSON.stringify(comparableSettings(localSettings)) !== JSON.stringify(comparableSettings(playerSettings)),
    [localSettings, playerSettings]
  );
  const hasUnsavedNickname = nicknameDraft.trim() !== ensureString(nicknameState.nickname);
  const hasUnsavedChanges = hasUnsavedSettings || hasUnsavedNickname;

  const refreshNicknameState = useCallback(async () => {
    const response = await onManagerRequest('managerGetNicknameState', {});
    if (response.ok === false) {
      setSettingsStatus({ error: responseReason(response, 'Nickname state could not be loaded') });
      return;
    }
    const state = asRecord(response.nicknameState || response) as NicknameState;
    setNicknameState(state);
    setNicknameDraft(ensureString(state.nickname));
    setSettingsStatus({});
  }, [onManagerRequest]);

  useEffect(() => {
    setLocalSettings(playerSettings);
  }, [playerSettings]);

  useEffect(() => {
    if (open) {
      void refreshNicknameState();
    }
  }, [open, refreshNicknameState]);

  if (!open) return null;

  const saveSettings = (settingsOverride?: PlayerSettings) => {
    const nextSettings = {
      ...(settingsOverride || localSettings),
      opacity: normalizeOpacity((settingsOverride || localSettings).opacity, 88)
    };
    setSettingsStatus({ pending: 'Saving settings...' });
    setLocalSettings(nextSettings);
    onSavePlayerSettings(nextSettings);
    setTimeout(() => setSettingsStatus({ ok: 'Settings saved' }), 500);
    setTimeout(() => setSettingsStatus({}), 3000);
  };

  const saveNickname = async (value = nicknameDraft) => {
    setSettingsStatus({ pending: 'Saving nickname...' });
    const response = await onManagerRequest('managerSetNickname', { nickname: value.trim() });
    if (response.ok === false) {
      setSettingsStatus({ error: responseReason(response, 'Nickname could not be saved') });
      setTimeout(() => setSettingsStatus({}), 3000);
      return;
    }
    const state = asRecord(response.nicknameState || response) as NicknameState;
    setNicknameState(state);
    setNicknameDraft(ensureString(state.nickname));
    setSettingsStatus({ ok: 'Nickname updated' });
    setTimeout(() => setSettingsStatus({}), 3000);
  };

  const setPinnedNickname = async (nickname: string, pinned: boolean) => {
    const response = await onManagerRequest('managerPinNickname', { nickname, pinned });
    if (response.ok === false) {
      setSettingsStatus({ error: responseReason(response, 'Could not update pinned nickname') });
      setTimeout(() => setSettingsStatus({}), 3000);
      return;
    }
    const state = asRecord(response.nicknameState || response) as NicknameState;
    setNicknameState(state);
    setSettingsStatus({ ok: pinned ? 'Pinned' : 'Unpinned' });
    setTimeout(() => setSettingsStatus({}), 3000);
  };

  const moveChannel = (channelId: string, groupId: number, beforeChannelId = '') => {
    if (!channelId || channelId === beforeChannelId) return;
    setLocalSettings((current) => {
      const next: PlayerSettings = {
        ...current,
        tabGrouping: {
          ...channelGroupingFor(channels, current),
          [channelId]: groupId
        },
        tabOrder: (() => {
          const currentOrder = { ...(asRecord(current.tabOrder) as Record<string, number>) };
          const currentGrouping = { ...channelGroupingFor(channels, current), [channelId]: groupId };
          const orderedIds = channels
            .filter((channel) => channel.id !== channelId)
            .sort((a, b) => (Number(currentOrder[a.id]) || Number(a.order) || 0) - (Number(currentOrder[b.id]) || Number(b.order) || 0))
            .map((channel) => channel.id);
          let insertAt = orderedIds.length;
          if (beforeChannelId) {
            const beforeIndex = orderedIds.indexOf(beforeChannelId);
            insertAt = beforeIndex >= 0 ? beforeIndex : orderedIds.length;
          } else {
            const lastInGroup = orderedIds.reduce((lastIndex, id, index) => (
              Number(currentGrouping[id]) === Number(groupId) ? index : lastIndex
            ), -1);
            if (lastInGroup >= 0) {
              insertAt = lastInGroup + 1;
            } else {
              const targetGroupIndex = groups.findIndex(([targetGroupId]) => targetGroupId === groupId);
              const nextGroupWithChannels = targetGroupIndex >= 0
                ? groups.slice(targetGroupIndex + 1).find(([, groupChannels]) => groupChannels.some((channel) => channel.id !== channelId))
                : undefined;
              const nextGroupFirstChannel = nextGroupWithChannels?.[1].find((channel) => channel.id !== channelId);
              const nextGroupIndex = nextGroupFirstChannel ? orderedIds.indexOf(nextGroupFirstChannel.id) : -1;
              insertAt = nextGroupIndex >= 0 ? nextGroupIndex : orderedIds.length;
            }
          }
          orderedIds.splice(insertAt, 0, channelId);
          orderedIds.forEach((id, index) => {
            currentOrder[id] = index + 1;
          });
          return currentOrder;
        })()
      };
      window.setTimeout(() => saveSettings(next), 0);
      return next;
    });
  };

  const moveChannelWithinGroup = (channelId: string, direction: -1 | 1) => {
    setLocalSettings((current) => {
      const currentGrouping = channelGroupingFor(channels, current);
      const groupId = Number(currentGrouping[channelId]) || 0;
      const currentOrder = { ...(asRecord(current.tabOrder) as Record<string, number>) };
      const peers = channels
        .filter((channel) => Number(currentGrouping[channel.id]) === groupId)
        .sort((a, b) => (Number(currentOrder[a.id]) || Number(a.order) || 0) - (Number(currentOrder[b.id]) || Number(b.order) || 0));
      const peerIndex = peers.findIndex((channel) => channel.id === channelId);
      const swapWith = peers[peerIndex + direction];
      if (!swapWith) {
        return current;
      }

      const orderedIds = [...channels]
        .sort((a, b) => (Number(currentOrder[a.id]) || Number(a.order) || 0) - (Number(currentOrder[b.id]) || Number(b.order) || 0))
        .map((channel) => channel.id);
      const currentIndex = orderedIds.indexOf(channelId);
      const swapIndex = orderedIds.indexOf(swapWith.id);
      if (currentIndex < 0 || swapIndex < 0) {
        return current;
      }
      orderedIds[currentIndex] = swapWith.id;
      orderedIds[swapIndex] = channelId;
      orderedIds.forEach((id, index) => {
        currentOrder[id] = index + 1;
      });

      const next: PlayerSettings = {
        ...current,
        tabGrouping: currentGrouping,
        tabOrder: currentOrder
      };
      window.setTimeout(() => saveSettings(next), 0);
      return next;
    });
  };

  const resolvePointerDropTarget = (clientX: number, clientY: number, movingChannelId: string): WorkspaceDropTarget | null => {
    if (typeof document === 'undefined' || typeof document.elementsFromPoint !== 'function') {
      return null;
    }

    const elements = document.elementsFromPoint(clientX, clientY);
    for (const element of elements) {
      if (!(element instanceof HTMLElement)) {
        continue;
      }
      const channelElement = element.closest('[data-channel-id][data-group-id]');
      if (!(channelElement instanceof HTMLElement)) {
        continue;
      }
      const beforeChannelId = ensureString(channelElement.dataset.channelId);
      const groupId = Number(channelElement.dataset.groupId);
      if (beforeChannelId === movingChannelId) {
        return null;
      }
      if (beforeChannelId && Number.isFinite(groupId) && groupId >= 0) {
        return { groupId, beforeChannelId };
      }
    }

    for (const element of elements) {
      if (!(element instanceof HTMLElement)) {
        continue;
      }
      const groupElement = element.closest('.pml-group[data-group-id], .pml-group-content[data-group-id], .pml-empty-drop[data-group-id]');
      if (!(groupElement instanceof HTMLElement)) {
        continue;
      }
      const groupId = Number(groupElement.dataset.groupId);
      if (Number.isFinite(groupId) && groupId >= 0) {
        return { groupId, beforeChannelId: '' };
      }
    }

    return null;
  };

  const setDragGhostPosition = (clientX: number, clientY: number) => {
    const ghost = dragGhostRef.current;
    if (ghost) {
      ghost.style.transform = `translate3d(${Math.round(clientX + 12)}px, ${Math.round(clientY + 12)}px, 0)`;
    }
  };

  const setNextDragTarget = (target: WorkspaceDropTarget | null) => {
    setDragTarget((current) => (
      current?.groupId === target?.groupId && current?.beforeChannelId === target?.beforeChannelId
        ? current
        : target
    ));
  };

  const beginChannelPointerDrag = (event: ReactPointerEvent<HTMLDivElement>, channelId: string) => {
    if (event.pointerType === 'mouse' && event.button !== 0) {
      return;
    }
    if (event.target instanceof HTMLElement && event.target.closest('button, select, input, textarea, a')) {
      return;
    }
    event.preventDefault();
    if (typeof event.currentTarget.setPointerCapture === 'function') {
      event.currentTarget.setPointerCapture(event.pointerId);
    }
    setDragStartPosition({ x: event.clientX + 12, y: event.clientY + 12 });
    setDragChannel(channelId);
    setNextDragTarget(null);
    window.requestAnimationFrame(() => setDragGhostPosition(event.clientX, event.clientY));
  };

  const updateChannelPointerDrag = (event: ReactPointerEvent<HTMLDivElement>, fallbackChannelId: string) => {
    const channelId = dragChannel || fallbackChannelId;
    if (!channelId) {
      return;
    }
    setDragGhostPosition(event.clientX, event.clientY);
    setNextDragTarget(resolvePointerDropTarget(event.clientX, event.clientY, channelId));
  };

  const finishChannelPointerDrag = (event: ReactPointerEvent<HTMLDivElement>, fallbackChannelId: string) => {
    const channelId = dragChannel || fallbackChannelId;
    if (!channelId) {
      return;
    }
    const target = resolvePointerDropTarget(event.clientX, event.clientY, channelId);
    if (typeof event.currentTarget.hasPointerCapture === 'function' && event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    setDragChannel('');
    setNextDragTarget(null);
    if (target) {
      moveChannel(channelId, target.groupId, target.beforeChannelId);
    }
  };

  const cancelChannelPointerDrag = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (typeof event.currentTarget.hasPointerCapture === 'function' && event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    setDragChannel('');
    setNextDragTarget(null);
  };

  const createGroup = () => {
    const groupId = Math.max(0, ...Object.values(grouping).map((value) => Number(value) || 0), ...extraGroups) + 1;
    setExtraGroups((current) => [...current, groupId]);
    setGroupOrder((current) => ({
      ...current,
      [groupId]: Math.max(0, ...Object.values(current), groups.length) + 1
    }));
    saveSettings({
      ...localSettings,
      groupNames: {
        ...(localSettings.groupNames || {}),
        [groupId]: `Group ${groupId}`
      },
      groupDisplayMode: {
        ...(localSettings.groupDisplayMode || {}),
        [groupId]: 'merged'
      }
    });
  };

  const deleteEmptyGroup = (groupId: number) => {
    setExtraGroups((current) => current.filter((entry) => entry !== groupId));
    setGroupOrder((current) => {
      const next = { ...current };
      delete next[groupId];
      return next;
    });
  };

  const moveGroup = (groupId: number, direction: -1 | 1) => {
    const currentIndex = groups.findIndex(([id]) => id === groupId);
    const target = groups[currentIndex + direction];
    if (currentIndex < 0 || !target) {
      return;
    }

    const nextGroups = [...groups];
    const targetIndex = currentIndex + direction;
    [nextGroups[currentIndex], nextGroups[targetIndex]] = [nextGroups[targetIndex], nextGroups[currentIndex]];

    setGroupOrder(() => nextGroups.reduce<Record<number, number>>((result, [id], index) => {
      result[id] = index + 1;
      return result;
    }, {}));

    const orderedIds = nextGroups.flatMap(([, groupChannels]) => groupChannels.map((channel) => channel.id));
    if (orderedIds.length === 0) {
      return;
    }

    const nextOrder = { ...(asRecord(localSettings.tabOrder) as Record<string, number>) };
    orderedIds.forEach((id, index) => {
      nextOrder[id] = index + 1;
    });
    saveSettings({
      ...localSettings,
      tabGrouping: grouping,
      tabOrder: nextOrder
    });
  };

  const requestClose = () => {
    if (hasUnsavedChanges && !window.confirm('You have unsaved chat settings. Close without saving?')) {
      return;
    }
    onClose(returnToChat);
  };

  return (
    <div className={`pml-backdrop ${open ? 'is-open' : ''}`}>
      <div className="pml-modal">
        {/* Left Sidebar */}
        <aside className="pml-sidebar">
          <div className="pml-sidebar-header">
            <h1>Settings</h1>
            <p>PoodleChat Premium</p>
          </div>
          
          <nav className="pml-nav">
            <button className={`pml-nav-btn ${activeTab === 'profile' ? 'active' : ''}`} onClick={() => setActiveTab('profile')}>
              <UserRound size={16} /> Profile
            </button>
            <button className={`pml-nav-btn ${activeTab === 'appearance' ? 'active' : ''}`} onClick={() => setActiveTab('appearance')}>
              <Paintbrush size={16} /> Appearance
            </button>
            <button className={`pml-nav-btn ${activeTab === 'behavior' ? 'active' : ''}`} onClick={() => setActiveTab('behavior')}>
              <Sparkles size={16} /> Behavior
            </button>
            <button className={`pml-nav-btn ${activeTab === 'tabs' ? 'active' : ''}`} onClick={() => setActiveTab('tabs')}>
              <Layers3 size={16} /> Tab Workspace
            </button>
          </nav>

          <div className="pml-sidebar-footer">
            <button className="pml-icon-btn" onClick={() => saveSettings()} title="Save settings">
              <Check size={16} />
            </button>
            <button className="pml-icon-btn" style={{ marginLeft: 'auto' }} onClick={requestClose} title="Close">
              <X size={16} />
            </button>
          </div>
        </aside>

        {/* Right Content */}
        <main className="pml-content">
          
          <div className={`pml-status-bar ${settingsStatus.pending ? 'pending show' : settingsStatus.error ? 'error show' : settingsStatus.ok ? 'ok show' : ''}`}>
            {settingsStatus.pending || settingsStatus.error || settingsStatus.ok}
          </div>

          {activeTab === 'profile' && (
            <div className="pml-tab-content">
              <div className="pml-section-title">
                <h2>Character Profile</h2>
                <p>Manage your identity and quick-switch nicknames.</p>
              </div>

              <div className="pml-card">
                <div className="pml-card-header">
                  <div>
                    <h3>Current Identity</h3>
                    <p>{ensureString(nicknameState.nickname) ? 'Using custom nickname' : 'Using character name'}</p>
                  </div>
                  <History size={18} style={{ opacity: 0.5 }} />
                </div>
                
                <div className="pml-input-group">
                  <label>Display Name (Use formatting like ^2 for color)</label>
                  <input 
                    className="pml-input" 
                    value={nicknameDraft} 
                    placeholder={ensureString(nicknameState.nickname, 'Character Name')} 
                    maxLength={40} 
                    onChange={(e) => setNicknameDraft(e.target.value)} 
                  />
                </div>
                
                <div className="pml-button-group">
                  <button className="pml-button primary" onClick={() => saveNickname()}><Check size={14} /> Apply</button>
                  <button className="pml-button" onClick={() => saveNickname('')}>Clear</button>
                  {ensureString(nicknameState.nickname) && (
                    <button 
                      className="pml-button" 
                      onClick={() => setPinnedNickname(ensureString(nicknameState.nickname), !pinnedNicknames.includes(ensureString(nicknameState.nickname)))}
                    >
                      {pinnedNicknames.includes(ensureString(nicknameState.nickname)) ? <PinOff size={14} /> : <Pin size={14} />}
                      {pinnedNicknames.includes(ensureString(nicknameState.nickname)) ? 'Unpin' : 'Pin'}
                    </button>
                  )}
                </div>
              </div>

              <div className="pml-card">
                <div className="pml-card-header" style={{ marginBottom: '0.5rem' }}>
                  <div>
                    <h3>Pinned & History</h3>
                    <p>Quick access to previous identities.</p>
                  </div>
                </div>
                
                <div style={{ marginBottom: '1rem' }}>
                  <label style={{ fontSize: '0.75rem', color: 'rgba(255,255,255,0.5)' }}>Pinned</label>
                  <div className="pml-pill-list">
                    {pinnedNicknames.map((nickname) => (
                      <div className="pml-pill pinned" key={`pinned:${nickname}`}>
                        <button className="pml-pill-btn" onClick={() => saveNickname(nickname)}>
                          <Pin size={12} style={{ marginRight: '0.3rem' }} /> 
                          <span dangerouslySetInnerHTML={{ __html: renderRichText(nickname) }} />
                        </button>
                        <button className="pml-pill-btn" style={{ marginLeft: '0.4rem', borderLeft: '1px solid rgba(255,255,255,0.2)', paddingLeft: '0.4rem' }} onClick={() => setPinnedNickname(nickname, false)}>
                          <X size={12} />
                        </button>
                      </div>
                    ))}
                    {pinnedNicknames.length === 0 && <span style={{ fontSize: '0.75rem', color: 'rgba(255,255,255,0.3)', padding: '0.25rem 0' }}>No pinned names</span>}
                  </div>
                </div>

                <div>
                  <label style={{ fontSize: '0.75rem', color: 'rgba(255,255,255,0.5)' }}>History</label>
                  <div className="pml-pill-list">
                    {uniqueNicknameHistory.map((nickname) => (
                      <div className="pml-pill" key={`history:${nickname}`}>
                        <button className="pml-pill-btn" onClick={() => saveNickname(nickname)}>
                          <span dangerouslySetInnerHTML={{ __html: renderRichText(nickname) }} />
                        </button>
                        <button className="pml-pill-btn" style={{ marginLeft: '0.4rem', borderLeft: '1px solid rgba(255,255,255,0.2)', paddingLeft: '0.4rem' }} onClick={() => setPinnedNickname(nickname, !pinnedNicknames.includes(nickname))}>
                          {pinnedNicknames.includes(nickname) ? <PinOff size={12} /> : <Pin size={12} />}
                        </button>
                      </div>
                    ))}
                    {uniqueNicknameHistory.length === 0 && <span style={{ fontSize: '0.75rem', color: 'rgba(255,255,255,0.3)', padding: '0.25rem 0' }}>No history</span>}
                  </div>
                </div>
              </div>
            </div>
          )}

          {activeTab === 'appearance' && (
            <div className="pml-tab-content">
              <div className="pml-section-title">
                <h2>Appearance</h2>
                <p>Customize the chat overlay visibility and typography.</p>
              </div>

              <div className="pml-card">
                <RangeSlider 
                  label="Panel Background" 
                  min={70} max={100} 
                  value={normalizeOpacity(localSettings.opacity, 88)} 
                  suffix="%" 
                  onChange={(val) => setLocalSettings(c => ({ ...c, opacity: val }))} 
                />
                <RangeSlider 
                  label="Interface Volume" 
                  min={0} max={1} step={0.05} 
                  value={Number(localSettings.soundVolume ?? 0.65)} 
                  onChange={(val) => setLocalSettings(c => ({ ...c, soundVolume: val }))} 
                />
              </div>

              <div className="pml-card">
                <div className="pml-input-group">
                  <label>Typeface</label>
                  <select 
                    className="pml-select" 
                    value={fontId} 
                    onChange={(e) => setLocalSettings(c => ({ ...c, fontFamily: e.target.value }))}
                  >
                    {CHAT_FONT_OPTIONS.map((opt) => <option key={opt.id} value={opt.id}>{opt.label}</option>)}
                  </select>
                </div>
                
                <RangeSlider 
                  label="Text Scale" 
                  min={50} max={150} 
                  value={Math.round(fontScale * 100)} 
                  suffix="%" 
                  onChange={(val) => setLocalSettings(c => ({ ...c, fontScale: val / 100 }))} 
                />

                <div className="pml-font-preview" style={{ fontFamily: CHAT_FONT_OPTIONS.find(o => o.id === fontId)?.css, fontSize: `${fontScale}em` }}>
                  <span dangerouslySetInnerHTML={{ __html: renderRichText('^2Premium ^#68d8a7typography ^7preview :)') }} />
                </div>
              </div>
            </div>
          )}

          {activeTab === 'behavior' && (
            <div className="pml-tab-content">
              <div className="pml-section-title">
                <h2>Behavior</h2>
                <p>Tune how chat interacts with you during gameplay.</p>
              </div>

              <div className="pml-card" style={{ padding: '0.5rem 1.5rem' }}>
                <div className="pml-toggle-row">
                  <span>Notification Sound</span>
                  <ToggleSwitch checked={localSettings.soundEnabled !== false} onChange={(v) => setLocalSettings(c => ({ ...c, soundEnabled: v }))} />
                </div>
                <div className="pml-toggle-row">
                  <span>Show Chat Bubbles</span>
                  <ToggleSwitch checked={localSettings.bubbles !== false} onChange={(v) => setLocalSettings(c => ({ ...c, bubbles: v }))} />
                </div>
                <div className="pml-toggle-row">
                  <span>Typing Indicators</span>
                  <ToggleSwitch checked={localSettings.typing !== false} onChange={(v) => setLocalSettings(c => ({ ...c, typing: v }))} />
                </div>
                <div className="pml-toggle-row">
                  <span>Overhead Chat (3D)</span>
                  <ToggleSwitch checked={localSettings.overhead === true} onChange={(v) => setLocalSettings(c => ({ ...c, overhead: v }))} />
                </div>
                <div className="pml-toggle-row">
                  <span>Auto-scroll to bottom</span>
                  <ToggleSwitch checked={localSettings.autoScroll !== false} onChange={(v) => setLocalSettings(c => ({ ...c, autoScroll: v }))} />
                </div>
                {permissions.moderation?.canViewDeletedMessages && (
                  <div className="pml-toggle-row">
                    <span>Hide Deleted Messages</span>
                    <ToggleSwitch checked={localSettings.hideDeletedMessages === true} onChange={(v) => setLocalSettings(c => ({ ...c, hideDeletedMessages: v }))} />
                  </div>
                )}
              </div>
            </div>
          )}

          {activeTab === 'tabs' && (
            <div className="pml-tab-content">
              <div className="pml-section-title" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                <div>
                  <h2>Tab Workspace</h2>
                  <p>Organize your channels into groups. Customize display names and modes.</p>
                </div>
                <button className="pml-button" onClick={createGroup}>
                  <Plus size={14} /> New Group
                </button>
              </div>

              <div className="pml-board">
                {groups.map(([groupId, groupChannels]) => (
                  <div 
                    className={`pml-group ${dragChannel ? 'pml-drag-ready' : ''}${dragTarget?.groupId === groupId ? ' pml-drop-target' : ''}`} 
                    key={`group:${groupId}`}
                    data-group-id={groupId}
                  >
                    <div className="pml-group-header">
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', flex: 1 }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                          <input 
                            className="pml-input" 
                            style={{ padding: '0.35rem 0.6rem', fontSize: '0.85rem', background: 'rgba(0,0,0,0.3)', width: '250px' }}
                            value={asRecord(localSettings.groupNames || {})[groupId] as string || `Group ${groupId}`}
                            onChange={(e) => setLocalSettings(c => ({
                              ...c,
                              groupNames: { ...(c.groupNames || {}), [groupId]: e.target.value }
                            }))}
                            placeholder={`Group ${groupId}`}
                          />
                        </div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                          <label style={{ fontSize: '0.75rem', color: 'rgba(255,255,255,0.6)' }}>Display Mode:</label>
                          <select 
                            className="pml-select"
                            style={{ padding: '0.2rem 1.8rem 0.2rem 0.6rem', fontSize: '0.75rem', width: '200px' }}
                            value={asRecord(localSettings.groupDisplayMode || {})[groupId] as string || 'merged'}
                            onChange={(e) => setLocalSettings(c => ({
                              ...c,
                              groupDisplayMode: { ...(c.groupDisplayMode || {}), [groupId]: e.target.value as 'merged' | 'folder' | 'folder-merged' }
                            }))}
                          >
                            <option value="merged">Merged Messages</option>
                            <option value="folder">Sub-tabs (Selected Tab)</option>
                            <option value="folder-merged">Sub-tabs + Merged Messages</option>
                          </select>
                        </div>
                      </div>

                      <div style={{ marginLeft: '1rem', display: 'flex', alignItems: 'center', gap: '1rem' }}>
                        <span style={{ fontSize: '0.8rem', color: 'rgba(255,255,255,0.4)' }}>
                          {groupChannels.length} tab{groupChannels.length !== 1 && 's'}
                        </span>
                        <div className="pml-group-controls">
                          <button
                            className="pml-pill-btn"
                            onClick={() => moveGroup(groupId, -1)}
                            disabled={groups[0]?.[0] === groupId}
                            title="Move group up"
                          >
                            <ArrowUp size={14} />
                          </button>
                          <button
                            className="pml-pill-btn"
                            onClick={() => moveGroup(groupId, 1)}
                            disabled={groups[groups.length - 1]?.[0] === groupId}
                            title="Move group down"
                          >
                            <ArrowDown size={14} />
                          </button>
                        </div>
                        {groupChannels.length === 0 && (
                          <button className="pml-button danger" style={{ padding: '0.4rem 0.6rem' }} onClick={() => deleteEmptyGroup(groupId)} title="Delete Group">
                            <Trash2 size={16} /> Delete
                          </button>
                        )}
                      </div>
                    </div>
                    
                    <div className="pml-group-content" data-group-id={groupId} style={{ flexDirection: 'row', flexWrap: 'wrap', gap: '0.5rem' }}>
                      {groupChannels.length === 0 && <div className="pml-empty-drop" data-group-id={groupId} style={{ width: '100%' }}>Drop here</div>}
                      
                      {groupChannels.map((channel) => (
                        <div 
                          key={`group-channel:${channel.id}`} 
                          className={`pml-channel-item${dragChannel === channel.id ? ' pml-dragging' : ''}${dragTarget?.groupId === groupId && dragTarget.beforeChannelId === channel.id ? ' pml-insert-before' : ''}`} 
                          style={{ width: 'auto', minWidth: '150px' }}
                          data-group-id={groupId}
                          data-channel-id={channel.id}
                          onPointerDown={(event) => beginChannelPointerDrag(event, channel.id)}
                          onPointerMove={(event) => updateChannelPointerDrag(event, channel.id)}
                          onPointerUp={(event) => finishChannelPointerDrag(event, channel.id)}
                          onPointerCancel={cancelChannelPointerDrag}
                        >
                          <div className="pml-channel-main">
                            <GripVertical size={14} style={{ opacity: 0.3 }} />
                            <span style={{ color: colorToCss(channel.color) }}>{channel.label}</span>
                          </div>
                          
                          <div className="pml-channel-controls">
                            <button
                              className="pml-pill-btn"
                              onClick={() => moveChannelWithinGroup(channel.id, -1)}
                              title="Move earlier"
                            >
                              <ArrowLeft size={14} />
                            </button>
                            <button
                              className="pml-pill-btn"
                              onClick={() => moveChannelWithinGroup(channel.id, 1)}
                              title="Move later"
                            >
                              <ArrowRight size={14} />
                            </button>
                            <select
                              className="pml-channel-group-select"
                              value={groupId}
                              onChange={(e) => {
                                const nextGroupId = Number(e.target.value);
                                if (nextGroupId !== groupId) {
                                  moveChannel(channel.id, nextGroupId);
                                }
                              }}
                              title="Move to group"
                            >
                              {groups.map(([targetGroupId]) => (
                                <option key={`move-target:${channel.id}:${targetGroupId}`} value={targetGroupId}>
                                  {ensureString(asRecord(localSettings.groupNames || {})[targetGroupId], `Group ${targetGroupId}`)}
                                </option>
                              ))}
                            </select>
                            <button 
                              className="pml-pill-btn" 
                              style={{ color: asRecord(localSettings.hiddenTabs)[channel.id] ? 'rgba(255,255,255,0.3)' : '#fff' }}
                              onClick={() => setLocalSettings(c => ({ ...c, hiddenTabs: { ...(c.hiddenTabs || {}), [channel.id]: !asRecord(c.hiddenTabs)[channel.id] } }))}
                              title="Toggle Visibility"
                            >
                              {asRecord(localSettings.hiddenTabs)[channel.id] ? <EyeOff size={14} /> : <Eye size={14} />}
                            </button>
                            <button 
                              className="pml-pill-btn" 
                              style={{ color: asRecord(localSettings.tabNotifications)[channel.id] !== false ? '#68d8a7' : 'rgba(255,255,255,0.3)' }}
                              onClick={() => setLocalSettings(c => ({ ...c, tabNotifications: { ...(c.tabNotifications || {}), [channel.id]: asRecord(c.tabNotifications)[channel.id] === false } }))}
                              title="Toggle Notifications"
                            >
                              {asRecord(localSettings.tabNotifications)[channel.id] !== false ? <Bell size={14} /> : <BellOff size={14} />}
                            </button>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

        </main>
      </div>
      {draggedChannelDef && (
        <div
          ref={dragGhostRef}
          className="pml-drag-ghost"
          style={{
            transform: `translate3d(${Math.round(dragStartPosition.x)}px, ${Math.round(dragStartPosition.y)}px, 0)`
          }}
        >
          <GripVertical size={14} />
          <span style={{ color: colorToCss(draggedChannelDef.color) }}>{draggedChannelDef.label}</span>
        </div>
      )}
    </div>
  );
}
