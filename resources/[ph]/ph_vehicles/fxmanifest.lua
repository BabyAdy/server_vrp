fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_vehicles'
author 'Purple Havoc'
description 'Purple Havoc - catalog de vehicule + vehicule personale (/v, /park, chei, HUD speedometer)'
version '0.2.0'

dependency 'ph-core'

shared_scripts {
    'data/vanilla.lua',
    'data/custom.lua',
    'shared.lua',
    'config.lua',
}

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'commands.lua',   -- toate comenzile / (dupa server.lua: foloseste VEHENV)
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/img/*.png',
    'html/img/*.jpg',
    'html/img/*.webp',
}
