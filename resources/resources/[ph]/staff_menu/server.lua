-- ==========================================================
--  staff_menu / server
-- ==========================================================
local PH_CORE = 'ph-core'
local ready = false
local startTime = os.time()

local frozen = {}      -- [userId] = bool  (SQL id, nu session id)
local S2U    = {}      -- [src] = userId  (cache pentru curatenie la disconnect)
local banCache = {}    -- [license] = { id, reason, expires_at }
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
        print('^1[staff_menu] eroare la initializarea bazei de date:^7 ' .. tostring(err))
        return
    end

    loadBans()
    ready = true
    print('^5[staff_menu]^7 pregatit.')
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

local function notify(src, text, color)
    if not src then return end
    if GetResourceState('ph_chat') == 'started' then
        exports['ph_chat']:send(src, { text = text, textColor = color or '#e8e6f0' })
    else
        TriggerClientEvent('chat:addMessage', src, { args = { text } })
    end
end

local function publics() return exports[PH_CORE]:GetPublicPlayers() or {} end

local function notifyStaff(text, color, minKey)
    minKey = minKey or Config.MinGrade
    for psrc in pairs(publics()) do
        psrc = tonumber(psrc)
        if exports[PH_CORE]:HasStaffRank(psrc, minKey) then
            notify(psrc, text, color)
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
        msg = ('Staff Notice: [%s] %s has connected to the server!'):format(gradeLabel, username)
    elseif kind == 'crash' then
        msg = ('Staff Notice: [%s] %s was disconnected from the server! [Reason: Crash]'):format(gradeLabel, username)
    else
        msg = ('Staff Notice: [%s] %s has disconnected from the server!'):format(gradeLabel, username)
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
RegisterNetEvent('staff_menu:sv:open', function()
    local src = source
    if not ready then return notify(src, 'staff_menu se initializeaza...', '#e07a7a') end
    if not exports[PH_CORE]:HasStaffRank(src, Config.MinGrade) then return end

    local sc = charOf(src)
    TriggerClientEvent('staff_menu:cl:open', src, {
        me = { id = sc and sc.id, name = sc and sc.username, staff = sc and sc.staff, rank = rankIdx(src) },
        perms = permMap(src),
        staffActions = Config.StaffActions,
        grades = exports[PH_CORE]:GetStaffGrades(),
        categories = Config.TicketCategories,
    })
end)

RegisterNetEvent('staff_menu:sv:players', function()
    local src = source
    if not ready or not can(src, 'tab_players') then return end
    TriggerClientEvent('staff_menu:cl:data', src, { tab = 'players', list = playerList() })
end)

-- ----------------------------------------------------------
--  Tickete
-- ----------------------------------------------------------
local function pushTickets(src)
    local rows = MySQL.query.await(
        "SELECT id, user_id, username, category, message, created_at FROM tickets WHERE status='open' ORDER BY id ASC LIMIT 100") or {}
    TriggerClientEvent('staff_menu:cl:data', src, { tab = 'tickets', list = rows })
end

local function pushActive(src)
    local sc = charOf(src)
    local rows = MySQL.query.await(
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
        local aff = MySQL.update.await(
            "UPDATE tickets SET status='active', assigned_to=?, assigned_name=? WHERE id=? AND status='open'",
            { sc.id, sc.username, id })
        if aff and aff > 0 then
            local t = MySQL.single.await('SELECT user_id FROM tickets WHERE id=?', { id })
            local psrc = t and srcByUserId(t.user_id)
            if psrc then notify(psrc, ('Tichetul tau #%s a fost preluat de %s.'):format(id, sc.username), '#8ce07a') end
            notifyStaff(('%s a acceptat tichetul #%s.'):format(sc.username, id), '#a89bc7')
            logAction(src, 'ticket_accept', nil, nil, '#' .. id)
        end
        pushTickets(src); pushActive(src)
    elseif op == 'close' then
        local id = tonumber(p.id); if not id then return end
        MySQL.update.await(
            "UPDATE tickets SET status='closed', closed_at=NOW() WHERE id=? AND status<>'closed'", { id })
        local t = MySQL.single.await('SELECT user_id FROM tickets WHERE id=?', { id })
        local psrc = t and srcByUserId(t.user_id)
        if psrc then notify(psrc, ('Tichetul tau #%s a fost inchis.'):format(id), '#e0c07a') end
        logAction(src, 'ticket_close', nil, nil, '#' .. id)
        pushTickets(src); pushActive(src)
    elseif op == 'reply' then
        local id = tonumber(p.id)
        local text = tostring(p.text or ''):sub(1, 300)
        if not id or #text < 1 then return end
        MySQL.insert.await(
            'INSERT INTO ticket_replies (ticket_id, author_id, author_name, is_staff, message) VALUES (?,?,?,1,?)',
            { id, sc.id, sc.username, text })
        MySQL.update.await('UPDATE tickets SET updated_at=NOW() WHERE id=?', { id })
        local t = MySQL.single.await('SELECT user_id FROM tickets WHERE id=?', { id })
        local psrc = t and srcByUserId(t.user_id)
        if psrc then notify(psrc, ('[Tichet #%s] %s: %s'):format(id, sc.username, text), '#b98cff') end
        logAction(src, 'ticket_reply', nil, nil, '#' .. id)
    elseif op == 'goto' then
        local id = tonumber(p.id); if not id then return end
        local t = MySQL.single.await('SELECT user_id FROM tickets WHERE id=?', { id })
        local psrc = t and srcByUserId(t.user_id)
        if not psrc then return notify(src, 'Jucatorul nu este online.', '#e07a7a') end
        local c = GetEntityCoords(GetPlayerPed(psrc))
        TriggerClientEvent('staff_menu:cl:teleport', src, { x = c.x, y = c.y, z = c.z })
    end
end)

-- ----------------------------------------------------------
--  /ticket  (jucatori)
-- ----------------------------------------------------------
local function inList(t, v)
    for _, x in ipairs(t) do if x == v then return true end end
    return false
end

RegisterCommand('ticket', function(src, args)
    if src == 0 then return end
    local char = charOf(src)
    if not char then return notify(src, 'Nu esti autentificat.', '#e07a7a') end

    local category = 'general'
    if args[1] and inList(Config.TicketCategories, args[1]:lower()) then
        category = table.remove(args, 1):lower()
    end
    local msg = table.concat(args, ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #msg < 3 then
        return notify(src, 'Foloseste: /ticket [categorie] <mesajul tau>', '#e07a7a')
    end

    if not ready then return notify(src, 'Sistemul de tickete nu e pregatit.', '#e07a7a') end

    local open = MySQL.scalar.await(
        "SELECT id FROM tickets WHERE user_id = ? AND status IN ('open','active') LIMIT 1", { char.id })
    if open then
        return notify(src, ('Ai deja un tichet deschis (#%s).'):format(open), '#e0c07a')
    end

    local id = MySQL.insert.await(
        'INSERT INTO tickets (user_id, username, category, message) VALUES (?,?,?,?)',
        { char.id, char.username, category, msg:sub(1, 500) })

    notify(src, ('Tichet #%s creat (%s). Un membru al staff-ului te va contacta.'):format(id, category), '#8ce07a')
    notifyStaff(('[TICHET] #%s (%s) de la %s [ID: %s]: %s'):format(
        id, category, char.username, char.id, msg:sub(1, 120)), '#b98cff')
end, false)

-- ----------------------------------------------------------
--  Actiuni de moderare
-- ----------------------------------------------------------
RegisterNetEvent('staff_menu:sv:action', function(p)
    local src = source
    if not ready then return end
    p = p or {}
    local action = p.action
    if not action or not Config.Perms[action] then return end
    if not can(src, action) then
        return notify(src, 'Nu ai permisiunea pentru aceasta actiune.', '#e07a7a')
    end

    local sc = charOf(src)
    if not sc then return end

    -- actiuni fara tinta
    if action == 'announce' then
        local text = tostring(p.text or ''):sub(1, 300)
        if #text < 2 then return end
        if GetResourceState('ph_chat') == 'started' then
            exports['ph_chat']:send(-1, { prefix = 'ANUNT', prefixColor = '#b98cff', text = text, textColor = '#ffffff' })
        else
            TriggerClientEvent('chatMessage', -1, '[ANUNT]', text)
        end
        logAction(src, 'announce', nil, nil, text)
        return TriggerClientEvent('staff_menu:cl:result', src, { ok = true, msg = 'Anunt trimis.' })
    end

    if action == 'unban' then
        local id = tonumber(p.banId)
        local lic = tostring(p.license or '')
        if id then
            MySQL.update.await('UPDATE bans SET active=0 WHERE id=?', { id })
        elseif lic ~= '' then
            MySQL.update.await('UPDATE bans SET active=0 WHERE license=? AND active=1', { lic })
        else
            return notify(src, 'Da un ID de ban sau o licenta.', '#e07a7a')
        end
        loadBans()
        logAction(src, 'unban', nil, nil, id and ('#' .. id) or lic)
        return TriggerClientEvent('staff_menu:cl:result', src, { ok = true, msg = 'Unban aplicat.' })
    end

    -- actiuni cu tinta online (identificata prin SQL id = users.id)
    local tId   = tonumber(p.targetId)
    local tSrc  = srcByUserId(tId)
    local tChar = tSrc and charOf(tSrc) or nil
    if not tId or not tSrc or not tChar then
        return notify(src, 'Jucatorul nu este online.', '#e07a7a')
    end
    if tSrc ~= src and rankIdx(tSrc) > 0 and rankIdx(tSrc) >= rankIdx(src) then
        return notify(src, 'Nu poti aplica asta pe un staff de rang egal sau superior.', '#e07a7a')
    end

    local reason = tostring(p.reason or ''):sub(1, 300)

    if action == 'goto_player' then
        local c = GetEntityCoords(GetPlayerPed(tSrc))
        TriggerClientEvent('staff_menu:cl:teleport', src, { x = c.x, y = c.y, z = c.z })

    elseif action == 'bring_player' then
        local c = GetEntityCoords(GetPlayerPed(src))
        TriggerClientEvent('staff_menu:cl:teleport', tSrc, { x = c.x, y = c.y, z = c.z })
        notify(tSrc, 'Ai fost adus de un membru al staff-ului.', '#e0c07a')

    elseif action == 'spectate' then
        TriggerClientEvent('staff_menu:cl:spectate', src, tSrc)

    elseif action == 'freeze' then
        frozen[tId] = not frozen[tId]
        TriggerClientEvent('staff_menu:cl:freeze', tSrc, frozen[tId] == true)
        notify(src, ('%s a fost %s.'):format(tChar.username, frozen[tId] and 'inghetat' or 'dezghetat'), '#8ce07a')

    elseif action == 'revive' then
        TriggerClientEvent('staff_menu:cl:revive', tSrc)
        notify(src, ('%s a fost resuscitat.'):format(tChar.username), '#8ce07a')

    elseif action == 'heal' then
        TriggerClientEvent('staff_menu:cl:heal', tSrc)
        notify(src, ('%s a fost vindecat.'):format(tChar.username), '#8ce07a')

    elseif action == 'warn' then
        if #reason < 2 then return notify(src, 'Motiv prea scurt.', '#e07a7a') end
        MySQL.insert('INSERT INTO warns (user_id, username, reason, warned_by, warned_by_name) VALUES (?,?,?,?,?)',
            { tChar.id, tChar.username, reason, sc.id, sc.username })
        notify(tSrc, ('AVERTISMENT de la %s: %s'):format(sc.username, reason), '#ff5a5a')
        notifyStaff(('%s a dat warn lui %s [ID:%s]: %s'):format(sc.username, tChar.username, tChar.id, reason), '#e0c07a')

    elseif action == 'kick' then
        if #reason < 2 then reason = 'nespecificat' end
        notifyStaff(('%s a dat kick lui %s [ID:%s]: %s'):format(sc.username, tChar.username, tChar.id, reason), '#e0c07a')
        DropPlayer(tSrc, ('Kick de %s\nMotiv: %s'):format(sc.username, reason))

    elseif action == 'ban' then
        if #reason < 2 then return notify(src, 'Motiv prea scurt.', '#e07a7a') end
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
        notifyStaff(('%s a banat pe %s [ID:%s] (%s): %s'):format(
            sc.username, tChar.username, tChar.id, days > 0 and (days .. ' zile') or 'permanent', reason), '#ff5a5a')
        DropPlayer(tSrc, ('BANAT de %s\nMotiv: %s\n%s\nID ban: #%s'):format(
            sc.username, reason,
            expires and ('Expira: ' .. os.date('%d.%m.%Y %H:%M', expires)) or 'Permanent', id))
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
        if not tChar then return notify(src, 'Jucatorul nu este online.', '#e07a7a') end

        local grades = exports[PH_CORE]:GetStaffGrades() or {}
        if grade ~= '' and not grades[grade] then return notify(src, 'Grad invalid.', '#e07a7a') end
        if grade ~= '' and exports[PH_CORE]:StaffRankOf(grade) >= rankIdx(src) then
            return notify(src, 'Nu poti acorda un grad egal sau superior tie.', '#e07a7a')
        end

        local ok = exports[PH_CORE]:SetStaff(tSrc, grade)
        notify(src, ok and ('Grad setat: %s -> %q'):format(tChar.username, grade) or 'Eroare.', ok and '#8ce07a' or '#e07a7a')
        logAction(src, 'set_staff', tChar.username, tChar.id, grade)
        if ok then pushNoclip(tSrc) end   -- re-evalueaza dreptul de noclip
        TriggerClientEvent('staff_menu:cl:result', src, { ok = ok })

    elseif p.op == 'restart_resource' then
        if not can(src, 'restart_resource') then return end
        local rname = tostring(p.name or ''):match('^[%w_%-]+$')
        if not rname then return notify(src, 'Nume de resursa invalid.', '#e07a7a') end
        ExecuteCommand(('ensure %s'):format(rname))
        notify(src, ('ensure %s trimis.'):format(rname), '#8ce07a')
        logAction(src, 'restart_resource', nil, nil, rname)

    elseif p.op == 'tp_coords' then
        if not can(src, 'tp_coords') then return end
        local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
        if not (x and y and z) then return notify(src, 'Coordonate invalide.', '#e07a7a') end
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

    -- anunt de staff doar daca cel care pleaca era staff >= NoticeMinGrade
    local minRank = exports[PH_CORE]:StaffRankOf(Config.NoticeMinGrade or 'trialhelper') or 0
    local rank    = exports[PH_CORE]:StaffRankOf(rec.staff or '') or 0
    if minRank > 0 and rank >= minRank then
        local kind = isCrashReason(reason) and 'crash' or 'disconnect'
        staffNotice(kind, rec.id, rec.name, rec.staff, reason)
    end
end)

-- ----------------------------------------------------------
--  /heal  si  /revive   (staff >= trialadmin)
--    fara argument -> pe tine ; cu <sqlId> -> pe jucatorul respectiv (online)
-- ----------------------------------------------------------
local function healTarget(src, args, action)
    if not can(src, action) then
        return notify(src, 'Nu ai permisiunea pentru aceasta actiune.', '#e07a7a')
    end
    local tSrc = src
    if args[1] then
        local uid = tonumber(args[1])
        tSrc = uid and srcByUserId(uid) or nil
        if not tSrc then return notify(src, 'Jucatorul nu este online.', '#e07a7a') end
    end

    TriggerClientEvent('staff_menu:cl:' .. action, tSrc)
    local sc = charOf(src)
    local tc = charOf(tSrc)
    logRaw(sc and sc.id, sc and sc.username, action, tc and ('target %s'):format(tc.id) or 'self')

    if tSrc == src then
        notify(src, action == 'heal' and 'Te-ai vindecat (100% HP).' or 'Te-ai resuscitat (100% HP).', '#8ce07a')
    else
        notify(src, ('%s: %s (100%% HP).'):format(tc and tc.username or ('#' .. args[1]),
            action == 'heal' and 'vindecat' or 'resuscitat'), '#8ce07a')
        notify(tSrc, action == 'heal'
            and 'Ai fost vindecat de un membru al staff-ului.'
            or  'Ai fost resuscitat de un membru al staff-ului.', '#8ce07a')
    end
end

RegisterCommand('heal',   function(src, args) if src ~= 0 then healTarget(src, args, 'heal') end end, false)
RegisterCommand('revive', function(src, args) if src ~= 0 then healTarget(src, args, 'revive') end end, false)

-- ----------------------------------------------------------
--  Comenzi de vehicul  (se executa pe clientul apelantului)
--    /dv        trialadmin   - sterge vehiculul in care esti / cel mai apropiat
--    /spawncar  generaladmin - spawneaza [model] descuiat + pornit
--    /fix       generaladmin - repara + porneste vehiculul
--    /flip      generaladmin - readuce vehiculul pe roti
--    /maxperf   manager      - tuneaza la maxim performanta (engine/brake/trans/susp/turbo)
--    /dvall     manager      - dupa un anunt global, sterge vehiculele neutilizate
-- ----------------------------------------------------------
local function vehCmd(src, perm, op, arg)
    if src == 0 then return end
    if not can(src, perm) then
        return notify(src, 'Nu ai permisiunea pentru aceasta comanda.', '#e07a7a')
    end
    TriggerClientEvent('staff_menu:cl:vehcmd', src, op, arg)
    local sc = charOf(src)
    logRaw(sc and sc.id, sc and sc.username, 'veh_' .. op, arg)
end

RegisterCommand('dv',      function(src)       vehCmd(src, 'dv', 'dv') end, false)
RegisterCommand('fix',     function(src)       vehCmd(src, 'fix', 'fix') end, false)
RegisterCommand('flip',    function(src)       vehCmd(src, 'flip', 'flip') end, false)
RegisterCommand('maxperf', function(src)       vehCmd(src, 'maxperf', 'maxperf') end, false)
RegisterCommand('spawncar', function(src, args)
    local model = tostring(args[1] or ''):gsub('%s', ''):lower()
    if model == '' then return notify(src, 'uz: /spawncar <model>', '#e0c07a') end
    vehCmd(src, 'spawncar', 'spawncar', model)
end, false)

-- ----------------------------------------------------------
--  /setvw <sqlId> <virtualWorld>   (staff >= trialadmin)
--    virtual world = routing bucket (0 = lumea normala)
-- ----------------------------------------------------------
RegisterCommand('setvw', function(src, args)
    if src ~= 0 and not can(src, 'setvw') then
        return notify(src, 'Nu ai permisiunea pentru aceasta comanda.', '#e07a7a')
    end
    local uid = tonumber(args[1])
    local vw  = tonumber(args[2])
    if not uid or not vw then
        return notify(src, 'uz: /setvw <sqlId> <virtualWorld>', '#e0c07a')
    end
    local tSrc = srcByUserId(uid)
    if not tSrc then return notify(src, 'Jucatorul nu este online.', '#e07a7a') end
    vw = math.max(0, math.floor(vw))
    SetPlayerRoutingBucket(tSrc, vw)
    TriggerClientEvent('staff_menu:cl:refreshDoors', tSrc)   -- re-incuie usile in noul virtual world
    local sc, tc = charOf(src), charOf(tSrc)
    logRaw(sc and sc.id, sc and sc.username, 'setvw', ('%s -> vw %d'):format(tc and tc.id or uid, vw))
    notify(src, ('%s -> virtual world %d.'):format(tc and tc.username or ('#' .. uid), vw), '#8ce07a')
    notify(tSrc, ('Ai fost mutat in virtual world %d de un membru al staff-ului.'):format(vw), '#e0c07a')
end, false)

-- /doorinfo -> pe clientul apelantului: afiseaza model + coords ale usii din apropiere
RegisterCommand('doorinfo', function(src)
    if src == 0 then return end
    if not can(src, 'doorinfo') then
        return notify(src, 'Nu ai permisiunea pentru aceasta comanda.', '#e07a7a')
    end
    TriggerClientEvent('staff_menu:cl:doorinfo', src)
end, false)

RegisterCommand('dvall', function(src)
    if src ~= 0 and not can(src, 'dvall') then
        return notify(src, 'Nu ai permisiunea pentru aceasta comanda.', '#e07a7a')
    end
    local delay = Config.DvallDelaySec or 10
    local msg = ('STAFF: In %d secunde toate vehiculele neutilizate vor fi sterse!'):format(delay)
    if GetResourceState('ph_chat') == 'started' then
        exports['ph_chat']:send(-1, { prefix = 'STAFF', prefixColor = '#ff5a5a', text = msg:gsub('^STAFF: ', ''), textColor = '#ffd6d6' })
    else
        TriggerClientEvent('chat:addMessage', -1, { args = { msg } })
    end
    local sc = charOf(src)
    logRaw(sc and sc.id, sc and sc.username, 'veh_dvall', ('delay %ds'):format(delay))
    SetTimeout(delay * 1000, function()
        TriggerClientEvent('staff_menu:cl:dvall', -1)
    end)
end, false)
