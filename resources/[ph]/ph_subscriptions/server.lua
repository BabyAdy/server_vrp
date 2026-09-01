-- ==========================================================
--  ph_subscriptions / server
--
--  Abonamente Gold / Platinum, cheiate pe SQL id (users.id).
--  Data de expirare = unix epoch (secunde); 0 sau in trecut => inactiv.
--
--  Exports (toate primesc userId = users.id):
--    GetSubscriptions(userId)  -> { gold = {active,expiresAt,remaining}, platinum = {...} }
--    HasSubscription(userId[, tier]) -> bool
--    GetActiveTier(userId)     -> 'platinum' | 'gold' | nil   (primul din Config.TierPriority activ)
--    GetSlotBonus(userId)      -> numar de sloturi bonus insumate
--    GetTierInfo(tier)         -> Config.Tiers[tier]
--    AddTime(userId, tier, seconds)  -> nou expiresAt (poate fi negativ pt scadere)
--    SetTime(userId, tier, seconds)  -> seteaza durata ramasa exact la N sec (0 = clear)
--    Clear(userId[, tier|'all'])
--
--  Event (server, cross-resource):
--    'ph_subscriptions:bonusChanged'  (userId, newBonus)   -- ph_inventory il asculta
--    'ph_subscriptions:expired'       (userId, tier)
-- ==========================================================
local PH = 'ph-core'
local ready = false

local SUBS = {}   -- [userId] = { gold=epoch, platinum=epoch, bonus=int, wasActive={gold=bool,platinum=bool} }
local S2U = {}    -- [src] = userId

local SCHEMA = [[
CREATE TABLE IF NOT EXISTS `subscriptions` (
  `user_id`             INT UNSIGNED    NOT NULL,
  `gold_expires_at`     BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `platinum_expires_at` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `updated_at`          TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    while GetResourceState(PH) ~= 'started' do Wait(200) end
    local ok, err = pcall(function() MySQL.query.await(SCHEMA) end)
    if not ok then
        print('^1[ph_subscriptions] DB init error:^7 ' .. tostring(err))
        return
    end
    ready = true
    print('^5[ph_subscriptions]^7 ready.')
end)

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function now() return os.time() end
local function tierActive(exp) return (tonumber(exp) or 0) > now() end

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

local function computeBonus(rec)
    local b = 0
    for tier, cfg in pairs(Config.Tiers) do
        if tierActive(rec[tier]) then b = b + (cfg.slots or 0) end
    end
    return b
end

local function loadSub(userId)
    userId = tonumber(userId)
    if not userId then return nil end
    local row = MySQL.single.await(
        'SELECT gold_expires_at, platinum_expires_at FROM subscriptions WHERE user_id = ?', { userId })
    local rec = {
        gold     = (row and tonumber(row.gold_expires_at)) or 0,
        platinum = (row and tonumber(row.platinum_expires_at)) or 0,
        wasActive = {},
    }
    for tier in pairs(Config.Tiers) do rec.wasActive[tier] = tierActive(rec[tier]) end
    rec.bonus = computeBonus(rec)
    SUBS[userId] = rec
    if not row then
        MySQL.insert('INSERT IGNORE INTO subscriptions (user_id) VALUES (?)', { userId })
    end
    return rec
end

local function getRec(userId)
    userId = tonumber(userId)
    if not userId then return nil end
    return SUBS[userId] or loadSub(userId)
end

local function persist(userId, rec)
    MySQL.update(
        'INSERT INTO subscriptions (user_id, gold_expires_at, platinum_expires_at) VALUES (?, ?, ?) '
        .. 'ON DUPLICATE KEY UPDATE gold_expires_at = ?, platinum_expires_at = ?',
        { userId, rec.gold, rec.platinum, rec.gold, rec.platinum })
end

--- recalculeaza bonusul de sloturi; daca s-a schimbat, anunta ph_inventory
local function syncBonus(userId, rec)
    local nb = computeBonus(rec)
    if nb ~= (rec.bonus or 0) then
        rec.bonus = nb
        TriggerEvent('ph_subscriptions:bonusChanged', userId, nb)
    end
    return nb
end

-- ----------------------------------------------------------
--  Mutatii
-- ----------------------------------------------------------
local function addTime(userId, tier, seconds)
    userId  = tonumber(userId)
    seconds = math.floor(tonumber(seconds) or 0)
    if not userId or not Config.Tiers[tier] then return nil end
    local rec = getRec(userId)
    if not rec then return nil end

    local cur  = rec[tier] or 0
    local from = (cur > now()) and cur or now()      -- daca era expirat, porneste de la "acum"
    rec[tier]  = math.max(0, from + seconds)
    rec.wasActive[tier] = tierActive(rec[tier])
    persist(userId, rec)
    syncBonus(userId, rec)
    return rec[tier]
end

local function setTime(userId, tier, seconds)
    userId  = tonumber(userId)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if not userId or not Config.Tiers[tier] then return nil end
    local rec = getRec(userId)
    if not rec then return nil end

    rec[tier] = (seconds > 0) and (now() + seconds) or 0
    rec.wasActive[tier] = tierActive(rec[tier])
    persist(userId, rec)
    syncBonus(userId, rec)
    return rec[tier]
end

-- ----------------------------------------------------------
--  Exports
-- ----------------------------------------------------------
exports('GetSlotBonus', function(userId)
    local rec = getRec(userId)
    return rec and rec.bonus or 0
end)

exports('GetSubscriptions', function(userId)
    local rec = getRec(userId)
    if not rec then return nil end
    local out = {}
    for tier in pairs(Config.Tiers) do
        local exp = rec[tier] or 0
        out[tier] = { active = tierActive(exp), expiresAt = exp, remaining = math.max(0, exp - now()) }
    end
    return out
end)

exports('HasSubscription', function(userId, tier)
    local rec = getRec(userId)
    if not rec then return false end
    if tier and Config.Tiers[tier] then return tierActive(rec[tier]) end
    for t in pairs(Config.Tiers) do if tierActive(rec[t]) then return true end end
    return false
end)

exports('GetActiveTier', function(userId)
    local rec = getRec(userId)
    if not rec then return nil end
    for _, t in ipairs(Config.TierPriority) do
        if Config.Tiers[t] and tierActive(rec[t]) then return t end
    end
    return nil
end)

exports('GetTierInfo', function(tier) return Config.Tiers[tier] end)

exports('AddTime', function(userId, tier, seconds) return addTime(userId, tostring(tier), seconds) end)
exports('SetTime', function(userId, tier, seconds) return setTime(userId, tostring(tier), seconds) end)

exports('Clear', function(userId, tier)
    if not tier or tier == 'all' then
        for t in pairs(Config.Tiers) do setTime(userId, t, 0) end
        return true
    end
    return setTime(userId, tostring(tier), 0) ~= nil
end)

-- ----------------------------------------------------------
--  Verificare periodica a expirarilor (doar online)
-- ----------------------------------------------------------
CreateThread(function()
    while not ready do Wait(500) end
    while true do
        Wait(Config.CheckIntervalMs)
        local ids = exports[PH]:GetOnlineUserIds() or {}
        for _, uid in ipairs(ids) do
            local rec = SUBS[uid]
            if rec then
                for tier, cfg in pairs(Config.Tiers) do
                    local activeNow = tierActive(rec[tier])
                    if rec.wasActive[tier] and not activeNow then
                        rec.wasActive[tier] = false
                        TriggerEvent('ph_subscriptions:expired', uid, tier)
                        local s = srcOf(uid)
                        if s then
                            notify(s, ('Your %s subscription expired. Bonus slots have been released.')
                                :format(cfg.label), '#e0c07a')
                        end
                    elseif activeNow and not rec.wasActive[tier] then
                        rec.wasActive[tier] = true
                    end
                end
                syncBonus(uid, rec)
            end
        end
    end
end)

-- ----------------------------------------------------------
--  Ciclu de viata
-- ----------------------------------------------------------
AddEventHandler('ph-core:playerLoaded', function(src, char)
    local uid = char and char.id
    if not uid then return end
    S2U[src] = uid
    loadSub(uid)
    -- push neconditionat: daca inventarul s-a incarcat deja, se corecteaza acum
    -- (handler-ul din ph_inventory ignora daca bonusul e deja corect)
    SetTimeout(1200, function()
        if SUBS[uid] then TriggerEvent('ph_subscriptions:bonusChanged', uid, SUBS[uid].bonus or 0) end
    end)
end)

AddEventHandler('playerDropped', function()
    local uid = S2U[source]
    S2U[source] = nil
    if uid then SUBS[uid] = nil end
end)

-- ----------------------------------------------------------
--  Comenzi de administrare  (argument = SQL id = users.id)
-- ----------------------------------------------------------
local function fmtRemaining(sec)
    sec = math.max(0, math.floor(sec or 0))
    local d = math.floor(sec / 86400); sec = sec % 86400
    local h = math.floor(sec / 3600);  sec = sec % 3600
    local m = math.floor(sec / 60);    sec = sec % 60
    return ('%dd %dh %dm %ds'):format(d, h, m, sec)
end

local function durFromArgs(a, i)
    local d = tonumber(a[i])     or 0
    local h = tonumber(a[i + 1]) or 0
    local m = tonumber(a[i + 2]) or 0
    local s = tonumber(a[i + 3]) or 0
    return math.floor(d * 86400 + h * 3600 + m * 60 + s)
end

local function announceTo(userId, text, color)
    local s = srcOf(userId)
    if s then notify(s, text, color) end
end

RegisterCommand('subadd', function(src, args)
    if not exports['ph-core']:RequireAce(src, 'ph.admin', 'admin') then return end
    local uid  = tonumber(args[1])
    local tier = (args[2] or ''):lower()
    if not uid or not Config.Tiers[tier] then
        exports['ph-core']:CmdSyntax(src, '/subadd [sqlId] [gold/platinum] [days] [hours] [minutes] [seconds]')
        return
    end
    local secs = durFromArgs(args, 3)
    local exp = addTime(uid, tier, secs)
    if not exp then exports['ph-core']:CmdSyntax(src, '/subadd [sqlId] [gold/platinum] [days] [hours] [minutes] [seconds]  (no such user)') return end
    print(('subadd: user %d %s -> %s (%s)'):format(
        uid, tier, exp > 0 and os.date('%d.%m.%Y %H:%M', exp) or 'inactive', fmtRemaining(exp - now())))
    announceTo(uid, ('You received %s of %s subscription.'):format(fmtRemaining(secs), Config.Tiers[tier].label), '#8ce07a')
    exports['ph-core']:StaffMsg('subscription', ('%s granted user %d %s of %s subscription.'):format(GetPlayerName(src) or ('src ' .. src), uid, fmtRemaining(secs), Config.Tiers[tier].label))
end, false)

RegisterCommand('subset', function(src, args)
    if not exports['ph-core']:RequireAce(src, 'ph.admin', 'admin') then return end
    local uid  = tonumber(args[1])
    local tier = (args[2] or ''):lower()
    if not uid or not Config.Tiers[tier] then
        exports['ph-core']:CmdSyntax(src, '/subset [sqlId] [gold/platinum] [days] [hours] [minutes] [seconds]')
        return
    end
    local secs = durFromArgs(args, 3)
    local exp = setTime(uid, tier, secs)
    if not exp then exports['ph-core']:CmdSyntax(src, '/subset [sqlId] [gold/platinum] [days] [hours] [minutes] [seconds]  (no such user)') return end
    print(('subset: user %d %s -> %s'):format(uid, tier, fmtRemaining(exp - now())))
    exports['ph-core']:StaffMsg('subscription', ('%s set user %d %s subscription to %s.'):format(GetPlayerName(src) or ('src ' .. src), uid, Config.Tiers[tier].label, fmtRemaining(exp - now())))
end, false)

RegisterCommand('subclear', function(src, args)
    if not exports['ph-core']:RequireAce(src, 'ph.admin', 'admin') then return end
    local uid  = tonumber(args[1])
    local tier = (args[2] or 'all'):lower()
    if not uid then exports['ph-core']:CmdSyntax(src, '/subclear [sqlId] [gold/platinum/all]') return end
    if tier ~= 'all' and not Config.Tiers[tier] then exports['ph-core']:CmdSyntax(src, '/subclear [sqlId] [gold/platinum/all]') return end
    if tier == 'all' then
        for t in pairs(Config.Tiers) do setTime(uid, t, 0) end
    else
        setTime(uid, tier, 0)
    end
    print(('subclear: user %d -> %s'):format(uid, tier))
    exports['ph-core']:StaffMsg('subscription', ('%s cleared user %d subscription (%s).'):format(GetPlayerName(src) or ('src ' .. src), uid, tier))
end, false)

RegisterCommand('subcheck', function(src, args)
    if not exports['ph-core']:RequireAce(src, 'ph.admin', 'admin') then return end
    local uid = tonumber(args[1])
    if not uid then exports['ph-core']:CmdSyntax(src, '/subcheck [sqlId]') return end
    local rec = getRec(uid)
    if not rec then exports['ph-core']:CmdSyntax(src, '/subcheck [sqlId]  (no such user)') return end
    for tier, cfg in pairs(Config.Tiers) do
        local exp = rec[tier] or 0
        print(('  %s: %s'):format(cfg.label,
            tierActive(exp) and ('active, ' .. fmtRemaining(exp - now()) .. ' left') or 'inactive'))
    end
    print(('  bonus slots: +%d'):format(rec.bonus or 0))
end, false)

-- ----------------------------------------------------------
--  /debugsubs  - pentru staff >= manager (sau consola / ph.admin)
--  Seteaza durata ramasa a unui abonament si arata starea inainte/dupa.
--    /debugsubs <sqlId> <gold|platinum> <zile> [ore] [minute] [secunde]
-- ----------------------------------------------------------
local function canDebug(src)
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, 'ph.admin') then return true end
    local ok, r = pcall(function() return exports['ph-core']:HasStaffRank(src, 'manager') end)
    return ok and r == true
end

RegisterCommand('debugsubs', function(src, args)
    if not canDebug(src) then
        exports['ph-core']:CmdPermError(src, 'manager')
        return
    end

    local function out(text, color)
        if src == 0 then print('[debugsubs] ' .. text) else notify(src, text, color) end
    end

    local uid  = tonumber(args[1])
    local tier = (args[2] or ''):lower()
    if not uid or not Config.Tiers[tier] then
        exports['ph-core']:CmdSyntax(src, '/debugsubs [sqlId] [gold/platinum] [days] [hours] [minutes] [seconds]')
        return
    end

    local rec = getRec(uid)
    if not rec then
        out(('No user with id %s.'):format(uid), '#ff4d4d')
        return
    end

    local before = rec[tier] or 0
    local secs   = durFromArgs(args, 3)
    local after  = setTime(uid, tier, secs)
    local cfg    = Config.Tiers[tier]

    out(('debugsubs: user %s / %s'):format(uid, cfg.label), '#b98cff')
    out(('  before: %s'):format(
        tierActive(before) and ('active, ' .. fmtRemaining(before - now())) or 'inactive'), '#cfc9e6')
    out(('  set:     %s  (%ds)'):format(fmtRemaining(secs), secs), '#cfc9e6')
    out(('  now:     %s%s'):format(
        tierActive(after) and ('active, ' .. fmtRemaining(after - now())) or 'inactive',
        after > 0 and (' -> ' .. os.date('%d.%m.%Y %H:%M', after)) or ''), '#8ce07a')
    out(('  user bonus slots: +%d'):format((SUBS[uid] and SUBS[uid].bonus) or 0), '#8ce07a')

    announceTo(uid, ('Your %s subscription was set to %s by a staff member.')
        :format(cfg.label, fmtRemaining(secs)), '#e0c07a')
    exports['ph-core']:StaffMsg('subscription', ('%s set user %d %s subscription to %s (debugsubs).'):format(GetPlayerName(src) or ('src ' .. src), uid, cfg.label, fmtRemaining(secs)))
end, false)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    if GetResourceState('ph_chat') == 'started' then
        TriggerClientEvent('chat:addSuggestion', -1, '/debugsubs',
            'Set a subscription duration',
            { { name = 'sqlId' }, { name = 'gold|platinum' }, { name = 'days' },
              { name = 'hours' }, { name = 'minutes' }, { name = 'seconds' } })
    end
end)

AddEventHandler('ph-core:playerLoaded', function(src)
    TriggerClientEvent('chat:addSuggestion', src, '/debugsubs',
        'Set a subscription duration',
        { { name = 'sqlId' }, { name = 'gold|platinum' }, { name = 'days' },
          { name = 'hours' }, { name = 'minutes' }, { name = 'seconds' } })
end)
