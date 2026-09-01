-- ==========================================================
--  ph_vehicles / shared
--  Indexeaza VanillaVehicles (data/vanilla.lua) + CustomVehicles (data/custom.lua)
--  si expune exports identice pe server si pe client:
--
--    exports['ph_vehicles']:List()            -> { car={{model,label}...}, heli=..., boat=... }  (vanilla + custom)
--    exports['ph_vehicles']:Flat()            -> { { model, label, category, custom, price }, ... }
--    exports['ph_vehicles']:Has(model)        -> bool  (e in catalog, vanilla SAU custom?)
--    exports['ph_vehicles']:Label(model)      -> string
--    exports['ph_vehicles']:Category(model)   -> 'car' | 'heli' | 'boat'
--    exports['ph_vehicles']:IsCustom(model)   -> bool  (e vehicul custom?)
--    exports['ph_vehicles']:Price(model)      -> number (0 daca nu are pret)
--    exports['ph_vehicles']:Count()           -> numarul total de intrari
-- ==========================================================
local VANILLA = VanillaVehicles or { car = {}, heli = {}, boat = {} }
local CUSTOM  = CustomVehicles  or { car = {}, heli = {}, boat = {} }

local BY_MODEL = {}     -- [model] = { label, category, custom, price }
local FLAT = {}
local MERGED = { car = {}, heli = {}, boat = {} }

local function index(raw, isCustom)
    for cat, arr in pairs(raw) do
        if type(arr) == 'table' then
            for _, v in ipairs(arr) do
                local m = tostring(v.model or ''):lower()
                if m ~= '' then
                    local entry = {
                        label    = v.label or m,
                        category = cat,
                        custom   = isCustom or nil,
                        price    = tonumber(v.price) or 0,
                    }
                    BY_MODEL[m] = entry
                    FLAT[#FLAT + 1] = {
                        model = m, label = entry.label, category = cat,
                        custom = entry.custom, price = entry.price,
                    }
                    MERGED[cat] = MERGED[cat] or {}
                    MERGED[cat][#MERGED[cat] + 1] = { model = m, label = entry.label }
                end
            end
        end
    end
end

index(VANILLA, false)
index(CUSTOM,  true)      -- custom-urile pot suprascrie o intrare vanilla cu acelasi model

table.sort(FLAT, function(a, b) return a.model < b.model end)
for _, arr in pairs(MERGED) do
    table.sort(arr, function(a, b) return a.model < b.model end)
end

exports('List',  function() return MERGED end)
exports('Flat',  function() return FLAT end)
exports('Count', function() return #FLAT end)

exports('Has', function(model)
    return BY_MODEL[tostring(model or ''):lower()] ~= nil
end)

exports('Label', function(model)
    local e = BY_MODEL[tostring(model or ''):lower()]
    return e and e.label or tostring(model or '')
end)

exports('Category', function(model)
    local e = BY_MODEL[tostring(model or ''):lower()]
    return e and e.category or 'car'
end)

exports('IsCustom', function(model)
    local e = BY_MODEL[tostring(model or ''):lower()]
    return (e and e.custom) == true
end)

exports('Price', function(model)
    local e = BY_MODEL[tostring(model or ''):lower()]
    return e and e.price or 0
end)
