fx_version "cerulean"
games {"gta5"}

name "PoodleChat"
description "Chat resource optimized and reworked"
author "kibukj (made the original version), arobase7sur7 "
repository "https://github.com/arobase7sur7/poodlechat"

files {
	"html/index.html",
	"html/emojibase.json",
	"html/assets/app.js",
	"html/assets/app.css",
	"html/vendor/interfonts.css",
	"html/vendor/fonts/InterRegular.woff2",
	"html/vendor/fonts/InterMedium.woff2",
	"html/vendor/fonts/InterSemiBold.woff2",
	"html/vendor/fonts/InterBold.woff2",
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
	"server/modules/config_runtime.lua",
	"server/modules/permissions.lua",
	"server/modules/audit.lua",
	"server/modules/emoji.lua",
	"server/modules/commands.lua",
	"server/modules/chat.lua",
	"server/modules/moderation.lua",
	"server/modules/automessages.lua",
	"server/modules/manager.lua",
	"server/server.lua"
}
