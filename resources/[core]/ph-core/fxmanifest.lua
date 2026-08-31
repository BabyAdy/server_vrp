fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph-core'
author 'Purple Havoc'
description 'Purple Havoc RPG - core framework: accounts, characters, auth NUI'
version '0.1.0'

dependency 'oxmysql'

shared_scripts {
    'config/config.lua',
    'shared/utils.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/crypto.js',
    'server/database.lua',
    'server/session.lua',
    'server/account.lua',
    'server/character.lua',
    'server/public.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
    'client/auth.lua',
    'client/character.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
