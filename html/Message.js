function getMessageUiConfig() {
	const config = window.PoodleChatUiConfig || {};
	return {
		defaultTemplateId: typeof config.defaultTemplateId === 'string' ? config.defaultTemplateId : 'default',
		defaultAltTemplateId: typeof config.defaultAltTemplateId === 'string' ? config.defaultAltTemplateId : 'defaultAlt'
	};
}

Vue.component('message', {
	template: '#message_template',
	data() {
		return {};
	},
	computed: {
		textEscaped() {
			const uiConfig = getMessageUiConfig();
			let templateValue = this.template || this.templates[this.templateId] || '';
			const activeTemplateId = this.template ? -1 : this.templateId;

			if (activeTemplateId === uiConfig.defaultTemplateId && this.args.length === 1) {
				templateValue = this.templates[uiConfig.defaultAltTemplateId] || templateValue;
			}

			templateValue = templateValue.replace(/{(\d+)}/g, (match, number) => {
				const argEscaped = this.args[number] !== undefined ? this.escape(this.args[number]) : match;
				if (Number(number) === 0 && this.color) {
					return this.colorizeOld(argEscaped);
				}
				return argEscaped;
			});

			return this.colorize(templateValue);
		}
	},
	methods: {
		colorizeOld(str) {
			return `<span style="color: rgb(${this.color[0]}, ${this.color[1]}, ${this.color[2]})">${str}</span>`;
		},
		colorize(str) {
			let output = `<span>${str.replace(/\^([0-9])/g, (match, color) => `</span><span class="color-${color}">`)}</span>`;

			const styleDict = {
				'*': 'font-weight: bold;',
				'_': 'text-decoration: underline;',
				'~': 'text-decoration: line-through;',
				'=': 'text-decoration: underline line-through;',
				r: 'text-decoration: none;font-weight: normal;'
			};

			const styleRegex = /\^(\_|\*|\=|\~|\/|r)(.*?)(?=$|\^r|<\/em>)/;
			while (styleRegex.test(output)) {
				output = output.replace(styleRegex, (match, style, inner) => `<em style="${styleDict[style]}">${inner}</em>`);
			}

			return output.replace(/<span[^>]*><\/span[^>]*>/g, '');
		},
		escape(unsafe) {
			return String(unsafe)
				.replace(/&/g, '&amp;')
				.replace(/</g, '&lt;')
				.replace(/>/g, '&gt;')
				.replace(/"/g, '&quot;')
				.replace(/'/g, '&#039;');
		}
	},
	props: {
		templates: {
			type: Object
		},
		args: {
			type: Array
		},
		template: {
			type: String,
			default: null
		},
		templateId: {
			type: String,
			default() {
				return getMessageUiConfig().defaultTemplateId;
			}
		},
		multiline: {
			type: Boolean,
			default: false
		},
		color: {
			type: Array,
			default: false
		}
	}
});
