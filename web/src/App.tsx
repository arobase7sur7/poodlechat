import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type ReactNode,
} from "react";
import {
  Bell,
  BellOff,
  ChevronsDown,
  Clipboard,
  FolderClosed,
  Hash,
  MessageCircle,
  Mic2,
  Palette,
  PanelRightOpen,
  Send,
  Settings,
  Shield,
  SignalHigh,
  SignalLow,
  SignalMedium,
  Smile,
  Trash2,
  Volume2,
  VolumeX,
  X,
} from "lucide-react";
import { copyToClipboard, fetchNui, nuiMessageData } from "./bridge";
import ManagerPanel from "./components/manager/ManagerPanel";
import EmojiPanel from "./components/chat/EmojiPanel";
import HexColorPicker from "./components/chat/HexColorPicker";
import MessageRow, {
  createReportContext,
  messageKey,
} from "./components/chat/MessageRow";
import Suggestions from "./components/chat/Suggestions";
import {
  chatFontCss,
  normalizeChatFontId,
  normalizeChatFontScale,
} from "./fontOptions";
import { useCommandHistory } from "./hooks/useCommandHistory";
import {
  asArray,
  asRecord,
  canUseStaffTools,
  getRadioSlot,
  normalizeChannels,
  normalizeOpacity,
  normalizePermissions,
  normalizeRadioState,
  normalizeSuggestion,
} from "./utils";
import {
  colorToCss,
  ensureString,
  formatTimestamp,
  messageAuthor,
  messageBody,
  messageRawText,
  normalizeMessage,
  renderRichText,
} from "./richText";
import type {
  AnyRecord,
  Channel,
  ChatMessage,
  ContextMenuState,
  DistanceState,
  EmojiEntry,
  FeatureState,
  ManagerBootstrap,
  Message3D,
  OnLoadPayload,
  PermissionState,
  PlayerSettings,
  RadioMessage,
  RadioState,
  ReportState,
  Suggestion,
  SuggestionParam,
  WhisperConversation,
  WhisperTarget,
} from "./types";

const emptyReport: ReportState = {
  open: false,
  targetId: "",
  reason: "",
  sourceMessageId: "",
  context: null,
};

type GroupDisplayMode = "merged" | "folder" | "folder-merged";

type ChatTabItem = {
  type: "channel" | "folder";
  key: string;
  label: string;
  color?: Channel["color"];
  channel?: Channel;
  groupId?: number;
  channels: Channel[];
};

function normalizeGroupNames(value: unknown): Record<number, string> {
  const result: Record<number, string> = {};
  Object.entries(asRecord(value)).forEach(([key, rawLabel]) => {
    const groupId = Number(key);
    const label = ensureString(rawLabel).trim();
    if (Number.isFinite(groupId) && groupId > 0 && label) {
      result[Math.floor(groupId)] = label;
    }
  });
  return result;
}

function normalizeGroupDisplayModes(
  value: unknown,
): Record<number, GroupDisplayMode> {
  const result: Record<number, GroupDisplayMode> = {};
  Object.entries(asRecord(value)).forEach(([key, rawMode]) => {
    const groupId = Number(key);
    const mode = ensureString(rawMode);
    if (
      Number.isFinite(groupId) &&
      groupId > 0 &&
      (mode === "folder" || mode === "merged" || mode === "folder-merged")
    ) {
      result[Math.floor(groupId)] = mode;
    }
  });
  return result;
}

function groupModeFor(
  groupId: number,
  modes: Record<number, GroupDisplayMode>,
): GroupDisplayMode {
  const mode = modes[groupId];
  return mode === "folder" || mode === "folder-merged" ? mode : "merged";
}

function isFolderGroupMode(mode: GroupDisplayMode): boolean {
  return mode === "folder" || mode === "folder-merged";
}

function isMergedGroupMode(mode: GroupDisplayMode): boolean {
  return mode === "merged" || mode === "folder-merged";
}

type ParamPickerState = {
  open: boolean;
  type: string;
  suggestion?: Suggestion;
  param?: SuggestionParam;
  value: string;
};

type DraftColorToken = {
  start: number;
  end: number;
  hex: string;
};

type ColorPickerState = {
  open: boolean;
  start: number;
};

type EmojiPanelState = {
  recent: EmojiEntry[];
  top: EmojiEntry[];
};

const hexHistoryStorageKey = "poodlechat:hexHistory:v1";
const defaultHexColors = [
  "68d8a7",
  "f6d365",
  "8fc7ff",
  "ff8f70",
  "d891ef",
  "fffaf0",
];
const defaultFiveMColors = [
  { code: "1", label: "^1", color: "#f25555" },
  { code: "2", label: "^2", color: "#79d86f" },
  { code: "3", label: "^3", color: "#f6d365" },
  { code: "4", label: "^4", color: "#73a9ff" },
  { code: "5", label: "^5", color: "#8fc7ff" },
  { code: "6", label: "^6", color: "#d891ef" },
  { code: "7", label: "^7", color: "#fffaf0" },
  { code: "8", label: "^8", color: "#ff8f70" },
  { code: "9", label: "^9", color: "#b7b7b0" },
];
const defaultFiveMFormats = [
  { code: "*", label: "^*", name: "Bold" },
  { code: "_", label: "^_", name: "Underline" },
  { code: "/", label: "^/", name: "Italic" },
  { code: "~", label: "^~", name: "Strike" },
  { code: "=", label: "^=", name: "Underline + Strike" },
  { code: "r", label: "^r", name: "Reset" },
];

function cleanHex(value: string): string {
  return value
    .replace(/^#/, "")
    .replace(/[^0-9a-f]/gi, "")
    .slice(0, 6)
    .toLowerCase();
}

function displayHex(value: string): string {
  const raw = cleanHex(value);
  if (raw.length === 3) {
    return raw
      .split("")
      .map((char) => char + char)
      .join("");
  }
  if (raw.length === 6) {
    return raw;
  }
  if (raw.length > 0) {
    return raw.padEnd(6, raw[raw.length - 1] || "0");
  }
  return defaultHexColors[0];
}

function normalizeDraftColorCodes(source: string): string {
  return source.replace(
    /\^#([0-9a-fA-F]{0,6})/g,
    (_match, hex: string) => `^#${displayHex(hex)}`,
  );
}

function getDraftColorTokens(source: string): DraftColorToken[] {
  const tokens: DraftColorToken[] = [];
  for (let index = 0; index < source.length; index += 1) {
    if (source[index] !== "^" || source[index + 1] !== "#") {
      continue;
    }
    let cursor = index + 2;
    let hex = "";
    while (
      cursor < source.length &&
      /^[0-9a-fA-F]$/.test(source[cursor]) &&
      hex.length < 6
    ) {
      hex += source[cursor];
      cursor += 1;
    }
    tokens.push({ start: index, end: cursor, hex });
    index = cursor - 1;
  }
  return tokens;
}

function extractSentHexColors(source: string): string[] {
  return getDraftColorTokens(source)
    .map((token) => cleanHex(token.hex))
    .filter((hex) => hex.length === 3 || hex.length === 6)
    .map((hex) => displayHex(hex));
}

function readHexHistory(): string[] {
  try {
    const parsed = JSON.parse(
      window.localStorage.getItem(hexHistoryStorageKey) || "[]",
    );
    return Array.isArray(parsed)
      ? parsed
          .map((entry) => cleanHex(String(entry)))
          .filter((entry) => entry.length === 6)
          .slice(0, 10)
      : [];
  } catch {
    return [];
  }
}

function normalizeEmojiUsageEntry(raw: unknown): EmojiEntry {
  const record = asRecord(raw);
  const glyph = ensureString(
    record.emoji ||
      record.value ||
      asArray(record.htmlCode)[0] ||
      asArray(record.unicode)[0],
  );
  const aliases = asArray<string>(record.aliases);
  return {
    ...record,
    emoji: glyph,
    name: ensureString(record.name || aliases[0] || glyph, glyph),
    aliases,
    search: ensureString(
      record.search || record.name || aliases.join(" "),
      glyph,
    ),
    usage: Number(record.usage) || 0,
  } as EmojiEntry;
}

function normalizeEmojiPanelData(raw: unknown): EmojiPanelState {
  const record = asRecord(raw);
  return {
    recent: asArray(record.recent)
      .map(normalizeEmojiUsageEntry)
      .filter((entry) => ensureString(entry.emoji)),
    top: asArray(record.top)
      .map(normalizeEmojiUsageEntry)
      .filter((entry) => ensureString(entry.emoji)),
  };
}

function tabOrderValue(
  channel: Channel,
  order: Record<string, number>,
): number {
  const value = Number(order[channel.id]);
  return Number.isFinite(value) && value > 0
    ? value
    : Number(channel.order || 100);
}

function messageSourceId(message: ChatMessage): number {
  const metadata = asRecord(message.metadata);
  return Number(
    metadata.authorSource || metadata.source || metadata.peerId || 0,
  );
}

function messageType(message: ChatMessage): string {
  return ensureString(asRecord(message.metadata).type, "chat");
}

function RangeIcon({ distance }: { distance: DistanceState }) {
  const percent = Number(distance.percent ?? distance.range ?? 0);
  if (percent >= 70) {
    return <SignalHigh size={17} />;
  }
  if (percent >= 35) {
    return <SignalMedium size={17} />;
  }
  return <SignalLow size={17} />;
}

function ensureAutoScroll(
  features: FeatureState,
  settings: PlayerSettings,
): boolean {
  return features.autoScroll?.active !== false && settings.autoScroll !== false;
}

function isSessionHistoryChannel(channelId: string): boolean {
  return channelId === "local" || channelId === "global";
}

function isNearBottom(target: HTMLElement): boolean {
  return target.scrollHeight - target.scrollTop - target.clientHeight < 48;
}

function appendRadioMessage(
  radio: RadioState,
  rawMessage: RadioMessage,
): RadioState {
  const frequency = ensureString(rawMessage.frequency);
  if (!frequency) {
    return radio;
  }
  const historyByFrequency = { ...(radio.historyByFrequency || {}) };
  historyByFrequency[frequency] = [
    ...asArray<RadioMessage>(historyByFrequency[frequency]),
    rawMessage,
  ].slice(-500);
  return { ...radio, historyByFrequency };
}

export default function App() {
  const [loaded, setLoaded] = useState(false);
  const [showInput, setShowInput] = useState(false);
  const [showWindow, setShowWindow] = useState(false);
  const [shouldHide, setShouldHide] = useState(false);
  const [channels, setChannels] = useState<Channel[]>([]);
  const [activeChannel, setActiveChannelState] = useState("global");
  const [messagesByChannel, setMessagesByChannel] = useState<
    Record<string, ChatMessage[]>
  >({});
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [permissions, setPermissions] = useState<PermissionState>({});
  const [features, setFeatures] = useState<FeatureState>({});
  const [distance, setDistance] = useState<DistanceState>({});
  const [radio, setRadio] = useState<RadioState>({});
  const [playerServerId, setPlayerServerId] = useState(0);
  const [uiOpacity, setUiOpacity] = useState(88);
  const [messageDraft, setMessageDraft] = useState("");
  const [draftPreviewOpen, setDraftPreviewOpen] = useState(false);
  const [colorPicker, setColorPicker] = useState<ColorPickerState>({
    open: false,
    start: -1,
  });
  const [paramPicker, setParamPicker] = useState<ParamPickerState>({
    open: false,
    type: "",
    value: "",
  });
  const [emojiOpen, setEmojiOpen] = useState(false);
  const [emojiQuery, setEmojiQuery] = useState("");
  const [emojis, setEmojis] = useState<EmojiEntry[]>([]);
  const [emojiPanel, setEmojiPanel] = useState<EmojiPanelState>({
    recent: [],
    top: [],
  });
  const [hexHistory, setHexHistory] = useState<string[]>(readHexHistory);
  const [whisperTargets, setWhisperTargets] = useState<WhisperTarget[]>([]);
  const [whisperConversations, setWhisperConversations] = useState<
    Record<string, WhisperConversation>
  >({});
  const [activeWhisperConversationId, setActiveWhisperConversationId] =
    useState<string>("");
  const [whisperPickerOpen, setWhisperPickerOpen] = useState(false);
  const [manualWhisperTarget, setManualWhisperTarget] = useState("");
  const [contextMenu, setContextMenu] = useState<ContextMenuState>({
    open: false,
    x: 0,
    y: 0,
  });
  const [reportModal, setReportModal] = useState<ReportState>(emptyReport);
  const [hideDeleted, setHideDeleted] = useState(false);
  const [managerOpen, setManagerOpen] = useState(false);
  const [managerState, setManagerState] = useState<ManagerBootstrap>({});
  const [playerSettings, setPlayerSettings] = useState<PlayerSettings>({});
  const [tabGrouping, setTabGroupingState] = useState<Record<string, number>>(
    {},
  );
  const [tabOrder, setTabOrderState] = useState<Record<string, number>>({});
  const [tabGroupNames, setTabGroupNames] = useState<Record<number, string>>(
    {},
  );
  const [tabGroupDisplayMode, setTabGroupDisplayMode] = useState<
    Record<number, GroupDisplayMode>
  >({});
  const [lastActiveChannelByGroup, setLastActiveChannelByGroup] = useState<
    Record<number, string>
  >({});
  const [hiddenTabs, setHiddenTabs] = useState<Record<string, boolean>>({});
  const [tabNotifications, setTabNotifications] = useState<
    Record<string, boolean>
  >({});
  const [notificationUnread, setNotificationUnread] = useState<
    Record<string, number>
  >({});
  const [radioUnread, setRadioUnread] = useState<Record<string, number>>({});
  const [radioStatus, setRadioStatus] = useState("");
  const [messages3d, setMessages3d] = useState<Record<string, Message3D>>({});
  const inputRef = useRef<HTMLTextAreaElement | null>(null);
  const draftOverlayRef = useRef<HTMLDivElement | null>(null);
  const standardMessagesRef = useRef<HTMLDivElement | null>(null);
  const whisperMessagesRef = useRef<HTMLDivElement | null>(null);
  const radioMessagesRef = useRef<HTMLDivElement | null>(null);
  const fadeTimerRef = useRef<number | null>(null);
  const fadeTimeoutRef = useRef(7000);
  const emojiCatalogLoadingRef = useRef<Promise<void> | null>(null);
  const nextMessageIdRef = useRef(1);
  const showInputRef = useRef(false);
  const userReadingRef = useRef(false);
  const managerReturnToChatRef = useRef(false);
  const { commitHistory, browseHistory, resetHistoryBrowse } =
    useCommandHistory(30);

  useEffect(() => {
    showInputRef.current = showInput;
  }, [showInput]);

  const channelsById = useMemo(() => {
    const map: Record<string, Channel> = {};
    channels.forEach((channel) => {
      map[channel.id] = channel;
    });
    return map;
  }, [channels]);

  const activeChannelDef = channelsById[activeChannel];
  const activeIsWhispers = activeChannel === "whispers";
  const radioChannelId = ensureString(radio.channelId, "radio");
  const activeIsRadio =
    activeChannel === radioChannelId && radio.enabled === true;
  const autoScrollActive = ensureAutoScroll(features, playerSettings);
  const staffAllowed = canUseStaffTools(permissions);
  const chatFontFamily = chatFontCss(playerSettings.fontFamily);
  const chatFontScale = normalizeChatFontScale(playerSettings.fontScale);

  const visibleChannels = useMemo(() => {
    const source = channels.filter(
      (channel) =>
        channel.allowed !== false &&
        channel.visible !== false &&
        hiddenTabs[channel.id] !== true,
    );
    if (source.length > 0) {
      return [...source].sort(
        (a, b) => tabOrderValue(a, tabOrder) - tabOrderValue(b, tabOrder),
      );
    }
    return channels
      .filter(
        (channel) => channel.allowed !== false && channel.visible !== false,
      )
      .sort((a, b) => tabOrderValue(a, tabOrder) - tabOrderValue(b, tabOrder));
  }, [channels, hiddenTabs, tabOrder]);

  const chatTabItems = useMemo<ChatTabItem[]>(() => {
    const folderGroups = new Map<number, Channel[]>();
    visibleChannels.forEach((channel) => {
      const groupId = Number(tabGrouping[channel.id]) || 0;
      if (
        groupId > 0 &&
        isFolderGroupMode(groupModeFor(groupId, tabGroupDisplayMode))
      ) {
        folderGroups.set(groupId, [
          ...(folderGroups.get(groupId) || []),
          channel,
        ]);
      }
    });

    const renderedFolderGroups = new Set<number>();
    const items: ChatTabItem[] = [];
    visibleChannels.forEach((channel) => {
      const groupId = Number(tabGrouping[channel.id]) || 0;
      if (
        groupId > 0 &&
        isFolderGroupMode(groupModeFor(groupId, tabGroupDisplayMode))
      ) {
        if (renderedFolderGroups.has(groupId)) {
          return;
        }
        const groupChannels = folderGroups.get(groupId) || [channel];
        renderedFolderGroups.add(groupId);
        items.push({
          type: "folder",
          key: `folder:${groupId}`,
          label: tabGroupNames[groupId] || `Group ${groupId}`,
          color: groupChannels[0]?.color,
          groupId,
          channels: groupChannels,
        });
        return;
      }

      items.push({
        type: "channel",
        key: `channel:${channel.id}`,
        label: channel.label,
        color: channel.color,
        channel,
        channels: [channel],
      });
    });
    return items;
  }, [tabGroupDisplayMode, tabGroupNames, tabGrouping, visibleChannels]);

  const activeFolderGroupId = useMemo(() => {
    const groupId = Number(tabGrouping[activeChannel]) || 0;
    if (
      groupId <= 0 ||
      !isFolderGroupMode(groupModeFor(groupId, tabGroupDisplayMode))
    ) {
      return 0;
    }
    return chatTabItems.some(
      (item) => item.type === "folder" && item.groupId === groupId,
    )
      ? groupId
      : 0;
  }, [activeChannel, chatTabItems, tabGroupDisplayMode, tabGrouping]);

  const activeFolderChannels = useMemo(() => {
    if (activeFolderGroupId <= 0) {
      return [];
    }
    return visibleChannels.filter(
      (channel) => Number(tabGrouping[channel.id]) === activeFolderGroupId,
    );
  }, [activeFolderGroupId, tabGrouping, visibleChannels]);

  const groupedChannelIds = useMemo(() => {
    const groupId = tabGrouping[activeChannel];
    if (
      !Number.isFinite(Number(groupId)) ||
      Number(groupId) <= 0 ||
      !isMergedGroupMode(groupModeFor(Number(groupId), tabGroupDisplayMode))
    ) {
      return [activeChannel];
    }
    return visibleChannels
      .filter((channel) => Number(tabGrouping[channel.id]) === Number(groupId))
      .sort((a, b) => tabOrderValue(a, tabOrder) - tabOrderValue(b, tabOrder))
      .map((channel) => channel.id);
  }, [
    activeChannel,
    tabGroupDisplayMode,
    tabGrouping,
    tabOrder,
    visibleChannels,
  ]);

  const activeMessages = useMemo(() => {
    if (activeIsWhispers) {
      return whisperConversations[activeWhisperConversationId]?.messages || [];
    }
    if (groupedChannelIds.length === 1) {
      return messagesByChannel[groupedChannelIds[0]] || [];
    }
    const list = groupedChannelIds.flatMap(
      (channelId) => messagesByChannel[channelId] || [],
    );
    return list.sort(
      (a, b) => Number(a.timestamp || 0) - Number(b.timestamp || 0),
    );
  }, [
    activeIsWhispers,
    activeWhisperConversationId,
    groupedChannelIds,
    messagesByChannel,
    whisperConversations,
  ]);

  const renderedActiveMessages = useMemo(
    () => activeMessages.slice(-180),
    [activeMessages],
  );

  const currentRadioFrequency = useMemo(() => {
    const slot = getRadioSlot(
      radio,
      radio.selectedSlot === "secondary" ? "secondary" : "primary",
    );
    return ensureString(slot.frequency);
  }, [radio]);

  const currentRadioMessages = useMemo(() => {
    if (!currentRadioFrequency) {
      return [];
    }
    return asArray<RadioMessage>(
      asRecord(radio.historyByFrequency)[currentRadioFrequency],
    );
  }, [currentRadioFrequency, radio.historyByFrequency]);

  const renderedRadioMessages = useMemo(
    () => currentRadioMessages.slice(-180),
    [currentRadioMessages],
  );

  const getActiveScrollTarget = useCallback(() => {
    if (activeIsRadio) {
      return radioMessagesRef.current;
    }
    if (activeIsWhispers) {
      return whisperMessagesRef.current;
    }
    return standardMessagesRef.current;
  }, [activeIsRadio, activeIsWhispers]);

  const scrollActiveMessages = useCallback(
    (force = false) => {
      if (!force && !autoScrollActive) {
        return;
      }
      const target = getActiveScrollTarget();
      if (target) {
        if (!force && userReadingRef.current && !isNearBottom(target)) {
          return;
        }
        target.scrollTop = target.scrollHeight;
        userReadingRef.current = false;
      }
    },
    [autoScrollActive, getActiveScrollTarget],
  );

  const bumpWindow = useCallback(() => {
    setShowWindow(true);
    if (fadeTimerRef.current) {
      window.clearTimeout(fadeTimerRef.current);
    }
    const timeout = Math.max(0, Number(fadeTimeoutRef.current) || 0);
    if (timeout <= 0) {
      return;
    }
    fadeTimerRef.current = window.setTimeout(() => {
      if (!showInputRef.current) {
        setShowWindow(false);
      }
    }, timeout);
  }, []);

  const rememberFolderSelection = useCallback(
    (channelId: string) => {
      const groupId = Number(tabGrouping[channelId]) || 0;
      if (
        groupId > 0 &&
        isFolderGroupMode(groupModeFor(groupId, tabGroupDisplayMode))
      ) {
        setLastActiveChannelByGroup((current) => ({
          ...current,
          [groupId]: channelId,
        }));
      }
    },
    [tabGroupDisplayMode, tabGrouping],
  );

  const setActiveChannel = useCallback(
    (channelId: string) => {
      const id = channelId || visibleChannels[0]?.id || "global";
      rememberFolderSelection(id);
      setActiveChannelState(id);
      setNotificationUnread((current) => ({ ...current, [id]: 0 }));
      void fetchNui("setChannel", { channelId: id });
    },
    [rememberFolderSelection, visibleChannels],
  );

  const activateChatTab = useCallback(
    (item: ChatTabItem) => {
      if (item.type === "folder") {
        const groupId = Number(item.groupId) || 0;
        const previous = ensureString(lastActiveChannelByGroup[groupId]);
        const nextChannel =
          previous && item.channels.some((channel) => channel.id === previous)
            ? previous
            : item.channels[0]?.id;
        if (nextChannel) {
          setActiveChannel(nextChannel);
        }
        return;
      }
      if (item.channel) {
        setActiveChannel(item.channel.id);
      }
    },
    [lastActiveChannelByGroup, setActiveChannel],
  );

  const cycleChannel = useCallback(() => {
    void fetchNui("cycleChannel", {});
  }, []);

  const applyOnLoad = useCallback((payload: OnLoadPayload) => {
    const normalizedChannels = normalizeChannels(payload.channels);
    const normalizedFeatures = payload.features || {};
    const opacity = normalizeOpacity(payload.ui?.opacity, 88);
    const loadedTabGrouping = asRecord(
      payload.tabs?.grouping || payload.tabs?.defaultGrouping,
    ) as Record<string, number>;
    const loadedTabOrder = asRecord(payload.tabs?.order) as Record<
      string,
      number
    >;
    const loadedGroupNames = normalizeGroupNames(payload.tabs?.groupNames);
    const loadedGroupDisplayMode = normalizeGroupDisplayModes(
      payload.tabs?.groupDisplayMode,
    );
    fadeTimeoutRef.current = Math.max(
      0,
      Number(payload.ui?.fadeTimeout) || 7000,
    );
    const initialSettings: PlayerSettings = {
      opacity,
      soundEnabled: asRecord(payload.whispers?.notifications).enabled !== false,
      soundVolume:
        Number(asRecord(payload.whispers?.notifications).volume) || 0.65,
      bubbles: normalizedFeatures.bubbles?.active !== false,
      typing: normalizedFeatures.typing?.active !== false,
      autoScroll: normalizedFeatures.autoScroll?.active !== false,
      fontFamily: normalizeChatFontId(payload.ui?.fontFamily),
      fontScale: normalizeChatFontScale(payload.ui?.fontScale),
      tabGrouping: loadedTabGrouping,
      tabOrder: loadedTabOrder,
      hiddenTabs: asRecord(payload.tabs?.hidden) as Record<string, boolean>,
      tabNotifications: asRecord(payload.notifications?.toggles) as Record<
        string,
        boolean
      >,
      hideDeletedMessages: false,
      groupNames: loadedGroupNames,
      groupDisplayMode: loadedGroupDisplayMode,
    };

    setChannels(normalizedChannels);
    setPlayerServerId(Number(payload.playerServerId) || 0);
    setPermissions(normalizePermissions(payload.permissions));
    setFeatures(normalizedFeatures);
    setDistance(payload.distance || {});
    setRadio(normalizeRadioState(payload.radio));
    setTabGroupingState(loadedTabGrouping);
    setTabOrderState(loadedTabOrder);
    setTabGroupNames(loadedGroupNames);
    setTabGroupDisplayMode(loadedGroupDisplayMode);
    setHiddenTabs(asRecord(payload.tabs?.hidden) as Record<string, boolean>);
    setTabNotifications(
      asRecord(payload.notifications?.toggles) as Record<string, boolean>,
    );
    setUiOpacity(opacity);
    setHideDeleted(initialSettings.hideDeletedMessages === true);
    setPlayerSettings(initialSettings);
    setEmojiPanel(normalizeEmojiPanelData(payload.emojiPanel));
    const desired = ensureString(
      payload.activeChannel,
      normalizedChannels[0]?.id || "global",
    );
    const initialActiveChannel = normalizedChannels.some(
      (channel) => channel.id === desired,
    )
      ? desired
      : normalizedChannels[0]?.id || "global";
    setActiveChannelState(initialActiveChannel);
    const initialActiveGroupId =
      Number(loadedTabGrouping[initialActiveChannel]) || 0;
    if (
      initialActiveGroupId > 0 &&
      isFolderGroupMode(
        groupModeFor(initialActiveGroupId, loadedGroupDisplayMode),
      )
    ) {
      setLastActiveChannelByGroup((current) => ({
        ...current,
        [initialActiveGroupId]: initialActiveChannel,
      }));
    }
  }, []);

  const loadInitial = useCallback(async () => {
    const payload = await fetchNui<OnLoadPayload>("onLoad", {});
    applyOnLoad(payload || {});
    await fetchNui("loaded", {});
    setLoaded(true);
  }, [applyOnLoad]);

  const addOrUpdateMessage = useCallback(
    (raw: ChatMessage) => {
      const normalized = normalizeMessage(
        raw,
        activeChannel,
        nextMessageIdRef.current,
      );
      nextMessageIdRef.current += 1;
      const metadata = asRecord(normalized.metadata);
      if (metadata.type === "whisper" && metadata.conversationId) {
        const conversationId = ensureString(
          metadata.conversationId || metadata.peerId || "conversation",
        );
        const peerId = Number(metadata.peerId) || undefined;
        const peerName = ensureString(
          metadata.peerName,
          peerId ? `Player ${peerId}` : "Whisper",
        );
        setWhisperConversations((current) => {
          const existing = current[conversationId] || {
            id: conversationId,
            peerName,
            peerId,
            peerCharacterId: ensureString(metadata.peerCharacterId),
            pending: false,
            unread: 0,
            lastAt: 0,
            messages: [],
          };
          const messageId = ensureString(normalized.messageId);
          const withoutDuplicate = existing.messages.filter(
            (message) => ensureString(message.messageId) !== messageId,
          );
          const direction = ensureString(metadata.direction);
          const visibleNow =
            activeChannel === "whispers" &&
            activeWhisperConversationId === conversationId;
          return {
            ...current,
            [conversationId]: {
              ...existing,
              peerName: existing.peerName || peerName,
              peerId: existing.peerId || peerId,
              peerCharacterId:
                existing.peerCharacterId ||
                ensureString(metadata.peerCharacterId),
              pending: false,
              lastAt: Math.max(
                existing.lastAt || 0,
                Number(normalized.timestamp) || Date.now(),
              ),
              unread:
                direction === "in" && !visibleNow ? existing.unread + 1 : 0,
              messages: [...withoutDuplicate, normalized].sort(
                (a, b) => Number(a.timestamp || 0) - Number(b.timestamp || 0),
              ),
            },
          };
        });
        if (
          ensureString(metadata.direction) === "out" ||
          !activeWhisperConversationId
        ) {
          setActiveWhisperConversationId(conversationId);
        }
        if (activeChannel !== "whispers") {
          setNotificationUnread((current) => ({
            ...current,
            whispers: (current.whispers || 0) + 1,
          }));
        }
      }

      setMessagesByChannel((current) => {
        const channelId = ensureString(normalized.channel, activeChannel);
        const channel = channelsById[channelId];
        const existing = current[channelId] || [];
        const messageId = ensureString(normalized.messageId);
        const withoutDuplicate = existing.filter(
          (message) => ensureString(message.messageId) !== messageId,
        );
        const limit = Number(channel?.maxHistory) || 250;
        const next = [...withoutDuplicate, normalized].sort(
          (a, b) => Number(a.timestamp || 0) - Number(b.timestamp || 0),
        );
        const trimmed =
          limit > 0 && next.length > limit
            ? next.slice(next.length - limit)
            : next;
        return { ...current, [channelId]: trimmed };
      });

      const visibleNow = groupedChannelIds.includes(
        ensureString(normalized.channel),
      );
      const ownSource = Number(metadata.authorSource || metadata.source);
      const isOwn = Number.isFinite(ownSource) && ownSource === playerServerId;
      if (!visibleNow && !isOwn && metadata.deleted !== true) {
        setNotificationUnread((current) => {
          const channelId = ensureString(normalized.channel, activeChannel);
          return { ...current, [channelId]: (current[channelId] || 0) + 1 };
        });
      }
      bumpWindow();
    },
    [
      activeChannel,
      activeWhisperConversationId,
      bumpWindow,
      channelsById,
      groupedChannelIds,
      playerServerId,
    ],
  );

  const requestManager = useCallback(
    async (name: string, payload: unknown = {}) => {
      const response = await fetchNui<ManagerBootstrap>(name, payload);
      if (response && typeof response === "object") {
        setManagerState((current) => ({
          ...current,
          ...response,
          commandPolicy: response.commandPolicy || current.commandPolicy,
          commandBlocks: response.commandBlocks || current.commandBlocks,
          commandRoutes: response.commandRoutes || current.commandRoutes,
          customCommands: response.customCommands || current.customCommands,
          autoMessages: response.autoMessages || current.autoMessages,
        }));
        if (response.permissions) {
          setPermissions(response.permissions);
        }
        if (response.playerSettings) {
          setPlayerSettings(response.playerSettings);
          if (
            typeof response.playerSettings.hideDeletedMessages === "boolean"
          ) {
            setHideDeleted(response.playerSettings.hideDeletedMessages);
          }
          if (response.playerSettings.tabGrouping) {
            setTabGroupingState(
              asRecord(response.playerSettings.tabGrouping) as Record<
                string,
                number
              >,
            );
          }
          if (response.playerSettings.tabOrder) {
            setTabOrderState(response.playerSettings.tabOrder);
          }
          setTabGroupNames(
            normalizeGroupNames(response.playerSettings.groupNames),
          );
          setTabGroupDisplayMode(
            normalizeGroupDisplayModes(
              response.playerSettings.groupDisplayMode,
            ),
          );
        }
      }
      return response || {};
    },
    [],
  );

  const loadManager = useCallback(async () => {
    await requestManager("managerGetBootstrap", {});
  }, [requestManager]);

  const savePlayerSettings = useCallback(
    (settings: PlayerSettings) => {
      const groupNames = normalizeGroupNames(settings.groupNames);
      const groupDisplayMode = normalizeGroupDisplayModes(
        settings.groupDisplayMode,
      );
      const nextSettings = { ...settings, groupNames, groupDisplayMode };
      setPlayerSettings(nextSettings);
      setUiOpacity(normalizeOpacity(nextSettings.opacity, uiOpacity));
      setHiddenTabs(
        asRecord(nextSettings.hiddenTabs) as Record<string, boolean>,
      );
      setTabNotifications(
        asRecord(nextSettings.tabNotifications) as Record<string, boolean>,
      );
      setHideDeleted(nextSettings.hideDeletedMessages === true);
      setTabOrderState(
        asRecord(nextSettings.tabOrder) as Record<string, number>,
      );
      setTabGroupNames(groupNames);
      setTabGroupDisplayMode(groupDisplayMode);
      if (
        nextSettings.tabGrouping &&
        typeof nextSettings.tabGrouping === "object"
      ) {
        setTabGroupingState(nextSettings.tabGrouping);
        void fetchNui("setTabGrouping", {
          grouping: nextSettings.tabGrouping,
          order: nextSettings.tabOrder || {},
          groupNames,
          groupDisplayMode,
        });
      }
      void fetchNui("managerUpdatePlayerSettings", {
        settings: nextSettings,
      }).then((response) => {
        const record = asRecord(response);
        if (record.playerSettings) {
          const returnedSettings = record.playerSettings as PlayerSettings;
          setPlayerSettings(returnedSettings);
          setTabGroupNames(normalizeGroupNames(returnedSettings.groupNames));
          setTabGroupDisplayMode(
            normalizeGroupDisplayModes(returnedSettings.groupDisplayMode),
          );
        }
        if (record.feature) {
          setFeatures(record.feature as FeatureState);
        }
      });
      Object.entries(asRecord(nextSettings.hiddenTabs)).forEach(
        ([channelId, hidden]) => {
          void fetchNui("setTabHidden", { channelId, hidden: hidden === true });
        },
      );
      Object.entries(asRecord(nextSettings.tabNotifications)).forEach(
        ([channelId, enabled]) => {
          void fetchNui("setTabNotificationToggle", {
            channelId,
            enabled: enabled !== false,
          });
        },
      );
    },
    [uiOpacity],
  );

  const closeInput = useCallback(
    (canceled = true) => {
      setShowInput(false);
      setEmojiOpen(false);
      setColorPicker({ open: false, start: -1 });
      setParamPicker({ open: false, type: "", value: "" });
      resetHistoryBrowse();
      void fetchNui(
        canceled ? "chatResult" : "closeInput",
        canceled ? { canceled: true } : {},
      );
    },
    [resetHistoryBrowse],
  );

  const recordUsedHexColors = useCallback((source: string) => {
    const used = extractSentHexColors(source);
    if (used.length === 0) {
      return;
    }
    setHexHistory((current) => {
      const next = [
        ...used,
        ...current.filter((entry) => !used.includes(entry)),
      ].slice(0, 10);
      try {
        window.localStorage.setItem(hexHistoryStorageKey, JSON.stringify(next));
      } catch {}
      return next;
    });
  }, []);

  const sendMessage = useCallback(async () => {
    const message = normalizeDraftColorCodes(messageDraft.trim());
    if (!message) {
      closeInput(true);
      return;
    }

    if (activeIsRadio && message.charAt(0) !== "/") {
      if (!currentRadioFrequency) {
        setRadioStatus("Select a connected radio slot first.");
        return;
      }
      const response = await fetchNui<AnyRecord>("radioSendMessage", {
        slot: radio.selectedSlot === "secondary" ? "secondary" : "primary",
        frequency: currentRadioFrequency,
        message,
      });
      if (response?.state) {
        setRadio(normalizeRadioState(response.state));
      }
      if (response?.ok) {
        commitHistory(message);
        recordUsedHexColors(message);
        setMessageDraft("");
        setRadioStatus("");
        closeInput(false);
      } else {
        setRadioStatus(
          ensureString(response?.reason, "Radio message could not be sent."),
        );
      }
      return;
    }

    const activeConversation =
      whisperConversations[activeWhisperConversationId];
    commitHistory(message);
    recordUsedHexColors(message);
    setMessageDraft("");
    void fetchNui("chatResult", {
      canceled: false,
      message,
      channel: activeChannel,
      whisperTarget:
        activeIsWhispers && activeConversation
          ? {
              peerId: activeConversation.peerId,
              peerCharacterId: activeConversation.peerCharacterId,
              conversationId: activeConversation.id,
            }
          : undefined,
    });
    setEmojiOpen(false);
    resetHistoryBrowse();
    setShowInput(false);
  }, [
    activeChannel,
    activeIsRadio,
    activeIsWhispers,
    activeWhisperConversationId,
    closeInput,
    commitHistory,
    currentRadioFrequency,
    messageDraft,
    radio.selectedSlot,
    recordUsedHexColors,
    resetHistoryBrowse,
    whisperConversations,
  ]);

  const startWhisper = useCallback(
    (target: WhisperTarget) => {
      const peerId = Number(target.id);
      if (!Number.isFinite(peerId) || peerId <= 0) {
        return;
      }
      const id = `pending:${peerId}`;
      setWhisperConversations((current) => ({
        ...current,
        [id]: current[id] || {
          id,
          peerName: ensureString(
            target.name || target.label,
            `Player ${peerId}`,
          ),
          peerId,
          unread: 0,
          lastAt: Date.now(),
          pending: true,
          messages: [],
        },
      }));
      setActiveWhisperConversationId(id);
      setActiveChannel("whispers");
      setWhisperPickerOpen(false);
    },
    [setActiveChannel],
  );

  const handleContext = useCallback(
    (event: React.MouseEvent, message: ChatMessage) => {
      event.preventDefault();
      setContextMenu({
        open: true,
        x: event.clientX,
        y: event.clientY,
        message,
      });
    },
    [],
  );

  const handleContextAction = useCallback(
    (action: string) => {
      const message = contextMenu.message;
      setContextMenu({ open: false, x: 0, y: 0 });
      if (!message) {
        return;
      }

      if (action === "copy") {
        copyToClipboard(messageRawText(message));
      } else if (action === "report") {
        const context = createReportContext(message);
        setReportModal({
          open: true,
          targetId: ensureString(context.authorSource || context.peerId || ""),
          reason: "",
          sourceMessageId: ensureString(message.messageId),
          context,
        });
      } else if (action === "delete") {
        void fetchNui("deleteMessage", { messageId: message.messageId });
      } else if (action === "whisper") {
        const metadata = asRecord(message.metadata);
        const peerId = Number(
          metadata.authorSource || metadata.source || metadata.peerId,
        );
        if (
          Number.isFinite(peerId) &&
          peerId > 0 &&
          peerId !== playerServerId &&
          ensureString(metadata.direction) !== "out"
        ) {
          startWhisper({ id: peerId, name: messageAuthor(message) });
        }
      }
    },
    [contextMenu.message, playerServerId, startWhisper],
  );

  const submitReport = useCallback(() => {
    if (!reportModal.reason.trim()) {
      return;
    }
    void fetchNui("submitReport", {
      targetId: reportModal.targetId.trim(),
      reason: reportModal.reason.trim(),
      sourceMessageId: reportModal.sourceMessageId,
      reportContext: reportModal.context,
    });
    setReportModal(emptyReport);
  }, [reportModal]);

  const cycleDistance = () => {
    void fetchNui<AnyRecord>("cycleDistance", {}).then((response) => {
      if (response?.state) {
        setDistance(asRecord(response.state) as DistanceState);
      }
    });
  };

  const toggleFeature = (callback: string, featureName: keyof FeatureState) => {
    const previous = asRecord(features[featureName]);
    const nextActive = previous.active === false;
    setFeatures((current) => ({
      ...current,
      [featureName]: {
        ...asRecord(current[featureName]),
        active: nextActive,
      },
    }));
    void fetchNui<AnyRecord>(callback, {}).then((response) => {
      setFeatures((current) => ({
        ...current,
        [featureName]: {
          ...asRecord(current[featureName]),
          ...asRecord(response),
          active:
            typeof response?.active === "boolean"
              ? response.active
              : asRecord(current[featureName]).active,
        },
      }));
      if (
        callback === "toggleAutoScroll" &&
        (response?.active === true || nextActive)
      ) {
        window.setTimeout(() => scrollActiveMessages(true), 20);
      }
      void fetchNui("resyncState", {});
    });
  };

  const openManagerFromChat = () => {
    managerReturnToChatRef.current = showInput;
    setManagerOpen(true);
    void loadManager();
  };

  const closeManager = (returnToChat = false) => {
    setManagerOpen(false);
    void fetchNui("closeManager", { returnToChat });
    if (returnToChat) {
      setShowInput(true);
      window.setTimeout(() => inputRef.current?.focus(), 40);
    }
    managerReturnToChatRef.current = false;
  };

  const refreshEmojiPanel = useCallback(() => {
    void fetchNui<AnyRecord>("getEmojiPanelData", {}).then((response) => {
      const payload = asRecord(response).panel || response;
      setEmojiPanel(normalizeEmojiPanelData(payload));
    });
  }, []);

  const loadEmojiCatalog = useCallback(() => {
    if (emojis.length > 0) {
      return emojiCatalogLoadingRef.current || Promise.resolve();
    }
    if (emojiCatalogLoadingRef.current) {
      return emojiCatalogLoadingRef.current;
    }

    const builtEmojiUrl = new URL("../../html/emojibase.json", import.meta.url)
      .href;
    const devHost = ["localhost", "127.0.0.1"].includes(
      window.location.hostname,
    );
    const emojiUrls = devHost
      ? [builtEmojiUrl, "./emojibase.json"]
      : ["./emojibase.json", builtEmojiUrl];
    emojiCatalogLoadingRef.current = (async () => {
      for (const url of emojiUrls) {
        try {
          const response = await fetch(url);
          if (response.ok) {
            setEmojis(asArray<EmojiEntry>(await response.json()));
            return;
          }
        } catch {}
      }
      setEmojis([]);
    })().finally(() => {
      emojiCatalogLoadingRef.current = null;
    });
    return emojiCatalogLoadingRef.current;
  }, [emojis.length]);

  const pickEmoji = (emoji: string, entry: EmojiEntry) => {
    setMessageDraft((current) => `${current}${emoji}`);
    void fetchNui<AnyRecord>("useEmoji", { emoji }).then((response) => {
      const payload = asRecord(response).panel || response;
      setEmojiPanel(normalizeEmojiPanelData(payload));
    });
    inputRef.current?.focus();
  };

  const handleDraftChange = (value: string) => {
    resetHistoryBrowse();
    setParamPicker({ open: false, type: "", value: "" });
    setMessageDraft(value);
  };

  const applySuggestion = useCallback((suggestion: Suggestion) => {
    const command = ensureString(suggestion.name).startsWith("/")
      ? ensureString(suggestion.name)
      : `/${ensureString(suggestion.name)}`;
    setMessageDraft((current) => {
      const rest = current.includes(" ")
        ? current.slice(current.indexOf(" "))
        : " ";
      return `${command}${rest}`;
    });
    window.setTimeout(() => inputRef.current?.focus(), 0);
  }, []);

  const appendCommandToken = useCallback((value: string) => {
    const token = value.trim();
    if (!token) {
      return;
    }
    setMessageDraft((current) => `${current.replace(/\s*$/, " ")}${token} `);
    setParamPicker({ open: false, type: "", value: "" });
    window.setTimeout(() => inputRef.current?.focus(), 0);
  }, []);

  const pickSuggestionParam = useCallback(
    (suggestion: Suggestion, param: SuggestionParam, type: string) => {
      if (type === "player") {
        setParamPicker({ open: true, type, suggestion, param, value: "" });
        void fetchNui("getWhisperTargets", {});
        return;
      }
      if (type === "number") {
        setParamPicker({ open: true, type, suggestion, param, value: "1" });
        return;
      }
      setParamPicker({
        open: true,
        type: "text",
        suggestion,
        param,
        value: "",
      });
    },
    [],
  );

  const draftColorTokens = useMemo(
    () => getDraftColorTokens(messageDraft),
    [messageDraft],
  );
  const draftPreviewHtml = useMemo(
    () =>
      renderRichText(
        normalizeDraftColorCodes(messageDraft || "Message preview"),
      ),
    [messageDraft],
  );

  const activeColorToken = useMemo(() => {
    if (!colorPicker.open) {
      return null;
    }
    return (
      draftColorTokens.find((token) => token.start === colorPicker.start) ||
      null
    );
  }, [colorPicker.open, colorPicker.start, draftColorTokens]);

  const replaceDraftColorAt = useCallback(
    (targetStart: number, nextColor: string) => {
      const normalized = displayHex(nextColor);
      setMessageDraft((current) => {
        const token = getDraftColorTokens(current).find(
          (item) => item.start === targetStart,
        );
        if (!token) {
          return current;
        }
        return `${current.slice(0, token.start)}^#${normalized}${current.slice(token.end)}`;
      });
    },
    [],
  );

  const insertDraftColor = useCallback((hex: string) => {
    setMessageDraft(
      (current) =>
        `${current}${current.endsWith(" ") || current.length === 0 ? "" : " "}^#${displayHex(hex)}`,
    );
    window.setTimeout(() => inputRef.current?.focus(), 0);
  }, []);

  const insertDraftCode = useCallback((code: string) => {
    const normalized = code.replace(/^\^/, "");
    setMessageDraft(
      (current) =>
        `${current}${current.endsWith(" ") || current.length === 0 ? "" : " "}^${normalized}`,
    );
    window.setTimeout(() => inputRef.current?.focus(), 0);
  }, []);

  const handleKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      void sendMessage();
    } else if (event.key === "Escape") {
      event.preventDefault();
      closeInput(true);
    } else if (event.key === "ArrowUp" || event.key === "ArrowDown") {
      event.preventDefault();
      const nextDraft = browseHistory(
        event.key === "ArrowUp" ? "up" : "down",
        messageDraft,
      );
      if (nextDraft !== null) {
        setMessageDraft(nextDraft);
        window.setTimeout(() => {
          const input = inputRef.current;
          if (input) {
            input.selectionStart = nextDraft.length;
            input.selectionEnd = nextDraft.length;
          }
        }, 0);
      }
    } else if (event.key === "PageUp" || event.key === "PageDown") {
      event.preventDefault();
      const target = getActiveScrollTarget();
      if (target) {
        target.scrollTop += event.key === "PageUp" ? -120 : 120;
        userReadingRef.current = !isNearBottom(target);
      }
    } else if (event.key === "Tab") {
      event.preventDefault();
      cycleChannel();
    }
  };

  const handleChatWheel = (event: React.WheelEvent) => {
    if (!showInput) {
      return;
    }
    const target = getActiveScrollTarget();
    if (target) {
      event.preventDefault();
      target.scrollTop += event.deltaY;
      userReadingRef.current = !isNearBottom(target);
    }
  };

  const handleMessageScroll = (event: React.UIEvent<HTMLDivElement>) => {
    userReadingRef.current = !isNearBottom(event.currentTarget);
  };

  useEffect(() => {
    void loadInitial();
  }, [loadInitial]);

  useEffect(() => {
    const listener = (event: MessageEvent) => {
      const item = nuiMessageData(event);
      const type = ensureString(item.type);
      if (!type) {
        return;
      }

      switch (type) {
        case "ON_OPEN":
          if (fadeTimerRef.current) {
            window.clearTimeout(fadeTimerRef.current);
          }
          setShouldHide(false);
          setShowWindow(true);
          setShowInput(true);
          window.setTimeout(() => inputRef.current?.focus(), 40);
          break;
        case "ON_SCREEN_STATE_CHANGE":
        case "setChatHidden":
          if (item.shouldHide === true || item.hidden === true) {
            if (fadeTimerRef.current) {
              window.clearTimeout(fadeTimerRef.current);
            }
            setShouldHide(true);
            setShowWindow(false);
          } else {
            setShouldHide(false);
            bumpWindow();
          }
          break;
        case "ON_MESSAGE":
          if (item.message && typeof item.message === "object") {
            addOrUpdateMessage(item.message as ChatMessage);
          }
          break;
        case "restoreHistory":
          asArray<ChatMessage>(item.messages).forEach(addOrUpdateMessage);
          break;
        case "characterSwitch":
          setMessagesByChannel((current) =>
            Object.fromEntries(
              Object.entries(current).filter(([channelId]) =>
                isSessionHistoryChannel(channelId),
              ),
            ),
          );
          setWhisperConversations({});
          setRadio((current) => ({ ...current, historyByFrequency: {} }));
          setRadioUnread({});
          setActiveWhisperConversationId("");
          asArray<ChatMessage>(item.messages).forEach(addOrUpdateMessage);
          bumpWindow();
          break;
        case "ON_CLEAR":
          setMessagesByChannel({});
          setWhisperConversations({});
          setNotificationUnread({});
          setRadioUnread({});
          setRadioStatus("");
          setShowWindow(showInputRef.current);
          break;
        case "ON_SUGGESTION_ADD":
          setSuggestions((current) => {
            const suggestion = normalizeSuggestion(item.suggestion);
            if (!suggestion) {
              return current;
            }
            return [
              ...current.filter((entry) => entry.name !== suggestion.name),
              suggestion,
            ];
          });
          break;
        case "ON_SUGGESTIONS_ADD":
          setSuggestions((current) => {
            const next = [...current];
            asArray<unknown>(item.suggestions).forEach((rawSuggestion) => {
              const suggestion = normalizeSuggestion(rawSuggestion);
              if (
                suggestion &&
                !next.some((entry) => entry.name === suggestion.name)
              ) {
                next.push(suggestion);
              }
            });
            return next;
          });
          break;
        case "ON_SUGGESTION_REMOVE":
          setSuggestions((current) =>
            current.filter((suggestion) => suggestion.name !== item.name),
          );
          break;
        case "setPermissions":
          setPermissions(normalizePermissions(item.permissions));
          if (item.channels) {
            setChannels(normalizeChannels(item.channels));
          }
          if (typeof item.activeChannel === "string") {
            setActiveChannelState(item.activeChannel);
          }
          break;
        case "setFeatureState":
          setFeatures(asRecord(item.state) as FeatureState);
          break;
        case "setDistanceState":
          setDistance(asRecord(item.state) as DistanceState);
          break;
        case "setRadioState":
          setRadio(normalizeRadioState(item.state));
          break;
        case "radioMessage": {
          const rawMessage = asRecord(item.message) as RadioMessage;
          const frequency = ensureString(rawMessage.frequency);
          if (frequency) {
            setRadio((current) => appendRadioMessage(current, rawMessage));
            if (!(activeIsRadio && currentRadioFrequency === frequency)) {
              setRadioUnread((current) => ({
                ...current,
                [frequency]: (current[frequency] || 0) + 1,
              }));
            }
          }
          break;
        }
        case "setWhisperTargets":
          setWhisperTargets(asArray<WhisperTarget>(item.targets));
          break;
        case "openReportModal":
          setReportModal({
            open: true,
            targetId: ensureString(item.targetId),
            reason: ensureString(item.reason),
            sourceMessageId: ensureString(item.sourceMessageId),
            context: asRecord(item.reportContext),
          });
          break;
        case "openManager":
          managerReturnToChatRef.current = showInputRef.current;
          setManagerOpen(true);
          void loadManager();
          break;
        case "setChannel":
          if (typeof item.channelId === "string") {
            rememberFolderSelection(item.channelId);
            setActiveChannelState(item.channelId);
            setNotificationUnread((current) => ({
              ...current,
              [item.channelId as string]: 0,
            }));
          }
          break;
        case "create3dMessage": {
          const id = ensureString(item.id);
          if (id) {
            const colorArray = asArray<number>(item.color);
            const color: [number, number, number] = [
              Number(colorArray[0]) || 255,
              Number(colorArray[1]) || 255,
              Number(colorArray[2]) || 255,
            ];
            setMessages3d((current) => ({
              ...current,
              [id]: {
                id,
                color,
                text: ensureString(item.text),
                timeout: Number(item.timeout) || 0,
                persistent: item.persistent === true,
                style: ensureString(item.style),
                floatUp: item.floatUp === true,
                onScreen: false,
                screenX: 0,
                screenY: 0,
              },
            }));
            if (!item.persistent && item.timeout) {
              setTimeout(() => {
                setMessages3d((current) => {
                  const next = { ...current };
                  delete next[id];
                  return next;
                });
              }, Number(item.timeout));
            }
          }
          break;
        }
        case "update3dMessage": {
          const id = ensureString(item.id);
          if (id) {
            setMessages3d((current) => {
              const existing = current[id];
              if (!existing) {
                return current;
              }
              return {
                ...current,
                [id]: {
                  ...existing,
                  onScreen: item.onScreen === true,
                  screenX: Number(item.screenX) || 0,
                  screenY: Number(item.screenY) || 0,
                },
              };
            });
          }
          break;
        }
        case "remove3dMessage": {
          const id = ensureString(item.id);
          if (id) {
            setMessages3d((current) => {
              const next = { ...current };
              delete next[id];
              return next;
            });
          }
          break;
        }
        default:
          break;
      }
    };

    window.addEventListener("message", listener);
    return () => window.removeEventListener("message", listener);
  }, [
    activeIsRadio,
    addOrUpdateMessage,
    bumpWindow,
    currentRadioFrequency,
    loadManager,
    rememberFolderSelection,
  ]);

  useEffect(() => {
    const gpsListener = (event: MouseEvent) => {
      const target = event.target as HTMLElement | null;
      const button = target?.closest?.(".gps-link") as HTMLElement | null;
      if (!button) {
        return;
      }
      void fetchNui("setWaypoint", {
        x: button.dataset.gpsX,
        y: button.dataset.gpsY,
        z: button.dataset.gpsZ,
      });
    };
    document.addEventListener("click", gpsListener);
    return () => document.removeEventListener("click", gpsListener);
  }, []);

  useEffect(() => {
    scrollActiveMessages(false);
  }, [activeMessages, currentRadioMessages, scrollActiveMessages]);

  const typingIndicatorActive = useMemo(() => {
    const draft = messageDraft.trim();
    return showInput && !shouldHide && draft.length > 0 && !draft.startsWith("/");
  }, [messageDraft, shouldHide, showInput]);

  useEffect(() => {
    void fetchNui("typingState", { active: typingIndicatorActive });
  }, [typingIndicatorActive]);

  useEffect(() => {
    if (colorPicker.open && !activeColorToken) {
      setColorPicker({ open: false, start: -1 });
    }
  }, [activeColorToken, colorPicker.open]);

  useEffect(() => {
    if (showInput || !showWindow) {
      return;
    }
    if (fadeTimerRef.current) {
      window.clearTimeout(fadeTimerRef.current);
    }
    const timeout = Math.max(0, Number(fadeTimeoutRef.current) || 0);
    if (timeout <= 0) {
      return;
    }
    fadeTimerRef.current = window.setTimeout(
      () => setShowWindow(false),
      timeout,
    );
    return () => {
      if (fadeTimerRef.current) {
        window.clearTimeout(fadeTimerRef.current);
      }
    };
  }, [showInput, showWindow]);

  const draftOverlay = useMemo(() => {
    const nodes: ReactNode[] = [];
    let cursor = 0;
    draftColorTokens.forEach((token) => {
      if (token.start > cursor) {
        nodes.push(
          <span key={`draft-text:${cursor}`}>
            {messageDraft.slice(cursor, token.start)}
          </span>,
        );
      }
      const color = displayHex(token.hex);
      nodes.push(
        <button
          type="button"
          key={`draft-chip:${token.start}`}
          className={`inline-color-chip${colorPicker.open && colorPicker.start === token.start ? " active" : ""}`}
          style={{ "--chip-color": `#${color}` } as CSSProperties}
          aria-label={`Edit color #${color}`}
          onMouseDown={(event) => {
            event.preventDefault();
            event.stopPropagation();
            setDraftPreviewOpen(true);
            setColorPicker({ open: true, start: token.start });
          }}
        />,
      );
      nodes.push(
        <span
          key={`draft-token:${token.start}`}
          className="draft-code-fragment"
        >{`#${token.hex}`}</span>,
      );
      cursor = token.end;
    });
    if (cursor < messageDraft.length) {
      nodes.push(
        <span key={`draft-text:${cursor}`}>{messageDraft.slice(cursor)}</span>,
      );
    }
    if (nodes.length === 0) {
      nodes.push(
        <span key="draft-empty" className="composer-placeholder">
          {" "}
        </span>,
      );
    }
    return nodes;
  }, [colorPicker.open, colorPicker.start, draftColorTokens, messageDraft]);

  const selectedContextMessageId = ensureString(
    contextMenu.message?.messageId || "",
  );
  const contextMessage = contextMenu.message;
  const contextType = contextMessage ? messageType(contextMessage) : "";
  const contextSource = contextMessage ? messageSourceId(contextMessage) : 0;
  const contextIsOwn =
    (contextSource > 0 && contextSource === playerServerId) ||
    ensureString(asRecord(contextMessage?.metadata).direction) === "out";
  const contextIsSystem =
    ["system", "join", "leave", "delete"].includes(contextType) ||
    ensureString(contextMessage?.label) === "System";
  const contextHasBody = contextMessage
    ? messageRawText(contextMessage).trim() !== ""
    : false;
  const contextCanWhisper = Boolean(
    contextMessage && !contextIsOwn && !contextIsSystem && contextSource > 0,
  );
  const contextCanReport = Boolean(
    contextMessage && permissions.moderation?.builtInReportsEnabled !== false,
  );
  const contextCanDelete = Boolean(
    contextMessage &&
    !contextIsSystem &&
    permissions.moderation?.canDeleteMessages &&
    ensureString(contextMessage.messageId),
  );
  const chatPanelOpacity = Math.max(0.7, Math.min(1, uiOpacity / 100));

  return (
    <div className={`app-root${loaded ? " loaded" : ""}`}>
      <section
        className={`chat-shell${showWindow || showInput ? " is-visible" : ""}${showInput ? " input-active" : ""}${shouldHide ? " is-hidden" : ""}`}
        style={
          {
            "--chat-panel-opacity": chatPanelOpacity,
            "--chat-font-family": chatFontFamily,
            "--chat-font-scale": chatFontScale,
          } as CSSProperties
        }
      >
        <div className="chat-window" onWheel={handleChatWheel}>
          {activeIsRadio ? (
            <div className="radio-view">
              <div className="radio-compact-head">
                <div>
                  <strong>Radio</strong>
                  <span>
                    {currentRadioFrequency
                      ? `Frequency ${currentRadioFrequency}`
                      : "No active frequency"}
                  </span>
                </div>
                <div className="radio-slots">
                  {(["primary", "secondary"] as const).map((slotName) => {
                    const slot = getRadioSlot(radio, slotName);
                    const frequency = ensureString(slot.frequency);
                    return (
                      <button
                        type="button"
                        key={slotName}
                        className={
                          radio.selectedSlot === slotName ? "active" : ""
                        }
                        style={{
                          borderColor: ensureString(slot.color, "#68d8a7"),
                        }}
                        data-hint={`${slotName === "primary" ? "Primary" : "Secondary"} radio slot`}
                        onClick={() => {
                          setRadio((current) => ({
                            ...current,
                            selectedSlot: slotName,
                          }));
                          if (frequency) {
                            setRadioUnread((current) => ({
                              ...current,
                              [frequency]: 0,
                            }));
                          }
                        }}
                      >
                        <strong>
                          {slotName === "primary" ? "CH1" : "CH2"}
                        </strong>
                        <span>{frequency || "Off"}</span>
                        {frequency && radioUnread[frequency] > 0 && (
                          <em>{radioUnread[frequency]}</em>
                        )}
                      </button>
                    );
                  })}
                </div>
              </div>
              <div
                className="radio-thread"
                ref={radioMessagesRef}
                onScroll={handleMessageScroll}
              >
                {radioStatus && (
                  <div className="radio-status">{radioStatus}</div>
                )}
                {currentRadioMessages.length === 0 && (
                  <div className="empty-state">
                    No radio traffic on this frequency.
                  </div>
                )}
                {renderedRadioMessages.map((message, index) => (
                  <div
                    className={`radio-message${Number(message.senderId) === playerServerId ? " own" : ""}`}
                    key={
                      message.clientMessageId || `${message.frequency}:${index}`
                    }
                  >
                    <div className="radio-message-meta">
                      <span>{ensureString(message.frequency)}</span>
                      <strong>{ensureString(message.sender, "Unknown")}</strong>
                      <time>{formatTimestamp(message.timestamp)}</time>
                    </div>
                    <p
                      dangerouslySetInnerHTML={{
                        __html: renderRichText(message.message),
                      }}
                    />
                  </div>
                ))}
              </div>
            </div>
          ) : activeIsWhispers ? (
            <div className="whisper-view">
              <aside className="whisper-sidebar">
                <div className="whisper-title">
                  <span>Conversations</span>
                  <button
                    type="button"
                    onClick={() => {
                      setWhisperPickerOpen((current) => !current);
                      void fetchNui("getWhisperTargets", {});
                    }}
                  >
                    <PanelRightOpen size={15} />
                  </button>
                </div>
                {whisperPickerOpen && (
                  <div className="whisper-picker">
                    <div className="form-row">
                      <input
                        value={manualWhisperTarget}
                        onChange={(event) =>
                          setManualWhisperTarget(event.target.value)
                        }
                        placeholder="Player ID"
                      />
                      <button
                        type="button"
                        onClick={() =>
                          startWhisper({
                            id: Number(manualWhisperTarget),
                            name: `Player ${manualWhisperTarget}`,
                          })
                        }
                      >
                        Open
                      </button>
                    </div>
                    {whisperTargets.map((target) => (
                      <button
                        type="button"
                        key={`target:${target.id}`}
                        onClick={() => startWhisper(target)}
                      >
                        <span>
                          {target.name || target.label || `Player ${target.id}`}
                        </span>
                        <small>ID {target.id}</small>
                      </button>
                    ))}
                  </div>
                )}
                {Object.values(whisperConversations)
                  .sort((a, b) => b.lastAt - a.lastAt)
                  .map((conversation) => (
                    <button
                      type="button"
                      className={
                        activeWhisperConversationId === conversation.id
                          ? "active"
                          : ""
                      }
                      key={conversation.id}
                      onClick={() => {
                        setActiveWhisperConversationId(conversation.id);
                        setWhisperConversations((current) => ({
                          ...current,
                          [conversation.id]: { ...conversation, unread: 0 },
                        }));
                      }}
                    >
                      <span>{conversation.peerName}</span>
                      {conversation.unread > 0 && (
                        <em>{conversation.unread}</em>
                      )}
                    </button>
                  ))}
              </aside>
              <div
                className="message-list"
                ref={whisperMessagesRef}
                onScroll={handleMessageScroll}
              >
                {activeMessages.length === 0 && (
                  <div className="empty-state">
                    No whisper messages in this conversation.
                  </div>
                )}
                {renderedActiveMessages.map((message, index) => (
                  <MessageRow
                    key={messageKey(message, index)}
                    message={message}
                    onContext={handleContext}
                    hideDeleted={hideDeleted}
                    selected={
                      selectedContextMessageId ===
                      ensureString(message.messageId)
                    }
                  />
                ))}
              </div>
            </div>
          ) : (
            <div
              className="message-list"
              ref={standardMessagesRef}
              onScroll={handleMessageScroll}
            >
              {activeMessages.length === 0 && (
                <div className="empty-state">
                  No messages in {activeChannelDef?.label || activeChannel} yet.
                </div>
              )}
              {renderedActiveMessages.map((message, index) => (
                <MessageRow
                  key={messageKey(message, index)}
                  message={message}
                  onContext={handleContext}
                  hideDeleted={hideDeleted}
                  selected={
                    selectedContextMessageId === ensureString(message.messageId)
                  }
                />
              ))}
            </div>
          )}
        </div>

        {showInput && (
          <div className="chat-input">
            <div className="channel-strip">
              <div className="channels">
                {chatTabItems.map((item) => {
                  const active =
                    item.type === "folder"
                      ? activeFolderGroupId === item.groupId
                      : activeChannel === item.channel?.id;
                  const unread = item.channels.reduce(
                    (total, channel) =>
                      total + (notificationUnread[channel.id] || 0),
                    0,
                  );
                  return (
                    <button
                      type="button"
                      key={item.key}
                      className={active ? "active" : ""}
                      style={
                        active ? undefined : { color: colorToCss(item.color) }
                      }
                      data-hint={
                        item.type === "folder"
                          ? `Open ${item.label} tabs`
                          : `Open ${item.label} chat`
                      }
                      onClick={() => activateChatTab(item)}
                    >
                      {item.type === "folder" ? (
                        <FolderClosed size={13} />
                      ) : (
                        <Hash size={13} />
                      )}
                      <span>{item.label}</span>
                      {unread > 0 && <em>{unread}</em>}
                    </button>
                  );
                })}
              </div>
              <div className="toolbar">
                <button
                  type="button"
                  data-hint="Open emoji library"
                  className={emojiOpen ? "active" : ""}
                  onClick={() => {
                    setEmojiOpen((current) => {
                      if (!current) {
                        void loadEmojiCatalog();
                        refreshEmojiPanel();
                      }
                      return !current;
                    });
                  }}
                >
                  <Smile size={17} />
                </button>
                <button
                  type="button"
                  data-hint="Cycle voice range"
                  className="range-button"
                  style={
                    {
                      "--range-color": ensureString(distance.color, "#68d8a7"),
                    } as CSSProperties
                  }
                  onClick={cycleDistance}
                >
                  <RangeIcon distance={distance} />
                  <span>
                    {ensureString(distance.label || distance.mode, "")}
                  </span>
                </button>
                <button
                  type="button"
                  data-hint="Keep chat pinned to newest messages"
                  className={autoScrollActive ? "active" : ""}
                  onClick={() =>
                    toggleFeature("toggleAutoScroll", "autoScroll")
                  }
                >
                  <ChevronsDown size={17} />
                </button>
                <button
                  type="button"
                  data-hint="Show typing indicators"
                  className={features.typing?.active === false ? "" : "active"}
                  onClick={() => toggleFeature("toggleTypingDisplay", "typing")}
                >
                  <MessageCircle size={17} />
                </button>
                <button
                  type="button"
                  data-hint="Show overhead bubbles"
                  className={features.bubbles?.active === false ? "" : "active"}
                  onClick={() =>
                    toggleFeature("toggleBubbleDisplay", "bubbles")
                  }
                >
                  <Bell size={17} />
                </button>
                <button
                  type="button"
                  data-hint="Toggle notification sound"
                  className={
                    features.whisperSound?.active === false ? "" : "active"
                  }
                  onClick={() =>
                    toggleFeature("toggleWhisperSound", "whisperSound")
                  }
                >
                  {features.whisperSound?.active === false ? (
                    <VolumeX size={17} />
                  ) : (
                    <Volume2 size={17} />
                  )}
                </button>
                <button
                  type="button"
                  data-hint="Open chat settings"
                  onClick={openManagerFromChat}
                >
                  <Settings size={17} />
                </button>
              </div>
            </div>
            {activeFolderChannels.length > 0 && (
              <div className="channel-substrip">
                {activeFolderChannels.map((channel) => (
                  <button
                    type="button"
                    key={`subtab:${channel.id}`}
                    className={activeChannel === channel.id ? "active" : ""}
                    style={
                      activeChannel === channel.id
                        ? undefined
                        : { color: colorToCss(channel.color) }
                    }
                    data-hint={`Open ${channel.label} chat`}
                    onClick={() => setActiveChannel(channel.id)}
                  >
                    <Hash size={12} />
                    <span>{channel.label}</span>
                    {(notificationUnread[channel.id] || 0) > 0 && (
                      <em>{notificationUnread[channel.id]}</em>
                    )}
                  </button>
                ))}
              </div>
            )}
            <div className="input-row">
              <div className="input-tools">
                <span className="input-prefix">&gt;</span>
                <button
                  type="button"
                  data-hint="Preview and edit ^#hex colors"
                  className={draftPreviewOpen ? "active" : ""}
                  onClick={() => setDraftPreviewOpen((current) => !current)}
                >
                  <Palette size={14} />
                </button>
              </div>
              <div className="composer-field">
                <div
                  className="composer-overlay"
                  ref={draftOverlayRef}
                  aria-hidden="true"
                >
                  {draftOverlay}
                </div>
                <textarea
                  ref={inputRef}
                  value={messageDraft}
                  onChange={(event) => handleDraftChange(event.target.value)}
                  onKeyDown={handleKeyDown}
                  onScroll={(event) => {
                    if (draftOverlayRef.current) {
                      draftOverlayRef.current.scrollTop =
                        event.currentTarget.scrollTop;
                    }
                  }}
                  placeholder={
                    activeIsRadio
                      ? "Send radio traffic..."
                      : activeIsWhispers
                        ? "Send a whisper..."
                        : `Message ${activeChannelDef?.label || activeChannel}`
                  }
                  spellCheck={false}
                />
              </div>
              <button
                type="button"
                className="send-button"
                data-hint="Send message"
                onClick={() => void sendMessage()}
              >
                <Send size={18} />
              </button>
            </div>
            {draftPreviewOpen && (
              <div className="draft-color-panel">
                <div className="draft-preview-card">
                  <span>Preview</span>
                  <div
                    className="draft-preview"
                    dangerouslySetInnerHTML={{ __html: draftPreviewHtml }}
                  />
                </div>
                {draftColorTokens.length > 0 && (
                  <div className="color-token-list">
                    {draftColorTokens.map((item, index) => {
                      const hex = displayHex(item.hex);
                      return (
                        <button
                          key={`color:${item.start}:${item.hex}`}
                          type="button"
                          className={`color-token${activeColorToken?.start === item.start ? " active" : ""}`}
                          onClick={() =>
                            setColorPicker({ open: true, start: item.start })
                          }
                        >
                          <span style={{ background: `#${hex}` }} />
                          <code>{`^#${hex}`}</code>
                          <small>{index + 1}</small>
                        </button>
                      );
                    })}
                  </div>
                )}
                {colorPicker.open && activeColorToken && (
                  <HexColorPicker
                    hex={displayHex(activeColorToken.hex)}
                    tokenLabel={`^#${displayHex(activeColorToken.hex)}`}
                    onChange={(hex) =>
                      replaceDraftColorAt(activeColorToken.start, hex)
                    }
                    onClose={() => setColorPicker({ open: false, start: -1 })}
                  />
                )}
                <div className="color-section">
                  <span>FiveM colors</span>
                  <div className="quick-colors labeled">
                    {defaultFiveMColors.map((item) => (
                      <button
                        type="button"
                        key={`fivem-color:${item.code}`}
                        style={
                          { "--swatch-color": item.color } as CSSProperties
                        }
                        onClick={() => insertDraftCode(item.code)}
                      >
                        <span />
                        <code>{item.label}</code>
                      </button>
                    ))}
                  </div>
                </div>
                <div className="color-section">
                  <span>Text formats</span>
                  <div className="quick-formats">
                    {defaultFiveMFormats.map((item) => (
                      <button
                        type="button"
                        key={`fivem-format:${item.code}`}
                        onClick={() => insertDraftCode(item.code)}
                      >
                        <code>{item.label}</code>
                        <span>{item.name}</span>
                      </button>
                    ))}
                  </div>
                </div>
                <div className="color-section">
                  <span>Last hex colors</span>
                  <div className="quick-colors">
                    {(hexHistory.length > 0
                      ? hexHistory
                      : defaultHexColors
                    ).map((hex) => (
                      <button
                        type="button"
                        key={`quick-color:${hex}`}
                        style={{ background: `#${hex}` }}
                        onClick={() => insertDraftColor(hex)}
                        aria-label={`Insert #${hex}`}
                      />
                    ))}
                  </div>
                </div>
              </div>
            )}
            <Suggestions
              input={messageDraft}
              suggestions={suggestions}
              onPickSuggestion={applySuggestion}
              onPickParam={pickSuggestionParam}
            />
            {paramPicker.open && (
              <div className="param-picker">
                <div>
                  <strong>{paramPicker.param?.name || "Argument"}</strong>
                  <span>{paramPicker.param?.help || paramPicker.type}</span>
                </div>
                {paramPicker.type === "player" ? (
                  <div className="param-player-list">
                    {whisperTargets.map((target) => (
                      <button
                        type="button"
                        key={`param-target:${target.id}`}
                        onClick={() => appendCommandToken(String(target.id))}
                      >
                        <span>
                          {target.name || target.label || `Player ${target.id}`}
                        </span>
                        <small>ID {target.id}</small>
                      </button>
                    ))}
                    {whisperTargets.length === 0 && (
                      <span className="quiet">
                        No nearby player list returned yet.
                      </span>
                    )}
                  </div>
                ) : (
                  <>
                    {paramPicker.type === "number" && (
                      <div className="quick-values">
                        {[1, 10, 100, 1000].map((value) => (
                          <button
                            type="button"
                            key={`quick-number:${value}`}
                            onClick={() =>
                              setParamPicker((current) => ({
                                ...current,
                                value: String(value),
                              }))
                            }
                          >
                            {value}
                          </button>
                        ))}
                      </div>
                    )}
                    <div className="form-row">
                      <input
                        type={paramPicker.type === "number" ? "number" : "text"}
                        value={paramPicker.value}
                        onChange={(event) =>
                          setParamPicker((current) => ({
                            ...current,
                            value: event.target.value,
                          }))
                        }
                        placeholder={paramPicker.param?.name || "value"}
                      />
                      {paramPicker.type === "number" && (
                        <div className="numeric-stepper">
                          <button
                            type="button"
                            onClick={() =>
                              setParamPicker((current) => ({
                                ...current,
                                value: String(
                                  Math.max(0, Number(current.value || 0) - 1),
                                ),
                              }))
                            }
                          >
                            -
                          </button>
                          <button
                            type="button"
                            onClick={() =>
                              setParamPicker((current) => ({
                                ...current,
                                value: String(Number(current.value || 0) + 1),
                              }))
                            }
                          >
                            +
                          </button>
                        </div>
                      )}
                      <button
                        type="button"
                        className="primary"
                        onClick={() => appendCommandToken(paramPicker.value)}
                      >
                        Insert
                      </button>
                    </div>
                  </>
                )}
              </div>
            )}
            {emojiOpen && (
              <EmojiPanel
                emojis={emojis}
                recent={emojiPanel.recent}
                top={emojiPanel.top}
                query={emojiQuery}
                setQuery={setEmojiQuery}
                onPick={pickEmoji}
              />
            )}
          </div>
        )}

        {contextMenu.open && contextMenu.message && (
          <div
            className="context-backdrop"
            onMouseDown={() => setContextMenu({ open: false, x: 0, y: 0 })}
          >
            <div
              className="context-menu"
              style={{ left: contextMenu.x, top: contextMenu.y }}
              onMouseDown={(event) => event.stopPropagation()}
            >
              {contextHasBody && (
                <button
                  type="button"
                  onClick={() => handleContextAction("copy")}
                >
                  <Clipboard size={14} /> Copy raw
                </button>
              )}
              {contextCanWhisper && (
                <button
                  type="button"
                  onClick={() => handleContextAction("whisper")}
                >
                  <MessageCircle size={14} /> Whisper
                </button>
              )}
              {contextCanReport && (
                <button
                  type="button"
                  onClick={() => handleContextAction("report")}
                >
                  <Shield size={14} /> Report
                </button>
              )}
              {contextCanDelete && (
                <button
                  type="button"
                  className="danger"
                  onClick={() => handleContextAction("delete")}
                >
                  <Trash2 size={14} /> Delete
                </button>
              )}
            </div>
          </div>
        )}

        {reportModal.open && (
          <div
            className="modal-backdrop"
            onMouseDown={() => setReportModal(emptyReport)}
          >
            <div
              className="report-modal"
              onMouseDown={(event) => event.stopPropagation()}
            >
              <div className="modal-header">
                <h2>Report Message</h2>
                <button
                  type="button"
                  onClick={() => setReportModal(emptyReport)}
                >
                  <X size={17} />
                </button>
              </div>
              <label>
                <span>Target ID</span>
                <input
                  value={reportModal.targetId}
                  onChange={(event) =>
                    setReportModal((current) => ({
                      ...current,
                      targetId: event.target.value,
                    }))
                  }
                />
              </label>
              {reportModal.context && (
                <div className="report-context">
                  {ensureString(
                    reportModal.context.renderedMessage ||
                      reportModal.context.excerpt ||
                      reportModal.context.rawMessage,
                  )}
                </div>
              )}
              <label>
                <span>Reason</span>
                <textarea
                  value={reportModal.reason}
                  onChange={(event) =>
                    setReportModal((current) => ({
                      ...current,
                      reason: event.target.value,
                    }))
                  }
                />
              </label>
              <div className="manager-actions">
                <button
                  type="button"
                  onClick={() => setReportModal(emptyReport)}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  className="primary"
                  onClick={submitReport}
                >
                  Send Report
                </button>
              </div>
            </div>
          </div>
        )}
      </section>

      <ManagerPanel
        open={managerOpen}
        channels={channels}
        permissions={permissions}
        playerSettings={playerSettings}
        managerState={managerState}
        onClose={closeManager}
        onRefresh={loadManager}
        onSavePlayerSettings={savePlayerSettings}
        onManagerRequest={requestManager}
        returnToChat={managerReturnToChatRef.current}
      />

      {!showInput && !managerOpen && (
        <div className="ambient-status">
          {staffAllowed ? <Shield size={14} /> : <BellOff size={14} />}
          <span>{loaded ? "PoodleChat" : "Loading chat..."}</span>
        </div>
      )}

      <div id="messages-3d" className="messages-3d">
        {Object.entries(messages3d).map(([id, message]) => (
          <div
            key={id}
            id={`message3d-${id}`}
            className={`message3d${message.style === "bubble" || id.startsWith("bubble-") ? " is-bubble" : ""}${id.startsWith("typing-") ? " is-typing-bubble" : ""}${message.floatUp ? " is-float-up" : ""}`}
            style={{
              display: message.onScreen ? "block" : "none",
              top: `${(message.screenY || 0) * 100}vh`,
              left: `${(message.screenX || 0) * 100}vw`,
              color: `rgb(${message.color[0]}, ${message.color[1]}, ${message.color[2]})`,
            }}
          >
            {id.startsWith("typing-") ? (
              <span className="typing-dots">
                <span></span>
                <span></span>
                <span></span>
              </span>
            ) : (
              <span
                dangerouslySetInnerHTML={{
                  __html: ensureString(message.text, ""),
                }}
              />
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
