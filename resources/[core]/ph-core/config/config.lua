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
