-- ==========================================================
--  ph-core / server / commands  -  TOATE comenzile / ale ph-core
--
--    /phresetchar                       (ace ph.admin / consola)
--    /setstaff    [sqlId] [grade]       (ace ph.admin / consola)
--    /removestaff [sqlId]               (ace ph.admin / consola)  -> staff = none
--    /getbeta     [code]                (oricine; cod valid = grad de staff)
--    /staffmenu                         (staff >= trialhelper)  -> tab Home
--    /tk                                (staff >= trialhelper)  -> tab Tickets
--    /stats                             (oricine; isi vede DOAR propriile date)
--
--  Helperele traiesc in server/main.lua + server/public.lua (namespace-ul PH.*);
--  `notify` e replicat aici (helper mic de chat) iar rangul de staff se ia din
--  PH.StaffRankIndex.  Se incarca DUPA main.lua/public.lua.
-- ==========================================================
local function notify(src, text, color)
    if GetResourceState('ph_chat') == 'started' then
        exports['ph_chat']:send(src, { text = text, textColor = color or '#e8e6f0' })
    else
        TriggerClientEvent('chat:addMessage', src, { args = { text } })
    end
end

local function staffRankIndex(key) return PH.StaffRankIndex(key) end

-- ----------------------------------------------------------
--  /phresetchar  - reseteaza datele de personaj si da afara (re-testare creare)
-- ----------------------------------------------------------
RegisterCommand('phresetchar', function(src)
    if not exports['ph-core']:RequireAce(src, 'ph.admin', 'admin') then return end

    local player = PH.Players[src]
    if not player then
        if src == 0 then print('[ph-core] Use this command in-game.') end
        return
    end

    MySQL.update.await([[
        UPDATE users
        SET dob = NULL, appearance = NULL, gender = 0, height = 180,
            level = 1, rp = 0, money = 500, bank = 0, playtime = 0
        WHERE id = ?
    ]], { player.userId })
    player.character = nil
    PH.Log(('Character manually reset for user %d [src %d]'):format(player.userId, src))
    DropPlayer(src, 'Your character has been reset. Reconnect to create a new one.')
end, false)

-- ----------------------------------------------------------
--  /setstaff [sqlId] [grade]   (fara grad = none).  Merge si offline (scrie in DB).
--  Argumentul <sqlId> este `users.id`, NU server id-ul de sesiune.
-- ----------------------------------------------------------
RegisterCommand('setstaff', function(src, args)
    if not exports['ph-core']:RequireAce(src, 'ph.admin', 'admin') then return end

    local userId = tonumber(args[1])
    local grade  = args[2] or ''

    if not userId then
        exports['ph-core']:CmdSyntax(src, '/setstaff [sqlId] [grade]')
        return
    end
    if grade ~= '' and not Config.StaffGrades[grade] then
        local keys = {}
        for k in pairs(Config.StaffGrades) do keys[#keys + 1] = k end
        if src == 0 then print('invalid grade. valid: ' .. table.concat(keys, ', '))
        else exports['ph-core']:CmdSyntax(src, '/setstaff [sqlId] [grade: ' .. table.concat(keys, '/') .. ']') end
        return
    end

    local tsrc = PH.Session.SourceOf(userId)
    if tsrc and PH.Players[tsrc] and PH.Players[tsrc].character then
        PH.Players[tsrc].character.staff = grade
        MySQL.update.await('UPDATE users SET staff = ? WHERE id = ?', { grade, userId })
        PH.PushPublic(tsrc)
        print(('staff for user %d (%s) set to %q'):format(
            userId, PH.Players[tsrc].character.username, grade))
        return
    end

    local aff = MySQL.update.await('UPDATE users SET staff = ? WHERE id = ?', { grade, userId })
    if aff and aff > 0 then
        print(('staff for user %d (offline) set to %q'):format(userId, grade))
    else
        print(('no user with id %d'):format(userId))
    end
end, false)

-- ----------------------------------------------------------
--  /removestaff [sqlId]  ->  staff = '' (none).  Merge si offline.
--  Echivalent cu /setstaff [sqlId] (fara grad), dar explicit.
-- ----------------------------------------------------------
RegisterCommand('removestaff', function(src, args)
    if not exports['ph-core']:RequireAce(src, 'ph.admin', 'admin') then return end

    local userId = tonumber(args[1])
    if not userId then
        exports['ph-core']:CmdSyntax(src, '/removestaff [sqlId]')
        return
    end

    local tsrc = PH.Session.SourceOf(userId)
    if tsrc and PH.Players[tsrc] and PH.Players[tsrc].character then
        PH.Players[tsrc].character.staff = ''
        MySQL.update.await('UPDATE users SET staff = ? WHERE id = ?', { '', userId })
        PH.PushPublic(tsrc)
        print(('staff for user %d (%s) removed'):format(userId, PH.Players[tsrc].character.username))
        return
    end

    local aff = MySQL.update.await('UPDATE users SET staff = ? WHERE id = ?', { '', userId })
    if aff and aff > 0 then
        print(('staff for user %d (offline) removed'):format(userId))
    else
        print(('no user with id %d'):format(userId))
    end
end, false)

-- ----------------------------------------------------------
--  /getbeta [code] - deschisa tuturor; un cod valid (Config.BetaCodes)
--  acorda gradul de staff asociat.
-- ----------------------------------------------------------
RegisterCommand('getbeta', function(src, args)
    if src == 0 then
        print('[ph-core] /getbeta is used in-game.')
        return
    end

    local player = PH.Players[src]
    if not player or not player.character then return end

    local code = tostring(args[1] or ''):lower():gsub('%s', '')
    if code == '' then
        exports['ph-core']:CmdSyntax(src, '/getbeta [code]')
        return
    end

    local grade = Config.BetaCodes and Config.BetaCodes[code]
    if not grade or not Config.StaffGrades[grade] then
        notify(src, 'ERROR: invalid beta code', '#ff4d4d')
        return
    end

    if staffRankIndex(player.character.staff) >= staffRankIndex(grade) then
        notify(src, ('You already have a staff grade of %s or higher.'):format(grade), '#e0c07a')
        return
    end

    exports['ph-core']:SetStaff(src, grade)

    local g = Config.StaffGrades[grade]
    notify(src, ('Beta code accepted. You are now %s.'):format(g and g.label or grade), '#8ce07a')
    print(('[ph-core] getbeta: user %d (%s) redeemed %q -> %s'):format(
        player.character.id, player.character.username, code, grade))
    exports['ph-core']:StaffMsg('getbeta', ('%s redeemed a beta code and is now %s.'):format(
        player.character.username, g and g.label or grade))
end, false)

-- ----------------------------------------------------------
--  /staffmenu  -> tab-ul Home    (staff >= trialhelper)
--  /tk         -> tab-ul Tickets (staff >= trialhelper)
-- ----------------------------------------------------------
local function openStaffMenu(src, tab)
    if src == 0 then
        print('[ph-core] /staffmenu is used in-game.')
        return
    end

    local player = PH.Players[src]
    if not player or not player.character
       or staffRankIndex(player.character.staff) < staffRankIndex('trialhelper') then
        exports['ph-core']:CmdPermError(src, 'trialhelper')
        return
    end

    if GetResourceState('staff_menu') ~= 'started' then
        notify(src, 'Staff menu is currently unavailable.', '#ff4d4d')
        return
    end

    local grade = Config.StaffGrades[player.character.staff]
    TriggerClientEvent('ph-core:staff:openMenu', src, {
        grade = player.character.staff,
        label = grade and grade.label or nil,
        rank = staffRankIndex(player.character.staff),
        tab  = tab or 'home',
    })
end

RegisterCommand('staffmenu', function(src) openStaffMenu(src, 'home') end, false)
RegisterCommand('tk',        function(src) openStaffMenu(src, 'tickets') end, false)

-- ----------------------------------------------------------
--  /stats  - trimite in chat, DOAR jucatorului, propriile informatii
-- ----------------------------------------------------------
local STATS_TITLE = '#b98cff'
local STATS_BODY  = '#e8e6f0'
local HELPER_GRADES = { trialhelper = true, helper = true, headhelper = true }

local function fmtMoney(n)
    n = math.floor(tonumber(n) or 0)
    local neg = n < 0
    local s = tostring(math.abs(n))
    s = s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    return (neg and '-' or '') .. s .. '$'
end

local function fmtDaysSince(dt)
    local y, mo, d, h, mi, sec = tostring(dt or ''):match('(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)')
    if not y then return '0.00' end
    local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                        hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec) })
    local dif = os.difftime(os.time(), t)
    if dif < 0 then dif = 0 end
    return ('%.2f'):format(dif / 86400)
end

local function rankLabel(ranksJson, rank)
    rank = tonumber(rank) or 0
    local ok, ranks = pcall(json.decode, ranksJson or '')
    local name = (ok and type(ranks) == 'table' and ranks[rank]) or ('Rank ' .. rank)
    return ('%s (%d)'):format(name, rank)
end

RegisterCommand('stats', function(src)
    if src == 0 then print('[ph-core] /stats is used in-game.') return end
    local player = PH.Players[src]
    if not player or not player.character then return end
    local uid = player.character.id

    local u = MySQL.single.await([[
        SELECT u.id, u.username, u.level, u.rp, u.playtime,
               u.money, u.bank, u.premiumpoints,
               u.warns, u.staff, u.staff_warns, u.leader_warns,
               u.faction, u.faction_rank, u.faction_warns, u.faction_join,
               u.clan, u.clan_rank, u.clan_warns, u.clan_join,
               f.f_name AS f_name, f.ranks AS f_ranks,
               c.c_name AS c_name, c.ranks AS c_ranks
        FROM users u
        LEFT JOIN factions f ON f.id = u.faction
        LEFT JOIN clans    c ON c.id = u.clan
        WHERE u.id = ?
    ]], { uid })
    if not u then return end

    local cap  = Config.WarnCap or 3
    local need = (Config.LevelCost((tonumber(u.level) or 1) + 1) or {}).rp or 0
    local grade = Config.StaffGrades[u.staff or ''] and Config.StaffGrades[u.staff].label or (u.staff ~= '' and u.staff or '-')
    local rIdx = staffRankIndex(u.staff)

    local function line(text, color) notify(src, text, color or STATS_BODY) end

    line(('%s - Stats'):format(u.username), STATS_TITLE)
    line(('Info: [ID: %d] | Level: %d | RP: %d/%d | Hours: %.2f | Warns: %d/%d |'):format(
        u.id, tonumber(u.level) or 1, tonumber(u.rp) or 0, need,
        (tonumber(u.playtime) or 0) / 3600, tonumber(u.warns) or 0, cap))
    line(('Economy: [Money: %s] | [Bank Money: %s] | [PP: %d] |'):format(
        fmtMoney(u.money), fmtMoney(u.bank), tonumber(u.premiumpoints) or 0))

    if (tonumber(u.faction) or 0) ~= 0 then
        line(('Faction: %s | Rank: %s | Days: %s | FW: %d/%d |'):format(
            u.f_name or ('#' .. u.faction), rankLabel(u.f_ranks, u.faction_rank),
            fmtDaysSince(u.faction_join), tonumber(u.faction_warns) or 0, cap))
    end
    if (tonumber(u.clan) or 0) ~= 0 then
        line(('Clan: %s | Rank: %s | Days: %s | CW: %d/%d |'):format(
            u.c_name or ('#' .. u.clan), rankLabel(u.c_ranks, u.clan_rank),
            fmtDaysSince(u.clan_join), tonumber(u.clan_warns) or 0, cap))
    end
    if rIdx >= staffRankIndex('trialadmin') then
        line(('Admin: [VW: %d] | [Staff: %s] | [SW: %d/%d] |'):format(
            GetPlayerRoutingBucket(src), grade, tonumber(u.staff_warns) or 0, cap))
    elseif HELPER_GRADES[u.staff or ''] then
        line(('Helper: [Staff: %s] | [SW: %d/%d] |'):format(grade, tonumber(u.staff_warns) or 0, cap))
    end
    if (tonumber(u.faction_rank) or 0) == 7 then
        line(('Leader: [LW: %d/%d]'):format(tonumber(u.leader_warns) or 0, cap))
    end
end, false)
