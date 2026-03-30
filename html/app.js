function uiRuntimeValue(key, fallback) {
	const runtime = getRuntimeUiConfig().runtime || {};
	const value = Number(runtime[key]);
	if (Number.isFinite(value)) {
		return value;
	}
	return fallback;
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
			messages: [],
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
				this[item.type](item);
			}
		};
		window.addEventListener('message', this.listener);
	},
	watch: {
		messages() {
			if (this.showWindowTimer) {
				clearTimeout(this.showWindowTimer);
			}
			this.showWindow = true;
			this.resetShowWindowTimer();

			const messagesObj = this.$refs.messages;
			this.$nextTick(() => {
				if (messagesObj) {
					messagesObj.scrollTop = messagesObj.scrollHeight;
				}
			});
		},
		message() {
			this.syncTypingState(false);
		}
	},
	computed: {
		suggestions() {
			return this.backingSuggestions.filter((el) => this.removedSuggestions.indexOf(el.name) <= -1);
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
			this.showWindow = true;
			if (this.showWindowTimer) {
				clearTimeout(this.showWindowTimer);
			}
			clearTimeout(this.focusTimer);
			this.focusTimer = setTimeout(() => {
				if (this.$refs.input) {
					this.$refs.input.focus();
				}
			}, uiRuntimeValue('inputFocusDelayMs', 100));
			this.syncTypingState(true);
		},
		ON_MESSAGE({ message }) {
			this.messages.push(message);
		},
		ON_CLEAR() {
			this.messages = [];
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
			updateFeatureButtons(this.featureState);
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
			this.messages.push({
				args: [msg],
				template: '^3<b>CHAT-WARN</b>: ^0{0}'
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
		keyUp() {
			this.resize();
			this.syncTypingState(false);
		},
		keyDown(event) {
			if (event.which === 38 || event.which === 40) {
				event.preventDefault();
				this.moveOldMessageIndex(event.which === 38);
			} else if (event.which === 33) {
				const buf = document.getElementsByClassName('chat-messages')[0];
				buf.scrollTop -= uiRuntimeValue('pageScrollStep', 100);
			} else if (event.which === 34) {
				const buf = document.getElementsByClassName('chat-messages')[0];
				buf.scrollTop += uiRuntimeValue('pageScrollStep', 100);
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
			input.style.height = '5px';
			input.style.height = `${input.scrollHeight + 2}px`;
		},
		send() {
			if (this.message !== '') {
				postJson('chatResult', { message: this.message });
				this.oldMessages.unshift(this.message);
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
		setChannel({ channelId }) {
			document.querySelectorAll('.channel').forEach((node) => {
				node.className = node.id === channelId ? 'channel tab active-tab' : 'channel tab';
			});
		},
		setPermissions({ permissions }) {
			let perms = {};
			try {
				perms = JSON.parse(permissions) || {};
			} catch (error) {
				perms = {};
			}

			const staffTab = document.getElementById('channel-staff');
			if (!staffTab) {
				return;
			}

			staffTab.style.display = perms.canAccessStaffChannel ? 'inline-flex' : 'none';
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
	setupEmojiUiBindings();

	fetch('https://' + resourceName() + '/onLoad')
		.then((resp) => resp.json())
		.then((payload) => {
			applyRuntimeUiConfig(payload.ui || {});
			if (window.APP_INSTANCE && typeof window.APP_INSTANCE.applyRuntimeUiConfig === 'function') {
				window.APP_INSTANCE.applyRuntimeUiConfig(payload.ui || {});
			}

			document.getElementById('channel-local').style.color = colorToRgb(payload.localColor);
			document.getElementById('channel-global').style.color = colorToRgb(payload.globalColor);
			document.getElementById('channel-staff').style.color = colorToRgb(payload.staffColor);

			if (payload.features && window.APP_INSTANCE) {
				window.APP_INSTANCE.setFeatureState({ state: payload.features });
			} else {
				updateFeatureButtons(payload.features || {});
			}

			if (payload.distance && window.APP_INSTANCE) {
				window.APP_INSTANCE.setDistanceState({ state: payload.distance });
			} else {
				updateDistanceWidget(payload.distance || {});
			}

			bootstrapEmojiDataset(payload || {});
		})
		.catch(() => {
			bootstrapEmojiDataset({});
		});

	document.querySelectorAll('.channel').forEach((node) => {
		node.addEventListener('click', function onChannelClick() {
			fetchJson('setChannel', { channelId: this.id });
		});
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


