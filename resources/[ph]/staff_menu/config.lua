Config = {}

-- Antetul minimalist (logo + numele serverului) - stanga sus in toate meniurile.
Config.ServerName = 'Purple Havoc'
Config.Logo       = 'https://i.imgur.com/eAfdBdO.png'   -- URL (gol = ascuns)

-- Meniul se deschide cu /staffmenu (tab Home) sau /tk (tab Tickets).
-- Comenzile sunt inregistrate in ph-core (trimite `ph-core:staff:openMenu`).
-- Grad minim ca sa poti deschide meniul:
Config.MinGrade = 'trialhelper'

-- ----------------------------------------------------------
--  Haine de staff  (tab-ul Home + Dev Tools)
--    Cele 6 butoane din Home ; item-ul se da dupa GRADUL jucatorului.
--    In Dev Tools apar toate gradele (dev poate testa orice).
--  Item-ul e dat din inventar prin  exports['ph_inventory']:GiveItem .
-- ----------------------------------------------------------
Config.StaffClothingPieces = {
    { id = 'mask_m',   label = 'Masca Staff (M)',   sex = 'm' },
    { id = 'mask_f',   label = 'Masca Staff (F)',   sex = 'f' },
    { id = 'tshirt_m', label = 'Tricou Staff (M)',  sex = 'm' },
    { id = 'tshirt_f', label = 'Tricou Staff (F)',  sex = 'f' },
    { id = 'hoodie_m', label = 'Hanorac Staff (M)', sex = 'm' },
    { id = 'hoodie_f', label = 'Hanorac Staff (F)', sex = 'f' },
}

-- Suprascrieri punctuale de nume de item : Config.StaffClothingItems[grade][pieceId]
Config.StaffClothingItems = {
    -- ['owner'] = { mask_m = 'staff_owner_mask_m', hoodie_f = 'staff_owner_hoodie_f', ... },
}

--- numele item-ului din ph_inventory pentru (grad, piesa).
--- schema implicita:  staff_<grad>_<pieceId>   (ex: staff_owner_mask_m)
function Config.StaffClothingItem(grade, pieceId)
    grade = tostring(grade or 'none')
    local o = Config.StaffClothingItems[grade]
    if o and o[pieceId] then return o[pieceId] end
    return ('staff_%s_%s'):format(grade, tostring(pieceId or ''))
end

-- Categorii acceptate pentru vechiul /ticket text (pastrate pentru compat).
Config.TicketCategories = { 'general', 'bug', 'report', 'question', 'refund' }

-- Culoare pe tipul de ticket (dupa gravitate) - folosita in UI.
Config.TicketTypeColors = {
    question  = '#4db8ff',
    general   = '#eab308',
    highstaff = '#ef4444',
    -- fallback-uri pentru tipurile vechi
    bug = '#eab308', report = '#f97316', refund = '#a855f7',
}

Config.MaxBanDays = 3650            -- 0 zile la ban = permanent
Config.PlayerRefreshMs = 5000       -- cat de des se reimprospateaza lista de playeri in meniu

-- ----------------------------------------------------------
--  Anunturi de conectare/deconectare pentru staff
--    "Staff Notice: [grad] Username has connected to the server!"
--  Se trimit in chat catre staff >= NoticeMinGrade, se scriu in `staff_logs`
--  si se trimit pe Discord (cu [ID: <sqlId>] la final).
-- ----------------------------------------------------------
Config.NoticeMinGrade = 'trialhelper'

Config.Discord = {
    Webhook  = 'https://discord.com/api/webhooks/1543915218181038080/uiH2_eCpCaB5wjJY3bsV2sd-y4-kzgBWKq1ZWRCBdNgtop664U77ZpCv2_mqJo8jkEFQ',                       -- pune aici URL-ul webhook-ului (gol = dezactivat)
    Username = 'Purple Havoc | Staff',
    Avatar   = '',                       -- URL avatar (optional)
    Colors   = { connect = 3066993, disconnect = 15105570, crash = 15158332 },
}

-- ----------------------------------------------------------
--  Noclip  (tasta F2, staff >= trialadmin)
--    F2 = toggle ; W/S = fata/spate ; Q/E = sus/jos ; L Shift = cicleaza viteza
--    Vitezele se deblocheaza in functie de level-ul personajului (users.level).
-- ----------------------------------------------------------
Config.Noclip = {
    Key       = 'F2',    -- default afisat in Settings > Key Bindings (rebindabil)
    RawKey    = 289,      -- poll direct pe tasta (289 = F2) ca sa mearga si fara bind salvat
    MinGrade  = 'trialadmin',
    SelfAlpha = 150,   -- cat de transparent te vezi TU cat esti in noclip (0-255); ceilalti nu te vad deloc
    -- Noclip e strict pentru staff -> toate vitezele sunt disponibile mereu.
    -- `mps` = viteza in metri/secunda (deplasarea pe frame = mps * frametime)
    Speeds = {
        { name = 'Slow',      label = 'Slow',             mps = 3.0   },
        { name = 'Normal',    label = 'Normal',           mps = 9.0   },
        { name = 'Fast',      label = 'Fast',             mps = 20.0  },
        { name = 'Very Fast', label = 'Very Fast',        mps = 45.0  },
        { name = 'Sasuke',    label = 'MEGA ULTRA FAST',  mps = 140.0 },
    },
}

-- Cuvinte-cheie in motivul de drop care inseamna "crash" (nu quit voluntar)
Config.CrashReasons = {
    'timed out', 'time out', 'timeout', 'crash', 'connection', 'reset',
    'overflow', 'malformed', 'hang', 'unexpectedly',
}

-- ----------------------------------------------------------
--  Permisiuni: actiune -> grad minim necesar
--  (cheile din Config.StaffGrades din ph-core)
-- ----------------------------------------------------------
Config.Perms = {
    -- tab-uri
    tab_home        = 'trialhelper',
    tab_staff       = 'trialhelper',   -- (pastrat pentru compat cu vechiul tab)
    tab_tickets     = 'trialhelper',
    tab_active      = 'trialhelper',
    tab_players     = 'trialhelper',
    tab_developer   = 'developer',     -- "Dev Tools"

    -- actiuni pe jucatori  (panoul Players)
    goto_player     = 'trialhelper',
    bring_player    = 'helper',
    spectate        = 'helper',
    freeze          = 'trialadmin',
    revive          = 'trialadmin',
    heal            = 'trialadmin',
    warn            = 'trialadmin',
    kick            = 'trialadmin',
    ban             = 'trialadmin',
    ban_offline     = 'headadmin',
    unban           = 'leadadmin',
    announce        = 'junioradmin',

    -- vehicule (comenzi)
    dv              = 'trialadmin',
    spawncar        = 'generaladmin',
    fix             = 'generaladmin',
    flip            = 'generaladmin',
    maxperf         = 'manager',
    dvall           = 'manager',

    -- utilitare
    setvw           = 'trialadmin',   -- /setvw <sqlId> <virtualWorld>
    doorinfo        = 'developer',    -- /doorinfo -> afiseaza model + coords ale usii din apropiere

    -- economie (amount negativ = scade, plafonat la 0)
    givemoney       = 'manager',      -- /givemoney  <sqlId> <amount>
    givebmoney      = 'manager',      -- /givebmoney <sqlId> <amount>
    givepp          = 'manager',      -- /givepp     <sqlId> <amount>

    -- developer
    set_staff       = 'manager',
    restart_resource = 'developer',
    tp_coords       = 'manager',
    server_info     = 'manager',
}

-- /dvall: cat asteptam dupa anunt inainte sa stergem (secunde)
Config.DvallDelaySec = 10

-- ----------------------------------------------------------
--  Usi inchise & incuiate permanent (fara UI, fara marker - doar inchise).
--  `model` = numele prop-ului (string) SAU hash-ul numeric (din /doorinfo).
--  Foloseste /doorinfo langa o usa ca sa afli model + coords.
-- ----------------------------------------------------------
Config.Doors = {
    { name = 'LSPD - Front Right Door', model = 320433149, x = 434.75, y = -983.22, z = 30.84 },
    { name = 'LSPD - Front Left Door', model = -1215222675, x = 434.75, y = -980.62, z = 30.84 },
    { name = 'LSPD - Armory Left Door', model = 185711165, x = 450.10, y = -981.49, z = 30.84 },
    { name = 'LSPD - Locker Room Door', model = 1557126584, x = 450.10, y = -985.74, z = 30.84 },
    { name = 'LSPD - Cells Left Door', model = 185711165, x = 446.01, y = -989.45, z = 30.84 },
    { name = 'LSPD - Cells Right Door', model = 185711165, x = 443.41, y = -989.45, z = 30.84 },
    { name = 'LSPD - Back Cells Door', model = -1033001619, x = 463.48, y = -1003.54, z = 25.01 },
    { name = 'LSPD - Back Left Door', model = -2023754432, x = 467.37, y = -1014.45, z = 26.54 },
    { name = 'LSPD - Back Right Door', model = -2023754432, x = 469.97, y = -1014.45, z = 26.54 },

    -- Cum adaugi altele:
    --   1. ruleaza /doorinfo -> intri in modul de ochire
    --   2. te uiti la usa (apare un marker pe ea) si apesi [E]
    --   3. in consola F8 apare o linie gata de copiat: { name = '', model = ..., x = ..., y = ..., z = ... },
    --   4. o lipesti aici, pui un nume, si ensure staff_menu
    -- Usi duble = 2 obiecte -> ochesti fiecare canat separat, adaugi 2 intrari.
}
Config.DoorRefreshMs = 3000   -- re-aplica starea "incuiat" periodic (si dupa schimbari de virtual world)

-- Ce actiuni apar in tab-ul "Staff" (moderare) - filtrate dupa grad la runtime
Config.StaffActions = {
    { id = 'goto_player', label = 'Goto',      needsTarget = true },
    { id = 'bring_player', label = 'Bring',    needsTarget = true },
    { id = 'spectate',    label = 'Spectate',  needsTarget = true },
    { id = 'freeze',      label = 'Freeze',    needsTarget = true },
    { id = 'revive',      label = 'Revive',    needsTarget = true },
    { id = 'heal',        label = 'Heal',      needsTarget = true },
    { id = 'warn',        label = 'Warn',      needsTarget = true, needsReason = true },
    { id = 'kick',        label = 'Kick',      needsTarget = true, needsReason = true },
    { id = 'ban',         label = 'Ban',       needsTarget = true, needsReason = true, needsDays = true },
    { id = 'unban',       label = 'Unban',     needsRef = true },
    { id = 'announce',    label = 'Announce',  needsText = true },
}
