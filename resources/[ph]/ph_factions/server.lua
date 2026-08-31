-- ==========================================================
--  ph_factions / server
--
--  Totul se cheiaza pe SQL id (users.id).  Apartenenta e in `users`
--  (faction / faction_rank / is_tester / is_supervisor / faction_join /
--   faction_warns).  Datele de factiune sunt in `factions` + `faction_vehicles`.
-- ==========================================================
local PH = 'ph-core'
local ready = false

local FACTIONS = {}   -- [id] = { id, name, short, ranks[7], leader, leaderName, manager, managerName,
                      --          hqEnter, hqExit, hqVw, blip, vgarage, hgarage, bgarage, active,
                      --          vehicles = { car={}, heli={}, boat={} } }
local MEMBER   = {}   -- [userId] = { faction, rank, tester, supervisor, warns, join }
local DUTY     = {}   -- [userId] = bool
local INSIDE   = {}   -- [userId] = factionId  (in interiorul HQ)
local S2U      = {}   -- [src] = userId

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function enc(t) return t and json.encode(t) or nil end
local function dec(s)
    if type(s) ~= 'string' or s == '' then return nil end
    local ok, v = pcall(json.decode, s)
    return ok and v or nil
end

local function srcOf(userId)
    local ok, s = pcall(function() return exports[PH]:GetSource(userId) end)
    return (ok and s) or nil
end
local function uidOf(src) return S2U[src] or (function()
    local ok, u = pcall(function() return exports[PH]:SourceToUserId(src) end)
    return ok and u or nil
end)() end

local function notify(src, text, color)
    if not src then return end
    if GetResourceState('ph_chat') == 'started' then
        exports['ph_chat']:send(src, { text = text, textColor = color or '#e8e6f0' })
    else
        TriggerClientEvent('chat:addMessage', src, { args = { text } })
    end
end

local function nameOfUser(userId)
    if not userId then return nil end
    local row = MySQL.single.await('SELECT username FROM users WHERE id = ?', { userId })
    return row and row.username or nil
end

--- numele RP (users.username) al unui jucator online, cu fallback pe numele FiveM
local function rpName(src)
    local ok, ch = pcall(function() return exports[PH]:GetCharacter(src) end)
    if ok and type(ch) == 'table' and ch.username then return ch.username end
    return GetPlayerName(src) or ('Player_' .. src)
end

local function bucketOf(f)
    if not f then return 0 end
    return (f.hqVw and f.hqVw > 0) and f.hqVw or (Config.HQBucketBase + f.id)
end

local function flog(fid, actor, action, targetId, targetName, detail)
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

local function reloadFaction(fid)
    local row = MySQL.single.await('SELECT * FROM factions WHERE id = ?', { fid })
    if row then cacheFaction(row) else FACTIONS[fid] = nil end
end

--- adauga toate vehiculele din data/vehicles_vanilla.lua in `faction_vehicles`.
--- @return n|nil, err
local function seedVanillaInto(fid, minRank)
    if not FACTIONS[fid] then return nil, 'Factiune inexistenta.' end
    minRank = math.max(1, math.min(Config.RankCount, tonumber(minRank) or Config.SeedDefaultMinRank))
    local raw = LoadResourceFile(GetCurrentResourceName(), 'data/vehicles_vanilla.lua')
    local okL, vanilla = pcall(function()
        local chunk = raw and load(raw, 'vehicles_vanilla', 't', {})
        return chunk and chunk() or nil
    end)
    if not okL or type(vanilla) ~= 'table' then return nil, 'Nu am putut incarca data/vehicles_vanilla.lua.' end
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
    print(('^5[ph_factions]^7 pregatit (%d factiuni).'):format(n))
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

local function pushPublic(target)
    TriggerClientEvent('ph_factions:cl:factions', target or -1, publicFactionList())
end

--- config + apartenenta pentru un jucator anume
local function pushSelf(src)
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
local function pushFactionMembers(fid)
    for uid, mm in pairs(MEMBER) do
        if mm.faction == fid then
            local s = srcOf(uid)
            if s then pushSelf(s) end
        end
    end
end

-- ----------------------------------------------------------
--  Roluri / permisiuni in meniu
-- ----------------------------------------------------------
--- rank "efectiv" pentru actiuni HR: supervisor conteaza ca Co-Leader
local function effRank(m)
    if not m or m.faction == 0 then return 0 end
    if m.rank >= Config.RankLeader then return Config.RankLeader end
    if m.supervisor then return math.max(m.rank, Config.RankCoLeader) end
    return m.rank
end

local function canOpenMenu(uid)
    local m = MEMBER[uid]
    if not m or m.faction == 0 then return false end
    return m.rank >= Config.MenuRank or m.tester or m.supervisor
end

local function isDev(src)
    local ok, r = pcall(function() return exports[PH]:HasStaffRank(src, Config.DevGrade) end)
    return ok and r == true
end

-- ----------------------------------------------------------
--  Operatii de membru
-- ----------------------------------------------------------
local function announceLocal(src, text, color)
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

local function setMemberFaction(userId, fid, rank)
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

local function kickMember(userId, reason)
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
        notify(s, ('Ai fost scos din factiune%s.'):format(reason and (' (' .. reason .. ')') or ''), '#e07a7a')
    end
    flog(fid, nil, 'kick', userId, nameOfUser(userId), reason)
end

local function addWarn(fid, actorUid, targetUid, delta, reason)
    local m = MEMBER[targetUid]
    if not m or m.faction ~= fid then return false, 'Nu e in factiune.' end
    m.warns = math.max(0, math.min(99, (m.warns or 0) + delta))
    saveMember(targetUid)
    flog(fid, actorUid, delta > 0 and 'warn' or 'unwarn', targetUid, nameOfUser(targetUid), reason)
    local s = srcOf(targetUid)
    if s then
        notify(s, delta > 0
            and ('Ai primit un warn de factiune (%d/%d)%s'):format(m.warns, Config.MaxWarns, reason and (': ' .. reason) or '')
            or  ('Ti-a fost scos un warn de factiune (%d/%d).'):format(m.warns, Config.MaxWarns),
            delta > 0 and '#e07a7a' or '#8ce07a')
    end
    if m.warns >= Config.MaxWarns then
        kickMember(targetUid, ('%d warn-uri'):format(Config.MaxWarns))
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
--  /duty
-- ----------------------------------------------------------
RegisterCommand('duty', function(src)
    if src == 0 then return end
    local uid = uidOf(src)
    local m = uid and MEMBER[uid]
    if not m or m.faction == 0 then
        return notify(src, 'Nu esti intr-o factiune.', '#e07a7a')
    end
    DUTY[uid] = not DUTY[uid]
    local name = rpName(src)
    if DUTY[uid] then
        announceLocal(src, ('%s is now on duty!'):format(name), Config.DutyColorOn)
    else
        announceLocal(src, ('%s is now off duty!'):format(name), Config.DutyColorOff)
    end
    pushSelf(src)
end, false)

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
    if not f.hqExit then return notify(src, 'HQ-ul nu are inca un punct de interior setat.', '#e07a7a') end

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
    if not g then return notify(src, 'Garajul nu e configurat.', '#e07a7a') end

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
        return notify(src, 'Rank-ul tau nu permite acest vehicul.', '#e07a7a')
    end

    local spawn = { x = g.sx or g.x, y = g.sy or g.y, z = g.sz or g.z, h = g.sh or g.h or 0.0 }
    TriggerClientEvent('ph_factions:cl:spawnVehicle', src, veh.model, spawn, m.faction, veh.props)
    flog(f.id, uid, 'vehicle_out', nil, nil, ('%s (%s)'):format(veh.label, category))
end)

-- ----------------------------------------------------------
--  /factionmenu
-- ----------------------------------------------------------
local function buildMembers(fid)
    local rows = MySQL.query.await([[
        SELECT id, username, faction_rank, is_tester, is_supervisor, faction_warns, faction_join, last_login
        FROM users WHERE faction = ? ORDER BY faction_rank DESC, username ASC
    ]], { fid }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = r.id, name = r.username, rank = tonumber(r.faction_rank) or 0,
            tester = (tonumber(r.is_tester) or 0) ~= 0,
            supervisor = (tonumber(r.is_supervisor) or 0) ~= 0,
            warns = tonumber(r.faction_warns) or 0,
            join = r.faction_join, lastLogin = r.last_login,
            online = srcOf(r.id) ~= nil,
        }
    end
    return out
end

local function menuPayload(src, uid, m)
    local f = FACTIONS[m.faction]
    local eff = effRank(m)
    return {
        role = {
            rank = m.rank, effRank = eff, rankName = f and f.ranks[m.rank] or nil,
            tester = m.tester, supervisor = m.supervisor,
            isLeader = m.rank >= Config.RankLeader,
            isDev = isDev(src),
            canManage = eff >= Config.MenuRank,
            canRecruit = (m.rank >= Config.RecruitRank) or m.tester or m.supervisor,
        },
        faction = f and {
            id = f.id, name = f.name, short = f.short, ranks = f.ranks,
            leader = f.leader, leaderName = f.leaderName,
            manager = f.manager, managerName = f.managerName,
            hqEnter = f.hqEnter, hqExit = f.hqExit,
            vgarage = f.vgarage, hgarage = f.hgarage, bgarage = f.bgarage,
        } or nil,
        members = f and buildMembers(f.id) or {},
        vehicles = f and f.vehicles or { car = {}, heli = {}, boat = {} },
        maxWarns = Config.MaxWarns,
        rankCount = Config.RankCount,
        allFactions = isDev(src) and (function()
            local l = {} for id, x in pairs(FACTIONS) do l[#l+1] = { id = id, name = x.name, active = x.active } end
            table.sort(l, function(a,b) return a.id < b.id end)
            return l
        end)() or nil,
    }
end

RegisterNetEvent('ph_factions:sv:openMenu', function()
    local src = source
    local uid = uidOf(src)
    local m = uid and MEMBER[uid]
    if not m then return end
    if not canOpenMenu(uid) and not isDev(src) then
        return notify(src, 'Nu ai acces la /factionmenu.', '#e07a7a')
    end
    TriggerClientEvent('ph_factions:cl:openMenu', src, menuPayload(src, uid, m))
end)

--- refresh (dupa o actiune)
local function refreshMenu(src, uid)
    local m = MEMBER[uid]
    if m then TriggerClientEvent('ph_factions:cl:menuData', src, menuPayload(src, uid, m)) end
end

RegisterNetEvent('ph_factions:sv:menu', function(p)
    local src = source
    local uid = uidOf(src)
    local m = uid and MEMBER[uid]
    if not m then return end
    if not canOpenMenu(uid) and not isDev(src) then return end
    p = p or {}
    local op = p.op
    local f = FACTIONS[m.faction]
    local eff = effRank(m)
    local dev = isDev(src)

    local function done(msg, color)
        if msg then notify(src, msg, color) end
        refreshMenu(src, uid)
    end

    -- ---- DEV: creare / stergere / setare lider ----
    if op == 'createFaction' then
        if not dev then return end
        local name = tostring(p.name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 64)
        if #name < 3 then return done('Nume prea scurt.', '#e07a7a') end
        if MySQL.scalar.await('SELECT id FROM factions WHERE f_name = ?', { name }) then
            return done('Exista deja o factiune cu acest nume.', '#e07a7a')
        end
        local id = MySQL.insert.await('INSERT INTO factions (f_name, f_short, ranks) VALUES (?,?,?)',
            { name, name:sub(1, 3):upper(), enc(Config.DefaultRanks) })
        reloadFaction(id)
        pushPublic(-1)
        return done(('Factiune creata: #%d %s'):format(id, name), '#8ce07a')

    elseif op == 'deleteFaction' then
        if not dev then return end
        local fid = tonumber(p.factionId)
        if not fid or not FACTIONS[fid] then return end
        MySQL.query.await('UPDATE users SET faction=0, faction_rank=0, is_tester=0, is_supervisor=0, faction_warns=0, faction_join=NULL WHERE faction=?', { fid })
        MySQL.query.await('DELETE FROM faction_vehicles WHERE faction_id=?', { fid })
        MySQL.query.await('DELETE FROM factions WHERE id=?', { fid })
        for tuid, mm in pairs(MEMBER) do
            if mm.faction == fid then setMemberFaction(tuid, 0, 0) end
        end
        FACTIONS[fid] = nil
        pushPublic(-1)
        return done('Factiune stearsa.', '#e0c07a')

    elseif op == 'setLeader' or op == 'setManager' then
        if not dev then return end
        local fid = tonumber(p.factionId) or m.faction
        local target = tonumber(p.userId)
        if not FACTIONS[fid] or not target then return done('Parametri invalizi.', '#e07a7a') end
        if not MySQL.scalar.await('SELECT id FROM users WHERE id = ?', { target }) then
            return done('Nu exista user cu id ' .. target .. '.', '#e07a7a')
        end
        local col = op == 'setLeader' and 'leader' or 'manager'
        MySQL.update.await(('UPDATE factions SET %s = ? WHERE id = ?'):format(col), { target, fid })
        -- lider primeste rank 7, manager rank 6, ambii intra in factiune
        local rank = op == 'setLeader' and Config.RankLeader or Config.RankCoLeader
        setMemberFaction(target, fid, rank)
        reloadFaction(fid)
        flog(fid, uid, op, target, nameOfUser(target))
        pushFactionMembers(fid)
        pushPublic(-1)
        return done(('%s setat.'):format(op == 'setLeader' and 'Lider' or 'Manager'), '#8ce07a')

    -- ---- DEV: setare coordonate din pozitia curenta ----
    elseif op == 'setPoint' then
        if not dev then return end
        local fid = tonumber(p.factionId) or m.faction
        if not FACTIONS[fid] then return end
        local ped = GetPlayerPed(src)
        local c = GetEntityCoords(ped); local h = GetEntityHeading(ped)
        local pt = { x = math.floor(c.x*100)/100, y = math.floor(c.y*100)/100, z = math.floor(c.z*100)/100, h = math.floor(h*100)/100 }
        local what = p.what
        local col
        if what == 'hqEnter' then col = 'hq_enter'
        elseif what == 'hqExit' then col = 'hq_exit'
        elseif what == 'vgarage' or what == 'hgarage' or what == 'bgarage' then
            col = what
            -- garaj: pastreaza si un punct de spawn (2m in fata)
            pt.label = Config.Garages[({vgarage='car',hgarage='heli',bgarage='boat'})[what]].label
            pt.sx, pt.sy, pt.sz, pt.sh = pt.x, pt.y, pt.z, pt.h
        else return done('Punct necunoscut.', '#e07a7a') end
        MySQL.update.await(('UPDATE factions SET %s = ? WHERE id = ?'):format(col), { enc(pt), fid })
        reloadFaction(fid)
        pushPublic(-1)
        pushFactionMembers(fid)
        return done(('%s setat pe pozitia ta.'):format(what), '#8ce07a')

    elseif op == 'seedVanilla' then
        if not dev then return done() end
        local fid = tonumber(p.factionId) or m.faction
        if not FACTIONS[fid] then return end
        local minRank = math.max(1, math.min(Config.RankCount, tonumber(p.minRank) or Config.SeedDefaultMinRank))
        local n, errmsg = seedVanillaInto(fid, minRank)
        if not n then return done(errmsg or 'Eroare la seed.', '#e07a7a') end
        SetTimeout(800, function() reloadFaction(fid); refreshMenu(src, uid) end)
        return done(('Adaugate %d vehicule vanilla (min rank %d). Se reincarca...'):format(n, minRank), '#8ce07a')
    end

    -- ---- restul necesita factiune ----
    if m.faction == 0 or not f then return end

    if op == 'setRankName' then
        if m.rank < Config.RankLeader then return done('Doar liderul poate redenumi rank-urile.', '#e07a7a') end
        local i = tonumber(p.index)
        local name = tostring(p.name or ''):gsub('^%s+',''):gsub('%s+$',''):sub(1, 32)
        if not i or i < 1 or i > Config.RankCount or #name < 1 then return done('Date invalide.', '#e07a7a') end
        f.ranks[i] = name
        MySQL.update.await('UPDATE factions SET ranks = ? WHERE id = ?', { enc(f.ranks), f.id })
        pushFactionMembers(f.id)
        return done('Rank redenumit.', '#8ce07a')

    elseif op == 'recruit' then
        if not ((m.rank >= Config.RecruitRank) or m.tester or m.supervisor) then
            return done('Nu ai permisiunea sa recrutezi.', '#e07a7a')
        end
        local target = tonumber(p.userId)
        if not target and p.serverId then
            target = exports[PH]:SourceToUserId(tonumber(p.serverId))
        end
        local tm = target and MEMBER[target]
        if not tm then return done('Jucatorul trebuie sa fie online si langa tine.', '#e07a7a') end
        if tm.faction ~= 0 then return done('Jucatorul e deja intr-o factiune.', '#e07a7a') end
        setMemberFaction(target, f.id, 1)
        flog(f.id, uid, 'recruit', target, nameOfUser(target))
        local ts = srcOf(target)
        if ts then notify(ts, ('Ai fost recrutat in %s ca %s.'):format(f.name, f.ranks[1]), '#8ce07a') end
        return done('Jucator recrutat.', '#8ce07a')

    elseif op == 'promote' or op == 'demote' then
        local target = tonumber(p.userId)
        local tm = target and MEMBER[target]
        if not tm or tm.faction ~= f.id then return done('Nu e in factiune.', '#e07a7a') end
        if not (eff >= Config.MenuRank and eff > tm.rank) then return done('Rank insuficient.', '#e07a7a') end
        local nr = tm.rank + (op == 'promote' and 1 or -1)
        if nr < 1 then return done('Deja la rank minim (foloseste Kick).', '#e0c07a') end
        if nr >= eff then return done('Nu poti ridica pe cineva la rank-ul tau sau peste.', '#e07a7a') end
        if nr >= Config.RankLeader then return done('Transferul de leadership se face separat.', '#e0c07a') end
        tm.rank = nr
        saveMember(target)
        flog(f.id, uid, op, target, nameOfUser(target), 'rank ' .. nr)
        local ts = srcOf(target)
        if ts then notify(ts, ('Rank nou: %s.'):format(f.ranks[nr]), '#8ce07a'); pushSelf(ts) end
        return done('Facut.', '#8ce07a')

    elseif op == 'transferLeader' then
        if m.rank < Config.RankLeader then return done('Doar liderul.', '#e07a7a') end
        local target = tonumber(p.userId)
        local tm = target and MEMBER[target]
        if not tm or tm.faction ~= f.id then return done('Nu e in factiune.', '#e07a7a') end
        tm.rank = Config.RankLeader
        m.rank = Config.RankCoLeader
        saveMember(target); saveMember(uid)
        MySQL.update.await('UPDATE factions SET leader = ? WHERE id = ?', { target, f.id })
        reloadFaction(f.id)
        flog(f.id, uid, 'transferLeader', target, nameOfUser(target))
        pushFactionMembers(f.id)
        return done('Leadership transferat.', '#8ce07a')

    elseif op == 'warn' or op == 'unwarn' then
        local target = tonumber(p.userId)
        local tm = target and MEMBER[target]
        if not tm or tm.faction ~= f.id then return done('Nu e in factiune.', '#e07a7a') end
        if not (eff >= Config.MenuRank and eff > tm.rank) then return done('Rank insuficient.', '#e07a7a') end
        addWarn(f.id, uid, target, op == 'warn' and 1 or -1, p.reason)
        return done('Facut.', '#8ce07a')

    elseif op == 'kick' then
        local target = tonumber(p.userId)
        local tm = target and MEMBER[target]
        if not tm or tm.faction ~= f.id then return done('Nu e in factiune.', '#e07a7a') end
        if target == uid then return done('Nu te poti da tu afara.', '#e0c07a') end
        if not (eff >= Config.MenuRank and eff > tm.rank) then return done('Rank insuficient.', '#e07a7a') end
        kickMember(target, p.reason or 'decizie de conducere')
        flog(f.id, uid, 'kick', target, nameOfUser(target), p.reason)
        return done('Jucator scos.', '#8ce07a')

    elseif op == 'toggleTester' or op == 'toggleSupervisor' then
        local target = tonumber(p.userId)
        local tm = target and MEMBER[target]
        if not tm or tm.faction ~= f.id then return done('Nu e in factiune.', '#e07a7a') end
        local isSup = op == 'toggleSupervisor'
        -- supervisor: doar leader/co-leader.  tester: leader/co-leader sau supervisor.
        if isSup then
            if m.rank < Config.RankCoLeader then return done('Doar Leader / Co-Leader.', '#e07a7a') end
        else
            if not (m.rank >= Config.RankCoLeader or m.supervisor) then return done('Doar Leader / Co-Leader / Supervisor.', '#e07a7a') end
        end
        if isSup then tm.supervisor = not tm.supervisor else tm.tester = not tm.tester end
        saveMember(target)
        flog(f.id, uid, op, target, nameOfUser(target), tostring(isSup and tm.supervisor or tm.tester))
        local ts = srcOf(target); if ts then pushSelf(ts) end
        return done('Facut.', '#8ce07a')

    -- ---- vehicule ----
    elseif op == 'addVehicle' then
        if m.rank < Config.RankCoLeader then return done('Doar Leader / Co-Leader.', '#e07a7a') end
        local cat = tostring(p.category or 'car')
        if not Config.Garages[cat] then return done('Categorie invalida.', '#e07a7a') end
        local model = tostring(p.model or ''):gsub('%s',''):lower():sub(1, 64)
        local label = tostring(p.label or model):sub(1, 64)
        local mr = math.max(1, math.min(Config.RankCount, tonumber(p.minRank) or 1))
        if #model < 2 then return done('Model invalid.', '#e07a7a') end
        MySQL.insert.await('INSERT INTO faction_vehicles (faction_id, category, model, label, min_rank) VALUES (?,?,?,?,?)',
            { f.id, cat, model, label, mr })
        reloadFaction(f.id)
        return done('Vehicul adaugat.', '#8ce07a')

    elseif op == 'removeVehicle' then
        if m.rank < Config.RankCoLeader then return done('Doar Leader / Co-Leader.', '#e07a7a') end
        MySQL.query.await('DELETE FROM faction_vehicles WHERE id = ? AND faction_id = ?', { tonumber(p.vehId), f.id })
        reloadFaction(f.id)
        return done('Vehicul sters.', '#8ce07a')

    elseif op == 'setVehicleRank' then
        if m.rank < Config.RankCoLeader then return done('Doar Leader / Co-Leader.', '#e07a7a') end
        local mr = math.max(1, math.min(Config.RankCount, tonumber(p.minRank) or 1))
        MySQL.update.await('UPDATE faction_vehicles SET min_rank = ? WHERE id = ? AND faction_id = ?', { mr, tonumber(p.vehId), f.id })
        reloadFaction(f.id)
        return done('Rank vehicul actualizat.', '#8ce07a')

    elseif op == 'refresh' then
        return refreshMenu(src, uid)
    end
end)

-- ----------------------------------------------------------
--  Comenzi de administrare (staff >= developer) - varianta rapida
-- ----------------------------------------------------------
RegisterCommand('fcreate', function(src, args)
    if src ~= 0 and not isDev(src) then return end
    local name = table.concat(args, ' '):gsub('^%s+',''):gsub('%s+$','')
    if #name < 3 then print('uz: /fcreate <nume factiune>'); return end
    if MySQL.scalar.await('SELECT id FROM factions WHERE f_name = ?', { name }) then
        return notify(src, 'Nume deja folosit.', '#e07a7a')
    end
    local id = MySQL.insert.await('INSERT INTO factions (f_name, f_short, ranks) VALUES (?,?,?)',
        { name, name:sub(1,3):upper(), enc(Config.DefaultRanks) })
    reloadFaction(id); pushPublic(-1)
    notify(src, ('Factiune #%d "%s" creata. Deschide /factionmenu (tab Developer) sau /fsetleader %d <sqlId>.'):format(id, name, id), '#8ce07a')
end, false)

RegisterCommand('fsetleader', function(src, args)
    if src ~= 0 and not isDev(src) then return end
    local fid = tonumber(args[1]); local target = tonumber(args[2])
    if not fid or not target or not FACTIONS[fid] then print('uz: /fsetleader <factionId> <sqlId>'); return end
    if not MySQL.scalar.await('SELECT id FROM users WHERE id = ?', { target }) then
        return notify(src, 'user inexistent', '#e07a7a')
    end
    MySQL.update.await('UPDATE factions SET leader = ? WHERE id = ?', { target, fid })
    setMemberFaction(target, fid, Config.RankLeader)
    reloadFaction(fid)
    notify(src, ('Lider setat pentru factiunea #%d.'):format(fid), '#8ce07a')
end, false)

RegisterCommand('fseedvanilla', function(src, args)
    if src ~= 0 and not isDev(src) then return end
    local fid = tonumber(args[1]); local mr = tonumber(args[2]) or Config.SeedDefaultMinRank
    if not fid or not FACTIONS[fid] then print('uz: /fseedvanilla <factionId> [minRank]'); return end
    local n, err = seedVanillaInto(fid, mr)
    if not n then return notify(src, err or 'eroare', '#e07a7a') end
    SetTimeout(800, function() reloadFaction(fid) end)
    notify(src, ('Adaugate %d vehicule vanilla in factiunea #%d (min rank %d).'):format(n, fid, mr), '#8ce07a')
end, false)

RegisterCommand('fdelete', function(src, args)
    if src ~= 0 and not isDev(src) then return end
    local fid = tonumber(args[1])
    if not fid or not FACTIONS[fid] then print('uz: /fdelete <factionId>'); return end
    MySQL.query.await('UPDATE users SET faction=0, faction_rank=0, is_tester=0, is_supervisor=0, faction_warns=0, faction_join=NULL WHERE faction=?', { fid })
    MySQL.query.await('DELETE FROM faction_vehicles WHERE faction_id=?', { fid })
    MySQL.query.await('DELETE FROM factions WHERE id=?', { fid })
    for tuid, mm in pairs(MEMBER) do if mm.faction == fid then setMemberFaction(tuid, 0, 0) end end
    FACTIONS[fid] = nil; pushPublic(-1)
    notify(src, ('Factiunea #%d stearsa.'):format(fid), '#e0c07a')
end, false)

-- /factionmenu si /duty se apeleaza din client (vezi client.lua) ->
-- evenimentele ph_factions:sv:openMenu / comanda 'duty' de mai sus.

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
