-- ==========================================================
--  ph_vehicles / commands  -  TOATE comenzile / ale resursei (server)
--  (argument <sqlId> = users.id, NU server id-ul de sesiune)
--
--    /v                              - deschide garajul personal (NUI)
--    /park                           - seteaza locul de parcare al masinii curente
--    /givekey  [sqlId]               - da cheile masinii tale unui jucator din raza de 50m
--    /throwkey                       - renunta la cheile imprumutate
--    /givecar  [sqlId] [model] [label?]   (ace ph.admin) - acorda un vehicul personal
--    /delcar   [vehId]                    (ace ph.admin) - sterge un vehicul personal
--    /setvehslots [sqlId] [n]             (ace ph.admin) - seteaza users.slots (merge offline)
--
--  Helperele traiesc in server.lua si sunt expuse prin VEHENV.
-- ==========================================================
local E  = VEHENV
local PH = E.PH

RegisterCommand('v', function(src)
    if src == 0 then print('[ph_vehicles] /v is used in-game.') return end
    E.sendList(src)
end, false)

RegisterCommand('park', function(src)
    if src == 0 then print('[ph_vehicles] /park is used in-game.') return end
    TriggerClientEvent('ph_vehicles:cl:parkQuery', src)
end, false)

RegisterCommand('givekey', function(src, args)
    if src == 0 then print('[ph_vehicles] /givekey is used in-game.') return end
    local targetUid = tonumber(args[1])
    if not targetUid then
        exports[PH]:CmdSyntax(src, '/givekey [sqlId]')
        return
    end
    TriggerClientEvent('ph_vehicles:cl:giveKeyQuery', src, targetUid)
end, false)

RegisterCommand('throwkey', function(src)
    if src == 0 then print('[ph_vehicles] /throwkey is used in-game.') return end
    E.throwKeys(src)
end, false)

local function doGiveCar(cmd, src, args, hasPerm)
    if not hasPerm(src) then return end
    local targetUid = tonumber(args[1])
    local model     = args[2]
    local label     = args[3] and table.concat(args, ' ', 3) or nil
    if not targetUid or not model then
        exports[PH]:CmdSyntax(src, ('/%s [sqlId] [model] [label?]'):format(cmd))
        return
    end
    local id, err = E.grant(targetUid, model, { label = label })
    if not id then
        E.notify(src, ('%s failed: %s'):format(cmd, err or '?'), 'error')
        return
    end
    E.notify(src, ('Granted vehicle #%d (%s) to user %d.'):format(id, model, targetUid), 'success')
    print(('[ph_vehicles] %s: %s -> user %d (veh #%d) by src %d'):format(cmd, model, targetUid, id, src))
end

-- /vcreate : staff >= manager   |   /givecar : ace ph.admin / consola
RegisterCommand('vcreate', function(src, args)
    doGiveCar('vcreate', src, args, function(s) return exports[PH]:RequireStaff(s, 'manager') end)
end, false)
RegisterCommand('givecar', function(src, args)
    doGiveCar('givecar', src, args, function(s) return exports[PH]:RequireAce(s, 'ph.admin', 'admin') end)
end, false)

RegisterCommand('delcar', function(src, args)
    if not exports[PH]:RequireAce(src, 'ph.admin', 'admin') then return end
    local vehId = tonumber(args[1])
    if not vehId then
        exports[PH]:CmdSyntax(src, '/delcar [vehId]')
        return
    end
    if E.remove(vehId) then
        E.notify(src, ('Vehicle #%d removed.'):format(vehId), 'success')
        print(('[ph_vehicles] delcar: veh #%d by src %d'):format(vehId, src))
    else
        E.notify(src, ('No vehicle #%d.'):format(vehId), 'error')
    end
end, false)

RegisterCommand('setvehslots', function(src, args)
    if not exports[PH]:RequireAce(src, 'ph.admin', 'admin') then return end
    local targetUid = tonumber(args[1])
    local n         = tonumber(args[2])
    if not targetUid or not n then
        exports[PH]:CmdSyntax(src, '/setvehslots [sqlId] [n]')
        return
    end
    local set = E.setSlots(targetUid, n)
    if not set then
        E.notify(src, ('setvehslots: no user with id %d.'):format(targetUid), 'error')
        return
    end
    E.notify(src, ('User %d vehicle slots set to %d.'):format(targetUid, set), 'success')
    local tsrc = E.srcOf(targetUid)
    if tsrc then E.chat(tsrc, ('Your vehicle slots were set to %d.'):format(set), '#8ce07a') end
    print(('[ph_vehicles] setvehslots: user %d -> %d by src %d'):format(targetUid, set, src))
end, false)
