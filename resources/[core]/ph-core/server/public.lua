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

-- ----------------------------------------------------------
--  Comanda de test / administrare de baza
-- ----------------------------------------------------------
RegisterCommand('setstaff', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'ph.admin') then return end

    local target = tonumber(args[1])
    local grade = args[2] or ''

    if not target then
        print('uz: setstaff <playerId> <grade|nimic pentru a scoate>')
        return
    end
    if grade ~= '' and not Config.StaffGrades[grade] then
        local keys = {}
        for k in pairs(Config.StaffGrades) do keys[#keys + 1] = k end
        print('grade invalid. valide: ' .. table.concat(keys, ', '))
        return
    end
    if not PH.Players[target] or not PH.Players[target].character then
        print('jucatorul ' .. target .. ' nu este incarcat.')
        return
    end

    PH.Players[target].character.staff = grade
    MySQL.update.await('UPDATE users SET staff = ? WHERE id = ?',
        { grade, PH.Players[target].character.id })
    PH.PushPublic(target)
    print(('staff pentru %d setat la %q'):format(target, grade))
end, false)
