fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_postoffice'
author 'Purple Havoc'
description 'Purple Havoc - post office (iteme puse deoparte cand inventarul nu incape)'
version '0.1.0'

dependency 'ph-core'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}
