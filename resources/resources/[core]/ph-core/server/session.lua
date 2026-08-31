-- ==========================================================
--  ph-core / server / session
--
--  Sursa unica de adevar pentru maparea:
--      session id (server id FiveM, volatil)  <->  sql id (users.id, stabil)
--
--  Toate resursele trebuie sa lucreze pe `userId` (= users.id) si sa ceara
--  server id-ul doar la momentul in care chiar au nevoie de un native FiveM
--  (GetPlayerPed, TriggerClientEvent, DropPlayer, ...), prin exports:
--      exports['ph-core']:GetSource(userId)        -> src | nil (doar online)
--      exports['ph-core']:SourceToUserId(src)      -> userId | nil
--      exports['ph-core']:GetCharacterById(userId) -> character | nil
--      exports['ph-core']:GetPlayerById(userId)    -> player | nil
--      exports['ph-core']:GetOnlineUserIds()       -> { userId, ... }
--      exports['ph-core']:IsUserOnline(userId)     -> bool
--
--  Oglinda persistenta se tine in tabelul `user_session`.
-- ==========================================================
PH = PH or {}
PH.Players  = PH.Players or {}
PH.Session  = PH.Session or {}

local byId  = {}   -- [userId] = src
local bySrc = {}   -- [src]    = userId

-- ----------------------------------------------------------
--  Intern
-- ----------------------------------------------------------
local function dbUpsert(userId, src, license, username)
    license  = license or ''
    username = username or ''
    MySQL.query(
        'INSERT INTO user_session (user_id, session_id, license, username, online) VALUES (?, ?, ?, ?, 1) '
        .. 'ON DUPLICATE KEY UPDATE session_id = ?, license = ?, username = ?, online = 1',
        { userId, src, license, username, src, license, username }
    )
end

local function dbOffline(userId)
    MySQL.query('UPDATE user_session SET online = 0, session_id = 0 WHERE user_id = ?', { userId })
end

-- ----------------------------------------------------------
--  API intern (folosit de account.lua / character.lua / main.lua)
-- ----------------------------------------------------------
--- Leaga src <-> userId si scrie in user_session.
function PH.Session.Bind(src, userId, license, username)
    src, userId = tonumber(src), tonumber(userId)
    if not src or not userId then return end

    -- daca userId era legat de alta sesiune (dubla logare / restart de resursa), curata legatura veche
    local prevSrc = byId[userId]
    if prevSrc and prevSrc ~= src then bySrc[prevSrc] = nil end

    -- daca src-ul avea alt userId (nu ar trebui, dar fii defensiv)
    local prevId = bySrc[src]
    if prevId and prevId ~= userId then byId[prevId] = nil end

    byId[userId] = src
    bySrc[src]   = userId
    dbUpsert(userId, src, license, username)
end

--- Re-sincronizeaza din PH.Players[src] (dupa restart de resursa etc.).
function PH.Session.Sync(src)
    src = tonumber(src)
    local p = src and PH.Players[src]
    if not p or not p.userId then return end
    PH.Session.Bind(src, p.userId,
        (PH.GetLicense and PH.GetLicense(src)) or '',
        p.username or (p.character and p.character.username) or '')
end

--- Rupe legatura la deconectare.
function PH.Session.Unbind(src)
    src = tonumber(src)
    local userId = bySrc[src]
    bySrc[src] = nil
    if userId then
        if byId[userId] == src then byId[userId] = nil end
        dbOffline(userId)
    end
end

-- ----------------------------------------------------------
--  Rezolvare
-- ----------------------------------------------------------
function PH.Session.SourceOf(userId)
    return byId[tonumber(userId) or -1]
end

function PH.Session.IdOf(src)
    return bySrc[tonumber(src) or -1]
end

function PH.Session.OnlineIds()
    local t = {}
    for userId in pairs(byId) do t[#t + 1] = userId end
    return t
end

-- (curatarea sesiunilor ramase din crash se face in server/database.lua,
--  imediat dupa crearea tabelului `user_session`.)

-- ----------------------------------------------------------
--  Exports publice
-- ----------------------------------------------------------
exports('GetSource',        function(userId) return PH.Session.SourceOf(userId) end)
exports('GetServerId',      function(userId) return PH.Session.SourceOf(userId) end)  -- alias
exports('SourceToUserId',   function(src)    return PH.Session.IdOf(src) end)
exports('GetOnlineUserIds', function()       return PH.Session.OnlineIds() end)
exports('IsUserOnline',     function(userId) return PH.Session.SourceOf(userId) ~= nil end)

exports('GetPlayerById', function(userId)
    local src = PH.Session.SourceOf(userId)
    return src and PH.Players[src] or nil
end)

exports('GetCharacterById', function(userId)
    local src = PH.Session.SourceOf(userId)
    local p = src and PH.Players[src]
    return p and p.character or nil
end)
