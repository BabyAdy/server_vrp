-- ==========================================================
--  ph_clans / clan_cmd  -  TOATE comenzile / ale clanurilor
--
--  CLIENT: (nimic in Faza 1 - meniul /clan vine in Faza 2)
--
--  SERVER:
--    /c <mesaj>                     - chat de clan
--    /togc                          - ascunde / arata clan chat-ul
--    /quitclan                      - iesire din clan (nu si liderul)
--    /cinvite [sqlId]               - invita (rank >= 5 sau permisiune "invite"), raza 50m
--    /acceptcinvite [sqlId]         - accepta invitatia (raza 50m)
--    /cdeposit [pp|money] [amount]  - depune in safebox-ul clanului
--    /lockclanchat [rank]           - clan_rank >= 6
--    /unlockclanchat                - clan_rank >= 6
--    /cmotd [mesaj]                 - clan_rank >= 6
--    /clantag [1-6]                 - alege stilul de tag
--    /clanreq list|accept <id>|reject <id>   - staff >= leadadmin
--    /editclan <id> <field> <value> - staff >= manager  (field: name|tag|days|money|pp|cp)
--
--  Fisierul e incarcat si pe client, si pe server (vezi fxmanifest).
-- ==========================================================

if not IsDuplicityVersion() then
    -- ================= CLIENT ================= (Faza 2: /clan)
    return
end

-- ================= SERVER =================
local E = CLANENV
local PH = E.PH
local CLANS, MEMBER, INVITES = E.CLANS, E.MEMBER, E.INVITES

local function syntax(src, usage) exports[PH]:CmdSyntax(src, usage) end
local function permErr(src, needed) exports[PH]:CmdPermError(src, needed) end

--- returneaza uid, member, clan (sau nil + trimite eroare)
local function need(src, opts)
    opts = opts or {}
    local uid = E.uidOf(src)
    local m = uid and MEMBER[uid]
    if not m or m.clan == 0 then
        E.notify(src, 'You are not in a clan.', 'error')
        return nil
    end
    local c = CLANS[m.clan]
    if not c then E.notify(src, 'Your clan no longer exists.', 'error') return nil end
    if opts.active ~= false and not c.active then
        E.notify(src, 'Your clan is inactive (0 days left).', 'error')
        return nil
    end
    if opts.minRank and m.rank < opts.minRank then
        permErr(src, 'clan rank ' .. opts.minRank)
        return nil
    end
    return uid, m, c
end

-- ----------------------------------------------------------
--  /c  /togc
-- ----------------------------------------------------------
RegisterCommand('c', function(src, args)
    if src == 0 then return end
    local msg = table.concat(args, ' ')
    if msg:gsub('%s', '') == '' then return syntax(src, '/c [message]') end
    E.clanChat(src, msg)
end, false)

RegisterCommand('togc', function(src)
    if src == 0 then return end
    local uid, m = need(src, { active = false })
    if not uid then return end
    m.chatHidden = not m.chatHidden
    E.saveMember(uid)
    E.notify(src, m.chatHidden and 'Clan chat hidden. You will not see or send /c messages.' or 'Clan chat shown.', 'info')
end, false)

-- ----------------------------------------------------------
--  /quitclan
-- ----------------------------------------------------------
RegisterCommand('quitclan', function(src)
    if src == 0 then return end
    local uid, m, c = need(src, { active = false })
    if not uid then return end
    if m.rank >= Config.RankLeader then
        return E.notify(src, 'The clan leader cannot use this command. Transfer leadership or let a manager delete the clan.', 'error')
    end
    local cid = m.clan
    m.clan, m.rank, m.warns, m.perms, m.join = 0, 0, 0, {}, nil
    E.saveMember(uid)
    E.clog(cid, uid, 'quit', uid)
    E.notify(src, ('You left %s.'):format(c.name), 'info')
end, false)

-- ----------------------------------------------------------
--  /cinvite  /acceptcinvite
-- ----------------------------------------------------------
RegisterCommand('cinvite', function(src, args)
    if src == 0 then return end
    local uid, m, c = need(src)
    if not uid then return end
    if m.rank < Config.InviteRank and not m.perms.invite then
        return permErr(src, 'clan rank ' .. Config.InviteRank .. ' or Invite permission')
    end
    local targetUid = tonumber(args[1])
    if not targetUid then return syntax(src, '/cinvite [sqlId]') end
    if targetUid == uid then return E.notify(src, 'You cannot invite yourself.', 'warning') end

    local tsrc = E.srcOf(targetUid)
    if not tsrc then return E.notify(src, ('Player #%d is not online.'):format(targetUid), 'error') end

    local tm = MEMBER[targetUid]
    if tm and tm.clan ~= 0 then return E.notify(src, 'That player is already in a clan.', 'warning') end
    if not E.withinRange(src, tsrc, Config.InviteRadius) then
        return E.notify(src, ('Player must be within %dm.'):format(math.floor(Config.InviteRadius)), 'error')
    end

    INVITES[targetUid] = { clan = m.clan, byUid = uid, byName = E.rpName(src), expires = os.time() + Config.InviteTimeoutSec }
    E.notify(src, ('Invitation sent to %s.'):format(E.rpName(tsrc)), 'success')
    E.chat(tsrc, ('%s invited you to the clan %s. Type /acceptcinvite %d within %ds (stay within %dm).')
        :format(E.rpName(src), c.name, uid, Config.InviteTimeoutSec, math.floor(Config.InviteRadius)), '#cfc9e6')
end, false)

RegisterCommand('acceptcinvite', function(src, args)
    if src == 0 then return end
    local uid = E.uidOf(src)
    if not uid then return end
    local inviterSqlId = tonumber(args[1])
    if not inviterSqlId then return syntax(src, '/acceptcinvite [sqlId]') end

    local inv = INVITES[uid]
    if not inv or inv.byUid ~= inviterSqlId then
        return E.notify(src, 'You have no pending invite from that player.', 'error')
    end
    if os.time() > inv.expires then
        INVITES[uid] = nil
        return E.notify(src, 'That invitation has expired.', 'warning')
    end
    local c = CLANS[inv.clan]
    if not c or not c.active then
        INVITES[uid] = nil
        return E.notify(src, 'That clan is no longer available.', 'error')
    end
    if MEMBER[uid] and MEMBER[uid].clan ~= 0 then
        INVITES[uid] = nil
        return E.notify(src, 'You are already in a clan.', 'warning')
    end
    local isrc = E.srcOf(inviterSqlId)
    if not isrc then return E.notify(src, 'The inviter went offline.', 'error') end
    if not E.withinRange(src, isrc, Config.InviteRadius) then
        return E.notify(src, ('You must be within %dm of the inviter.'):format(math.floor(Config.InviteRadius)), 'error')
    end

    local m = MEMBER[uid] or E.loadMember(uid)
    m.clan, m.rank, m.warns, m.perms = inv.clan, 1, 0, {}
    m.join = os.date('%Y-%m-%d %H:%M:%S')
    MEMBER[uid] = m
    E.saveMember(uid)
    INVITES[uid] = nil
    E.clog(inv.clan, inviterSqlId, 'invite', uid)
    E.notify(src, ('You joined %s.'):format(c.name), 'success')
    E.notify(isrc, ('%s joined your clan.'):format(E.rpName(src)), 'success')
end, false)

-- ----------------------------------------------------------
--  /cdeposit
-- ----------------------------------------------------------
RegisterCommand('cdeposit', function(src, args)
    if src == 0 then return end
    local uid, m, c = need(src)
    if not uid then return end
    local kind = tostring(args[1] or ''):lower()
    local amount = math.floor(tonumber(args[2]) or 0)
    if (kind ~= 'pp' and kind ~= 'money') or amount <= 0 then
        return syntax(src, '/cdeposit [pp|money] [amount]')
    end
    local field = kind == 'pp' and 'premiumpoints' or 'money'
    local ch = exports[PH]:GetCharacter(src)
    if not ch or (tonumber(ch[field]) or 0) < amount then
        return E.notify(src, ('Not enough %s.'):format(kind == 'pp' and 'Premium Points' or 'money'), 'error')
    end
    local res = exports[PH]:AdjustBalance(uid, field, -amount)
    if not res or res.delta ~= -amount then
        if res and res.delta and res.delta ~= 0 then exports[PH]:AdjustBalance(uid, field, -res.delta) end
        return E.notify(src, 'Deposit failed.', 'error')
    end
    E.adjustSafebox(c.id, kind == 'pp' and 'pp' or 'money', amount)
    E.clog(c.id, uid, 'deposit', nil, ('%d %s'):format(amount, kind))
    E.notify(src, ('Deposited %d %s into the clan safebox.'):format(amount, kind == 'pp' and 'PP' or '$'), 'success')
end, false)

-- ----------------------------------------------------------
--  /lockclanchat  /unlockclanchat  /cmotd
-- ----------------------------------------------------------
RegisterCommand('lockclanchat', function(src, args)
    if src == 0 then return end
    local uid, m, c = need(src, { minRank = Config.RankCoLeader })
    if not uid then return end
    local raw = tonumber(args[1])
    if not raw then return syntax(src, '/lockclanchat [rank 1-' .. Config.RankCount .. ']') end
    local n = math.max(1, math.min(Config.RankCount, math.floor(raw)))
    c.chatLockRank = n
    MySQL.update('UPDATE clans SET chat_lock_rank = ? WHERE id = ?', { n, c.id })
    E.clog(c.id, uid, 'chatlock', nil, 'rank ' .. n)
    E.notify(src, ('Clan chat locked to rank %d and above.'):format(n), 'success')
end, false)

RegisterCommand('unlockclanchat', function(src)
    if src == 0 then return end
    local uid, m, c = need(src, { minRank = Config.RankCoLeader })
    if not uid then return end
    c.chatLockRank = 1
    MySQL.update('UPDATE clans SET chat_lock_rank = 1 WHERE id = ?', { c.id })
    E.clog(c.id, uid, 'chatunlock')
    E.notify(src, 'Clan chat unlocked for all members.', 'success')
end, false)

RegisterCommand('cmotd', function(src, args)
    if src == 0 then return end
    local uid, m, c = need(src, { minRank = Config.RankCoLeader })
    if not uid then return end
    local msg = table.concat(args, ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 200)
    c.motd = msg
    MySQL.update('UPDATE clans SET motd = ? WHERE id = ?', { msg, c.id })
    E.clog(c.id, uid, 'motd', nil, msg)
    if msg == '' then
        E.notify(src, 'Clan MOTD cleared.', 'info')
    else
        for _, tuid in ipairs(exports[PH]:GetOnlineUserIds() or {}) do
            local tm = MEMBER[tuid]
            if tm and tm.clan == c.id then
                local s = E.srcOf(tuid)
                if s then E.chat(s, ('[Clan MOTD] %s'):format(msg), c.chatColor) end
            end
        end
    end
end, false)

-- ----------------------------------------------------------
--  /clantag [1-6]
-- ----------------------------------------------------------
RegisterCommand('clantag', function(src, args)
    if src == 0 then return end
    local uid, m = need(src, { active = false })
    if not uid then return end
    local n = tonumber(args[1])
    if not n or n < 1 or n > #Config.TagStyles then
        E.notify(src, 'Tag styles: 1 [TAG] Name | 2 Name [TAG] | 3 TAG. Name | 4 Name .TAG | 5 TAG Name | 6 Name TAG', 'info')
        return syntax(src, '/clantag [1-' .. #Config.TagStyles .. ']')
    end
    m.tagStyle = math.floor(n) - 1
    E.saveMember(uid)
    E.notify(src, ('Clan tag style set to %d.'):format(math.floor(n)), 'success')
end, false)

-- ----------------------------------------------------------
--  /clanreq   (staff >= leadadmin)
-- ----------------------------------------------------------
RegisterCommand('clanreq', function(src, args)
    if not E.staffAtLeast(src, Config.RequestGrade) then return permErr(src, Config.RequestGrade) end
    local sub = tostring(args[1] or ''):lower()

    if sub == 'list' or sub == '' then
        local rows = MySQL.query.await(
            "SELECT id, user_id, c_name, c_tag, created_at FROM clan_requests WHERE status = 'pending' ORDER BY id") or {}
        if #rows == 0 then return E.notify(src, 'No pending clan requests.', 'info') end
        E.chat(src, ('Pending clan requests (%d):'):format(#rows), '#b98cff')
        for _, r in ipairs(rows) do
            E.chat(src, ('  #%d  user %d (%s)  "%s" [%s]  — /clanreq accept %d | /clanreq reject %d')
                :format(r.id, r.user_id, E.nameOfUser(r.user_id) or '?', r.c_name, r.c_tag, r.id, r.id), '#cfc9e6')
        end
        return
    end

    local reqId = tonumber(args[2])
    if (sub ~= 'accept' and sub ~= 'reject') or not reqId then
        return syntax(src, '/clanreq list | accept <id> | reject <id>')
    end
    local r = MySQL.single.await("SELECT * FROM clan_requests WHERE id = ? AND status = 'pending'", { reqId })
    if not r then return E.notify(src, ('No pending request #%d.'):format(reqId), 'error') end

    if sub == 'reject' then
        MySQL.update.await("UPDATE clan_requests SET status = 'rejected', decided_by = ? WHERE id = ?", { E.uidOf(src), reqId })
        exports[PH]:AdjustBalance(r.user_id, 'premiumpoints', Config.CreateCost)
        local ts = E.srcOf(r.user_id)
        if ts then E.chat(ts, ('Your clan request "%s" was rejected. %d Premium Points refunded.'):format(r.c_name, Config.CreateCost), '#e0c07a') end
        exports[PH]:StaffMsg('clan', ('%s rejected clan request #%d (user %d refunded %d PP).')
            :format(E.rpName(src), reqId, r.user_id, Config.CreateCost))
        return
    end

    -- accept
    local id, err = E.createClanFromRequest(r, src)
    if not id then return E.notify(src, err or 'Could not create the clan.', 'error') end
    MySQL.update.await("UPDATE clan_requests SET status = 'accepted', decided_by = ? WHERE id = ?", { E.uidOf(src), reqId })
    local ts = E.srcOf(r.user_id)
    if ts then E.chat(ts, ('Your clan "%s" [%s] was approved! You are the Leader.'):format(r.c_name, r.c_tag), '#8ce07a') end
    exports[PH]:StaffMsg('clan', ('%s approved clan #%d "%s" [%s] for user %d.')
        :format(E.rpName(src), id, r.c_name, r.c_tag, r.user_id))
end, false)

-- ----------------------------------------------------------
--  /editclan <id> <field> <value>   (staff >= manager)
-- ----------------------------------------------------------
RegisterCommand('editclan', function(src, args)
    if not E.staffAtLeast(src, Config.EditGrade) then return permErr(src, Config.EditGrade) end
    local cid = tonumber(args[1])
    local field = tostring(args[2] or ''):lower()
    local value = table.concat(args, ' ', 3):gsub('^%s+', ''):gsub('%s+$', '')
    if not cid or field == '' then
        return syntax(src, '/editclan <id> <name|tag|days|money|pp|cp> <value>')
    end
    local c = CLANS[cid]
    if not c then return E.notify(src, ('No clan #%d.'):format(cid), 'error') end

    if field == 'name' then
        value = value:sub(1, 64)
        if #value < 3 then return E.notify(src, 'Name too short.', 'error') end
        if MySQL.scalar.await('SELECT id FROM clans WHERE c_name = ? AND id <> ?', { value, cid }) then
            return E.notify(src, 'That name is taken.', 'error')
        end
        MySQL.update.await('UPDATE clans SET c_name = ? WHERE id = ?', { value, cid })

    elseif field == 'tag' then
        value = value:sub(1, 5)
        MySQL.update.await('UPDATE clans SET c_tag = ? WHERE id = ?', { value, cid })

    elseif field == 'days' then
        local raw = tonumber(value)
        if not raw then return syntax(src, '/editclan <id> days <number>') end
        local n = math.max(0, math.floor(raw))
        MySQL.update.await('UPDATE clans SET expires_at = DATE_ADD(NOW(), INTERVAL ? DAY), active = ? WHERE id = ?',
            { n, n > 0 and 1 or 0, cid })

    elseif field == 'money' or field == 'pp' or field == 'cp' then
        local raw = tonumber(value)
        if not raw then return syntax(src, ('/editclan <id> %s <number>'):format(field)) end
        local n = math.max(0, math.floor(raw))
        local col = field == 'money' and 'money' or (field == 'pp' and 'premiumpoints' or 'clan_points')
        MySQL.update.await(('UPDATE clans SET `%s` = ? WHERE id = ?'):format(col), { n, cid })

    else
        return syntax(src, '/editclan <id> <name|tag|days|money|pp|cp> <value>')
    end

    E.reloadClan(cid)
    E.clog(cid, E.uidOf(src), 'editclan', nil, ('%s = %s'):format(field, value))
    exports[PH]:StaffMsg('clan', ('%s set clan #%d %s = %s.'):format(E.rpName(src), cid, field, value ~= '' and value or '(cleared)'))
end, false)

-- ----------------------------------------------------------
--  Sugestii de comenzi
-- ----------------------------------------------------------
local function pushSuggestions(target)
    local function s(name, help, params) TriggerClientEvent('chat:addSuggestion', target, name, help, params) end
    s('/c', 'Clan chat', { { name = 'message' } })
    s('/togc', 'Hide / show clan chat')
    s('/quitclan', 'Leave your clan')
    s('/cinvite', 'Invite a nearby player to your clan', { { name = 'sqlId' } })
    s('/acceptcinvite', 'Accept a clan invite', { { name = 'inviter sqlId' } })
    s('/cdeposit', 'Deposit into the clan safebox', { { name = 'pp|money' }, { name = 'amount' } })
    s('/lockclanchat', 'Lock /c to a minimum rank (clan rank 6+)', { { name = 'rank' } })
    s('/unlockclanchat', 'Unlock /c for all members (clan rank 6+)')
    s('/cmotd', 'Set the clan message of the day (clan rank 6+)', { { name = 'message' } })
    s('/clantag', 'Choose your clan tag style (1-6)', { { name = '1-6' } })
    s('/clanreq', 'Review clan-creation requests (staff >= leadadmin)', { { name = 'list|accept|reject' }, { name = 'id' } })
    s('/editclan', 'Edit a clan (staff >= manager)', { { name = 'id' }, { name = 'field' }, { name = 'value' } })
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, p in ipairs(GetPlayers()) do pushSuggestions(tonumber(p)) end
end)

AddEventHandler('ph-core:playerLoaded', function(src) pushSuggestions(src) end)
