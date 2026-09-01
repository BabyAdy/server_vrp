-- ==========================================================
--  ph_vehicles / server
--
--  Vehicule personale.  Totul se cheiaza pe SQL id (users.id).
--    users.slots            -> cate vehicule poate detine un jucator
--    player_vehicles        -> vehiculele detinute
--
--  Live state (in memorie): LIVE[vehId] = {
--      ownerId, model, label, plate, netId, spawnedBy(src),
--      engine=bool, locked=bool, keys={[userId]=true}, lastOcc=os.time(),
--      fuel=0..100, odoStart=metri
--  }
--
--  Comenzile ( /v /park /givekey /throwkey /givecar /setvehslots /delcar )
--  sunt in commands.lua si folosesc tabelul global VEHENV.
-- ==========================================================
local PH  = 'ph-core'
local RES = GetCurrentResourceName()
local ready = false

local OWNED = {}   -- [userId] = { [vehId] = row }
local LIVE  = {}   -- [vehId]  = { ... }  (vezi antet)
local S2U   = {}   -- [src]    = userId   (cache local pentru playerDropped)

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function enc(t) return t and json.encode(t) or nil end
local function dec(s)
    if type(s) ~= 'string' or s == '' or s == 'null' then return nil end
    local ok, v = pcall(json.decode, s)
    return ok and v or nil
end

local function uidOf(src)
    if S2U[src] then return S2U[src] end
    local ok, id = pcall(function()
        local v = exports[PH]:SourceToUserId(src)
        if v then return v end
        local c = exports[PH]:GetCharacter(src)
        return c and c.id or nil
    end)
    if ok and id then S2U[src] = id return id end
    return nil
end

local function srcOf(userId)
    local ok, s = pcall(function() return exports[PH]:GetSource(userId) end)
    return (ok and s) or nil
end

--- feedback marunt -> notificare deasupra minimapului
local function notify(src, text, kind)
    if not src or src == 0 then print('[ph_vehicles] ' .. tostring(text)) return end
    exports[PH]:Notify(src, text, kind or 'info')
end

--- lucru important -> mesaj in chat
local function chat(src, text, color)
    if not src or src == 0 then print('[ph_vehicles] ' .. tostring(text)) return end
    exports[PH]:Msg(src, text, color)
end

--- numele RP al unui jucator online
local function rpName(src)
    local ok, ch = pcall(function() return exports[PH]:GetCharacter(src) end)
    if ok and type(ch) == 'table' and ch.username then return ch.username end
    return GetPlayerName(src) or ('Player_' .. tostring(src))
end

local function catalogHas(model)   return exports[RES]:Has(model) end
local function catalogLabel(model) return exports[RES]:Label(model) end
local function catalogCat(model)   return exports[RES]:Category(model) end

--- mesaj local (raza EngineMsgRange) in jurul unui jucator
local function announceLocal(src, text, color)
    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local c = GetEntityCoords(ped)
    local bucket = GetPlayerRoutingBucket(src)
    for _, sid in ipairs(GetPlayers()) do
        sid = tonumber(sid)
        local tped = GetPlayerPed(sid)
        if tped and tped ~= 0 and GetPlayerRoutingBucket(sid) == bucket then
            if #(GetEntityCoords(tped) - c) <= Config.EngineMsgRange then
                chat(sid, text, color)
            end
        end
    end
end

-- ----------------------------------------------------------
--  DB init / migratie
-- ----------------------------------------------------------
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    while GetResourceState(PH) ~= 'started' do Wait(200) end

    local ok = pcall(function()
        MySQL.query.await(([[
            ALTER TABLE `users`
              ADD COLUMN IF NOT EXISTS `slots` TINYINT UNSIGNED NOT NULL DEFAULT %d
        ]]):format(Config.DefaultSlots))
    end)
    if not ok then
        pcall(function()
            local has = MySQL.scalar.await([[
                SELECT COUNT(*) FROM information_schema.columns
                WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'slots']])
            if (tonumber(has) or 0) == 0 then
                MySQL.query.await('ALTER TABLE `users` ADD COLUMN `slots` TINYINT UNSIGNED NOT NULL DEFAULT ' .. Config.DefaultSlots)
            end
        end)
    end

    local ok2, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `player_vehicles` (
              `id`         INT UNSIGNED     NOT NULL AUTO_INCREMENT,
              `owner_id`   INT UNSIGNED     NOT NULL,
              `model`      VARCHAR(64)      NOT NULL,
              `label`      VARCHAR(64)      NOT NULL,
              `category`   ENUM('car','heli','boat') NOT NULL DEFAULT 'car',
              `plate`      VARCHAR(8)       NOT NULL DEFAULT '',
              `props`      LONGTEXT         NULL DEFAULT NULL,
              `odometer`   BIGINT UNSIGNED  NOT NULL DEFAULT 0,
              `fuel`       FLOAT            NOT NULL DEFAULT 100,
              `park`       LONGTEXT         NULL DEFAULT NULL,
              `last_pos`   LONGTEXT         NULL DEFAULT NULL,
              `created_at` TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
              PRIMARY KEY (`id`), KEY `idx_pv_owner` (`owner_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])
    end)
    if not ok2 then print('^1[ph_vehicles] init DB:^7 ' .. tostring(err)) return end

    ready = true
    print('^5[ph_vehicles]^7 ready (personal vehicles).')
end)

-- ----------------------------------------------------------
--  Incarcare / cache
-- ----------------------------------------------------------
local function loadOwned(userId)
    local rows = MySQL.query.await('SELECT * FROM player_vehicles WHERE owner_id = ? ORDER BY id', { userId }) or {}
    local t = {}
    for _, r in ipairs(rows) do t[r.id] = r end
    OWNED[userId] = t
    return t
end

local function ownedOf(userId)
    return OWNED[userId] or loadOwned(userId)
end

local function getSlots(userId)
    local n = MySQL.scalar.await('SELECT slots FROM users WHERE id = ?', { userId })
    return math.max(Config.DefaultSlots, math.min(Config.MaxSlots, tonumber(n) or Config.DefaultSlots))
end

local function setSlots(userId, n)
    n = math.max(Config.DefaultSlots, math.min(Config.MaxSlots, math.floor(tonumber(n) or Config.DefaultSlots)))
    local aff = MySQL.update.await('UPDATE users SET slots = ? WHERE id = ?', { n, userId })
    return (aff and aff > 0) and n or nil
end

local function countOwned(userId)
    local t = ownedOf(userId)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- ----------------------------------------------------------
--  Chei: ce vehicule are un jucator drept de folosinta
-- ----------------------------------------------------------
local function keyIdsFor(userId)
    local t = {}
    for id, L in pairs(LIVE) do
        if L.keys[userId] then t[#t + 1] = id end
    end
    return t
end

local function pushKeys(src)
    local uid = uidOf(src)
    if not uid then return end
    TriggerClientEvent('ph_vehicles:cl:keys', src, keyIdsFor(uid))
end

local function pushKeysToUser(userId)
    local s = srcOf(userId)
    if s then TriggerClientEvent('ph_vehicles:cl:keys', s, keyIdsFor(userId)) end
end

-- ----------------------------------------------------------
--  Lista pentru /v
-- ----------------------------------------------------------
local function buildList(userId)
    local out = {}
    local t = ownedOf(userId)
    for id, r in pairs(t) do
        local L = LIVE[id]
        local odoM = L and (L.odoLast or L.odoStart) or tonumber(r.odometer) or 0
        out[#out + 1] = {
            id       = id,
            model    = r.model,
            label    = r.label,
            category = r.category or 'car',
            plate    = r.plate ~= '' and r.plate or ('PH%05d'):format(id % 100000),
            odoKm    = math.floor(odoM / 100) / 10,
            fuel     = math.floor(tonumber(L and L.fuel or r.fuel) or 100),
            spawned  = L ~= nil,
            hasPark  = r.park ~= nil and r.park ~= '',
            hasLast  = r.last_pos ~= nil and r.last_pos ~= '',
        }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function sendList(src)
    local uid = uidOf(src)
    if not uid then return end
    if not ready then return notify(src, 'Vehicle system is still starting, try again in a moment.', 'error') end
    TriggerClientEvent('ph_vehicles:cl:openMenu', src, {
        list   = buildList(uid),
        slots  = getSlots(uid),
        used   = countOwned(uid),
        imgDir = Config.ImgDir,
    })
end

-- ----------------------------------------------------------
--  Spawn / despawn
-- ----------------------------------------------------------
--- @param coords {x,y,z,h|heading}
local function doSpawn(src, userId, row, coords, reason)
    if LIVE[row.id] then return false, 'already spawned' end
    if not coords or not coords.x then return false, 'no coords' end

    local L = {
        ownerId   = userId,
        model     = row.model,
        label     = row.label,
        plate     = row.plate ~= '' and row.plate or ('PH%05d'):format(row.id % 100000),
        netId     = nil,
        spawnedBy = src,
        engine    = false,
        locked    = true,
        keys      = { [userId] = true },
        lastOcc   = os.time(),
        fuel      = math.max(0, math.min(100, tonumber(row.fuel) or 100)),
        odoStart  = tonumber(row.odometer) or 0,
        pending   = true,
    }
    LIVE[row.id] = L
    pushKeys(src)   -- cheile inainte de spawn, ca lacatul de sofer sa nu-l dea afara pe owner

    TriggerClientEvent('ph_vehicles:cl:spawn', src, {
        id     = row.id,
        model  = row.model,
        label  = row.label,
        plate  = L.plate,
        x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0,
        h = (coords.h or coords.heading or 0.0) + 0.0,
        props  = dec(row.props),
        fuel   = L.fuel,
        odo    = L.odoStart,
        locked = true,
        ownerId = userId,
    })

    -- daca clientul nu confirma crearea, curata dupa 12s
    SetTimeout(12000, function()
        if LIVE[row.id] and LIVE[row.id].pending then
            LIVE[row.id] = nil
        end
    end)
    return true
end

local function persistVeh(id, L)
    local row = OWNED[L.ownerId] and OWNED[L.ownerId][id]
    local odo = L.odoLast or L.odoStart
    MySQL.update('UPDATE player_vehicles SET fuel = ?, odometer = GREATEST(odometer, ?) WHERE id = ?',
        { math.floor((L.fuel or 100) * 100) / 100, math.floor(odo), id })
    if row then
        row.fuel = L.fuel or row.fuel
        row.odometer = math.max(tonumber(row.odometer) or 0, math.floor(odo))
    end
end

local function doDespawn(id, reason, clearLast)
    id = tonumber(id)
    local L = id and LIVE[id]
    if not L then return end
    persistVeh(id, L)

    if L.netId then
        local ent = NetworkGetEntityFromNetworkId(L.netId)
        if ent and ent ~= 0 and DoesEntityExist(ent) then
            DeleteEntity(ent)
        end
    end
    TriggerClientEvent('ph_vehicles:cl:despawn', -1, id)

    if clearLast then
        MySQL.update('UPDATE player_vehicles SET last_pos = NULL WHERE id = ?', { id })
        if OWNED[L.ownerId] and OWNED[L.ownerId][id] then OWNED[L.ownerId][id].last_pos = nil end
    end

    local holders = {}
    for kuid in pairs(L.keys) do holders[#holders + 1] = kuid end
    LIVE[id] = nil
    for _, kuid in ipairs(holders) do pushKeysToUser(kuid) end
end

-- ----------------------------------------------------------
--  Client: vehiculul a fost creat
-- ----------------------------------------------------------
RegisterNetEvent('ph_vehicles:sv:spawned', function(id, netId)
    local src = source
    id = tonumber(id)
    local L = id and LIVE[id]
    if not L or L.spawnedBy ~= src then return end
    if not netId or netId == 0 then
        LIVE[id] = nil
        return notify(src, 'Could not spawn the vehicle (invalid model?).', 'error')
    end
    L.netId = netId
    L.pending = nil
    L.lastOcc = os.time()
    notify(src, ('%s spawned.'):format(L.label), 'success')
end)

-- ----------------------------------------------------------
--  Client: raport periodic (ocupare / combustibil / km / ultima pozitie)
-- ----------------------------------------------------------
RegisterNetEvent('ph_vehicles:sv:report', function(p)
    local src = source
    p = p or {}
    local id = tonumber(p.id)
    local L = id and LIVE[id]
    if not L then return end

    if p.occupied then L.lastOcc = os.time() end
    if type(p.fuel) == 'number' then L.fuel = math.max(0, math.min(100, p.fuel)) end
    if type(p.odo) == 'number' then L.odoLast = math.max(L.odoStart or 0, math.floor(p.odo)) end

    if type(p.lastPos) == 'table' and p.lastPos.x then
        local pos = { x = p.lastPos.x, y = p.lastPos.y, z = p.lastPos.z, h = p.lastPos.h or 0.0 }
        MySQL.update('UPDATE player_vehicles SET last_pos = ? WHERE id = ?', { enc(pos), id })
        if OWNED[L.ownerId] and OWNED[L.ownerId][id] then OWNED[L.ownerId][id].last_pos = enc(pos) end
    end
    if p.flush then persistVeh(id, L) end
end)

RegisterNetEvent('ph_vehicles:sv:destroyed', function(id)
    local L = LIVE[tonumber(id) or -1]
    if not L then return end
    local osrc = srcOf(L.ownerId)
    local label = L.label
    doDespawn(id, 'destroyed', true)
    if osrc then chat(osrc, ('Your %s was destroyed.'):format(label), '#e07a7a') end
end)

-- ----------------------------------------------------------
--  Actiuni din meniul /v
-- ----------------------------------------------------------
RegisterNetEvent('ph_vehicles:sv:action', function(p)
    local src = source
    local uid = uidOf(src)
    if not uid then return end
    p = p or {}
    local id = tonumber(p.id)
    local row = id and ownedOf(uid)[id]
    if not row then return notify(src, 'That vehicle is not yours.', 'error') end
    local op = p.op
    local L = LIVE[id]

    if op == 'spawn' then
        if L then return notify(src, 'That vehicle is already out.', 'warning') end
        local pk = dec(row.park)
        if not pk then return notify(src, 'No park spot set. Sit in the car (engine off) and use /park first.', 'error') end
        doSpawn(src, uid, row, pk, 'park')

    elseif op == 'spawnLast' then
        if L then return notify(src, 'That vehicle is already out.', 'warning') end
        local lp = dec(row.last_pos)
        if not lp then return notify(src, 'No last location stored for this vehicle.', 'error') end
        doSpawn(src, uid, row, lp, 'last')

    elseif op == 'despawn' then
        if not L then return notify(src, 'That vehicle is not spawned.', 'warning') end
        doDespawn(id, 'despawn')
        notify(src, ('%s stored.'):format(row.label), 'success')

    elseif op == 'locate' then
        if not L or not L.netId then return notify(src, 'That vehicle is not spawned.', 'warning') end
        local ent = NetworkGetEntityFromNetworkId(L.netId)
        if not ent or ent == 0 or not DoesEntityExist(ent) then
            return notify(src, 'Vehicle position is unavailable right now.', 'error')
        end
        local c = GetEntityCoords(ent)
        TriggerClientEvent('ph_vehicles:cl:waypoint', src, { x = c.x, y = c.y, z = c.z }, row.label)
        notify(src, ('Marked %s on your GPS.'):format(row.label), 'info')

    elseif op == 'unstuck' then
        if not L then return notify(src, 'That vehicle is not spawned.', 'warning') end
        local ped = GetPlayerPed(src)
        local pc = ped ~= 0 and GetEntityCoords(ped) or vector3(0, 0, 0)
        local best, bestD
        for _, pk in ipairs(Config.Parkings) do
            local d = #(pc - vector3(pk.x, pk.y, pk.z))
            if not bestD or d < bestD then bestD, best = d, pk end
        end
        if not best then return notify(src, 'No parking configured.', 'error') end
        doDespawn(id, 'unstuck')
        SetTimeout(400, function()
            local fresh = ownedOf(uid)[id]
            if fresh and not LIVE[id] then
                doSpawn(src, uid, fresh, best, 'unstuck')
                TriggerClientEvent('ph_vehicles:cl:waypoint', src, { x = best.x, y = best.y, z = best.z }, row.label)
                notify(src, ('%s moved to the nearest parking.'):format(row.label), 'success')
            end
        end)
    end

    -- reimprospateaza meniul daca inca e deschis
    SetTimeout(500, function()
        local s = srcOf(uid)
        if s then TriggerClientEvent('ph_vehicles:cl:refresh', s, { list = buildList(uid), slots = getSlots(uid), used = countOwned(uid) }) end
    end)
end)

-- ----------------------------------------------------------
--  Motor (tasta 2) / incuietoare (tasta L)
-- ----------------------------------------------------------
RegisterNetEvent('ph_vehicles:sv:engine', function(id)
    local src = source
    local uid = uidOf(src)
    local L = LIVE[tonumber(id) or -1]
    if not L or not uid or not L.keys[uid] then return end

    local turningOn = not L.engine
    if turningOn and Config.Fuel.enabled and (L.fuel or 0) <= Config.Fuel.reserve then
        return notify(src, 'The tank is empty.', 'error')
    end
    L.engine = turningOn
    TriggerClientEvent('ph_vehicles:cl:engine', -1, id, L.engine)
    announceLocal(src, ('%s %s engine (%s).'):format(
        rpName(src), L.engine and 'started' or 'stopped', L.label), '#cdb8ff')
end)

RegisterNetEvent('ph_vehicles:sv:lock', function(id)
    local src = source
    local uid = uidOf(src)
    local L = LIVE[tonumber(id) or -1]
    if not L or not uid or not L.keys[uid] then return end
    L.locked = not L.locked
    TriggerClientEvent('ph_vehicles:cl:lock', -1, id, L.locked)
    notify(src, L.locked and ('%s locked.'):format(L.label) or ('%s unlocked.'):format(L.label),
        L.locked and 'info' or 'success')
end)

-- ----------------------------------------------------------
--  /park  (validat pe client, persistat aici)
-- ----------------------------------------------------------
RegisterNetEvent('ph_vehicles:sv:parkSet', function(p)
    local src = source
    local uid = uidOf(src)
    if not uid then return end
    p = p or {}
    local id = tonumber(p.id)
    local row = id and ownedOf(uid)[id]
    if not row then return notify(src, 'That vehicle is not yours.', 'error') end
    local pos = { x = p.x, y = p.y, z = p.z, h = p.h or 0.0 }
    MySQL.update('UPDATE player_vehicles SET park = ? WHERE id = ?', { enc(pos), id })
    row.park = enc(pos)
    chat(src, ('Park spot for %s saved at your current position.'):format(row.label), '#8ce07a')
end)

-- ----------------------------------------------------------
--  /givekey  (query pe client -> validare aici)
-- ----------------------------------------------------------
RegisterNetEvent('ph_vehicles:sv:giveKey', function(p)
    local src = source
    local uid = uidOf(src)
    if not uid then return end
    p = p or {}
    local id = tonumber(p.id)
    local targetUid = tonumber(p.targetUid)
    local L = id and LIVE[id]
    if not L then return notify(src, 'You must be sitting in your vehicle.', 'error') end
    if L.ownerId ~= uid then return notify(src, 'You can only hand out keys to your own vehicle.', 'error') end
    if not targetUid or targetUid == uid then return notify(src, 'Invalid target id.', 'error') end

    local tsrc = srcOf(targetUid)
    if not tsrc then return notify(src, ('Player #%d is not online.'):format(targetUid), 'error') end

    local pped, tped = GetPlayerPed(src), GetPlayerPed(tsrc)
    if pped == 0 or tped == 0 or #(GetEntityCoords(pped) - GetEntityCoords(tped)) > Config.KeyRadius then
        return notify(src, ('Player must be within %dm.'):format(math.floor(Config.KeyRadius)), 'error')
    end

    L.keys[targetUid] = true
    pushKeysToUser(targetUid)
    chat(src, ('You gave %s keys to %s.'):format(rpName(tsrc), L.label), '#8ce07a')
    chat(tsrc, ('%s gave you keys to their %s.'):format(rpName(src), L.label), '#8ce07a')
end)

local function throwKeys(src)
    local uid = uidOf(src)
    if not uid then return end
    local n = 0
    for _, L in pairs(LIVE) do
        if L.keys[uid] and L.ownerId ~= uid then L.keys[uid] = nil n = n + 1 end
    end
    pushKeys(src)
    if n > 0 then notify(src, 'You gave up the borrowed keys.', 'info')
    else notify(src, 'You are not holding anyone else\'s keys.', 'warning') end
end

-- ----------------------------------------------------------
--  Grant / remove (folosite de comenzi admin si de alte resurse)
-- ----------------------------------------------------------
local function grantVehicle(ownerUserId, model, opts)
    ownerUserId = tonumber(ownerUserId)
    model = tostring(model or ''):lower():gsub('%s', '')
    if not ownerUserId then return nil, 'bad owner id' end
    if not MySQL.scalar.await('SELECT id FROM users WHERE id = ?', { ownerUserId }) then return nil, 'no such user' end
    if not catalogHas(model) then return nil, 'unknown model' end
    opts = opts or {}

    local used = countOwned(ownerUserId)
    local slots = getSlots(ownerUserId)
    if used >= slots and not opts.force then return nil, ('no free slot (%d/%d)'):format(used, slots) end

    local label = tostring(opts.label or catalogLabel(model)):sub(1, 64)
    local cat   = opts.category or catalogCat(model) or 'car'
    if cat ~= 'car' and cat ~= 'heli' and cat ~= 'boat' then cat = 'car' end

    local id = MySQL.insert.await(
        'INSERT INTO player_vehicles (owner_id, model, label, category, plate, props, fuel) VALUES (?,?,?,?,?,?,100)',
        { ownerUserId, model, label, cat, '', enc(opts.props) })
    if not id then return nil, 'insert failed' end
    local plate = tostring(opts.plate or ('PH%05d'):format(id % 100000)):upper():sub(1, 8)
    MySQL.update.await('UPDATE player_vehicles SET plate = ? WHERE id = ?', { plate, id })

    if OWNED[ownerUserId] then
        OWNED[ownerUserId][id] = MySQL.single.await('SELECT * FROM player_vehicles WHERE id = ?', { id })
    end
    local s = srcOf(ownerUserId)
    if s then chat(s, ('You received a personal vehicle: %s (plate %s).'):format(label, plate), '#8ce07a') end
    return id
end

local function removeVehicle(vehId)
    vehId = tonumber(vehId)
    if not vehId then return false end
    if LIVE[vehId] then doDespawn(vehId, 'removed') end
    local row = MySQL.single.await('SELECT owner_id FROM player_vehicles WHERE id = ?', { vehId })
    MySQL.query.await('DELETE FROM player_vehicles WHERE id = ?', { vehId })
    if row and OWNED[row.owner_id] then OWNED[row.owner_id][vehId] = nil end
    return true
end

-- ----------------------------------------------------------
--  Auto-despawn (vehicul gol dupa Config.DespawnMinutes)
-- ----------------------------------------------------------
CreateThread(function()
    while true do
        Wait(Config.SweepSec * 1000)
        local now = os.time()
        local cutoff = Config.DespawnMinutes * 60
        for id, L in pairs(LIVE) do
            if not L.pending and (now - (L.lastOcc or now)) >= cutoff then
                local osrc = srcOf(L.ownerId)
                doDespawn(id, 'timeout')
                if osrc then notify(osrc, ('%s was stored (left empty for %d min).'):format(L.label, Config.DespawnMinutes), 'info') end
            end
        end
    end
end)

-- ----------------------------------------------------------
--  Ciclu de viata
-- ----------------------------------------------------------
AddEventHandler('ph-core:playerLoaded', function(src, char)
    if not (char and char.id) then return end
    S2U[src] = char.id
    local waited = 0
    while not ready and waited < 15000 do Wait(200) waited = waited + 200 end
    loadOwned(char.id)
    pushKeys(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local uid = S2U[src]
    S2U[src] = nil
    if not uid then return end

    -- cheile imprumutate de acest jucator devin invalide
    for _, L in pairs(LIVE) do
        if L.keys[uid] and L.ownerId ~= uid then L.keys[uid] = nil end
    end
    -- vehiculele proprii aflate in lume dispar; last_pos se sterge
    for id, L in pairs(LIVE) do
        if L.ownerId == uid then doDespawn(id, 'owner-dc', true) end
    end
    OWNED[uid] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for id, L in pairs(LIVE) do persistVeh(id, L) end
end)

-- ----------------------------------------------------------
--  Namespace pentru commands.lua
-- ----------------------------------------------------------
VEHENV = {
    PH        = PH,
    uidOf     = uidOf,
    srcOf     = srcOf,
    notify    = notify,
    chat      = chat,
    sendList  = sendList,
    throwKeys = throwKeys,
    grant     = grantVehicle,
    remove    = removeVehicle,
    getSlots  = getSlots,
    setSlots  = setSlots,
    ownedOf   = ownedOf,
    countOwned = countOwned,
    isReady   = function() return ready end,
    live      = function() return LIVE end,
}

-- ----------------------------------------------------------
--  Exports pentru alte resurse
-- ----------------------------------------------------------
exports('GrantVehicle',      function(ownerUserId, model, opts) return grantVehicle(ownerUserId, model, opts) end)
exports('RemoveVehicle',     function(vehId) return removeVehicle(vehId) end)
exports('GetPlayerVehicles', function(userId)
    local t, out = ownedOf(tonumber(userId) or -1), {}
    for id, r in pairs(t) do
        out[#out + 1] = { id = id, model = r.model, label = r.label, category = r.category,
                          plate = r.plate, spawned = LIVE[id] ~= nil }
    end
    return out
end)
exports('CountVehicles', function(userId) return countOwned(tonumber(userId) or -1) end)
exports('GetVehicleSlots', function(userId) return getSlots(tonumber(userId) or -1) end)
exports('SetVehicleSlots', function(userId, n) return setSlots(tonumber(userId) or -1, n) end)
exports('IsSpawned',       function(vehId) return LIVE[tonumber(vehId) or -1] ~= nil end)
