PH = PH or {}
PH.Players = PH.Players or {}
PH.Public = PH.Public or {}   -- [src] = { src, id, name, staff, staffLabel, staffColor, badges }

-- ----------------------------------------------------------
--  Construieste intrarea publica pentru un jucator
-- ----------------------------------------------------------
local function buildEntry(src)
    local player = PH.Players[src]
    local char = player and player.character
    if not char then return nil end

    local g = Config.StaffGrades[char.staff or '']
    return {
        src        = src,
        id         = char.id,
        name       = char.username,
        staff      = char.staff or '',
        staffLabel = g and g.label or nil,
        staffColor = g and g.color or nil,
        badges     = char.badges or {},
    }
end

--- Recalculeaza si difuzeaza intrarea publica a unui jucator
function PH.PushPublic(src)
    local e = buildEntry(src)
    if not e then return end
    PH.Public[src] = e
    TriggerClientEvent('ph-core:public:set', -1, src, e)
end

-- ----------------------------------------------------------
--  Sincronizare
-- ----------------------------------------------------------
AddEventHandler('ph-core:playerLoaded', function(src)
    PH.PushPublic(src)
    TriggerClientEvent('ph-core:public:sync', src, PH.Public)  -- roster complet -> noul jucator
    TriggerClientEvent('chat:addSuggestion', src, '/getbeta', 'Redeem a beta code', { { name = 'code' } })
end)

AddEventHandler('playerDropped', function()
    local src = source
    if PH.Public[src] then
        PH.Public[src] = nil
        TriggerClientEvent('ph-core:public:remove', -1, src)
    end
end)

RegisterNetEvent('ph-core:public:request', function()
    TriggerClientEvent('ph-core:public:sync', source, PH.Public)
end)

-- ----------------------------------------------------------
--  Exports
-- ----------------------------------------------------------
exports('GetPublicPlayers', function()
    return PH.Public
end)

exports('GetPublicPlayer', function(src)
    return PH.Public[src]
end)

--- Seteaza gradul de staff (persistent). grade = '' pentru a scoate.
exports('SetStaff', function(src, grade)
    local player = PH.Players[src]
    if not player or not player.character then return false end
    grade = grade or ''
    if grade ~= '' and not Config.StaffGrades[grade] then return false end

    player.character.staff = grade
    MySQL.update.await('UPDATE users SET staff = ? WHERE id = ?', { grade, player.character.id })
    PH.PushPublic(src)
    return true
end)

--- Seteaza badge-urile afisate (lista de { text = '...', color = '#rrggbb' }); nepersistent deocamdata.
exports('SetBadges', function(src, badges)
    local player = PH.Players[src]
    if not player or not player.character then return false end
    player.character.badges = badges or {}
    PH.PushPublic(src)
    return true
end)

exports('GetStaffGrade', function(key)
    return Config.StaffGrades[key or '']
end)

exports('GetStaffGrades', function()
    return Config.StaffGrades
end)

-- ----------------------------------------------------------
--  Rang de staff (Config.StaffOrder: 1 = cel mai mic ... N = cel mai mare)
-- ----------------------------------------------------------
local function staffRankIndex(key)
    if not key or key == '' then return 0 end
    for i, k in ipairs(Config.StaffOrder) do
        if k == key then return i end
    end
    return 0
end
PH.StaffRankIndex = staffRankIndex

--- Indexul de rang al unui jucator (0 = fara staff)
exports('GetStaffRank', function(src)
    local p = PH.Players[src]
    return p and p.character and staffRankIndex(p.character.staff) or 0
end)

--- Indexul de rang al unei chei de grad (ex: 'manager') ; 0 daca nu exista
exports('StaffRankOf', function(key)
    return staffRankIndex(key)
end)

--- true daca jucatorul are cel putin gradul `minKey` (ex: 'trialhelper')
exports('HasStaffRank', function(src, minKey)
    local p = PH.Players[src]
    if not p or not p.character then return false end
    local need = staffRankIndex(minKey)
    if need == 0 then return false end
    return staffRankIndex(p.character.staff) >= need
end)

-- ----------------------------------------------------------
--  Comanda de test / administrare de baza
-- ----------------------------------------------------------
--  Argumentul <sqlId> este `users.id`, NU server id-ul de sesiune.
--  Merge si pe jucatori offline (scrie direct in DB).
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
--  /staffmenu - disponibil pentru staff >= trialhelper
-- ----------------------------------------------------------
local function notify(src, text, color)
    if GetResourceState('ph_chat') == 'started' then
        exports['ph_chat']:send(src, { text = text, textColor = color or '#e8e6f0' })
    else
        TriggerClientEvent('chat:addMessage', src, { args = { text } })
    end
end

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

RegisterCommand('staffmenu', function(src)
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
    })
end, false)
