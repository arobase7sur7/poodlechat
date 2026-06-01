function getMessageUiConfig() {
	const config = window.PoodleChatUiConfig || {};
	return {
		defaultTemplateId: typeof config.defaultTemplateId === 'string' ? config.defaultTemplateId : 'default',
		defaultAltTemplateId: typeof config.defaultAltTemplateId === 'string' ? config.defaultAltTemplateId : 'defaultAlt',
		showRestoredIndicator: config.messages && config.messages.showRestoredIndicator === true
	};
}

function escapeRichTextHtml(unsafe) {
	return String(unsafe)
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&#039;');
}

function colorizeEscapedRichText(str) {
	let raw = String(str || '');

	raw = raw.replace(/\^#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})/g, (match, hex) => {
		const expanded = hex.length === 3
			? hex.split('').map((char) => char + char).join('')
			: hex;
		return `</span><span style="color:#${expanded}">`;
	});

	let output = `<span>${raw.replace(/\^([0-9])/g, (match, color) => `</span><span class="color-${color}">`)}</span>`;

	const styleDict = {
		'*': 'font-weight: 700;',
		_: 'text-decoration: underline;',
		'~': 'text-decoration: line-through;',
		'=': 'text-decoration: underline line-through;',
		r: 'text-decoration: none;font-weight: 400;'
	};

	const styleRegex = /\^(\_|\*|\=|\~|\/|r)(.*?)(?=$|\^r|<\/em>)/;
	while (styleRegex.test(output)) {
		output = output.replace(styleRegex, (match, style, inner) => `<em style="${styleDict[style]}">${inner}</em>`);
	}

	let brCount = 0;
	output = output.replace(/\\n/g, () => {
		brCount += 1;
		return brCount <= 3 ? '<br>' : ' ';
	});

	return output.replace(/<span[^>]*><\/span[^>]*>/g, '');
}

function decorateGpsLinks(str) {
	return String(str || '').replace(/%gpslink\|([^|]+)\|(-?\d+(?:\.\d+)?)\|(-?\d+(?:\.\d+)?)\|(-?\d+(?:\.\d+)?)%/g, (full, label, x, y, z) => {
		return `<span class="gps-link" onclick="window.poodlechatSetGpsWaypoint(${x}, ${y}, ${z})">${label}</span>`;
	});
}

function renderRichContent(value) {
	return decorateGpsLinks(colorizeEscapedRichText(escapeRichTextHtml(value)));
}

function stripRichTextCodes(value) {
	return String(value || '')
		.replace(/%gpslink\|([^|]+)\|[^%]+%/g, '$1')
		.replace(/\^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})/g, '')
		.replace(/\^([0-9]|_|\*|=|~|\/|r)/g, '')
		.replace(/\\n/g, ' ')
		.replace(/\s+/g, ' ')
		.trim();
}

function normalizeAuthorSpacing(value) {
	return String(value || '')
		.replace(/(\[[^\]]+\])(?=\S)/g, '$1 ')
		.replace(/\s{2,}/g, ' ')
		.trim();
}

function formatMessageTimestamp(value) {
	const numeric = Number(value);
	if (!Number.isFinite(numeric) || numeric <= 0) {
		return '';
	}

	const date = new Date(numeric < 1000000000000 ? numeric * 1000 : numeric);
	return date.toLocaleTimeString([], {
		hour: '2-digit',
		minute: '2-digit'
	});
}

function formatMessageDateTime(value) {
	const numeric = Number(value);
	if (!Number.isFinite(numeric) || numeric <= 0) {
		return '';
	}

	const date = new Date(numeric < 1000000000000 ? numeric * 1000 : numeric);
	const year = date.getFullYear();
	const month = String(date.getMonth() + 1).padStart(2, '0');
	const day = String(date.getDate()).padStart(2, '0');
	const hours = String(date.getHours()).padStart(2, '0');
	const minutes = String(date.getMinutes()).padStart(2, '0');
	return `${year}-${month}-${day} ${hours}:${minutes}`;
}

window.poodlechatSetGpsWaypoint = window.poodlechatSetGpsWaypoint || function poodlechatSetGpsWaypoint(x, y, z) {
	if (typeof postJson === 'function') {
		postJson('setWaypoint', {x, y, z});
	}
};

window.PoodleChatRichText = window.PoodleChatRichText || {
	escapeHtml: escapeRichTextHtml,
	colorizeEscaped: colorizeEscapedRichText,
	decorateEscaped(value) {
		return decorateGpsLinks(value);
	},
	render(value) {
		return renderRichContent(value);
	}
};

Vue.component('message', {
	template: '#message_template',
	computed: {
		messageData() {
			return this.message && typeof this.message === 'object' ? this.message : {};
		},
		metadata() {
			return this.messageData.metadata && typeof this.messageData.metadata === 'object' ? this.messageData.metadata : {};
		},
		args() {
			return Array.isArray(this.messageData.args) ? this.messageData.args : [];
		},
		color() {
			return Array.isArray(this.messageData.color) ? this.messageData.color : [255, 255, 255];
		},
		multiline() {
			return this.messageData.multiline === true;
		},
		isOffline() {
			return this.metadata.offline === true;
		},
		restored() {
			return this.messageData.restored === true;
		},
		isDeleted() {
			return this.metadata.deleted === true;
		},
		deletedShowsOriginal() {
			return this.metadata.deletedVisibleOriginal === true;
		},
		variant() {
			const type = String(this.metadata.type || '');
			if (type === 'join' || type === 'leave') {
				return 'presence';
			}
			if (type === 'report') {
				return 'report';
			}
			if (type === 'system' || type === 'delete' || String(this.messageData.label || '') === 'System') {
				return 'system';
			}
			return 'chat';
		},
		rowClasses() {
			const classes = {
				multiline: this.multiline,
				'msg-offline': this.isOffline,
				'msg-restored': this.restored,
				'msg-deleted': this.isDeleted,
				'msg-context-selected': this.selectedContextId && this.messageData.messageId === this.selectedContextId,
				[`msg-${this.variant}`]: true,
				[`msg-type-${String(this.metadata.type || 'chat')}`]: true,
				[this.rangeClass]: !!this.rangeClass
			};
			// Presence subtype — used by CSS for join/leave color tinting
			if (this.variant === 'presence') {
				const presenceType = String(this.metadata.type || 'join');
				classes[`msg-presence-${presenceType}`] = true;
			}
			return classes;
		},

		timestampLabel() {
			return formatMessageTimestamp(this.messageData.timestamp);
		},
		presenceChipClass() {
			return String(this.metadata.type || '') === 'leave' ? 'leave' : 'join';
		},
		presenceLabel() {
			return String(this.metadata.type || '') === 'leave' ? 'Left' : 'Joined';
		},
		presenceName() {
			return String(this.metadata.playerName || this.args[0] || '');
		},
		presenceNameHtml() {
			return renderRichContent(normalizeAuthorSpacing(this.presenceName));
		},
		presenceText() {
			return String(this.args[1] || (String(this.metadata.type || '') === 'leave' ? 'left the server' : 'joined the server'));
		},
		presenceReason() {
			return String(this.metadata.reason || this.args[2] || '');
		},
		systemTag() {
			if (this.metadata.subtype === 'delete') {
				return 'Delete';
			}
			return 'System';
		},
		systemTitle() {
			if (this.args.length > 1) {
				return renderRichContent(this.args[0]);
			}
			return '';
		},
		reportReporterHtml() {
			return renderRichContent(normalizeAuthorSpacing(this.metadata.reporterName || this.args[0] || ''));
		},
		reportTargetHtml() {
			return renderRichContent(normalizeAuthorSpacing(this.metadata.targetName || ''));
		},
		reportContext() {
			return this.metadata.reportContext && typeof this.metadata.reportContext === 'object'
				? this.metadata.reportContext
				: null;
		},
		reportContextAuthor() {
			const context = this.reportContext || {};
			return stripRichTextCodes(normalizeAuthorSpacing(context.authorName || ''));
		},
		reportContextExcerpt() {
			const context = this.reportContext || {};
			return stripRichTextCodes(context.excerpt || '');
		},
		messageBadge() {
			const uiConfig = getMessageUiConfig();
			if (this.metadata.type === 'whisper') {
				if (this.metadata.direction === 'out') {
					return 'Reply';
				}
				return this.isOffline ? 'Offline' : 'DM';
			}
			if (this.metadata.type === 'action') {
				return 'Action';
			}
			if (uiConfig.showRestoredIndicator && this.restored && !this.isDeleted) {
				return 'History';
			}
			return '';
		},
		messageBadgeClass() {
			const type = String(this.metadata.type || '');
			if (type === 'whisper') {
				return this.metadata.direction === 'out' ? 'whisper-out' : 'whisper-in';
			}
			if (type === 'action') {
				return 'action';
			}
			return 'history';
		},
		deletedBadgeVisible() {
			return this.isDeleted;
		},
		deleteNoteText() {
			if (this.deletedShowsOriginal) {
				return `Removed by ${String(this.metadata.deletedByName || 'staff')}`;
			}
			return String(this.metadata.deletedReason || 'This message was removed by staff.');
		},
		authorHtml() {
			const metadataType = String(this.metadata.type || '');
			if ((metadataType === 'chat' || metadataType === 'whisper' || metadataType === 'action') && this.metadata.authorName) {
				return renderRichContent(normalizeAuthorSpacing(this.metadata.authorName));
			}
			if (this.args.length > 1) {
				return renderRichContent(normalizeAuthorSpacing(this.args[0]));
			}
			if (this.args.length === 1 && !this.isDeleted) {
				return renderRichContent(normalizeAuthorSpacing(this.args[0]));
			}
			return renderRichContent(normalizeAuthorSpacing(this.metadata.authorName || this.messageData.label || ''));
		},
		bodyHtml() {
			if (this.variant === 'report') {
				return renderRichContent(this.metadata.reason || this.args[1] || '');
			}
			if (this.isDeleted && !this.deletedShowsOriginal) {
				return renderRichContent(this.metadata.deletedReason || 'This message was removed by staff.');
			}
			if (this.args.length > 1) {
				return renderRichContent(this.args.slice(1).join(' '));
			}
			if (this.args.length === 1) {
				return renderRichContent(this.args[0]);
			}
			return this.renderLegacyTemplate();
		},
		authorStyle() {
			return {
				color: `rgb(${this.color[0]}, ${this.color[1]}, ${this.color[2]})`
			};
		},
		replyPreview() {
			return this.metadata.replyTo && typeof this.metadata.replyTo === 'object' ? this.metadata.replyTo : null;
		},
		replyAuthorText() {
			const replyTo = this.replyPreview || {};
			return normalizeAuthorSpacing(replyTo.authorName || '');
		},
		replyExcerptText() {
			const replyTo = this.replyPreview || {};
			return stripRichTextCodes(replyTo.excerpt || '');
		},
		authorPlainText() {
			const metadataType = String(this.metadata.type || '');
			if ((metadataType === 'chat' || metadataType === 'whisper' || metadataType === 'action') && this.metadata.authorName) {
				return stripRichTextCodes(normalizeAuthorSpacing(this.metadata.authorName));
			}
			if (this.args.length > 1) {
				return stripRichTextCodes(normalizeAuthorSpacing(this.args[0]));
			}
			if (this.args.length === 1 && !this.isDeleted) {
				return stripRichTextCodes(normalizeAuthorSpacing(this.args[0]));
			}
			return stripRichTextCodes(normalizeAuthorSpacing(this.metadata.authorName || this.messageData.label || ''));
		},
		bodyPlainText() {
			if (this.variant === 'report') {
				return stripRichTextCodes(this.metadata.reason || this.args[1] || '');
			}
			if (this.isDeleted && !this.deletedShowsOriginal) {
				return stripRichTextCodes(this.metadata.deletedReason || 'This message was removed by staff.');
			}
			if (this.args.length > 1) {
				return stripRichTextCodes(this.args.slice(1).join(' '));
			}
			if (this.args.length === 1) {
				return stripRichTextCodes(this.args[0]);
			}
			return stripRichTextCodes(this.messageData.text || '');
		},
		plainText() {
			return [this.authorPlainText, this.bodyPlainText]
				.filter((entry) => String(entry || '').trim() !== '')
				.join(' ')
				.trim();
		},
		// Preserves raw color codes (^#rrggbb and ^N) so staff can paste the exact format string.
		clipboardText() {
			const time = formatMessageDateTime(this.messageData.timestamp) || 'Unknown time';
			const author = this.authorPlainText || stripRichTextCodes(this.metadata.authorName || this.messageData.label || 'System');
			// Use raw args to keep color codes intact
			let rawBody = '';
			if (this.isDeleted && !this.deletedShowsOriginal) {
				rawBody = this.metadata.deletedReason || 'This message was removed by staff.';
			} else if (this.args.length > 1) {
				rawBody = this.args.slice(1).join(' ');
			} else if (this.args.length === 1) {
				rawBody = this.args[0];
			} else {
				rawBody = this.messageData.text || '';
			}
			return `[${time}] ${author}: ${rawBody}`.trim();
		},
		// Subtle background tint based on sender proximity distance
		rangeClass() {
			const dist = Number(this.metadata.senderDistance || this.metadata.distance);
			if (!Number.isFinite(dist) || dist <= 0) {
				return '';
			}
			if (dist <= 5) {
				return 'msg-range-whisper';
			}
			if (dist <= 15) {
				return 'msg-range-close';
			}
			if (dist <= 30) {
				return 'msg-range-mid';
			}
			return 'msg-range-far';
		}
	},
	methods: {
		renderLegacyTemplate() {
			const uiConfig = getMessageUiConfig();
			let templateValue = this.messageData.template || this.templates[this.messageData.templateId] || '';
			const activeTemplateId = this.messageData.template ? -1 : this.messageData.templateId;

			if (activeTemplateId === uiConfig.defaultTemplateId && this.args.length === 1) {
				templateValue = this.templates[uiConfig.defaultAltTemplateId] || templateValue;
			}

			templateValue = templateValue.replace(/{(\d+)}/g, (match, number) => {
				const argEscaped = this.args[number] !== undefined ? escapeRichTextHtml(this.args[number]) : match;
				if (Number(number) === 0 && this.color) {
					return `<span style="color: rgb(${this.color[0]}, ${this.color[1]}, ${this.color[2]})">${argEscaped}</span>`;
				}
				return argEscaped;
			});

			return decorateGpsLinks(colorizeEscapedRichText(templateValue));
		},
		handleContextMenu(event) {
			this.$emit('message-context', {
				x: event.clientX,
				y: event.clientY,
				message: this.messageData,
				plainText: this.plainText,
				clipboardText: this.clipboardText
			});
		}
	},
	props: {
		message: {
			type: Object,
			required: true
		},
		templates: {
			type: Object,
			default() {
				return {};
			}
		},
		permissions: {
			type: Object,
			default() {
				return {};
			}
		},
		selectedContextId: {
			type: String,
			default: ''
		},
		// When true, messages flagged as deleted are hidden from view (staff toggle)
		hideDeleted: {
			type: Boolean,
			default: false
		}
	}
});
