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
