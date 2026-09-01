Config = {}

-- Print de debug in consola serverului/clientului
Config.Debug = true

-- ----------------------------------------------------------
--  Autentificare
-- ----------------------------------------------------------
Config.Username = {
    minLength = 3,
    maxLength = 24,
    -- litere, cifre si underscore (este si numele in joc, stil SAMP)
    pattern   = '^[%w_]+$',
}

Config.Password = {
    minLength = 6,
    maxLength = 64,
}

-- Camera cinematografica afisata peste ecranul de login / creare personaj
Config.AuthCamera = {
    coords  = vec3(-263.52, -1015.44, 150.0),
    pointAt = vec3(-380.0, -820.0, 45.0),
}

-- ----------------------------------------------------------
--  Personaj
-- ----------------------------------------------------------
-- Punctul unde apare un personaj nou (Legion Square)
Config.NewCharacterSpawn = {
    x = 195.17, y = -933.77, z = 30.69, heading = 144.5,
}

-- Modele folosite pentru personaj (editor de aspect complet vine in v2)
Config.PedModels = {
    male   = 'mp_m_freemode_01',
    female = 'mp_f_freemode_01',
}

-- Varsta acceptata la creare (ani)
Config.Character = {
    minAge = 18,
    maxAge = 100,
    minHeight = 140,
    maxHeight = 220,
}

-- Plafonul afisat pentru toate warn-urile ( x / WarnCap )
Config.WarnCap = 3

-- ----------------------------------------------------------
--  Avansare in nivel  (/buylevel, inca neimplementat)
--    [nivelTinta] = { money = cost $, rp = RP necesari }
--  /stats afiseaza  RP: <rp curent> / <rp necesari pentru nivelul urmator>.
--  Nivelele nelistate folosesc Config.LevelUpFormula.
-- ----------------------------------------------------------
Config.LevelUp = {
    [2] = { money = 1000, rp = 3 },
}
function Config.LevelUpFormula(targetLevel)
    local n = math.max(2, math.floor(targetLevel))
    return {
        money = math.floor(1000 * (n - 1) ^ 1.6),
        rp    = 3 * (n - 1),
    }
end

--- costul (money + rp) pentru a ajunge la `targetLevel`
function Config.LevelCost(targetLevel)
    return Config.LevelUp[targetLevel] or Config.LevelUpFormula(targetLevel)
end

-- Salvare automata a personajelor (ms)
Config.AutoSaveInterval = 5 * 60 * 1000

-- ----------------------------------------------------------
--  Grade de staff (cheia = valoarea din users.staff)
-- ----------------------------------------------------------
Config.StaffGrades = {
    owner        = { label = 'Owner',         color = '#5100ff' },
    developer    = { label = 'Developer',     color = '#da9dff' },
    manager      = { label = 'Manager',       color = '#ff0000' },
    headstaff    = { label = 'Head Staff',    color = '#00e1ff' },
    leadadmin    = { label = 'Lead Admin',    color = '#8f2ad1' },
    headadmin    = { label = 'Head Admin',    color = '#ff6a00' },
    generaladmin = { label = 'General Admin', color = '#ff6a00' },
    junioradmin  = { label = 'Junior Admin',  color = '#ff6a00' },
    trialadmin   = { label = 'Trial Admin',   color = '#ff6a00' },
    headhelper   = { label = 'Head Helper',   color = '#37ff00' },
    helper       = { label = 'Helper',        color = '#37ff00' },
    trialhelper  = { label = 'Trial Helper',  color = '#37ff00' },
}

-- Ordine ierarhica (de la cel mai mic la cel mai mare) - pentru comparatii de permisiuni
Config.StaffOrder = {
    'trialhelper', 'helper', 'headhelper',
    'trialadmin', 'junioradmin', 'generaladmin', 'headadmin', 'leadadmin',
    'headstaff', 'manager', 'developer', 'owner',
}

-- ----------------------------------------------------------
--  Vizibilitatea mesajelor de tip "Staff: ..."
--
--  Fiecare actiune de staff care produce un anunt in chat este trimisa DOAR
--  catre membrii staff-ului cu gradul >= valoarea de mai jos, iar mesajul
--  poarta eticheta "Staff: (staff >= <grad>) ...".
--  Schimba gradul unei chei ca sa restrangi / largesti cine vede acel anunt.
--  O cheie lipsa foloseste Config.StaffMsgDefault.
-- ----------------------------------------------------------
Config.StaffMsgDefault = 'trialhelper'

Config.StaffMsgGrades = {
    -- ph-core
    getbeta     = 'manager',

    -- staff_menu
    heal        = 'trialadmin',
    revive      = 'trialadmin',
    spawncar    = 'generaladmin',
    dv          = 'trialadmin',
    dvall       = 'manager',
    fix         = 'generaladmin',
    flip        = 'generaladmin',
    maxperf     = 'manager',
    setvw       = 'trialadmin',
    doorinfo    = 'developer',
    noclip      = 'trialadmin',
    spectate    = 'trialadmin',
    ticket      = 'trialhelper',

    -- ph_world
    time         = 'manager',
    weather      = 'manager',

    -- ph_subscriptions
    subscription = 'manager',

    -- ph_factions
    faction      = 'leadadmin',

    -- ph_shop / ph_clans
    clan         = 'leadadmin',
}

-- ----------------------------------------------------------
--  /getbeta [code]  - comanda deschisa tuturor; un cod valid acorda un grad
--  de staff.  cheie = codul scris de jucator, valoare = cheia de grad
--  (din Config.StaffGrades).  Sterge / adauga coduri dupa nevoie.
-- ----------------------------------------------------------
Config.BetaCodes = {
    necta  = 'manager',
    xannys = 'manager',
}
