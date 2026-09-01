Config = Config or {}

-- ==========================================================
--  ph_world - time & weather sync
-- ==========================================================

-- Grad minim ca sa poti rula /time si /weather
Config.StaffPerm = 'manager'

-- ----------------------------------------------------------
--  Timp
-- ----------------------------------------------------------
Config.Time = {
    -- ceasul pleaca de aici la pornirea resursei
    StartHour   = 12,
    StartMinute = 0,

    -- true  = dupa /time ceasul curge mai departe (zi/noapte natural)
    -- false = ceasul ramane fix la ora setata
    KeepRunning = true,

    -- cate secunde reale trec pentru 1 minut de joc (GTA implicit = 2.0)
    RealSecondsPerGameMinute = 2.0,

    -- server -> clienti: retrimite ora exacta la acest interval (anti-drift)
    ResyncMs = 120000,
}

-- ----------------------------------------------------------
--  Vreme
-- ----------------------------------------------------------
Config.Weather = {
    Start = 'EXTRASUNNY',

    -- secunde de tranzitie intre vremea veche si cea noua
    TransitionSec = 15,

    -- reaplicam periodic vremea ca sa nu porneasca ciclul automat din GTA
    ReassertMs = 30000,

    -- tipuri acceptate de /weather (cheile din GTA V)
    Types = {
        'EXTRASUNNY', 'CLEAR', 'NEUTRAL', 'CLOUDS', 'OVERCAST', 'SMOG', 'FOGGY',
        'RAIN', 'THUNDER', 'CLEARING', 'SNOW', 'SNOWLIGHT', 'BLIZZARD',
        'XMAS', 'HALLOWEEN',
    },
}
