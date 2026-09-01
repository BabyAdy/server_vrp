fx_version 'cerulean'
game 'gta5'

name 'ph_cars'
author 'Purple Havoc'
description 'Purple Havoc - streaming pentru vehiculele CUSTOM (modele + meta). Catalogul e in ph_vehicles/data/custom.lua'
version '0.1.0'

-- ==========================================================
--  CUM ADAUGI UN VEHICUL CUSTOM
--  1. Pune modelul in  stream/<spawnname>/  :  .yft .hi.yft _hi.yft .ytd .ycd + interior_*.yft
--     (subfolderele sunt libere - FiveM scaneaza recursiv orice folder `stream`)
--  2. Pune fisierele meta in  data/<spawnname>/  : vehicles.meta, carvariations.meta,
--     carcols.meta, handling.meta si (daca exista) vehiclelayouts.meta
--  3. Adauga o intrare in  resources/[ph]/ph_vehicles/data/custom.lua  ca sa apara in
--     catalog / lista de spawn:  { model = 'spawnname', label = 'Nume Frumos', category = 'car' }
--  4. server.cfg -> `ensure ph_cars`  (deja adaugat) apoi  `restart ph_cars ; restart ph_vehicles`
--
--  NOTA (players-only world): ph_world sterge orice vehicul care nu e "mission entity".
--  /spawncar din staff_menu marcheaza deja vehiculul ca mission entity, deci custom-urile
--  spawnate de acolo raman. Alte sisteme care spawneaza vehicule trebuie sa faca la fel.
-- ==========================================================

files {
    'data/**/vehicles.meta',
    'data/**/carvariations.meta',
    'data/**/carcols.meta',
    'data/**/handling.meta',
    'data/**/dlctext.meta',
    -- Daca un vehicul chiar are `vehiclelayouts.meta`, adauga aici linia
    --   'data/**/vehiclelayouts.meta',
    -- si `data_file 'VEHICLE_LAYOUTS_FILE' 'data/**/vehiclelayouts.meta'` mai jos.

    -- audio custom de vehicul (mf1 / mf1c -> dlc_progenmf1)
    'audio/config/mf1_game.dat151.rel',
    'audio/config/mf1_game.dat151.nametable',
    'audio/config/mf1_sounds.dat54.rel',
    'audio/config/mf1_sounds.dat54.nametable',
    'audio/config/mf1c_game.dat151.rel',
    'audio/config/mf1c_game.dat151.nametable',
    'audio/config/mf1c_sounds.dat54.rel',
    'audio/config/mf1c_sounds.dat54.nametable',
    'audio/sfx/dlc_progenmf1/progenmf1.awc',
    'audio/sfx/dlc_progenmf1/progenmf1_npc.awc',
}

data_file 'VEHICLE_METADATA_FILE'  'data/**/vehicles.meta'
data_file 'CARCOLS_FILE'           'data/**/carcols.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/**/carvariations.meta'
data_file 'HANDLING_FILE'          'data/**/handling.meta'

-- ==========================================================
--  AUDIO CUSTOM DE VEHICUL
--  Fisierele efective: audio/config/<name>_game.dat151(.rel/.nametable) +
--  audio/config/<name>_sounds.dat54(.rel/.nametable), iar AWC-urile in
--  audio/sfx/<dlcname>/ .  In `data_file` se scrie calea FARA "151"/"54"/".rel"
--  (motorul le adauga singur).  Pentru fiecare model nou de vehicul cu audio
--  propriu adaugi inca o pereche GAMEDATA + SOUNDDATA + fisierele in `files{}`.
-- ==========================================================
data_file 'AUDIO_GAMEDATA'  'audio/config/mf1_game.dat'
data_file 'AUDIO_SOUNDDATA' 'audio/config/mf1_sounds.dat'
data_file 'AUDIO_GAMEDATA'  'audio/config/mf1c_game.dat'
data_file 'AUDIO_SOUNDDATA' 'audio/config/mf1c_sounds.dat'
data_file 'AUDIO_WAVEPACK'  'audio/sfx/dlc_progenmf1'