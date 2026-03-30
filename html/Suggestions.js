function getSuggestionLimit() {
	const config = window.PoodleChatUiConfig || {};
	const limit = Number(config.suggestionLimit);
	if (Number.isFinite(limit) && limit > 0) {
		return Math.floor(limit);
	}
	return 5;
}

Vue.component('suggestions', {
	template: '#suggestions_template',
	props: ['message', 'suggestions'],
	data() {
		return {};
	},
	computed: {
		currentSuggestions() {
			if (this.message === '') {
				return [];
			}

			const filtered = this.suggestions
				.filter((suggestion) => {
					if (!suggestion.name.startsWith(this.message)) {
						const suggestionSplit = suggestion.name.split(' ');
						const messageSplit = this.message.split(' ');

						for (let i = 0; i < messageSplit.length; i += 1) {
							if (i >= suggestionSplit.length) {
								return i < suggestionSplit.length + suggestion.params.length;
							}
							if (suggestionSplit[i] !== messageSplit[i]) {
								return false;
							}
						}
					}
					return true;
				})
				.slice(0, getSuggestionLimit())
				.map((suggestion) => ({
					...suggestion,
					disabled: !suggestion.name.startsWith(this.message),
					params: (suggestion.params || []).map((param, index) => {
						const wType = index === suggestion.params.length - 1 ? '.' : '\\S';
						const regex = new RegExp(`${suggestion.name} (?:\\w+ ){${index}}(?:${wType}*)$`, 'g');
						return {
							...param,
							disabled: this.message.match(regex) == null
						};
					})
				}));

			return filtered;
		}
	}
});
