fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_subscriptions'
author 'Purple Havoc'
description 'Purple Havoc - abonamente Gold / Platinum (sloturi bonus, premium chat)'
version '0.1.0'

dependency 'ph-core'

shared_script 'config.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'commands.lua',   -- toate comenzile / (dupa server.lua: foloseste SUBENV)
}
