-- ==========================================================
--  ph_clans / config  (shared)
--  Sistemul de clanuri.  Faza 1: chat, ranguri, permisiuni, safebox,
--  tag-uri, MOTD, expirare pe zile, unelte de staff.
--  Faza 2: meniul /clan (NUI, 7 tab-uri) + vehiculele de clan.
-- ==========================================================
Config = Config or {}

-- Header-ul meniului /clan
Config.ServerName = 'Purple Havoc'
Config.MenuLogo   = 'https://i.imgur.com/eAfdBdO.png'   -- URL sau nui://... ; gol = ascuns

Config.RankCount    = 7
Config.RankLeader   = 7          -- clan_rank 7
Config.RankCoLeader = 6          -- clan_rank 6 (are acces la "Manage" + tab-ul Settings)
Config.InviteRank   = 5          -- /cinvite, /cvr, spawn vehicul : clan_rank >= 5 (sau permisiune)
Config.WarnCap      = 3

-- Nume implicite de rang (7) + culori (7).  Fiecare clan si le poate customiza.
Config.DefaultRanks = {
    'Rank 1', 'Rank 2', 'Rank 3', 'Rank 4', 'Rank 5', 'Co-Leader', 'Leader',
}
Config.DefaultRankColors = {
    '#cfc9e6', '#cfc9e6', '#cfc9e6', '#b8afd6', '#b8afd6', '#b98cff', '#b98cff',
}
Config.DefaultChatColor = '#b98cff'

-- Zile la creare + costul (trebuie sa fie egal cu ph_shop create_clan cost,
-- pentru refund la respingere).
Config.CreateDays = 30
Config.CreateCost = 500

-- Invitatii
Config.InviteRadius     = 50.0
Config.InviteTimeoutSec = 60

-- Verificarea expirarii clanurilor (minute)
Config.ExpirySweepMin = 5

-- Clan Points castigate din activitate
Config.ClanPoints = {
    tickMinutes         = 10,   -- la cate minute se acorda
    perMemberPer10Min   = 1,    -- cate CP per membru online per tick
}

-- Cheile de permisiuni (stocate CSV in users.clan_perms)
Config.Perms = { 'changerank', 'vehmgmt', 'invite', 'kick', 'warn' }

-- Stiluri de tag.  %t = tag, %s = username.  /clantag [1-6] alege indexul.
Config.TagStyles = {
    '[%t] %s',
    '%s [%t]',
    '%t. %s',
    '%s .%t',
    '%t %s',
    '%s %t',
}

-- Gradul de staff pentru /clanreq (aprobare cereri de creare)
Config.RequestGrade = 'leadadmin'
-- Gradul de staff pentru /editclan
Config.EditGrade    = 'manager'

-- ==========================================================
--  FAZA 2  -  meniul /clan  +  vehiculele de clan
-- ==========================================================

-- Cine deschide /clan (orice membru) si cine vede tab-ul Settings.
Config.MenuMinRank  = 1
Config.SettingsRank  = Config.RankCoLeader   -- 6+ : rank names/colors, chat color, MOTD, chat lock

-- Cate randuri de log arata tab-ul "Clan Logs".
Config.LogLimit     = 100

-- ---- Vehicule de clan ------------------------------------
-- Spawn / Despawn / /cvr : clan_rank >= InviteRank SAU permisiunea "vehmgmt".
-- Buy / Sell / Upgrade    : clan_rank >= RankCoLeader SAU permisiunea "vehmgmt".
Config.VehSpawnRadius = 6.0     -- cat de aproape de vehicul trebuie sa fii ca sa il "Despawn"
Config.VehDespawnMin  = 15      -- un vehicul de clan gol dispare dupa atatea minute
Config.VehMaxPerClan  = 20      -- cate vehicule poate detine un clan

-- Pret la cumparare : pretul din catalogul ph_vehicles daca e > 0, altfel
-- valoarea de mai jos, pe categorie.  Se plateste din safebox-ul `$`.
Config.VehFallbackPrice = { car = 15000, heli = 120000, boat = 40000 }

-- La "Sell" se ramburseaza acest procent din pretul curent, inapoi in safebox `$`.
Config.VehSellRefundPct = 0.5

-- Upgrade : creste nivelul de performanta (0..maxLevel).  Fiecare nivel costa
-- `costPerLevel` din safebox-ul `$` si aplica mod-urile de mai jos la spawn.
Config.VehUpgrade = { maxLevel = 4, costPerLevel = 25000 }

--- Aplica pe client mod-urile de performanta pentru un nivel de upgrade dat.
--  level 0 = stock.  Apelat din client.lua dupa CreateVehicle.
function Config.ApplyUpgradeMods(veh, level)
    level = math.max(0, math.min(Config.VehUpgrade.maxLevel, math.floor(tonumber(level) or 0)))
    SetVehicleModKit(veh, 0)
    -- 11 engine, 12 brakes, 13 transmission, 15 suspension, 18 turbo
    local val = level - 1                       -- mod index 0-based (level 1 -> mod 0)
    for _, slot in ipairs({ 11, 12, 13, 15 }) do
        SetVehicleMod(veh, slot, val >= 0 and val or -1, false)
    end
    ToggleVehicleMod(veh, 18, level >= Config.VehUpgrade.maxLevel)   -- turbo la nivel maxim
end
