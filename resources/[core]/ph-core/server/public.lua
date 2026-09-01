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
--  Economie: ajusteaza money / bank / premiumpoints dupa SQL id.
--    delta pozitiv = adauga ; negativ = scade (plafonat la 0).
--    Merge si offline (scrie direct in DB).
--    @return { value = nou, old = vechi, delta = nou-vechi } | nil daca userul nu exista
-- ----------------------------------------------------------
local ECON_FIELDS = { money = true, bank = true, premiumpoints = true }

exports('AdjustBalance', function(userId, field, delta)
    userId = tonumber(userId)
    delta  = math.floor(tonumber(delta) or 0)
    if not userId or not ECON_FIELDS[field] then return nil end

    local tsrc   = PH.Session.SourceOf(userId)
    local player = tsrc and PH.Players[tsrc]
    if player and player.character then
        local old = math.floor(tonumber(player.character[field]) or 0)
        local new = math.max(0, old + delta)
        player.character[field] = new
        MySQL.update(('UPDATE users SET `%s` = ? WHERE id = ?'):format(field), { new, userId })
        TriggerClientEvent('ph-core:client:setData', tsrc, field, new)
        return { value = new, old = old, delta = new - old }
    end

    local row = MySQL.single.await(('SELECT `%s` AS v FROM users WHERE id = ?'):format(field), { userId })
    if not row then return nil end
    local old = math.floor(tonumber(row.v) or 0)
    local new = math.max(0, old + delta)
    MySQL.update.await(('UPDATE users SET `%s` = ? WHERE id = ?'):format(field), { new, userId })
    return { value = new, old = old, delta = new - old }
end)

