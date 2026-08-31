fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_factions'
author 'Purple Havoc'
description 'Purple Havoc - factiuni (HQ + interior, rank-uri custom, garaje pe rank, duty, /factionmenu, tester/supervisor)'
version '0.1.0'

dependencies {
    'ph-core',
    'ph_vehicles',
}

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
}
