fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_clans'
author 'Purple Havoc'
description 'Purple Havoc - sistemul de clanuri (chat, ranguri, permisiuni, safebox, tag-uri, MOTD, expirare pe zile)'
version '0.1.0'

dependency 'ph-core'

shared_script 'config.lua'

client_scripts {
    'clan_cmd.lua',   -- ramura de client se opreste imediat (Faza 2 adauga /clan)
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'clan_cmd.lua',   -- dupa server.lua: foloseste CLANENV
}
