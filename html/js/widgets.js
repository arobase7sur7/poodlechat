function normalizeDistanceState(state) {
	const payload = state || {};
	const ranges = ensureArray(payload.ranges)
		.map((entry) => Number(entry))
		.filter((entry) => Number.isFinite(entry) && entry > 0)
		.sort((a, b) => a - b);
	return {
		enabled: payload.enabled === true,
		label: ensureString(payload.label, ''),
		color: ensureString(payload.color, '#95a5a6'),
		percent: Number.isFinite(Number(payload.percent)) ? Number(payload.percent) : 0,
		value: Number.isFinite(Number(payload.value)) ? Number(payload.value) : 0,
		modeIndex: Number.isFinite(Number(payload.modeIndex)) ? Number(payload.modeIndex) : 0,
		modeCount: Number.isFinite(Number(payload.modeCount)) ? Number(payload.modeCount) : 0,
		ranges
	};
}

function percentFromDistance(payload) {
	const ranges = payload.ranges || [];
	if (ranges.length === 0 || !Number.isFinite(payload.value)) {
		return null;
	}
	if (ranges.length === 1) {
		return 100;
	}

	const minRange = ranges[0];
	const maxRange = ranges[ranges.length - 1];
	if (!Number.isFinite(minRange) || !Number.isFinite(maxRange) || maxRange <= minRange) {
		return null;
	}

	return ((payload.value - minRange) / (maxRange - minRange)) * 100;
}

function updateDistanceWidget(state) {
	const widget = document.getElementById('distance-widget');
	const label = document.getElementById('distance-label');
	const fill = document.getElementById('distance-fill');

	if (!widget || !label || !fill) {
		return;
	}

	const payload = normalizeDistanceState(state);
	if (!payload.enabled) {
		widget.style.display = 'none';
		return;
	}

	widget.style.display = 'inline-flex';
	label.textContent = payload.label || `${payload.value.toFixed(1)} m`;
	label.style.color = payload.color;
	let percent = Number(payload.percent);
	if (!Number.isFinite(percent)) {
		const fallbackPercent = percentFromDistance(payload);
		percent = Number.isFinite(fallbackPercent) ? fallbackPercent : 0;
	} else {
		const fallbackPercent = percentFromDistance(payload);
		if (Number.isFinite(fallbackPercent)) {
			percent = Math.max(percent, fallbackPercent);
		}
	}

	let safePercent = Math.max(0, Math.min(100, percent));
	if (safePercent >= 99) {
		safePercent = 100;
	}
	fill.setAttribute('width', `${safePercent}`);
	fill.style.width = `${safePercent}%`;
	fill.style.fill = payload.color;
	widget.dataset.modeIndex = String(payload.modeIndex || 0);
	widget.dataset.modeCount = String(payload.modeCount || 0);
}

function normalizeFeatureState(state) {
	const payload = state || {};
	return {
		typing: payload.typing || { enabled: false, allowToggle: false, active: false },
		bubbles: payload.bubbles || { enabled: false, allowToggle: false, active: false },
		autoScroll: payload.autoScroll || { enabled: true, allowToggle: true, active: true },
		whisperSound: payload.whisperSound || { enabled: true, allowToggle: true, active: true, volume: 0.65 },
		distance: payload.distance || { enabled: false }
	};
}

function applyToggleButtonState(id, feature) {
	const button = document.getElementById(id);
	if (!button) {
		return;
	}

	if (!feature.enabled) {
		button.style.display = 'none';
		return;
	}

	button.style.display = 'inline-flex';
	button.className = `tool-btn icon-btn no-focus${feature.active ? ' active-toggle' : ''}${feature.allowToggle ? '' : ' disabled-toggle'}`;
}

function updateFeatureButtons(state) {
	const payload = normalizeFeatureState(state);
	applyToggleButtonState('typing-toggle', payload.typing);
	applyToggleButtonState('bubbles-toggle', payload.bubbles);
	applyToggleButtonState('autoscroll-toggle', payload.autoScroll);
	applyToggleButtonState('whisper-sound-toggle', payload.whisperSound);

	const distanceWidget = document.getElementById('distance-widget');
	if (distanceWidget && !payload.distance.enabled) {
		distanceWidget.style.display = 'none';
	}
}


