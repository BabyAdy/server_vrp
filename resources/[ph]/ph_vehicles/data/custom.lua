-- ==========================================================
--  ph_vehicles / data / custom.lua
--  Catalogul vehiculelor CUSTOM (spawn name + label + categorie).
--  Fisierele efective (.yft/.ytd/.meta) stau in  resources/[stream]/ph_cars/.
--  Aici e DOAR metadata pentru catalog / lista de spawn / validari.
--
--  category: 'car' | 'heli' | 'boat'   (acelasi set ca la vanilla)
--  price:    optional - pentru un viitor dealership; 0 / nil = fara pret
-- ==========================================================
CustomVehicles = {
    car = {
        { model = 'tempestaes', label = 'Peggasi Tempesta ES', price = 1000000 },
        { model = 'h4rxst2',    label = 'Pfister ST2 RS',      price = 2500000 },
        { model = 'mf1',        label = 'Progem MF 1',         price = 500000 },
        -- { model = 'mf1c',    label = 'Progem MF 1 (Cabrio)', price = 500000 },  -- al 2-lea model din mf1/vehicles.meta
        -- { model = 'adder2',  label = 'Truffade Adder MkII', price = 2500000 },
        -- { model = 'vagner2', label = 'Overflod Vagner GT' },
    },

    heli = {
        -- { model = 'buzzard3', label = 'Buzzard (custom)' },
    },

    boat = {
        -- { model = 'toro3', label = 'Toro (custom)' },
    },
}
