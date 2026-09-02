fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_tickets'
author 'Purple Havoc'
description 'Purple Havoc - sistemul de tickete al jucatorilor (/ticket) : creare, tichetele mele, chat live cu staff-ul care a acceptat'
version '0.1.0'

dependency 'ph-core'

shared_script 'config.lua'

client_scripts {
    'client.lua',
    'ticket_cmd.lua',   -- /ticket (client) ; branch-uit cu IsDuplicityVersion
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
