fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_appearance'
author 'Purple Havoc'
description 'Purple Havoc - character creator (freemode heritage / face / hair / overlays / eyes) + /editcharacter'
version '0.1.0'

dependency 'ph-core'

shared_scripts {
    'config.lua',
    'shared.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'appearance_cmd.lua',   -- /editcharacter (dupa server.lua)
}

client_scripts {
    'client.lua',
    'appearance_cmd.lua',   -- /editcharacter (branch-uit cu IsDuplicityVersion)
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
