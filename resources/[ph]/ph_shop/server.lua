-- ==========================================================
--  ph_shop / server  -  magazin cu Premium Points
--
--  Cheia e mereu SQL id-ul (users.id).  Banii de PP se misca prin
--  exports['ph-core']:AdjustBalance(uid, 'premiumpoints', delta).
--
--  Comanda /shop e in commands.lua (foloseste SHOPENV).
-- ==========================================================
local PH  = 'ph-core'
local RES = GetCurrentResourceName()

-- index rapid dupa cheie
local BYKEY = {}
for _, it in ipairs(Config.Items) do BYKEY[it.key] = it end

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function uidOf(src)
    local ok, id = pcall(function()
        local v = exports[PH]:GetUserId(src)
        if v then return v end
        local c = exports[PH]:GetCharacter(src)
        return c and c.id or nil
    end)
    return (ok and id) or nil
end

local function srcOf(userId)
    local ok, s = pcall(function() return exports[PH]:GetSource(userId) end)
    return (ok and s) or nil
end

local function notify(src, text, kind)
    if not src or src == 0 then print('[ph_shop] ' .. tostring(text)) return end
    exports[PH]:Notify(src, text, kind or 'info')
end

local function chat(src, text, color)
    if not src or src == 0 then print('[ph_shop] ' .. tostring(text)) return end
    exports[PH]:Msg(src, text, color)
end

local function ppOf(src)
    local ok, ch = pcall(function() return exports[PH]:GetCharacter(src) end)
    return (ok and type(ch) == 'table' and tonumber(ch.premiumpoints)) or 0
end

local function rpName(src)
    local ok, ch = pcall(function() return exports[PH]:GetCharacter(src) end)
    if ok and type(ch) == 'table' and ch.username then return ch.username end
    return GetPlayerName(src) or ('Player_' .. tostring(src))
end

--- charge PP; return true on success (false -> not enough; nothing left the account)
local function charge(uid, cost)
    cost = math.abs(cost)
    local res = exports[PH]:AdjustBalance(uid, 'premiumpoints', -cost)
    if not res then return false end
    if res.delta ~= -cost then
        -- AdjustBalance clamps at 0 -> only a partial amount moved; put it back
        if res.delta ~= 0 then exports[PH]:AdjustBalance(uid, 'premiumpoints', -res.delta) end
        return false
    end
    return true
end

local function refund(uid, amount)
    exports[PH]:AdjustBalance(uid, 'premiumpoints', math.abs(amount))
end

-- ----------------------------------------------------------
--  Deschidere meniu
-- ----------------------------------------------------------
local function ownsPhone(uid)
    local v
    pcall(function() v = MySQL.scalar.await('SELECT phone FROM users WHERE id = ?', { uid }) end)
    return v ~= nil and v ~= ''
end

local function clanState(uid)
    -- 'none' | 'member' | 'pending'
    local inClan = false
    pcall(function() inClan = (exports['ph_clans']:GetClan(uid) or 0) ~= 0 end)
    if not inClan then
        local row = MySQL.scalar.await('SELECT clan FROM users WHERE id = ?', { uid })
        inClan = (tonumber(row) or 0) ~= 0
    end
    if inClan then return 'member' end
    local p
    pcall(function()
        p = MySQL.scalar.await("SELECT id FROM clan_requests WHERE user_id = ? AND status = 'pending' LIMIT 1", { uid })
    end)
    return p and 'pending' or 'none'
end

local function open(src)
    local uid = uidOf(src)
    if not uid then return end
    local pp = ppOf(src)
    local hasPhone = ownsPhone(uid)
    local cstate = clanState(uid)

    local list = {}
    for _, it in ipairs(Config.Items) do
        local locked, lockMsg
        if it.key == 'phone_number' and hasPhone then
            locked, lockMsg = true, 'Already owned'
        elseif it.key == 'create_clan' and cstate == 'member' then
            locked, lockMsg = true, 'Already in a clan'
        elseif it.key == 'create_clan' and cstate == 'pending' then
            locked, lockMsg = true, 'Request pending'
        end
        list[#list + 1] = {
            key = it.key, label = it.label, desc = it.desc, cost = it.cost,
            kind = it.kind, form = it.form,
            afford = pp >= it.cost, locked = locked or nil, lockMsg = lockMsg,
        }
    end
    TriggerClientEvent('ph_shop:cl:open', src, { items = list, pp = pp })
end

local function repush(src) open(src) end

-- ----------------------------------------------------------
--  Cumparare
-- ----------------------------------------------------------
RegisterNetEvent('ph_shop:sv:buy', function(key)
    local src = source
    local uid = uidOf(src)
    local it = BYKEY[tostring(key or '')]
    if not uid or not it then return end

    if it.kind == 'form' then
        -- formularele nu taxeaza acum; taxarea e la confirmare
        if it.form == 'phone' and ownsPhone(uid) then
            return notify(src, 'You already have a phone number.', 'warning')
        end
        if it.form == 'clan' then
            local st = clanState(uid)
            if st == 'member' then return notify(src, 'You are already in a clan.', 'warning') end
            if st == 'pending' then return notify(src, 'You already have a pending clan request.', 'warning') end
        end
        TriggerClientEvent('ph_shop:cl:form', src, {
            which = it.form, cost = it.cost, label = it.label,
            phoneMin = Config.Phone.min, phoneMax = Config.Phone.max,
            nameMax = Config.Clan.nameMax, tagMax = Config.Clan.tagMax,
        })
        return
    end

    if ppOf(src) < it.cost then
        return notify(src, ('Not enough Premium Points (need %d).'):format(it.cost), 'error')
    end
    if not charge(uid, it.cost) then
        return notify(src, 'Not enough Premium Points.', 'error')
    end

    if it.kind == 'item' then
        local ok = false
        pcall(function() ok = exports['ph_inventory']:GiveItem(uid, it.grant.item, 1) == true end)
        if not ok then
            refund(uid, it.cost)
            return notify(src, 'Your inventory is full — purchase refunded.', 'error')
        end
        notify(src, ('Purchased: %s'):format(it.label), 'success')

    elseif it.kind == 'instant' and it.grant.vslot then
        local cur = 0
        pcall(function() cur = exports['ph_vehicles']:GetVehicleSlots(uid) or 0 end)
        local okSet = false
        pcall(function() okSet = exports['ph_vehicles']:SetVehicleSlots(uid, cur + it.grant.vslot) ~= nil end)
        if not okSet then
            refund(uid, it.cost)
            return notify(src, 'Could not add the vehicle slot — purchase refunded.', 'error')
        end
        notify(src, ('Vehicle slots: %d -> %d'):format(cur, cur + it.grant.vslot), 'success')
    end

    repush(src)
end)

-- ----------------------------------------------------------
--  Phone Number  (formular)
-- ----------------------------------------------------------
RegisterNetEvent('ph_shop:sv:phoneSet', function(value)
    local src = source
    local uid = uidOf(src)
    if not uid then return end
    local it = BYKEY['phone_number']

    local v = tostring(value or ''):upper():gsub('%s', '')
    local function bad(msg) TriggerClientEvent('ph_shop:cl:formError', src, { which = 'phone', msg = msg }) end

    if #v < Config.Phone.min or #v > Config.Phone.max then
        return bad(('Use %d-%d characters.'):format(Config.Phone.min, Config.Phone.max))
    end
    if v:match('[^A-Z0-9]') then
        return bad('Only letters A-Z and digits 0-9.')
    end
    if ownsPhone(uid) then return bad('You already have a phone number.') end
    if MySQL.scalar.await('SELECT id FROM users WHERE phone = ?', { v }) then
        return bad('That number is already taken.')
    end
    if ppOf(src) < it.cost then return bad(('Not enough Premium Points (need %d).'):format(it.cost)) end
    if not charge(uid, it.cost) then return bad('Not enough Premium Points.') end

    local aff = MySQL.update.await('UPDATE users SET phone = ? WHERE id = ?', { v, uid })
    if not aff or aff == 0 then
        refund(uid, it.cost)
        return bad('Could not save the number — try again.')
    end
    TriggerClientEvent('ph_shop:cl:formDone', src, { which = 'phone' })
    notify(src, ('Your phone number is now %s.'):format(v), 'success')
    repush(src)
end)

-- ----------------------------------------------------------
--  Create Clan  (formular -> cerere catre staff)
-- ----------------------------------------------------------
RegisterNetEvent('ph_shop:sv:clanRequest', function(p)
    local src = source
    local uid = uidOf(src)
    if not uid then return end
    p = p or {}
    local it = BYKEY['create_clan']

    local name = tostring(p.name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, Config.Clan.nameMax)
    local tag  = tostring(p.tag or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, Config.Clan.tagMax)
    local function bad(msg) TriggerClientEvent('ph_shop:cl:formError', src, { which = 'clan', msg = msg }) end

    if #name < Config.Clan.nameMin then return bad(('Name too short (min %d).'):format(Config.Clan.nameMin)) end
    if #tag < 1 then return bad('Tag is required.') end

    local st = clanState(uid)
    if st == 'member' then return bad('You are already in a clan.') end
    if st == 'pending' then return bad('You already have a pending request.') end
    if ppOf(src) < it.cost then return bad(('Not enough Premium Points (need %d).'):format(it.cost)) end
    if not charge(uid, it.cost) then return bad('Not enough Premium Points.') end

    local reqId = MySQL.insert.await(
        "INSERT INTO clan_requests (user_id, c_name, c_tag, status) VALUES (?, ?, ?, 'pending')",
        { uid, name, tag })
    if not reqId then
        refund(uid, it.cost)
        return bad('Could not file the request — try again.')
    end

    TriggerClientEvent('ph_shop:cl:formDone', src, { which = 'clan' })
    chat(src, ('Clan request #%d sent to staff. You will be refunded %d PP if it is rejected.'):format(reqId, it.cost), '#cfc9e6')
    exports[PH]:StaffMsg('clan', ('%s requested a clan: "%s" [%s]  —  /clanreq accept %d  |  /clanreq reject %d')
        :format(rpName(src), name, tag, reqId, reqId))
    repush(src)
end)

-- ----------------------------------------------------------
--  Bilete de abonament folosite din inventar
-- ----------------------------------------------------------
AddEventHandler('ph_inventory:server:used', function(uid, itemName)
    local tier
    if itemName == 'sub_ticket_gold' then tier = 'gold'
    elseif itemName == 'sub_ticket_platinum' then tier = 'platinum'
    else return end

    local ok = false
    pcall(function()
        ok = exports['ph_subscriptions']:AddTime(uid, tier, Config.SubTicketDays * 86400) ~= nil
    end)
    local s = srcOf(uid)
    local tierLabel = (tier:gsub('^%l', string.upper))
    if ok then
        if s then chat(s, ('%s subscription: +%d days.'):format(tierLabel, Config.SubTicketDays), '#8ce07a') end
    else
        if s then notify(s, 'Subscription service is unavailable right now.', 'error') end
        print(('[ph_shop] AddTime failed for user %s tier %s'):format(tostring(uid), tier))
    end
end)

-- ----------------------------------------------------------
--  Namespace pentru commands.lua
-- ----------------------------------------------------------
SHOPENV = {
    PH   = PH,
    open = open,
}
