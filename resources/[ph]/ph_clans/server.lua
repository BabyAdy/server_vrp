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
