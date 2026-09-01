-- ==========================================================
--  ph_vehicles / config
--  (shared - incarcat si pe server si pe client)
-- ==========================================================
Config = Config or {}

-- Sloturi de vehicule (users.slots).  Minim = valoarea implicita.
Config.DefaultSlots = 2
Config.MaxSlots     = 20

-- Auto-despawn: un vehicul personal in care nu se afla nimeni dispare dupa
-- atatea minute.
Config.DespawnMinutes = 15
Config.HeartbeatSec   = 5      -- clientul raporteaza "sunt in masina" la acest interval
Config.SweepSec       = 30     -- cat de des verifica serverul vehiculele goale

-- Raze
Config.KeyRadius      = 50.0   -- /givekey: distanta maxima pana la tinta
Config.LockRadius     = 8.0    -- tasta L functioneaza si din afara masinii, in raza asta
Config.EngineMsgRange = 22.0   -- raza pe care se vede mesajul "started/stopped engine"

-- Taste
Config.EngineControl  = 158    -- "2" din hotbar (INPUT_SELECT_WEAPON_MELEE) - pornire/oprire motor
Config.LockKey        = 'L'    -- incuiere / descuiere
Config.SeatbeltKey    = 'B'    -- centura

-- Combustibil (GTA nu are sistem nativ real; modelul de mai jos e suficient
-- pentru HUD si persistenta).  Consum exprimat per 10 secunde.
Config.Fuel = {
    enabled    = true,
    idlePer10  = 0.15,         -- la ralanti
    drivePer10 = 0.85,         -- in mers, la turatie maxima (scaleaza cu RPM)
    reserve    = 0.0,          -- sub acest % motorul nu mai porneste
}

-- Centura
Config.Seatbelt = {
    enabled      = true,
    ejectMinKmh  = 55.0,       -- viteza minima ca sa te poata arunca prin parbriz
    ejectDropKmh = 42.0,       -- scadere brusca de viteza intr-un frame = impact
    ejectDamage  = 22,         -- daune aplicate la ejectare
}

-- Parcari folosite de butonul "Unstuck" (se alege cea mai apropiata de jucator).
-- Editeaza / adauga dupa harta reala.  h = heading.
Config.Parkings = {
    { x = -56.8,   y = -1096.4, z = 26.4, h = 25.0  },   -- LS Customs (Burton)
    { x = 215.9,   y = -810.2,  z = 30.7, h = 250.0 },   -- langa Legion Square
    { x = -337.2,  y = -790.1,  z = 33.5, h = 160.0 },   -- Alta St
    { x = 1728.9,  y = 3712.0,  z = 32.2, h = 210.0 },   -- Sandy Shores
    { x = -1157.6, y = -1521.9, z = 4.4,  h = 215.0 },   -- Vespucci Beach
    { x = -805.9,  y = -2033.7, z = 9.0,  h = 55.0  },   -- LSIA
}

-- Blip temporar folosit de "Locate" / "Unstuck"
Config.Blip = { sprite = 225, color = 3, scale = 0.9 }

-- Directorul cu imaginile masinilor din meniul /v : html/img/<model>.png
-- (fallback: html/img/_default.png)
Config.ImgDir = 'img/'
