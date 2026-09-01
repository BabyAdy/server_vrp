fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_inventory'
author 'Purple Havoc'
description 'Purple Havoc - inventar (grid, echipament pe ped, fast slots, drop pe jos, arme cu munitie/durabilitate)'
version '0.1.0'

dependencies {
    'ph-core',
    'ph_subscriptions',
    'ph_postoffice',
}

shared_script 'config.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'commands.lua',   -- toate comenzile / (dupa server.lua: foloseste INVENV)
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
