-- ==========================================================
--  ph_inventory / server
--
--  Model: SERVER-DRIVEN AUTHORITATIVE.
--    NUI trimite un event -> serverul valideaza si muta itemele in INV[src]
--    -> serverul trimite `ph_inventory:cl:state` inapoi cu starea reala din
--    memorie.  NUI-ul NU muta niciodata itemele local; doar deseneaza `state`.
--
--  Sloturi: strict numere intregi.
--    grid      = 1 .. inv.slots
--    haine     = 101 .. 111  (Config.ClothingSlots)
--    hotbar    = 1 .. Config.HotbarSlots  (pointeri catre sloturi de grid)
--
--  Wire format (server -> client), imun la "array-ification" msgpack:
--    items    = { { slot=1, name=, count=, meta= }, ... }   -- LISTA, nu map
--    hotbar   = { { i=1, s=12 }, ... }                      -- LISTA
--    equipment= { hat = { name=, meta= }, ... }             -- map cu chei string
-- ==========================================================
local PH = 'ph-core'
local ready = false
math.randomseed(os.time())

local INV     = {}   -- [src] = { slots, items = { [slot]={name,count,meta} }, equipment = {}, hotbar = {} }
local DROPS   = {}   -- [dropId] = { id, coords, items = { {name,count,meta}, ... }, expires }
local dropSeq = 0
local dirty   = {}   -- [src] = true   (scriere debounce)

-- ----------------------------------------------------------
--  DB init / migratie  (o singura interogare in loc de 3)
-- ----------------------------------------------------------
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    while GetResourceState(PH) ~= 'started' do Wait(200) end

    local ok = pcall(function()
        MySQL.query.await(([[
            ALTER TABLE `users`
              ADD COLUMN IF NOT EXISTS `inventory` LONGTEXT NULL DEFAULT NULL,
              ADD COLUMN IF NOT EXISTS `inv_slots` SMALLINT NOT NULL DEFAULT %d
        ]]):format(Config.DefaultSlots))
    end)

    if not ok then
        -- fallback pentru MySQL vechi fara "ADD COLUMN IF NOT EXISTS"
        local ok2, err = pcall(function()
            local has = MySQL.scalar.await([[
                SELECT COUNT(*) FROM information_schema.columns
                WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'inventory'
            ]])
            if (tonumber(has) or 0) == 0 then
                MySQL.query.await("ALTER TABLE `users` ADD COLUMN `inventory` LONGTEXT NULL DEFAULT NULL")
                MySQL.query.await("ALTER TABLE `users` ADD COLUMN `inv_slots` SMALLINT NOT NULL DEFAULT " .. Config.DefaultSlots)
            end
        end)
        if not ok2 then
            print('^1[ph_inventory] eroare init DB:^7 ' .. tostring(err))
            return
        end
    end

    ready = true
    print('^5[ph_inventory]^7 pregatit.')
end)

-- ----------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------
local function itemDef(name) return Config.Items[name] end
local function charOf(src)   return exports[PH]:GetCharacter(src) end

local function notify(src, text, color)
    if GetResourceState('ph_chat') == 'started' then
        exports['ph_chat']:send(src, { text = text, textColor = color or '#e8e6f0' })
    else
        TriggerClientEvent('chat:addMessage', src, { args = { text } })
    end
end

--- coercitie stricta la numar intreg (nil daca nu e valid)
local function toInt(v)
    local n = tonumber(v)
    if not n then return nil end
    n = math.floor(n)
    return n
end

--- slot valid de grid: numar intreg in 1 .. inv.slots
local function validGrid(inv, n)
    return type(n) == 'number' and n == math.floor(n) and n >= 1 and n <= inv.slots
end

local function isClothingSlot(n)
    return n ~= nil and Config.ClothingSlots[n] ~= nil
end

local function newMeta(name)
    local d = itemDef(name)
    if d and d.type == 'weapon' then
        return {
            ammo       = 0,
            durability = Config.Weapon.MaxDurability,
            serial     = ('%05d'):format(math.random(0, 99999)),
        }
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

--- curata pointerii de hotbar care nu mai indica spre un item valid
local function sanitizeHotbar(inv)
    for i = 1, Config.HotbarSlots do
        local s = inv.hotbar[i]
        if s ~= nil then
            local e = inv.items[s]
            local d = e and itemDef(e.name)
            if not e or not d or not (d.type == 'weapon' or d.usable) then
                inv.hotbar[i] = nil
            end
        end
    end
end

--- muta pointerii de hotbar cand itemul urmarit se muta / dispare de pe `from`
local function remapHotbar(inv, from, to)
    for i = 1, Config.HotbarSlots do
        if inv.hotbar[i] == from then
            if to and validGrid(inv, to) then
                inv.hotbar[i] = to
            else
                inv.hotbar[i] = nil
            end
        end
    end
end

--- schimba intre ele pointerii de hotbar cand doua sloturi fac swap
local function swapHotbar(inv, from, to)
    for i = 1, Config.HotbarSlots do
        if inv.hotbar[i] == from then
            inv.hotbar[i] = to
        elseif inv.hotbar[i] == to then
            inv.hotbar[i] = from
        end
    end
end

-- ----------------------------------------------------------
--  Persistenta
-- ----------------------------------------------------------
--- serializare imuna la sparse array: items/hotbar ca LISTE
local function serialize(inv)
    local items = {}
    for slot, e in pairs(inv.items) do
        items[#items + 1] = { slot = slot, name = e.name, count = e.count, meta = e.meta }
    end
    local hotbar = {}
    for i = 1, Config.HotbarSlots do
        if inv.hotbar[i] then hotbar[#hotbar + 1] = { i = i, s = inv.hotbar[i] } end
    end
    return json.encode({ v = 2, items = items, equipment = inv.equipment or {}, hotbar = hotbar })
end

local function writeInv(src)
    local inv  = INV[src]
    local char = charOf(src)
    if not inv or not char then return end
    dirty[src] = nil
    MySQL.update('UPDATE users SET inventory = ? WHERE id = ?', { serialize(inv), char.id })
end

--- marcheaza pentru scriere; flush debounce (vezi thread-ul de mai jos)
local function saveInv(src)
    dirty[src] = true
end

local function loadInv(src)
    local char = charOf(src)
    if not char then return end

    local okQ, row = pcall(function()
        return MySQL.single.await('SELECT inventory, inv_slots FROM users WHERE id = ?', { char.id })
    end)
    if not okQ then
        print('^1[ph_inventory] SELECT users.inventory a esuat (coloane lipsa?):^7 ' .. tostring(row))
        row = nil
    end

    local slots  = (row and toInt(row.inv_slots)) or Config.DefaultSlots
    local items  = {}
    local hotbar = {}
    local equipment = {}

    if row and row.inventory and row.inventory ~= '' then
        local ok, dec = pcall(json.decode, row.inventory)
        if ok and type(dec) == 'table' then
            equipment = type(dec.equipment) == 'table' and dec.equipment or {}

            local list = dec.items
            if type(list) == 'table' and (dec.v == 2 or (list[1] and list[1].slot ~= nil)) then
                -- format v2: lista de intrari
                for _, e in ipairs(list) do
                    local s = toInt(e.slot)
                    if s then
                        items[s] = { name = e.name, count = toInt(e.count) or 1, meta = e.meta }
                    end
                end
                for _, h in ipairs(dec.hotbar or {}) do
                    local i, s = toInt(h.i), toInt(h.s)
                    if i and s then hotbar[i] = s end
                end
            else
                -- format legacy v1: map slot -> intrare
                for k, v in pairs(list or {}) do
                    local s = toInt(k)
                    if s and type(v) == 'table' then
                        items[s] = { name = v.name, count = toInt(v.count) or 1, meta = v.meta }
                    end
                end
                for k, v in pairs(dec.hotbar or {}) do
                    local i, s = toInt(k), toInt(v)
                    if i and s then hotbar[i] = s end
                end
            end
        end
    end

    -- normalizeaza: scoate cheile invalide si aduna itemele peste capacitate
    local overflow = {}
    for slot, e in pairs(items) do
        if type(slot) ~= 'number' or slot ~= math.floor(slot) or slot < 1 then
            items[slot] = nil
        elseif slot > slots then
            items[slot] = nil
            overflow[#overflow + 1] = e
        end
    end
    -- relocheaza itemele overflow in sloturi libere (fara sa stearga nimic)
    for _, e in ipairs(overflow) do
        local free
        for i = 1, slots do if not items[i] then free = i break end end
        if free then items[free] = e end
    end

    INV[src] = { slots = slots, items = items, equipment = equipment, hotbar = hotbar }
    sanitizeHotbar(INV[src])
end

-- forward declaratii (folosite in sv:context inainte de definirea din sectiunea "Drop-uri")
local createDrop, dropPreview

-- ----------------------------------------------------------
--  Push catre client
-- ----------------------------------------------------------
local function pushConfig(src)
    local inv = INV[src]
    TriggerClientEvent('ph_inventory:cl:config', src, {
        slots            = inv and inv.slots or Config.DefaultSlots,
        maxWeight        = Config.MaxWeight,
        defs             = Config.Items,
        equipmentSlots   = Config.EquipmentSlots,
        equipmentOrder   = Config.EquipmentOrder,
        equipmentSlotIds = Config.EquipmentSlotIds,
        clothingSlots    = Config.ClothingSlots,
        hotbarSlots      = Config.HotbarSlots,
        weapon           = Config.Weapon,
    })
end

local function pushState(src)
    local inv = INV[src]
    if not inv then return end
    sanitizeHotbar(inv)

    local items = {}
    for slot, e in pairs(inv.items) do
        items[#items + 1] = { slot = slot, name = e.name, count = e.count, meta = e.meta }
    end
    local hotbar = {}
    for i = 1, Config.HotbarSlots do
        if inv.hotbar[i] then hotbar[#hotbar + 1] = { i = i, s = inv.hotbar[i] } end
    end

    TriggerClientEvent('ph_inventory:cl:state', src, {
        slots     = inv.slots,
        weight    = weightOf(inv),
        items     = items,
        equipment = inv.equipment,
        hotbar    = hotbar,
    })
end

local function applyPedEquipment(src)
    local inv = INV[src]
    if not inv then return end
    TriggerClientEvent('ph_inventory:cl:applyEquipment', src, inv.equipment)
end

-- ----------------------------------------------------------
--  Operatii de baza (add / count / remove)  -- folosite de exports & drop
-- ----------------------------------------------------------
local function addItem(src, name, count, meta)
    local inv = INV[src]
    local d   = itemDef(name)
    count = toInt(count) or 0
    if not inv or not d or count <= 0 then return false end
    if weightOf(inv) + d.weight * count > Config.MaxWeight then return false end

    if meta or (d.stack or 1) <= 1 then
        for _ = 1, count do
            local s = firstFreeSlot(inv)
            if not s then return false end
            inv.items[s] = { name = name, count = 1, meta = meta or newMeta(name) }
        end
        return true
    end

    -- stackabil: umple stack-urile existente, apoi sloturi noi
    for _, e in pairs(inv.items) do
        if e.name == name and not e.meta and e.count < d.stack then
            local take = math.min(d.stack - e.count, count)
            e.count = e.count + take
            count   = count - take
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
    for _, e in pairs(inv.items) do
        if e.name == name then n = n + e.count end
    end
    return n
end

local function removeItem(src, name, count)
    local inv = INV[src]
    if not inv then return false end
    count = toInt(count) or 0
    if count <= 0 or countItem(src, name) < count then return false end
    for s, e in pairs(inv.items) do
        if e.name == name then
            local take = math.min(e.count, count)
            e.count = e.count - take
            count   = count - take
            if e.count <= 0 then inv.items[s] = nil end
            if count <= 0 then break end
        end
    end
    sanitizeHotbar(inv)
    return count <= 0
end

-- ----------------------------------------------------------
--  DRAG & DROP  (nucleul - 3 cazuri, nu se pierde niciun item)
-- ----------------------------------------------------------
--- muta un item intre doua sloturi de GRID.
--  @return changed (bool)
local function doGridMove(inv, from, to, count)
    local a = inv.items[from]
    if not a then return false end

    local da = itemDef(a.name)
    local maxStack = (da and da.stack) or 1

    -- cate bucati vrem sa mutam (drag & drop trimite mereu tot stack-ul)
    count = toInt(count) or a.count
    if count < 1 then count = a.count end
    if count > a.count then count = a.count end

    local b = inv.items[to]

    -- ---- CAZ 1: slot destinatie GOL --------------------------------
    if not b then
        if count >= a.count then
            inv.items[to]   = a
            inv.items[from] = nil
            remapHotbar(inv, from, to)
        else
            inv.items[to] = { name = a.name, count = count, meta = nil }
            a.count = a.count - count
        end
        return true
    end

    -- ---- CAZ 2: acelasi item, stackabil, fara meta -> STACKING -----
    if b.name == a.name and not a.meta and not b.meta and maxStack > 1 then
        local room = maxStack - b.count
        if room <= 0 then
            -- stack destinatie plin -> swap complet (nimic pierdut)
            inv.items[from], inv.items[to] = b, a
            swapHotbar(inv, from, to)
            return true
        end
        local moved = math.min(room, count)
        b.count = b.count + moved
        a.count = a.count - moved
        if a.count <= 0 then
            inv.items[from] = nil
            remapHotbar(inv, from, nil)
        end
        return true
    end

    -- ---- CAZ 3: iteme diferite (sau meta / non-stack) -> SWAP ------
    -- swap doar la mutare de stack intreg; mutarea partiala peste un
    -- slot ocupat de alt item se ignora (altfel s-ar pierde diferenta)
    if count >= a.count then
        inv.items[from], inv.items[to] = b, a
        swapHotbar(inv, from, to)
        return true
    end
    return false
end

--- muta intre grid <-> slot de haine (echipare / dezechipare / swap)
--  @return changed (bool)
local function doClothingMove(src, inv, from, to)
    local fromKey = Config.ClothingSlots[from]
    local toKey   = Config.ClothingSlots[to]

    -- GRID -> HAINE  (echipare)
    if not fromKey and toKey then
        if not validGrid(inv, from) then return false end
        local e = inv.items[from]
        if not e then return false end
        local d = itemDef(e.name)
        if not d or d.type ~= 'clothing' or d.slot ~= toKey then
            notify(src, 'Acest obiect nu se poate echipa in slotul respectiv.', '#e07a7a')
            return false
        end

        local prev = inv.equipment[toKey]
        inv.equipment[toKey] = { name = e.name, meta = e.meta }

        -- scoate o bucata din grid
        if (e.count or 1) > 1 then
            e.count = e.count - 1
        else
            inv.items[from] = nil
            remapHotbar(inv, from, nil)
        end

        -- pune inapoi in grid ce era echipat
        if prev then
            local dest = (not inv.items[from]) and from or firstFreeSlot(inv)
            if not dest then
                -- fara loc: anuleaza tot, restaureaza starea initiala
                inv.equipment[toKey] = prev
                if inv.items[from] and inv.items[from].name == e.name and not e.meta then
                    inv.items[from].count = inv.items[from].count + 1
                else
                    inv.items[from] = { name = e.name, count = 1, meta = e.meta }
                end
                notify(src, 'Nu ai loc in inventar pentru obiectul scos.', '#e07a7a')
                return false
            end
            inv.items[dest] = { name = prev.name, count = 1, meta = prev.meta }
        end

        applyPedEquipment(src)
        return true
    end

    -- HAINE -> GRID  (dezechipare)
    if fromKey and not toKey then
        local worn = inv.equipment[fromKey]
        if not worn then return false end
        if not validGrid(inv, to) then return false end

        local tgt = inv.items[to]
        if tgt then
            local dd = itemDef(worn.name)
            if tgt.name == worn.name and not tgt.meta and not worn.meta
               and dd and (dd.stack or 1) > 1 and tgt.count < dd.stack then
                tgt.count = tgt.count + 1
            else
                local free = firstFreeSlot(inv)
                if not free then
                    notify(src, 'Nu ai slot liber.', '#e07a7a')
                    return false
                end
                inv.items[free] = { name = worn.name, count = 1, meta = worn.meta }
            end
        else
            inv.items[to] = { name = worn.name, count = 1, meta = worn.meta }
        end

        inv.equipment[fromKey] = nil
        applyPedEquipment(src)
        return true
    end

    -- HAINE -> HAINE  (fara efect util) / alt caz -> ignora
    return false
end

--- muta / merge / split in grid + haine
RegisterNetEvent('ph_inventory:sv:move', function(from, to, count)
    local src = source
    local inv = INV[src]
    if not inv then return end

    from  = toInt(from)
    to    = toInt(to)
    count = toInt(count)

    if not from or not to or from == to then
        return pushState(src)   -- re-sincronizeaza NUI-ul
    end

    local changed
    if isClothingSlot(from) or isClothingSlot(to) then
        changed = doClothingMove(src, inv, from, to)
    elseif validGrid(inv, from) and validGrid(inv, to) then
        changed = doGridMove(inv, from, to, count)
    else
        changed = false
    end

    if changed then saveInv(src) end
    pushState(src)
end)

--- incarca gloante peste arma (drag ammo -> weapon)
RegisterNetEvent('ph_inventory:sv:loadAmmo', function(ammoSlot, weaponSlot)
    local src = source
    local inv = INV[src]
    if not inv then return end

    ammoSlot   = toInt(ammoSlot)
    weaponSlot = toInt(weaponSlot)
    if not validGrid(inv, ammoSlot) or not validGrid(inv, weaponSlot) then return pushState(src) end

    local ammo = inv.items[ammoSlot]
    local wpn  = inv.items[weaponSlot]
    if not ammo or not wpn then return pushState(src) end

    local wd, ad = itemDef(wpn.name), itemDef(ammo.name)
    if not wd or wd.type ~= 'weapon' or not wd.ammoType then return pushState(src) end
    if not ad or ad.type ~= 'ammo' or wd.ammoType ~= ammo.name then
        notify(src, 'Munitie incompatibila cu arma.', '#e07a7a')
        return pushState(src)
    end

    wpn.meta = wpn.meta or newMeta(wpn.name)
    local room = Config.Weapon.MaxLoadedAmmo - (wpn.meta.ammo or 0)
    if room <= 0 then
        notify(src, 'Arma este deja plina (max ' .. Config.Weapon.MaxLoadedAmmo .. ').', '#e0c07a')
        return pushState(src)
    end

    local take = math.min(room, ammo.count)
    wpn.meta.ammo = (wpn.meta.ammo or 0) + take
    ammo.count = ammo.count - take
    if ammo.count <= 0 then
        inv.items[ammoSlot] = nil
        remapHotbar(inv, ammoSlot, nil)
    end

    notify(src, ('Incarcat %d gloante. Total: %d/%d'):format(take, wpn.meta.ammo, Config.Weapon.MaxLoadedAmmo), '#8ce07a')
    saveInv(src)
    pushState(src)
end)

--- use / split / drop din context menu
RegisterNetEvent('ph_inventory:sv:context', function(op, slot, count)
    local src = source
    local inv = INV[src]
    if not inv then return end

    slot = toInt(slot)
    if not validGrid(inv, slot) then return pushState(src) end
    local e = inv.items[slot]
    if not e then return pushState(src) end
    local d = itemDef(e.name)

    if op == 'use' then
        if not d or not d.usable then return pushState(src) end
        e.count = e.count - 1
        if e.count <= 0 then inv.items[slot] = nil end
        TriggerClientEvent('ph_inventory:cl:useEffect', src, d.effect, d.value, e.name)
        saveInv(src); pushState(src)

    elseif op == 'split' then
        count = toInt(count) or 0
        if count < 1 or count >= e.count or e.meta then return pushState(src) end
        local free = firstFreeSlot(inv)
        if not free then
            notify(src, 'Nu ai slot liber.', '#e07a7a')
            return pushState(src)
        end
        inv.items[free] = { name = e.name, count = count }
        e.count = e.count - count
        saveInv(src); pushState(src)

    elseif op == 'drop' then
        count = toInt(count) or e.count
        count = math.max(1, math.min(count, e.count))
        local c = GetEntityCoords(GetPlayerPed(src))
        local items = { { name = e.name, count = count, meta = e.meta } }
        e.count = e.count - count
        if e.count <= 0 then inv.items[slot] = nil end
        createDrop({ x = c.x, y = c.y, z = c.z - 0.9 }, items)
        saveInv(src); pushState(src)
    else
        pushState(src)
    end
end)

-- ----------------------------------------------------------
--  Drop-uri pe jos
-- ----------------------------------------------------------
function dropPreview(items)
    local out = {}
    for _, e in ipairs(items) do
        local d = itemDef(e.name)
        out[#out + 1] = { name = e.name, label = d and d.label or e.name, count = e.count }
    end
    return out
end

function createDrop(coords, items)  -- luainspect: se atribuie forward-declaratiei locale
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

CreateThread(function()
    while true do
        Wait(30000)
        local now = GetGameTimer()
        for id, d in pairs(DROPS) do
            if now >= d.expires then removeDrop(id) end
        end
    end
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

RegisterNetEvent('ph_inventory:sv:pickup', function(dropId)
    local src = source
    local inv = INV[src]
    local d   = DROPS[toInt(dropId)]
    if not inv or not d then return pushState(src) end

    local c = GetEntityCoords(GetPlayerPed(src))
    local dx, dy, dz = d.coords.x - c.x, d.coords.y - c.y, d.coords.z - c.z
    if (dx * dx + dy * dy + dz * dz) > (Config.Drop.PickupDistance ^ 2) then
        notify(src, 'Prea departe de item.', '#e07a7a')
        return pushState(src)
    end

    local leftover = {}
    for _, e in ipairs(d.items) do
        if not addItem(src, e.name, e.count, e.meta) then
            leftover[#leftover + 1] = e
        end
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
--  Echipament (compat - drag pe cell-ul de haine merge deja prin sv:move)
-- ----------------------------------------------------------
RegisterNetEvent('ph_inventory:sv:equip', function(slot, eqSlot)
    local src = source
    local inv = INV[src]
    if not inv then return end
    slot   = toInt(slot)
    eqSlot = toInt(eqSlot)
    if not validGrid(inv, slot) then return pushState(src) end

    -- daca nu ni s-a dat slotul de haine, il deducem din item
    if not eqSlot then
        local e = inv.items[slot]
        local d = e and itemDef(e.name)
        if not d or d.type ~= 'clothing' or not d.slot then return pushState(src) end
        eqSlot = Config.EquipmentSlotIds[d.slot]
    end
    if not isClothingSlot(eqSlot) then return pushState(src) end

    if doClothingMove(src, inv, slot, eqSlot) then saveInv(src) end
    pushState(src)
end)

RegisterNetEvent('ph_inventory:sv:unequip', function(eqSlot)
    local src = source
    local inv = INV[src]
    if not inv then return end

    -- accepta atat numar (101..111) cat si cheie string ('hat')
    local num = toInt(eqSlot)
    if not num and type(eqSlot) == 'string' then num = Config.EquipmentSlotIds[eqSlot] end
    if not isClothingSlot(num) then return pushState(src) end

    local free = firstFreeSlot(inv)
    if not free then
        notify(src, 'Nu ai slot liber.', '#e07a7a')
        return pushState(src)
    end
    if doClothingMove(src, inv, num, free) then saveInv(src) end
    pushState(src)
end)

-- ----------------------------------------------------------
--  Hotbar / fast slots  (1 .. Config.HotbarSlots)
-- ----------------------------------------------------------
RegisterNetEvent('ph_inventory:sv:setHotbar', function(hotIndex, slot)
    local src = source
    local inv = INV[src]
    if not inv then return end

    hotIndex = toInt(hotIndex)
    if not hotIndex or hotIndex < 1 or hotIndex > Config.HotbarSlots then return pushState(src) end

    if slot == nil or slot == false then
        inv.hotbar[hotIndex] = nil
        saveInv(src); return pushState(src)
    end

    slot = toInt(slot)
    if not validGrid(inv, slot) then return pushState(src) end
    local e = inv.items[slot]
    if not e then return pushState(src) end
    local d = itemDef(e.name)
    if not d or not (d.type == 'weapon' or d.usable) then
        notify(src, 'Doar armele si consumabilele pot fi puse pe fast slot.', '#e07a7a')
        return pushState(src)
    end

    -- acelasi slot de grid nu poate fi pe doua fast-sloturi
    for i = 1, Config.HotbarSlots do
        if i ~= hotIndex and inv.hotbar[i] == slot then inv.hotbar[i] = nil end
    end
    inv.hotbar[hotIndex] = slot
    saveInv(src); pushState(src)
end)

RegisterNetEvent('ph_inventory:sv:useHotbar', function(hotIndex)
    local src = source
    local inv = INV[src]
    if not inv then return end

    hotIndex = toInt(hotIndex)
    if not hotIndex then return end
    local slot = inv.hotbar[hotIndex]
    local e    = slot and inv.items[slot]
    if not e then return end
    local d = itemDef(e.name)
    if not d then return end

    if d.type == 'weapon' then
        if Config.Weapon.BrokenBlocksEquip and e.meta and (e.meta.durability or 0) <= 0 then
            return notify(src, 'Arma este stricata. Trebuie reparata.', '#e07a7a')
        end
        TriggerClientEvent('ph_inventory:cl:equipWeapon', src, {
            slot       = slot,
            weaponName = d.weaponName,
            ammo       = e.meta and e.meta.ammo or 0,
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
    slot = toInt(slot)
    if not validGrid(inv, slot) then return end
    local e = inv.items[slot]
    if not e or not e.meta then return end
    e.meta.ammo       = math.max(0, math.min(Config.Weapon.MaxLoadedAmmo, toInt(ammo) or e.meta.ammo))
    e.meta.durability = math.max(0, math.min(Config.Weapon.MaxDurability, tonumber(durability) or e.meta.durability))
    saveInv(src)
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
            applyPedEquipment(src)
        end
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    if INV[src] then writeInv(src) end
    INV[src]   = nil
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
--  Comenzi
-- ----------------------------------------------------------
RegisterCommand('giveitem', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'ph.admin') then return end
    local target = toInt(args[1])
    local name   = args[2]
    local count  = toInt(args[3]) or 1
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
    local target = toInt(args[1])
    local n      = toInt(args[2])
    if not target or not n then print('uz: setslots <playerId> <nrSloturi>') return end
    n = math.max(Config.DefaultSlots, math.min(500, n))
    local char = charOf(target)
    if not char then print('jucator neincarcat') return end
    MySQL.update.await('UPDATE users SET inv_slots = ? WHERE id = ?', { n, char.id })
    if INV[target] then
        INV[target].slots = n
        sanitizeHotbar(INV[target])
        pushState(target)
    end
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
