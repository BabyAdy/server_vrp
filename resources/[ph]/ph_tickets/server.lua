-- ==========================================================
--  ph_tickets / server
--
--  Autoritatea pe tabelele `tickets` + `ticket_replies`.  Totul se cheiaza pe
--  SQL id (users.id).  Staff-ul foloseste in continuare staff_menu pentru
--  accept / reply / close ; acele operatii apeleaza exporturile de aici ca
--  firul de chat al jucatorului sa se actualizeze live.
-- ==========================================================
local PH = 'ph-core'
local ready = false

local OPEN = {}   -- [userId] = true  cat timp meniul NUI e deschis la jucator
local S2U  = {}   -- [src] = userId

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function charOf(src) return exports[PH]:GetCharacter(src) end

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
    local ok, s = pcall(function() return exports[PH]:GetSource(tonumber(userId)) end)
    return (ok and s) or nil
end

local function nameOfUser(userId)
    if not userId then return nil end
    local row = MySQL.single.await('SELECT username FROM users WHERE id = ?', { userId })
    return row and row.username or nil
end

local function staffOfUser(userId)
    if not userId then return '' end
    local row = MySQL.single.await('SELECT staff FROM users WHERE id = ?', { userId })
    return (row and row.staff) or ''
end

local function gradeInfo(key)
    key = tostring(key or '')
    if key == '' then return nil end
    local ok, g = pcall(function() return exports[PH]:GetStaffGrade(key) end)
    if ok and type(g) == 'table' then
        return { key = key, label = g.label or key, color = g.color or '#37ff00' }
    end
    return { key = key, label = key, color = '#37ff00' }
end

local function notify(src, text, kind)
    if not src or src == 0 then return end
    exports[PH]:Notify(src, text, kind or 'info')
end

local function chat(src, text, color)
    if not src or src == 0 then return end
    local ok = pcall(function() exports[PH]:Msg(src, text, color) end)
    if not ok then notify(src, text, 'info') end
end

--- anunta in chat tot staff-ul online cu gradul >= minKey
local function notifyStaff(text, color, minKey)
    minKey = minKey or Config.NotifyGrade
    for _, sid in ipairs(GetPlayers()) do
        sid = tonumber(sid)
        local ok, has = pcall(function() return exports[PH]:HasStaffRank(sid, minKey) end)
        if ok and has then chat(sid, text, color or '#b98cff') end
    end
end

local function typeById(id)
    for _, t in ipairs(Config.Types) do if t.id == id then return t end end
    return nil
end
local function typeLabel(id)
    local t = typeById(id)
    return t and t.label or (id and (id:sub(1, 1):upper() .. id:sub(2)) or 'General')
end

-- ----------------------------------------------------------
--  Schema (idempotenta ; staff_menu creeaza aceleasi tabele)
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
}

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    while GetResourceState(PH) ~= 'started' do Wait(200) end
    local ok, err = pcall(function()
        for _, q in ipairs(SCHEMA) do MySQL.query.await(q) end
    end)
    if not ok then print('^1[ph_tickets] init DB:^7 ' .. tostring(err)); return end
    ready = true
    print('^5[ph_tickets]^7 ready.')
end)

-- ----------------------------------------------------------
--  Interogari
-- ----------------------------------------------------------
--- ticketul curent (open sau active) al unui jucator ; nil daca n-are
local function activeTicketRow(userId)
    return MySQL.single.await(
        "SELECT * FROM tickets WHERE user_id = ? AND status IN ('open','active') ORDER BY id DESC LIMIT 1",
        { userId })
end

local function repliesOf(ticketId)
    local rows = MySQL.query.await(
        'SELECT author_id, author_name, is_staff, message, created_at FROM ticket_replies WHERE ticket_id = ? ORDER BY id ASC',
        { ticketId }) or {}
    -- gradul autorilor de staff (un singur query)
    local staffIds, seen = {}, {}
    for _, r in ipairs(rows) do
        if (tonumber(r.is_staff) or 0) ~= 0 and r.author_id and not seen[r.author_id] then
            seen[r.author_id] = true
            staffIds[#staffIds + 1] = r.author_id
        end
    end
    local gradeByUser = {}
    if #staffIds > 0 then
        local q = ('SELECT id, staff FROM users WHERE id IN (%s)'):format(table.concat(staffIds, ','))
        for _, u in ipairs(MySQL.query.await(q) or {}) do gradeByUser[u.id] = u.staff or '' end
    end
    local out = {}
    for _, r in ipairs(rows) do
        local isStaff = (tonumber(r.is_staff) or 0) ~= 0
        out[#out + 1] = {
            authorId   = r.author_id,
            authorName = r.author_name,
            isStaff    = isStaff,
            message    = r.message,
            createdAt  = tostring(r.created_at or ''),
            grade      = isStaff and gradeInfo(gradeByUser[r.author_id]) or nil,
        }
    end
    return out
end

local function ticketPayload(row)
    if not row then return nil end
    return {
        id           = row.id,
        type         = row.category,
        typeLabel    = typeLabel(row.category),
        status       = row.status,
        message      = row.message,
        assignedId   = row.assigned_to and tonumber(row.assigned_to) or nil,
        assignedName = row.assigned_name or nil,
        assignedGrade = row.assigned_to and gradeInfo(staffOfUser(tonumber(row.assigned_to))) or nil,
        createdAt    = tostring(row.created_at or ''),
        replies      = repliesOf(row.id),
    }
end

local function buildPayload(userId, char)
    return {
        server  = { name = Config.ServerName, logo = Config.Logo },
        me      = { id = userId, name = char and char.username or nameOfUser(userId) or ('#' .. tostring(userId)) },
        types   = Config.Types,
        maxLen  = Config.MaxLen,
        poll    = Config.PollSeconds,
        ticket  = ticketPayload(activeTicketRow(userId)),
    }
end

local function pushTo(userId, action)
    local s = srcOf(userId)
    if not s then return end
    local char = charOf(s)
    TriggerClientEvent('ph_tickets:cl:' .. (action or 'data'), s, buildPayload(userId, char))
end

--- re-trimite payload-ul catre jucatorul unui ticket, daca are meniul deschis
local function refreshTicketOwner(ticketId)
    local row = MySQL.single.await('SELECT user_id FROM tickets WHERE id = ?', { tonumber(ticketId) or -1 })
    local uid = row and tonumber(row.user_id) or nil
    if uid and OPEN[uid] then pushTo(uid, 'data') end
end

-- ----------------------------------------------------------
--  /ticket  ->  deschide meniul
-- ----------------------------------------------------------
RegisterNetEvent('ph_tickets:sv:open', function()
    local src = source
    if not ready then return notify(src, 'The ticket system is still starting.', 'warning') end
    local char = charOf(src)
    local uid = char and char.id or uidOf(src)
    if not uid then return notify(src, 'You are not authenticated.', 'error') end
    OPEN[uid] = true
    TriggerClientEvent('ph_tickets:cl:open', src, buildPayload(uid, char))
end)

RegisterNetEvent('ph_tickets:sv:action', function(p)
    local src = source
    if not ready then return end
    local char = charOf(src)
    local uid = char and char.id or uidOf(src)
    if not uid then return end
    p = p or {}
    local op = p.op

    local function done(msg, kind)
        if msg then notify(src, msg, kind or 'info') end
        TriggerClientEvent('ph_tickets:cl:data', src, buildPayload(uid, char))
    end

    if op == 'refresh' then
        return TriggerClientEvent('ph_tickets:cl:data', src, buildPayload(uid, char))

    elseif op == 'create' then
        local t = typeById(tostring(p.typeId or ''))
        if not t then return done('Pick a ticket type.', 'warning') end
        local desc = tostring(p.description or ''):gsub('^%s+', ''):gsub('%s+$', '')
        if #desc < 3 then return done('Describe your issue (at least 3 characters).', 'warning') end
        desc = desc:sub(1, Config.MaxLen)
        if activeTicketRow(uid) then return done('You already have an active ticket.', 'warning') end

        local id = MySQL.insert.await(
            'INSERT INTO tickets (user_id, username, category, message) VALUES (?,?,?,?)',
            { uid, char and char.username or ('#' .. uid), t.id, desc })
        if not id then return done('Could not create the ticket.', 'error') end

        local grade = t.id == 'highstaff' and Config.HighStaffNotifyGrade or Config.NotifyGrade
        notifyStaff(('[TICKET #%s] %s from %s [ID: %s]: %s'):format(
            id, t.label, char and char.username or uid, uid, desc:sub(1, 120)), '#b98cff', grade)
        return done(('Ticket #%s created. A staff member will be with you shortly.'):format(id), 'success')

    elseif op == 'reply' then
        local row = activeTicketRow(uid)
        if not row then return done('You have no active ticket.', 'warning') end
        local text = tostring(p.text or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, Config.MaxLen)
        if #text < 1 then return end
        MySQL.insert.await(
            'INSERT INTO ticket_replies (ticket_id, author_id, author_name, is_staff, message) VALUES (?,?,?,0,?)',
            { row.id, uid, char and char.username or ('#' .. uid), text })
        MySQL.update.await('UPDATE tickets SET updated_at = NOW() WHERE id = ?', { row.id })
        -- anunta staff-ul care a acceptat
        if row.assigned_to then
            local ssrc = srcOf(row.assigned_to)
            if ssrc then chat(ssrc, ('[Ticket #%s] %s: %s'):format(row.id, char and char.username or uid, text), '#b98cff') end
        end
        return done(nil)

    elseif op == 'closeOwn' then
        local row = activeTicketRow(uid)
        if not row then return done(nil) end
        MySQL.update.await("UPDATE tickets SET status='closed', closed_at=NOW() WHERE id=? AND user_id=?", { row.id, uid })
        if row.assigned_to then
            local ssrc = srcOf(row.assigned_to)
            if ssrc then chat(ssrc, ('[Ticket #%s] closed by the player.'):format(row.id), '#e0c07a') end
        end
        return done('Ticket closed.', 'info')
    end
end)

RegisterNetEvent('ph_tickets:sv:closeMenu', function()
    local uid = uidOf(source)
    if uid then OPEN[uid] = nil end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local uid = S2U[src]
    S2U[src] = nil
    if uid then OPEN[uid] = nil end
end)

-- ==========================================================
--  Exports  -  folosite de staff_menu (accept / reply / close)
--  Toate primesc `staffSrc` (session id-ul membrului staff) si `ticketId`.
-- ==========================================================
local function staffCharId(staffSrc)
    local c = charOf(staffSrc)
    return c and c.id or nil, c and c.username or 'Staff'
end

--- lista ticketelor deschise (nepreluate) - pentru lista de staff
exports('GetOpen', function()
    return MySQL.query.await(
        "SELECT id, user_id, username, category, message, created_at FROM tickets WHERE status='open' ORDER BY id ASC LIMIT 100") or {}
end)

--- ticketele active preluate de un anumit membru staff
exports('GetActiveFor', function(staffUserId)
    return MySQL.query.await(
        "SELECT id, user_id, username, category, message, created_at, updated_at FROM tickets WHERE status='active' AND assigned_to = ? ORDER BY updated_at DESC LIMIT 100",
        { tonumber(staffUserId) or -1 }) or {}
end)

--- firul complet al unui ticket (pentru viitorul UI de staff)
exports('GetThread', function(ticketId)
    local row = MySQL.single.await('SELECT * FROM tickets WHERE id = ?', { tonumber(ticketId) or -1 })
    if not row then return nil end
    return { ticket = ticketPayload(row), raw = row }
end)

--- staff preia un ticket
exports('Accept', function(staffSrc, ticketId)
    local sid, sname = staffCharId(staffSrc)
    if not sid then return false end
    ticketId = tonumber(ticketId)
    local aff = MySQL.update.await(
        "UPDATE tickets SET status='active', assigned_to=?, assigned_name=? WHERE id=? AND status='open'",
        { sid, sname, ticketId })
    if not (aff and aff > 0) then return false end
    local t = MySQL.single.await('SELECT user_id FROM tickets WHERE id=?', { ticketId })
    local psrc = t and srcOf(t.user_id)
    if psrc then notify(psrc, ('Your ticket #%s was accepted by %s.'):format(ticketId, sname), 'success') end
    refreshTicketOwner(ticketId)
    return true
end)

--- un reply pe ticket.  isStaff = true cand vine de la staff.
exports('Reply', function(authorSrc, ticketId, text, isStaff)
    local sid, sname = staffCharId(authorSrc)
    if not sid then return false end
    ticketId = tonumber(ticketId)
    text = tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, Config.MaxLen)
    if #text < 1 then return false end
    MySQL.insert.await(
        'INSERT INTO ticket_replies (ticket_id, author_id, author_name, is_staff, message) VALUES (?,?,?,?,?)',
        { ticketId, sid, sname, isStaff and 1 or 0, text })
    MySQL.update.await('UPDATE tickets SET updated_at=NOW() WHERE id=?', { ticketId })
    local t = MySQL.single.await('SELECT user_id FROM tickets WHERE id=?', { ticketId })
    local psrc = t and srcOf(t.user_id)
    if isStaff and psrc then
        chat(psrc, ('[Ticket #%s] %s: %s'):format(ticketId, sname, text), '#b98cff')
    end
    refreshTicketOwner(ticketId)
    return true
end)

--- staff inchide un ticket
exports('Close', function(staffSrc, ticketId)
    local sid, sname = staffCharId(staffSrc)
    ticketId = tonumber(ticketId)
    MySQL.update.await("UPDATE tickets SET status='closed', closed_at=NOW() WHERE id=? AND status<>'closed'", { ticketId })
    local t = MySQL.single.await('SELECT user_id FROM tickets WHERE id=?', { ticketId })
    local psrc = t and srcOf(t.user_id)
    if psrc then notify(psrc, ('Your ticket #%s was closed%s.'):format(ticketId, sname and (' by ' .. sname) or ''), 'info') end
    refreshTicketOwner(ticketId)
    return true
end)

--- doar re-trimite payload-ul catre jucator (daca staff_menu isi pastreaza SQL-ul propriu)
exports('StaffTouch', function(ticketId) refreshTicketOwner(ticketId) end)
