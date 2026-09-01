fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ph_clothing'
author 'Purple Havoc'
description 'Purple Havoc - streaming pentru haine CUSTOM (freemode) + comanda de test /tryon'
version '0.1.0'

-- ==========================================================
--  DOUA METODE DE A ADAUGA HAINE
--
--  A) REPLACE (fara meta, merge imediat) - inlocuiesti sloturi vanilla existente.
--     Pui .ydd + .ytd in  stream/  cu NUMELE EXACT al fisierului din joc, ex:
--       mp_m_freemode_01^jbib_diff_015_a_uni.ytd
--       mp_m_freemode_01^jbib_015_u.ydd
--     Limitat la numarul de drawable-uri vanilla; nu adaugi sloturi noi.
--
--  B) ADDON (recomandat, non-distructiv) - adaugi drawable-uri NOI peste cele vanilla.
--     Ai nevoie de fisiere .meta per model. Decomenteaza blocul de mai jos si pune
--     pack-ul in  meta/<model>/  +  stream/<model>/ .
--     Indecsii noi (drawable) sunt cei de dupa ultimul vanilla - ii vezi cu /tryon.
--
--  Dupa orice modificare:  restart ph_clothing
-- ==========================================================

shared_script 'config.lua'
client_script 'client.lua'
server_script 'commands.lua'

-- ==========================================================
--  ADDON CLOTHING (drawable-uri NOI, non-distructiv)
--
--  Colectie:  mp_f_freemode_01_staff  (jbib / component 11 = top)
--  Fisiere in stream/ :
--    mp_f_freemode_01_staff^jbib_002_u.ydd            (model)
--    mp_f_freemode_01_staff^jbib_diff_002_a_uni.ytd   (textura 0 - Owner)
--    mp_f_freemode_01_staff^jbib_diff_002_b_uni.ytd   (textura 1 - Developer)
--    mp_f_freemode_01_staff^jbib_diff_002_c_uni.ytd   (textura 2 - Manager)
--
--  Jocul adauga drawable-ul dupa cele vanilla -> indexul REAL il afli in joc cu
--    /tryon info                (numarul de variatii component 11)
--    /tryon component 11 <N>    (cauta pana apare hanoracul)
--  apoi pui <N> in  ph_inventory/config.lua  (STAFF_F_JBIB_DRAWABLE).
--
--  Pentru fiecare colectie noua: adaugi un .meta si inca o linie data_file.
-- ==========================================================
files {
    'meta/mp_f_freemode_01_staff.meta',
}
data_file 'SHOP_PED_APPAREL_META_FILE' 'meta/mp_f_freemode_01_staff.meta'
