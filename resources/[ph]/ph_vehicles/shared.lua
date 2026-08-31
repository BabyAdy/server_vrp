-- ==========================================================
--  ph_vehicles / shared
--  Indexeaza VanillaVehicles (din data/vanilla.lua) si expune exports
--  identice pe server si pe client:
--
--    exports['ph_vehicles']:List()            -> { car={{model,label}...}, heli=..., boat=... }
--    exports['ph_vehicles']:Flat()            -> { { model, label, category }, ... }
--    exports['ph_vehicles']:Has(model)        -> bool  (e in lista vanilla?)
--    exports['ph_vehicles']:Label(model)      -> string
--    exports['ph_vehicles']:Category(model)   -> 'car' | 'heli' | 'boat'
-- ==========================================================
local RAW = VanillaVehicles or { car = {}, heli = {}, boat = {} }

local BY_MODEL = {}     -- [model] = { label, category }
local FLAT = {}

for cat, arr in pairs(RAW) do
    if type(arr) == 'table' then
        for _, v in ipairs(arr) do
            local m = tostring(v.model or ''):lower()
            if m ~= '' then
                BY_MODEL[m] = { label = v.label or m, category = cat }
                FLAT[#FLAT + 1] = { model = m, label = v.label or m, category = cat }
            end
        end
    end
end

table.sort(FLAT, function(a, b) return a.model < b.model end)

exports('List',  function() return RAW end)
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
