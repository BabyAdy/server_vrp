fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'staff_menu'
author 'Purple Havoc'
description 'Purple Havoc - meniu staff (moderare, tickete, players, developer)'
version '0.1.0'

dependency 'ph-core'

shared_script 'config.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'staff_cmd.lua',   -- toate comenzile / (dupa server.lua: foloseste SMENV)
}

client_script 'client.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
