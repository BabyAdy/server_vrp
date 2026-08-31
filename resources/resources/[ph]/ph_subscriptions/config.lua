Config = {}

-- Cat de des verificam expirarile pentru jucatorii online (ms).
Config.CheckIntervalMs = 10000

-- ==========================================================
--  Tipuri de abonament
--  slots = cate sloturi de inventar adauga cat timp abonamentul e activ.
--  Abonamentele se pot cumula (Gold + Platinum = +75).
-- ==========================================================
Config.Tiers = {
    gold = {
        label = 'Gold',
        color = '#FCD600',
        slots = 25,
    },
    platinum = {
        label = 'Platinum',
        color = '#8F00FC',
        slots = 50,
    },
}

-- Ordinea de prioritate pentru "tier-ul afisat" (ex: la /pc alege primul activ).
Config.TierPriority = { 'platinum', 'gold' }

-- Cheia numerica a duratei implicite la crearea randului (0 = inactiv).
-- (default cerut: 0 days, 0 hours, 0 minutes, 0 seconds)
Config.DefaultSeconds = 0
