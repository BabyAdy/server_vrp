-- ==========================================================
--  staff_menu / staff_cmd  -  TOATE comenzile / ale staff menu-ului
--
--    /ticket   [category] [message]        (jucatori)
--    /heal     [sqlId]                     (staff >= trialadmin)
--    /revive   [sqlId]                     (staff >= trialadmin)
--    /dv                                   (staff >= trialadmin)
--    /fix                                  (staff >= generaladmin)
--    /flip                                 (staff >= generaladmin)
--    /maxperf                              (staff >= manager)
--    /spawncar [model]                     (staff >= generaladmin)
--    /setvw    [sqlId] [virtualWorld]      (staff >= trialadmin)
--    /doorinfo                             (staff >= developer)
--    /dvall                                (staff >= manager)
--    /givemoney  [sqlId] [amount]          (staff >= manager)  amount<0 = scade
--    /givebmoney [sqlId] [amount]          (staff >= manager)
--    /givepp     [sqlId] [amount]          (staff >= manager)
--
--  Helperele / starea traiesc in  server.lua  si sunt expuse prin `SMENV`
--  (fisierele din aceeasi resursa impart doar mediul global).
--  Noclip-ul e legat pe tasta -> ramane in  client.lua  (+phNoclip/-phNoclip).
-- ==========================================================
local PH_CORE = 'ph-core'
local E = SMENV

local charOf, notify, notifyStaff, toast = E.charOf, E.notify, E.notifyStaff, E.toast
local requirePerm, srcByUserId, logRaw   = E.requirePerm, E.srcByUserId, E.logRaw

-- /ticket (jucatori) e acum in resursa dedicata  ph_tickets  (meniu NUI).

-- ----------------------------------------------------------
--  /heal  si  /revive   (staff >= trialadmin)
--    fara argument -> pe tine ; cu <sqlId> -> pe jucatorul respectiv (online)
-- ----------------------------------------------------------
local function healTarget(src, args, action)
    if not requirePerm(src, action) then return end
    local tSrc = src
    if args[1] then
        local uid = tonumber(args[1])
        tSrc = uid and srcByUserId(uid) or nil
        if not tSrc then return toast(src, 'The player is not online.', 'error') end
    end

    TriggerClientEvent('staff_menu:cl:' .. action, tSrc)
    local sc = charOf(src)
    local tc = charOf(tSrc)
    logRaw(sc and sc.id, sc and sc.username, action, tc and ('target %s'):format(tc.id) or 'self')

    if tSrc == src then
        toast(src, action == 'heal' and 'You healed yourself (100% HP).' or 'You revived yourself (100% HP).', 'success')
    else
        toast(src, ('%s: %s (100%% HP).'):format(tc and tc.username or ('#' .. args[1]),
            action == 'heal' and 'healed' or 'revived'), 'success')
        notify(tSrc, action == 'heal'
            and 'You were healed by a staff member.'
            or  'You were revived by a staff member.', '#8ce07a')
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
    if not requirePerm(src, perm) then return end
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
    if model == '' then return exports[PH_CORE]:CmdSyntax(src, '/spawncar [model]') end
    vehCmd(src, 'spawncar', 'spawncar', model)
end, false)

-- ----------------------------------------------------------
--  /setvw <sqlId> <virtualWorld>   (staff >= trialadmin)
--    virtual world = routing bucket (0 = lumea normala)
-- ----------------------------------------------------------
RegisterCommand('setvw', function(src, args)
    if not requirePerm(src, 'setvw') then return end
    local uid = tonumber(args[1])
    local vw  = tonumber(args[2])
    if not uid or not vw then
        return exports[PH_CORE]:CmdSyntax(src, '/setvw [sqlId] [virtualWorld]')
    end
    local tSrc = srcByUserId(uid)
    if not tSrc then return toast(src, 'The player is not online.', 'error') end
    vw = math.max(0, math.floor(vw))
    SetPlayerRoutingBucket(tSrc, vw)
    TriggerClientEvent('staff_menu:cl:refreshDoors', tSrc)   -- re-incuie usile in noul virtual world
    local sc, tc = charOf(src), charOf(tSrc)
    logRaw(sc and sc.id, sc and sc.username, 'setvw', ('%s -> vw %d'):format(tc and tc.id or uid, vw))
    toast(src, ('%s -> virtual world %d.'):format(tc and tc.username or ('#' .. uid), vw), 'success')
    notify(tSrc, ('You were moved to virtual world %d by a staff member.'):format(vw), '#e0c07a')
end, false)

-- /doorinfo -> pe clientul apelantului: afiseaza model + coords ale usii din apropiere
RegisterCommand('doorinfo', function(src)
    if src == 0 then return end
    if not requirePerm(src, 'doorinfo') then return end
    TriggerClientEvent('staff_menu:cl:doorinfo', src)
end, false)

RegisterCommand('dvall', function(src)
    if not requirePerm(src, 'dvall') then return end
    local delay = Config.DvallDelaySec or 10
    local msg = ('STAFF: All unused vehicles will be deleted in %d seconds!'):format(delay)
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

-- ----------------------------------------------------------
--  /givemoney /givebmoney /givepp   (staff >= manager)
--    argument = SQL id ; `amount` negativ => scade (plafonat la 0).
--    Anunt catre staff >= GIVE_BROADCAST_GRADE (implicit trialadmin).
--      Staff: [grad] <actor> gave <target> [Id: <sqlId>] the amount of <amount> <Label>!
-- ----------------------------------------------------------
local GIVE_BROADCAST_GRADE = 'trialadmin'

local GIVE_DEFS = {
    givemoney  = { perm = 'givemoney',  field = 'money',         label = 'Money' },
    givebmoney = { perm = 'givebmoney', field = 'bank',          label = 'Bank Money' },
    givepp     = { perm = 'givepp',     field = 'premiumpoints', label = 'Premium Points' },
}

--- numar cu separator de mii ( . ), pastreaza semnul
local function fmtAmount(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(math.abs(n)):reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    return (n < 0 and '-' or '') .. s
end

local function nameOfUserId(uid)
    local s = srcByUserId(uid)
    local c = s and charOf(s)
    if c and c.username then return c.username end
    local row = MySQL.single.await('SELECT username FROM users WHERE id = ?', { uid })
    return (row and row.username) or ('#' .. tostring(uid))
end

local function broadcastGiveStaff(text)
    for _, sid in ipairs(GetPlayers()) do
        sid = tonumber(sid)
        if exports[PH_CORE]:HasStaffRank(sid, GIVE_BROADCAST_GRADE) then
            notify(sid, text, '#c9a3ff')
        end
    end
    print('^5[staff]^7 ' .. text)
end

local function doGive(src, cmdName, args)
    local def = GIVE_DEFS[cmdName]
    if not requirePerm(src, def.perm) then return end

    local uid    = tonumber(args[1])
    local amount = math.floor(tonumber(args[2]) or 0)
    if not uid or amount == 0 then
        return exports[PH_CORE]:CmdSyntax(src, ('/%s [sqlId] [amount]  (amount negativ = scade)'):format(cmdName))
    end

    local res = exports[PH_CORE]:AdjustBalance(uid, def.field, amount)
    if type(res) ~= 'table' then
        return toast(src, ('No user with id %s.'):format(uid), 'error')
    end
    local old, new = res.old, res.value
    if new == old then
        return toast(src, ('%s unchanged (cannot go below 0).'):format(def.label), 'warning')
    end

    local sc         = charOf(src)
    local actor      = (sc and sc.username) or 'console'
    local g          = exports[PH_CORE]:GetStaffGrade(sc and sc.staff or '')
    local gradeLabel = (g and g.label) or 'Staff'
    local targetName = nameOfUserId(uid)

    toast(src, ('%s: %s -> %s (%s to %s)'):format(
        def.label, fmtAmount(old), fmtAmount(new), fmtAmount(amount), targetName), 'success')

    broadcastGiveStaff(('Staff: [%s] %s gave %s [Id: %s] the amount of %s %s!'):format(
        gradeLabel, actor, targetName, uid, fmtAmount(amount), def.label))

    logRaw(sc and sc.id, actor, cmdName,
        ('%s %s -> #%s (%s => %s)'):format(fmtAmount(amount), def.field, uid, fmtAmount(old), fmtAmount(new)))
end

RegisterCommand('givemoney',  function(src, args) if src ~= 0 then doGive(src, 'givemoney',  args) end end, false)
RegisterCommand('givebmoney', function(src, args) if src ~= 0 then doGive(src, 'givebmoney', args) end end, false)
RegisterCommand('givepp',     function(src, args) if src ~= 0 then doGive(src, 'givepp',     args) end end, false)
