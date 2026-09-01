PH = PH or {}
PH.Players = PH.Players or {}

local RES = GetCurrentResourceName()

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function getLicense(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then
            return id
        end
    end
    return nil
end
PH.GetLicense = getLicense

local function hashPassword(pw)
    return exports[RES]:hashPassword(pw)
end

local function verifyPassword(pw, stored)
    return exports[RES]:verifyPassword(pw, stored) == true
end

local function validateUsername(u)
    if type(u) ~= 'string' then return false end
    u = PH.Utils.Trim(u)
    if #u < Config.Username.minLength or #u > Config.Username.maxLength then
        return false
    end
    if not u:match(Config.Username.pattern) then
        return false
    end
    return true, u
end

local function validatePassword(p)
    if type(p) ~= 'string' then return false end
    if #p < Config.Password.minLength or #p > Config.Password.maxLength then
        return false
    end
    return true, p
end

local function validateEmail(e)
    if type(e) ~= 'string' then return false end
    e = PH.Utils.Trim(e):lower()
    if #e < 5 or #e > 120 then return false end
    -- ceva @ ceva . ceva  (fara spatii, fara al doilea @)
    if not e:match('^[^@%s]+@[^@%s]+%.[^@%s]+$') then return false end
    return true, e
end

local function authFail(src, message)
    TriggerClientEvent('ph-core:auth:result', src, { ok = false, message = message })
end

-- ----------------------------------------------------------
--  Cererea de stare initiala (login sau register?)
-- ----------------------------------------------------------
RegisterNetEvent('ph-core:auth:requestState', function()
    local src = source

    if not PH.DB.ready then
        authFail(src, 'The server is still starting up. Try again in a few seconds.')
        return
    end

    -- restart de resursa in timpul jocului: retrimite personajul deja incarcat
    if PH.Players[src] and PH.Players[src].character then
        PH.Session.Sync(src)
        TriggerClientEvent('ph-core:character:spawn', src, PH.Players[src].character)
        return
    end

    local license = getLicense(src)
    if not license then
        DropPlayer(src, 'Could not identify your FiveM/Rockstar license.')
        return
    end

    local user = MySQL.single.await(
        'SELECT id, username FROM users WHERE license = ?', { license }
    )

    if user then
        TriggerClientEvent('ph-core:auth:setScreen', src, 'login')
    else
        TriggerClientEvent('ph-core:auth:setScreen', src, 'register')
    end
end)

-- ----------------------------------------------------------
--  Register
-- ----------------------------------------------------------
RegisterNetEvent('ph-core:auth:register', function(data)
    local src = source
    if PH.Players[src] then return end        -- deja autentificat in aceasta sesiune
    if not PH.DB.ready then return authFail(src, 'The server is starting up.') end

    data = data or {}
    print(('^3[ph-core] register payload:^7 username=%q email=%q pass_len=%s'):format(
        tostring(data.username), tostring(data.email),
        type(data.password) == 'string' and #data.password or 'nil'))

    local okU, username = validateUsername(data.username)
    local okE, email    = validateEmail(data.email)
    local okP, password = validatePassword(data.password)

    if not okU then
        return authFail(src, 'Invalid username (3-24 characters: letters, digits, _).')
    end
    if not okE then
        return authFail(src, 'Invalid email address.')
    end
    if not okP then
        return authFail(src, 'Invalid password (minimum ' .. Config.Password.minLength .. ' characters).')
    end

    local license = getLicense(src)
    if not license then
        return DropPlayer(src, 'Invalid license.')
    end

    if MySQL.scalar.await('SELECT id FROM users WHERE license = ?', { license }) then
        return authFail(src, 'An account already exists on this license. Use the login instead.')
    end
    if MySQL.scalar.await('SELECT id FROM users WHERE username = ?', { username }) then
        return authFail(src, 'That username is already taken.')
    end
    if MySQL.scalar.await('SELECT id FROM users WHERE email = ?', { email }) then
        return authFail(src, 'An account with this email already exists.')
    end

    local id = MySQL.insert.await(
        'INSERT INTO users (username, email, password, license) VALUES (?, ?, ?, ?)',
        { username, email, hashPassword(password), license }
    )

    if not id then
        return authFail(src, 'Error creating the account. Try again.')
    end

    PH.Players[src] = { userId = id, username = username }
    PH.Session.Bind(src, id, license, username)
    PH.Log(('Cont creat: %s (id %d) [src %d]'):format(username, id, src))

    TriggerClientEvent('ph-core:auth:result', src, {
        ok = true, next = 'character_create', username = username,
        message = 'Account created successfully.',
    })
end)

-- ----------------------------------------------------------
--  Login
-- ----------------------------------------------------------
RegisterNetEvent('ph-core:auth:login', function(data)
    local src = source
    if PH.Players[src] and PH.Players[src].character then return end
    if not PH.DB.ready then return authFail(src, 'The server is starting up.') end

    data = data or {}
    local username = PH.Utils.Trim(tostring(data.username or ''))
    local password = tostring(data.password or '')

    if username == '' or password == '' then
        return authFail(src, 'Fill in all fields.')
    end

    local user = MySQL.single.await('SELECT * FROM users WHERE username = ?', { username })

    if not user or not verifyPassword(password, user.password) then
        return authFail(src, 'Wrong username or password.')
    end

    MySQL.update.await('UPDATE users SET last_login = NOW() WHERE id = ?', { user.id })
    PH.Players[src] = { userId = user.id, username = user.username }
    PH.Session.Bind(src, user.id, getLicense(src), user.username)
    PH.Log(('Autentificat: %s (id %d) [src %d]'):format(user.username, user.id, src))

    if user.dob == nil or user.dob == false or tostring(user.dob) == '' then
        -- cont fara personaj
        TriggerClientEvent('ph-core:auth:result', src, {
            ok = true, next = 'character_create', username = user.username,
            message = 'Authenticated. Create your character.',
        })
    else
        TriggerClientEvent('ph-core:auth:result', src, {
            ok = true, next = 'spawn', username = user.username,
            message = 'Welcome back!',
        })
        PH.Character.Load(src, user)
    end
end)

-- ----------------------------------------------------------
--  Deconectare
-- ----------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    local player = PH.Players[src]

    if player and player.character then
        PH.Character.Save(src)
    end
    PH.Session.Unbind(src)
    PH.Players[src] = nil
    if player then
        PH.Log(('Player disconnected [src %d] user %s'):format(src, player.userId or '?'))
    end
end)
