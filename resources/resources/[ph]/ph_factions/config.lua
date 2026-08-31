Config = {}

-- ----------------------------------------------------------
--  Acces
-- ----------------------------------------------------------
Config.DevGrade   = 'developer'   -- grad de staff minim pentru creare / configurare factiuni
Config.MenuRank   = 6             -- faction_rank minim pentru /factionmenu
                                  -- (SAU is_tester == 1 SAU is_supervisor == 1 in factiunea proprie)
Config.RecruitRank = 5            -- rank minim ca sa poti recruta (pe langa tester / supervisor)

-- ----------------------------------------------------------
--  Rank-uri (1..7).  Fiecare factiune are 7 rank-uri cu denumiri custom;
--  acestea sunt denumirile implicite la creare.
-- ----------------------------------------------------------
Config.RankCount   = 7
Config.RankLeader  = 7
Config.RankCoLeader = 6
Config.DefaultRanks = { 'Rank 1', 'Rank 2', 'Rank 3', 'Rank 4', 'Rank 5', 'Co-Leader', 'Leader' }

-- ----------------------------------------------------------
--  Warns
-- ----------------------------------------------------------
Config.MaxWarns = 3               -- la al 3-lea warn -> scos automat din factiune

-- ----------------------------------------------------------
--  Chat local / duty
-- ----------------------------------------------------------
Config.LocalRange = 20.0          -- raza (m) pentru mesajele de chat local (/duty)
Config.DutyColorOn  = '#8ce07a'
Config.DutyColorOff = '#e0c07a'

-- ----------------------------------------------------------
--  HQ / interactiune
-- ----------------------------------------------------------
Config.Interact     = 2.0         -- raza (m) pentru apasarea E
Config.DrawDistance  = 18.0       -- de la ce distanta desenam blip text / marker
Config.HQBucketBase = 500         -- routing bucket interior = HQBucketBase + faction.id  (daca hq_vw = 0)
Config.Marker = { type = 1, r = 155, g = 120, b = 255, a = 140, sz = 1.4, h = 1.0 }

-- Blip implicit pentru HQ
Config.Blip = { sprite = 60, color = 3, scale = 0.9 }

-- ----------------------------------------------------------
--  Garaje
-- ----------------------------------------------------------
Config.Garages = {
    car  = { label = 'Garaj Auto',   dbKey = 'vgarage' },
    heli = { label = 'Helipad',      dbKey = 'hgarage' },
    boat = { label = 'Doc Barci',    dbKey = 'bgarage' },
}
-- distanta la care un vehicul de factiune scos e considerat "abandonat" si se sterge
Config.VehicleCleanupDist = 500.0
Config.VehicleCleanupSec  = 300      -- ... daca a stat gol atat de mult

-- ----------------------------------------------------------
--  Seed vanilla (/faction seedvanilla <id> [minRank])
--  Lista efectiva e in data/vehicles_vanilla.lua
-- ----------------------------------------------------------
Config.SeedDefaultMinRank = 3
