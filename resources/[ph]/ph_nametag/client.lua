-- ==========================================================
--  ph_nametag - nametag 3D pentru toti jucatorii
--  Roster-ul (id sql, username, grad staff, badge-uri) vine
--  de la ph-core prin evenimentele ph-core:public:*
-- ==========================================================

local roster = {}   -- [serverId] = { id, name, staff, staffLabel, staffColor, badges }

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function hexToRgb(hex, dr, dg, db)
    if type(hex) ~= 'string' then return dr or 255, dg or 255, db or 255 end
    hex = hex:gsub('#', '')
    if #hex < 6 then return dr or 255, dg or 255, db or 255 end
    return tonumber(hex:sub(1, 2), 16) or 255,
           tonumber(hex:sub(3, 4), 16) or 255,
           tonumber(hex:sub(5, 6), 16) or 255
end

local function line3d(text, yoff, scale, r, g, b, a)
    SetTextScale(0.0, scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(r, g, b, a)
    SetTextEdge(1, 0, 0, 0, 205)
    SetTextOutline()
    SetTextDropShadow()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentSubstringPlayerName(text)
    DrawText(0.0, yoff)
end

-- ----------------------------------------------------------
--  Sincronizare roster (de la ph-core)
-- ----------------------------------------------------------
RegisterNetEvent('ph-core:public:sync', function(all)
    local t = {}
    for src, e in pairs(all or {}) do t[tonumber(src)] = e end
    roster = t
end)

RegisterNetEvent('ph-core:public:set', function(src, e)
    roster[tonumber(src)] = e
end)

RegisterNetEvent('ph-core:public:remove', function(src)
    roster[tonumber(src)] = nil
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == GetCurrentResourceName() then
        TriggerServerEvent('ph-core:public:request')
    end
end)

AddEventHandler('ph-core:client:playerLoaded', function()
    TriggerServerEvent('ph-core:public:request')
end)

-- ----------------------------------------------------------
--  Desenare
-- ----------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 500
        local loaded = false
        local ok, res = pcall(function() return exports['ph-core']:IsLoaded() end)
        if ok then loaded = res end

        if loaded then
            sleep = 0
            local myPid = PlayerId()
            local myPed = PlayerPedId()
            local myCoords = GetEntityCoords(myPed)

            for _, ply in ipairs(GetActivePlayers()) do
                local sid = GetPlayerServerId(ply)
                local e = roster[sid]
                if e then
                    local ped = GetPlayerPed(ply)
                    local isSelf = (ply == myPid)
                    local show = ((not isSelf) or Config.ShowSelf)
                        and DoesEntityExist(ped)
                        and IsEntityVisible(ped)
                        and not (Config.HideWhenDead and IsEntityDead(ped))

                    if show and isSelf and Config.HideInVehicleFPV
                       and IsPedInAnyVehicle(ped, false)
                       and GetFollowPedCamViewMode() == 4 then
                        show = false
                    end

                    if show then
                        local pc = GetEntityCoords(ped)
                        local dist = #(pc - myCoords)

                        if dist <= Config.MaxDistance then
                            local head = GetPedBoneCoords(ped, 0x796E, 0.0, 0.0, 0.0)

                            local a = 255
                            if dist > Config.FadeStart then
                                local t = (dist - Config.FadeStart) / (Config.MaxDistance - Config.FadeStart)
                                a = math.floor(255 - t * (255 - Config.MinAlpha))
                            end

                            local scale = 0.34
                            local step = 0.028
                            local y = 0.0

                            SetDrawOrigin(head.x, head.y, head.z + Config.HeadOffset, 0)

                            -- linia 1: (id)Username
                            local nc = Config.Colors.name
                            line3d(('~p~(%s)~w~%s'):format(e.id or '?', e.name or '???'),
                                y, scale, nc[1], nc[2], nc[3], a)

                            -- linia 2 (deasupra): grad staff, in culoarea sa
                            if e.staffLabel then
                                y = y - step
                                local r, g, b = hexToRgb(e.staffColor, 255, 255, 255)
                                line3d(e.staffLabel:upper(), y, scale * 0.92, r, g, b, a)
                            end

                            -- linia 3 (deasupra gradului): badge-uri subscriptii (viitor)
                            if e.badges and #e.badges > 0 then
                                local parts = {}
                                for _, bd in ipairs(e.badges) do
                                    parts[#parts + 1] = (type(bd) == 'table' and (bd.text or bd.label))
                                        or tostring(bd)
                                end
                                y = y - step
                                local bc = Config.Colors.badge
                                line3d(table.concat(parts, '  '), y, scale * 0.86, bc[1], bc[2], bc[3], a)
                            end

                            ClearDrawOrigin()
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)
