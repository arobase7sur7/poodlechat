import type {
  AnyRecord,
  AutoMessageRecord,
  Channel,
  CommandBlockRecord,
  CommandRegistryRecord,
  CommandRouteRecord,
  CustomCommandRecord,
  ManagerBootstrap,
  PermissionState,
  RadioMessage,
  RadioState,
  Suggestion
} from './types';
import { ensureString } from './richText';

export function asRecord(value: unknown): AnyRecord {
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as AnyRecord) : {};
}

export function asArray<T = unknown>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

export function normalizeChannels(rawChannels: unknown): Channel[] {
  return asArray<Channel>(rawChannels)
    .filter((channel) => channel && typeof channel.id === 'string')
    .map((channel) => ({
      id: channel.id,
      label: ensureString(channel.label, channel.id),
      color: channel.color || [255, 255, 255],
      order: Number.isFinite(Number(channel.order)) ? Number(channel.order) : 100,
      visible: channel.visible !== false,
      cycle: channel.cycle !== false,
      canSend: channel.canSend !== false,
      allowed: channel.allowed !== false,
      maxHistory: Number(channel.maxHistory) || 250
    }))
    .sort((a, b) => Number(a.order || 0) - Number(b.order || 0));
}

export function normalizeOpacity(value: unknown, fallback = 88): number {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return fallback;
  }
  if (numeric > 0 && numeric <= 1) {
    return Math.round(numeric * 100);
  }
  return Math.max(70, Math.min(100, Math.round(numeric)));
}

export function normalizeSuggestion(raw: unknown): Suggestion | null {
  if (Array.isArray(raw)) {
    const name = ensureString(raw[0]);
    if (!name) {
      return null;
    }
    return {
      name,
      help: ensureString(raw[1]),
      params: asArray(raw[2])
    };
  }
  const record = asRecord(raw);
  const name = ensureString(record.name);
  if (!name) {
    return null;
  }
  return {
    ...record,
    name,
    help: ensureString(record.help),
    params: asArray(record.params)
  } as Suggestion;
}

export function normalizePermissions(raw: unknown): PermissionState {
  if (typeof raw === 'string') {
    try {
      return JSON.parse(raw) as PermissionState;
    } catch {
      return {};
    }
  }
  return asRecord(raw) as PermissionState;
}

export function truthyCapability(permissions: PermissionState, key: string): boolean {
  const capabilities = asRecord(permissions.capabilities);
  return permissions.manager === true || capabilities[key] === true;
}

export function canUseManager(permissions: PermissionState): boolean {
  return permissions.manager === true || permissions.admin === true || permissions.canManagePoodleChat === true || truthyCapability(permissions, 'chat.manager');
}

export function canUseStaffTools(permissions: PermissionState): boolean {
  return canUseManager(permissions) || permissions.staff === true || asRecord(permissions.moderation).canDeleteMessages === true;
}

export function normalizeRadioState(raw: unknown): RadioState {
  const source = asRecord(raw);
  const slots = asRecord(source.slots);
  return {
    enabled: source.enabled === true,
    available: source.available === true,
    resource: ensureString(source.resource, '7-radio'),
    channelId: ensureString(source.channelId, 'radio'),
    active: ensureString(source.active, 'primary') === 'secondary' ? 'secondary' : 'primary',
    selectedSlot: ensureString(source.selectedSlot || source.active, 'primary') === 'secondary' ? 'secondary' : 'primary',
    relayLocked: source.relayLocked === true,
    slots: {
      primary: asRecord(slots.primary),
      secondary: asRecord(slots.secondary)
    },
    historyByFrequency: asRecord(source.historyByFrequency) as Record<string, RadioMessage[]>
  };
}

export function getRadioSlot(radio: RadioState, slot: 'primary' | 'secondary') {
  return asRecord(radio.slots?.[slot]);
}

export function compactStringList(value: string): string[] {
  return value
    .split(',')
    .map((item) => item.trim().replace(/^\//, '').toLowerCase())
    .filter(Boolean);
}

export function parseJsonField(value: string, fallback: unknown): unknown {
  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}

export function nextUniqueGrouping(channels: Channel[], grouping: Record<string, number>): number {
  return channels.reduce((highest, channel) => Math.max(highest, Number(grouping[channel.id]) || 0), 0) + 1;
}

export function hexToRgbArray(value: unknown): number[] | undefined {
  if (Array.isArray(value)) {
    const parsed = value.slice(0, 3).map((entry) => Math.max(0, Math.min(255, Math.round(Number(entry) || 0))));
    return parsed.length === 3 ? parsed : undefined;
  }
  const raw = ensureString(value).trim().replace(/^#/, '');
  const expanded = /^[0-9a-fA-F]{3}$/.test(raw)
    ? raw.split('').map((char) => char + char).join('')
    : raw;
  if (!/^[0-9a-fA-F]{6}$/.test(expanded)) {
    return undefined;
  }
  return [0, 2, 4].map((index) => parseInt(expanded.slice(index, index + 2), 16));
}

export function responseReason(response: unknown, fallback = 'Action failed'): string {
  const record = asRecord(response);
  return ensureString(record.reason || record.error || record.message, fallback);
}

function entriesRecord(value: unknown): Record<string, AnyRecord> {
  const record = asRecord(value);
  const entries = asRecord(record.entries);
  if (Object.keys(entries).length > 0) {
    return entries as Record<string, AnyRecord>;
  }
  return record as Record<string, AnyRecord>;
}

export function commandListFrom(value: unknown): CommandRegistryRecord[] {
  const record = asRecord(value);
  let source: unknown[] = [];
  if (Array.isArray(value)) {
    source = value;
  } else if (Array.isArray(record.registry)) {
    source = record.registry;
  } else if (Array.isArray(record.commandRegistry)) {
    source = record.commandRegistry;
  } else {
    const nested = record.registry || record.commandRegistry || record.items;
    if (nested && typeof nested === 'object') {
      source = Object.entries(asRecord(nested)).map(([name, command]) => ({ ...asRecord(command), name: ensureString(asRecord(command).name || name, name) }));
    } else if (!record.blocks && !record.routes && !record.customCommands) {
      source = Object.entries(record).map(([name, command]) => ({ ...asRecord(command), name: ensureString(asRecord(command).name || name, name) }));
    }
  }
  return source.map((entry) => asRecord(entry) as CommandRegistryRecord).filter((entry) => ensureString(entry.name));
}

export function normalizeCommandBlocks(value: unknown): CommandBlockRecord[] {
  return Object.entries(entriesRecord(value)).map(([command, block]) => ({
    ...(block as CommandBlockRecord),
    command: ensureString(block.command || command, command)
  }));
}

export function normalizeCommandRoutes(value: unknown): CommandRouteRecord[] {
  const source = asRecord(asRecord(value).overrides || value);
  return Object.entries(source).map(([command, route]) => {
    const routeRecord = asRecord(route);
    return {
      ...routeRecord,
      command: ensureString(routeRecord.command || command, command),
      channel: ensureString(routeRecord.channel || routeRecord.to || route)
    };
  }).filter((route) => route.command && route.channel);
}

export function normalizeCustomCommands(value: unknown): CustomCommandRecord[] {
  const source = Array.isArray(value) ? asArray<AnyRecord>(value) : Object.entries(entriesRecord(value)).map(([name, command]) => ({ ...command, name }));
  return source.map((entry) => asRecord(entry) as CustomCommandRecord).filter((entry) => ensureString(entry.name || entry.command));
}

export function normalizeAutoMessages(value: unknown): AutoMessageRecord[] {
  const source = Array.isArray(value) ? asArray<AnyRecord>(value) : Object.entries(asRecord(asRecord(value).items || value)).map(([id, message]) => ({ ...asRecord(message), id }));
  return source
    .map((entry) => {
      const record = asRecord(entry) as AutoMessageRecord;
      return {
        ...record,
        text: ensureString(record.text || record.message)
      };
    })
    .filter((entry) => ensureString(entry.id || entry.label || entry.text));
}

export function normalizeManagerState(managerState: ManagerBootstrap) {
  const commandPolicy = asRecord(managerState.commandPolicy);
  return {
    registry: commandListFrom(managerState.commandRegistry || commandPolicy),
    blocks: normalizeCommandBlocks(managerState.commandBlocks || commandPolicy.blocks),
    routes: normalizeCommandRoutes(managerState.commandRoutes || commandPolicy.routes),
    customCommands: normalizeCustomCommands(managerState.customCommands || commandPolicy.customCommands),
    autoMessages: normalizeAutoMessages(managerState.autoMessages),
    reports: asArray<AnyRecord>(managerState.reports || managerState.recentReports || asRecord(managerState.moderation).reports),
    audit: asArray<AnyRecord>(managerState.audit || managerState.recentAudit || asRecord(managerState.moderation).audit),
    recentMessages: asArray<AnyRecord>(managerState.recentMessages || asRecord(managerState.moderation).recentMessages),
    warnings: asArray<AnyRecord | string>(managerState.warnings)
  };
}
