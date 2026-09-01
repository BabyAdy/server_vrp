-- ==========================================================
--  ph_factions / faction_cmd  -  TOATE comenzile / ale factiunilor
--
--  CLIENT:
--    /factionmenu                                  - meniul de factiune (faction_rank >= 6)
--    /devfactionmenu                               - meniul de dezvoltator (staff >= developer)
--
--  SERVER:
--    /duty                                         - on/off duty
--    /fcreate       [faction name]                 (staff >= DevGrade)
--    /fsetleader    [factionId] [sqlId]            (staff >= DevGrade)
--    /fseedvanilla  [factionId] [minRank]          (staff >= DevGrade)
--    /fdelete       [factionId]                    (staff >= DevGrade)
--    /setleader     [sqlId] [factionId]            (staff >= leadadmin)
--    /setfmember    [sqlId] [factionId] [rank 1-7] (staff >= manager)
--    /makeleader    [sqlId] [factionId]            (staff >= manager)
--    /changerankname [factionId] [rank] [name]     (staff >= manager)
--    /auninvite | /uninvite  [sqlId] [reason]      (staff >= leadadmin)
--    /removeleader  [sqlId] [reason]               (staff >= leadadmin)
--
--  Fisierul e incarcat si pe client, si pe server (vezi fxmanifest).  Helperele
--  si starea (FACTIONS/MEMBER/DUTY, notify, rpName, ...) sunt globale la nivel de
--  resursa in server.lua, deci sunt vizibile aici fara alt boilerplate.
-- ==========================================================

if not IsDuplicityVersion() then
    -- ================= CLIENT =================
    RegisterCommand('factionmenu', function()
        TriggerServerEvent('ph_factions:sv:openMenu')
    end, false)
    RegisterCommand('devfactionmenu', function()
        TriggerServerEvent('ph_factions:sv:openDevMenu')
    end, false)
    return
end

-- ================= SERVER =================

-- ----------------------------------------------------------
--  /duty
-- ----------------------------------------------------------
RegisterCommand('duty', function(src)
    if src == 0 then return end
    local uid = uidOf(src)
    local m = uid and MEMBER[uid]
    if not m or m.faction == 0 then
        return notify(src, 'ERROR: you are not in a faction', '#ff4d4d')
    end
    DUTY[uid] = not DUTY[uid]
    local name = rpName(src)
    if DUTY[uid] then
        announceLocal(src, ('%s is now on duty!'):format(name), Config.DutyColorOn)
    else
        announceLocal(src, ('%s is now off duty!'):format(name), Config.DutyColorOff)
    end
    pushSelf(src)
end, false)

-- ----------------------------------------------------------
--  Comenzi de administrare (staff >= developer) - varianta rapida
-- ----------------------------------------------------------
RegisterCommand('fcreate', function(src, args)
    if not exports['ph-core']:RequireStaff(src, Config.DevGrade) then return end
    local name = table.concat(args, ' '):gsub('^%s+',''):gsub('%s+$','')
    if #name < 3 then exports['ph-core']:CmdSyntax(src, '/fcreate [faction name]'); return end
    if MySQL.scalar.await('SELECT id FROM factions WHERE f_name = ?', { name }) then
        return notify(src, 'Name already in use.', '#e07a7a')
    end
    local id = MySQL.insert.await('INSERT INTO factions (f_name, f_short, ranks) VALUES (?,?,?)',
        { name, name:sub(1,3):upper(), enc(Config.DefaultRanks) })
    reloadFaction(id); pushPublic(-1)
    exports['ph-core']:StaffMsg('faction', ('%s created faction #%d "%s". Use /factionmenu (Developer tab) or /fsetleader %d <sqlId>.'):format(rpName(src), id, name, id))
end, false)

RegisterCommand('fsetleader', function(src, args)
    if not exports['ph-core']:RequireStaff(src, Config.DevGrade) then return end
    local fid = tonumber(args[1]); local target = tonumber(args[2])
    if not fid or not target or not FACTIONS[fid] then exports['ph-core']:CmdSyntax(src, '/fsetleader [factionId] [sqlId]'); return end
    if not MySQL.scalar.await('SELECT id FROM users WHERE id = ?', { target }) then
        return notify(src, 'No such user.', '#e07a7a')
    end
    MySQL.update.await('UPDATE factions SET leader = ? WHERE id = ?', { target, fid })
    setMemberFaction(target, fid, Config.RankLeader)
    reloadFaction(fid)
    exports['ph-core']:StaffMsg('faction', ('%s set the leader of faction #%d (user %d).'):format(rpName(src), fid, target))
end, false)

RegisterCommand('fseedvanilla', function(src, args)
    if not exports['ph-core']:RequireStaff(src, Config.DevGrade) then return end
    local fid = tonumber(args[1]); local mr = tonumber(args[2]) or Config.SeedDefaultMinRank
    if not fid or not FACTIONS[fid] then exports['ph-core']:CmdSyntax(src, '/fseedvanilla [factionId] [minRank]'); return end
    local n, err = seedVanillaInto(fid, mr)
    if not n then return notify(src, err or 'error', '#e07a7a') end
    SetTimeout(800, function() reloadFaction(fid) end)
    exports['ph-core']:StaffMsg('faction', ('%s added %d vanilla vehicles to faction #%d (min rank %d).'):format(rpName(src), n, fid, mr))
end, false)

RegisterCommand('fdelete', function(src, args)
    if not exports['ph-core']:RequireStaff(src, Config.DevGrade) then return end
    local fid = tonumber(args[1])
    if not fid or not FACTIONS[fid] then exports['ph-core']:CmdSyntax(src, '/fdelete [factionId]'); return end
    MySQL.query.await('UPDATE users SET faction=0, faction_rank=0, is_tester=0, is_supervisor=0, faction_warns=0, faction_join=NULL WHERE faction=?', { fid })
    MySQL.query.await('DELETE FROM faction_vehicles WHERE faction_id=?', { fid })
    MySQL.query.await('DELETE FROM factions WHERE id=?', { fid })
    for tuid, mm in pairs(MEMBER) do if mm.faction == fid then setMemberFaction(tuid, 0, 0) end end
    FACTIONS[fid] = nil; pushPublic(-1)
    exports['ph-core']:StaffMsg('faction', ('%s deleted faction #%d.'):format(rpName(src), fid))
end, false)

-- ----------------------------------------------------------
--  Comenzi de staff (grad din ph-core), argument = SQL id (users.id)
-- ----------------------------------------------------------

--- /setleader <sqlId> <factionId>   (staff >= leadadmin)
--  faction = factionId, faction_rank = 7  SI  factions.leader = sqlId
RegisterCommand('setleader', function(src, args)
    if not staffAtLeast(src, 'leadadmin') then
        exports['ph-core']:CmdPermError(src, 'leadadmin')
        return
    end
    local uid = tonumber(args[1]); local fid = tonumber(args[2])
    if not uid or not fid then
        return exports['ph-core']:CmdSyntax(src, '/setleader [sqlId] [factionId]')
    end
    if not FACTIONS[fid] then return notify(src, ('Faction #%s does not exist.'):format(fid), '#e07a7a') end
    if not adminSetMembership(uid, fid, Config.RankLeader, true) then
        return notify(src, ('No user with id %s.'):format(uid), '#e07a7a')
    end
    MySQL.update.await('UPDATE factions SET leader = ? WHERE id = ?', { uid, fid })
    reloadFaction(fid)
    pushFactionMembers(fid)
    pushPublic(-1)
    flog(fid, uidOf(src) or nil, 'admin_setleader', uid, nameOfUser(uid))
    exports['ph-core']:StaffMsg('faction', ('%s made user %s Leader (rank 7) of faction #%d and set factions.leader.'):format(rpName(src), uid, fid))
end, false)

--- /setfmember <sqlId> <factionId> <rank>   (staff >= manager)
RegisterCommand('setfmember', function(src, args)
    if not staffAtLeast(src, 'manager') then
        exports['ph-core']:CmdPermError(src, 'manager')
        return
    end
    local uid  = tonumber(args[1])
    local fid  = tonumber(args[2])
    local rank = tonumber(args[3])
    if not uid or not fid or not rank then
        return exports['ph-core']:CmdSyntax(src, '/setfmember [sqlId] [factionId] [rank 1-7]')
    end
    if fid ~= 0 and not FACTIONS[fid] then return notify(src, ('Faction #%s does not exist.'):format(fid), '#e07a7a') end
    rank = math.max(1, math.min(Config.RankCount, math.floor(rank)))
    if fid == 0 then rank = 0 end
    if not adminSetMembership(uid, fid, rank, false) then
        return notify(src, ('No user with id %s.'):format(uid), '#e07a7a')
    end
    if FACTIONS[fid] then reloadFaction(fid); pushFactionMembers(fid) end
    flog(fid, uidOf(src) or nil, 'admin_setmember', uid, nameOfUser(uid), 'rank ' .. rank)
    exports['ph-core']:StaffMsg('faction', ('%s moved user %s to faction #%d, rank %d.'):format(rpName(src), uid, fid, rank))
end, false)

--- /makeleader <sqlId> <factionId>   (staff >= manager)
--  faction = factionId, faction_rank = 7  FARA a modifica factions.leader
RegisterCommand('makeleader', function(src, args)
    if not staffAtLeast(src, 'manager') then
        exports['ph-core']:CmdPermError(src, 'manager')
        return
    end
    local uid = tonumber(args[1]); local fid = tonumber(args[2])
    if not uid or not fid then
        return exports['ph-core']:CmdSyntax(src, '/makeleader [sqlId] [factionId]')
    end
    if not FACTIONS[fid] then return notify(src, ('Faction #%s does not exist.'):format(fid), '#e07a7a') end
    if not adminSetMembership(uid, fid, Config.RankLeader, true) then
        return notify(src, ('No user with id %s.'):format(uid), '#e07a7a')
    end
    pushFactionMembers(fid)
    flog(fid, uidOf(src) or nil, 'admin_makeleader', uid, nameOfUser(uid))
    exports['ph-core']:StaffMsg('faction', ('%s set user %s to rank 7 in faction #%d (factions.leader NOT changed).'):format(rpName(src), uid, fid))
end, false)

--- /changerankname <factionId> <rank> <nume nou...>   (staff >= manager)
RegisterCommand('changerankname', function(src, args)
    if not staffAtLeast(src, 'manager') then
        exports['ph-core']:CmdPermError(src, 'manager')
        return
    end
    local fid  = tonumber(args[1])
    local rank = tonumber(args[2])
    local name = table.concat(args, ' ', 3):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 32)
    if not fid or not rank or #name < 1 then
        return exports['ph-core']:CmdSyntax(src, '/changerankname [factionId] [rank 1-7] [new name]')
    end
    local f = FACTIONS[fid]
    if not f then return notify(src, ('Faction #%s does not exist.'):format(fid), '#e07a7a') end
    rank = math.floor(rank)
    if rank < 1 or rank > Config.RankCount then
        return notify(src, ('Invalid rank (1-%d).'):format(Config.RankCount), '#e07a7a')
    end
    f.ranks[rank] = name
    MySQL.update.await('UPDATE factions SET ranks = ? WHERE id = ?', { enc(f.ranks), fid })
    pushFactionMembers(fid)
    flog(fid, uidOf(src) or nil, 'admin_rankname', nil, nil, ('rank %d = %s'):format(rank, name))
    exports['ph-core']:StaffMsg('faction', ('%s renamed faction #%d rank %d to "%s".'):format(rpName(src), fid, rank, name))
end, false)

--- scoate userId din factiune (online sau offline).  online -> si din interiorul HQ.
local function forceRemoveFromFaction(userId, reason)
    userId = tonumber(userId)
    if not userId then return false end
    if not MySQL.scalar.await('SELECT id FROM users WHERE id = ?', { userId }) then return false end
    if srcOf(userId) and MEMBER[userId] and MEMBER[userId].faction ~= 0 then
        kickMember(userId, reason)     -- eject din HQ + cache + save + notify + flog
    else
        adminSetMembership(userId, 0, 0, false)
    end
    return true
end

--- curata argumentul de motiv (accepta si prefixul literal "reason:")
local function reasonFrom(args, i)
    local r = table.concat(args, ' ', i or 2):gsub('^%s+', ''):gsub('%s+$', '')
    r = r:gsub('^[Rr]eason:%s*', '')
    return r ~= '' and r:sub(1, 200) or nil
end

--- /auninvite <sqlId> [reason]   (staff >= leadadmin)
--  faction = 0, faction_rank = 0, is_tester = 0, is_supervisor = 0 (+ warns/join curatate)
local function doAuninvite(src, args)
    if not staffAtLeast(src, 'leadadmin') then
        exports['ph-core']:CmdPermError(src, 'leadadmin')
        return
    end
    local uid = tonumber(args[1])
    if not uid then return exports['ph-core']:CmdSyntax(src, '/auninvite [sqlId] [reason]') end
    local reason = reasonFrom(args, 2)
    if not forceRemoveFromFaction(uid, reason or 'auninvite') then
        return notify(src, ('No user with id %s.'):format(uid), '#e07a7a')
    end
    flog(0, uidOf(src) or nil, 'admin_auninvite', uid, nameOfUser(uid), reason)
    exports['ph-core']:StaffMsg('faction', ('%s removed user %s from their faction%s.'):format(rpName(src), uid, reason and (' — ' .. reason) or ''))
end
RegisterCommand('auninvite', doAuninvite, false)
RegisterCommand('uninvite', doAuninvite, false)

--- /removeleader <sqlId> [reason]   (staff >= leadadmin)
--  ca /auninvite + il scoate din `factions.leader` oriunde ar fi asignat
RegisterCommand('removeleader', function(src, args)
    if not staffAtLeast(src, 'leadadmin') then
        exports['ph-core']:CmdPermError(src, 'leadadmin')
        return
    end
    local uid = tonumber(args[1])
    if not uid then return exports['ph-core']:CmdSyntax(src, '/removeleader [sqlId] [reason]') end
    local reason = reasonFrom(args, 2)

    if not MySQL.scalar.await('SELECT id FROM users WHERE id = ?', { uid }) then
        return notify(src, ('No user with id %s.'):format(uid), '#e07a7a')
    end

    -- scoate-l din leader oriunde e asignat
    local rows = MySQL.query.await('SELECT id FROM factions WHERE leader = ?', { uid }) or {}
    MySQL.update.await('UPDATE factions SET leader = NULL WHERE leader = ?', { uid })

    forceRemoveFromFaction(uid, reason or 'removeleader')

    for _, r in ipairs(rows) do
        reloadFaction(r.id)
        pushFactionMembers(r.id)
    end
    pushPublic(-1)
    flog(0, uidOf(src) or nil, 'admin_removeleader', uid, nameOfUser(uid), reason)
    exports['ph-core']:StaffMsg('faction', ('%s removed user %s from their faction and from factions.leader (%d faction(s))%s.')
        :format(rpName(src), uid, #rows, reason and (' — ' .. reason) or ''))
end, false)
