-- ==========================================================
--  ph_inventory / server
-- ==========================================================
local PH = 'ph-core'
local ready = false
math.randomseed(os.time())

local INV = {}          -- [src] = { slots, items = { [slot] = {name,count,meta} }, equipment = {}, hotbar = {} }
local DROPS = {}         -- [dropId] = { id, coords = {x,y,z}, items = { {name,count,meta}, ... }, expires = gametimer }
local dropSeq = 0

-- ----------------------------------------------------------
--  DB init / migratie
-- ----------------------------------------------------------
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(250) end
    while GetResourceState(PH) ~= 'started' do Wait(250) end
    Wait(2500)

    local ok, err = pcall(function()
        local hasInv = MySQL.scalar.await([[
            SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'inventory'
        ]])
        if (tonumber(hasInv) or 0) == 0 then
            MySQL.query.await("ALTER TABLE `users` ADD COLUMN `inventory` LONGTEXT NULL DEFAULT NULL")
            MySQL.query.await("ALTER TABLE `users` ADD COLUMN `inv_slots` SMALLINT NOT NULL DEFAULT " .. Config.DefaultSlots)
            print('^5[ph_inventory]^7 Migratie: adaugate coloanele `users.inventory` / `users.inv_slots`.')
        end
    end)
    if not ok then
        print('^1[ph_inventory] eroare init DB:^7 ' .. tostring(err))
        return
    end
    ready = true
    print('^5[ph_inventory]^7 pregatit.')
end)

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function itemDef(name) return Config.Items[name] end

local function charOf(src) return exports[PH]:GetCharacter(src) end

local function notify(src, text, color)
    if GetResourceState('ph_chat') == 'started' then
        exports['ph_chat']:send(src, { text = text, textColor = color or '#e8e6f0' })
    else
        TriggerClientEvent('chat:addMessage', src, { args = { text } })
    end
end

local function newMeta(name)
    local d = itemDef(name)
    if d and d.type == 'weapon' then
        return { ammo = 0, durability = Config.Weapon.MaxDurability,
                 serial = ('%05d'):format(math.random(0, 99999)) }
    end
    return nil
end

local function weightOf(inv)
    local w = 0.0
    for _, e in pairs(inv.items) do
        local d = itemDef(e.name)
        w = w + (d and d.weight or 0) * (e.count or 1)
    end
    return w
end

local function firstFreeSlot(inv)
    for i = 1, inv.slots do
        if not inv.items[i] then return i end
    end
    return nil
end

--- true daca incape `count` din `name` (greutate + slot)
local function canCarry(inv, name, count)
    local d = itemDef(name)
    if not d then return false end
    if weightOf(inv) + d.weight * count > Config.MaxWeight then return false end
    -- incape intr-un stack existent?
    for _, e in pairs(inv.items) do
        if e.name == name and (e.count + count) <= (d.stack or 1) and not e.meta then
            return true
        end
    end
    return firstFreeSlot(inv) ~= nil
end

-- ----------------------------------------------------------
--  Persistenta
-- ----------------------------------------------------------
local function serialize(inv)
    return json.encode({ items = inv.items, equipment = inv.equipment, hotbar = inv.hotbar })
end

local dirty = {}   -- [src] = true  (scriere debounce)

local function writeInv(src)
    local inv = INV[src]
    local char = charOf(src)
    if not inv or not char then return end
    dirty[src] = nil
    MySQL.update('UPDATE users SET inventory = ? WHERE id = ?', { serialize(inv), char.id })
end

--- marcheaza pentru scriere; flush-ul e la fiecare 15s (vezi thread-ul de mai jos)
local function saveInv(src)
    dirty[src] = true
end

local function loadInv(src)
    local char = charOf(src)
    if not char then return end

    local row = MySQL.single.await('SELECT inventory, inv_slots FROM users WHERE id = ?', { char.id })
    local slots = (row and tonumber(row.inv_slots)) or Config.DefaultSlots
    local data = { items = {}, equipment = {}, hotbar = {} }

    if row and row.inventory and row.inventory ~= '' then
        local ok, dec = pcall(json.decode, row.inventory)
        if ok and type(dec) == 'table' then
            data.items = dec.items or {}
            data.equipment = dec.equipment or {}
            data.hotbar = dec.hotbar or {}
        end
    end

    -- json.decode transforma cheile numerice in string; normalizam
    local items = {}
    for k, v in pairs(data.items) do items[tonumber(k)] = v end
    local hotbar = {}
    for k, v in pairs(data.hotbar) do hotbar[tonumber(k)] = tonumber(v) end

    INV[src] = { slots = slots, items = items, equipment = data.equipment, hotbar = hotbar }
end

-- ----------------------------------------------------------
--  Operatii pe inventar
-- ----------------------------------------------------------
-- config-ul static se trimite o singura data (la deschidere)
local function pushConfig(src)
    local inv = INV[src]
    TriggerClientEvent('ph_inventory:cl:config', src, {
        slots = inv and inv.slots or Config.DefaultSlots,
        maxWeight = Config.MaxWeight,
        defs = Config.Items,
        equipmentSlots = Config.EquipmentSlots,
        equipmentOrder = Config.EquipmentOrder,
        hotbarSlots = Config.HotbarSlots,
        weapon = Config.Weapon,
    })
end

-- datele dinamice - trimise des, cat mai mici
local function pushState(src)
    local inv = INV[src]
    if not inv then return end
    TriggerClientEvent('ph_inventory:cl:state', src, {
        slots = inv.slots,
        weight = weightOf(inv),
        items = inv.items,
        equipment = inv.equipment,
        hotbar = inv.hotbar,
    })
end

local function addItem(src, name, count, meta)
    local inv = INV[src]
    local d = itemDef(name)
    if not inv or not d or count <= 0 then return false end
    if weightOf(inv) + d.weight * count > Config.MaxWeight then return false end

    if meta or (d.stack or 1) <= 1 then
        -- item cu meta sau nestackabil -> slot separat per bucata
        for _ = 1, count do
            local s = firstFreeSlot(inv)
            if not s then return false end
            inv.items[s] = { name = name, count = 1, meta = meta or newMeta(name) }
        end
        return true
    end

    -- stackabil
    for _, e in pairs(inv.items) do
        if e.name == name and not e.meta and e.count < d.stack then
            local room = d.stack - e.count
            local take = math.min(room, count)
            e.count = e.count + take
            count = count - take
            if count <= 0 then return true end
        end
    end
    while count > 0 do
        local s = firstFreeSlot(inv)
        if not s then return false end
        local take = math.min(d.stack, count)
        inv.items[s] = { name = name, count = take }
        count = count - take
    end
    return true
end

local function countItem(src, name)
    local inv = INV[src]
    if not inv then return 0 end
    local n = 0
    for _, e in pairs(inv.items) do if e.name == name then n = n + e.count end end
    return n
end

local function removeItem(src, name, count)
    local inv = INV[src]
    if not inv then return false end
    if countItem(src, name) < count then return false end
    for s, e in pairs(inv.items) do
        if e.name == name then
            local take = math.min(e.count, count)
            e.count = e.count - take
            count = count - take
            if e.count <= 0 then inv.items[s] = nil end
            if count <= 0 then return true end
        end
    end
    return count <= 0
end

-- ----------------------------------------------------------
--  Drop-uri
-- ----------------------------------------------------------
local function dropPreview(items)
    local out = {}
    for _, e in ipairs(items) do
        local d = itemDef(e.name)
        out[#out + 1] = { name = e.name, label = d and d.label or e.name, count = e.count }
    end
    return out
end

local function createDrop(coords, items)
    dropSeq = dropSeq + 1
    local id = dropSeq
    DROPS[id] = { id = id, coords = coords, items = items, expires = GetGameTimer() + Config.Drop.ExpireMs }
    TriggerClientEvent('ph_inventory:cl:dropAdd', -1, id, coords, dropPreview(items))
    return id
end

local function removeDrop(id)
    if not DROPS[id] then return end
    DROPS[id] = nil
    TriggerClientEvent('ph_inventory:cl:dropRemove', -1, id)
end

-- expirare
CreateThread(function()
    while true do
        Wait(30000)
        local now = GetGameTimer()
        for id, d in pairs(DROPS) do
            if now >= d.expires then removeDrop(id) end
        end
    end
end)

-- ----------------------------------------------------------
--  ph-core hooks
-- ----------------------------------------------------------
AddEventHandler('ph-core:playerLoaded', function(src)
    if not ready then
        SetTimeout(3000, function() if INV[src] == nil then loadInv(src) end end)
    else
        loadInv(src)
    end
    SetTimeout(1500, function()
        if INV[src] then
            pushState(src)
            TriggerClientEvent('ph_inventory:cl:applyEquipment', src, INV[src].equipment)
        end
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    if INV[src] then writeInv(src) end
    INV[src] = nil
    dirty[src] = nil
end)

-- flush periodic al inventarelor modificate
CreateThread(function()
    while true do
        Wait(15000)
        for src in pairs(dirty) do
            if INV[src] then writeInv(src) end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(INV) do writeInv(src) end
end)

-- ----------------------------------------------------------
--  NUI / client -> server
-- ----------------------------------------------------------
RegisterNetEvent('ph_inventory:sv:request', function()
    local src = source
    if not INV[src] then loadInv(src) end
    pushConfig(src)
    pushState(src)
end)

RegisterNetEvent('ph_inventory:sv:nearby', function(coords)
    local src = source
    if type(coords) ~= 'table' then return end
    local list = {}
    for id, d in pairs(DROPS) do
        local dx, dy, dz = d.coords.x - coords.x, d.coords.y - coords.y, d.coords.z - coords.z
        if (dx * dx + dy * dy + dz * dz) <= (Config.Drop.NearbyDistance ^ 2) then
            list[#list + 1] = { id = id, items = dropPreview(d.items) }
        end
    end
    TriggerClientEvent('ph_inventory:cl:nearby', src, list)
end)

--- muta / merge / split in grid
RegisterNetEvent('ph_inventory:sv:move', function(from, to, count)
    local src = source
    local inv = INV[src]
    if not inv then return end
    from, to = tonumber(from), tonumber(to)
    if not from or not to or from == to or to < 1 or to > inv.slots then return end

    local a = inv.items[from]
    if not a then return end
    count = tonumber(count) or a.count
    count = math.max(1, math.min(count, a.count))

    local b = inv.items[to]
    local d = itemDef(a.name)

    if not b then
        if count >= a.count or a.meta then
            inv.items[to], inv.items[from] = a, nil
        else
            inv.items[to] = { name = a.name, count = count }
            a.count = a.count - count
        end
    elseif b.name == a.name and not a.meta and not b.meta and d and (b.count + count) <= (d.stack or 1) then
        b.count = b.count + count
        a.count = a.count - count
        if a.count <= 0 then inv.items[from] = nil end
    else
        -- swap
        inv.items[from], inv.items[to] = b, a
    end

    saveInv(src)
    pushState(src)
end)

--- incarca gloante peste arma (drag ammo -> weapon)
RegisterNetEvent('ph_inventory:sv:loadAmmo', function(ammoSlot, weaponSlot)
    local src = source
    local inv = INV[src]
    if not inv then return end
    ammoSlot, weaponSlot = tonumber(ammoSlot), tonumber(weaponSlot)

    local ammo = inv.items[ammoSlot]
    local wpn = inv.items[weaponSlot]
    if not ammo or not wpn then return end

    local wd, ad = itemDef(wpn.name), itemDef(ammo.name)
    if not wd or wd.type ~= 'weapon' or not wd.ammoType then return end
    if not ad or ad.type ~= 'ammo' or wd.ammoType ~= ammo.name then
        return notify(src, 'Munitie incompatibila cu arma.', '#e07a7a')
    end

    wpn.meta = wpn.meta or newMeta(wpn.name)
    local room = Config.Weapon.MaxLoadedAmmo - (wpn.meta.ammo or 0)
    if room <= 0 then return notify(src, 'Arma este deja plina (max ' .. Config.Weapon.MaxLoadedAmmo .. ').', '#e0c07a') end

    local take = math.min(room, ammo.count)
    wpn.meta.ammo = (wpn.meta.ammo or 0) + take
    ammo.count = ammo.count - take
    if ammo.count <= 0 then inv.items[ammoSlot] = nil end

    notify(src, ('Incarcat %d gloante. Total: %d/%d'):format(take, wpn.meta.ammo, Config.Weapon.MaxLoadedAmmo), '#8ce07a')
    saveInv(src)
    pushState(src)
end)

--- use / split / drop din context menu
RegisterNetEvent('ph_inventory:sv:context', function(op, slot, count)
    local src = source
    local inv = INV[src]
    if not inv then return end
    slot = tonumber(slot)
    local e = inv.items[slot]
    if not e then return end
    local d = itemDef(e.name)

    if op == 'use' then
        if not d or not d.usable then return end
        e.count = e.count - 1
        if e.count <= 0 then inv.items[slot] = nil end
        TriggerClientEvent('ph_inventory:cl:useEffect', src, d.effect, d.value, e.name)
        saveInv(src); pushState(src)

    elseif op == 'split' then
        count = math.floor(tonumber(count) or 0)
        if count < 1 or count >= e.count or e.meta then return end
        local free = firstFreeSlot(inv)
        if not free then return notify(src, 'Nu ai slot liber.', '#e07a7a') end
        inv.items[free] = { name = e.name, count = count }
        e.count = e.count - count
        saveInv(src); pushState(src)

    elseif op == 'drop' then
        count = math.floor(tonumber(count) or e.count)
        count = math.max(1, math.min(count, e.count))
        local ped = GetPlayerPed(src)
        local c = GetEntityCoords(ped)
        local items = { { name = e.name, count = count, meta = e.meta } }
        e.count = e.count - count
        if e.count <= 0 then inv.items[slot] = nil end
        createDrop({ x = c.x, y = c.y, z = c.z - 0.9 }, items)
        saveInv(src); pushState(src)
    end
end)

--- ridica un drop
RegisterNetEvent('ph_inventory:sv:pickup', function(dropId)
    local src = source
    local inv = INV[src]
    local d = DROPS[tonumber(dropId)]
    if not inv or not d then return end

    local ped = GetPlayerPed(src)
    local c = GetEntityCoords(ped)
    local dx, dy, dz = d.coords.x - c.x, d.coords.y - c.y, d.coords.z - c.z
    if (dx * dx + dy * dy + dz * dz) > (Config.Drop.PickupDistance ^ 2) then
        return notify(src, 'Prea departe de item.', '#e07a7a')
    end

    local leftover = {}
    for _, e in ipairs(d.items) do
        local ok = addItem(src, e.name, e.count, e.meta)
        if not ok then leftover[#leftover + 1] = e end
    end

    if #leftover == 0 then
        removeDrop(d.id)
    else
        d.items = leftover
        TriggerClientEvent('ph_inventory:cl:dropAdd', -1, d.id, d.coords, dropPreview(leftover))
        notify(src, 'Inventar plin - o parte a ramas pe jos.', '#e0c07a')
    end
    saveInv(src); pushState(src)
end)

-- ----------------------------------------------------------
--  Echipament (haine / accesorii)
-- ----------------------------------------------------------
RegisterNetEvent('ph_inventory:sv:equip', function(slot)
    local src = source
    local inv = INV[src]
    if not inv then return end
    slot = tonumber(slot)
    local e = inv.items[slot]
    if not e then return end
    local d = itemDef(e.name)
    if not d or d.type ~= 'clothing' or not d.slot then return end

    -- pune inapoi in grid ce era echipat pe acel slot
    local prev = inv.equipment[d.slot]
    inv.items[slot] = nil
    inv.equipment[d.slot] = { name = e.name, meta = e.meta }
    if prev then
        local free = firstFreeSlot(inv)
        if free then inv.items[free] = { name = prev.name, count = 1, meta = prev.meta } end
    end

    TriggerClientEvent('ph_inventory:cl:applyEquipment', src, inv.equipment)
    saveInv(src); pushState(src)
end)

RegisterNetEvent('ph_inventory:sv:unequip', function(eqSlot)
    local src = source
    local inv = INV[src]
    if not inv or type(eqSlot) ~= 'string' then return end
    local e = inv.equipment[eqSlot]
    if not e then return end
    local free = firstFreeSlot(inv)
    if not free then return notify(src, 'Nu ai slot liber.', '#e07a7a') end

    inv.equipment[eqSlot] = nil
    inv.items[free] = { name = e.name, count = 1, meta = e.meta }
    TriggerClientEvent('ph_inventory:cl:applyEquipment', src, inv.equipment)
    saveInv(src); pushState(src)
end)

-- ----------------------------------------------------------
--  Hotbar / fast slots
-- ----------------------------------------------------------
RegisterNetEvent('ph_inventory:sv:setHotbar', function(hotIndex, slot)
    local src = source
    local inv = INV[src]
    if not inv then return end
    hotIndex = tonumber(hotIndex)
    if not hotIndex or hotIndex < 1 or hotIndex > Config.HotbarSlots then return end
    inv.hotbar[hotIndex] = slot and tonumber(slot) or nil
    saveInv(src); pushState(src)
end)

RegisterNetEvent('ph_inventory:sv:useHotbar', function(hotIndex)
    local src = source
    local inv = INV[src]
    if not inv then return end
    hotIndex = tonumber(hotIndex)
    local slot = inv.hotbar[hotIndex]
    local e = slot and inv.items[slot]
    if not e then return end
    local d = itemDef(e.name)
    if not d then return end

    if d.type == 'weapon' then
        if Config.Weapon.BrokenBlocksEquip and e.meta and (e.meta.durability or 0) <= 0 then
            return notify(src, 'Arma este stricata. Trebuie reparata.', '#e07a7a')
        end
        TriggerClientEvent('ph_inventory:cl:equipWeapon', src, {
            slot = slot,
            weaponName = d.weaponName,
            ammo = e.meta and e.meta.ammo or 0,
            durability = e.meta and e.meta.durability or Config.Weapon.MaxDurability,
        })
    elseif d.usable then
        e.count = e.count - 1
        if e.count <= 0 then inv.items[slot] = nil end
        TriggerClientEvent('ph_inventory:cl:useEffect', src, d.effect, d.value, e.name)
        saveInv(src); pushState(src)
    end
end)

--- clientul sincronizeaza gloante + durabilitate dupa tras
RegisterNetEvent('ph_inventory:sv:weaponSync', function(slot, ammo, durability)
    local src = source
    local inv = INV[src]
    if not inv then return end
    local e = inv.items[tonumber(slot)]
    if not e or not e.meta then return end
    e.meta.ammo = math.max(0, math.min(Config.Weapon.MaxLoadedAmmo, math.floor(tonumber(ammo) or e.meta.ammo)))
    e.meta.durability = math.max(0, math.min(Config.Weapon.MaxDurability, tonumber(durability) or e.meta.durability))
    saveInv(src)
end)

-- ----------------------------------------------------------
--  Comenzi
-- ----------------------------------------------------------
RegisterCommand('giveitem', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'ph.admin') then return end
    local target = tonumber(args[1])
    local name = args[2]
    local count = tonumber(args[3]) or 1
    if not target or not name or not Config.Items[name] then
        print('uz: giveitem <playerId> <item> [count]')
        return
    end
    if addItem(target, name, count) then
        saveInv(target); pushState(target)
        notify(target, ('Ai primit %dx %s'):format(count, Config.Items[name].label), '#8ce07a')
    end
end, false)

RegisterCommand('setslots', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'ph.admin') then return end
    local target = tonumber(args[1])
    local n = tonumber(args[2])
    if not target or not n then print('uz: setslots <playerId> <nrSloturi>') return end
    n = math.max(Config.DefaultSlots, math.min(500, math.floor(n)))
    local char = charOf(target)
    if not char then print('jucator neincarcat') return end
    MySQL.update.await('UPDATE users SET inv_slots = ? WHERE id = ?', { n, char.id })
    if INV[target] then INV[target].slots = n; pushState(target) end
    print(('sloturi pentru %d setate la %d'):format(target, n))
end, false)

-- ----------------------------------------------------------
--  Exports pentru alte resurse
-- ----------------------------------------------------------
exports('GiveItem', function(src, name, count, meta)
    if not INV[src] then return false end
    local ok = addItem(src, name, count or 1, meta)
    if ok then saveInv(src); pushState(src) end
    return ok
end)

exports('RemoveItem', function(src, name, count)
    if not INV[src] then return false end
    local ok = removeItem(src, name, count or 1)
    if ok then saveInv(src); pushState(src) end
    return ok
end)

exports('HasItem', function(src, name, count)
    return countItem(src, name) >= (count or 1)
end)

exports('GetItemCount', function(src, name)
    return countItem(src, name)
end)

exports('GetInventory', function(src)
    return INV[src]
end)
