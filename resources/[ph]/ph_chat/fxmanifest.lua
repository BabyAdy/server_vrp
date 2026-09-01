fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_chat'
author 'Purple Havoc'
description 'Purple Havoc - chat (inlocuieste chat-ul default)'
version '0.1.0'

provide 'chat'

dependency 'ph-core'

shared_script 'config.lua'
client_script 'client.lua'
server_scripts {
    'server.lua',
    'commands.lua',   -- toate comenzile / (dupa server.lua: foloseste CHATENV)
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
