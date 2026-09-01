-- ==========================================================
--  ph_clans / config  (shared)
--  Sistemul de clanuri.  Faza 1: chat, ranguri, permisiuni, safebox,
--  tag-uri, MOTD, expirare pe zile, unelte de staff.
--  Faza 2 (mai tarziu): meniul /clan (NUI) + vehiculele de clan.
-- ==========================================================
Config = Config or {}

Config.RankCount    = 7
Config.RankLeader   = 7          -- clan_rank 7
Config.RankCoLeader = 6          -- clan_rank 6 (are acces la "Manage")
Config.InviteRank   = 5          -- /cinvite, /cvr : clan_rank >= 5 (sau permisiune)
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
