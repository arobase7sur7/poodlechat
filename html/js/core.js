function resourceName() {
	return GetParentResourceName();
}

function postJson(route, payload) {
	post('https://' + resourceName() + '/' + route, JSON.stringify(payload || {}));
}

function fetchJson(route, payload) {
	return fetch('https://' + resourceName() + '/' + route, {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json'
		},
		body: JSON.stringify(payload || {})
	}).then((resp) => resp.json());
}

function ensureArray(value) {
	return Array.isArray(value) ? value : [];
}

function ensureString(value, fallback) {
	if (typeof value === 'string') {
		return value;
	}
	return fallback || '';
}

function colorToRgb(color) {
	const safe = Array.isArray(color) ? color : [255, 255, 255];
	return `rgb(${safe[0] || 255},${safe[1] || 255},${safe[2] || 255})`;
}

const DEFAULT_UI_CONFIG = {
	defaultTemplateId: 'default',
	defaultAltTemplateId: 'defaultAlt',
	templates: {
		default: '<b>{0}</b>: {1}',
		defaultAlt: '{0}',
		print: '<pre>{0}</pre>',
		'example:important': '<h1>^2{0}</h1>'
	},
	fadeTimeout: 7000,
	suggestionLimit: 5,
	style: {
		width: '38%',
		height: '22%'
	},
	runtime: {
		emojiRenderBatchSize: 260,
		emojiSearchDebounceMs: 80,
		inputFocusDelayMs: 100,
		pageScrollStep: 100
	}
};

const runtimeUiConfig = {
	defaultTemplateId: DEFAULT_UI_CONFIG.defaultTemplateId,
	defaultAltTemplateId: DEFAULT_UI_CONFIG.defaultAltTemplateId,
	templates: { ...DEFAULT_UI_CONFIG.templates },
	fadeTimeout: DEFAULT_UI_CONFIG.fadeTimeout,
	suggestionLimit: DEFAULT_UI_CONFIG.suggestionLimit,
	style: { ...DEFAULT_UI_CONFIG.style },
	runtime: { ...DEFAULT_UI_CONFIG.runtime }
};
window.PoodleChatUiConfig = runtimeUiConfig;

function getRuntimeUiConfig() {
	return runtimeUiConfig;
}

function applyRuntimeUiConfig(rawConfig) {
	const payload = rawConfig && typeof rawConfig === 'object' ? rawConfig : {};
	runtimeUiConfig.defaultTemplateId = ensureString(payload.defaultTemplateId, DEFAULT_UI_CONFIG.defaultTemplateId);
	runtimeUiConfig.defaultAltTemplateId = ensureString(payload.defaultAltTemplateId, DEFAULT_UI_CONFIG.defaultAltTemplateId);
	runtimeUiConfig.fadeTimeout = Number.isFinite(Number(payload.fadeTimeout)) ? Number(payload.fadeTimeout) : DEFAULT_UI_CONFIG.fadeTimeout;
	runtimeUiConfig.suggestionLimit = Number.isFinite(Number(payload.suggestionLimit)) ? Number(payload.suggestionLimit) : DEFAULT_UI_CONFIG.suggestionLimit;
	runtimeUiConfig.templates = {
		...DEFAULT_UI_CONFIG.templates,
		...(payload.templates && typeof payload.templates === 'object' ? payload.templates : {})
	};
	runtimeUiConfig.style = {
		...DEFAULT_UI_CONFIG.style,
		...(payload.style && typeof payload.style === 'object' ? payload.style : {})
	};
	runtimeUiConfig.runtime = {
		...DEFAULT_UI_CONFIG.runtime,
		...(payload.runtime && typeof payload.runtime === 'object' ? payload.runtime : {})
	};
}

const message3dTimers = {};

function clearMessage3dTimer(id) {
	const key = String(id);
	if (message3dTimers[key]) {
		clearTimeout(message3dTimers[key]);
		delete message3dTimers[key];
	}
}

function removeMessage3dNode(id) {
	const key = String(id);
	clearMessage3dTimer(key);
	const node = document.getElementById('message3d-' + key);
	const sourceKey = node && node.dataset ? node.dataset.bubbleSource : '';
	if (node) {
		node.remove();
	}
	if (sourceKey) {
		refreshBubbleTailForSource(sourceKey);
	}
}

function getBubbleMetaFromId(id) {
	const key = String(id || '');
	const bubbleMatch = key.match(/^bubble-(.+)-(\d+)$/);
	if (bubbleMatch) {
		return {
			source: bubbleMatch[1],
			serial: Number(bubbleMatch[2]) || 0,
			isBubble: true,
			isTyping: false
		};
	}
	const singleBubbleMatch = key.match(/^bubble-(.+)$/);
	if (singleBubbleMatch) {
		return {
			source: singleBubbleMatch[1],
			serial: 0,
			isBubble: true,
			isTyping: false
		};
	}

	const typingMatch = key.match(/^typing-(.+)$/);
	if (typingMatch) {
		return {
			source: typingMatch[1],
			serial: 0,
			isBubble: false,
			isTyping: true
		};
	}

	return null;
}

function refreshBubbleTailForSource(sourceKey) {
	if (!sourceKey) {
		return;
	}

	const nodes = Array.from(document.querySelectorAll('.message3d.is-bubble'));
	let newestNode = null;
	let newestSerial = -1;

	for (let i = 0; i < nodes.length; i += 1) {
		const node = nodes[i];
		if (!node || !node.dataset || node.dataset.bubbleSource !== sourceKey) {
			continue;
		}

		if (node.classList.contains('is-typing-bubble')) {
			continue;
		}

		node.classList.remove('has-tail');
		const serial = Number(node.dataset.bubbleSerial || 0);
		if (serial >= newestSerial) {
			newestSerial = serial;
			newestNode = node;
		}
	}

	if (newestNode) {
		newestNode.classList.add('has-tail');
	}
}


