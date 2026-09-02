-- ==========================================================
--  staff_menu / server
-- ==========================================================
local PH_CORE = 'ph-core'
local ready = false
local startTime = os.time()

local frozen = {}      -- [userId] = bool  (SQL id, nu session id)
local S2U    = {}      -- [src] = userId  (cache pentru curatenie la disconnect)
local banCache = {}    -- [license] = { id, reason, expires_at }
local GODMODE = {}     -- [userId] = true  (Home -> God Mode)
local INVIS   = {}     -- [userId] = true  (Home -> Invisible)
local pushNoclip       -- forward-declarat; definit mai jos (folosit si in staff_menu:sv:dev)

-- ----------------------------------------------------------
--  DB
-- ----------------------------------------------------------
local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `tickets` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `user_id` INT UNSIGNED NOT NULL,
      `username` VARCHAR(24) NOT NULL,
      `category` VARCHAR(32) NOT NULL DEFAULT 'general',
      `message` TEXT NOT NULL,
      `status` ENUM('open','active','closed') NOT NULL DEFAULT 'open',
      `assigned_to` INT UNSIGNED NULL,
      `assigned_name` VARCHAR(24) NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      `closed_at` TIMESTAMP NULL DEFAULT NULL,
      PRIMARY KEY (`id`), KEY `idx_tickets_status` (`status`), KEY `idx_tickets_assigned` (`assigned_to`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    [[CREATE TABLE IF NOT EXISTS `ticket_replies` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `ticket_id` INT UNSIGNED NOT NULL,
      `author_id` INT UNSIGNED NOT NULL,
      `author_name` VARCHAR(24) NOT NULL,
      `is_staff` TINYINT(1) NOT NULL DEFAULT 0,
      `message` TEXT NOT NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), KEY `idx_replies_ticket` (`ticket_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    [[CREATE TABLE IF NOT EXISTS `staff_logs` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `staff_id` INT UNSIGNED NOT NULL,
      `staff_name` VARCHAR(24) NOT NULL,
      `action` VARCHAR(32) NOT NULL,
      `target_id` INT UNSIGNED NULL,
      `target_name` VARCHAR(24) NULL,
      `detail` TEXT NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), KEY `idx_logs_staff` (`staff_id`), KEY `idx_logs_action` (`action`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    [[CREATE TABLE IF NOT EXISTS `bans` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `user_id` INT UNSIGNED NULL,
      `license` VARCHAR(64) NOT NULL,
      `username` VARCHAR(24) NULL,
      `reason` TEXT NOT NULL,
      `banned_by` INT UNSIGNED NULL,
      `banned_by_name` VARCHAR(24) NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      `expires_at` BIGINT UNSIGNED NULL,
      `active` TINYINT(1) NOT NULL DEFAULT 1,
      PRIMARY KEY (`id`), KEY `idx_bans_license` (`license`), KEY `idx_bans_active` (`active`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    [[CREATE TABLE IF NOT EXISTS `warns` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `user_id` INT UNSIGNED NOT NULL,
      `username` VARCHAR(24) NOT NULL,
      `reason` TEXT NOT NULL,
      `warned_by` INT UNSIGNED NULL,
      `warned_by_name` VARCHAR(24) NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), KEY `idx_warns_user` (`user_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    [[CREATE TABLE IF NOT EXISTS `chat_logs` (
      `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      `user_id` INT UNSIGNED NULL,
      `username` VARCHAR(24) NOT NULL,
      `message` VARCHAR(300) NOT NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), KEY `idx_chatlogs_user` (`user_id`), KEY `idx_chatlogs_time` (`created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],
}

local function loadBans()
    banCache = {}
    local rows = MySQL.query.await('SELECT id, license, reason, expires_at FROM bans WHERE active = 1') or {}
    for _, b in ipairs(rows) do
        banCache[b.license] = {
            id = b.id,
            reason = b.reason,
            expires_at = b.expires_at and tonumber(b.expires_at) or nil,
        }
    end
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(250) end
    while GetResourceState(PH_CORE) ~= 'started' do Wait(250) end
    Wait(2500) -- lasa ph-core sa creeze tabelul `users`

    local ok, err = pcall(function()
        for _, q in ipairs(SCHEMA) do MySQL.query.await(q) end
    end)
    if not ok then
        print('^1[staff_menu] database init error:^7 ' .. tostring(err))
        return
    end

    loadBans()
    ready = true
    print('^5[staff_menu]^7 ready.')
end)

-- ----------------------------------------------------------
--  Ban check (apelat de ph-core in playerConnecting)
-- ----------------------------------------------------------
exports('CheckBan', function(license)
    local b = banCache[license]
    if not b then return nil end
    if b.expires_at and os.time() >= b.expires_at then
        banCache[license] = nil
        MySQL.update('UPDATE bans SET active = 0 WHERE id = ?', { b.id })
        return nil
    end
    return b
end)

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function charOf(src) return exports[PH_CORE]:GetCharacter(src) end
local function rankIdx(src) return exports[PH_CORE]:GetStaffRank(src) or 0 end

local function can(src, permKey)
    local need = Config.Perms[permKey]
    if not need then return false end
    return exports[PH_CORE]:HasStaffRank(src, need) == true
end

--- can() + trimite "ERROR: insufficient permission ( #grad )" daca nu are
local function requirePerm(src, permKey)
    if src == 0 then return true end
    if can(src, permKey) then return true end
    exports[PH_CORE]:CmdPermError(src, Config.Perms[permKey] or permKey)
    return false
end

local function notify(src, text, color)
    if not src then return end
    if GetResourceState('ph_chat') == 'started' then
        exports['ph_chat']:send(src, { text = text, textColor = color or '#e8e6f0' })
    else
        TriggerClientEvent('chat:addMessage', src, { args = { text } })
    end
end

--- feedback marunt pentru staff-ul care a rulat actiunea -> deasupra minimapului
local function toast(src, text, kind)
    if not src or src == 0 then print('[staff_menu] ' .. tostring(text)); return end
    exports[PH_CORE]:Notify(src, text, kind or 'info')
end

local function publics() return exports[PH_CORE]:GetPublicPlayers() or {} end

--- anunt catre tot staff-ul cu gradul >= minKey.
--- mesajul e prefixat "Staff: (staff >= <grad>) ..." ca sa fie clar
--- pentru cine e vizibil; schimba `minKey` (Config.*) ca sa restrangi audienta.
local function notifyStaff(text, color, minKey)
    minKey = minKey or Config.MinGrade
    local tagged = ('Staff: (staff >= %s) %s'):format(minKey, text)
    for psrc in pairs(publics()) do
        psrc = tonumber(psrc)
        if exports[PH_CORE]:HasStaffRank(psrc, minKey) then
            notify(psrc, tagged, color)
        end
    end
end

--- SQL id (users.id) -> session id (server id) prin maparea ph-core; nil daca e offline
local function srcByUserId(userId)
    if not userId then return nil end
    return exports[PH_CORE]:GetSource(tonumber(userId))
end

local function logAction(staffSrc, action, tName, tId, detail)
    local sc = charOf(staffSrc)
    MySQL.insert(
        'INSERT INTO staff_logs (staff_id, staff_name, action, target_id, target_name, detail) VALUES (?,?,?,?,?,?)',
        { sc and sc.id or 0, sc and sc.username or 'console', action, tId, tName,
          detail ~= nil and tostring(detail):sub(1, 300) or nil }
    )
end

--- log crud in `staff_logs` fara sa fie nevoie de un src (folosit la connect/disconnect)
local function logRaw(userId, username, action, detail)
    MySQL.insert(
        'INSERT INTO staff_logs (staff_id, staff_name, action, target_id, target_name, detail) VALUES (?,?,?,?,?,?)',
        { userId or 0, username or '?', action, userId, username,
          detail ~= nil and tostring(detail):sub(1, 300) or nil }
    )
end

-- ----------------------------------------------------------
--  Discord webhook
-- ----------------------------------------------------------
local function discordSend(title, description, color)
    local url = Config.Discord and Config.Discord.Webhook
    if type(url) ~= 'string' or url == '' then return end
    local body = {
        username   = Config.Discord.Username or 'Purple Havoc',
        avatar_url = (Config.Discord.Avatar ~= '' and Config.Discord.Avatar) or nil,
        embeds = { {
            title       = title,
            description = description,
            color       = color or 8388736,
            timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }
    PerformHttpRequest(url, function() end, 'POST', json.encode(body),
        { ['Content-Type'] = 'application/json' })
end

-- ----------------------------------------------------------
--  Anunt de conectare / deconectare pentru staff
-- ----------------------------------------------------------
local function isCrashReason(reason)
    local r = tostring(reason or ''):lower()
    for _, kw in ipairs(Config.CrashReasons or {}) do
        if r:find(kw, 1, true) then return true end
    end
    return false
end

--- kind: 'connect' | 'disconnect' | 'crash'
local function staffNotice(kind, userId, username, gradeKey, reason)
    local g = exports[PH_CORE]:GetStaffGrade(gradeKey or '')
    local gradeLabel = (g and g.label) or gradeKey or 'Staff'

    local msg
    if kind == 'connect' then
        msg = ('[%s] %s has connected to the server!'):format(gradeLabel, username)
    elseif kind == 'crash' then
        msg = ('[%s] %s was disconnected from the server! [Reason: Crash]'):format(gradeLabel, username)
    else
        msg = ('[%s] %s has disconnected from the server!'):format(gradeLabel, username)
    end

    notifyStaff(msg, '#c9a3ff', Config.NoticeMinGrade or 'trialhelper')

    logRaw(userId, username, 'notice_' .. kind,
        (reason and reason ~= '') and (tostring(reason) .. (' [ID: %s]'):format(userId))
        or (' [ID: %s]'):format(userId))

    local color = (Config.Discord.Colors or {})[kind]
    local desc = msg
    if kind == 'crash' and reason and reason ~= '' then
        desc = desc .. ('\n`%s`'):format(tostring(reason):sub(1, 200))
    end
    discordSend('Staff ' .. kind:sub(1, 1):upper() .. kind:sub(2),
        desc .. ('\n**[ID: %s]**'):format(userId), color)
end

local function playerList()
    local out = {}
    for psrc, e in pairs(publics()) do
        psrc = tonumber(psrc)
        out[#out + 1] = {
            src = psrc, id = e.id, name = e.name,
            staff = e.staff or '', staffLabel = e.staffLabel, staffColor = e.staffColor,
            ping = GetPlayerPing(psrc),
        }
    end
    table.sort(out, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return out
end

local function permMap(src)
    local m = {}
    for k in pairs(Config.Perms) do m[k] = can(src, k) end
    return m
end

-- ----------------------------------------------------------
--  Deschidere meniu
-- ----------------------------------------------------------
--- lista gradelor, ordonata de la cel mai mare la cel mai mic (Owner ... Trial Helper)
local function orderedGrades()
    local grades = exports[PH_CORE]:GetStaffGrades() or {}
    local keys = {}
    for k in pairs(grades) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        return (exports[PH_CORE]:StaffRankOf(a) or 0) > (exports[PH_CORE]:StaffRankOf(b) or 0)
    end)
    local order = {}
    for _, k in ipairs(keys) do
        order[#order + 1] = { key = k, label = grades[k].label or k, color = grades[k].color or '#b98cff' }
    end
    return order
end

RegisterNetEvent('staff_menu:sv:open', function(tab)
    local src = source
    if not ready then return toast(src, 'Staff menu is initializing...', 'warning') end
    if not exports[PH_CORE]:HasStaffRank(src, Config.MinGrade) then return end

    local sc = charOf(src)
    local g = sc and exports[PH_CORE]:GetStaffGrade(sc.staff or '') or nil
    TriggerClientEvent('staff_menu:cl:open', src, {
        server = { name = Config.ServerName, logo = Config.Logo },
        me = {
            id = sc and sc.id, name = sc and sc.username,
            staff = sc and sc.staff, rank = rankIdx(src),
            gradeLabel = g and g.label or 'Staff', gradeColor = g and g.color or '#b98cff',
        },
        tab = tab or 'home',
        perms = permMap(src),
        staffActions = Config.StaffActions,
        grades = exports[PH_CORE]:GetStaffGrades(),
        gradeList = orderedGrades(),
        clothingPieces = Config.StaffClothingPieces,
        ticketColors = Config.TicketTypeColors,
        categories = Config.TicketCategories,
        home = { god = GODMODE[sc and sc.id] == true, invis = INVIS[sc and sc.id] == true },
    })
end)

RegisterNetEvent('staff_menu:sv:players', function()
    local src = source
    if not ready or not can(src, 'tab_players') then return end
    TriggerClientEvent('staff_menu:cl:data', src, { tab = 'players', list = playerList() })
end)

-- ==========================================================
--  HOME  -  haine de staff, godmode, invisible, respawn
-- ==========================================================
RegisterNetEvent('staff_menu:sv:home', function(p)
    local src = source
    if not ready or not can(src, 'tab_home') then return end
    p = p or {}
    local sc = charOf(src)
    if not sc then return end
    local op = p.op

    local function homeState()
        TriggerClientEvent('staff_menu:cl:data', src, { tab = 'home',
            state = { god = GODMODE[sc.id] == true, invis = INVIS[sc.id] == true } })
    end

    if op == 'godmode' then
        GODMODE[sc.id] = not GODMODE[sc.id] or nil
        TriggerClientEvent('staff_menu:cl:godmode', src, GODMODE[sc.id] == true)
        toast(src, ('God Mode %s.'):format(GODMODE[sc.id] and 'ON' or 'OFF'), 'success')
        logAction(src, 'godmode', sc.username, sc.id, GODMODE[sc.id] and 'on' or 'off')
        homeState()

    elseif op == 'invis' then
        INVIS[sc.id] = not INVIS[sc.id] or nil
        local on = INVIS[sc.id] == true
        TriggerClientEvent('staff_menu:cl:invis', src, on)
        TriggerClientEvent('staff_menu:cl:invisState', -1, src, on)   -- ceilalti te ascund
        toast(src, ('Invisible %s.'):format(on and 'ON' or 'OFF'), 'success')
        logAction(src, 'invisible', sc.username, sc.id, on and 'on' or 'off')
        homeState()

    elseif op == 'respawn' then
        TriggerClientEvent('staff_menu:cl:respawn', src)
        logAction(src, 'respawn_self', sc.username, sc.id)

    elseif op == 'cloth' then
        local piece = tostring(p.pieceId or '')
        local grade = p.grade and tostring(p.grade) or (sc.staff or '')
        -- Dev Tools poate cere orice grad ; Home foloseste gradul propriu
        if p.grade and not can(src, 'tab_developer') then grade = sc.staff or '' end
        if grade == '' then return toast(src, 'You have no staff grade.', 'error') end
        local item = Config.StaffClothingItem(grade, piece)
        if GetResourceState('ph_inventory') ~= 'started' then
            return toast(src, 'Inventory is unavailable.', 'error')
        end
        local ok = exports['ph_inventory']:GiveItem(sc.id, item, 1)
        if ok then
            toast(src, ('Added "%s" to your inventory.'):format(item), 'success')
            logAction(src, 'staff_cloth', sc.username, sc.id, item)
        else
            toast(src, ('Item "%s" is not configured / inventory full.'):format(item), 'error')
        end
    end
end)

exports('IsGod',    function(userId) return GODMODE[userId] == true end)
exports('IsInvis',  function(userId) return INVIS[userId] == true end)

-- ==========================================================
--  PLAYERS  -  pagina de detalii + loguri + moderare
-- ==========================================================
local function factionInfoOf(userId)
    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT u.faction AS fid, u.faction_rank AS frank, f.f_name AS fname, f.ranks AS franks
            FROM users u LEFT JOIN factions f ON f.id = u.faction WHERE u.id = ?]], { userId })
    end)
    if not ok or not row or not row.fid or tonumber(row.fid) == 0 then
        return { name = 'None', rank = nil }
    end
    local rankName = 'Rank ' .. tostring(row.frank)
    local okj, ranks = pcall(json.decode, row.franks or '')
    if okj and type(ranks) == 'table' and ranks[tonumber(row.frank)] then
        rankName = ranks[tonumber(row.frank)]
    end
    return { name = row.fname or ('#' .. row.fid), rank = ('%s (%s)'):format(rankName, row.frank) }
end

local function playerDetail(userId)
    userId = tonumber(userId)
    if not userId then return nil end
    local u = MySQL.single.await('SELECT id, username, staff, warns FROM users WHERE id = ?', { userId })
    if not u then return nil end
    local g = u.staff ~= '' and exports[PH_CORE]:GetStaffGrade(u.staff) or nil
    local fac = factionInfoOf(userId)
    local onlineSrc = srcByUserId(userId)

    return {
        id       = u.id,
        name     = u.username,
        staff    = u.staff ~= '' and u.staff or nil,
        staffLabel = g and g.label or (u.staff ~= '' and u.staff) or 'NONE',
        staffColor = g and g.color or '#8a93a5',
        warns    = tonumber(u.warns) or 0,
        faction  = fac.name,
        factionRank = fac.rank,
        online   = onlineSrc ~= nil,
        logs = {
            warns = MySQL.query.await(
                'SELECT reason, warned_by_name, created_at FROM warns WHERE user_id = ? ORDER BY id DESC LIMIT 50', { userId }) or {},
            kicks = MySQL.query.await(
                "SELECT staff_name, detail, created_at FROM staff_logs WHERE action = 'kick' AND target_id = ? ORDER BY id DESC LIMIT 50", { userId }) or {},
            bans = MySQL.query.await(
                'SELECT reason, banned_by_name, created_at, expires_at, active FROM bans WHERE user_id = ? ORDER BY id DESC LIMIT 50', { userId }) or {},
            chats = MySQL.query.await(
                'SELECT message, created_at FROM chat_logs WHERE user_id = ? ORDER BY id DESC LIMIT 60', { userId }) or {},
        },
    }
end

RegisterNetEvent('staff_menu:sv:player', function(p)
    local src = source
    if not ready or not can(src, 'tab_players') then return end
    p = p or {}
    if p.op == 'get' then
        local d = playerDetail(p.id)
        if not d then return toast(src, ('No user with id %s.'):format(tostring(p.id)), 'error') end
        TriggerClientEvent('staff_menu:cl:data', src, { tab = 'playerDetail', detail = d })
    end
end)

-- moderare din pagina Players  (warn / kick / ban / ban_offline / unban)
RegisterNetEvent('staff_menu:sv:pmod', function(p)
    local src = source
    if not ready then return end
    p = p or {}
    local action = tostring(p.action or '')
    if not Config.Perms[action] then return end
    if not requirePerm(src, action) then return end

    local sc = charOf(src)
    if not sc then return end
    local tId = tonumber(p.targetId)
    if not tId then return toast(src, 'Invalid target.', 'error') end
    local reason = tostring(p.reason or ''):sub(1, 300)
    local days = math.max(0, math.min(Config.MaxBanDays, math.floor(tonumber(p.days) or 0)))

    local function refresh()
        local d = playerDetail(tId)
        if d then TriggerClientEvent('staff_menu:cl:data', src, { tab = 'playerDetail', detail = d }) end
    end

    -- tinta (username + license) din DB ; sursa online daca exista
    local u = MySQL.single.await('SELECT id, username, license, staff FROM users WHERE id = ?', { tId })
    if not u then return toast(src, 'No such user.', 'error') end
    local tSrc = srcByUserId(tId)
    -- protectie: nu poti actiona pe staff de rang egal/mai mare (nici pe tine)
    if u.staff and u.staff ~= '' and (exports[PH_CORE]:StaffRankOf(u.staff) or 0) >= rankIdx(src) then
        return toast(src, 'You cannot moderate staff of equal or higher rank.', 'error')
    end

    if action == 'warn' then
        if #reason < 2 then return toast(src, 'Reason too short.', 'error') end
        MySQL.insert('INSERT INTO warns (user_id, username, reason, warned_by, warned_by_name) VALUES (?,?,?,?,?)',
            { u.id, u.username, reason, sc.id, sc.username })
        MySQL.update('UPDATE users SET warns = LEAST(3, warns + 1) WHERE id = ?', { u.id })
        if tSrc then notify(tSrc, ('WARNING from %s: %s'):format(sc.username, reason), '#ff5a5a') end
        notifyStaff(('%s warned %s [ID:%s]: %s'):format(sc.username, u.username, u.id, reason), '#e0c07a')
        logAction(src, 'warn', u.username, u.id, reason)
        toast(src, ('Warned %s.'):format(u.username), 'success')

    elseif action == 'kick' then
        if not tSrc then return toast(src, 'The player is not online.', 'error') end
        if #reason < 2 then reason = 'unspecified' end
        notifyStaff(('%s kicked %s [ID:%s]: %s'):format(sc.username, u.username, u.id, reason), '#e0c07a')
        logAction(src, 'kick', u.username, u.id, reason)
        DropPlayer(tSrc, ('Kicked by %s\nReason: %s'):format(sc.username, reason))

    elseif action == 'ban' or action == 'ban_offline' then
        if action == 'ban' and not tSrc then return toast(src, 'The player is not online (use Ban Offline).', 'error') end
        if #reason < 2 then return toast(src, 'Reason too short.', 'error') end
        local expires = days > 0 and (os.time() + days * 86400) or nil
        local license = tSrc and exports[PH_CORE]:GetLicense(tSrc) or u.license
        local id = MySQL.insert.await(
            'INSERT INTO bans (user_id, license, username, reason, banned_by, banned_by_name, expires_at) VALUES (?,?,?,?,?,?,?)',
            { u.id, license, u.username, reason, sc.id, sc.username, expires })
        if license then banCache[license] = { id = id, reason = reason, expires_at = expires } end
        notifyStaff(('%s banned %s [ID:%s] (%s): %s'):format(
            sc.username, u.username, u.id, days > 0 and (days .. ' days') or 'permanent', reason), '#ff5a5a')
        logAction(src, action, u.username, u.id, ('%s | %s'):format(days > 0 and (days .. 'd') or 'perm', reason))
        if tSrc then
            DropPlayer(tSrc, ('BANNED by %s\nReason: %s\n%s\nBan ID: #%s'):format(
                sc.username, reason, expires and ('Expires: ' .. os.date('%d.%m.%Y %H:%M', expires)) or 'Permanent', id))
        end
        toast(src, ('Banned %s (#%s).'):format(u.username, id), 'success')

    elseif action == 'unban' then
        local aff = MySQL.update.await('UPDATE bans SET active = 0 WHERE user_id = ? AND active = 1', { u.id })
        loadBans()
        logAction(src, 'unban', u.username, u.id, reason ~= '' and reason or nil)
        toast(src, (aff and aff > 0) and ('Unbanned %s.'):format(u.username) or 'No active ban found.',
            (aff and aff > 0) and 'success' or 'warning')
    end

    refresh()
end)

-- ==========================================================
--  Ticket thread (vederea de staff, similara cu /ticket)
-- ==========================================================
local function ticketReplies(ticketId)
    local rows = MySQL.query.await([[
        SELECT r.author_id, r.author_name, r.is_staff, r.message, r.created_at, u.staff AS author_staff
        FROM ticket_replies r LEFT JOIN users u ON u.id = r.author_id
        WHERE r.ticket_id = ? ORDER BY r.id ASC]], { ticketId }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local isStaff = (tonumber(r.is_staff) or 0) ~= 0
        local grade
        if isStaff and r.author_staff and r.author_staff ~= '' then
            local gg = exports[PH_CORE]:GetStaffGrade(r.author_staff)
            grade = { key = r.author_staff, label = gg and gg.label or r.author_staff, color = gg and gg.color or '#37ff00' }
        end
        out[#out + 1] = {
            authorId = r.author_id, authorName = r.author_name, isStaff = isStaff,
            message = r.message, createdAt = tostring(r.created_at or ''), grade = grade,
        }
    end
    return out
end

RegisterNetEvent('staff_menu:sv:ticketThread', function(p)
    local src = source
    if not ready or not can(src, 'tab_tickets') then return end
    p = p or {}
    local id = tonumber(p.id)
    if not id then return end
    local row = MySQL.single.await('SELECT * FROM tickets WHERE id = ?', { id })
    if not row then return toast(src, 'Ticket not found.', 'error') end
    local u = row.user_id and MySQL.single.await('SELECT username, warns FROM users WHERE id = ?', { row.user_id }) or nil
    TriggerClientEvent('staff_menu:cl:data', src, { tab = 'ticketThread', thread = {
        id           = id,
        status       = row.status,
        category     = row.category,
        message      = row.message,
        createdAt    = tostring(row.created_at or ''),
        assignedId   = row.assigned_to and tonumber(row.assigned_to) or nil,
        assignedName = row.assigned_name,
        playerUserId = row.user_id and tonumber(row.user_id) or nil,
        playerName   = (u and u.username) or row.username,
        playerWarns  = u and (tonumber(u.warns) or 0) or 0,
        playerOnline = row.user_id and (srcByUserId(row.user_id) ~= nil) or false,
        replies      = ticketReplies(id),
    } })
end)

-- ----------------------------------------------------------
--  Tickete
-- ----------------------------------------------------------
--- ph_tickets detine tabelele de tickete ; daca ruleaza, delegam catre el
--- (asa firul de chat al jucatorului din /ticket se actualizeaza live).
local function tickets()
    return GetResourceState('ph_tickets') == 'started' and exports['ph_tickets'] or nil
end

local function pushTickets(src)
    local T = tickets()
    local rows = (T and T:GetOpen()) or MySQL.query.await(
        "SELECT id, user_id, username, category, message, created_at FROM tickets WHERE status='open' ORDER BY id ASC LIMIT 100") or {}
    TriggerClientEvent('staff_menu:cl:data', src, { tab = 'tickets', list = rows })
end

local function pushActive(src)
    local sc = charOf(src)
    local T = tickets()
    local rows = (T and sc and T:GetActiveFor(sc.id)) or MySQL.query.await(
        "SELECT id, user_id, username, category, message, created_at, updated_at FROM tickets WHERE status='active' AND assigned_to = ? ORDER BY updated_at DESC LIMIT 100",
        { sc and sc.id or 0 }) or {}
    TriggerClientEvent('staff_menu:cl:data', src, { tab = 'active', list = rows })
end

RegisterNetEvent('staff_menu:sv:ticket', function(p)
    local src = source
    if not ready or not can(src, 'tab_tickets') then return end
    p = p or {}
    local sc = charOf(src)
    if not sc then return end
    local op = p.op

    if op == 'list' then
        pushTickets(src)
    elseif op == 'listActive' then
        pushActive(src)
    elseif op == 'accept' then
        local id = tonumber(p.id); if not id then return end
        local T = tickets()
        if T then
            if T:Accept(src, id) then
                notifyStaff(('%s accepted ticket #%s.'):format(sc.username, id), '#a89bc7')
                logAction(src, 'ticket_accept', nil, nil, '#' .. id)
            end
        else
            local aff = MySQL.update.await(
                "UPDATE tickets SET status='active', assigned_to=?, assigned_name=? WHERE id=? AND status='open'",
                { sc.id, sc.username, id })
            if aff and aff > 0 then
                local t = MySQL.single.await('SELECT user_id FROM tickets WHERE id=?', { id })
                local psrc = t and srcByUserId(t.user_id)
                if psrc then notify(psrc, ('Your ticket #%s was picked up by %s.'):format(id, sc.username), '#8ce07a') end
                notifyStaff(('%s accepted ticket #%s.'):format(sc.username, id), '#a89bc7')
                logAction(src, 'ticket_accept', nil, nil, '#' .. id)
            end
        end
        pushTickets(src); pushActive(src)
    elseif op == 'close' then
        local id = tonumber(p.id); if not id then return end
        local T = tickets()
        if T then
            T:Close(src, id)
        else
            MySQL.update.await(
                "UPDATE tickets SET status='closed', closed_at=NOW() WHERE id=? AND status<>'closed'", { id })
            local t = MySQL.single.await('SELECT user_id FROM tickets WHERE id=?', { id })
            local psrc = t and srcByUserId(t.user_id)
            if psrc then notify(psrc, ('Your ticket #%s was closed.'):format(id), '#e0c07a') end
        end
        logAction(src, 'ticket_close', nil, nil, '#' .. id)
        pushTickets(src); pushActive(src)
    elseif op == 'reply' then
        local id = tonumber(p.id)
        local text = tostring(p.text or ''):sub(1, 300)
        if not id or #text < 1 then return end
        local T = tickets()
        if T then
            T:Reply(src, id, text, true)
        else
            MySQL.insert.await(
                'INSERT INTO ticket_replies (ticket_id, author_id, author_name, is_staff, message) VALUES (?,?,?,1,?)',
                { id, sc.id, sc.username, text })
            MySQL.update.await('UPDATE tickets SET updated_at=NOW() WHERE id=?', { id })
            local t = MySQL.single.await('SELECT user_id FROM tickets WHERE id=?', { id })
            local psrc = t and srcByUserId(t.user_id)
            if psrc then notify(psrc, ('[Ticket #%s] %s: %s'):format(id, sc.username, text), '#b98cff') end
        end
        logAction(src, 'ticket_reply', nil, nil, '#' .. id)
    elseif op == 'goto' then
        local id = tonumber(p.id); if not id then return end
        local t = MySQL.single.await('SELECT user_id FROM tickets WHERE id=?', { id })
        local psrc = t and srcByUserId(t.user_id)
        if not psrc then return toast(src, 'The player is not online.', 'error') end
        local c = GetEntityCoords(GetPlayerPed(psrc))
        TriggerClientEvent('staff_menu:cl:teleport', src, { x = c.x, y = c.y, z = c.z })
    end
end)

-- ----------------------------------------------------------
--  Actiuni de moderare
-- ----------------------------------------------------------
RegisterNetEvent('staff_menu:sv:action', function(p)
    local src = source
    if not ready then return end
    p = p or {}
    local action = p.action
    if not action or not Config.Perms[action] then return end
    if not requirePerm(src, action) then return end

    local sc = charOf(src)
    if not sc then return end

    -- actiuni fara tinta
    if action == 'announce' then
        local text = tostring(p.text or ''):sub(1, 300)
        if #text < 2 then return end
        if GetResourceState('ph_chat') == 'started' then
            exports['ph_chat']:send(-1, { prefix = 'ANNOUNCEMENT', prefixColor = '#b98cff', text = text, textColor = '#ffffff' })
        else
            TriggerClientEvent('chatMessage', -1, '[ANNOUNCEMENT]', text)
        end
        logAction(src, 'announce', nil, nil, text)
        return TriggerClientEvent('staff_menu:cl:result', src, { ok = true, msg = 'Announcement sent.' })
    end

    if action == 'unban' then
        local id = tonumber(p.banId)
        local lic = tostring(p.license or '')
        if id then
            MySQL.update.await('UPDATE bans SET active=0 WHERE id=?', { id })
        elseif lic ~= '' then
            MySQL.update.await('UPDATE bans SET active=0 WHERE license=? AND active=1', { lic })
        else
            return toast(src, 'Provide a ban ID or a license.', 'error')
        end
        loadBans()
        logAction(src, 'unban', nil, nil, id and ('#' .. id) or lic)
        return TriggerClientEvent('staff_menu:cl:result', src, { ok = true, msg = 'Unban applied.' })
    end

    -- actiuni cu tinta online (identificata prin SQL id = users.id)
    local tId   = tonumber(p.targetId)
    local tSrc  = srcByUserId(tId)
    local tChar = tSrc and charOf(tSrc) or nil
    if not tId or not tSrc or not tChar then
        return toast(src, 'The player is not online.', 'error')
    end
    if tSrc ~= src and rankIdx(tSrc) > 0 and rankIdx(tSrc) >= rankIdx(src) then
        return toast(src, 'You cannot use that on staff of equal or higher rank.', 'error')
    end

    local reason = tostring(p.reason or ''):sub(1, 300)

    if action == 'goto_player' then
        local c = GetEntityCoords(GetPlayerPed(tSrc))
        TriggerClientEvent('staff_menu:cl:teleport', src, { x = c.x, y = c.y, z = c.z })

    elseif action == 'bring_player' then
        local c = GetEntityCoords(GetPlayerPed(src))
        TriggerClientEvent('staff_menu:cl:teleport', tSrc, { x = c.x, y = c.y, z = c.z })
        notify(tSrc, 'You were brought by a staff member.', '#e0c07a')

    elseif action == 'spectate' then
        TriggerClientEvent('staff_menu:cl:spectate', src, tSrc)

    elseif action == 'freeze' then
        frozen[tId] = not frozen[tId]
        TriggerClientEvent('staff_menu:cl:freeze', tSrc, frozen[tId] == true)
        toast(src, ('%s was %s.'):format(tChar.username, frozen[tId] and 'frozen' or 'unfrozen'), 'success')

    elseif action == 'revive' then
        TriggerClientEvent('staff_menu:cl:revive', tSrc)
        toast(src, ('%s was revived.'):format(tChar.username), 'success')

    elseif action == 'heal' then
        TriggerClientEvent('staff_menu:cl:heal', tSrc)
        toast(src, ('%s was healed.'):format(tChar.username), 'success')

    elseif action == 'warn' then
        if #reason < 2 then return toast(src, 'Reason too short.', 'error') end
        MySQL.insert('INSERT INTO warns (user_id, username, reason, warned_by, warned_by_name) VALUES (?,?,?,?,?)',
            { tChar.id, tChar.username, reason, sc.id, sc.username })
        -- contorul plafonat afisat de /stats  (Info: Warns x/3)
        MySQL.update('UPDATE users SET warns = LEAST(3, warns + 1) WHERE id = ?', { tChar.id })
        notify(tSrc, ('WARNING from %s: %s'):format(sc.username, reason), '#ff5a5a')
        notifyStaff(('%s warned %s [ID:%s]: %s'):format(sc.username, tChar.username, tChar.id, reason), '#e0c07a')

    elseif action == 'kick' then
        if #reason < 2 then reason = 'unspecified' end
        notifyStaff(('%s kicked %s [ID:%s]: %s'):format(sc.username, tChar.username, tChar.id, reason), '#e0c07a')
        DropPlayer(tSrc, ('Kicked by %s\nReason: %s'):format(sc.username, reason))

    elseif action == 'ban' then
        if #reason < 2 then return toast(src, 'Reason too short.', 'error') end
        local days = math.floor(tonumber(p.days) or 0)
        if days < 0 then days = 0 end
        if days > Config.MaxBanDays then days = Config.MaxBanDays end
        local expires = days > 0 and (os.time() + days * 86400) or nil
        local license = exports[PH_CORE]:GetLicense(tSrc)

        local id = MySQL.insert.await(
            'INSERT INTO bans (user_id, license, username, reason, banned_by, banned_by_name, expires_at) VALUES (?,?,?,?,?,?,?)',
            { tChar.id, license, tChar.username, reason, sc.id, sc.username, expires })
        if license then
            banCache[license] = { id = id, reason = reason, expires_at = expires }
        end
        notifyStaff(('%s banned %s [ID:%s] (%s): %s'):format(
            sc.username, tChar.username, tChar.id, days > 0 and (days .. ' days') or 'permanent', reason), '#ff5a5a')
        DropPlayer(tSrc, ('BANNED by %s\nReason: %s\n%s\nBan ID: #%s'):format(
            sc.username, reason,
            expires and ('Expires: ' .. os.date('%d.%m.%Y %H:%M', expires)) or 'Permanent', id))
    end

    logAction(src, action, tChar.username, tChar.id, p.reason or p.days)
    TriggerClientEvent('staff_menu:cl:result', src, { ok = true })
end)

-- ----------------------------------------------------------
--  Developer
-- ----------------------------------------------------------
RegisterNetEvent('staff_menu:sv:dev', function(p)
    local src = source
    if not ready or not can(src, 'tab_developer') then return end
    p = p or {}
    local sc = charOf(src)
    if not sc then return end

    if p.op == 'set_staff' then
        if not can(src, 'set_staff') then return end
        local tId   = tonumber(p.targetId)
        local grade = tostring(p.grade or '')
        local tSrc  = srcByUserId(tId)
        local tChar = tSrc and charOf(tSrc)
        if not tChar then return toast(src, 'The player is not online.', 'error') end

        local grades = exports[PH_CORE]:GetStaffGrades() or {}
        if grade ~= '' and not grades[grade] then return toast(src, 'Invalid grade.', 'error') end
        if grade ~= '' and exports[PH_CORE]:StaffRankOf(grade) >= rankIdx(src) then
            return toast(src, 'You cannot grant a grade equal to or higher than yours.', 'error')
        end

        local ok = exports[PH_CORE]:SetStaff(tSrc, grade)
        toast(src, ok and ('Grade set: %s -> %q'):format(tChar.username, grade) or 'Error.', ok and 'success' or 'error')
        logAction(src, 'set_staff', tChar.username, tChar.id, grade)
        if ok then pushNoclip(tSrc) end   -- re-evalueaza dreptul de noclip
        TriggerClientEvent('staff_menu:cl:result', src, { ok = ok })

    elseif p.op == 'restart_resource' then
        if not can(src, 'restart_resource') then return end
        local rname = tostring(p.name or ''):match('^[%w_%-]+$')
        if not rname then return toast(src, 'Invalid resource name.', 'error') end
        ExecuteCommand(('ensure %s'):format(rname))
        toast(src, ('ensure %s sent.'):format(rname), 'success')
        logAction(src, 'restart_resource', nil, nil, rname)

    elseif p.op == 'tp_coords' then
        if not can(src, 'tp_coords') then return end
        local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
        if not (x and y and z) then return toast(src, 'Invalid coordinates.', 'error') end
        TriggerClientEvent('staff_menu:cl:teleport', src, { x = x, y = y, z = z })

    elseif p.op == 'server_info' then
        if not can(src, 'server_info') then return end
        TriggerClientEvent('staff_menu:cl:data', src, { tab = 'developer', info = {
            uptime = os.time() - startTime,
            players = #GetPlayers(),
            maxPlayers = GetConvarInt('sv_maxClients', 48),
            resources = GetNumResources(),
        }})
    end
end)

-- ----------------------------------------------------------
--  Noclip: permisiune (staff >= Config.Noclip.MinGrade)
-- ----------------------------------------------------------
function pushNoclip(src)
    local grade = (Config.Noclip and Config.Noclip.MinGrade) or 'trialadmin'
    local allowed = exports[PH_CORE]:HasStaffRank(src, grade) == true
    TriggerClientEvent('staff_menu:cl:noclip', src, allowed)
end

RegisterNetEvent('staff_menu:sv:reqNoclip', function()
    pushNoclip(source)
end)

local noclipOn = {}   -- [src] = true  (cine e in noclip acum)

--- log + broadcast: ceilalti clienti ascund jucatorul din noclip
RegisterNetEvent('staff_menu:sv:noclip', function(on)
    local src = source
    local grade = (Config.Noclip and Config.Noclip.MinGrade) or 'trialadmin'
    if not (exports[PH_CORE]:HasStaffRank(src, grade)) then return end
    on = on == true
    noclipOn[src] = on or nil
    local sc = charOf(src)
    logRaw(sc and sc.id, sc and sc.username, on and 'noclip_on' or 'noclip_off', nil)
    TriggerClientEvent('staff_menu:cl:noclipState', -1, src, on)
end)

--- un client care intra tarziu primeste lista celor deja in noclip
RegisterNetEvent('staff_menu:sv:reqNoclipList', function()
    local src = source
    for osrc in pairs(noclipOn) do
        TriggerClientEvent('staff_menu:cl:noclipState', src, osrc, true)
    end
end)

--- ... si lista staff-ului invizibil (Home -> Invisible)
RegisterNetEvent('staff_menu:sv:reqInvisList', function()
    local src = source
    for uid in pairs(INVIS) do
        local osrc = srcByUserId(uid)
        if osrc then TriggerClientEvent('staff_menu:cl:invisState', src, osrc, true) end
    end
end)

-- ----------------------------------------------------------
--  Conectare / deconectare: cache local + anunturi de staff
-- ----------------------------------------------------------
AddEventHandler('ph-core:playerLoaded', function(src, char)
    if not (char and char.id) then return end
    S2U[src] = { id = char.id, name = char.username, staff = char.staff or '' }
    pushNoclip(src)

    -- anunt de staff doar daca cel care se conecteaza e staff >= NoticeMinGrade
    if exports[PH_CORE]:HasStaffRank(src, Config.NoticeMinGrade or 'trialhelper') then
        staffNotice('connect', char.id, char.username, char.staff)
    end
end)

AddEventHandler('playerDropped', function(reason)
    if noclipOn[source] then
        noclipOn[source] = nil
        TriggerClientEvent('staff_menu:cl:noclipState', -1, source, false)
    end

    local rec = S2U[source]
    S2U[source] = nil
    if not rec then return end

    frozen[rec.id] = nil
    GODMODE[rec.id] = nil
    if INVIS[rec.id] then
        INVIS[rec.id] = nil
        TriggerClientEvent('staff_menu:cl:invisState', -1, source, false)
    end

    -- anunt de staff doar daca cel care pleaca era staff >= NoticeMinGrade
    local minRank = exports[PH_CORE]:StaffRankOf(Config.NoticeMinGrade or 'trialhelper') or 0
    local rank    = exports[PH_CORE]:StaffRankOf(rec.staff or '') or 0
    if minRank > 0 and rank >= minRank then
        local kind = isCrashReason(reason) and 'crash' or 'disconnect'
        staffNotice(kind, rec.id, rec.name, rec.staff, reason)
    end
end)

-- ----------------------------------------------------------
--  Chat logs  (pentru pagina Players -> "Chat Logs")
--  ph_chat declanseaza `chatMessage` pe server la fiecare mesaj public.
-- ----------------------------------------------------------
AddEventHandler('chatMessage', function(src, _name, msg)
    if not ready or type(msg) ~= 'string' then return end
    if msg == '' or msg:sub(1, 1) == '/' then return end
    local sc = charOf(src)
    MySQL.insert('INSERT INTO chat_logs (user_id, username, message) VALUES (?,?,?)',
        { sc and sc.id or nil, (sc and sc.username) or tostring(_name or '?'):sub(1, 24), msg:sub(1, 300) })
end)

CreateThread(function()
    while true do
        Wait(3600000)   -- o data pe ora
        if ready then
            pcall(function()
                MySQL.query('DELETE FROM chat_logs WHERE created_at < (NOW() - INTERVAL 14 DAY)')
            end)
        end
    end
end)

-- ----------------------------------------------------------
--  Expus pentru  staff_cmd.lua  (toate comenzile / ale resursei).
--  Fisierele din aceeasi resursa impart mediul GLOBAL, dar nu si local-urile,
--  deci helperele de care au nevoie comenzile se dau printr-un tabel global.
-- ----------------------------------------------------------
SMENV = {
    charOf       = charOf,
    notify       = notify,
    notifyStaff  = notifyStaff,
    toast        = toast,
    requirePerm  = requirePerm,
    srcByUserId  = srcByUserId,
    logRaw       = logRaw,
    isReady      = function() return ready end,
}
