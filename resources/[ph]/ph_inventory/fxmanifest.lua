fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_inventory'
author 'Purple Havoc'
description 'Purple Havoc - inventar (grid, echipament pe ped, fast slots, drop pe jos, arme cu munitie/durabilitate)'
version '0.1.0'

dependency 'ph-core'

shared_script 'config.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

client_script 'client.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/img/*.png',
    'html/img/*.webp',
    'html/img/*.svg',
    'html/img/*.jpg',
}
