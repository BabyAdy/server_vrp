fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_clans'
author 'Purple Havoc'
description 'Purple Havoc - sistemul de clanuri (chat, ranguri, permisiuni, safebox, tag-uri, MOTD, expirare pe zile, meniul /clan + vehicule de clan)'
version '0.2.0'

dependencies {
    'ph-core',
    'ph_vehicles',   -- catalogul de vehicule pentru tab-ul "Buy Vehicles"
}

shared_script 'config.lua'

client_scripts {
    'client.lua',     -- NUI-ul /clan + vehiculele de clan
    'clan_cmd.lua',   -- comenzile de client ( /clan /clanmenu /cvr )
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'clan_cmd.lua',   -- dupa server.lua: foloseste CLANENV
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
