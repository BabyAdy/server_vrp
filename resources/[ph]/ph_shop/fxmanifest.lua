fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_shop'
author 'Purple Havoc'
description 'Purple Havoc - magazin cu Premium Points (bilete de abonament, slot vehicul, numar de telefon, creare clan)'
version '0.1.0'

dependency 'ph-core'

shared_script 'config.lua'

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'commands.lua',   -- /shop (dupa server.lua: foloseste SHOPENV)
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
