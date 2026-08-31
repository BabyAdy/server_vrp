Config = {}

-- Meniul se deschide cu /staffmenu (comanda e inregistrata in ph-core, care
-- trimite evenimentul `ph-core:staff:openMenu` catre acest resource).
-- Grad minim ca sa poti deschide meniul:
Config.MinGrade = 'trialhelper'

-- Categorii acceptate pentru /ticket  (prima e implicita)
Config.TicketCategories = { 'general', 'bug', 'report', 'question', 'refund' }

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
    Key       = 'F2',
    MinGrade  = 'trialadmin',
    SelfAlpha = 150,   -- cat de transparent te vezi TU cat esti in noclip (0-255); ceilalti nu te vad deloc
    -- Noclip e strict pentru staff -> toate vitezele sunt disponibile mereu.
    -- `mps` = viteza in metri/secunda (deplasarea pe frame = mps * frametime)
    Speeds = {
        { name = 'Slow',      label = 'Incet',            mps = 3.0   },
        { name = 'Normal',    label = 'Normal',           mps = 9.0   },
        { name = 'Fast',      label = 'Rapid',            mps = 20.0  },
        { name = 'Very Fast', label = 'Foarte rapid',     mps = 45.0  },
        { name = 'Sasuke',    label = 'MEGA ULTRA RAPID', mps = 140.0 },
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
    tab_staff       = 'trialhelper',
    tab_tickets     = 'trialhelper',
    tab_active      = 'trialhelper',
    tab_players     = 'trialhelper',
    tab_developer   = 'manager',

    -- actiuni pe jucatori
    goto_player     = 'trialhelper',
    bring_player    = 'helper',
    spectate        = 'helper',
    freeze          = 'trialadmin',
    revive          = 'trialadmin',
    heal            = 'trialadmin',
    warn            = 'trialadmin',
    kick            = 'junioradmin',
    ban             = 'generaladmin',
    unban           = 'headadmin',
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
    -- exemplu:
    -- { name = 'Depozit PD',  model = 'v_ilev_ph_door01', x = 461.79,  y = -1002.9, z = 24.91 },
    -- { name = 'Poarta X',    model = -1281601925,        x = 100.0,   y = 200.0,   z = 30.0  },
}
Config.DoorRefreshMs = 15000   -- re-aplica starea "incuiat" periodic

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
