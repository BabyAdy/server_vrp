-- ==========================================================
--  ph_clans / server
--
--  Totul se cheiaza pe SQL id (users.id).  Apartenenta e in `users`
--  (clan / clan_rank / clan_warns / clan_join / clan_perms / clan_tag_style /
--   clan_chat_hidden).  Datele de clan sunt in `clans` (+ clan_requests,
--   clan_vehicles, clan_logs).
--
--  Comenzile ( /c /togc /quitclan /cinvite /acceptcinvite /cdeposit
--  /lockclanchat /unlockclanchat /cmotd /clantag /clanreq /editclan )
--  sunt in clan_cmd.lua si folosesc tabelul global CLANENV.
--
--  Faza 2 adauga meniul /clan (NUI) si vehiculele de clan.
-- ==========================================================
local PH  = 'ph-core'
local RES = GetCurrentResourceName()
local ready = false

CLANS   = {}   -- [id]     = { id, name, short, tag, ranks[7], rankColors[7], leader, founder,
               --              active, expiresAt, money, pp, clanPoints, chatColor, motd, chatLockRank }
MEMBER  = {}   -- [userId] = { clan, rank, warns, join, perms={key=true}, tagStyle, chatHidden }
INVITES = {}   -- [userId] = { clan, byUid, byName, expires (os.time) }
local S2U = {} -- [src]    = userId

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
        local v = exports[PH]:GetUserId(src)
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

--- trimite clientului clan-id-ul curent (folosit de lacatul de sofer al
--  vehiculelor de clan).  0 = fara clan.
local function pushClan(userId)
    local s = srcOf(userId)
    if not s then return end
    local m = MEMBER[userId]
    TriggerClientEvent('ph_clans:cl:clan', s, (m and m.clan) or 0)
end

local function notify(src, text, kind)
    if not src or src == 0 then print('[ph_clans] ' .. tostring(text)) return end
    exports[PH]:Notify(src, text, kind or 'info')
end

local function chat(src, text, color)
    if not src or src == 0 then print('[ph_clans] ' .. tostring(text)) return end
    exports[PH]:Msg(src, text, color)
end

local function rpName(src)
    local ok, ch = pcall(function() return exports[PH]:GetCharacter(src) end)
    if ok and type(ch) == 'table' and ch.username then return ch.username end
    return GetPlayerName(src) or ('Player_' .. tostring(src))
end

local function nameOfUser(userId)
    if not userId then return nil end
    local row = MySQL.single.await('SELECT username FROM users WHERE id = ?', { userId })
    return row and row.username or nil
end

local function staffAtLeast(src, gradeKey)
    if src == 0 then return true end
    local ok, r = pcall(function() return exports[PH]:HasStaffRank(src, gradeKey) end)
    return ok and r == true
end

local function withinRange(a, b, dist)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if not pa or not pb or pa == 0 or pb == 0 then return false end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb)) <= dist
end

--- zile ramase (in sus) dintr-un DATETIME "YYYY-MM-DD HH:MM:SS"
local function daysLeft(expiresAt)
    local y, mo, d, h, mi, s = tostring(expiresAt or ''):match('(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)')
    if not y then return 0 end
    local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                        hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
    local dif = os.difftime(t, os.time())
    if dif <= 0 then return 0 end
    return math.ceil(dif / 86400)
end

local function clog(clanId, actorId, action, targetId, detail)
    MySQL.insert(
        'INSERT INTO clan_logs (clan_id, actor_id, actor_name, action, target_id, target_name, detail) VALUES (?,?,?,?,?,?,?)',
        { clanId, actorId, actorId and nameOfUser(actorId) or nil, action,
          targetId, targetId and nameOfUser(targetId) or nil,
          detail and tostring(detail):sub(1, 255) or nil })
end

local function parsePerms(csv)
    local t = {}
    for k in tostring(csv or ''):gmatch('[^,]+') do
        k = k:gsub('%s', '')
        if k ~= '' then t[k] = true end
    end
    return t
end

local function permsCsv(t)
    local a = {}
    for _, k in ipairs(Config.Perms) do if t[k] then a[#a + 1] = k end end
    return table.concat(a, ',')
end

-- ----------------------------------------------------------
--  DB init / migratie
-- ----------------------------------------------------------
local TABLES = {
    [[CREATE TABLE IF NOT EXISTS `clans` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `c_name` VARCHAR(64) NOT NULL,
      `c_short` VARCHAR(12) NOT NULL DEFAULT '',
      `c_tag` VARCHAR(5) NOT NULL DEFAULT '',
      `ranks` LONGTEXT NOT NULL,
      `rank_colors` LONGTEXT NULL DEFAULT NULL,
      `leader` INT UNSIGNED NULL DEFAULT NULL,
      `founder` INT UNSIGNED NULL DEFAULT NULL,
      `active` TINYINT(1) NOT NULL DEFAULT 1,
      `expires_at` DATETIME NULL DEFAULT NULL,
      `money` BIGINT NOT NULL DEFAULT 0,
      `premiumpoints` BIGINT NOT NULL DEFAULT 0,
      `clan_points` BIGINT NOT NULL DEFAULT 0,
      `chat_color` VARCHAR(9) NOT NULL DEFAULT '#b98cff',
      `motd` VARCHAR(200) NOT NULL DEFAULT '',
      `chat_lock_rank` TINYINT NOT NULL DEFAULT 1,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), UNIQUE KEY `uq_clans_name` (`c_name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    [[CREATE TABLE IF NOT EXISTS `clan_requests` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `user_id` INT UNSIGNED NOT NULL,
      `c_name` VARCHAR(25) NOT NULL,
      `c_tag` VARCHAR(5) NOT NULL,
      `status` ENUM('pending','accepted','rejected') NOT NULL DEFAULT 'pending',
      `decided_by` INT UNSIGNED NULL DEFAULT NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), KEY `idx_cr_status` (`status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    [[CREATE TABLE IF NOT EXISTS `clan_vehicles` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `clan_id` INT UNSIGNED NOT NULL,
      `model` VARCHAR(64) NOT NULL,
      `label` VARCHAR(64) NOT NULL,
      `category` ENUM('car','heli','boat') NOT NULL DEFAULT 'car',
      `plate` VARCHAR(8) NOT NULL DEFAULT '',
      `props` LONGTEXT NULL DEFAULT NULL,
      `park` LONGTEXT NULL DEFAULT NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), KEY `idx_cv_clan` (`clan_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    [[CREATE TABLE IF NOT EXISTS `clan_logs` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `clan_id` INT UNSIGNED NOT NULL,
      `actor_id` INT UNSIGNED NULL, `actor_name` VARCHAR(24) NULL,
      `action` VARCHAR(32) NOT NULL,
      `target_id` INT UNSIGNED NULL, `target_name` VARCHAR(24) NULL,
      `detail` VARCHAR(255) NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), KEY `idx_clog` (`clan_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],
}

local function columnExists(tbl, col)
    local n = MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?',
        { tbl, col })
    return (tonumber(n) or 0) > 0
end

local function ensureColumns(tbl, defs)
    for _, d in ipairs(defs) do
        if not columnExists(tbl, d[1]) then
            pcall(function() MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tbl, d[1], d[2])) end)
        end
    end
end

local function migrate()
    for _, q in ipairs(TABLES) do MySQL.query.await(q) end

    ensureColumns('users', {
        { 'phone',            'VARCHAR(10) NULL DEFAULT NULL' },
        { 'clan_perms',       "VARCHAR(64) NOT NULL DEFAULT ''" },
        { 'clan_tag_style',   'TINYINT NOT NULL DEFAULT 0' },
        { 'clan_chat_hidden', 'TINYINT NOT NULL DEFAULT 0' },
    })
    pcall(function() MySQL.query.await('ALTER TABLE `users` ADD UNIQUE KEY `uq_users_phone` (`phone`)') end)

    ensureColumns('clans', {
        { 'c_tag',          "VARCHAR(5) NOT NULL DEFAULT ''" },
        { 'founder',        'INT UNSIGNED NULL DEFAULT NULL' },
        { 'expires_at',     'DATETIME NULL DEFAULT NULL' },
        { 'money',          'BIGINT NOT NULL DEFAULT 0' },
        { 'premiumpoints',  'BIGINT NOT NULL DEFAULT 0' },
        { 'clan_points',    'BIGINT NOT NULL DEFAULT 0' },
        { 'chat_color',     "VARCHAR(9) NOT NULL DEFAULT '#b98cff'" },
        { 'rank_colors',    'LONGTEXT NULL DEFAULT NULL' },
        { 'motd',           "VARCHAR(200) NOT NULL DEFAULT ''" },
        { 'chat_lock_rank', 'TINYINT NOT NULL DEFAULT 1' },
    })

    -- Faza 2 : coloane pentru vehiculele de clan (Buy / Sell / Upgrade)
    ensureColumns('clan_vehicles', {
        { 'upgrade',   'TINYINT NOT NULL DEFAULT 0' },
        { 'bought_by', 'INT UNSIGNED NULL DEFAULT NULL' },
        { 'bought_at', 'TIMESTAMP NULL DEFAULT NULL' },
    })
end

-- ----------------------------------------------------------
--  Cache clanuri
-- ----------------------------------------------------------
local function normList(src, defaults, maxLen)
    local out = {}
    for i = 1, Config.RankCount do
        local v = (type(src) == 'table') and src[i] or nil
        out[i] = (type(v) == 'string' and v ~= '') and v:sub(1, maxLen or 32) or defaults[i]
    end
    return out
end

local function cacheClan(row)
    if not row then return end
    CLANS[row.id] = {
        id           = row.id,
        name         = row.c_name,
        short        = row.c_short or '',
        tag          = row.c_tag or '',
        ranks        = normList(dec(row.ranks), Config.DefaultRanks, 15),
        rankColors   = normList(dec(row.rank_colors), Config.DefaultRankColors, 9),
        leader       = row.leader and tonumber(row.leader) or nil,
        founder      = row.founder and tonumber(row.founder) or nil,
        active       = (tonumber(row.active) or 1) ~= 0,
        expiresAt    = row.expires_at,
        money        = tonumber(row.money) or 0,
        pp           = tonumber(row.premiumpoints) or 0,
        clanPoints   = tonumber(row.clan_points) or 0,
        chatColor    = row.chat_color or Config.DefaultChatColor,
        motd         = row.motd or '',
        chatLockRank = tonumber(row.chat_lock_rank) or 1,
    }
    return CLANS[row.id]
end

local function loadAllClans()
    for k in pairs(CLANS) do CLANS[k] = nil end   -- golire in-place (CLANENV pastreaza referinta)
    for _, r in ipairs(MySQL.query.await('SELECT * FROM clans') or {}) do cacheClan(r) end
end

function reloadClan(id)
    id = tonumber(id)
    local row = id and MySQL.single.await('SELECT * FROM clans WHERE id = ?', { id })
    if row then cacheClan(row) else CLANS[id] = nil end
    return CLANS[id]
end

-- ----------------------------------------------------------
--  Membru: incarcare / salvare
-- ----------------------------------------------------------
local function loadMember(userId)
    local row = MySQL.single.await(
        'SELECT clan, clan_rank, clan_warns, clan_join, clan_perms, clan_tag_style, clan_chat_hidden FROM users WHERE id = ?',
        { userId })
    local m = {
        clan       = row and tonumber(row.clan) or 0,
        rank       = row and tonumber(row.clan_rank) or 0,
        warns      = row and tonumber(row.clan_warns) or 0,
        join       = row and row.clan_join or nil,
        perms      = parsePerms(row and row.clan_perms),
        tagStyle   = row and tonumber(row.clan_tag_style) or 0,
        chatHidden = (row and tonumber(row.clan_chat_hidden) or 0) ~= 0,
    }
    -- clan disparut -> curata apartenenta, pastreaza preferintele personale
    if m.clan ~= 0 and not CLANS[m.clan] then
        MySQL.update("UPDATE users SET clan = 0, clan_rank = 0, clan_warns = 0, clan_join = NULL, clan_perms = '' WHERE id = ?", { userId })
        m.clan, m.rank, m.warns, m.join, m.perms = 0, 0, 0, nil, {}
    end
    MEMBER[userId] = m
    return m
end

local function saveMember(userId)
    local m = MEMBER[userId]
    if not m then return end
    MySQL.update([[
        UPDATE users SET clan = ?, clan_rank = ?, clan_warns = ?, clan_join = ?,
                         clan_perms = ?, clan_tag_style = ?, clan_chat_hidden = ?
        WHERE id = ?
    ]], {
        m.clan, m.rank, m.warns, m.join, permsCsv(m.perms), m.tagStyle,
        m.chatHidden and 1 or 0, userId,
    })
end

--- scrie apartenenta pentru un user offline direct in DB
local function dbSetMembership(userId, clanId, rank)
    if clanId == 0 then
        MySQL.update.await("UPDATE users SET clan = 0, clan_rank = 0, clan_warns = 0, clan_join = NULL, clan_perms = '' WHERE id = ?", { userId })
    else
        MySQL.update.await("UPDATE users SET clan = ?, clan_rank = ?, clan_warns = 0, clan_join = NOW(), clan_perms = '' WHERE id = ?",
            { clanId, rank, userId })
    end
    MEMBER[userId] = nil
end

-- ----------------------------------------------------------
--  Chat de clan  (/c)
-- ----------------------------------------------------------
local function clanChat(src, msg)
    local uid = uidOf(src)
    local m = uid and MEMBER[uid]
    if not m or m.clan == 0 then return notify(src, 'You are not in a clan.', 'error') end
    local c = CLANS[m.clan]
    if not c then return end
    if not c.active then return notify(src, 'Your clan is inactive (0 days left).', 'error') end
    if m.chatHidden then return notify(src, 'Your clan chat is hidden — use /togc to show it.', 'warning') end
    if m.rank < (c.chatLockRank or 1) then
        return notify(src, ('Clan chat is locked to rank %d and above.'):format(c.chatLockRank), 'error')
    end

    msg = tostring(msg or ''):gsub('%^%d', ''):sub(1, 180)
    if msg:gsub('%s', '') == '' then return end

    local name = rpName(src)
    local rc = c.rankColors[m.rank] or c.chatColor
    local segs = {
        { t = '(clan) ', c = c.chatColor },
        { t = c.tag ~= '' and ('[%s] '):format(c.tag) or '', c = rc },
        { t = name .. ': ', c = rc },
        { t = msg, c = c.chatColor },
    }
    for _, tuid in ipairs(exports[PH]:GetOnlineUserIds() or {}) do
        local tm = MEMBER[tuid]
        if tm and tm.clan == m.clan and (tuid == uid or not tm.chatHidden) then
            exports['ph_chat']:sendToUser(tuid, { segments = segs })
        end
    end
    print(('[clan %d] %s: %s'):format(m.clan, name, msg))
end

-- ----------------------------------------------------------
--  Safebox
-- ----------------------------------------------------------
local SAFE_COL = { money = 'money', pp = 'premiumpoints', clanPoints = 'clan_points' }

local function adjustSafebox(clanId, field, delta)
    local col = SAFE_COL[field]
    local c = CLANS[tonumber(clanId) or -1]
    if not col or not c then return nil end
    delta = math.floor(tonumber(delta) or 0)
    local cur = c[field] or 0
    local new = math.max(0, cur + delta)
    c[field] = new
    MySQL.update(('UPDATE clans SET `%s` = ? WHERE id = ?'):format(col), { new, c.id })
    return new
end

-- ----------------------------------------------------------
--  Creare clan dintr-o cerere aprobata
-- ----------------------------------------------------------
local function createClanFromRequest(req, staffSrc)
    if MySQL.scalar.await('SELECT id FROM clans WHERE c_name = ?', { req.c_name }) then
        return nil, 'A clan with that name already exists.'
    end
    local id = MySQL.insert.await([[
        INSERT INTO clans (c_name, c_short, c_tag, ranks, rank_colors, leader, founder, active,
                           expires_at, chat_color, chat_lock_rank)
        VALUES (?, ?, ?, ?, ?, ?, ?, 1, DATE_ADD(NOW(), INTERVAL ? DAY), ?, 1)
    ]], {
        req.c_name, tostring(req.c_tag or ''):sub(1, 12), req.c_tag,
        enc(Config.DefaultRanks), enc(Config.DefaultRankColors),
        req.user_id, req.user_id, Config.CreateDays, Config.DefaultChatColor,
    })
    if not id then return nil, 'Insert failed.' end
    reloadClan(id)

    local uid = tonumber(req.user_id)
    if srcOf(uid) then
        local m = MEMBER[uid] or loadMember(uid)
        m.clan, m.rank, m.warns, m.perms = id, Config.RankLeader, 0, {}
        m.join = os.date('%Y-%m-%d %H:%M:%S')
        MEMBER[uid] = m
        saveMember(uid)
        pushClan(uid)
    else
        dbSetMembership(uid, id, Config.RankLeader)
    end
    clog(id, uidOf(staffSrc), 'create', uid, ('"%s" [%s]'):format(req.c_name, req.c_tag))
    return id
end

-- ----------------------------------------------------------
--  Ciclu de viata
-- ----------------------------------------------------------
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    while GetResourceState(PH) ~= 'started' do Wait(200) end

    local ok, err = pcall(migrate)
    if not ok then print('^1[ph_clans] init DB:^7 ' .. tostring(err)) return end
    loadAllClans()
    ready = true

    local n = 0
    for _ in pairs(CLANS) do n = n + 1 end
    print(('^5[ph_clans]^7 ready (%d clans).'):format(n))
end)

AddEventHandler('ph-core:playerLoaded', function(src, char)
    if not (char and char.id) then return end
    local uid = char.id
    S2U[src] = uid
    local waited = 0
    while not ready and waited < 15000 do Wait(200) waited = waited + 200 end
    if not ready then return end   -- nu incarca (si nu curata) apartenenta pana clanurile nu sunt in memorie
    local m = loadMember(uid)
    pushClan(uid)

    local c = m.clan ~= 0 and CLANS[m.clan] or nil
    if c and c.active and c.motd ~= '' then
        chat(src, ('[Clan MOTD] %s'):format(c.motd), c.chatColor)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local uid = S2U[src]
    S2U[src] = nil
    if uid then
        MEMBER[uid] = nil
        INVITES[uid] = nil
    end
end)

-- Expirare clanuri pe zile
CreateThread(function()
    while true do
        Wait(Config.ExpirySweepMin * 60000)
        if ready then
            local rows = MySQL.query.await(
                'SELECT id FROM clans WHERE active = 1 AND expires_at IS NOT NULL AND expires_at <= NOW()') or {}
            for _, r in ipairs(rows) do
                MySQL.update.await('UPDATE clans SET active = 0 WHERE id = ?', { r.id })
                reloadClan(r.id)
                clog(r.id, nil, 'expired')
                for uid, m in pairs(MEMBER) do
                    if m.clan == r.id then
                        local s = srcOf(uid)
                        if s then notify(s, 'Your clan has expired. A leader must renew it or a manager must delete it.', 'error') end
                    end
                end
            end
        end
    end
end)

-- Clan Points din activitate
CreateThread(function()
    while true do
        Wait(Config.ClanPoints.tickMinutes * 60000)
        if ready then
            local perClan = {}
            for _, uid in ipairs(exports[PH]:GetOnlineUserIds() or {}) do
                local m = MEMBER[uid]
                if m and m.clan ~= 0 and CLANS[m.clan] and CLANS[m.clan].active then
                    perClan[m.clan] = (perClan[m.clan] or 0) + 1
                end
            end
            for cid, cnt in pairs(perClan) do
                local gain = cnt * Config.ClanPoints.perMemberPer10Min
                if gain > 0 then adjustSafebox(cid, 'clanPoints', gain) end
            end
        end
    end
end)

-- ==========================================================
--  FAZA 2  -  meniul /clan (NUI, 7 tab-uri)  +  vehiculele de clan
--
--  Tab-uri: Members | Vehicle | Buy Vehicles | Clan Logs | Safebox |
--           Information | Settings
--
--  Vehiculele de clan sunt entitati "mission" simple (ph_world nu le sterge),
--  cu un lacat de sofer (doar membrii pot conduce).  Randurile stau in
--  `clan_vehicles`; starea "spawned" e doar in memorie (CVLIVE).
-- ==========================================================
local CVLIVE = {}   -- [vehId] = { clanId, netId, byUid, src, spawnedAt }
local CVLAST = {}   -- [clanId] = vehId  (ultimul spawnat, folosit de /cvr)

-- ---- permisiuni ------------------------------------------
local function hasPerm(m, key)
    return m and (m.rank >= Config.RankLeader or (m.perms and m.perms[key] == true))
end
local function canVehBasic(m)   -- Spawn / Despawn / /cvr
    return m and (m.rank >= Config.InviteRank or (m.perms and m.perms.vehmgmt == true))
end
local function canVehManage(m)  -- Buy / Sell / Upgrade
    return m and (m.rank >= Config.RankCoLeader or (m.perms and m.perms.vehmgmt == true))
end

-- ---- catalog ph_vehicles --------------------------------
local function catFlat()
    local ok, l = pcall(function() return exports['ph_vehicles']:Flat() end)
    return (ok and type(l) == 'table') and l or {}
end
local function catInfo(model)
    model = tostring(model or ''):lower()
    local ok, has = pcall(function() return exports['ph_vehicles']:Has(model) end)
    if not ok or not has then return nil end
    local _, label = pcall(function() return exports['ph_vehicles']:Label(model) end)
    local _, cat   = pcall(function() return exports['ph_vehicles']:Category(model) end)
    local _, price = pcall(function() return exports['ph_vehicles']:Price(model) end)
    return {
        model = model,
        label = type(label) == 'string' and label or model,
        category = (cat == 'heli' or cat == 'boat') and cat or 'car',
        price = tonumber(price) or 0,
    }
end
local function vehPriceFor(info)
    if not info then return nil end
    if (info.price or 0) > 0 then return math.floor(info.price) end
    return math.floor(Config.VehFallbackPrice[info.category] or Config.VehFallbackPrice.car or 15000)
end

-- ---- interogari clan_vehicles ---------------------------
local function clanVehRow(vehId)
    return MySQL.single.await('SELECT * FROM clan_vehicles WHERE id = ?', { tonumber(vehId) or -1 })
end
local function clanVehRows(clanId)
    return MySQL.query.await('SELECT * FROM clan_vehicles WHERE clan_id = ? ORDER BY id', { clanId }) or {}
end
local function countClanVeh(clanId)
    return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM clan_vehicles WHERE clan_id = ?', { clanId })) or 0
end

--- zile (2 zecimale) de la un DATETIME pana acum
local function daysSince(dt)
    local y, mo, d, h, mi, s = tostring(dt or ''):match('(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)')
    if not y then return 0 end
    local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                        hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
    local dif = os.difftime(os.time(), t)
    if dif < 0 then dif = 0 end
    return math.floor(dif / 864) / 100
end

-- ---- payload pentru NUI ---------------------------------
local function buildMembers(clanId)
    local rows = MySQL.query.await([[
        SELECT id, username, clan_rank, clan_warns, clan_join, clan_perms, last_login
        FROM users WHERE clan = ? ORDER BY clan_rank DESC, username ASC
    ]], { clanId }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id     = r.id,
            name   = r.username,
            rank   = tonumber(r.clan_rank) or 0,
            warns  = tonumber(r.clan_warns) or 0,
            days   = daysSince(r.clan_join),
            lastLogin = r.last_login or nil,
            perms  = (function()
                local t = {}
                for k in tostring(r.clan_perms or ''):gmatch('[^,]+') do t[#t + 1] = k:gsub('%s', '') end
                return t
            end)(),
            online = srcOf(r.id) ~= nil,
        }
    end
    return out
end

local function buildLogs(clanId)
    local lim = math.max(1, math.min(500, math.floor(tonumber(Config.LogLimit) or 100)))
    return MySQL.query.await(
        'SELECT actor_name, action, target_name, detail, created_at FROM clan_logs '
        .. 'WHERE clan_id = ? ORDER BY id DESC LIMIT ' .. lim, { clanId }) or {}
end

local function buildVehicles(clanId)
    local out = {}
    for _, r in ipairs(clanVehRows(clanId)) do
        out[#out + 1] = {
            id       = r.id,
            model    = r.model,
            label    = r.label,
            category = r.category,
            plate    = r.plate ~= '' and r.plate or ('PH%05d'):format(r.id % 100000),
            upgrade  = tonumber(r.upgrade) or 0,
            price    = vehPriceFor(catInfo(r.model)) or 0,
            live     = CVLIVE[r.id] ~= nil,
        }
    end
    return out
end

local function clanMenuPayload(uid, m, withCatalog)
    local c = CLANS[m.clan]
    if not c then return nil end
    return {
        clan = {
            id           = c.id,
            name         = c.name,
            short        = c.short,
            tag          = c.tag,
            serverName   = Config.ServerName,
            logo         = Config.MenuLogo,
            active       = c.active,
            daysLeft     = daysLeft(c.expiresAt),
            ranks        = c.ranks,
            rankColors   = c.rankColors,
            chatColor    = c.chatColor,
            motd         = c.motd,
            chatLockRank = c.chatLockRank,
            founderName  = c.founder and nameOfUser(c.founder) or nil,
            leaderName   = c.leader and nameOfUser(c.leader) or nil,
            safebox      = { money = c.money, pp = c.pp, clanPoints = c.clanPoints },
            memberCount  = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM users WHERE clan = ?', { c.id })) or 0,
            vehCount     = countClanVeh(c.id),
        },
        role = {
            userId     = uid,
            myName     = nameOfUser(uid),
            rank       = m.rank,
            rankName   = c.ranks[m.rank] or ('Rank ' .. m.rank),
            isLeader   = m.rank >= Config.RankLeader,
            canManage  = m.rank >= Config.RankCoLeader,
            canVehBasic  = canVehBasic(m) == true,
            canVehManage = canVehManage(m) == true,
            canSettings  = m.rank >= Config.SettingsRank,
            perms      = (function()
                local t = {}
                for _, k in ipairs(Config.Perms) do if m.perms[k] then t[#t + 1] = k end end
                return t
            end)(),
            tagStyle   = m.tagStyle or 0,
        },
        members  = buildMembers(c.id),
        vehicles = buildVehicles(c.id),
        logs     = buildLogs(c.id),
        catalog  = withCatalog and catFlat() or nil,   -- doar la deschidere (lista e mare)
        cfg = {
            rankCount    = Config.RankCount,
            rankLeader   = Config.RankLeader,
            rankCoLeader = Config.RankCoLeader,
            inviteRank   = Config.InviteRank,
            warnCap      = Config.WarnCap,
            permKeys     = Config.Perms,
            tagStyles    = Config.TagStyles,
            vehMax       = Config.VehMaxPerClan,
            upgradeMax   = Config.VehUpgrade.maxLevel,
            upgradeCost  = Config.VehUpgrade.costPerLevel,
            sellPct      = Config.VehSellRefundPct,
            fallbackPrice = Config.VehFallbackPrice,
        },
    }
end

local function refresh(src, uid)
    local m = MEMBER[uid]
    if not m or m.clan == 0 then return end
    local pl = clanMenuPayload(uid, m)
    if pl then TriggerClientEvent('ph_clans:cl:menuData', src, pl) end
end

-- ---- vehicule : spawn / despawn -------------------------
local function doClanVehDespawn(vehId, reason)
    local L = CVLIVE[vehId]
    if not L then return end
    CVLIVE[vehId] = nil
    if CVLAST[L.clanId] == vehId then CVLAST[L.clanId] = nil end
    if L.netId then TriggerClientEvent('ph_clans:cl:despawnClanVehicle', -1, L.netId) end
    if reason then
        local row = clanVehRow(vehId)
        clog(L.clanId, L.byUid, 'veh_despawn', nil, row and row.label or ('#' .. vehId))
    end
end

--- cere clientului `src` sa creeze vehiculul `row` langa el
local function requestClanVehSpawn(src, uid, clanId, row)
    CVLIVE[row.id] = { clanId = clanId, netId = nil, byUid = uid, src = src, spawnedAt = os.time() }
    CVLAST[clanId] = row.id
    TriggerClientEvent('ph_clans:cl:spawnClanVehicle', src, {
        vehId    = row.id,
        clanId   = clanId,
        model    = row.model,
        plate    = row.plate ~= '' and row.plate or ('PH%05d'):format(row.id % 100000),
        props    = dec(row.props),
        upgrade  = tonumber(row.upgrade) or 0,
    })
end

-- ----------------------------------------------------------
--  /clan  ->  deschide meniul
-- ----------------------------------------------------------
RegisterNetEvent('ph_clans:sv:openMenu', function()
    local src = source
    local uid = uidOf(src)
    local m = uid and MEMBER[uid]
    if not m or m.clan == 0 then
        return exports[PH]:CmdPermError(src, 'clan member')
    end
    local c = CLANS[m.clan]
    if not c then return notify(src, 'Your clan no longer exists.', 'error') end
    if not c.active then return notify(src, 'Your clan is inactive (0 days left).', 'error') end
    if m.rank < Config.MenuMinRank then return exports[PH]:CmdPermError(src, 'clan rank ' .. Config.MenuMinRank) end
    local pl = clanMenuPayload(uid, m, true)
    if pl then TriggerClientEvent('ph_clans:cl:openMenu', src, pl) end
end)

-- ----------------------------------------------------------
--  /clan  ->  actiuni din meniu
-- ----------------------------------------------------------
RegisterNetEvent('ph_clans:sv:menu', function(p)
    local src = source
    local uid = uidOf(src)
    local m = uid and MEMBER[uid]
    if not m or m.clan == 0 then return end
    local c = CLANS[m.clan]
    if not c or not c.active then return end
    p = p or {}
    local op = p.op

    local function done(msg, kind)
        if msg then notify(src, msg, kind or 'info') end
        refresh(src, uid)
    end

    if op == 'refresh' then return refresh(src, uid) end

    -- ---------- Members / Manage ----------
    if op == 'rankUp' or op == 'rankDown' then
        if m.rank < Config.RankLeader then return done('Leader only.', 'error') end
        local target = tonumber(p.userId)
        local tm = target and MEMBER[target]
        if not tm or tm.clan ~= c.id then return done('The member must be online.', 'error') end
        if target == uid then return done('Not on yourself.', 'warning') end
        local nr = tm.rank + (op == 'rankUp' and 1 or -1)
        if nr < 1 then return done('Already at the lowest rank.', 'warning') end
        if nr >= Config.RankLeader then return done('Cannot set Leader here.', 'warning') end
        tm.rank = nr
        saveMember(target)
        clog(c.id, uid, op, target, 'rank ' .. nr)
        local ts = srcOf(target)
        if ts then notify(ts, ('Your clan rank is now: %s.'):format(c.ranks[nr] or ('Rank ' .. nr)), 'info') end
        return done('Rank updated.', 'success')

    elseif op == 'setRank' then
        -- set arbitrary rank 1..(RankLeader-1) : Leader only, target online
        if m.rank < Config.RankLeader then return done('Leader only.', 'error') end
        local target = tonumber(p.userId)
        local tm = target and MEMBER[target]
        if not tm or tm.clan ~= c.id then return done('The member must be online.', 'error') end
        if target == uid then return done('Not on yourself.', 'warning') end
        if tm.rank >= Config.RankLeader then return done('Cannot change the leader here.', 'warning') end
        local nr = math.floor(tonumber(p.rank) or 0)
        if nr < 1 or nr >= Config.RankLeader then
            return done(('Rank must be 1-%d.'):format(Config.RankLeader - 1), 'error')
        end
        if nr == tm.rank then return refresh(src, uid) end
        tm.rank = nr
        saveMember(target)
        clog(c.id, uid, 'setrank', target, 'rank ' .. nr)
        local ts = srcOf(target)
        if ts then notify(ts, ('Your clan rank is now: %s.'):format(c.ranks[nr] or ('Rank ' .. nr)), 'info') end
        return done('Rank updated.', 'success')

    elseif op == 'warn' or op == 'unwarn' then
        if not hasPerm(m, 'warn') then return done('You lack the Warn permission.', 'error') end
        local target = tonumber(p.userId)
        local tm = target and MEMBER[target]
        if not tm or tm.clan ~= c.id then return done('The member must be online.', 'error') end
        if op == 'warn' and target ~= uid and tm.rank >= m.rank then
            return done('Cannot warn an equal or higher rank.', 'error')
        end
        local nw = math.max(0, math.min(Config.WarnCap, tm.warns + (op == 'warn' and 1 or -1)))
        tm.warns = nw
        saveMember(target)
        clog(c.id, uid, op, target, ('%d/%d'):format(nw, Config.WarnCap) .. (p.reason and (' — ' .. tostring(p.reason):sub(1, 120)) or ''))
        local ts = srcOf(target)
        if ts then
            notify(ts, op == 'warn'
                and ('You received a clan warning (%d/%d)%s.'):format(nw, Config.WarnCap, p.reason and (': ' .. tostring(p.reason):sub(1, 120)) or '')
                or  ('A clan warning was removed (%d/%d).'):format(nw, Config.WarnCap), op == 'warn' and 'warning' or 'info')
        end
        return done('Updated.', 'success')

    elseif op == 'kick' then
        if not hasPerm(m, 'kick') then return done('You lack the Kick permission.', 'error') end
        local target = tonumber(p.userId)
        if not target or target == uid then return done('Invalid target.', 'warning') end
        -- tinta poate fi offline : citim rangul din DB
        local trank
        local tm = MEMBER[target]
        if tm and tm.clan == c.id then
            trank = tm.rank
        else
            local row = MySQL.single.await('SELECT clan, clan_rank FROM users WHERE id = ?', { target })
            if not row or tonumber(row.clan) ~= c.id then return done('That player is not in your clan.', 'error') end
            trank = tonumber(row.clan_rank) or 0
        end
        if trank >= m.rank then return done('Cannot kick an equal or higher rank.', 'error') end
        if trank >= Config.RankLeader then return done('Cannot kick the leader.', 'error') end
        if tm then
            tm.clan, tm.rank, tm.warns, tm.perms, tm.join = 0, 0, 0, {}, nil
            saveMember(target)
        else
            dbSetMembership(target, 0, 0)
        end
        clog(c.id, uid, 'kick', target, nameOfUser(target))
        pushClan(target)
        local ts = srcOf(target)
        if ts then notify(ts, ('You were removed from %s.'):format(c.name), 'error') end
        return done('Member kicked.', 'success')

    elseif op == 'permToggle' then
        if m.rank < Config.RankCoLeader then return done('Leader / Co-Leader only.', 'error') end
        local target = tonumber(p.userId)
        local key = tostring(p.key or '')
        local valid = false
        for _, k in ipairs(Config.Perms) do if k == key then valid = true break end end
        if not valid then return done('Unknown permission.', 'warning') end
        local tm = target and MEMBER[target]
        if not tm or tm.clan ~= c.id then return done('The member must be online.', 'error') end
        if tm.rank >= m.rank then return done('Cannot change permissions of an equal or higher rank.', 'error') end
        tm.perms[key] = not tm.perms[key] or nil
        saveMember(target)
        clog(c.id, uid, 'perm', target, key .. ' = ' .. (tm.perms[key] and 'on' or 'off'))
        return done('Permission updated.', 'success')

    elseif op == 'invite' then
        if m.rank < Config.InviteRank and not m.perms.invite then
            return done('You lack the Invite permission.', 'error')
        end
        local target = tonumber(p.sqlId)
        if not target then return done('Enter a valid SQL id.', 'warning') end
        if target == uid then return done('You cannot invite yourself.', 'warning') end
        local tsrc = srcOf(target)
        if not tsrc then return done(('Player #%d is not online.'):format(target), 'error') end
        local tm = MEMBER[target]
        if tm and tm.clan ~= 0 then return done('That player is already in a clan.', 'warning') end
        if not withinRange(src, tsrc, Config.InviteRadius) then
            return done(('Player must be within %dm.'):format(math.floor(Config.InviteRadius)), 'error')
        end
        INVITES[target] = { clan = c.id, byUid = uid, byName = rpName(src), expires = os.time() + Config.InviteTimeoutSec }
        chat(tsrc, ('%s invited you to the clan %s. Type /acceptcinvite %d within %ds (stay within %dm).')
            :format(rpName(src), c.name, uid, Config.InviteTimeoutSec, math.floor(Config.InviteRadius)), '#cfc9e6')
        return done(('Invitation sent to %s.'):format(rpName(tsrc)), 'success')

    -- ---------- Settings ----------
    elseif op == 'setRankNames' or op == 'setRankColors' then
        if m.rank < Config.SettingsRank then return done('Leader / Co-Leader only.', 'error') end
        local arr = type(p.values) == 'table' and p.values or {}
        local isName = op == 'setRankNames'
        local dst = isName and c.ranks or c.rankColors
        for i = 1, Config.RankCount do
            local v = tostring(arr[i] or arr[tostring(i)] or '')
            if isName then
                v = v:gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 15)
                if v ~= '' then dst[i] = v end
            else
                if v:match('^#%x%x%x%x%x%x$') or v:match('^#%x%x%x$') then dst[i] = v:sub(1, 9) end
            end
        end
        MySQL.update('UPDATE clans SET ' .. (isName and 'ranks' or 'rank_colors') .. ' = ? WHERE id = ?', { enc(dst), c.id })
        reloadClan(c.id)
        clog(c.id, uid, isName and 'rank_names' or 'rank_colors')
        return done('Saved.', 'success')

    elseif op == 'setChatColor' then
        if m.rank < Config.SettingsRank then return done('Leader / Co-Leader only.', 'error') end
        local v = tostring(p.value or '')
        if not (v:match('^#%x%x%x%x%x%x$') or v:match('^#%x%x%x$')) then return done('Enter a hex colour like #b98cff.', 'warning') end
        c.chatColor = v:sub(1, 9)
        MySQL.update('UPDATE clans SET chat_color = ? WHERE id = ?', { c.chatColor, c.id })
        reloadClan(c.id)
        clog(c.id, uid, 'chat_color', nil, c.chatColor)
        return done('Chat colour saved.', 'success')

    elseif op == 'setMotd' then
        if m.rank < Config.SettingsRank then return done('Leader / Co-Leader only.', 'error') end
        local msg = tostring(p.value or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 200)
        c.motd = msg
        MySQL.update('UPDATE clans SET motd = ? WHERE id = ?', { msg, c.id })
        reloadClan(c.id)
        clog(c.id, uid, 'motd', nil, msg)
        if msg ~= '' then
            for _, tuid in ipairs(exports[PH]:GetOnlineUserIds() or {}) do
                local tm = MEMBER[tuid]
                if tm and tm.clan == c.id then
                    local s = srcOf(tuid)
                    if s then chat(s, ('[Clan MOTD] %s'):format(msg), c.chatColor) end
                end
            end
        end
        return done(msg == '' and 'MOTD cleared.' or 'MOTD saved.', 'success')

    elseif op == 'setChatLock' then
        if m.rank < Config.SettingsRank then return done('Leader / Co-Leader only.', 'error') end
        local n = math.max(1, math.min(Config.RankCount, math.floor(tonumber(p.value) or 1)))
        c.chatLockRank = n
        MySQL.update('UPDATE clans SET chat_lock_rank = ? WHERE id = ?', { n, c.id })
        reloadClan(c.id)
        clog(c.id, uid, 'chatlock', nil, 'rank ' .. n)
        return done(('Clan chat locked to rank %d and above.'):format(n), 'success')

    elseif op == 'setTagStyle' then   -- personal
        local n = tonumber(p.value)
        if not n or n < 1 or n > #Config.TagStyles then return done('Pick a style 1-' .. #Config.TagStyles .. '.', 'warning') end
        m.tagStyle = math.floor(n) - 1
        saveMember(uid)
        return done(('Tag style set to %d.'):format(math.floor(n)), 'success')

    -- ---------- Safebox ----------
    elseif op == 'deposit' or op == 'withdraw' then
        local kind = tostring(p.kind or ''):lower()
        local amount = math.floor(tonumber(p.amount) or 0)
        if (kind ~= 'pp' and kind ~= 'money') or amount <= 0 then return done('Enter a positive amount.', 'warning') end
        local field = kind == 'pp' and 'premiumpoints' or 'money'
        local safeKey = kind == 'pp' and 'pp' or 'money'
        if op == 'deposit' then
            local ch = exports[PH]:GetCharacter(src)
            if not ch or (tonumber(ch[field]) or 0) < amount then
                return done(('Not enough %s.'):format(kind == 'pp' and 'Premium Points' or 'money'), 'error')
            end
            local res = exports[PH]:AdjustBalance(uid, field, -amount)
            if not res or res.delta ~= -amount then
                if res and res.delta and res.delta ~= 0 then exports[PH]:AdjustBalance(uid, field, -res.delta) end
                return done('Deposit failed.', 'error')
            end
            adjustSafebox(c.id, safeKey, amount)
            clog(c.id, uid, 'deposit', nil, ('%d %s'):format(amount, kind))
            return done(('Deposited %d %s.'):format(amount, kind == 'pp' and 'PP' or '$'), 'success')
        else
            if m.rank < Config.RankLeader then return done('Leader only.', 'error') end
            if (c[safeKey] or 0) < amount then return done('The safebox does not hold that much.', 'error') end
            adjustSafebox(c.id, safeKey, -amount)
            exports[PH]:AdjustBalance(uid, field, amount)
            clog(c.id, uid, 'withdraw', nil, ('%d %s'):format(amount, kind))
            return done(('Withdrew %d %s.'):format(amount, kind == 'pp' and 'PP' or '$'), 'success')
        end

    -- ---------- Vehicle : Buy / Sell / Upgrade ----------
    elseif op == 'vehBuy' then
        if not canVehManage(m) then return done('You lack the Vehicle Management permission.', 'error') end
        local info = catInfo(p.model)
        if not info then return done('Unknown vehicle model.', 'error') end
        if countClanVeh(c.id) >= Config.VehMaxPerClan then
            return done(('Vehicle limit reached (%d).'):format(Config.VehMaxPerClan), 'error')
        end
        local price = vehPriceFor(info)
        if (c.money or 0) < price then return done(('Not enough $ in the safebox (need $%d).'):format(price), 'error') end
        adjustSafebox(c.id, 'money', -price)
        local id = MySQL.insert.await(
            'INSERT INTO clan_vehicles (clan_id, model, label, category, plate, upgrade, bought_by, bought_at) VALUES (?,?,?,?,?,0,?,NOW())',
            { c.id, info.model, info.label, info.category, '', uid })
        if id then
            MySQL.update('UPDATE clan_vehicles SET plate = ? WHERE id = ?', { ('PH%05d'):format(id % 100000), id })
        end
        clog(c.id, uid, 'veh_buy', nil, ('%s ($%d)'):format(info.label, price))
        return done(('Bought %s for $%d.'):format(info.label, price), 'success')

    elseif op == 'vehSell' then
        if not canVehManage(m) then return done('You lack the Vehicle Management permission.', 'error') end
        local row = clanVehRow(p.vehId)
        if not row or tonumber(row.clan_id) ~= c.id then return done('No such clan vehicle.', 'error') end
        if CVLIVE[row.id] then doClanVehDespawn(row.id) end
        local price = vehPriceFor(catInfo(row.model)) or 0
        local refund = math.floor(price * (Config.VehSellRefundPct or 0))
        MySQL.update.await('DELETE FROM clan_vehicles WHERE id = ?', { row.id })
        if refund > 0 then adjustSafebox(c.id, 'money', refund) end
        clog(c.id, uid, 'veh_sell', nil, ('%s (+$%d)'):format(row.label, refund))
        return done(('Sold %s. $%d refunded to the safebox.'):format(row.label, refund), 'success')

    elseif op == 'vehUpgrade' then
        if not canVehManage(m) then return done('You lack the Vehicle Management permission.', 'error') end
        local row = clanVehRow(p.vehId)
        if not row or tonumber(row.clan_id) ~= c.id then return done('No such clan vehicle.', 'error') end
        local lvl = tonumber(row.upgrade) or 0
        if lvl >= Config.VehUpgrade.maxLevel then return done('Already at the maximum upgrade level.', 'warning') end
        local cost = Config.VehUpgrade.costPerLevel
        if (c.money or 0) < cost then return done(('Not enough $ in the safebox (need $%d).'):format(cost), 'error') end
        adjustSafebox(c.id, 'money', -cost)
        MySQL.update.await('UPDATE clan_vehicles SET upgrade = ? WHERE id = ?', { lvl + 1, row.id })
        clog(c.id, uid, 'veh_upgrade', nil, ('%s -> lvl %d'):format(row.label, lvl + 1))
        if CVLIVE[row.id] then
            doClanVehDespawn(row.id)
            local fresh = clanVehRow(row.id)
            if fresh then requestClanVehSpawn(src, uid, c.id, fresh) end
        end
        return done(('Upgraded %s to level %d.'):format(row.label, lvl + 1), 'success')

    -- ---------- Vehicle : Spawn / Despawn ----------
    elseif op == 'vehSpawn' then
        if not canVehBasic(m) then return done('You lack the Vehicle permission.', 'error') end
        local row = clanVehRow(p.vehId)
        if not row or tonumber(row.clan_id) ~= c.id then return done('No such clan vehicle.', 'error') end
        if CVLIVE[row.id] then return done('That vehicle is already spawned.', 'warning') end
        requestClanVehSpawn(src, uid, c.id, row)
        clog(c.id, uid, 'veh_spawn', nil, row.label)
        return done('Spawning ' .. row.label .. '…', 'info')

    elseif op == 'vehDespawn' then
        if not canVehBasic(m) then return done('You lack the Vehicle permission.', 'error') end
        local vehId = tonumber(p.vehId)
        if not vehId or not CVLIVE[vehId] then return done('That vehicle is not spawned.', 'warning') end
        doClanVehDespawn(vehId, 'menu')
        return done('Vehicle despawned.', 'success')
    end
end)

-- clientul confirma net id-ul dupa CreateVehicle
RegisterNetEvent('ph_clans:sv:clanVehSpawned', function(vehId, netId)
    local src = source
    vehId = tonumber(vehId)
    local L = CVLIVE[vehId]
    if not L or L.src ~= src then return end
    if not netId or netId == 0 then
        CVLIVE[vehId] = nil
        if CVLAST[L.clanId] == vehId then CVLAST[L.clanId] = nil end
        return notify(src, 'The vehicle failed to spawn.', 'error')
    end
    L.netId = netId
end)

-- clientul raporteaza ca vehiculul e gol de prea mult timp
RegisterNetEvent('ph_clans:sv:vehEmpty', function(vehId)
    local src = source
    vehId = tonumber(vehId)
    local L = CVLIVE[vehId]
    if L and L.src == src then doClanVehDespawn(vehId, 'idle') end
end)

-- ----------------------------------------------------------
--  /cvr  -  Clan Vehicle Request : respawn / summon
-- ----------------------------------------------------------
RegisterNetEvent('ph_clans:sv:cvr', function()
    local src = source
    local uid = uidOf(src)
    local m = uid and MEMBER[uid]
    if not m or m.clan == 0 then return notify(src, 'You are not in a clan.', 'error') end
    local c = CLANS[m.clan]
    if not c or not c.active then return notify(src, 'Your clan is inactive.', 'error') end
    if not canVehBasic(m) then
        return exports[PH]:CmdPermError(src, 'clan rank ' .. Config.InviteRank .. ' or Vehicle permission')
    end

    -- 1) un vehicul pe care l-ai spawnat tu -> respawn langa tine (unstuck)
    local mineId
    for vehId, L in pairs(CVLIVE) do
        if L.clanId == c.id and L.byUid == uid then mineId = vehId break end
    end
    if mineId then
        local row = clanVehRow(mineId)
        doClanVehDespawn(mineId)
        if row then
            Wait(250)
            requestClanVehSpawn(src, uid, c.id, row)
            clog(c.id, uid, 'veh_cvr', nil, row.label)
            return notify(src, ('Respawning %s next to you.'):format(row.label), 'info')
        end
        return
    end

    -- 2) altfel : spawneaza ultimul vehicul folosit de clan
    local lastId = CVLAST[c.id]
    local row = lastId and clanVehRow(lastId)
    if not row then row = clanVehRows(c.id)[1] end
    if not row then return notify(src, 'Your clan has no vehicles. Buy one from /clan.', 'error') end
    if CVLIVE[row.id] then return notify(src, ('%s is already spawned.'):format(row.label), 'warning') end
    requestClanVehSpawn(src, uid, c.id, row)
    clog(c.id, uid, 'veh_cvr', nil, row.label)
    notify(src, ('Spawning %s.'):format(row.label), 'info')
end)

-- curata vehiculele spawnate de un jucator care pleaca
AddEventHandler('playerDropped', function()
    local src = source
    for vehId, L in pairs(CVLIVE) do
        if L.src == src then doClanVehDespawn(vehId) end
    end
end)

-- la stergerea unui clan (staff /editclan days 0 -> inactiv) NU se sterg
-- vehiculele; ele redevin utile daca managerul reactiveaza clanul.

-- ----------------------------------------------------------
--  Namespace pentru clan_cmd.lua
-- ----------------------------------------------------------
CLANENV = {
    PH            = PH,
    CLANS         = CLANS,
    MEMBER        = MEMBER,
    INVITES       = INVITES,
    isReady       = function() return ready end,
    uidOf         = uidOf,
    srcOf         = srcOf,
    pushClan      = pushClan,
    notify        = notify,
    chat          = chat,
    rpName        = rpName,
    nameOfUser    = nameOfUser,
    staffAtLeast  = staffAtLeast,
    withinRange   = withinRange,
    daysLeft      = daysLeft,
    clog          = clog,
    clanChat      = clanChat,
    loadMember    = loadMember,
    saveMember    = saveMember,
    dbSetMembership = dbSetMembership,
    reloadClan    = reloadClan,
    adjustSafebox = adjustSafebox,
    createClanFromRequest = createClanFromRequest,
}

-- ----------------------------------------------------------
--  Exports
-- ----------------------------------------------------------
exports('DecorateName', function(userId, baseName)
    baseName = tostring(baseName or '')
    local m = MEMBER[tonumber(userId) or -1]
    if not m or m.clan == 0 then return baseName end
    local c = CLANS[m.clan]
    if not c or not c.active or c.tag == '' then return baseName end
    local style = Config.TagStyles[(m.tagStyle or 0) + 1] or Config.TagStyles[1]
    return (style:gsub('%%([ts])', function(k) return k == 't' and c.tag or baseName end))
end)

exports('GetClan',       function(userId) local m = MEMBER[tonumber(userId) or -1]; return m and m.clan or 0 end)
exports('GetClanRank',   function(userId) local m = MEMBER[tonumber(userId) or -1]; return m and m.rank or 0 end)
exports('IsClanMember',  function(userId, clanId) local m = MEMBER[tonumber(userId) or -1]; return m ~= nil and m.clan == tonumber(clanId) end)
exports('GetClanName',   function(clanId) local c = CLANS[tonumber(clanId) or -1]; return c and c.name or nil end)
exports('GetClanData',   function(clanId) return CLANS[tonumber(clanId) or -1] end)
exports('GetSafebox',    function(clanId)
    local c = CLANS[tonumber(clanId) or -1]
    if not c then return nil end
    return { money = c.money, pp = c.pp, clanPoints = c.clanPoints }
end)
exports('AdjustSafebox', function(clanId, field, delta) return adjustSafebox(clanId, field, delta) end)

--- lista vehiculelor unui clan (pentru un viitor dealership de clan)
exports('GetClanVehicles', function(clanId)
    return MySQL.query.await('SELECT id, model, label, category, plate, upgrade FROM clan_vehicles WHERE clan_id = ? ORDER BY id',
        { tonumber(clanId) or -1 }) or {}
end)
