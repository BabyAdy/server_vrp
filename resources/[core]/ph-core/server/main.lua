PH = PH or {}
PH.Players = PH.Players or {}

local RES = GetCurrentResourceName()

-- ----------------------------------------------------------
--  Conectare: verificare de baza inainte de intrarea in sesiune
-- ----------------------------------------------------------
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    deferrals.update('Purple Havoc - se verifica accesul...')

    -- asteapta pana la 10s ca baza de date sa fie gata
    local waited = 0
    while not PH.DB.ready and waited < 10000 do
        Wait(250)
        waited = waited + 250
    end

    if not PH.DB.ready then
        deferrals.done('Serverul nu este inca pregatit (baza de date). Incearca peste putin timp.')
        return
    end

    local hasLicense = false
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then
            hasLicense = true
            break
        end
    end

    if not hasLicense then
        deferrals.done('Nu ai o licenta FiveM/Rockstar valida. Porneste jocul prin launcher-ul oficial.')
        return
    end

    deferrals.done()
end)

-- ----------------------------------------------------------
--  Exports pentru alte resurse
-- ----------------------------------------------------------
exports('GetPlayer', function(src)
    return PH.Players[src]
end)

exports('GetCharacter', function(src)
    local p = PH.Players[src]
    return p and p.character or nil
end)

exports('GetUserId', function(src)
    local p = PH.Players[src]
    return p and p.userId or nil
end)

exports('IsPlayerLoaded', function(src)
    local p = PH.Players[src]
    return (p and p.character) ~= nil
end)

-- ----------------------------------------------------------
--  Comenzi utilitare (dev/admin)
-- ----------------------------------------------------------
RegisterCommand('phresetchar', function(src)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'ph.admin') then
        return
    end

    local player = PH.Players[src]
    if not player then
        if src == 0 then print('[ph-core] Foloseste comanda in joc.') end
        return
    end

    MySQL.update.await([[
        UPDATE users
        SET dob = NULL, appearance = NULL, gender = 0, height = 180,
            level = 1, rp = 0, money = 500, bank = 0, playtime = 0
        WHERE id = ?
    ]], { player.userId })
    player.character = nil
    PH.Log(('Personaj resetat manual pentru user %d [src %d]'):format(player.userId, src))
    DropPlayer(src, 'Personajul tau a fost resetat. Reconecteaza-te pentru a crea unul nou.')
end, false)

-- ----------------------------------------------------------
--  La oprirea resursei salveaza tot
-- ----------------------------------------------------------
AddEventHandler('onResourceStop', function(resource)
    if resource ~= RES then return end
    for src, player in pairs(PH.Players) do
        if player.character then
            PH.Character.Save(src)
        end
    end
end)

CreateThread(function()
    Wait(1000)
    print('^5[ph-core]^7 Purple Havoc core incarcat. Astept jucatori...')
end)
