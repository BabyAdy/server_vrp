PH = PH or {}
PH.Players = PH.Players or {}
PH.Character = PH.Character or {}

-- ----------------------------------------------------------
--  Validari
-- ----------------------------------------------------------
local function validDob(s)
    if type(s) ~= 'string' then return false end
    local y, m, d = s:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    if not y then return false end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if m < 1 or m > 12 or d < 1 or d > 31 then return false end

    local normalized = ('%04d-%02d-%02d'):format(y, m, d)
    local age = PH.Utils.AgeFromDob(normalized)
    if not age or age < Config.Character.minAge or age > Config.Character.maxAge then
        return false
    end
    return true, normalized
end

local function charFail(src, message)
    TriggerClientEvent('ph-core:character:result', src, { ok = false, message = message })
end

-- ----------------------------------------------------------
--  Incarcare / salvare (totul pe randul din `users`)
-- ----------------------------------------------------------
function PH.Character.Load(src, row)
    local player = PH.Players[src]
    if not player then return end

    player.loginTime = os.time()
    player.character = {
        id            = row.id,
        username      = row.username,
        dob           = tostring(row.dob),
        gender        = tonumber(row.gender) or 0,
        height        = tonumber(row.height) or 180,
        level         = tonumber(row.level) or 1,
        rp            = tonumber(row.rp) or 0,
        money         = tonumber(row.money) or 0,
        bank          = tonumber(row.bank) or 0,
        premiumpoints = tonumber(row.premiumpoints) or 0,
        playtime      = tonumber(row.playtime) or 0,
        appearance    = row.appearance,
        staff         = row.staff or '',
        badges        = {},
        spawn         = Config.NewCharacterSpawn,
    }

    MySQL.update.await('UPDATE users SET last_login = NOW() WHERE id = ?', { row.id })
    PH.Session.Bind(src, row.id, (PH.GetLicense and PH.GetLicense(src)) or '', row.username)
    PH.Log(('Character loaded: %s (id %d) [src %d]'):format(row.username, row.id, src))

    TriggerClientEvent('ph-core:character:spawn', src, player.character)
end

function PH.Character.Save(src)
    local player = PH.Players[src]
    if not player or not player.character then return end

    local c = player.character

    -- acumuleaza timpul jucat
    local now = os.time()
    local delta = now - (player.loginTime or now)
    if delta < 0 then delta = 0 end
    c.playtime = (c.playtime or 0) + delta
    player.loginTime = now

    MySQL.update.await([[
        UPDATE users
        SET level = ?, rp = ?, money = ?, bank = ?, premiumpoints = ?,
            playtime = ?, appearance = ?, last_login = NOW()
        WHERE id = ?
    ]], {
        c.level, c.rp, c.money, c.bank, c.premiumpoints,
        c.playtime, c.appearance, c.id,
    })
    PH.Log(('Personaj salvat: id %d [src %d]'):format(c.id, src))
end

-- ----------------------------------------------------------
--  Creare personaj (completeaza randul existent din `users`)
-- ----------------------------------------------------------
RegisterNetEvent('ph-core:character:create', function(data)
    local src = source
    local player = PH.Players[src]

    if not player then
        return charFail(src, 'You are not authenticated.')
    end
    if player.character then return end   -- are deja personaj incarcat

    data = data or {}
    local okD, dob = validDob(data.dob)
    local gender = tonumber(data.gender)
    local height = tonumber(data.height)

    if not okD then
        return charFail(src, ('Invalid date of birth, or age outside the %d-%d range.')
            :format(Config.Character.minAge, Config.Character.maxAge))
    end
    if gender ~= 0 and gender ~= 1 then
        return charFail(src, 'Invalid gender.')
    end
    if not height or height < Config.Character.minHeight or height > Config.Character.maxHeight then
        return charFail(src, ('Invalid height (%d-%d cm).')
            :format(Config.Character.minHeight, Config.Character.maxHeight))
    end

    -- scrie doar daca personajul nu a fost deja creat (dob IS NULL)
    MySQL.update.await([[
        UPDATE users SET dob = ?, gender = ?, height = ?
        WHERE id = ? AND dob IS NULL
    ]], { dob, gender, math.floor(height + 0.5), player.userId })

    local row = MySQL.single.await('SELECT * FROM users WHERE id = ?', { player.userId })
    if not row then
        return charFail(src, 'Error saving the character.')
    end

    PH.Log(('Character created: %s (id %d) [src %d]'):format(row.username, row.id, src))
    TriggerClientEvent('ph-core:character:result', src, { ok = true, message = 'Character created!' })
    PH.Character.Load(src, row)
end)

-- ----------------------------------------------------------
--  Client raporteaza ca a terminat spawn-ul
-- ----------------------------------------------------------
RegisterNetEvent('ph-core:character:spawned', function()
    local src = source
    local player = PH.Players[src]
    if not player or not player.character then return end

    PH.Log(('Player fully in game [src %d] user %d'):format(src, player.character.id))
    -- hook pentru alte resurse (leveling, inventar, etc.)
    TriggerEvent('ph-core:playerLoaded', src, player.character)
end)

-- ----------------------------------------------------------
--  Salvare automata periodica
-- ----------------------------------------------------------
CreateThread(function()
    while true do
        Wait(Config.AutoSaveInterval)
        local n = 0
        for src, player in pairs(PH.Players) do
            if player.character then
                PH.Character.Save(src)
                n = n + 1
            end
        end
        if n > 0 then PH.Log(('Auto-save: %d personaj(e).'):format(n)) end
    end
end)
