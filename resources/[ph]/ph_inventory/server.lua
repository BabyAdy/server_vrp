-- ==========================================================
--  ph_inventory / server
--
--  Model: SERVER-DRIVEN AUTHORITATIVE.
--    NUI trimite un event -> serverul valideaza si muta itemele in INV[userId]
--    -> serverul trimite `ph_inventory:cl:state` inapoi cu starea reala din
--    memorie.  NUI-ul NU muta niciodata itemele local; doar deseneaza `state`.
--
--  Sloturi: strict numere intregi, fara suprapunere.
--    grid    = 1 .. inv.slots
--    haine   = 5001 .. 5011  (Config.ClothingSlots)
--    hotbar  = 6001 .. 6000+HotbarSlots  -- FAST SLOTS REALE (tin itemul,
--             deci itemul de pe hotbar NU mai apare si in grid)
--
--  Wire format (server -> client), imun la "array-ification" msgpack:
--    items    = { { slot=1, name=, count=, meta= }, ... }        -- LISTA
--    hotbar   = { { i=1, name=, count=, meta= }, ... }           -- LISTA
--    equipment= { hat = { name=, meta= }, ... }                  -- map chei string
--
--  Arme:
--    meta = { ammo, durability, attachments = { 'suppressor', ... }, serial }
--    maxAmmo / maxDurability = per-arma (Config.Items[x].maxAmmo) sau implicit.
--    La durabilitate 0 arma se sparge SI dispare (Config.Weapon.BreakAtZero).
--    Atasamentele sunt one-time-use: se consuma la montare, raman pana la
--    spargere sau pana sunt scoase din meniul de context (op 'rmattach').
-- ==========================================================
local PH = 'ph-core'
local ready = false
math.randomseed(os.time())

local INV     = {}
local DROPS   = {}
local dropSeq = 0
local dirty   = {}

local HOTBAR_MIN = Config.HotbarBase
local HOTBAR_MAX = Config.HotbarBase + Config.HotbarSlots - 1

-- ----------------------------------------------------------
--  DB init / migratie
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
            print('^1[ph_inventory] DB init error:^7 ' .. tostring(err))
            return
        end
    end

    ready = true
    print('^5[ph_inventory]^7 ready.')
end)

-- ----------------------------------------------------------
--  Identitate: totul se cheiaza pe SQL id (users.id), nu pe session id.
--    INV[userId], dirty[userId]
--    U[src] = userId   -> cache local, sursa de adevar pentru maparea inversa
--                        (nu depinde de ordinea de teardown a ph-core la disconnect)
-- ----------------------------------------------------------
local U = {}

local function itemDef(name) return Config.Items[name] end
local function charOf(src)   return exports[PH]:GetCharacter(src) end

--- session id -> SQL id
local function uidOf(src)
    local u = U[src]
    if u then return u end
    local ok, id = pcall(function()
        local v = exports[PH]:SourceToUserId(src)
        if v then return v end
        local c = exports[PH]:GetCharacter(src)
        return c and c.id or nil
    end)
    if ok and id then U[src] = id; return id end
    return nil
end

--- SQL id -> session id (nil daca jucatorul e offline)
local function srcOf(userId)
    local ok, s = pcall(function() return exports[PH]:GetSource(userId) end)
    return (ok and s) or nil
end

--- feedback de inventar = lucruri marunte -> notificare simpla deasupra minimapului
local function kindFromColor(color)
    if color == '#e07a7a' or color == '#ff4d4d' then return 'error' end
    if color == '#e0c07a' then return 'warning' end
    if color == '#8ce07a' then return 'success' end
    return 'info'
end

local function notify(src, text, color)
    if not src or src == 0 then return end
    exports[PH]:Notify(src, text, kindFromColor(color))
end

--- coercitie stricta la numar intreg (nil daca nu e valid)
local function toInt(v)
    local n = tonumber(v)
    if not n then return nil end
    return math.floor(n)
end

-- ---- sloturi ----
local function hotbarIndexOf(slot)
    if type(slot) ~= 'number' then return nil end
    if slot >= HOTBAR_MIN and slot <= HOTBAR_MAX then return slot - HOTBAR_MIN + 1 end
    return nil
end
local function hotbarSlotOf(i) return HOTBAR_MIN + i - 1 end
local function isHotbarSlot(slot) return hotbarIndexOf(slot) ~= nil end
local function isClothingSlot(n)  return n ~= nil and Config.ClothingSlots[n] ~= nil end

local function validGrid(inv, n)
    return type(n) == 'number' and n == math.floor(n) and n >= 1 and n <= inv.slots
end
local function validRealSlot(inv, n)
    return validGrid(inv, n) or isHotbarSlot(n)
end

--- acces uniform la orice slot REAL (grid sau hotbar) - NU haine
local function getSlot(inv, slot)
    local hi = hotbarIndexOf(slot)
    if hi then return inv.hotbar[hi] end
    return inv.items[slot]
end
local function setSlot(inv, slot, entry)
    local hi = hotbarIndexOf(slot)
    if hi then
        inv.hotbar[hi] = entry
    else
        inv.items[slot] = entry
    end
end

--- ce accepta un slot:  hotbar = doar arme / consumabile
local function slotAccepts(slot, name)
    if not isHotbarSlot(slot) then return true end
    local d = itemDef(name)
    return d ~= nil and (d.type == 'weapon' or d.usable == true)
end

-- ---- arme ----
local function maxAmmoOf(name)
    local d = itemDef(name)
    return (d and d.maxAmmo) or Config.Weapon.MaxLoadedAmmo
end
local function maxDurabilityOf(name)
    local d = itemDef(name)
    return (d and d.maxDurability) or Config.Weapon.MaxDurability
end

local function newMeta(name)
    local d = itemDef(name)
    if d and d.type == 'weapon' then
        return {
            ammo        = 0,
            durability  = maxDurabilityOf(name),
            attachments = {},
            serial      = ('%05d'):format(math.random(0, 99999)),
        }
    end
    return nil
end

--- normalizeaza meta unei arme (dupa load / dupa pickup)
local function ensureWeaponMeta(e)
    if not e then return end
    local d = itemDef(e.name)
    if not d or d.type ~= 'weapon' then return end
    e.meta = e.meta or {}
    e.meta.attachments = e.meta.attachments or {}
    if e.meta.ammo == nil then e.meta.ammo = 0 end
    if e.meta.durability == nil then e.meta.durability = maxDurabilityOf(e.name) end
    if not e.meta.serial then e.meta.serial = ('%05d'):format(math.random(0, 99999)) end
end

-- ----------------------------------------------------------
--  Greutate / sloturi libere
-- ----------------------------------------------------------
local function weightOf(inv)
    local w = 0.0
    for _, e in pairs(inv.items) do
        local d = itemDef(e.name)
        w = w + (d and d.weight or 0) * (e.count or 1)
    end
    for i = 1, Config.HotbarSlots do
        local e = inv.hotbar[i]
        if e then
            local d = itemDef(e.name)
            w = w + (d and d.weight or 0) * (e.count or 1)
        end
    end
    return w
end

local function firstFreeSlot(inv)
    for i = 1, inv.slots do
        if not inv.items[i] then return i end
    end
    return nil
end

--- fast slot invalid (item ne-arma / ne-consumabil ajuns cumva acolo) -> in grid
local function sanitizeHotbar(inv)
    for i = 1, Config.HotbarSlots do
        local e = inv.hotbar[i]
        if e then
            local d = itemDef(e.name)
            if d and not (d.type == 'weapon' or d.usable) then
                local free = firstFreeSlot(inv)
                if free then
                    inv.items[free] = e
                    inv.hotbar[i] = nil
                end
            end
        end
    end
end

--- Micsoreaza capacitatea grid-ului la `newSlots`.  Itemele de pe sloturile
--- care dispar se muta (stack-merge sau slot liber) in restul inventarului;
--- ce nu incape ajunge in Post Office.  Nu se pierde niciun item.
local function shrinkTo(uid, newSlots)
    local inv = INV[uid]
    if not inv then return end
    newSlots = math.floor(tonumber(newSlots) or inv.slots)
    if newSlots < Config.DefaultSlots then newSlots = Config.DefaultSlots end
    if newSlots >= inv.slots then
        inv.slots = newSlots
        return
    end

    local evict = {}
    for slot, e in pairs(inv.items) do
        if slot > newSlots then
            evict[#evict + 1] = e
            inv.items[slot] = nil
        end
    end
    inv.slots = newSlots   -- firstFreeSlot() scaneaza acum doar 1..newSlots

    for _, e in ipairs(evict) do
        local d = itemDef(e.name)
        if d and (d.stack or 1) > 1 and not e.meta and (e.count or 0) > 0 then
            for s = 1, newSlots do
                local t = inv.items[s]
                if t and t.name == e.name and not t.meta and t.count < d.stack then
                    local mv = math.min(d.stack - t.count, e.count)
                    t.count = t.count + mv
                    e.count = e.count - mv
                    if e.count <= 0 then break end
                end
            end
        end
        if (e.count or 0) > 0 then
            local free = firstFreeSlot(inv)
            if free then
                inv.items[free] = e
            else
                pcall(function()
                    exports['ph_postoffice']:Deposit(uid,
                        { name = e.name, count = e.count, meta = e.meta }, 'subscription expired')
                end)
            end
        end
    end
    sanitizeHotbar(inv)
end

-- ----------------------------------------------------------
--  Persistenta
-- ----------------------------------------------------------
local function serialize(inv)
    local items = {}
    for slot, e in pairs(inv.items) do
        items[#items + 1] = { slot = slot, name = e.name, count = e.count, meta = e.meta }
    end
    local hotbar = {}
    for i = 1, Config.HotbarSlots do
        local e = inv.hotbar[i]
        if e then hotbar[#hotbar + 1] = { i = i, name = e.name, count = e.count, meta = e.meta } end
    end
    return json.encode({ v = 3, items = items, equipment = inv.equipment or {}, hotbar = hotbar })
end

--- scrie inventarul pe SQL id (users.id) - fara nevoie de session id
local function writeInv(uid)
    local inv = INV[uid]
    if not uid or not inv then return end
    dirty[uid] = nil
    MySQL.update('UPDATE users SET inventory = ? WHERE id = ?', { serialize(inv), uid })
end

local function saveInv(uid) if uid then dirty[uid] = true end end

local function loadInv(src)
    local char = charOf(src)
    if not char then return end
    local uid = char.id
    U[src] = uid

    local okQ, row = pcall(function()
        return MySQL.single.await('SELECT inventory, inv_slots FROM users WHERE id = ?', { uid })
    end)
    if not okQ then
        print('^1[ph_inventory] SELECT users.inventory a esuat:^7 ' .. tostring(row))
        row = nil
    end

    -- capacitate = sloturi de baza (users.inv_slots) + bonus de abonament
    local base = (row and toInt(row.inv_slots)) or Config.DefaultSlots
    if base < Config.DefaultSlots then base = Config.DefaultSlots end
    if base > Config.MaxSlots then base = Config.MaxSlots end
    local bonus = 0
    pcall(function() bonus = tonumber(exports['ph_subscriptions']:GetSlotBonus(uid)) or 0 end)
    local slots = base + bonus

    local items, hotbar, equipment = {}, {}, {}

    if row and row.inventory and row.inventory ~= '' then
        local ok, dec = pcall(json.decode, row.inventory)
        if ok and type(dec) == 'table' then
            equipment = type(dec.equipment) == 'table' and dec.equipment or {}

            local list = dec.items
            local isList = type(list) == 'table' and (dec.v ~= nil or (list[1] and list[1].slot ~= nil))
            if isList then
                for _, e in ipairs(list) do
                    local s = toInt(e.slot)
                    if s then items[s] = { name = e.name, count = toInt(e.count) or 1, meta = e.meta } end
                end
            else
                for k, v in pairs(list or {}) do
                    local s = toInt(k)
                    if s and type(v) == 'table' then
                        items[s] = { name = v.name, count = toInt(v.count) or 1, meta = v.meta }
                    end
                end
            end

            -- hotbar: accepta v3 (entry), v2 (pointer {i,s}) si legacy map {i=ptr}
            for k, v in pairs(dec.hotbar or {}) do
                if type(v) == 'table' and v.i ~= nil then
                    local i = toInt(v.i)
                    if i and i >= 1 and i <= Config.HotbarSlots then
                        if v.name then
                            hotbar[i] = { name = v.name, count = toInt(v.count) or 1, meta = v.meta }
                        elseif v.s then
                            local p = toInt(v.s)
                            if p and items[p] then hotbar[i] = items[p]; items[p] = nil end
                        end
                    end
                else
                    local i, p = toInt(k), toInt(v)
                    if i and p and i >= 1 and i <= Config.HotbarSlots and items[p] and not hotbar[i] then
                        hotbar[i] = items[p]; items[p] = nil
                    end
                end
            end
        end
    end

    -- normalizeaza: cheile invalide afara, itemele peste capacitate relocate
    local overflow = {}
    for slot, e in pairs(items) do
        if type(slot) ~= 'number' or slot ~= math.floor(slot) or slot < 1 then
            items[slot] = nil
        elseif slot > slots then
            items[slot] = nil
            overflow[#overflow + 1] = e
        end
    end
    for _, e in ipairs(overflow) do
        -- 1. incearca sa umpli stack-uri existente
        local d = itemDef(e.name)
        if d and (d.stack or 1) > 1 and not e.meta and (e.count or 0) > 0 then
            for i = 1, slots do
                local t = items[i]
                if t and t.name == e.name and not t.meta and t.count < d.stack then
                    local mv = math.min(d.stack - t.count, e.count)
                    t.count = t.count + mv
                    e.count = e.count - mv
                    if e.count <= 0 then break end
                end
            end
        end
        -- 2. slot liber
        if (e.count or 0) > 0 then
            local free
            for i = 1, slots do if not items[i] then free = i break end end
            if free then
                items[free] = e
            else
                -- 3. nu incape -> post office
                pcall(function()
                    exports['ph_postoffice']:Deposit(uid,
                        { name = e.name, count = e.count, meta = e.meta }, 'slots reduced')
                end)
            end
        end
    end

    for _, e in pairs(items) do ensureWeaponMeta(e) end
    for i = 1, Config.HotbarSlots do ensureWeaponMeta(hotbar[i]) end

    INV[uid] = {
        slots = slots, baseSlots = base, subBonus = bonus,
        items = items, equipment = equipment, hotbar = hotbar,
    }
    sanitizeHotbar(INV[uid])
end

-- forward-declaratii (folosite inainte de definitia din sectiunea "Drop-uri")
local createDrop, dropPreview

-- ----------------------------------------------------------
--  Push catre client
-- ----------------------------------------------------------
local function pushConfig(src)
    local inv = INV[uidOf(src)]
    TriggerClientEvent('ph_inventory:cl:config', src, {
        slots            = inv and inv.slots or Config.DefaultSlots,
        maxWeight        = Config.MaxWeight,
        defs             = Config.Items,
        equipmentSlots   = Config.EquipmentSlots,
        equipmentOrder   = Config.EquipmentOrder,
        equipmentSlotIds = Config.EquipmentSlotIds,
        clothingSlots    = Config.ClothingSlots,
        hotbarSlots      = Config.HotbarSlots,
        hotbarBase       = Config.HotbarBase,
        attachments      = Config.Attachments,
        weapon           = Config.Weapon,
    })
end

local function pushState(src)
    local inv = INV[uidOf(src)]
    if not inv then return end
    sanitizeHotbar(inv)

    local items = {}
    for slot, e in pairs(inv.items) do
        items[#items + 1] = { slot = slot, name = e.name, count = e.count, meta = e.meta }
    end
    local hotbar = {}
    for i = 1, Config.HotbarSlots do
        local e = inv.hotbar[i]
        if e then hotbar[#hotbar + 1] = { i = i, name = e.name, count = e.count, meta = e.meta } end
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
    local inv = INV[uidOf(src)]
    if not inv then return end
    TriggerClientEvent('ph_inventory:cl:applyEquipment', src, inv.equipment)
end

-- ----------------------------------------------------------
--  Operatii de baza (add / count / remove)  -- exports & drop
-- ----------------------------------------------------------
local function addItem(uid, name, count, meta)
    local inv = INV[uid]
    local d   = itemDef(name)
    count = toInt(count) or 0
    if not inv or not d or count <= 0 then return false end
    if weightOf(inv) + d.weight * count > Config.MaxWeight then return false end

    if meta or (d.stack or 1) <= 1 then
        for _ = 1, count do
            local s = firstFreeSlot(inv)
            if not s then return false end
            local e = { name = name, count = 1, meta = meta or newMeta(name) }
            ensureWeaponMeta(e)
            inv.items[s] = e
        end
        return true
    end

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

local function countItem(uid, name)
    local inv = INV[uid]
    if not inv then return 0 end
    local n = 0
    for _, e in pairs(inv.items) do
        if e.name == name then n = n + e.count end
    end
    for i = 1, Config.HotbarSlots do
        local e = inv.hotbar[i]
        if e and e.name == name then n = n + e.count end
    end
    return n
end

local function removeItem(uid, name, count)
    local inv = INV[uid]
    if not inv then return false end
    count = toInt(count) or 0
    if count <= 0 or countItem(uid, name) < count then return false end
    for s, e in pairs(inv.items) do
        if e.name == name then
            local take = math.min(e.count, count)
            e.count = e.count - take
            count   = count - take
            if e.count <= 0 then inv.items[s] = nil end
            if count <= 0 then break end
        end
    end
    if count > 0 then
        for i = 1, Config.HotbarSlots do
            local e = inv.hotbar[i]
            if e and e.name == name then
                local take = math.min(e.count, count)
                e.count = e.count - take
                count   = count - take
                if e.count <= 0 then inv.hotbar[i] = nil end
                if count <= 0 then break end
            end
        end
    end
    return count <= 0
end

-- ----------------------------------------------------------
--  DRAG & DROP  (unificat grid + hotbar; 3 cazuri; zero pierderi)
-- ----------------------------------------------------------
local function doMove(src, inv, from, to, count)
    local a = getSlot(inv, from)
    if not a then return false end

    local da = itemDef(a.name)
    local maxStack = (da and da.stack) or 1

    count = toInt(count) or a.count
    if count < 1 or count > a.count then count = a.count end

    -- destinatia hotbar accepta doar arme / consumabile
    if isHotbarSlot(to) and not slotAccepts(to, a.name) then
        notify(src, 'Only weapons and consumables fit in a fast slot.', '#e07a7a')
        return false
    end

    local b = getSlot(inv, to)

    -- ---- CAZ 1: destinatie GOALA ----
    if not b then
        if count >= a.count then
            setSlot(inv, to, a)
            setSlot(inv, from, nil)
        else
            setSlot(inv, to, { name = a.name, count = count, meta = nil })
            a.count = a.count - count
        end
        return true
    end

    -- ---- CAZ 2: acelasi item stackabil, fara meta -> STACKING ----
    if b.name == a.name and not a.meta and not b.meta and maxStack > 1 then
        local room = maxStack - b.count
        if room <= 0 then
            setSlot(inv, from, b); setSlot(inv, to, a)   -- swap (stack plin)
            return true
        end
        local moved = math.min(room, count)
        b.count = b.count + moved
        a.count = a.count - moved
        if a.count <= 0 then setSlot(inv, from, nil) end
        return true
    end

    -- ---- CAZ 3: iteme diferite / meta / non-stack -> SWAP (doar stack intreg) ----
    if count >= a.count then
        -- swap-ul aduce `b` pe `from`; daca `from` e hotbar, `b` trebuie acceptat
        if isHotbarSlot(from) and not slotAccepts(from, b.name) then
            notify(src, 'You cannot move that to a fast slot.', '#e07a7a')
            return false
        end
        setSlot(inv, from, b); setSlot(inv, to, a)
        return true
    end
    return false
end

--- grid <-> slot de haine (echipare / dezechipare / swap)
local function doClothingMove(src, inv, from, to)
    local fromKey = Config.ClothingSlots[from]
    local toKey   = Config.ClothingSlots[to]

    -- GRID -> HAINE
    if not fromKey and toKey then
        if not validGrid(inv, from) then return false end
        local e = inv.items[from]
        if not e then return false end
        local d = itemDef(e.name)
        if not d or d.type ~= 'clothing' or d.slot ~= toKey then
            notify(src, 'This item cannot be equipped in that slot.', '#e07a7a')
            return false
        end

        local prev = inv.equipment[toKey]
        inv.equipment[toKey] = { name = e.name, meta = e.meta }

        if (e.count or 1) > 1 then
            e.count = e.count - 1
        else
            inv.items[from] = nil
        end

        if prev then
            local dest = (not inv.items[from]) and from or firstFreeSlot(inv)
            if not dest then
                inv.equipment[toKey] = prev
                if inv.items[from] and inv.items[from].name == e.name and not e.meta then
                    inv.items[from].count = inv.items[from].count + 1
                else
                    inv.items[from] = { name = e.name, count = 1, meta = e.meta }
                end
                notify(src, 'Not enough inventory space for the removed item.', '#e07a7a')
                return false
            end
            inv.items[dest] = { name = prev.name, count = 1, meta = prev.meta }
        end

        applyPedEquipment(src)
        return true
    end

    -- HAINE -> GRID
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
                    notify(src, 'No free slot.', '#e07a7a')
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

    return false
end

RegisterNetEvent('ph_inventory:sv:move', function(from, to, count)
    local src = source
    local uid = uidOf(src)
    local inv = INV[uid]
    if not inv then return end

    from  = toInt(from)
    to    = toInt(to)
    count = toInt(count)

    if not from or not to or from == to then return pushState(src) end

    local changed
    if isClothingSlot(from) or isClothingSlot(to) then
        changed = doClothingMove(src, inv, from, to)
    elseif validRealSlot(inv, from) and validRealSlot(inv, to) then
        changed = doMove(src, inv, from, to, count)
    else
        changed = false
    end

    if changed then saveInv(uid) end
    pushState(src)
end)

-- ----------------------------------------------------------
--  Munitie -> arma
-- ----------------------------------------------------------
RegisterNetEvent('ph_inventory:sv:loadAmmo', function(ammoSlot, weaponSlot)
    local src = source
    local uid = uidOf(src)
    local inv = INV[uid]
    if not inv then return end

    ammoSlot   = toInt(ammoSlot)
    weaponSlot = toInt(weaponSlot)
    if not validRealSlot(inv, ammoSlot) or not validRealSlot(inv, weaponSlot) then return pushState(src) end

    local ammo = getSlot(inv, ammoSlot)
    local wpn  = getSlot(inv, weaponSlot)
    if not ammo or not wpn then return pushState(src) end

    local wd, ad = itemDef(wpn.name), itemDef(ammo.name)
    if not wd or wd.type ~= 'weapon' or not wd.ammoType then return pushState(src) end
    if not ad or ad.type ~= 'ammo' or wd.ammoType ~= ammo.name then
        notify(src, 'Ammo not compatible with this weapon.', '#e07a7a')
        return pushState(src)
    end

    ensureWeaponMeta(wpn)
    local cap  = maxAmmoOf(wpn.name)
    local room = cap - (wpn.meta.ammo or 0)
    if room <= 0 then
        notify(src, ('Weapon is already full (max %d).'):format(cap), '#e0c07a')
        return pushState(src)
    end

    local take = math.min(room, ammo.count)
    wpn.meta.ammo = (wpn.meta.ammo or 0) + take
    ammo.count = ammo.count - take
    if ammo.count <= 0 then setSlot(inv, ammoSlot, nil) end

    notify(src, ('Loaded %d rounds. Total: %d/%d'):format(take, wpn.meta.ammo, cap), '#8ce07a')
    if isHotbarSlot(weaponSlot) then
        TriggerClientEvent('ph_inventory:cl:weaponMeta', src, weaponSlot, wpn.meta.ammo, wpn.meta.durability)
    end
    saveInv(uid); pushState(src)
end)

-- ----------------------------------------------------------
--  Atasamente -> arma  (one time use)
-- ----------------------------------------------------------
RegisterNetEvent('ph_inventory:sv:applyAttachment', function(attachSlot, weaponSlot)
    local src = source
    local uid = uidOf(src)
    local inv = INV[uid]
    if not inv then return end

    attachSlot = toInt(attachSlot)
    weaponSlot = toInt(weaponSlot)
    if not validRealSlot(inv, attachSlot) or not validRealSlot(inv, weaponSlot) then return pushState(src) end

    local at  = getSlot(inv, attachSlot)
    local wpn = getSlot(inv, weaponSlot)
    if not at or not wpn then return pushState(src) end

    local ad, wd = itemDef(at.name), itemDef(wpn.name)
    if not ad or ad.type ~= 'attachment' or not ad.attachment then return pushState(src) end
    if not wd or wd.type ~= 'weapon' then return pushState(src) end

    local key  = ad.attachment
    local acfg = Config.Attachments[key]
    if not acfg then return pushState(src) end

    local comp = (acfg.components and acfg.components[wd.weaponName]) or acfg.component
    if not comp then
        notify(src, 'Attachment not compatible with this weapon.', '#e07a7a')
        return pushState(src)
    end

    ensureWeaponMeta(wpn)
    for _, k in ipairs(wpn.meta.attachments) do
        if k == key then
            notify(src, 'Attachment is already fitted.', '#e0c07a')
            return pushState(src)
        end
    end

    wpn.meta.attachments[#wpn.meta.attachments + 1] = key
    at.count = at.count - 1
    if at.count <= 0 then setSlot(inv, attachSlot, nil) end

    notify(src, ('Fitted: %s'):format(acfg.label or key), '#8ce07a')
    TriggerClientEvent('ph_inventory:cl:weaponMods', src, weaponSlot, wpn.meta.attachments)
    saveInv(uid); pushState(src)
end)

-- ----------------------------------------------------------
--  Context menu: use / split / drop / rmattach
-- ----------------------------------------------------------
RegisterNetEvent('ph_inventory:sv:context', function(op, slot, count, extra)
    local src = source
    local uid = uidOf(src)
    local inv = INV[uid]
    if not inv then return end

    slot = toInt(slot)
    if not validRealSlot(inv, slot) then return pushState(src) end
    local e = getSlot(inv, slot)
    if not e then return pushState(src) end
    local d = itemDef(e.name)

    if op == 'use' then
        if not d or not d.usable then return pushState(src) end
        e.count = e.count - 1
        local usedName = e.name
        if e.count <= 0 then setSlot(inv, slot, nil) end
        TriggerClientEvent('ph_inventory:cl:useEffect', src, d.effect, d.value, usedName)
        TriggerEvent('ph_inventory:server:used', uid, usedName, d)   -- hook pentru alte resurse
        saveInv(uid); pushState(src)

    elseif op == 'split' then
        count = toInt(count) or 0
        if isHotbarSlot(slot) then return pushState(src) end     -- split doar in grid
        if count < 1 or count >= e.count or e.meta then return pushState(src) end
        local free = firstFreeSlot(inv)
        if not free then
            notify(src, 'No free slot.', '#e07a7a')
            return pushState(src)
        end
        inv.items[free] = { name = e.name, count = count }
        e.count = e.count - count
        saveInv(uid); pushState(src)

    elseif op == 'drop' then
        count = toInt(count) or e.count
        count = math.max(1, math.min(count, e.count))
        local c = GetEntityCoords(GetPlayerPed(src))
        local items = { { name = e.name, count = count, meta = e.meta } }
        e.count = e.count - count
        if e.count <= 0 then setSlot(inv, slot, nil) end
        createDrop({ x = c.x, y = c.y, z = c.z - 0.9 }, items)
        saveInv(uid); pushState(src)

    elseif op == 'rmattach' then
        if not d or d.type ~= 'weapon' or not e.meta or not e.meta.attachments then return pushState(src) end
        local key = tostring(extra or '')
        local removed
        for idx, k in ipairs(e.meta.attachments) do
            if k == key then
                table.remove(e.meta.attachments, idx)
                removed = k
                break
            end
        end
        if not removed then return pushState(src) end
        local acfg = Config.Attachments[removed]
        notify(src, ('Removed: %s'):format((acfg and acfg.label) or removed), '#e0c07a')
        TriggerClientEvent('ph_inventory:cl:weaponMods', src, slot, e.meta.attachments)
        saveInv(uid); pushState(src)

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

function createDrop(coords, items)
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
    local uid = uidOf(src)
    local inv = INV[uid]
    local d   = DROPS[toInt(dropId)]
    if not inv or not d then return pushState(src) end

    local c = GetEntityCoords(GetPlayerPed(src))
    local dx, dy, dz = d.coords.x - c.x, d.coords.y - c.y, d.coords.z - c.z
    if (dx * dx + dy * dy + dz * dz) > (Config.Drop.PickupDistance ^ 2) then
        notify(src, 'Too far from the item.', '#e07a7a')
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
        notify(src, 'Inventory full - some items were left on the ground.', '#e0c07a')
    end
    saveInv(uid); pushState(src)
end)

-- ----------------------------------------------------------
--  Echipament (compat - drag pe cell-ul de haine merge deja prin sv:move)
-- ----------------------------------------------------------
RegisterNetEvent('ph_inventory:sv:equip', function(slot, eqSlot)
    local src = source
    local uid = uidOf(src)
    local inv = INV[uid]
    if not inv then return end
    slot   = toInt(slot)
    eqSlot = toInt(eqSlot)
    if not validGrid(inv, slot) then return pushState(src) end

    if not eqSlot then
        local e = inv.items[slot]
        local d = e and itemDef(e.name)
        if not d or d.type ~= 'clothing' or not d.slot then return pushState(src) end
        eqSlot = Config.EquipmentSlotIds[d.slot]
    end
    if not isClothingSlot(eqSlot) then return pushState(src) end

    if doClothingMove(src, inv, slot, eqSlot) then saveInv(uid) end
    pushState(src)
end)

RegisterNetEvent('ph_inventory:sv:unequip', function(eqSlot)
    local src = source
    local uid = uidOf(src)
    local inv = INV[uid]
    if not inv then return end

    local num = toInt(eqSlot)
    if not num and type(eqSlot) == 'string' then num = Config.EquipmentSlotIds[eqSlot] end
    if not isClothingSlot(num) then return pushState(src) end

    local free = firstFreeSlot(inv)
    if not free then
        notify(src, 'No free slot.', '#e07a7a')
        return pushState(src)
    end
    if doClothingMove(src, inv, num, free) then saveInv(uid) end
    pushState(src)
end)

-- ----------------------------------------------------------
--  Fast slots (index 1..HotbarSlots de la taste)
-- ----------------------------------------------------------
RegisterNetEvent('ph_inventory:sv:useHotbar', function(hotIndex)
    local src = source
    local uid = uidOf(src)
    local inv = INV[uid]
    if not inv then return end

    hotIndex = toInt(hotIndex)
    if not hotIndex or hotIndex < 1 or hotIndex > Config.HotbarSlots then return end
    local e = inv.hotbar[hotIndex]
    if not e then return end
    local d = itemDef(e.name)
    if not d then return end

    if d.type == 'weapon' then
        ensureWeaponMeta(e)
        if Config.Weapon.BrokenBlocksEquip and (e.meta.durability or 0) <= 0 then
            return notify(src, 'The weapon is broken.', '#e07a7a')
        end
        TriggerClientEvent('ph_inventory:cl:equipWeapon', src, {
            slot          = hotbarSlotOf(hotIndex),
            weaponName    = d.weaponName,
            ammo          = e.meta.ammo or 0,
            durability    = e.meta.durability or maxDurabilityOf(e.name),
            maxAmmo       = maxAmmoOf(e.name),
            maxDurability = maxDurabilityOf(e.name),
            attachments   = e.meta.attachments or {},
        })
    elseif d.usable then
        e.count = e.count - 1
        local usedName = e.name
        if e.count <= 0 then inv.hotbar[hotIndex] = nil end
        TriggerClientEvent('ph_inventory:cl:useEffect', src, d.effect, d.value, usedName)
        TriggerEvent('ph_inventory:server:used', uid, usedName, d)   -- hook pentru alte resurse
        saveInv(uid); pushState(src)
    end
end)

--- clientul sincronizeaza gloante + durabilitate dupa tras
RegisterNetEvent('ph_inventory:sv:weaponSync', function(slot, ammo, durability)
    local src = source
    local uid = uidOf(src)
    local inv = INV[uid]
    if not inv then return end
    slot = toInt(slot)
    if not validRealSlot(inv, slot) then return end
    local e = getSlot(inv, slot)
    if not e or not e.meta then return end
    local d = itemDef(e.name)
    if not d or d.type ~= 'weapon' then return end

    local cap  = maxAmmoOf(e.name)
    local maxD = maxDurabilityOf(e.name)
    e.meta.ammo       = math.max(0, math.min(cap, toInt(ammo) or e.meta.ammo or 0))
    e.meta.durability = math.max(0, math.min(maxD, tonumber(durability) or e.meta.durability or maxD))

    if Config.Weapon.BreakAtZero and e.meta.durability <= 0 then
        setSlot(inv, slot, nil)
        notify(src, 'The weapon broke and was destroyed.', '#e07a7a')
        TriggerClientEvent('ph_inventory:cl:weaponBroke', src, slot)
        saveInv(uid); pushState(src)
        return
    end

    saveInv(uid)
end)

-- ----------------------------------------------------------
--  NUI / client -> server
-- ----------------------------------------------------------
RegisterNetEvent('ph_inventory:sv:request', function()
    local src = source
    if not INV[uidOf(src)] then loadInv(src) end
    pushConfig(src)
    pushState(src)
end)

-- ----------------------------------------------------------
--  ph-core hooks
-- ----------------------------------------------------------
AddEventHandler('ph-core:playerLoaded', function(src)
    if not ready then
        SetTimeout(3000, function() if INV[uidOf(src)] == nil then loadInv(src) end end)
    else
        loadInv(src)
    end
    SetTimeout(1500, function()
        if INV[uidOf(src)] then
            pushState(src)
            applyPedEquipment(src)
        end
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local uid = U[src] or uidOf(src)      -- U e sursa de adevar; nu depinde de teardown-ul ph-core
    if uid then
        if INV[uid] then writeInv(uid) end
        INV[uid]   = nil
        dirty[uid] = nil
    end
    U[src] = nil
end)

-- ----------------------------------------------------------
--  Abonamente: bonusul de sloturi s-a schimbat pentru un user
-- ----------------------------------------------------------
AddEventHandler('ph_subscriptions:bonusChanged', function(userId, newBonus)
    userId = tonumber(userId)
    local inv = INV[userId]
    if not inv then return end
    newBonus = math.max(0, math.floor(tonumber(newBonus) or 0))
    if newBonus == (inv.subBonus or 0) then return end

    inv.subBonus = newBonus
    local newSlots = (inv.baseSlots or Config.DefaultSlots) + newBonus
    if newSlots >= inv.slots then
        inv.slots = newSlots
    else
        shrinkTo(userId, newSlots)
    end
    saveInv(userId)
    local s = srcOf(userId)
    if s then pushState(s) end
end)

CreateThread(function()
    while true do
        Wait(15000)
        for uid in pairs(dirty) do
            if INV[uid] then writeInv(uid) end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for uid in pairs(INV) do writeInv(uid) end
end)

-- ----------------------------------------------------------
--  Comenzile / (/giveitem, /setslots) sunt in  commands.lua .
--  Helperele de care au nevoie se dau prin tabelul global INVENV.
-- ----------------------------------------------------------
INVENV = {
    PH             = PH,
    toInt          = toInt,
    notify         = notify,
    addItem        = addItem,
    saveInv        = saveInv,
    srcOf          = srcOf,
    pushState      = pushState,
    sanitizeHotbar = sanitizeHotbar,
    shrinkTo       = shrinkTo,
    inv            = function() return INV end,
}

-- ----------------------------------------------------------
--  Exports  (toate primesc SQL id = users.id)
-- ----------------------------------------------------------

--- dezechipeaza TOATE hainele si le muta in grid ; ce nu incape -> Post Office.
--- folosit de /resetcharacter (ph_appearance).  @return ok, moved, mailed
exports('UnequipAllToInventory', function(userId)
    userId = tonumber(userId)
    local inv = userId and INV[userId]
    if not inv then return false, 0, 0 end
    inv.equipment = inv.equipment or {}

    local moved, mailed = 0, 0
    for eqKey in pairs(Config.EquipmentSlotIds) do
        local worn = inv.equipment[eqKey]
        if worn then
            inv.equipment[eqKey] = nil
            local free = firstFreeSlot(inv)
            if free then
                inv.items[free] = { name = worn.name, count = 1, meta = worn.meta }
                moved = moved + 1
            else
                pcall(function()
                    exports['ph_postoffice']:Deposit(userId,
                        { name = worn.name, count = 1, meta = worn.meta }, 'character reset')
                end)
                mailed = mailed + 1
            end
        end
    end

    if moved + mailed > 0 then
        saveInv(userId)
        local s = srcOf(userId)
        if s then applyPedEquipment(s); pushState(s) end
    end
    return true, moved, mailed
end)

exports('GiveItem', function(userId, name, count, meta)
    if not INV[userId] then return false end
    local ok = addItem(userId, name, count or 1, meta)
    if ok then
        saveInv(userId)
        local s = srcOf(userId); if s then pushState(s) end
    end
    return ok
end)

exports('RemoveItem', function(userId, name, count)
    if not INV[userId] then return false end
    local ok = removeItem(userId, name, count or 1)
    if ok then
        saveInv(userId)
        local s = srcOf(userId); if s then pushState(s) end
    end
    return ok
end)

exports('HasItem', function(userId, name, count)
    return countItem(userId, name) >= (count or 1)
end)

exports('GetItemCount', function(userId, name)
    return countItem(userId, name)
end)

exports('GetInventory', function(userId)
    return INV[userId]
end)

--- definitiile de iteme (Config.Items) - pentru alte resurse (ph_postoffice etc.)
exports('GetItems', function() return Config.Items end)
exports('GetItemDef', function(name) return Config.Items[name] end)

--- helper pentru alte resurse: SQL id -> inventarul live (sau nil)
exports('GetInventoryByUserId', function(userId)
    return INV[userId]
end)
