-- ==========================================================
--  ph_chat / commands  -  TOATE comenzile / ale resursei
--
--    /pc [message]   - Premium Chat (staff, sau abonament activ)
--
--  Helperele traiesc in server.lua si sunt expuse prin `CHATENV`.
--  Deschiderea chat-ului pe tasta (phChatOpen/phChatCmd) ramane in client.lua.
-- ==========================================================
local E = CHATENV
local PH = E.PH

RegisterCommand('pc', function(src, args)
    if src == 0 then return end
    local SETTINGS = E.settings()
    local msg = E.clean(table.concat(args, ' '))
    local uid = E.sqlId(src)
    local staff = E.isStaff(src)

    local tier
    if not staff then
        pcall(function() tier = exports['ph_subscriptions']:GetActiveTier(uid) end)
    end
    if not staff and not tier then
        exports[PH]:CmdSubError(src)
        return
    end
    if msg == '' then
        exports[PH]:CmdSyntax(src, '/pc [message]')
        return
    end

    -- eticheta + culoarea ei
    local tagText, tagColor
    if staff then
        local pub = exports[PH]:GetPublicPlayer(src)
        tagText  = (pub and pub.staffLabel) or 'Staff'
        tagColor = (pub and pub.staffColor) or '#37ff00'
    else
        local ti = exports['ph_subscriptions']:GetTierInfo(tier) or {}
        tagText  = ti.label or tier
        tagColor = ti.color or '#8c00ff'
    end

    local name = GetPlayerName(src) or ('Player_' .. src)
    local body = Config.PremiumChat.TextColor or '#8c00ff'
    local payload = {
        stamp = E.roStamp(),
        segments = {
            { t = (Config.PremiumChat.Prefix or '(/pc)') .. ' ', c = body },
            { t = ('[%s] '):format(tagText), c = tagColor },
            { t = name .. ': ', c = body },
            { t = msg, c = body },
        },
    }

    -- destinatari: eligibili (staff >= min SAU abonament activ) care nu au ascuns canalul.
    -- expeditorul primeste mesajul indiferent de setare.
    local sent = {}
    for _, tuid in ipairs(exports[PH]:GetOnlineUserIds() or {}) do
        local tsrc = E.srcOf(tuid)
        if tsrc then
            local eligible = E.isStaff(tsrc) or E.hasSub(tuid)
            local hidden = SETTINGS[tuid] and SETTINGS[tuid].pcHidden
            if tuid == uid or (eligible and not hidden) then
                TriggerClientEvent('ph_chat:receive', tsrc, payload)
                sent[tsrc] = true
            end
        end
    end
    if not sent[src] then TriggerClientEvent('ph_chat:receive', src, payload) end

    print(('[pc] %s: %s'):format(name, msg))
end, false)
