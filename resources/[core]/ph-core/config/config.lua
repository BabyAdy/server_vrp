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
