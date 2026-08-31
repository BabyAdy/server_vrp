-- ==========================================================
--  ph_postoffice / server
--
--  "Cutia postala" a fiecarui jucator, cheiata pe SQL id (users.id).
--  Alte resurse depun iteme aici cand nu incap in inventar:
--      exports['ph_postoffice']:Deposit(userId, { name=, count=, meta= }, motiv)
--  Jucatorul le revendica in joc cu /po  (sau /postoffice).
-- ==========================================================
local PH = 'ph-core'
local ready = false

local SCHEMA = [[
CREATE TABLE IF NOT EXISTS `post_office_items` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    INT UNSIGNED NOT NULL,
  `name`       VARCHAR(64)  NOT NULL,
  `count`      INT          NOT NULL DEFAULT 1,
  `meta`       LONGTEXT     NULL DEFAULT NULL,
  `reason`     VARCHAR(128) NULL DEFAULT NULL,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `claimed_at` TIMESTAMP    NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_po_user` (`user_id`, `claimed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    while GetResourceState(PH) ~= 'started' do Wait(200) end
    local ok, err = pcall(function() MySQL.query.await(SCHEMA) end)
    if not ok then
        print('^1[ph_postoffice] eroare init DB:^7 ' .. tostring(err))
        return
    end
    ready = true
    print('^5[ph_postoffice]^7 pregatit.')
end)

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function srcOf(userId)
    local ok, s = pcall(function() return exports[PH]:GetSource(userId) end)
    return (ok and s) or nil
end

local function notify(src, text, color)
    if not src then return end
    if GetResourceState('ph_chat') == 'started' then
        exports['ph_chat']:send(src, { text = text, textColor = color or '#e8e6f0' })
    else
        TriggerClientEvent('chat:addMessage', src, { args = { text } })
    end
end

local function itemLabel(name)
    local ok, items = pcall(function() return exports['ph_inventory']:GetItems() end)
    if ok and type(items) == 'table' and type(items[name]) == 'table' and items[name].label then
        return items[name].label
    end
    return name
end

-- ----------------------------------------------------------
--  Depunere
-- ----------------------------------------------------------
--- @param userId number   SQL id
--- @param item table       { name, count, meta }
--- @param reason string?   motiv (optional)
exports('Deposit', function(userId, item, reason)
    userId = tonumber(userId)
    if not userId or type(item) ~= 'table' or not item.name then return false end
    local count = math.max(1, math.floor(tonumber(item.count) or 1))
    MySQL.insert(
        'INSERT INTO post_office_items (user_id, name, count, meta, reason) VALUES (?, ?, ?, ?, ?)',
        {
            userId, tostring(item.name), count,
            item.meta and json.encode(item.meta) or nil,
            reason and tostring(reason):sub(1, 128) or nil,
        }
    )
    local s = srcOf(userId)
    if s then
        notify(s, ('Post Office: %dx %s pus deoparte%s. Scrie /po pentru a revendica.')
            :format(count, itemLabel(item.name), reason and (' (' .. reason .. ')') or ''), '#e0c07a')
    end
    return true
end)

exports('Count', function(userId)
    userId = tonumber(userId)
    if not userId then return 0 end
    return tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM post_office_items WHERE user_id = ? AND claimed_at IS NULL', { userId })) or 0
end)

-- ----------------------------------------------------------
--  Revendicare
-- ----------------------------------------------------------
local function claim(userId, src)
    userId = tonumber(userId)
    if not userId then return 0 end
    if not ready then
        if src then notify(src, 'Post Office se initializeaza, incearca din nou.', '#e07a7a') end
        return 0
    end

    local rows = MySQL.query.await(
        'SELECT id, name, count, meta FROM post_office_items WHERE user_id = ? AND claimed_at IS NULL ORDER BY id ASC',
        { userId }) or {}

    if #rows == 0 then
        if src then notify(src, 'Post Office gol.', '#e0c07a') end
        return 0
    end

    local given, blocked = 0, false
    for _, r in ipairs(rows) do
        local meta
        if r.meta and r.meta ~= '' then
            local ok, dec = pcall(json.decode, r.meta)
            if ok then meta = dec end
        end
        local ok = false
        pcall(function()
            ok = exports['ph_inventory']:GiveItem(userId, r.name, tonumber(r.count) or 1, meta) == true
        end)
        if ok then
            MySQL.update('UPDATE post_office_items SET claimed_at = NOW() WHERE id = ?', { r.id })
            given = given + 1
        else
            blocked = true
            break   -- inventar plin: opreste-te, restul ramane in cutie
        end
    end

    if src then
        if given > 0 then
            notify(src, ('Ai revendicat %d pachet(e) din Post Office%s.')
                :format(given, blocked and ' (restul nu a incaput)' or ''), '#8ce07a')
        else
            notify(src, 'Nu ai loc in inventar pentru itemele din Post Office.', '#e07a7a')
        end
    end
    return given
end

exports('Claim', function(userId)
    return claim(userId, srcOf(tonumber(userId)))
end)

-- ----------------------------------------------------------
--  Comenzi
-- ----------------------------------------------------------
local function doPostoffice(src, args)
    if src == 0 then print('[ph_postoffice] foloseste comanda in joc.') return end
    local uid = exports[PH]:GetUserId(src)
    if not uid then return end

    if args[1] == 'list' then
        local rows = MySQL.query.await(
            'SELECT name, count, reason, created_at FROM post_office_items WHERE user_id = ? AND claimed_at IS NULL ORDER BY id ASC LIMIT 50',
            { uid }) or {}
        if #rows == 0 then return notify(src, 'Post Office gol.', '#e0c07a') end
        notify(src, ('Post Office (%d pachet(e)):'):format(#rows), '#b98cff')
        for _, r in ipairs(rows) do
            notify(src, (' - %dx %s%s'):format(r.count, itemLabel(r.name), r.reason and (' — ' .. r.reason) or ''), '#cfc9e6')
        end
    else
        claim(uid, src)
    end
end

RegisterCommand('postoffice', function(src, args) doPostoffice(src, args) end, false)
RegisterCommand('po', function(src, args) doPostoffice(src, args) end, false)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    if GetResourceState('ph_chat') == 'started' then
        TriggerClientEvent('chat:addSuggestion', -1, '/po', 'Revendica itemele din Post Office', {})
        TriggerClientEvent('chat:addSuggestion', -1, '/postoffice', 'Post Office: "list" sau revendica', { { name = 'list', help = 'optional' } })
    end
end)

AddEventHandler('ph-core:playerLoaded', function(src)
    TriggerClientEvent('chat:addSuggestion', src, '/po', 'Revendica itemele din Post Office', {})
end)
