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
    'data/**/vehiclelayouts.meta',
    'data/**/dlctext.meta',
}

data_file 'VEHICLE_METADATA_FILE'  'data/**/vehicles.meta'
data_file 'CARCOLS_FILE'           'data/**/carcols.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/**/carvariations.meta'
data_file 'HANDLING_FILE'          'data/**/handling.meta'
data_file 'VEHICLE_LAYOUTS_FILE'   'data/**/vehiclelayouts.meta'