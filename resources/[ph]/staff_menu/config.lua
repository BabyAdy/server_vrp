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

    -- developer
    set_staff       = 'manager',
    restart_resource = 'developer',
    tp_coords       = 'manager',
    server_info     = 'manager',
}

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
