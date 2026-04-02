function uiRuntimeValue(key, fallback) {
	const runtime = getRuntimeUiConfig().runtime || {};
	const value = Number(runtime[key]);
	if (Number.isFinite(value)) {
		return value;
	}
	return fallback;
}

function normalizeLimit(value, fallback) {
	const parsed = Number(value);
	if (Number.isFinite(parsed)) {
		if (parsed < 0) {
			return -1;
		}
		if (parsed === 0) {
			return Math.max(1, Number(fallback) || 1);
		}
		return Math.floor(parsed);
	}
	return Math.max(1, Number(fallback) || 1);
}

window.APP = {
	template: '#app_template',
	name: 'app',
	data() {
		return {
			style: { ...getRuntimeUiConfig().style },
			showInput: false,
			showWindow: false,
			shouldHide: true,
			backingSuggestions: [],
			removedSuggestions: [],
			templates: { ...getRuntimeUiConfig().templates },
			message: '',
			channels: [],
			messagesByChannel: {},
			unreadByChannel: {},
			activeChannelId: '',
			separateChannelTabs: true,
			singleChannelId: 'local',
			whisperTabEnabled: true,
			whisperFallbackChannel: 'local',
			whisperConversations: {},
			hiddenWhisperConversations: {},
			activeWhisperConversationId: null,
			whisperPickerOpen: false,
			whisperTargets: [],
			whisperSidebarCollapsible: true,
			whisperSidebarCollapsed: false,
			autoScrollEnabled: true,
			myServerId: 0,
			whisperNotificationVolume: 0.65,
			nextMessageId: 1,
			whisperLimits: {
				maxConversations: 30,
				maxMessagesPerConversation: 80,
				defaultConversationMode: 'active-only',
				separateWhisperTab: true,
				fallbackChannel: 'local'
			},
			oldMessages: [],
			oldMessagesIndex: -1,
			tplBackups: [],
			msgTplBackups: [],
			listener: null,
			showWindowTimer: null,
			focusTimer: null,
			lastTypingState: false,
			distanceState: { enabled: false },
			featureState: {
				typing: { enabled: false, allowToggle: false, active: false },
				bubbles: { enabled: false, allowToggle: false, active: false },
				autoScroll: { enabled: true, allowToggle: true, active: true },
				whisperSound: { enabled: true, allowToggle: true, active: true, volume: 0.65 },
				distance: { enabled: false }
			}
		};
	},
	destroyed() {
		clearTimeout(this.focusTimer);
		clearTimeout(this.showWindowTimer);
		clearTimeout(emojiState.searchTimer);
		if (this.listener) {
			window.removeEventListener('message', this.listener);
		}
		window.APP_INSTANCE = null;
	},
	mounted() {
		window.APP_INSTANCE = this;
		postJson('loaded', {});
		this.listener = (event) => {
			const item = event.data || event.detail;
			if (!item || !item.type) {
				return;
			}
			if (typeof this[item.type] === 'function') {
				try {
					this[item.type](item);
				} catch (error) {
					console.error('poodlechat ui handler failed', item.type, error);
				}
			}
		};
		window.addEventListener('message', this.listener);
	},
	watch: {
		message() {
			this.syncTypingState(false);
		},
		activeChannelId() {
			if (!this.separateChannelTabs) {
				const single = this.singleAllowedChannelId();
				if (single && this.activeChannelId !== single) {
					this.setChannel({ channelId: single });
					return;
				}
			}
			if (this.activeChannelId === 'whispers' && this.whisperTabEnabled && !this.activeWhisperConversationId) {
				const first = this.whisperConversationList[0];
				if (first) {
					this.activeWhisperConversationId = first.id;
				}
			}
			if (this.activeChannelId !== 'whispers') {
				this.whisperPickerOpen = false;
			}
			this.$nextTick(() => this.scrollActiveMessages(false));
		}
	},
	computed: {
		suggestions() {
			return this.backingSuggestions.filter((el) => this.removedSuggestions.indexOf(el.name) <= -1);
		},
		visibleChannels() {
			const sorted = this.channels
				.filter((channel) => channel.visible !== false && channel.allowed !== false)
				.sort((a, b) => {
					if (a.order === b.order) {
						return String(a.id).localeCompare(String(b.id));
					}
					return a.order - b.order;
				});
			if (this.separateChannelTabs) {
				return sorted;
			}
			const preferred = sorted.find((channel) => channel.id === this.singleChannelId);
			if (preferred) {
				return [preferred];
			}
			return sorted.length > 0 ? [sorted[0]] : [];
		},
		currentMessages() {
			return this.messagesByChannel[this.activeChannelId] || [];
		},
		isWhispersActive() {
			return this.whisperTabEnabled && this.activeChannelId === 'whispers';
		},
		whisperConversationList() {
			return Object.values(this.whisperConversations)
				.filter((conversation) => this.hiddenWhisperConversations[conversation.id] !== true)
				.sort((a, b) => {
					if (a.lastAt === b.lastAt) {
						return String(a.id).localeCompare(String(b.id));
					}
					return b.lastAt - a.lastAt;
				})
				.map((conversation) => {
					const peerId = Number(conversation.peerId);
					let peerShortId = '';
					if (Number.isFinite(peerId) && peerId > 0) {
						peerShortId = String(Math.floor(peerId));
					} else {
						peerShortId = String(conversation.id || '').replace(/^id:/, '') || 'DM';
					}
					return {
						...conversation,
						peerShortId
					};
				});
		},
		hasWhisperUnreadDot() {
			return Object.values(this.whisperConversations).some((conversation) => Number(conversation.unread) > 0);
		},
		isWhisperSidebarCollapsed() {
			return this.whisperSidebarCollapsible && this.whisperSidebarCollapsed;
		},
		activeWhisperMessages() {
			if (!this.activeWhisperConversationId) {
				return [];
			}
			const conversation = this.whisperConversations[this.activeWhisperConversationId];
			return conversation ? conversation.messages : [];
		}
	},
	methods: {
		ON_SCREEN_STATE_CHANGE({ shouldHide }) {
			this.shouldHide = shouldHide;
			if (shouldHide) {
				this.syncTypingState(true);
			}
		},
		ON_OPEN() {
			this.showInput = true;
			this.bumpWindow();
			clearTimeout(this.focusTimer);
			this.focusTimer = setTimeout(() => {
				if (this.$refs.input) {
					this.$refs.input.focus();
				}
			}, uiRuntimeValue('inputFocusDelayMs', 100));
			this.syncTypingState(true);
		},
		ON_MESSAGE({ message }) {
			if (!message || typeof message !== 'object') {
				return;
			}

			const normalized = this.normalizeIncomingMessage(message);
			this.pushMessage(normalized);
			const isOwn = this.isOwnMessage(normalized);

			let shouldMarkUnread = !isOwn && normalized.channel !== this.activeChannelId;
			if (!shouldMarkUnread && this.isWhispersActive && normalized.channel === 'whispers') {
				const messageConversation = normalized.metadata && normalized.metadata.conversationId
					? String(normalized.metadata.conversationId)
					: null;
				shouldMarkUnread = !isOwn && !!messageConversation && messageConversation !== this.activeWhisperConversationId;
			}
			if (this.whisperTabEnabled && normalized.channel === 'whispers') {
				this.syncWhisperChannelUnread();
			} else if (shouldMarkUnread) {
				this.incrementChannelUnread(normalized.channel, 1);
			}

			const metadata = normalized.metadata || {};
			const incomingWhisper = metadata.type === 'whisper' && metadata.direction === 'in';
			if (
				incomingWhisper &&
				(!this.whisperTabEnabled || normalized.channel !== 'whispers') &&
				!this.showInput &&
				this.featureState.whisperSound &&
				this.featureState.whisperSound.active
			) {
				this.playWhisperNotificationSound();
			}

			this.bumpWindow();
			this.$nextTick(() => {
				this.scrollActiveMessagesIfNeeded(normalized);
			});
		},
		ON_CLEAR() {
			this.messagesByChannel = {};
			for (let i = 0; i < this.channels.length; i += 1) {
				this.ensureChannelHistory(this.channels[i].id);
			}
			this.whisperConversations = {};
			this.hiddenWhisperConversations = {};
			this.activeWhisperConversationId = null;
			this.whisperPickerOpen = false;
			this.whisperTargets = [];
			this.unreadByChannel = {};
			this.oldMessages = [];
			this.oldMessagesIndex = -1;
		},
		ON_SUGGESTION_ADD({ suggestion }) {
			const duplicateSuggestion = this.backingSuggestions.find((item) => item.name === suggestion.name);
			if (duplicateSuggestion) {
				if (suggestion.help || suggestion.params) {
					duplicateSuggestion.help = suggestion.help || '';
					duplicateSuggestion.params = suggestion.params || [];
				}
				return;
			}
			if (!suggestion.params) {
				suggestion.params = [];
			}
			this.backingSuggestions.push(suggestion);
		},
		ON_SUGGESTIONS_ADD({ suggestions }) {
			const list = ensureArray(suggestions);
			for (let i = 0; i < list.length; i += 1) {
				this.ON_SUGGESTION_ADD({ suggestion: list[i] });
			}
		},
		ON_SUGGESTION_REMOVE({ name }) {
			if (this.removedSuggestions.indexOf(name) <= -1) {
				this.removedSuggestions.push(name);
			}
		},
		ON_TEMPLATE_ADD({ template }) {
			if (!template || !template.id) {
				return;
			}
			if (this.templates[template.id]) {
				this.warn(`Tried to add duplicate template '${template.id}'`);
			} else {
				this.templates[template.id] = template.html;
			}
		},
		ON_UPDATE_THEMES({ themes }) {
			this.removeThemes();
			this.setThemes(themes || {});
		},
		setDistanceState({ state }) {
			this.distanceState = normalizeDistanceState(state);
			updateDistanceWidget(this.distanceState);
		},
		setFeatureState({ state }) {
			this.featureState = normalizeFeatureState(state);
			if (this.featureState.autoScroll) {
				this.autoScrollEnabled = this.featureState.autoScroll.active !== false;
			}
			const volume = Number(this.featureState.whisperSound && this.featureState.whisperSound.volume);
			if (Number.isFinite(volume)) {
				this.whisperNotificationVolume = Math.max(0, Math.min(1, volume));
			}
			updateFeatureButtons(this.featureState);
		},
		setWhisperTargets({ targets }) {
			this.whisperTargets = ensureArray(targets)
				.filter((entry) => entry && typeof entry === 'object')
				.map((entry) => ({
					id: Number(entry.id) || 0,
					name: ensureString(entry.name, ''),
					label: ensureString(entry.label, ''),
					fivemName: ensureString(entry.fivemName, '')
				}))
				.filter((entry) => entry.id > 0)
				.sort((a, b) => a.id - b.id);
		},
		applyRuntimeUiConfig(rawConfig) {
			applyRuntimeUiConfig(rawConfig);
			const config = getRuntimeUiConfig();
			this.style = { ...config.style };
			this.templates = {
				...this.templates,
				...config.templates
			};
		},
		applyInitialPayload(payload) {
			const data = payload || {};
			this.applyRuntimeUiConfig(data.ui || {});
			this.myServerId = Number(data.playerServerId) || 0;
			if (data.ui && typeof data.ui === 'object') {
				this.separateChannelTabs = data.ui.separateChannelTabs !== false;
				this.singleChannelId = ensureString(data.ui.singleChannelId, 'local');
				if (typeof data.ui.autoScrollDefault === 'boolean') {
					this.autoScrollEnabled = data.ui.autoScrollDefault;
				}
			}

			if (data.whispers && typeof data.whispers === 'object') {
				this.whisperLimits.maxConversations = normalizeLimit(data.whispers.maxConversations, 30);
				this.whisperLimits.maxMessagesPerConversation = normalizeLimit(data.whispers.maxMessagesPerConversation, 80);
				this.whisperLimits.defaultConversationMode = ensureString(data.whispers.defaultConversationMode, 'active-only');
				this.whisperTabEnabled = data.whispers.separateWhisperTab !== false;
				this.whisperFallbackChannel = ensureString(data.whispers.fallbackChannel, 'local');

				if (data.whispers.sidebar && typeof data.whispers.sidebar === 'object') {
					this.whisperSidebarCollapsible = data.whispers.sidebar.collapsible !== false;
					this.whisperSidebarCollapsed = data.whispers.sidebar.defaultCollapsed === true;
				}

				if (data.whispers.notifications && typeof data.whispers.notifications === 'object') {
					const volume = Number(data.whispers.notifications.volume);
					if (Number.isFinite(volume)) {
						this.whisperNotificationVolume = Math.max(0, Math.min(1, volume));
					}
				}
			}

			this.applyChannels(data.channels || [], data.activeChannel || '');

			if (data.features) {
				this.setFeatureState({ state: data.features });
			} else {
				updateFeatureButtons({});
			}

			if (data.distance) {
				this.setDistanceState({ state: data.distance });
			} else {
				updateDistanceWidget({});
			}

			bootstrapEmojiDataset(data || {});
		},
		applyChannels(rawChannels, desiredActiveChannel) {
			const channels = ensureArray(rawChannels)
				.filter((channel) => channel && typeof channel === 'object' && typeof channel.id === 'string')
				.map((channel) => ({
					id: String(channel.id),
					label: ensureString(channel.label, channel.id),
					color: Array.isArray(channel.color) ? channel.color : [255, 255, 255],
					order: Number.isFinite(Number(channel.order)) ? Number(channel.order) : 100,
					visible: (this.whisperTabEnabled || String(channel.id) !== 'whispers') ? channel.visible !== false : false,
					cycle: channel.cycle !== false,
					maxHistory: normalizeLimit(channel.maxHistory, 250),
					allowed: channel.allowed !== false
				}));

			this.channels = channels;
			const nextUnreadByChannel = {};
			for (let i = 0; i < channels.length; i += 1) {
				const id = channels[i].id;
				nextUnreadByChannel[id] = Number(this.unreadByChannel[id]) || 0;
			}
			this.unreadByChannel = nextUnreadByChannel;
			for (let i = 0; i < channels.length; i += 1) {
				this.ensureChannelHistory(channels[i].id);
			}

			let nextChannel = desiredActiveChannel || this.activeChannelId;
			if (!this.separateChannelTabs) {
				nextChannel = this.singleAllowedChannelId() || nextChannel;
			}
			if (!this.isChannelAllowedById(nextChannel)) {
				nextChannel = this.firstAllowedChannelId();
			}

			if (!nextChannel && channels.length > 0) {
				nextChannel = channels[0].id;
			}

			this.setChannel({ channelId: nextChannel || 'global' });
		},
		setChannel({ channelId }) {
			let target = ensureString(channelId, '');
			if (!this.separateChannelTabs) {
				target = this.singleAllowedChannelId() || target;
			}
			if (!this.whisperTabEnabled && target === 'whispers') {
				target = this.whisperFallbackChannel || this.firstAllowedChannelId();
			}
			if (!this.isChannelAllowedById(target)) {
				target = this.firstAllowedChannelId();
			}
			if (!target) {
				return;
			}
			this.activeChannelId = target;
			this.clearChannelUnread(target);
			if (this.isWhispersActive && this.activeWhisperConversationId && this.whisperConversations[this.activeWhisperConversationId]) {
				this.whisperConversations[this.activeWhisperConversationId].unread = 0;
			}
			if (target === 'whispers') {
				this.syncWhisperChannelUnread();
			}
		},
		channelUnread(channelId) {
			return Number(this.unreadByChannel[channelId]) || 0;
		},
		incrementChannelUnread(channelId, amount) {
			const id = ensureString(channelId, '');
			if (!id) {
				return;
			}
			const current = Number(this.unreadByChannel[id]) || 0;
			const delta = Math.max(1, Number(amount) || 1);
			this.$set(this.unreadByChannel, id, current + delta);
		},
		clearChannelUnread(channelId) {
			const id = ensureString(channelId, '');
			if (!id) {
				return;
			}
			this.$set(this.unreadByChannel, id, 0);
		},
		singleAllowedChannelId() {
			const preferred = this.channels.find((channel) => channel.id === this.singleChannelId && channel.visible !== false && channel.allowed !== false);
			if (preferred) {
				return preferred.id;
			}
			const fallback = this.channels.find((channel) => channel.visible !== false && channel.allowed !== false);
			return fallback ? fallback.id : '';
		},
		isOwnMessage(message) {
			const metadata = message && message.metadata ? message.metadata : {};
			const source = Number(metadata.source);
			if (Number.isFinite(source) && this.myServerId > 0 && source === this.myServerId) {
				return true;
			}
			return metadata.type === 'whisper' && metadata.direction === 'out';
		},
		syncWhisperChannelUnread() {
			if (!this.whisperTabEnabled || !this.channelById('whispers')) {
				return;
			}
			const hasUnread = Object.values(this.whisperConversations).some((conversation) => Number(conversation.unread) > 0);
			this.$set(this.unreadByChannel, 'whispers', hasUnread ? 1 : 0);
		},
		setPermissions(payload) {
			let permissions = {};
			if (payload && typeof payload.permissions === 'string') {
				try {
					permissions = JSON.parse(payload.permissions) || {};
				} catch (error) {
					permissions = {};
				}
			} else if (payload && typeof payload.permissions === 'object') {
				permissions = payload.permissions;
			}

			if (Array.isArray(payload && payload.channels)) {
				this.applyChannels(payload.channels, payload.activeChannel || this.activeChannelId);
			} else if (permissions.channels && typeof permissions.channels === 'object') {
				this.channels = this.channels.map((channel) => ({
					...channel,
					allowed: permissions.channels[channel.id] !== false
				}));
				if (!this.isChannelAllowedById(this.activeChannelId)) {
					const fallback = this.firstAllowedChannelId();
					if (fallback) {
						this.setChannel({ channelId: fallback });
					}
				}
			}
		},
		normalizeIncomingMessage(message) {
			const normalized = { ...message };
			let channelId = ensureString(normalized.channel, '');
			if (!channelId || !this.channelById(channelId)) {
				channelId = this.activeChannelId || this.firstAllowedChannelId() || 'global';
			}

			normalized.channel = channelId;
			normalized.label = ensureString(normalized.label, (this.channelById(channelId) || {}).label || 'Chat');
			normalized.color = Array.isArray(normalized.color) ? normalized.color : ((this.channelById(channelId) || {}).color || [255, 255, 255]);
			normalized.args = Array.isArray(normalized.args)
				? normalized.args
				: [ensureString(normalized.text, normalized.label)];
			normalized.metadata = normalized.metadata && typeof normalized.metadata === 'object' ? normalized.metadata : {};
			normalized._id = this.nextMessageId;
			this.nextMessageId += 1;

			return normalized;
		},
		pushMessage(message) {
			if (this.whisperTabEnabled && message.metadata && message.metadata.type === 'whisper' && message.metadata.conversationId) {
				this.pushWhisperMessage(message);
				return;
			}

			this.ensureChannelHistory(message.channel);
			this.messagesByChannel[message.channel].push(message);
			this.trimChannelHistory(message.channel);
		},
		pushWhisperMessage(message) {
			const metadata = message.metadata || {};
			let conversationId = String(metadata.conversationId || metadata.peerId || 'conversation');
			const peerId = Number(metadata.peerId) || null;
			const existingConversationId = peerId ? this.findWhisperConversationIdByPeer(peerId) : null;
			if (existingConversationId && !this.whisperConversations[conversationId]) {
				conversationId = existingConversationId;
			}

			message.metadata = {
				...metadata,
				conversationId
			};
			const normalizedMetadata = message.metadata;

			const defaultPeerName = normalizedMetadata.peerName || (normalizedMetadata.peerId ? `Player ${normalizedMetadata.peerId}` : 'Unknown');
			const conversation = this.whisperConversations[conversationId] || {
				id: conversationId,
				peerName: defaultPeerName,
				peerId,
				messages: [],
				lastAt: 0,
				unread: 0
			};

			conversation.peerName = normalizedMetadata.peerName || conversation.peerName || defaultPeerName;
			conversation.peerId = peerId || conversation.peerId;
			conversation.messages.push(message);
			if (this.whisperLimits.maxMessagesPerConversation !== -1 && conversation.messages.length > this.whisperLimits.maxMessagesPerConversation) {
				conversation.messages.splice(0, conversation.messages.length - this.whisperLimits.maxMessagesPerConversation);
			}
			conversation.lastAt = Date.now();

			const direction = ensureString(normalizedMetadata.direction, '');
			const incoming = direction === 'in';
			if (this.isWhispersActive && this.activeWhisperConversationId === conversationId) {
				conversation.unread = 0;
			} else if (incoming) {
				conversation.unread += 1;
			}

			this.$delete(this.hiddenWhisperConversations, conversationId);
			this.$set(this.whisperConversations, conversationId, conversation);
			this.trimWhisperConversations();

			if (direction === 'out') {
				this.setChannel({ channelId: 'whispers' });
				this.activeWhisperConversationId = conversationId;
				conversation.unread = 0;
			} else if (!this.activeWhisperConversationId) {
				this.activeWhisperConversationId = conversationId;
			}
			this.syncWhisperChannelUnread();

			if (incoming && !this.showInput && this.featureState.whisperSound && this.featureState.whisperSound.active) {
				this.playWhisperNotificationSound();
			}
		},
		trimWhisperConversations() {
			const maxConversations = normalizeLimit(this.whisperLimits.maxConversations, 30);
			if (maxConversations === -1) {
				return;
			}
			const entries = Object.values(this.whisperConversations)
				.sort((a, b) => b.lastAt - a.lastAt);

			if (entries.length <= maxConversations) {
				return;
			}

			for (let i = maxConversations; i < entries.length; i += 1) {
				this.$delete(this.whisperConversations, entries[i].id);
				this.$delete(this.hiddenWhisperConversations, entries[i].id);
			}

			if (this.activeWhisperConversationId && !this.whisperConversations[this.activeWhisperConversationId]) {
				this.activeWhisperConversationId = entries[0] ? entries[0].id : null;
			}
		},
		findWhisperConversationIdByPeer(peerId) {
			if (!peerId) {
				return null;
			}
			const numericPeer = Number(peerId);
			const entries = Object.values(this.whisperConversations);
			for (let i = 0; i < entries.length; i += 1) {
				if (Number(entries[i].peerId) === numericPeer) {
					return entries[i].id;
				}
			}
			return null;
		},
		selectWhisperConversation(conversationId) {
			if (!conversationId || !this.whisperConversations[conversationId]) {
				return;
			}
			this.$delete(this.hiddenWhisperConversations, conversationId);
			this.activeWhisperConversationId = conversationId;
			this.whisperConversations[conversationId].unread = 0;
			if (this.isWhispersActive) {
				this.clearChannelUnread('whispers');
			}
			this.syncWhisperChannelUnread();
			this.whisperPickerOpen = false;
			this.$nextTick(() => this.scrollActiveMessages(false));
		},
		closeWhisperConversation(conversationId) {
			if (!conversationId || !this.whisperConversations[conversationId]) {
				return;
			}
			this.$set(this.hiddenWhisperConversations, conversationId, true);
			if (this.activeWhisperConversationId === conversationId) {
				const first = this.whisperConversationList[0];
				this.activeWhisperConversationId = first ? first.id : null;
			}
			this.syncWhisperChannelUnread();
		},
		toggleWhisperSidebarMode() {
			if (!this.whisperSidebarCollapsible) {
				return;
			}
			this.whisperSidebarCollapsed = !this.whisperSidebarCollapsed;
		},
		toggleWhisperPicker() {
			if (!this.whisperTabEnabled) {
				return;
			}

			const next = !this.whisperPickerOpen;
			this.whisperPickerOpen = next;
			if (!next) {
				return;
			}

			fetchJson('getWhisperTargets', {}).catch(() => null);
		},
		startWhisperConversation(player) {
			const peerId = Number(player && player.id);
			if (!Number.isFinite(peerId) || peerId <= 0) {
				return;
			}

			let conversationId = this.findWhisperConversationIdByPeer(peerId);
			if (!conversationId) {
				conversationId = `id:${peerId}`;
				this.$set(this.whisperConversations, conversationId, {
					id: conversationId,
					peerName: ensureString(player.name, '') || ensureString(player.label, `Player ${peerId}`),
					peerId,
					messages: [],
					lastAt: Date.now(),
					unread: 0
				});
			}

			this.$delete(this.hiddenWhisperConversations, conversationId);
			this.activeWhisperConversationId = conversationId;
			this.whisperPickerOpen = false;
			this.setChannel({ channelId: 'whispers' });
			this.$nextTick(() => this.scrollActiveMessages(false));
		},
		playWhisperNotificationSound() {
			const volume = Math.max(0, Math.min(1, Number(this.whisperNotificationVolume) || 0.65));
			if (volume <= 0) {
				return;
			}
			postJson('playWhisperSound', { volume });
		},
		selectChannel(channelId) {
			if (!this.isChannelAllowedById(channelId)) {
				return;
			}
			this.setChannel({ channelId });
			fetchJson('setChannel', { channelId }).catch(() => null);
			const input = document.querySelector('textarea');
			if (input) {
				input.focus();
			}
		},
		channelById(channelId) {
			for (let i = 0; i < this.channels.length; i += 1) {
				if (this.channels[i].id === channelId) {
					return this.channels[i];
				}
			}
			return null;
		},
		channelColor(channel) {
			return colorToRgb((channel && channel.color) || [255, 255, 255]);
		},
		isChannelAllowedById(channelId) {
			const channel = this.channelById(channelId);
			return !!channel && channel.visible !== false && channel.allowed !== false;
		},
		firstAllowedChannelId() {
			const available = this.visibleChannels;
			if (available.length === 0) {
				return '';
			}
			return available[0].id;
		},
		ensureChannelHistory(channelId) {
			if (!this.messagesByChannel[channelId]) {
				this.$set(this.messagesByChannel, channelId, []);
			}
		},
		trimChannelHistory(channelId) {
			const list = this.messagesByChannel[channelId];
			if (!Array.isArray(list)) {
				return;
			}
			const channel = this.channelById(channelId);
			const maxHistory = normalizeLimit(channel && channel.maxHistory, 250);
			if (maxHistory === -1) {
				return;
			}
			if (list.length > maxHistory) {
				list.splice(0, list.length - maxHistory);
			}
		},
		scrollActiveMessagesIfNeeded(message) {
			if (!this.autoScrollEnabled) {
				return;
			}
			if (!message || message.channel !== this.activeChannelId) {
				return;
			}
			if (this.isWhispersActive) {
				const messageConversation = message.metadata && message.metadata.conversationId
					? String(message.metadata.conversationId)
					: null;
				if (messageConversation && messageConversation !== this.activeWhisperConversationId) {
					return;
				}
			}
			this.scrollActiveMessages(false);
		},
		scrollActiveMessages(force) {
			if (!force && !this.autoScrollEnabled) {
				return;
			}
			const target = this.isWhispersActive ? this.$refs.whisperMessages : this.$refs.messages;
			if (target) {
				target.scrollTop = target.scrollHeight;
			}
		},
		removeThemes() {
			document.querySelectorAll('script[data-theme]').forEach((node) => {
				node.remove();
			});

			for (let i = document.styleSheets.length - 1; i >= 0; i -= 1) {
				const styleSheet = document.styleSheets[i];
				const node = styleSheet && styleSheet.ownerNode;
				if (node && node.getAttribute && node.getAttribute('data-theme')) {
					node.parentNode.removeChild(node);
				}
			}

			this.tplBackups.reverse();
			for (const [elem, oldData] of this.tplBackups) {
				elem.innerText = oldData;
			}
			this.tplBackups = [];

			this.msgTplBackups.reverse();
			for (const [id, oldData] of this.msgTplBackups) {
				this.templates[id] = oldData;
			}
			this.msgTplBackups = [];
		},
		setThemes(themes) {
			for (const [id, data] of Object.entries(themes)) {
				if (data.style) {
					const style = document.createElement('style');
					style.type = 'text/css';
					style.setAttribute('data-theme', id);
					style.appendChild(document.createTextNode(data.style));
					document.head.appendChild(style);
				}

				if (data.styleSheet) {
					const link = document.createElement('link');
					link.rel = 'stylesheet';
					link.type = 'text/css';
					link.href = data.baseUrl + data.styleSheet;
					link.setAttribute('data-theme', id);
					document.head.appendChild(link);
				}

				if (data.templates) {
					for (const [tplId, tpl] of Object.entries(data.templates)) {
						const elem = document.getElementById(tplId);
						if (elem) {
							this.tplBackups.push([elem, elem.innerText]);
							elem.innerText = tpl;
						}
					}
				}

				if (data.script) {
					const script = document.createElement('script');
					script.type = 'text/javascript';
					script.src = data.baseUrl + data.script;
					script.setAttribute('data-theme', id);
					document.head.appendChild(script);
				}

				if (data.msgTemplates) {
					for (const [tplId, tpl] of Object.entries(data.msgTemplates)) {
						this.msgTplBackups.push([tplId, this.templates[tplId]]);
						this.templates[tplId] = tpl;
					}
				}
			}
		},
		warn(msg) {
			this.ON_MESSAGE({
				message: {
					channel: this.activeChannelId || 'global',
					args: [msg],
					template: '^3<b>CHAT-WARN</b>: ^0{0}'
				}
			});
		},
		clearShowWindowTimer() {
			clearTimeout(this.showWindowTimer);
		},
		resetShowWindowTimer() {
			this.clearShowWindowTimer();
			const fadeTimeout = Math.max(0, Number(getRuntimeUiConfig().fadeTimeout) || 7000);
			this.showWindowTimer = setTimeout(() => {
				if (!this.showInput) {
					this.showWindow = false;
				}
			}, fadeTimeout);
		},
		bumpWindow() {
			this.showWindow = true;
			this.resetShowWindowTimer();
		},
		keyUp() {
			this.resize();
			this.syncTypingState(false);
		},
		keyDown(event) {
			if (event.which === 38 || event.which === 40) {
				event.preventDefault();
				this.moveOldMessageIndex(event.which === 38);
			} else if (event.which === 33 || event.which === 34) {
				const target = this.isWhispersActive ? this.$refs.whisperMessages : this.$refs.messages;
				if (target) {
					target.scrollTop += event.which === 33 ? -uiRuntimeValue('pageScrollStep', 100) : uiRuntimeValue('pageScrollStep', 100);
				}
			} else if (event.which === 9) {
				event.preventDefault();
				postJson('cycleChannel', {});
			}
		},
		moveOldMessageIndex(up) {
			if (up && this.oldMessages.length > this.oldMessagesIndex + 1) {
				this.oldMessagesIndex += 1;
				this.message = this.oldMessages[this.oldMessagesIndex];
			} else if (!up && this.oldMessagesIndex - 1 >= 0) {
				this.oldMessagesIndex -= 1;
				this.message = this.oldMessages[this.oldMessagesIndex];
			} else if (!up && this.oldMessagesIndex - 1 === -1) {
				this.oldMessagesIndex = -1;
				this.message = '';
			}
			this.syncTypingState(false);
		},
		resize() {
			const input = this.$refs.input;
			if (!input) {
				return;
			}
			input.style.height = 'auto';
			input.style.height = `${Math.max(input.scrollHeight + 2, 36)}px`;
		},
		send() {
			if (this.message !== '') {
				const original = this.message;
				let outgoing = original;
				if (this.whisperTabEnabled && this.isWhispersActive && original.charAt(0) !== '/' && this.activeWhisperConversationId) {
					const conversation = this.whisperConversations[this.activeWhisperConversationId];
					if (conversation && Number(conversation.peerId) > 0) {
						outgoing = `/w ${Number(conversation.peerId)} ${original}`;
					}
				}

				postJson('chatResult', { message: outgoing });
				this.oldMessages.unshift(original);
				this.oldMessagesIndex = -1;
				this.hideInput(false);
			} else {
				this.hideInput(true);
			}
		},
		hideInput(canceled = false) {
			if (canceled) {
				postJson('chatResult', { canceled: true });
			}
			this.message = '';
			this.showInput = false;
			clearTimeout(this.focusTimer);
			this.syncTypingState(true);
			this.resetShowWindowTimer();
		},
		syncTypingState(force) {
			const active = this.showInput && !this.shouldHide;
			if (!force && this.lastTypingState === active) {
				return;
			}
			this.lastTypingState = active;
			postJson('typingState', { active });
		},
		cycleDistanceButton() {
			return fetchJson('cycleDistance', {})
				.then((resp) => {
					if (resp && resp.state) {
						this.setDistanceState({ state: resp.state });
					}
					return resp;
				})
				.catch(() => null);
		},
		toggleTypingButton() {
			return fetchJson('toggleTypingDisplay', {})
				.then((resp) => {
					if (resp && typeof resp.active === 'boolean') {
						this.featureState.typing.active = resp.active;
						updateFeatureButtons(this.featureState);
					}
					return resp;
				})
				.catch(() => null);
		},
		toggleBubblesButton() {
			return fetchJson('toggleBubbleDisplay', {})
				.then((resp) => {
					if (resp && typeof resp.active === 'boolean') {
						this.featureState.bubbles.active = resp.active;
						updateFeatureButtons(this.featureState);
					}
					return resp;
				})
				.catch(() => null);
		},
		toggleWhisperSoundButton() {
			return fetchJson('toggleWhisperSound', {})
				.then((resp) => {
					if (resp && typeof resp.active === 'boolean') {
						this.featureState.whisperSound.active = resp.active;
					}
					const volume = Number(resp && resp.volume);
					if (Number.isFinite(volume)) {
						this.featureState.whisperSound.volume = volume;
						this.whisperNotificationVolume = Math.max(0, Math.min(1, volume));
					}
					updateFeatureButtons(this.featureState);
					return resp;
				})
				.catch(() => null);
		},
		toggleAutoScrollButton() {
			return fetchJson('toggleAutoScroll', {})
				.then((resp) => {
					if (resp && typeof resp.active === 'boolean') {
						this.featureState.autoScroll.active = resp.active;
						this.autoScrollEnabled = resp.active;
						if (this.autoScrollEnabled) {
							this.$nextTick(() => this.scrollActiveMessages(true));
						}
					}
					updateFeatureButtons(this.featureState);
					return resp;
				})
				.catch(() => null);
		},
		create3dMessage({ id, color, text, timeout, persistent, style, floatUp }) {
			const key = String(id);
			removeMessage3dNode(key);
			const bubbleMeta = getBubbleMetaFromId(key);

			const div = document.createElement('div');
			div.id = 'message3d-' + key;
			div.className = 'message3d';
			div.style.display = 'none';
			div.style.color = `rgb(${color[0]}, ${color[1]}, ${color[2]})`;

			const visualStyle = ensureString(style, '');
			const isTyping = visualStyle === 'typingBubble' || key.startsWith('typing-');
			const isBubble = visualStyle === 'bubble' || visualStyle === 'typingBubble' || key.startsWith('bubble-');

			if (isTyping) {
				div.classList.add('is-typing-bubble');
				div.innerHTML = '<span class="typing-dots"><span></span><span></span><span></span></span>';
			} else {
				div.innerText = text;
			}

			if (isBubble) {
				div.classList.add('is-bubble');
			}
			if (bubbleMeta && bubbleMeta.source) {
				div.dataset.bubbleSource = bubbleMeta.source;
			}
			if (bubbleMeta && bubbleMeta.isBubble) {
				div.dataset.bubbleSerial = String(bubbleMeta.serial);
			}

			if (floatUp === true && !isTyping) {
				div.classList.add('is-float-up');
			}

			if (!isBubble && (visualStyle === 'overhead' || key.startsWith('msg-'))) {
				div.classList.add('is-overhead');
			}

			const container = document.getElementById('message3d');
			if (container) {
				container.appendChild(div);
			}
			if (bubbleMeta && bubbleMeta.source) {
				refreshBubbleTailForSource(bubbleMeta.source);
			}

			if (!persistent) {
				const wait = Math.max(0, Number(timeout) || 0);
				message3dTimers[key] = setTimeout(() => {
					removeMessage3dNode(key);
				}, wait);
			}
		},
		update3dMessage({ id, onScreen, screenX, screenY }) {
			const div = document.getElementById('message3d-' + String(id));
			if (!div) {
				return;
			}

			if (onScreen) {
				div.style.display = 'block';
				div.style.top = screenY * 100 + 'vh';
				div.style.left = screenX * 100 + 'vw';
			} else {
				div.style.display = 'none';
			}
		},
		remove3dMessage({ id }) {
			removeMessage3dNode(id);
		}
	}
};

window.addEventListener('load', () => {
	if (window.__POODLECHAT_UI_LOADED) {
		return;
	}
	window.__POODLECHAT_UI_LOADED = true;

	setupEmojiUiBindings();

	fetch('https://' + resourceName() + '/onLoad')
		.then((resp) => (resp ? resp.text() : ''))
		.then((raw) => {
			if (!raw || raw === '') {
				return {};
			}
			try {
				return JSON.parse(raw);
			} catch (error) {
				return {};
			}
		})
		.then((payload) => {
			if (window.APP_INSTANCE && typeof window.APP_INSTANCE.applyInitialPayload === 'function') {
				window.APP_INSTANCE.applyInitialPayload(payload || {});
			} else {
				bootstrapEmojiDataset(payload || {});
			}
		})
		.catch(() => {
			if (window.APP_INSTANCE && typeof window.APP_INSTANCE.applyInitialPayload === 'function') {
				window.APP_INSTANCE.applyInitialPayload({});
			} else {
				bootstrapEmojiDataset({});
			}
		});

	document.querySelectorAll('.tab, .tool-btn').forEach((node) => {
		node.addEventListener('click', () => {
			const input = document.querySelector('textarea');
			if (input) {
				input.focus();
			}
		});
	});

	const emojiToggle = document.getElementById('emoji-toggle');
	const emojiWindow = document.getElementById('emoji-window');
	if (emojiToggle && emojiWindow) {
		emojiToggle.addEventListener('click', () => {
			const open = emojiWindow.style.display === 'flex';
			emojiWindow.style.display = open ? 'none' : 'flex';
			emojiToggle.className = open ? 'tab' : 'tab active-tab';
			const input = document.querySelector('textarea');
			if (input) {
				input.focus();
			}
		});
	}

	const distanceButton = document.getElementById('distance-widget');
	if (distanceButton) {
		distanceButton.addEventListener('click', () => {
			if (window.APP_INSTANCE) {
				window.APP_INSTANCE.cycleDistanceButton();
			}
		});
	}

	const typingButton = document.getElementById('typing-toggle');
	if (typingButton) {
		typingButton.addEventListener('click', () => {
			if (typingButton.classList.contains('disabled-toggle')) {
				return;
			}
			if (window.APP_INSTANCE) {
				window.APP_INSTANCE.toggleTypingButton();
			}
		});
	}

	const bubblesButton = document.getElementById('bubbles-toggle');
	if (bubblesButton) {
		bubblesButton.addEventListener('click', () => {
			if (bubblesButton.classList.contains('disabled-toggle')) {
				return;
			}
			if (window.APP_INSTANCE) {
				window.APP_INSTANCE.toggleBubblesButton();
			}
		});
	}

	const autoScrollButton = document.getElementById('autoscroll-toggle');
	if (autoScrollButton) {
		autoScrollButton.addEventListener('click', () => {
			if (autoScrollButton.classList.contains('disabled-toggle')) {
				return;
			}
			if (window.APP_INSTANCE) {
				window.APP_INSTANCE.toggleAutoScrollButton();
			}
		});
	}

	const whisperSoundButton = document.getElementById('whisper-sound-toggle');
	if (whisperSoundButton) {
		whisperSoundButton.addEventListener('click', () => {
			if (whisperSoundButton.classList.contains('disabled-toggle')) {
				return;
			}
			if (window.APP_INSTANCE) {
				window.APP_INSTANCE.toggleWhisperSoundButton();
			}
		});
	}

	document.querySelectorAll('.no-focus').forEach((node) => {
		node.addEventListener('focus', (event) => {
			event.preventDefault();
			if (event.relatedTarget) {
				event.relatedTarget.focus();
			} else {
				event.currentTarget.blur();
			}
		});
	});
});
