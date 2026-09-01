PH = PH or {}
PH.Players = PH.Players or {}

local RES = GetCurrentResourceName()

-- ----------------------------------------------------------
--  Conectare: verificare de baza inainte de intrarea in sesiune
-- ----------------------------------------------------------
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    deferrals.update('Purple Havoc - checking access...')

    -- asteapta pana la 10s ca baza de date sa fie gata
    local waited = 0
    while not PH.DB.ready and waited < 10000 do
        Wait(250)
        waited = waited + 250
    end

    if not PH.DB.ready then
        deferrals.done('The server is not ready yet (database). Try again shortly.')
        return
    end

    local license
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then
            license = id
            break
        end
    end

    if not license then
        deferrals.done('You do not have a valid FiveM/Rockstar license. Start the game through the official launcher.')
        return
    end

    -- verificare de ban (staff_menu, optional)
    if GetResourceState('staff_menu') == 'started' then
        local ok, ban = pcall(function()
            return exports['staff_menu']:CheckBan(license)
        end)
        if ok and type(ban) == 'table' then
            local when = ban.expires_at
                and ('Expires: ' .. os.date('%d.%m.%Y %H:%M', ban.expires_at))
                or 'Permanent'
            deferrals.done(('\n\n[Purple Havoc] Account banned.\nReason: %s\n%s\nBan ID: #%s')
                :format(ban.reason or '-', when, ban.id or '?'))
            return
        end
    end

    deferrals.done()
end)

-- ----------------------------------------------------------
--  Exports pentru alte resurse
-- ----------------------------------------------------------
exports('GetPlayer', function(src)
    return PH.Players[src]
end)

exports('GetCharacter', function(src)
    local p = PH.Players[src]
    return p and p.character or nil
end)

--- src (session id) -> sql id (users.id).  Sursa: PH.Players, apoi maparea de sesiune.
exports('GetUserId', function(src)
    local p = PH.Players[src]
    if p and p.userId then return p.userId end
    return PH.Session and PH.Session.IdOf(src) or nil
end)

exports('IsPlayerLoaded', function(src)
    local p = PH.Players[src]
    return (p and p.character) ~= nil
end)

exports('GetLicense', function(src)
    return PH.GetLicense and PH.GetLicense(src) or nil
end)

-- ----------------------------------------------------------
--  Feedback STANDARD pentru comenzi (folosit de toate resursele)
--    :CmdPermError(src, grade)  -> rosu   "ERROR: insufficient permission ( #grade )"
--    :CmdSubError(src)          -> rosu   "ERROR: You dont have a active subscription!"
--    :CmdSyntax(src, usage)     -> turcoaz "SYNTAX: /cmd [..] [..]"
--    :RequireStaff(src, grade)  -> bool   (trimite CmdPermError daca nu are)
--    :RequireAce(src, ace, lbl) -> bool   (idem, pentru comenzi pe ace)
--    :RequireSub(src[, tier])   -> bool   (trimite CmdSubError daca nu are abonament)
-- ----------------------------------------------------------
local CMD_RED  = '#ff4d4d'
local CMD_TURQ = '#40e0d0'

local function cmdSend(src, text, color, rgb)
    if src == 0 then print(text); return end
    if GetResourceState('ph_chat') == 'started' then
        exports['ph_chat']:send(src, { text = text, textColor = color })
    else
        TriggerClientEvent('chat:addMessage', src, { color = rgb, args = { text } })
    end
end

exports('CmdPermError', function(src, grade)
    cmdSend(src, ('ERROR: insufficient permission ( #%s )'):format(tostring(grade or '?')), CMD_RED, { 255, 77, 77 })
end)

exports('CmdSubError', function(src)
    cmdSend(src, 'ERROR: You dont have a active subscription!', CMD_RED, { 255, 77, 77 })
end)

exports('CmdSyntax', function(src, usage)
    cmdSend(src, ('SYNTAX: %s'):format(tostring(usage or '')), CMD_TURQ, { 64, 224, 208 })
end)

exports('RequireStaff', function(src, grade)
    if src == 0 then return true end
    local ok = false
    pcall(function() ok = exports['ph-core']:HasStaffRank(src, grade) == true end)
    if ok then return true end
    cmdSend(src, ('ERROR: insufficient permission ( #%s )'):format(tostring(grade or '?')), CMD_RED, { 255, 77, 77 })
    return false
end)

exports('RequireAce', function(src, ace, label)
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, ace) then return true end
    cmdSend(src, ('ERROR: insufficient permission ( #%s )'):format(tostring(label or ace or 'admin')), CMD_RED, { 255, 77, 77 })
    return false
end)

exports('RequireSub', function(src, tier)
    if src == 0 then return true end
    local uid
    pcall(function() uid = exports['ph-core']:GetUserId(src) end)
    local ok = false
    if uid then pcall(function() ok = exports['ph_subscriptions']:HasSubscription(uid, tier) == true end) end
    if ok then return true end
    cmdSend(src, 'ERROR: You dont have a active subscription!', CMD_RED, { 255, 77, 77 })
    return false
end)

-- ----------------------------------------------------------
--  Notificari & mesaje STANDARD (folosite de toate resursele)
--
--    :Notify(src, text[, kind])  -> notificare simpla DEASUPRA MINIMAPULUI
--                                   kind = 'info' | 'success' | 'error' | 'warning'
--                                   pentru feedback marunt / confirmari
--    :Msg(src, text[, color])    -> mesaj in CHAT (pentru lucruri importante)
--    :StaffMsg(key, text[, color]) -> anunt in chat catre tot staff-ul cu
--                                   gradul >= Config.StaffMsgGrades[key];
--                                   prefixat "Staff: (staff >= <grad>) ..."
-- ----------------------------------------------------------
exports('Notify', function(src, text, kind)
    if not src or src == 0 then print('[notify] ' .. tostring(text)); return end
    TriggerClientEvent('ph-core:cl:notify', src, tostring(text), kind or 'info')
end)

exports('Msg', function(src, text, color)
    if not src or src == 0 then print(tostring(text)); return end
    if GetResourceState('ph_chat') == 'started' then
        exports['ph_chat']:send(src, { text = tostring(text), textColor = color or '#e8e6f0' })
    else
        TriggerClientEvent('chat:addMessage', src, { args = { tostring(text) } })
    end
end)

exports('StaffMsg', function(key, text, color)
    local grade = (Config.StaffMsgGrades and Config.StaffMsgGrades[key]) or Config.StaffMsgDefault or 'trialhelper'
    local line = ('Staff: (staff >= %s) %s'):format(grade, tostring(text))
    for _, sid in ipairs(GetPlayers()) do
        sid = tonumber(sid)
        local ok = false
        pcall(function() ok = exports['ph-core']:HasStaffRank(sid, grade) == true end)
        if ok then
            if GetResourceState('ph_chat') == 'started' then
                exports['ph_chat']:send(sid, { text = line, textColor = color or '#7f30ff' })
            else
                TriggerClientEvent('chat:addMessage', sid, { color = { 127, 48, 255 }, args = { line } })
            end
        end
    end
    print('^5[staff]^7 ' .. line)
end)

-- ----------------------------------------------------------
--  Comenzi utilitare (dev/admin)
-- ----------------------------------------------------------
RegisterCommand('phresetchar', function(src)
    if not exports['ph-core']:RequireAce(src, 'ph.admin', 'admin') then return end

    local player = PH.Players[src]
    if not player then
        if src == 0 then print('[ph-core] Use this command in-game.') end
        return
    end

    MySQL.update.await([[
        UPDATE users
        SET dob = NULL, appearance = NULL, gender = 0, height = 180,
            level = 1, rp = 0, money = 500, bank = 0, playtime = 0
        WHERE id = ?
    ]], { player.userId })
    player.character = nil
    PH.Log(('Character manually reset for user %d [src %d]'):format(player.userId, src))
    DropPlayer(src, 'Your character has been reset. Reconnect to create a new one.')
end, false)

-- ----------------------------------------------------------
--  La oprirea resursei salveaza tot
-- ----------------------------------------------------------
AddEventHandler('onResourceStop', function(resource)
    if resource ~= RES then return end
    for src, player in pairs(PH.Players) do
        if player.character then
            PH.Character.Save(src)
        end
    end
end)

CreateThread(function()
    Wait(1000)
    print('^5[ph-core]^7 Purple Havoc core loaded. Waiting for players...')
end)
