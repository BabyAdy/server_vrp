-- ==========================================================
--  ph_inventory / commands  -  TOATE comenzile / ale resursei
--  (argument <sqlId> = users.id, NU server id-ul de sesiune)
--
--    /giveitem [sqlId] [item] [count]   (ace ph.admin)  - da iteme
--    /setslots [sqlId] [slots]          (ace ph.admin)  - merge si offline
--
--  Helperele traiesc in server.lua si sunt expuse prin `INVENV`.
--  Tasta de inventar (+ph_inv/-ph_inv) ramane in client.lua.
-- ==========================================================
local E = INVENV
local PH = E.PH
local toInt, notify = E.toInt, E.notify
local addItem, saveInv, srcOf, pushState = E.addItem, E.saveInv, E.srcOf, E.pushState
local sanitizeHotbar, shrinkTo = E.sanitizeHotbar, E.shrinkTo

RegisterCommand('giveitem', function(src, args)
    if not exports[PH]:RequireAce(src, 'ph.admin', 'admin') then return end
    local targetUid = toInt(args[1])
    local name      = args[2]
    local count     = toInt(args[3]) or 1
    if not targetUid or not name or not Config.Items[name] then
        exports[PH]:CmdSyntax(src, '/giveitem [sqlId] [item] [count]')
        return
    end
    if not E.inv()[targetUid] then
        notify(src, ('giveitem: user %s has no inventory loaded (offline?).'):format(targetUid), '#ff4d4d')
        return
    end
    if addItem(targetUid, name, count) then
        saveInv(targetUid)
        local tsrc = srcOf(targetUid)
        if tsrc then
            pushState(tsrc)
            notify(tsrc, ('You received %dx %s'):format(count, Config.Items[name].label), '#8ce07a')
        end
        print(('giveitem: %dx %s -> user %s'):format(count, name, targetUid))
    end
end, false)

--  Merge si pe jucatori offline (scrie in DB; se aplica la urmatoarea conectare).
RegisterCommand('setslots', function(src, args)
    if not exports[PH]:RequireAce(src, 'ph.admin', 'admin') then return end
    local targetUid = toInt(args[1])
    local n         = toInt(args[2])
    if not targetUid or not n then exports[PH]:CmdSyntax(src, '/setslots [sqlId] [slots]') return end
    n = math.max(Config.DefaultSlots, math.min(Config.MaxSlots, n))

    local aff = MySQL.update.await('UPDATE users SET inv_slots = ? WHERE id = ?', { n, targetUid })
    if not aff or aff == 0 then
        notify(src, ('setslots: no user with id %s.'):format(targetUid), '#ff4d4d')
        return
    end
    local inv = E.inv()[targetUid]
    if inv then
        inv.baseSlots = n
        local newSlots = n + (inv.subBonus or 0)
        if newSlots >= inv.slots then
            inv.slots = newSlots
            sanitizeHotbar(inv)
        else
            shrinkTo(targetUid, newSlots)
        end
        saveInv(targetUid)
        local tsrc = srcOf(targetUid)
        if tsrc then pushState(tsrc) end
    end
    print(('base slots for user %s set to %d (+%d bonus)'):format(
        targetUid, n, inv and inv.subBonus or 0))
end, false)
