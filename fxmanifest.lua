fx_version "cerulean"
games {"gta5"}

name "PoodleChat"
description "Chat resource optimized and reworked"
author "kibukj (made the original version), arobase7sur7 "
repository "https://github.com/arobase7sur7/poodlechat"

files {
	"html/index.html",
	"html/index.css",
	"html/emojibase.json",
	"html/app.js",
	"html/js/core.js",
	"html/js/emoji.js",
	"html/js/widgets.js",
	"html/js/ui_runtime.js",
	"html/Message.js",
	"html/Suggestions.js",
	"html/vendor/vue.2.3.3.min.js",
	"html/vendor/flexboxgrid.6.3.1.min.css",
	"html/vendor/animate.3.5.2.min.css",
	"html/vendor/latofonts.css",
	"html/vendor/fonts/LatoRegular.woff2",
	"html/vendor/fonts/LatoRegular2.woff2",
	"html/vendor/fonts/LatoLight2.woff2",
	"html/vendor/fonts/LatoLight.woff2",
	"html/vendor/fonts/LatoBold.woff2",
	"html/vendor/fonts/LatoBold2.woff2",
}

ui_page "html/index.html"

shared_scripts {
	"shared/config.lua",
	"shared/emoji_utils.lua"
}

client_scripts {
	"client/modules/bootstrap.lua",
	"client/modules/emoji.lua",
	"client/modules/chat.lua",
	"client/modules/features.lua",
	"client/modules/nui.lua",
	"client/client.lua"
}

server_scripts {
	"server/modules/bootstrap.lua",
	"server/modules/emoji.lua",
	"server/modules/chat.lua",
	"server/modules/moderation.lua",
	"server/server.lua"
}
