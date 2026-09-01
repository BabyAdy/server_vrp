-- ==========================================================
--  ph_subscriptions / commands  -  TOATE comenzile / ale resursei
--  (argument = SQL id = users.id)
--
--    /subadd    [sqlId] [gold/platinum] [d] [h] [m] [s]   (ace ph.admin)
--    /subset    [sqlId] [gold/platinum] [d] [h] [m] [s]   (ace ph.admin)
--    /subclear  [sqlId] [gold/platinum/all]               (ace ph.admin)
--    /subcheck  [sqlId]                                    (ace ph.admin)
--    /debugsubs [sqlId] [gold/platinum] [d] [h] [m] [s]    (staff >= manager / ph.admin)
--
--  Helperele traiesc in server.lua si sunt expuse prin `SUBENV`.
-- ==========================================================
local E = SUBENV
local now, tierActive = E.now, E.tierActive
local srcOf, notify   = E.srcOf, E.notify
local getRec, addTime, setTime = E.getRec, E.addTime, E.setTime

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
    out(('  user bonus slots: +%d'):format((E.subs()[uid] and E.subs()[uid].bonus) or 0), '#8ce07a')

    announceTo(uid, ('Your %s subscription was set to %s by a staff member.')
        :format(cfg.label, fmtRemaining(secs)), '#e0c07a')
    exports['ph-core']:StaffMsg('subscription', ('%s set user %d %s subscription to %s (debugsubs).'):format(GetPlayerName(src) or ('src ' .. src), uid, cfg.label, fmtRemaining(secs)))
end, false)
