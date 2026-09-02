-- ==========================================================
--  ph_factions / server
--
--  Totul se cheiaza pe SQL id (users.id).  Apartenenta e in `users`
--  (faction / faction_rank / is_tester / is_supervisor / faction_join /
--   faction_warns).  Datele de factiune sunt in `factions` + `faction_vehicles`.
-- ==========================================================
local PH = 'ph-core'
local ready = false

FACTIONS = {}   -- [id] = { id, name, short, ranks[7], leader, leaderName, manager, managerName,
                      --          hqEnter, hqExit, hqVw, blip, vgarage, hgarage, bgarage, active,
                      --          vehicles = { car={}, heli={}, boat={} } }
MEMBER   = {}   -- [userId] = { faction, rank, tester, supervisor, warns, join }
DUTY     = {}   -- [userId] = bool
local INSIDE   = {}   -- [userId] = factionId  (in interiorul HQ)
local S2U      = {}   -- [src] = userId

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
function enc(t) return t and json.encode(t) or nil end
local function dec(s)
    if type(s) ~= 'string' or s == '' then return nil end
    local ok, v = pcall(json.decode, s)
    return ok and v or nil
end

function srcOf(userId)
    local ok, s = pcall(function() return exports[PH]:GetSource(userId) end)
    return (ok and s) or nil
end
function uidOf(src) return S2U[src] or (function()
    local ok, u = pcall(function() return exports[PH]:SourceToUserId(src) end)
    return ok and u or nil
end)() end

function notify(src, text, color)
    if not src then return end
    if src == 0 then print('^5[ph_factions]^7 ' .. tostring(text)); return end
    if GetResourceState('ph_chat') == 'started' then
        exports['ph_chat']:send(src, { text = text, textColor = color or '#e8e6f0' })
    else
        TriggerClientEvent('chat:addMessage', src, { args = { text } })
    end
end

function nameOfUser(userId)
    if not userId then return nil end
    local row = MySQL.single.await('SELECT username FROM users WHERE id = ?', { userId })
    return row and row.username or nil
end

--- numele RP (users.username) al unui jucator online, cu fallback pe numele FiveM
function rpName(src)
    local ok, ch = pcall(function() return exports[PH]:GetCharacter(src) end)
    if ok and type(ch) == 'table' and ch.username then return ch.username end
    return GetPlayerName(src) or ('Player_' .. src)
end

local function bucketOf(f)
    if not f then return 0 end
    return (f.hqVw and f.hqVw > 0) and f.hqVw or (Config.HQBucketBase + f.id)
end

function flog(fid, actor, action, targetId, targetName, detail)
    local an = actor and nameOfUser(actor) or nil
    MySQL.insert(
        'INSERT INTO faction_logs (faction_id, actor_id, actor_name, action, target_id, target_name, detail) VALUES (?,?,?,?,?,?,?)',
        { fid, actor, an, action, targetId, targetName, detail and tostring(detail):sub(1, 255) or nil })
end

-- ----------------------------------------------------------
--  DB init
-- ----------------------------------------------------------
local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `factions` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `f_name` VARCHAR(64) NOT NULL,
      `f_short` VARCHAR(12) NOT NULL DEFAULT '',
      `ranks` LONGTEXT NOT NULL,
      `leader` INT UNSIGNED NULL DEFAULT NULL,
      `manager` INT UNSIGNED NULL DEFAULT NULL,
      `hq_enter` LONGTEXT NULL DEFAULT NULL,
      `hq_exit` LONGTEXT NULL DEFAULT NULL,
      `hq_vw` INT NOT NULL DEFAULT 0,
      `blip` LONGTEXT NULL DEFAULT NULL,
      `vgarage` LONGTEXT NULL DEFAULT NULL,
      `hgarage` LONGTEXT NULL DEFAULT NULL,
      `bgarage` LONGTEXT NULL DEFAULT NULL,
      `active` TINYINT(1) NOT NULL DEFAULT 1,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), UNIQUE KEY `uq_factions_name` (`f_name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    [[CREATE TABLE IF NOT EXISTS `faction_vehicles` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `faction_id` INT UNSIGNED NOT NULL,
      `category` ENUM('car','heli','boat') NOT NULL DEFAULT 'car',
      `model` VARCHAR(64) NOT NULL,
      `label` VARCHAR(64) NOT NULL,
      `min_rank` TINYINT NOT NULL DEFAULT 1,
      `props` LONGTEXT NULL DEFAULT NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), KEY `idx_fv` (`faction_id`,`category`,`min_rank`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    [[CREATE TABLE IF NOT EXISTS `faction_logs` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `faction_id` INT UNSIGNED NOT NULL,
      `actor_id` INT UNSIGNED NULL, `actor_name` VARCHAR(24) NULL,
      `action` VARCHAR(32) NOT NULL,
      `target_id` INT UNSIGNED NULL, `target_name` VARCHAR(24) NULL,
      `detail` VARCHAR(255) NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), KEY `idx_flog` (`faction_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],
}

local function migrateUsers()
    local ok = pcall(function()
        MySQL.query.await([[
            ALTER TABLE `users`
              ADD COLUMN IF NOT EXISTS `faction`       INT UNSIGNED NOT NULL DEFAULT 0,
              ADD COLUMN IF NOT EXISTS `faction_rank`  TINYINT      NOT NULL DEFAULT 0,
              ADD COLUMN IF NOT EXISTS `is_tester`     TINYINT(1)   NOT NULL DEFAULT 0,
              ADD COLUMN IF NOT EXISTS `is_supervisor` TINYINT(1)   NOT NULL DEFAULT 0,
              ADD COLUMN IF NOT EXISTS `faction_join`  DATETIME     NULL DEFAULT NULL,
              ADD COLUMN IF NOT EXISTS `faction_warns` TINYINT      NOT NULL DEFAULT 0
        ]])
    end)
    if not ok then
        pcall(function()
            local has = MySQL.scalar.await([[
                SELECT COUNT(*) FROM information_schema.columns
                WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'faction']])
            if (tonumber(has) or 0) == 0 then
                MySQL.query.await("ALTER TABLE `users` ADD COLUMN `faction` INT UNSIGNED NOT NULL DEFAULT 0")
                MySQL.query.await("ALTER TABLE `users` ADD COLUMN `faction_rank` TINYINT NOT NULL DEFAULT 0")
                MySQL.query.await("ALTER TABLE `users` ADD COLUMN `is_tester` TINYINT(1) NOT NULL DEFAULT 0")
                MySQL.query.await("ALTER TABLE `users` ADD COLUMN `is_supervisor` TINYINT(1) NOT NULL DEFAULT 0")
                MySQL.query.await("ALTER TABLE `users` ADD COLUMN `faction_join` DATETIME NULL DEFAULT NULL")
                MySQL.query.await("ALTER TABLE `users` ADD COLUMN `faction_warns` TINYINT NOT NULL DEFAULT 0")
            end
        end)
    end
end

-- ----------------------------------------------------------
--  Incarcare factiuni in memorie
-- ----------------------------------------------------------
local function normalizeRanks(r)
    local out = {}
    for i = 1, Config.RankCount do
        out[i] = (type(r) == 'table' and type(r[i]) == 'string' and r[i] ~= '') and r[i] or Config.DefaultRanks[i]
    end
    return out
end

local function loadVehicles(fid)
    local rows = MySQL.query.await(
        'SELECT id, category, model, label, min_rank, props FROM faction_vehicles WHERE faction_id = ? ORDER BY category, min_rank, label',
        { fid }) or {}
    local out = { car = {}, heli = {}, boat = {} }
    for _, v in ipairs(rows) do
        local cat = out[v.category] and v.category or 'car'
        out[cat][#out[cat] + 1] = {
            id = v.id, model = v.model, label = v.label,
            minRank = tonumber(v.min_rank) or 1, props = dec(v.props),
        }
    end
    return out
end

local function cacheFaction(row)
    if not row then return end
    local f = {
        id       = row.id,
        name     = row.f_name,
        short    = row.f_short or '',
        ranks    = normalizeRanks(dec(row.ranks)),
        leader   = row.leader and tonumber(row.leader) or nil,
        manager  = row.manager and tonumber(row.manager) or nil,
        hqEnter  = dec(row.hq_enter),
        hqExit   = dec(row.hq_exit),
        hqVw     = tonumber(row.hq_vw) or 0,
        blip     = dec(row.blip) or Config.Blip,
        vgarage  = dec(row.vgarage),
        hgarage  = dec(row.hgarage),
        bgarage  = dec(row.bgarage),
        active   = (tonumber(row.active) or 1) ~= 0,
        vehicles = loadVehicles(row.id),
    }
    f.leaderName  = f.leader and nameOfUser(f.leader) or nil
    f.managerName = f.manager and nameOfUser(f.manager) or nil
    FACTIONS[f.id] = f
    return f
end

local function loadAllFactions()
    local rows = MySQL.query.await('SELECT * FROM factions') or {}
    FACTIONS = {}
    for _, r in ipairs(rows) do cacheFaction(r) end
end

function reloadFaction(fid)
    local row = MySQL.single.await('SELECT * FROM factions WHERE id = ?', { fid })
    if row then cacheFaction(row) else FACTIONS[fid] = nil end
end

--- adauga toata lista vanilla globala (ph_vehicles) in `faction_vehicles`.
--- @return n|nil, err
function seedVanillaInto(fid, minRank)
    if not FACTIONS[fid] then return nil, 'Faction does not exist.' end
    minRank = math.max(1, math.min(Config.RankCount, tonumber(minRank) or Config.SeedDefaultMinRank))

    local okL, vanilla = pcall(function() return exports['ph_vehicles']:List() end)
    if not okL or type(vanilla) ~= 'table' then
        return nil, 'ph_vehicles is not running / not responding.'
    end

    local n = 0
    for cat, arr in pairs(vanilla) do
        if type(arr) == 'table' and Config.Garages[cat] then
            for _, v in ipairs(arr) do
                if v.model then
                    MySQL.insert('INSERT INTO faction_vehicles (faction_id, category, model, label, min_rank) VALUES (?,?,?,?,?)',
                        { fid, cat, tostring(v.model):lower(), tostring(v.label or v.model), minRank })
                    n = n + 1
                end
            end
        end
    end
    return n
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    while GetResourceState(PH) ~= 'started' do Wait(200) end

    local ok, err = pcall(function()
        for _, q in ipairs(SCHEMA) do MySQL.query.await(q) end
    end)
    if not ok then print('^1[ph_factions] init DB:^7 ' .. tostring(err)); return end
    migrateUsers()
    loadAllFactions()
    ready = true

    local n = 0
    for _ in pairs(FACTIONS) do n = n + 1 end
    print(('^5[ph_factions]^7 ready (%d factions).'):format(n))
end)

-- ----------------------------------------------------------
--  Membru: incarcare / salvare
-- ----------------------------------------------------------
local function loadMember(userId)
    local row = MySQL.single.await(
        'SELECT faction, faction_rank, is_tester, is_supervisor, faction_warns, faction_join FROM users WHERE id = ?',
        { userId })
    local m = {
        faction    = row and tonumber(row.faction) or 0,
        rank       = row and tonumber(row.faction_rank) or 0,
        tester     = (row and tonumber(row.is_tester) or 0) ~= 0,
        supervisor = (row and tonumber(row.is_supervisor) or 0) ~= 0,
        warns      = row and tonumber(row.faction_warns) or 0,
        join       = row and row.faction_join or nil,
    }
    -- factiune inexistenta / inactiva -> curata
    if m.faction ~= 0 and not (FACTIONS[m.faction] and FACTIONS[m.faction].active) then
        m = { faction = 0, rank = 0, tester = false, supervisor = false, warns = 0, join = nil }
        MySQL.update('UPDATE users SET faction=0, faction_rank=0, is_tester=0, is_supervisor=0, faction_warns=0, faction_join=NULL WHERE id=?', { userId })
    end
    MEMBER[userId] = m
    return m
end

local function saveMember(userId)
    local m = MEMBER[userId]
    if not m then return end
    MySQL.update([[
        UPDATE users SET faction=?, faction_rank=?, is_tester=?, is_supervisor=?, faction_warns=?, faction_join=?
        WHERE id=?
    ]], {
        m.faction, m.rank, m.tester and 1 or 0, m.supervisor and 1 or 0, m.warns,
        m.join, userId,
    })
end

-- ----------------------------------------------------------
--  Push catre client
-- ----------------------------------------------------------
--- lista publica de HQ-uri (blip pe harta pentru toata lumea)
local function publicFactionList()
    local out = {}
    for id, f in pairs(FACTIONS) do
        if f.active and f.hqEnter then
            out[#out + 1] = { id = id, name = f.name, hqEnter = f.hqEnter, blip = f.blip }
        end
    end
    return out
end

function pushPublic(target)
    TriggerClientEvent('ph_factions:cl:factions', target or -1, publicFactionList())
end

--- config + apartenenta pentru un jucator anume
function pushSelf(src)
    local uid = uidOf(src)
    if not uid then return end
    local m = MEMBER[uid] or loadMember(uid)
    local f = m.faction ~= 0 and FACTIONS[m.faction] or nil
    TriggerClientEvent('ph_factions:cl:self', src, {
        faction    = m.faction,
        rank       = m.rank,
        rankName   = f and f.ranks[m.rank] or nil,
        tester     = m.tester,
        supervisor = m.supervisor,
        warns      = m.warns,
        onDuty     = DUTY[uid] == true,
        data       = f and {
            id = f.id, name = f.name, short = f.short, ranks = f.ranks,
            leaderName = f.leaderName, managerName = f.managerName,
            hqEnter = f.hqEnter, hqExit = f.hqExit,
            vgarage = f.vgarage, hgarage = f.hgarage, bgarage = f.bgarage,
        } or nil,
        marker     = Config.Marker,
        interact   = Config.Interact,
        drawDist   = Config.DrawDistance,
    })
end

--- re-trimite `self` la toti membrii online ai unei factiuni (dupa schimbari de config)
function pushFactionMembers(fid)
    for uid, mm in pairs(MEMBER) do
        if mm.faction == fid then
            local s = srcOf(uid)
            if s then pushSelf(s) end
        end
    end
end

-- ----------------------------------------------------------
--  Roluri / permisiuni in meniu
--    /factionmenu     -> faction_rank >= Config.MenuRank (verificat in openMenu)
--    /devfactionmenu  -> isDev(src)
-- ----------------------------------------------------------
local function isDev(src)
    local ok, r = pcall(function() return exports[PH]:HasStaffRank(src, Config.DevGrade) end)
    return ok and r == true
end

--- true daca src e consola (0) sau staff cu gradul >= gradeKey
function staffAtLeast(src, gradeKey)
    if src == 0 then return true end
    local ok, r = pcall(function() return exports[PH]:HasStaffRank(src, gradeKey) end)
    return ok and r == true
end

-- ----------------------------------------------------------
--  Operatii de membru
-- ----------------------------------------------------------
function announceLocal(src, text, color)
    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local c = GetEntityCoords(ped)
    local bucket = GetPlayerRoutingBucket(src)
    for _, tuid in ipairs(exports[PH]:GetOnlineUserIds() or {}) do
        local tsrc = srcOf(tuid)
        if tsrc then
            local tped = GetPlayerPed(tsrc)
            if tped ~= 0 and GetPlayerRoutingBucket(tsrc) == bucket then
                if #(GetEntityCoords(tped) - c) <= Config.LocalRange then
                    notify(tsrc, text, color)
                end
            end
        end
    end
end

function setMemberFaction(userId, fid, rank)
    local m = MEMBER[userId] or { faction = 0, rank = 0, tester = false, supervisor = false, warns = 0 }
    m.faction = fid
    m.rank = rank
    if fid == 0 then
        m.tester = false; m.supervisor = false; m.warns = 0; m.join = nil
    else
        m.join = m.join or os.date('%Y-%m-%d %H:%M:%S')
    end
    MEMBER[userId] = m
    saveMember(userId)
    local s = srcOf(userId)
    if s then pushSelf(s) end
end

--- seteaza apartenenta pentru un user ONLINE sau OFFLINE.
--- `fresh` = true -> reseteaza faction_join la acum.  Returneaza true daca userId exista.
function adminSetMembership(userId, fid, rank, fresh)
    userId = tonumber(userId)
    if not userId then return false end
    if not MySQL.scalar.await('SELECT id FROM users WHERE id = ?', { userId }) then return false end

    local s = srcOf(userId)
    if s and MEMBER[userId] then
        -- online: prin caile obisnuite (cache + push)
        if fresh and fid ~= 0 then MEMBER[userId].join = os.date('%Y-%m-%d %H:%M:%S') end
        setMemberFaction(userId, fid, rank)
    else
        -- offline: scrie direct in DB, invalideaza cache-ul
        if fid == 0 then
            MySQL.update.await([[
                UPDATE users SET faction = 0, faction_rank = 0, is_tester = 0, is_supervisor = 0,
                                 faction_warns = 0, faction_join = NULL WHERE id = ?]], { userId })
        else
            MySQL.update.await([[
                UPDATE users SET faction = ?, faction_rank = ?,
                                 faction_join = CASE WHEN ? = 1 OR faction_join IS NULL THEN NOW() ELSE faction_join END
                WHERE id = ?]], { fid, rank, fresh and 1 or 0, userId })
        end
        MEMBER[userId] = nil
    end
    return true
end

function kickMember(userId, reason, actorUid)
    local m = MEMBER[userId]
    if not m or m.faction == 0 then return end
    local fid = m.faction
    local f = FACTIONS[fid]
    local s = srcOf(userId)

    -- daca era in interiorul HQ-ului: scoate-l in lume (bucket 0 + coords intrare)
    if s and INSIDE[userId] then
        INSIDE[userId] = nil
        SetPlayerRoutingBucket(s, 0)
        TriggerClientEvent('ph_factions:cl:leaveHQ', s, f and f.hqEnter or nil)
    end

    setMemberFaction(userId, 0, 0)
    DUTY[userId] = nil
    if s then
        notify(s, ('You were removed from the faction%s.'):format(reason and (' (' .. reason .. ')') or ''), '#e07a7a')
    end
    flog(fid, actorUid, 'kick', userId, nameOfUser(userId), reason)
end

local function addWarn(fid, actorUid, targetUid, delta, reason)
    local m = MEMBER[targetUid]
    if not m or m.faction ~= fid then return false, 'Not in the faction.' end
    m.warns = math.max(0, math.min(99, (m.warns or 0) + delta))
    saveMember(targetUid)
    flog(fid, actorUid, delta > 0 and 'warn' or 'unwarn', targetUid, nameOfUser(targetUid), reason)
    local s = srcOf(targetUid)
    if s then
        notify(s, delta > 0
            and ('You received a faction warn (%d/%d)%s'):format(m.warns, Config.MaxWarns, reason and (': ' .. reason) or '')
            or  ('A faction warn was removed (%d/%d).'):format(m.warns, Config.MaxWarns),
            delta > 0 and '#e07a7a' or '#8ce07a')
    end
    if m.warns >= Config.MaxWarns then
        kickMember(targetUid, ('%d warns'):format(Config.MaxWarns))
    else
        if s then pushSelf(s) end
    end
    return true
end

-- ----------------------------------------------------------
--  Ciclu de viata
-- ----------------------------------------------------------
AddEventHandler('ph-core:playerLoaded', function(src, char)
    if not (char and char.id) then return end
    local uid = char.id
    S2U[src] = uid
    local waited = 0
    while not ready and waited < 15000 do Wait(200); waited = waited + 200 end
    if not ready then return end
    loadMember(uid)
    pushPublic(src)
    pushSelf(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local uid = S2U[src]
    S2U[src] = nil
    if uid then
        MEMBER[uid] = nil
        DUTY[uid] = nil
        INSIDE[uid] = nil
    end
end)


-- ----------------------------------------------------------
--  HQ enter / exit
-- ----------------------------------------------------------
RegisterNetEvent('ph_factions:sv:enterHQ', function(fid)
    local src = source
    local uid = uidOf(src)
    fid = tonumber(fid)
    local f = fid and FACTIONS[fid]
    local m = uid and MEMBER[uid]
    if not f or not m or m.faction ~= fid then return end
    if not f.hqExit then return notify(src, 'The HQ has no interior point set yet.', '#e07a7a') end

    local bucket = bucketOf(f)
    SetPlayerRoutingBucket(src, bucket)
    pcall(function()
        SetRoutingBucketPopulationEnabled(bucket, false)
        SetRoutingBucketEntityLockdownMode(bucket, 'relaxed')
    end)
    INSIDE[uid] = fid
    TriggerClientEvent('ph_factions:cl:enteredHQ', src, f.hqExit, fid)
end)

RegisterNetEvent('ph_factions:sv:exitHQ', function()
    local src = source
    local uid = uidOf(src)
    local fid = uid and INSIDE[uid]
    local f = fid and FACTIONS[fid]
    if not f or not f.hqEnter then return end
    SetPlayerRoutingBucket(src, 0)
    INSIDE[uid] = nil
    TriggerClientEvent('ph_factions:cl:leftHQ', src, f.hqEnter)
end)

-- ----------------------------------------------------------
--  Garaje
-- ----------------------------------------------------------
RegisterNetEvent('ph_factions:sv:openGarage', function(category)
    local src = source
    local uid = uidOf(src)
    local m = uid and MEMBER[uid]
    category = tostring(category or 'car')
    if not m or m.faction == 0 or not Config.Garages[category] then return end
    local f = FACTIONS[m.faction]
    if not f then return end
    local g = f[Config.Garages[category].dbKey]
    if not g then return notify(src, 'The garage is not configured.', '#e07a7a') end

    local list = {}
    for _, v in ipairs((f.vehicles[category] or {})) do
        if m.rank >= (v.minRank or 1) then
            list[#list + 1] = { id = v.id, model = v.model, label = v.label, minRank = v.minRank }
        end
    end
    TriggerClientEvent('ph_factions:cl:garage', src, category, list, g)
end)

RegisterNetEvent('ph_factions:sv:spawnVehicle', function(vehId, category)
    local src = source
    local uid = uidOf(src)
    local m = uid and MEMBER[uid]
    if not m or m.faction == 0 then return end
    local f = FACTIONS[m.faction]
    category = tostring(category or 'car')
    if not f or not Config.Garages[category] then return end
    local g = f[Config.Garages[category].dbKey]
    if not g then return end

    local veh
    for _, v in ipairs((f.vehicles[category] or {})) do
        if v.id == tonumber(vehId) then veh = v break end
    end
    if not veh then return end
    if m.rank < (veh.minRank or 1) then
        return notify(src, 'Your rank does not allow this vehicle.', '#e07a7a')
    end

    local spawn = { x = g.sx or g.x, y = g.sy or g.y, z = g.sz or g.z, h = g.sh or g.h or 0.0 }
    TriggerClientEvent('ph_factions:cl:spawnVehicle', src, veh.model, spawn, m.faction, veh.props)
    flog(f.id, uid, 'vehicle_out', nil, nil, ('%s (%s)'):format(veh.label, category))
end)

-- ==========================================================
--  /factionmenu  -  meniul de factiune (faction_rank >= 6)
--    Tab-uri: Members | Logs
-- ==========================================================
local function r2(n) return math.floor((tonumber(n) or 0) * 100) / 100 end

--- zile (cu 2 zecimale) de la un DATETIME "YYYY-MM-DD HH:MM:SS"
local function daysSince(dt)
    local y, mo, d, h, mi, s = tostring(dt or ''):match('(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)')
    if not y then return 0 end
    local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                        hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
    local dif = os.difftime(os.time(), t)
    if dif < 0 then dif = 0 end
    return math.floor(dif / 864) / 100
end

--- un singur badge pe rand, in ordinea prioritatii
local function memberBadge(rank, tester, supervisor)
    if rank >= Config.RankLeader then return 'leader' end
    if rank >= Config.RankCoLeader then return 'coleader' end
    if supervisor then return 'supervisor' end
    if tester then return 'tester' end
    return nil
end

local function buildMembers(fid)
    local rows = MySQL.query.await([[
        SELECT id, username, faction_rank, is_tester, is_supervisor, faction_warns, faction_join
        FROM users WHERE faction = ? ORDER BY faction_rank DESC, username ASC
    ]], { fid }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local rank = tonumber(r.faction_rank) or 0
        local tester = (tonumber(r.is_tester) or 0) ~= 0
        local sup    = (tonumber(r.is_supervisor) or 0) ~= 0
        out[#out + 1] = {
            id = r.id, name = r.username, rank = rank,
            tester = tester, supervisor = sup,
            warns = tonumber(r.faction_warns) or 0,
            days  = daysSince(r.faction_join),
            badge = memberBadge(rank, tester, sup),
            online = srcOf(r.id) ~= nil,
        }
    end
    return out
end

local function buildLogs(fid)
    local lim = math.max(1, math.min(500, math.floor(tonumber(Config.LogLimit) or 100)))
    return MySQL.query.await(
        'SELECT actor_name, action, target_name, detail, created_at FROM faction_logs '
        .. 'WHERE faction_id = ? ORDER BY id DESC LIMIT ' .. lim, { fid }) or {}
end

local function memberMenuPayload(uid, m)
    local f = FACTIONS[m.faction]
    if not f then return nil end
    return {
        role = {
            me        = uid,
            myName    = nameOfUser(uid),
            rank      = m.rank,
            rankName  = f.ranks[m.rank] or ('Rank ' .. m.rank),
            isLeader  = m.rank >= Config.RankLeader,
            canManage = m.rank >= Config.RankCoLeader,   -- rank >= 6
        },
        faction = {
            id = f.id, name = f.name, short = f.short, ranks = f.ranks,
            leaderName = f.leaderName, managerName = f.managerName,
        },
        serverName  = Config.ServerName,
        logo        = Config.MenuLogo,
        members     = buildMembers(f.id),
        logs        = buildLogs(f.id),
        badges      = Config.Badges,
        maxWarns    = Config.MaxWarns,
        rankCount   = Config.RankCount,
        rankLeader  = Config.RankLeader,
        rankCoLeader = Config.RankCoLeader,
    }
end

RegisterNetEvent('ph_factions:sv:openMenu', function()
    local src = source
    local uid = uidOf(src)
    local m = uid and MEMBER[uid]
    if not m or m.faction == 0 or m.rank < Config.MenuRank then
        return exports[PH]:CmdPermError(src, 'faction rank ' .. Config.MenuRank)
    end
    local pl = memberMenuPayload(uid, m)
    if pl then TriggerClientEvent('ph_factions:cl:openMenu', src, pl) end
end)

local function refreshMember(src, uid)
    local m = MEMBER[uid]
    if not m or m.faction == 0 then return end
    local pl = memberMenuPayload(uid, m)
    if pl then TriggerClientEvent('ph_factions:cl:menuData', src, pl) end
end

RegisterNetEvent('ph_factions:sv:menu', function(p)
    local src = source
    local uid = uidOf(src)
    local m = uid and MEMBER[uid]
    if not m or m.faction == 0 or m.rank < Config.MenuRank then return end
    p = p or {}
    local f = FACTIONS[m.faction]
    if not f then return end

    local function done(msg, kind)
        if msg then exports[PH]:Notify(src, msg, kind or 'info') end
        refreshMember(src, uid)
    end

    local op = p.op
    if op == 'refresh' then return refreshMember(src, uid) end

    local target = tonumber(p.userId)
    local tm = target and MEMBER[target]
    if not tm or tm.faction ~= f.id then
        return done('The member must be online.', 'error')
    end

    if op == 'promote' or op == 'demote' then
        -- rank up / rank down: doar Leaderul (faction_rank == 7)
        if m.rank < Config.RankLeader then return done('Leader only.', 'error') end
        if target == uid then return done('Not on yourself.', 'warning') end
        local nr = tm.rank + (op == 'promote' and 1 or -1)
        if nr < 1 then return done('Already at the lowest rank.', 'warning') end
        if nr >= Config.RankLeader then return done('Cannot set Leader here (use /setleader).', 'warning') end
        tm.rank = nr
        saveMember(target)
        flog(f.id, uid, op, target, nameOfUser(target), 'rank ' .. nr)
        local ts = srcOf(target)
        if ts then notify(ts, ('New rank: %s.'):format(f.ranks[nr]), '#8ce07a'); pushSelf(ts) end
        return done('Rank updated.', 'success')

    elseif op == 'setRank' then
        -- set arbitrary rank 1..(RankLeader-1): doar Leaderul (faction_rank == 7)
        if m.rank < Config.RankLeader then return done('Leader only.', 'error') end
        if target == uid then return done('Not on yourself.', 'warning') end
        if tm.rank >= Config.RankLeader then return done('Cannot change the Leader here (use /setleader).', 'warning') end
        local nr = math.floor(tonumber(p.rank) or 0)
        if nr < 1 or nr >= Config.RankLeader then
            return done(('Rank must be 1-%d.'):format(Config.RankLeader - 1), 'error')
        end
        if nr == tm.rank then return refreshMember(src, uid) end
        tm.rank = nr
        saveMember(target)
        flog(f.id, uid, 'setrank', target, nameOfUser(target), 'rank ' .. nr)
        local ts = srcOf(target)
        if ts then notify(ts, ('New rank: %s.'):format(f.ranks[nr]), '#8ce07a'); pushSelf(ts) end
        return done('Rank updated.', 'success')

    elseif op == 'uninvite' then
        -- Uninvite: faction_rank >= 6, tinta strict sub rangul actorului
        if m.rank < Config.RankCoLeader then return done('Leader / Co-Leader only.', 'error') end
        if target == uid then return done('Not on yourself.', 'warning') end
        if tm.rank >= m.rank then return done('Cannot uninvite an equal or higher rank.', 'error') end
        flog(f.id, uid, 'uninvite', target, nameOfUser(target), p.reason)
        kickMember(target, p.reason and ('uninvited: ' .. tostring(p.reason):sub(1, 120)) or 'uninvited', uid)
        return done('Member removed from the faction.', 'success')

    elseif op == 'toggleTester' or op == 'toggleSupervisor' then
        -- Promote / Remove Tester|Supervisor: faction_rank >= 6
        if m.rank < Config.RankCoLeader then return done('Leader / Co-Leader only.', 'error') end
        local isSup = op == 'toggleSupervisor'
        if isSup then tm.supervisor = not tm.supervisor else tm.tester = not tm.tester end
        saveMember(target)
        flog(f.id, uid, op, target, nameOfUser(target), tostring(isSup and tm.supervisor or tm.tester))
        local ts = srcOf(target); if ts then pushSelf(ts) end
        return done(('%s %s.'):format(isSup and 'Supervisor' or 'Tester',
            (isSup and tm.supervisor or tm.tester) and 'granted' or 'removed'), 'success')

    elseif op == 'warn' or op == 'unwarn' then
        -- Give / Remove Faction Warn: faction_rank >= 6
        if m.rank < Config.RankCoLeader then return done('Leader / Co-Leader only.', 'error') end
        if op == 'warn' and tm.rank >= m.rank and target ~= uid then
            return done('Cannot warn an equal or higher rank.', 'error')
        end
        addWarn(f.id, uid, target, op == 'warn' and 1 or -1, p.reason)
        return done('Updated.', 'success')
    end
end)

-- ==========================================================
--  /devfactionmenu  -  meniul de dezvoltator (staff >= Config.DevGrade)
--    Tab-uri: Create Faction | Edit Faction
-- ==========================================================
local function devFactionList()
    local l = {}
    for id, x in pairs(FACTIONS) do l[#l + 1] = { id = id, name = x.name, active = x.active } end
    table.sort(l, function(a, b) return a.id < b.id end)
    return l
end

local function devFactionData(fid)
    local f = fid and FACTIONS[fid]
    if not f then return nil end
    return {
        id = f.id, name = f.name, short = f.short, ranks = f.ranks,
        leader = f.leader, leaderName = f.leaderName,
        manager = f.manager, managerName = f.managerName,
        hqEnter = f.hqEnter, hqExit = f.hqExit, hqVw = f.hqVw,
        vgarage = f.vgarage, hgarage = f.hgarage, bgarage = f.bgarage,
        vehicles = f.vehicles or { car = {}, heli = {}, boat = {} },
    }
end

local function devPayload(fid)
    return {
        factions        = devFactionList(),
        rankCount       = Config.RankCount,
        rankCoLeader    = Config.RankCoLeader,
        seedDefaultRank = Config.SeedDefaultMinRank,
        faction         = fid and devFactionData(fid) or nil,
    }
end

RegisterNetEvent('ph_factions:sv:openDevMenu', function()
    local src = source
    if not isDev(src) then return exports[PH]:CmdPermError(src, Config.DevGrade) end
    TriggerClientEvent('ph_factions:cl:openDevMenu', src, devPayload())
end)

RegisterNetEvent('ph_factions:sv:devMenu', function(p)
    local src = source
    if not isDev(src) then return end
    p = p or {}
    local op = p.op
    local actor = uidOf(src)

    local function push(fid, msg, kind)
        if msg then exports[PH]:Notify(src, msg, kind or 'info') end
        TriggerClientEvent('ph_factions:cl:devData', src, devPayload(fid))
    end

    if op == 'select' then
        return push(tonumber(p.factionId))

    elseif op == 'createFaction' then
        local name  = tostring(p.name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 64)
        local short = tostring(p.short or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 12)
        if #name < 3 then return push(nil, 'Name too short (min 3).', 'error') end
        if short == '' then short = name:sub(1, 3):upper() end
        if MySQL.scalar.await('SELECT id FROM factions WHERE f_name = ?', { name }) then
            return push(nil, 'A faction with that name already exists.', 'error')
        end
        local id = MySQL.insert.await('INSERT INTO factions (f_name, f_short, ranks) VALUES (?,?,?)',
            { name, short, enc(Config.DefaultRanks) })
        reloadFaction(id); pushPublic(-1)
        return push(id, ('Faction #%d "%s" created.'):format(id, name), 'success')

    elseif op == 'deleteFaction' then
        local fid = tonumber(p.factionId)
        if not fid or not FACTIONS[fid] then return push(nil, 'Unknown faction.', 'error') end
        MySQL.query.await('UPDATE users SET faction=0, faction_rank=0, is_tester=0, is_supervisor=0, faction_warns=0, faction_join=NULL WHERE faction=?', { fid })
        MySQL.query.await('DELETE FROM faction_vehicles WHERE faction_id=?', { fid })
        MySQL.query.await('DELETE FROM factions WHERE id=?', { fid })
        for tuid, mm in pairs(MEMBER) do if mm.faction == fid then setMemberFaction(tuid, 0, 0) end end
        FACTIONS[fid] = nil; pushPublic(-1)
        return push(nil, ('Faction #%d deleted.'):format(fid), 'warning')

    elseif op == 'setLeader' or op == 'setManager' then
        local fid = tonumber(p.factionId)
        local tgt = tonumber(p.userId)
        if not fid or not FACTIONS[fid] or not tgt then return push(fid, 'Invalid parameters.', 'error') end
        if not MySQL.scalar.await('SELECT id FROM users WHERE id = ?', { tgt }) then
            return push(fid, 'No user with id ' .. tgt .. '.', 'error')
        end
        local col  = op == 'setLeader' and 'leader' or 'manager'
        local rank = op == 'setLeader' and Config.RankLeader or Config.RankCoLeader
        MySQL.update.await(('UPDATE factions SET %s = ? WHERE id = ?'):format(col), { tgt, fid })
        setMemberFaction(tgt, fid, rank)
        reloadFaction(fid)
        flog(fid, actor, op, tgt, nameOfUser(tgt))
        pushFactionMembers(fid); pushPublic(-1)
        return push(fid, ('%s set.'):format(op == 'setLeader' and 'Leader' or 'Manager'), 'success')

    elseif op == 'setPoint' then
        local fid = tonumber(p.factionId)
        if not fid or not FACTIONS[fid] then return push(nil, 'Unknown faction.', 'error') end
        local ped = GetPlayerPed(src)
        local c = GetEntityCoords(ped); local h = GetEntityHeading(ped)
        local pt = { x = r2(c.x), y = r2(c.y), z = r2(c.z), h = r2(h) }
        local what = p.what
        local col
        if what == 'hqEnter' then
            col = 'hq_enter'
        elseif what == 'hqExit' then
            col = 'hq_exit'
            -- interiorul se seteaza si cu routing bucket-ul curent al utilizatorului
            MySQL.update.await('UPDATE factions SET hq_vw = ? WHERE id = ?', { GetPlayerRoutingBucket(src), fid })
        elseif what == 'vgarage' or what == 'hgarage' or what == 'bgarage' then
            col = what
            pt.label = Config.Garages[({ vgarage = 'car', hgarage = 'heli', bgarage = 'boat' })[what]].label
            pt.sx, pt.sy, pt.sz, pt.sh = pt.x, pt.y, pt.z, pt.h
        else
            return push(fid, 'Unknown point.', 'error')
        end
        MySQL.update.await(('UPDATE factions SET %s = ? WHERE id = ?'):format(col), { enc(pt), fid })
        reloadFaction(fid); pushPublic(-1); pushFactionMembers(fid)
        return push(fid, ('%s set to your position.'):format(what), 'success')

    elseif op == 'seedVanilla' then
        local fid = tonumber(p.factionId)
        if not fid or not FACTIONS[fid] then return push(nil, 'Unknown faction.', 'error') end
        local mr = math.max(1, math.min(Config.RankCount, tonumber(p.minRank) or Config.SeedDefaultMinRank))
        local n, errmsg = seedVanillaInto(fid, mr)
        if not n then return push(fid, errmsg or 'Seeding error.', 'error') end
        SetTimeout(800, function() reloadFaction(fid); TriggerClientEvent('ph_factions:cl:devData', src, devPayload(fid)) end)
        return push(fid, ('Added %d vanilla vehicles (min rank %d).'):format(n, mr), 'success')

    elseif op == 'addVehicle' then
        local fid = tonumber(p.factionId)
        local f = fid and FACTIONS[fid]
        if not f then return push(nil, 'Unknown faction.', 'error') end
        local cat = tostring(p.category or 'car')
        if not Config.Garages[cat] then return push(fid, 'Invalid category.', 'error') end
        local model = tostring(p.model or ''):gsub('%s', ''):lower():sub(1, 64)
        local label = tostring(p.label or model):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 64)
        local mr = math.max(1, math.min(Config.RankCount, tonumber(p.minRank) or 1))
        if #model < 2 then return push(fid, 'Invalid model.', 'error') end
        if label == '' then label = model end
        MySQL.insert.await('INSERT INTO faction_vehicles (faction_id, category, model, label, min_rank) VALUES (?,?,?,?,?)',
            { fid, cat, model, label, mr })
        reloadFaction(fid)
        return push(fid, 'Vehicle added.', 'success')

    elseif op == 'removeVehicle' then
        local fid = tonumber(p.factionId)
        if not fid or not FACTIONS[fid] then return push(nil, 'Unknown faction.', 'error') end
        MySQL.query.await('DELETE FROM faction_vehicles WHERE id = ? AND faction_id = ?', { tonumber(p.vehId), fid })
        reloadFaction(fid)
        return push(fid, 'Vehicle removed.', 'success')

    elseif op == 'setVehicleRank' then
        local fid = tonumber(p.factionId)
        if not fid or not FACTIONS[fid] then return push(fid) end
        local mr = math.max(1, math.min(Config.RankCount, tonumber(p.minRank) or 1))
        MySQL.update.await('UPDATE faction_vehicles SET min_rank = ? WHERE id = ? AND faction_id = ?', { mr, tonumber(p.vehId), fid })
        reloadFaction(fid)
        return push(fid, 'Vehicle rank updated.', 'success')

    elseif op == 'setRankName' then
        local fid = tonumber(p.factionId)
        local f = fid and FACTIONS[fid]
        if not f then return push(nil, 'Unknown faction.', 'error') end
        local i = tonumber(p.index)
        local nm = tostring(p.name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 32)
        if not i or i < 1 or i > Config.RankCount or #nm < 1 then return push(fid, 'Invalid data.', 'error') end
        f.ranks[i] = nm
        MySQL.update.await('UPDATE factions SET ranks = ? WHERE id = ?', { enc(f.ranks), fid })
        pushFactionMembers(fid)
        return push(fid, ('Rank %d renamed to "%s".'):format(i, nm), 'success')
    end
end)


-- ----------------------------------------------------------
--  Exports
-- ----------------------------------------------------------
exports('GetFaction',      function(userId) local m = MEMBER[userId]; return m and m.faction or 0 end)
exports('GetFactionRank',  function(userId) local m = MEMBER[userId]; return m and m.rank or 0 end)
exports('IsOnDuty',        function(userId) return DUTY[userId] == true end)
exports('IsTester',        function(userId) local m = MEMBER[userId]; return (m and m.tester) == true end)
exports('IsSupervisor',    function(userId) local m = MEMBER[userId]; return (m and m.supervisor) == true end)
exports('IsFactionMember', function(userId, fid) local m = MEMBER[userId]; return m ~= nil and m.faction == tonumber(fid) end)
exports('GetFactionName',  function(fid) local f = FACTIONS[tonumber(fid) or 0]; return f and f.name or nil end)
exports('GetRankName',     function(fid, rank)
    local f = FACTIONS[tonumber(fid) or 0]
    return f and f.ranks[tonumber(rank) or 0] or nil
end)
exports('GetFactionData',  function(fid) return FACTIONS[tonumber(fid) or 0] end)
