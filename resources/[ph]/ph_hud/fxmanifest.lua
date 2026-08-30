fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_hud'
author 'Purple Havoc'
description 'Purple Havoc - HUD (identitate, bani, ceas, status, nevoi)'
version '0.1.0'

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
