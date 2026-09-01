fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_factions'
author 'Purple Havoc'
description 'Purple Havoc - factiuni (HQ + interior, rank-uri custom, garaje pe rank, duty, /factionmenu + /devfactionmenu)'
version '0.1.0'

dependencies {
    'ph-core',
    'ph_vehicles',
}

shared_script 'config.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'faction_cmd.lua',   -- comenzile / server (dupa server.lua: foloseste globalele resursei)
}

client_scripts {
    'client.lua',
    'faction_cmd.lua',   -- /factionmenu + /devfactionmenu (branch-uit cu IsDuplicityVersion)
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
