-- ==========================================================
--  ph_appearance / server
--    - creare: primeste aspectul de la creator, il scrie in users.appearance
--      (+ users.gender), apoi anunta ph-core sa continue spawn-ul.
--    - /editcharacter: "Save" -> aspect LIVE al tintei ; "Save Character" ->
--      preset in character_templates (user_id, gender).
--  Totul se cheiaza pe SQL id (users.id).
-- ==========================================================
local PH = 'ph-core'
local ready = false

-- ----------------------------------------------------------
--  DB
-- ----------------------------------------------------------
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    while GetResourceState(PH) ~= 'started' do Wait(200) end
    Wait(1500)   -- lasa ph-core sa creeze `users`

    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `character_templates` (
              `user_id`    INT UNSIGNED NOT NULL,
              `gender`     TINYINT      NOT NULL,
              `appearance` LONGTEXT     NOT NULL,
              `updated_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
              PRIMARY KEY (`user_id`, `gender`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])
    end)
    if not ok then
        print('^1[ph_appearance] DB init error:^7 ' .. tostring(err))
        return
    end
    ready = true
    print('^5[ph_appearance]^7 ready.')
end)

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function uidOf(src)
    local ok, u = pcall(function() return exports[PH]:GetUserId(src) end)
    return ok and u or nil
end

local function srcOfUser(uid)
    local ok, s = pcall(function() return exports[PH]:GetSource(uid) end)
    return ok and s or nil
end

local function isEditor(src)
    if src == 0 then return true end
    local ok, r = pcall(function() return exports[PH]:HasStaffRank(src, Config.EditCharacterGrade) end)
    return ok and r == true
end

local function userExists(uid)
    return MySQL.scalar.await('SELECT id FROM users WHERE id = ?', { uid }) ~= nil
end

local function loadAppearance(uid)
    local row = MySQL.single.await('SELECT appearance, gender, username FROM users WHERE id = ?', { uid })
    if not row then return nil end
    return {
        username   = row.username,
        gender     = tonumber(row.gender) or 0,
        appearance = Appearance.Decode(row.appearance),
    }
end

local function loadTemplate(uid, gender)
    local row = MySQL.single.await(
        'SELECT appearance FROM character_templates WHERE user_id = ? AND gender = ?',
        { uid, (tonumber(gender) == 1) and 1 or 0 })
    return row and Appearance.Decode(row.appearance) or nil
end

-- ----------------------------------------------------------
--  CREARE  (declansat de ph-core prin ph_appearance:cl:startCreator)
-- ----------------------------------------------------------
local pendingStarter = {}   -- [uid] = true  -> primeste Config.StarterClothing la playerLoaded

RegisterNetEvent('ph_appearance:sv:saveCreate', function(payload)
    local src = source
    local uid = uidOf(src)
    if not uid then return end

    payload = type(payload) == 'table' and payload or {}
    -- compat: se accepta si aspectul trimis direct (fara wrapper)
    local raw = type(payload.appearance) == 'table' and payload.appearance or payload
    local isReset = payload.reset == true

    local ap = Appearance.Clamp(raw)
    local enc = json.encode(ap)

    MySQL.update.await('UPDATE users SET appearance = ?, gender = ? WHERE id = ?', { enc, ap.gender, uid })
    print(('^5[ph_appearance]^7 character appearance %s: user %d (gender %d)'):format(
        isReset and 'reset' or 'created', uid, ap.gender))

    -- hainele de start doar la PRIMA creare, nu la /resetcharacter (deja are haine)
    if not isReset then pendingStarter[uid] = true end
    -- ph-core preia si continua spawn-ul
    TriggerEvent('ph_appearance:createDone', src, enc, ap.gender)
end)

--- dupa spawn: livreaza hainele de start in inventar (nu echipate), cu retry
--- pana se incarca inventarul jucatorului nou
AddEventHandler('ph-core:playerLoaded', function(src, char)
    local uid = char and char.id
    if not uid or not pendingStarter[uid] then return end
    pendingStarter[uid] = nil
    if GetResourceState('ph_inventory') ~= 'started' then return end
    if not Config.StarterClothing or #Config.StarterClothing == 0 then return end

    CreateThread(function()
        for _, item in ipairs(Config.StarterClothing) do
            local delivered = false
            for _ = 1, 20 do
                local ok = false
                pcall(function() ok = exports['ph_inventory']:GiveItem(uid, item, 1) end)
                if ok then delivered = true; break end
                Wait(500)
            end
            if not delivered then
                print(('^3[ph_appearance] starter clothing "%s" not delivered to user %d^7'):format(item, uid))
            end
        end
    end)
end)

-- ----------------------------------------------------------
--  /editcharacter  (server-side helpers ; comanda in appearance_cmd.lua)
-- ----------------------------------------------------------
--- deschide editorul pe ped-ul apelantului, cu datele tintei
function PHA_OpenEditor(src, targetUid)
    if not ready then
        exports[PH]:Notify(src, 'The appearance system is still initializing.', 'warning')
        return
    end
    if not isEditor(src) then
        exports[PH]:CmdPermError(src, Config.EditCharacterGrade)
        return
    end
    targetUid = tonumber(targetUid)
    if not targetUid then
        exports[PH]:CmdSyntax(src, '/editcharacter [sqlId]')
        return
    end
    local info = loadAppearance(targetUid)
    if not info then
        exports[PH]:Notify(src, ('No user with id %s.'):format(targetUid), 'error')
        return
    end

    TriggerClientEvent('ph_appearance:cl:startEditor', src, {
        targetId   = targetUid,
        targetName = info.username,
        gender     = info.gender,
        appearance = info.appearance,                       -- aspectul live curent (poate fi nil)
        template   = loadTemplate(targetUid, info.gender),  -- preset pt genul curent (poate fi nil)
    })
end

--- /resetcharacter [sqlId]  - baga jucatorul (online) fortat in creatorul de caracter,
--- ii dezechipeaza hainele in inventar (ce nu incape -> Post Office) si sterge aspectul.
function PHA_ResetCharacter(staffSrc, targetUid)
    if not ready then
        exports[PH]:Notify(staffSrc, 'The appearance system is still initializing.', 'warning')
        return
    end
    if not isEditor(staffSrc) then
        exports[PH]:CmdPermError(staffSrc, Config.EditCharacterGrade)
        return
    end
    targetUid = tonumber(targetUid)
    if not targetUid then
        exports[PH]:CmdSyntax(staffSrc, '/resetcharacter [sqlId]')
        return
    end
    local tsrc = srcOfUser(targetUid)
    if not tsrc then
        exports[PH]:Notify(staffSrc, ('User %s is not online.'):format(targetUid), 'error')
        return
    end
    local row = MySQL.single.await('SELECT username, gender FROM users WHERE id = ?', { targetUid })
    if not row then
        exports[PH]:Notify(staffSrc, ('No user with id %s.'):format(targetUid), 'error')
        return
    end

    local moved, mailed = 0, 0
    if GetResourceState('ph_inventory') == 'started' then
        pcall(function()
            local ok, m, ml = exports['ph_inventory']:UnequipAllToInventory(targetUid)
            if ok then moved, mailed = m or 0, ml or 0 end
        end)
    end

    MySQL.update.await('UPDATE users SET appearance = NULL WHERE id = ?', { targetUid })
    TriggerEvent('ph_appearance:resetPending', tsrc)   -- ph-core curata cache-ul de aspect

    TriggerClientEvent('ph_appearance:cl:startCreator', tsrc, { gender = tonumber(row.gender) or 0, reset = true })
    exports[PH]:Notify(tsrc, 'Your character was reset by staff. Recreate your look.', 'warning')
    exports[PH]:Notify(staffSrc, ('%s (#%d) sent to the character creator. Clothes: %d to inventory, %d to Post Office.')
        :format(row.username, targetUid, moved, mailed), 'success')
    print(('^5[ph_appearance]^7 /resetcharacter user %d by src %d (moved %d, mailed %d)'):format(
        targetUid, staffSrc, moved, mailed))
end

--- managerul a comutat M/F in editor -> trimite preset-ul (daca exista) pentru noul gen
RegisterNetEvent('ph_appearance:sv:editorGender', function(p)
    local src = source
    if not isEditor(src) then return end
    p = p or {}
    local targetUid = tonumber(p.targetId)
    local gender = (tonumber(p.gender) == 1) and 1 or 0
    if not targetUid or not userExists(targetUid) then return end

    local live = loadAppearance(targetUid)
    TriggerClientEvent('ph_appearance:cl:editorTemplate', src, {
        gender    = gender,
        template  = loadTemplate(targetUid, gender),
        -- daca genul cerut == genul live al tintei, oferim si aspectul live
        liveSame  = live and (live.gender == gender) and true or false,
        live      = (live and live.gender == gender) and live.appearance or nil,
    })
end)

--- "Save"  -> aspectul LIVE al tintei (users.appearance + users.gender)
RegisterNetEvent('ph_appearance:sv:editorSave', function(p)
    local src = source
    if not isEditor(src) then return end
    p = p or {}
    local targetUid = tonumber(p.targetId)
    if not targetUid or not userExists(targetUid) then
        return exports[PH]:Notify(src, 'Target no longer exists.', 'error')
    end

    local ap  = Appearance.Clamp(p.appearance)
    local enc = json.encode(ap)
    MySQL.update.await('UPDATE users SET appearance = ?, gender = ? WHERE id = ?', { enc, ap.gender, targetUid })

    local tsrc = srcOfUser(targetUid)
    if tsrc then
        TriggerClientEvent('ph_appearance:cl:applyLive', tsrc, ap)
        TriggerEvent('ph_appearance:liveUpdated', tsrc, enc, ap.gender)   -- ph-core sync cache
        exports[PH]:Notify(tsrc, 'Your character appearance was updated by staff.', 'info')
    end

    exports[PH]:Notify(src, ('Saved live appearance for %s (#%d).'):format(p.targetName or 'user', targetUid), 'success')
    print(('^5[ph_appearance]^7 /editcharacter SAVE: user %d gender %d (by src %d)'):format(targetUid, ap.gender, src))
end)

--- "Save Character"  -> preset in character_templates (user_id, gender)
RegisterNetEvent('ph_appearance:sv:editorTemplate', function(p)
    local src = source
    if not isEditor(src) then return end
    p = p or {}
    local targetUid = tonumber(p.targetId)
    if not targetUid or not userExists(targetUid) then
        return exports[PH]:Notify(src, 'Target no longer exists.', 'error')
    end

    local ap  = Appearance.Clamp(p.appearance)
    local enc = json.encode(ap)
    MySQL.query.await([[
        INSERT INTO character_templates (user_id, gender, appearance) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE appearance = VALUES(appearance)
    ]], { targetUid, ap.gender, enc })

    exports[PH]:Notify(src, ('Saved %s template for %s (#%d).'):format(
        ap.gender == 1 and 'female' or 'male', p.targetName or 'user', targetUid), 'success')
    print(('^5[ph_appearance]^7 /editcharacter SAVE CHARACTER: user %d gender %d template (by src %d)'):format(
        targetUid, ap.gender, src))
end)

-- ----------------------------------------------------------
--  Exports
-- ----------------------------------------------------------
exports('GetAppearance', function(uid)
    local info = loadAppearance(tonumber(uid) or 0)
    return info and info.appearance or nil
end)

exports('GetTemplate', function(uid, gender)
    return loadTemplate(tonumber(uid) or 0, gender)
end)
