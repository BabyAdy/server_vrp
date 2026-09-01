fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_clothing'
author 'Purple Havoc'
description 'Purple Havoc - streaming pentru haine CUSTOM (freemode, doar prefix ^) + comanda de test /tryon'
version '0.1.0'

-- ==========================================================
--  STREAMING DE HAINE - DOAR PRIN PREFIX ( ^ ), FARA .meta
--
--  Pui fisierele in  stream/  cu numele exact al slotului din joc:
--    mp_f_freemode_01^jbib_<idx>_u.ydd            (model)
--    mp_f_freemode_01^jbib_diff_<idx>_a_uni.ytd   (textura 0)
--    mp_f_freemode_01^jbib_diff_<idx>_b_uni.ytd   (textura 1)
--    ...
--  `^` din nume e convertit in `/` de FiveM.  <idx> = drawable-ul vanilla
--  pe care il INLOCUIESTI (metoda replace; nu se adauga sloturi noi).
--
--  FiveM detecteaza automat folderul  stream/  - nu e nevoie de `files {}`
--  sau `data_file` pentru .ydd / .ytd.
--
--  Dupa orice modificare:  restart ph_clothing  + reconectare (clientul
--  streameaza hainele doar la intrarea in sesiune).
-- ==========================================================

shared_script 'config.lua'
client_script 'client.lua'
server_script 'commands.lua'
