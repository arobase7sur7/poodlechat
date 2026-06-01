export type AnyRecord = Record<string, unknown>;

export interface Channel {
  id: string;
  label: string;
  color?: number[] | string;
  order?: number;
  visible?: boolean;
  cycle?: boolean;
  canSend?: boolean;
  allowed?: boolean;
  maxHistory?: number;
}

export interface ChatMessage {
  _id?: number;
  messageId?: string;
  channel?: string;
  label?: string;
  color?: number[] | string;
  args?: unknown[];
  text?: string;
  template?: string;
  multiline?: boolean;
  timestamp?: number;
  restored?: boolean;
  metadata?: AnyRecord;
}

export interface SuggestionParam {
  name?: string;
  help?: string;
  type?: string;
  required?: boolean;
}

export interface Suggestion {
  name: string;
  help?: string;
  params?: SuggestionParam[];
  disabled?: boolean;
}

export interface Message3D {
  id: string;
  color: [number, number, number];
  text?: string;
  timeout?: number;
  persistent?: boolean;
  style?: string;
  floatUp?: boolean;
  onScreen?: boolean;
  screenX?: number;
  screenY?: number;
}

export interface PermissionState {
  channels?: Record<string, boolean>;
  moderation?: {
    builtInReportsEnabled?: boolean;
    canDeleteMessages?: boolean;
    canViewDeletedMessages?: boolean;
    [key: string]: unknown;
  };
  staff?: boolean;
  admin?: boolean;
  manager?: boolean;
  capabilities?: Record<string, boolean>;
  [key: string]: unknown;
}

export interface FeatureState {
  typing?: FeatureToggle;
  bubbles?: FeatureToggle;
  autoScroll?: FeatureToggle;
  whisperSound?: FeatureToggle & { mode?: string; volume?: number };
  distance?: FeatureToggle;
  [key: string]: unknown;
}

export interface FeatureToggle {
  enabled?: boolean;
  active?: boolean;
  allowToggle?: boolean;
}

export interface DistanceState {
  enabled?: boolean;
  available?: boolean;
  label?: string;
  color?: string;
  mode?: string;
  range?: number;
  percent?: number;
  [key: string]: unknown;
}

export interface RadioSlot {
  slot?: string;
  frequency?: string | null;
  label?: string;
  color?: string | null;
  relay?: boolean;
}

export interface RadioMessage {
  frequency?: string;
  sender?: string;
  senderId?: number;
  message?: string;
  timestamp?: number;
  slot?: string;
  clientMessageId?: string;
}

export interface RadioState {
  enabled?: boolean;
  available?: boolean;
  resource?: string;
  channelId?: string;
  active?: string;
  selectedSlot?: string;
  relayLocked?: boolean;
  slots?: {
    primary?: RadioSlot;
    secondary?: RadioSlot;
  };
  historyByFrequency?: Record<string, RadioMessage[]>;
}

export interface WhisperTarget {
  id: number;
  name?: string;
  label?: string;
  fivemName?: string;
}

export interface WhisperConversation {
  id: string;
  peerName: string;
  peerId?: number | null;
  peerCharacterId?: string;
  pending?: boolean;
  unread: number;
  lastAt: number;
  messages: ChatMessage[];
}

export interface PlayerSettings {
  opacity?: number;
  soundEnabled?: boolean;
  soundVolume?: number;
  bubbles?: boolean;
  typing?: boolean;
  overhead?: boolean;
  autoScroll?: boolean;
  fontFamily?: string;
  fontScale?: number;
  tabGrouping?: Record<string, number>;
  tabOrder?: Record<string, number>;
  hiddenTabs?: Record<string, boolean>;
  tabNotifications?: Record<string, boolean>;
  hideDeletedMessages?: boolean;
  groupNames?: Record<number, string>;
  groupDisplayMode?: Record<number, "merged" | "folder" | "folder-merged">;
  lastActiveTab?: string;
}

export interface NicknameState {
  nickname?: string;
  history?: string[];
  pinned?: string[];
  maxPinned?: number;
  canUse?: boolean;
  reason?: string;
}

export interface ManagerBootstrap {
  ok?: boolean;
  permissions?: PermissionState;
  dashboard?: AnyRecord;
  runtime?: AnyRecord;
  runtimeAcl?: AnyRecord;
  commandPolicy?: AnyRecord;
  commandBlocks?: AnyRecord;
  commandRoutes?: AnyRecord;
  commandRegistry?: AnyRecord;
  customCommands?: AnyRecord;
  autoMessages?: AnyRecord;
  moderation?: AnyRecord;
  playerSettings?: PlayerSettings;
  nicknameState?: NicknameState;
  reason?: string;
  [key: string]: unknown;
}

export interface CommandRegistryRecord extends AnyRecord {
  name?: string;
  aliases?: unknown[];
  origin?: string;
  side?: string;
  source?: string;
  restricted?: boolean;
  permission?: string;
  enabled?: boolean;
  route?: string;
  channel?: string;
  handlerType?: string;
  notes?: string;
}

export interface CommandBlockRecord extends AnyRecord {
  command?: string;
  enabled?: boolean;
  mode?: string;
  permission?: string;
  redirect?: string;
  message?: string;
  notes?: string;
}

export interface CommandRouteRecord extends AnyRecord {
  command: string;
  channel: string;
}

export interface CustomCommandRecord extends AnyRecord {
  name?: string;
  command?: string;
  aliases?: unknown[];
  enabled?: boolean;
  visible?: boolean;
  staffOnly?: boolean;
  help?: string;
  usage?: string;
  permission?: string;
  cooldown?: number;
  channel?: string;
  actions?: AnyRecord[];
}

export interface AutoMessageRecord extends AnyRecord {
  id?: string;
  enabled?: boolean;
  label?: string;
  text?: string;
  channel?: string;
  interval?: number;
  color?: number[] | string;
  permission?: string;
}

export interface EmojiEntry {
  emoji?: string;
  name?: string;
  category?: string;
  htmlCode?: string[];
  unicode?: string[];
  aliases?: string[];
  search?: string;
  usage?: number;
}

export interface ContextMenuState {
  open: boolean;
  x: number;
  y: number;
  message?: ChatMessage;
}

export interface ReportState {
  open: boolean;
  targetId: string;
  reason: string;
  sourceMessageId: string;
  context?: AnyRecord | null;
}

export interface CustomDraft {
  name: string;
  aliases: string;
  help: string;
  usage: string;
  permission: string;
  cooldown: number;
  usageLimit: number;
  usageScope: string;
  channel: string;
  argumentsJson: string;
  visible: boolean;
  staffOnly: boolean;
  enabled: boolean;
  actions: AnyRecord[];
}

export interface AutoMessageDraft {
  id: string;
  enabled: boolean;
  label: string;
  text: string;
  channel: string;
  interval: number;
  color: string;
  permission: string;
}

export type SaveState = {
  pending?: string;
  ok?: string;
  error?: string;
};

export interface OnLoadPayload {
  playerServerId?: number;
  channels?: Channel[];
  activeChannel?: string;
  tabs?: {
    grouping?: Record<string, number>;
    defaultGrouping?: Record<string, number>;
    groupRelayTargetByChannel?: Record<string, boolean>;
    pinnedByChannel?: Record<string, boolean>;
    hidden?: Record<string, boolean>;
    order?: Record<string, number>;
    groupNames?: Record<number, string>;
    groupDisplayMode?: Record<number, "merged" | "folder" | "folder-merged">;
  };
  notifications?: {
    default?: AnyRecord;
    channels?: Record<string, AnyRecord>;
    toggles?: Record<string, boolean>;
  };
  whispers?: AnyRecord;
  emoji?: AnyRecord;
  emojiPanel?: AnyRecord;
  distance?: DistanceState;
  features?: FeatureState;
  radio?: RadioState;
  permissions?: PermissionState;
  ui?: {
    fadeTimeout?: number;
    suggestionLimit?: number;
    style?: AnyRecord;
    separateChannelTabs?: boolean;
    singleChannelId?: string;
    autoScrollDefault?: boolean;
    opacity?: number;
    fontFamily?: string;
    fontScale?: number;
    templates?: Record<string, string>;
    defaultTemplateId?: string;
    defaultAltTemplateId?: string;
    theme?: AnyRecord;
    messages?: AnyRecord;
    contextMenu?: AnyRecord;
    colorPicker?: AnyRecord;
    animations?: AnyRecord;
    runtime?: AnyRecord;
  };
}
