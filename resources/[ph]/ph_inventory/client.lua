-- ==========================================================
--  ph_inventory / client
-- ==========================================================
local open = false
local equipment = {}            -- [eqSlot] = { name, meta }
local drops = {}                -- [id] = { obj, coords, preview }
local equipped = nil            -- { slot, hash, ammo, durability, dirty }
local lastAmmo = 0

local function isLoaded()
    local ok, r = pcall(function() return exports['ph-core']:IsLoaded() end)
    return ok and r
end

-- ----------------------------------------------------------
--  Deschidere / inchidere
-- ----------------------------------------------------------
local function openInv()
    if open or not isLoaded() then return end
    open = true
    SetNuiFocus(true, true)
    local c = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('ph_inventory:sv:request')
    TriggerServerEvent('ph_inventory:sv:nearby', { x = c.x, y = c.y, z = c.z })
    SendNUIMessage({ action = 'open' })
end

local function closeInv()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterCommand('+ph_inv', openInv, false)
RegisterCommand('-ph_inv', function() end, false)
RegisterKeyMapping('+ph_inv', 'Inventar', 'keyboard', Config.OpenKey)

RegisterNUICallback('close', function(_, cb) closeInv(); cb('ok') end)
RegisterNUICallback('move', function(d, cb) TriggerServerEvent('ph_inventory:sv:move', d.from, d.to, d.count); cb('ok') end)
RegisterNUICallback('loadAmmo', function(d, cb) TriggerServerEvent('ph_inventory:sv:loadAmmo', d.ammoSlot, d.weaponSlot); cb('ok') end)
RegisterNUICallback('context', function(d, cb) TriggerServerEvent('ph_inventory:sv:context', d.op, d.slot, d.count); cb('ok') end)
RegisterNUICallback('equip', function(d, cb) TriggerServerEvent('ph_inventory:sv:equip', d.slot); cb('ok') end)
RegisterNUICallback('unequip', function(d, cb) TriggerServerEvent('ph_inventory:sv:unequip', d.eqSlot); cb('ok') end)
RegisterNUICallback('setHotbar', function(d, cb) TriggerServerEvent('ph_inventory:sv:setHotbar', d.hotIndex, d.slot); cb('ok') end)
RegisterNUICallback('pickup', function(d, cb) TriggerServerEvent('ph_inventory:sv:pickup', d.id); cb('ok') end)

RegisterNetEvent('ph_inventory:cl:config', function(cfg)
    SendNUIMessage({ action = 'config', data = cfg })
end)

RegisterNetEvent('ph_inventory:cl:state', function(state)
    SendNUIMessage({ action = 'state', data = state })
end)

RegisterNetEvent('ph_inventory:cl:nearby', function(list)
    SendNUIMessage({ action = 'nearby', data = list })
end)

-- inchide cu ESC / Backspace
CreateThread(function()
    while true do
        if open then
            if IsControlJustReleased(0, 322) or IsControlJustReleased(0, 177) then
                closeInv()
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- ----------------------------------------------------------
--  Echipament pe ped
-- ----------------------------------------------------------
local function applyEquipment(map)
    equipment = map or {}
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    for eqSlot, cfg in pairs(Config.EquipmentSlots) do
        local worn = equipment[eqSlot]
        local def = worn and Config.Items[worn.name]

        if cfg.kind == 'component' then
            -- setam DOAR daca exista o haina si drawable-ul e valid pentru ped-ul curent
            if def and def.drawable then
                local maxDraw = GetNumberOfPedDrawableVariations(ped, cfg.id)
                local dr = math.floor(def.drawable)
                if dr >= 0 and dr < maxDraw then
                    local maxTex = GetNumberOfPedTextureVariations(ped, cfg.id, dr)
                    local tx = math.floor(def.texture or 0)
                    if tx < 0 or tx >= maxTex then tx = 0 end
                    SetPedComponentVariation(ped, cfg.id, dr, tx, 0)
                end
            end
            -- fara reset la 0 pe dezechipare (poate crapa jocul + arata prost fara sistem de appearance)
        else
            if def and def.drawable then
                local maxDraw = GetNumberOfPedPropDrawableVariations(ped, cfg.id)
                local dr = math.floor(def.drawable)
                if dr >= 0 and dr < maxDraw then
                    SetPedPropIndex(ped, cfg.id, dr, math.floor(def.texture or 0), true)
                else
                    ClearPedProp(ped, cfg.id)
                end
            else
                ClearPedProp(ped, cfg.id)
            end
        end
    end
end

RegisterNetEvent('ph_inventory:cl:applyEquipment', function(map)
    applyEquipment(map)
end)

-- reaplica dupa spawn / schimbare model
AddEventHandler('ph-core:client:playerLoaded', function()
    SetTimeout(1500, function() applyEquipment(equipment) end)
end)

-- ----------------------------------------------------------
--  Arme: echipare + durabilitate/gloante
-- ----------------------------------------------------------
local function holster()
    if not equipped then return end
    local ped = PlayerPedId()
    if equipped.dirty then
        TriggerServerEvent('ph_inventory:sv:weaponSync', equipped.slot, equipped.ammo, equipped.durability)
    end
    RemoveWeaponFromPed(ped, equipped.hash)
    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    equipped = nil
end

RegisterNetEvent('ph_inventory:cl:equipWeapon', function(w)
    local ped = PlayerPedId()
    local hash = GetHashKey(w.weaponName)

    -- toggle: acelasi fast slot -> baga arma la loc
    if equipped and equipped.slot == w.slot then
        holster()
        return
    end
    if equipped then holster() end

    equipped = {
        slot = w.slot, hash = hash,
        ammo = math.floor(w.ammo or 0),
        durability = w.durability or Config.Weapon.MaxDurability,
        dirty = false,
    }
    GiveWeaponToPed(ped, hash, 0, false, true)
    SetCurrentPedWeapon(ped, hash, true)
    SetPedAmmo(ped, hash, equipped.ammo)
    lastAmmo = equipped.ammo
end)

-- detectare focuri: scade gloante + durabilitate
CreateThread(function()
    while true do
        if equipped then
            local ped = PlayerPedId()
            -- daca a schimbat arma manual din roata, holster logic
            if GetSelectedPedWeapon(ped) ~= equipped.hash then
                -- lasa; sincronizeaza starea
                if equipped.dirty then
                    TriggerServerEvent('ph_inventory:sv:weaponSync', equipped.slot, equipped.ammo, equipped.durability)
                    equipped.dirty = false
                end
            else
                local cur = GetAmmoInPedWeapon(ped, equipped.hash)
                if cur < lastAmmo then
                    local fired = lastAmmo - cur
                    equipped.ammo = math.max(0, equipped.ammo - fired)
                    equipped.durability = math.max(0, equipped.durability - fired * Config.Weapon.DurabilityPerShot)
                    equipped.dirty = true
                end
                lastAmmo = cur
                if equipped.durability <= 0 then
                    -- arma stricata: blocheaza tragerea
                    DisablePlayerFiring(PlayerId(), true)
                end
            end
            Wait(0)
        else
            Wait(300)
        end
    end
end)

-- sync periodic
CreateThread(function()
    while true do
        Wait(4000)
        if equipped and equipped.dirty then
            TriggerServerEvent('ph_inventory:sv:weaponSync', equipped.slot, equipped.ammo, equipped.durability)
            equipped.dirty = false
        end
    end
end)

-- Fast slots: tastele 1..5 = controalele 157..161.
-- Dezactivam selectarea de arme nativa (roata + 1..9) si citim direct tastele.
local HOTBAR_CONTROLS = { 157, 158, 159, 160, 161 }

CreateThread(function()
    while true do
        if isLoaded() then
            DisableControlAction(0, 37, true)                       -- weapon wheel
            for c = 157, 165 do DisableControlAction(0, c, true) end -- 1..9 weapon select

            if not open and not IsPauseMenuActive() then
                for i = 1, Config.HotbarSlots do
                    if IsDisabledControlJustPressed(0, HOTBAR_CONTROLS[i] or -1) then
                        TriggerServerEvent('ph_inventory:sv:useHotbar', i)
                    end
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

AddEventHandler('ph-core:client:playerLoaded', function() equipped = nil end)

-- ----------------------------------------------------------
--  Efecte "use"
-- ----------------------------------------------------------
RegisterNetEvent('ph_inventory:cl:useEffect', function(effect, value, itemName)
    local ped = PlayerPedId()
    if effect == 'heal' then
        SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), GetEntityHealth(ped) + (value or 20)))
    elseif effect == 'hunger' or effect == 'thirst' then
        TriggerEvent('ph_needs:client:add', effect, value or 20) -- hook pentru viitorul sistem de nevoi
    elseif effect == 'phone' then
        TriggerEvent('ph_phone:toggle')
    elseif effect == 'radio' then
        TriggerEvent('ph_radio:toggle')
    end
end)

-- ----------------------------------------------------------
--  Drop-uri pe jos
-- ----------------------------------------------------------
RegisterNetEvent('ph_inventory:cl:dropAdd', function(id, coords, preview)
    if drops[id] and DoesEntityExist(drops[id].obj) then
        drops[id].preview = preview
        return
    end
    local model = GetHashKey(Config.Drop.Prop)
    RequestModel(model)
    local t = 0
    while not HasModelLoaded(model) and t < 100 do Wait(10); t = t + 1 end
    local obj = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(model)
    drops[id] = { obj = obj, coords = coords, preview = preview }
end)

RegisterNetEvent('ph_inventory:cl:dropRemove', function(id)
    local d = drops[id]
    if d and DoesEntityExist(d.obj) then DeleteEntity(d.obj) end
    drops[id] = nil
end)

-- marker + ridicare cu E
CreateThread(function()
    while true do
        local wait = 700
        if isLoaded() then
            local pc = GetEntityCoords(PlayerPedId())
            local near
            for id, d in pairs(drops) do
                local dist = #(pc - vector3(d.coords.x, d.coords.y, d.coords.z))
                if dist < 8.0 then
                    wait = 0
                    DrawMarker(2, d.coords.x, d.coords.y, d.coords.z + 0.6, 0, 0, 0, 0, 0, 0,
                        0.22, 0.22, 0.22, 155, 120, 255, 180, false, true, 2, false, nil, nil, false)
                    if dist < Config.Drop.PickupDistance then near = id end
                end
            end
            if near then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('Apasa ~INPUT_CONTEXT~ pentru a ridica itemele')
                EndTextCommandDisplayHelp(0, false, true, -1)
                if IsControlJustReleased(0, 51) then
                    TriggerServerEvent('ph_inventory:sv:pickup', near)
                end
            end
        end
        Wait(wait)
    end
end)

-- panoul NEARBY se reimprospateaza cat timp meniul e deschis
CreateThread(function()
    while true do
        Wait(2000)
        if open then
            local c = GetEntityCoords(PlayerPedId())
            TriggerServerEvent('ph_inventory:sv:nearby', { x = c.x, y = c.y, z = c.z })
        end
    end
end)
