const emojiState = {
	categories: [],
	entriesByCategory: {},
	indexByEmoji: {},
	recentEntries: [],
	topEntries: [],
	activeTab: 'recent',
	search: '',
	renderToken: 0,
	filterCache: {},
	searchTimer: null,
	tabsKey: '',
	bound: false
};

const emojiRenderState = {
	entries: [],
	rendered: 0,
	batchSize: Number(getRuntimeUiConfig().runtime.emojiRenderBatchSize) || 260
};

function clearEmojiFilterCache() {
	emojiState.filterCache = {};
}

function escapeAttribute(value) {
	return ensureString(value, '')
		.replace(/&/g, '&amp;')
		.replace(/"/g, '&quot;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;');
}

function getEmojiTabIcon(id, label) {
	const key = String(id || '').toLowerCase();
	if (key === 'recent') {
		return '\u{1F558}';
	}
	if (key === 'top') {
		return '\u{1F525}';
	}
	if (key.includes('smile')) {
		return '\u{1F604}';
	}
	if (key.includes('people') || key.includes('body')) {
		return '\u{1F9CD}';
	}
	if (key.includes('animal') || key.includes('nature')) {
		return '\u{1F43E}';
	}
	if (key.includes('food') || key.includes('drink')) {
		return '\u{1F354}';
	}
	if (key.includes('travel') || key.includes('place')) {
		return '\u{1F697}';
	}
	if (key.includes('activity')) {
		return '\u{26BD}';
	}
	if (key.includes('object')) {
		return '\u{1F4A1}';
	}
	if (key.includes('symbol')) {
		return '\u{1F523}';
	}
	if (key.includes('flag')) {
		return '\u{1F3F3}\u{FE0F}';
	}
	if (key.includes('all')) {
		return '\u{1F4DA}';
	}
	const firstChar = ensureString(label, '').trim().charAt(0);
	return firstChar || '•';
}

function normalizeAliases(aliases) {
	const list = ensureArray(aliases)
		.filter((alias) => typeof alias === 'string' && alias.length > 0);
	return list;
}

function categoryIdFromLabel(label, fallback) {
	const base = ensureString(label, '')
		.toLowerCase()
		.replace(/&/g, ' and ')
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-+|-+$/g, '')
		.replace(/-{2,}/g, '-');
	return base || fallback;
}

function categoryLabelFromId(value, fallback) {
	const source = ensureString(value, fallback || 'Category');
	return source
		.split(/\s+/)
		.join(' ')
		.trim()
		.split('-')
		.join(' ')
		.replace(/\b\w/g, (char) => char.toUpperCase());
}

function buildAliasFromName(name) {
	const normalized = ensureString(name, '')
		.toLowerCase()
		.replace(/&/g, ' and ')
		.replace(/[’']/g, '')
		.replace(/[^a-z0-9]+/g, '_')
		.replace(/^_+|_+$/g, '')
		.replace(/_{2,}/g, '_');
	return normalized ? `:${normalized}:` : '';
}

function decodeEmojiFromUnicodeList(unicodeList) {
	const list = ensureArray(unicodeList);
	if (list.length === 0) {
		return '';
	}

	const codepoints = [];
	for (let i = 0; i < list.length; i += 1) {
		const item = ensureString(list[i], '').trim();
		if (!item) {
			continue;
		}

		const normalized = item.replace(/^U\+/i, '');
		if (!/^[0-9a-fA-F]+$/.test(normalized)) {
			continue;
		}

		const value = Number.parseInt(normalized, 16);
		if (Number.isFinite(value) && value >= 0 && value <= 0x10ffff) {
			codepoints.push(value);
		}
	}

	if (codepoints.length === 0) {
		return '';
	}

	try {
		return String.fromCodePoint(...codepoints);
	} catch (error) {
		return '';
	}
}

function decodeEmojiFromHtmlCodeList(htmlCodeList) {
	const list = ensureArray(htmlCodeList);
	if (list.length === 0) {
		return '';
	}

	const codepoints = [];
	for (let i = 0; i < list.length; i += 1) {
		const source = ensureString(list[i], '');
		const matches = source.match(/&#x?[0-9a-fA-F]+;/g) || [];
		for (let k = 0; k < matches.length; k += 1) {
			const token = matches[k];
			const body = token.slice(2, -1);
			const isHex = body.charAt(0).toLowerCase() === 'x';
			const parsed = Number.parseInt(isHex ? body.slice(1) : body, isHex ? 16 : 10);
			if (Number.isFinite(parsed) && parsed >= 0 && parsed <= 0x10ffff) {
				codepoints.push(parsed);
			}
		}
	}

	if (codepoints.length === 0) {
		return '';
	}

	try {
		return String.fromCodePoint(...codepoints);
	} catch (error) {
		return '';
	}
}

function normalizeEmojiEntry(raw, categoryId, categoryLabel) {
	if (!raw || typeof raw !== 'object') {
		return null;
	}

	let emoji = ensureString(raw.emoji || raw.value, '');
	if (!emoji) {
		emoji = decodeEmojiFromUnicodeList(raw.unicode) || decodeEmojiFromHtmlCodeList(raw.htmlCode);
	}
	if (!emoji) {
		return null;
	}

	const aliases = normalizeAliases(raw.aliases || raw[0]);
	if (aliases.length === 0) {
		const generatedAlias = buildAliasFromName(raw.name);
		if (generatedAlias) {
			aliases.push(generatedAlias);
		}
	}

	let search = ensureString(raw.search, '').toLowerCase();
	if (!search) {
		search = [
			ensureString(raw.name, ''),
			ensureString(raw.group, ''),
			ensureString(categoryLabel, '')
		]
			.join(' ')
			.toLowerCase()
			.trim();
	}

	const aliasesLower = aliases.map((alias) => alias.toLowerCase());
	const searchBlob = `${search} ${aliasesLower.join(' ')}`.trim();

	return {
		emoji,
		aliases,
		aliasesLower,
		searchBlob,
		categoryId,
		categoryLabel
	};
}

function buildCategoriesFromLegacy(legacyList) {
	const entries = [];
	const source = ensureArray(legacyList);

	for (let i = 0; i < source.length; i += 1) {
		const item = source[i];
		if (!Array.isArray(item) || item.length < 2) {
			continue;
		}
		const aliases = ensureArray(item[0]);
		const emoji = ensureString(item[1], '');
		if (!emoji) {
			continue;
		}
		entries.push({
			emoji,
			aliases,
			search: aliases.join(' ').replace(/:/g, ' ')
		});
	}

	return [
		{
			id: 'all',
			label: 'All',
			emojis: entries
		}
	];
}

function buildCategoriesFromEmojibase(rawList) {
	const source = ensureArray(rawList);
	const byId = {};
	const order = [];

	for (let i = 0; i < source.length; i += 1) {
		const entry = source[i];
		if (!entry || typeof entry !== 'object') {
			continue;
		}

		const label = ensureString(entry.category, 'Misc');
		const id = categoryIdFromLabel(label, `category_${i}`);

		if (!byId[id]) {
			byId[id] = {
				id,
				label: categoryLabelFromId(label, id),
				emojis: []
			};
			order.push(id);
		}

		byId[id].emojis.push(entry);
	}

	const categories = [];
	for (let i = 0; i < order.length; i += 1) {
		categories.push(byId[order[i]]);
	}

	return categories;
}

function loadLocalEmojibaseCategories() {
	const urls = [
		'emojibase.json',
		'./emojibase.json'
	];

	function parsePayload(payload) {
		let categories = [];
		if (Array.isArray(payload)) {
			categories = buildCategoriesFromEmojibase(payload);
		} else if (payload && typeof payload === 'object' && Array.isArray(payload.categories)) {
			categories = payload.categories;
		}

		if (categories.length > 0) {
			setEmojiCategories(categories);
			renderEmojiTabs();
			refreshEmojiList();
			return true;
		}

		return false;
	}

	function tryUrl(index) {
		if (index >= urls.length) {
			return Promise.resolve(false);
		}

		return fetch(urls[index])
			.then((resp) => {
				if (!resp.ok) {
					throw new Error('failed');
				}
				return resp.json();
			})
			.then((payload) => {
				if (parsePayload(payload)) {
					return true;
				}
				return tryUrl(index + 1);
			})
			.catch(() => tryUrl(index + 1));
	}

	return tryUrl(0);
}

function setEmojiCategories(rawCategories) {
	const categories = ensureArray(rawCategories);
	const entriesByCategory = {};
	const indexByEmoji = {};
	const normalizedCategories = [];

	for (let i = 0; i < categories.length; i += 1) {
		const category = categories[i] || {};
		const id = ensureString(category.id, `category_${i}`);
		const label = ensureString(category.label, id);
		const rawEntries = ensureArray(category.emojis);
		const entries = [];

		for (let j = 0; j < rawEntries.length; j += 1) {
			const entry = normalizeEmojiEntry(rawEntries[j], id, label);
			if (!entry) {
				continue;
			}
			entries.push(entry);
			if (!indexByEmoji[entry.emoji]) {
				indexByEmoji[entry.emoji] = entry;
			}
		}

		normalizedCategories.push({ id, label });
		entriesByCategory[id] = entries;
	}

	emojiState.categories = normalizedCategories;
	emojiState.entriesByCategory = entriesByCategory;
	emojiState.indexByEmoji = indexByEmoji;
	clearEmojiFilterCache();
	emojiState.tabsKey = '';

	if (!emojiState.categories.find((category) => category.id === emojiState.activeTab) && emojiState.activeTab !== 'recent' && emojiState.activeTab !== 'top') {
		emojiState.activeTab = emojiState.categories.length > 0 ? emojiState.categories[0].id : 'recent';
	}
}

function mapUsageEntries(rawEntries) {
	const mapped = [];
	const source = ensureArray(rawEntries);

	for (let i = 0; i < source.length; i += 1) {
		const raw = source[i];
		if (!raw || typeof raw !== 'object') {
			continue;
		}

		const emoji = ensureString(raw.emoji, '');
		if (!emoji) {
			continue;
		}

		const indexed = emojiState.indexByEmoji[emoji];
		if (indexed) {
			mapped.push(indexed);
		} else {
			const aliases = normalizeAliases(raw.aliases);
			const aliasesLower = aliases.map((alias) => alias.toLowerCase());
			mapped.push({
				emoji,
				aliases,
				aliasesLower,
				searchBlob: aliasesLower.join(' '),
				categoryId: 'usage',
				categoryLabel: 'Usage'
			});
		}
	}

	return mapped;
}

function applyEmojiPanelData(panelData) {
	const payload = panelData || {};
	emojiState.recentEntries = mapUsageEntries(payload.recent);
	emojiState.topEntries = mapUsageEntries(payload.top);
	clearEmojiFilterCache();
}

function getEmojiEntriesForActiveTab() {
	if (emojiState.activeTab === 'recent') {
		return emojiState.recentEntries;
	}

	if (emojiState.activeTab === 'top') {
		return emojiState.topEntries;
	}

	return emojiState.entriesByCategory[emojiState.activeTab] || [];
}

function buildEmojiChunkHtml(entries, start, end) {
	let html = '';

	for (let i = start; i < end; i += 1) {
		const entry = entries[i];
		html += `<button type="button" class="emoji" data-emoji="${escapeAttribute(entry.emoji)}" data-placeholder="${escapeAttribute(entry.aliases.join(', '))}">${entry.emoji}</button>`;
	}

	return html;
}

function appendEmojiChunk(token) {
	if (token !== emojiState.renderToken) {
		return;
	}

	const emojiList = document.getElementById('emoji-list');
	if (!emojiList) {
		return;
	}

	const entries = emojiRenderState.entries;
	const start = emojiRenderState.rendered;
	const end = Math.min(start + emojiRenderState.batchSize, entries.length);

	if (end <= start) {
		return;
	}

	emojiList.insertAdjacentHTML('beforeend', buildEmojiChunkHtml(entries, start, end));
	emojiRenderState.rendered = end;
}

function maybeRenderMoreEmoji() {
	const emojiList = document.getElementById('emoji-list');
	if (!emojiList || emojiRenderState.rendered >= emojiRenderState.entries.length) {
		return;
	}

	if (emojiList.scrollTop + emojiList.clientHeight >= emojiList.scrollHeight - 120) {
		appendEmojiChunk(emojiState.renderToken);
	}
}

function renderEmojiList(entries) {
	const emojiList = document.getElementById('emoji-list');
	if (!emojiList) {
		return;
	}

	emojiState.renderToken += 1;
	const token = emojiState.renderToken;
	emojiList.innerHTML = '';
	emojiList.scrollTop = 0;

	emojiRenderState.entries = entries;
	emojiRenderState.rendered = 0;
	emojiRenderState.batchSize = Number(getRuntimeUiConfig().runtime.emojiRenderBatchSize) || 260;
	appendEmojiChunk(token);

	requestAnimationFrame(() => {
		maybeRenderMoreEmoji();
	});
}

function renderEmojiTabs() {
	const tabs = document.getElementById('emoji-tabs');
	if (!tabs) {
		return;
	}

	const tabList = [
		{ id: 'recent', label: 'Recent' },
		{ id: 'top', label: 'Top' }
	].concat(emojiState.categories);

	const key = tabList
		.map((tab) => `${tab.id}:${emojiState.activeTab === tab.id ? 1 : 0}`)
		.join('|');

	if (emojiState.tabsKey === key) {
		return;
	}

	emojiState.tabsKey = key;
	tabs.innerHTML = '';

	for (let i = 0; i < tabList.length; i += 1) {
		const tab = tabList[i];
		const node = document.createElement('button');
		node.type = 'button';
		node.className = 'emoji-tab' + (emojiState.activeTab === tab.id ? ' active-emoji-tab' : '');
		node.dataset.tab = tab.id;
		node.title = tab.label;
		node.textContent = getEmojiTabIcon(tab.id, tab.label);
		tabs.appendChild(node);
	}
}

function getFilteredEmojiEntries() {
	const query = emojiState.search.trim().toLowerCase();
	const cacheKey = `${emojiState.activeTab}|${query}`;
	const cached = emojiState.filterCache[cacheKey];
	if (cached) {
		return cached;
	}

	const entries = getEmojiEntriesForActiveTab();
	if (!query) {
		emojiState.filterCache[cacheKey] = entries;
		return entries;
	}

	const filtered = [];
	for (let i = 0; i < entries.length; i += 1) {
		const entry = entries[i];
		if (entry.searchBlob.includes(query)) {
			filtered.push(entry);
		}
	}

	emojiState.filterCache[cacheKey] = filtered;
	return filtered;
}

function refreshEmojiList() {
	renderEmojiList(getFilteredEmojiEntries());
}

function setActiveEmojiTab(tabId) {
	emojiState.activeTab = tabId;
	renderEmojiTabs();
	refreshEmojiList();
}

function appendEmojiToInput(emoji) {
	const input = document.querySelector('textarea');
	if (!input) {
		return;
	}

	input.value += emoji;
	input.dispatchEvent(new Event('input'));
	if (window.APP_INSTANCE && typeof window.APP_INSTANCE.syncTypingState === 'function') {
		window.APP_INSTANCE.syncTypingState(false);
	}
	input.focus();
}

function requestEmojiPanelData() {
	return fetchJson('getEmojiPanelData', {})
		.then((panelData) => {
			const hasCategories = panelData && panelData.categories && ensureArray(panelData.categories).length > 0;
			if (hasCategories && emojiState.categories.length === 0) {
				setEmojiCategories(panelData.categories);
			}

			const ensureCategoriesPromise = (!hasCategories && emojiState.categories.length === 0)
				? loadLocalEmojibaseCategories()
				: Promise.resolve(false);

			return ensureCategoriesPromise.then(() => {
				applyEmojiPanelData(panelData || {});
				renderEmojiTabs();
				refreshEmojiList();
				return panelData;
			});
		})
		.catch(() => null);
}

function handleEmojiUse(emoji) {
	return fetchJson('useEmoji', { emoji })
		.then((resp) => {
			if (resp && resp.panel) {
				applyEmojiPanelData(resp.panel);
				if (resp.panel.categories && ensureArray(resp.panel.categories).length > 0 && emojiState.categories.length === 0) {
					setEmojiCategories(resp.panel.categories);
				}
				renderEmojiTabs();
				refreshEmojiList();
				return resp;
			}
			return requestEmojiPanelData();
		})
		.catch(() => null);
}

function setupEmojiUiBindings() {
	if (emojiState.bound) {
		return;
	}

	emojiState.bound = true;

	const tabs = document.getElementById('emoji-tabs');
	const list = document.getElementById('emoji-list');
	const search = document.getElementById('emoji-search');

	if (tabs) {
		tabs.addEventListener('click', (event) => {
			const target = event.target.closest('.emoji-tab');
			if (!target) {
				return;
			}
			setActiveEmojiTab(target.dataset.tab || 'recent');
			const input = document.querySelector('textarea');
			if (input) {
				input.focus();
			}
		});
	}

	if (list) {
		list.addEventListener('scroll', () => {
			maybeRenderMoreEmoji();
		});

		list.addEventListener('click', (event) => {
			const target = event.target.closest('.emoji');
			if (!target) {
				return;
			}

			const emoji = target.dataset.emoji;
			if (!emoji) {
				return;
			}

			appendEmojiToInput(emoji);
			handleEmojiUse(emoji);
		});

		list.addEventListener('mouseover', (event) => {
			const target = event.target.closest('.emoji');
			if (!target || !search) {
				return;
			}
			search.placeholder = target.dataset.placeholder || 'Search...';
		});

		list.addEventListener('mouseout', () => {
			if (search) {
				search.placeholder = 'Search...';
			}
		});
	}

	if (search) {
		search.addEventListener('input', () => {
			if (emojiState.searchTimer) {
				clearTimeout(emojiState.searchTimer);
			}
			const debounceMs = Number(getRuntimeUiConfig().runtime.emojiSearchDebounceMs) || 80;
			emojiState.searchTimer = setTimeout(() => {
				emojiState.search = search.value.toLowerCase();
				refreshEmojiList();
			}, debounceMs);
		});
	}
}

function bootstrapEmojiDataset(onLoadPayload) {
	const payload = onLoadPayload || {};
	const fallbackLegacy = ensureArray(payload.emoji);
	const fallbackPanel = payload.emojiPanel || {};
	const hasPanelCategories = fallbackPanel.categories && ensureArray(fallbackPanel.categories).length > 0;

	if (hasPanelCategories) {
		setEmojiCategories(fallbackPanel.categories);
	} else if (fallbackLegacy.length > 0) {
		setEmojiCategories(buildCategoriesFromLegacy(fallbackLegacy));
	}

	applyEmojiPanelData(fallbackPanel);
	renderEmojiTabs();
	refreshEmojiList();

	const ensureCategoriesPromise = (!hasPanelCategories && fallbackLegacy.length === 0)
		? loadLocalEmojibaseCategories()
		: Promise.resolve(false);

	if (!fallbackPanel.recent && !fallbackPanel.top) {
		return ensureCategoriesPromise.then(() => requestEmojiPanelData());
	}

	return ensureCategoriesPromise;
}


