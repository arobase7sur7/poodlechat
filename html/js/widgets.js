function normalizeDistanceState(state) {
	const payload = state || {};
	return {
		enabled: payload.enabled === true,
		label: ensureString(payload.label, ''),
		color: ensureString(payload.color, '#95a5a6'),
		percent: Number.isFinite(Number(payload.percent)) ? Number(payload.percent) : 0,
		value: Number.isFinite(Number(payload.value)) ? Number(payload.value) : 0,
		modeIndex: Number.isFinite(Number(payload.modeIndex)) ? Number(payload.modeIndex) : 0,
		modeCount: Number.isFinite(Number(payload.modeCount)) ? Number(payload.modeCount) : 0
	};
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
	const safePercent = Math.max(0, Math.min(100, payload.percent));
	fill.setAttribute('width', `${safePercent}`);
	fill.style.fill = payload.color;
	widget.dataset.modeIndex = String(payload.modeIndex || 0);
	widget.dataset.modeCount = String(payload.modeCount || 0);
}

function normalizeFeatureState(state) {
	const payload = state || {};
	return {
		typing: payload.typing || { enabled: false, allowToggle: false, active: false },
		bubbles: payload.bubbles || { enabled: false, allowToggle: false, active: false },
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

	const distanceWidget = document.getElementById('distance-widget');
	if (distanceWidget && !payload.distance.enabled) {
		distanceWidget.style.display = 'none';
	}
}


