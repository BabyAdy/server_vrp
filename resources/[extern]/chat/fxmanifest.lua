fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'chat'
description 'Chat stil Fondator - adaptat la framework-ul Purple Havoc (ph-core)'
version '1.1.0'

dependency 'ph-core'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

client_script 'client.lua'
server_script 'server.lua'
