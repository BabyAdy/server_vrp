Config = Config or {}

-- ==========================================================
--  ph_appearance / config
-- ==========================================================

-- Grad minim pentru /editcharacter
Config.EditCharacterGrade = 'manager'

-- Modelele freemode folosite (index = users.gender)
Config.PedModels = {
    [0] = 'mp_m_freemode_01',   -- Male
    [1] = 'mp_f_freemode_01',   -- Female
}

-- ----------------------------------------------------------
--  Aspectul "DEZBRACAT" (baza fara haine).  Se aplica dupa aspect, ca sa
--  fie reperul de "fara haine de inventar" pe care il capteaza ph_inventory.
--  Hainele NU se pun de server - jucatorul primeste iteme (Config.StarterClothing)
--  si le echipeaza singur din inventar (sloturile 5001..5011).
--
--  components: [gtaComponentId] = { drawable, texture }
--    1  masca   3  torso/brate   4  pantaloni/lenjerie   5  rucsac
--    6  incaltaminte   7  accesoriu   8  tricou/underlayer   9 vesta   11 top (jbib)
--  props: [gtaPropId] = { drawable, texture }   ( -1 / lipsa = fara )
--
--  NOTA: valorile de mai jos sunt cele "clasice" de freemode gol pe base game
--  (fara DLC).  Verifica-le in joc si ajusteaza daca versiunea difera.
-- ----------------------------------------------------------
Config.NakedOutfit = {
    [0] = { -- Male
        components = {
            [1]  = { 0,  0 },   -- fara masca
            [3]  = { 15, 0 },   -- torso gol
            [4]  = { 21, 0 },   -- boxeri
            [5]  = { 0,  0 },   -- fara rucsac
            [6]  = { 34, 0 },   -- descult
            [7]  = { 0,  0 },   -- fara accesoriu
            [8]  = { 15, 0 },   -- fara underlayer
            [9]  = { 0,  0 },   -- fara vesta
            [11] = { 15, 0 },   -- fara top
        },
        props = { [0] = { -1 }, [1] = { -1 }, [2] = { -1 }, [6] = { -1 }, [7] = { -1 } },
    },
    [1] = { -- Female
        components = {
            [1]  = { 0,  0 },
            [3]  = { 15, 0 },   -- torso gol
            [4]  = { 15, 0 },   -- lenjerie
            [5]  = { 0,  0 },
            [6]  = { 35, 0 },   -- desculta
            [7]  = { 0,  0 },
            [8]  = { 15, 0 },   -- sutien de baza
            [9]  = { 0,  0 },
            [11] = { 15, 0 },   -- fara top
        },
        props = { [0] = { -1 }, [1] = { -1 }, [2] = { -1 }, [6] = { -1 }, [7] = { -1 } },
    },
}

-- ----------------------------------------------------------
--  ASCUNDERE REGIUNI DE CORP  (creator + /editcharacter -> tab "Body")
--
--  Fiecare regiune (cheile din Appearance.BODY_PARTS) = lista de componente GTA
--  care se seteaza pe un drawable "invizibil" cand jucatorul o ascunde.
--    { comp = <id GTA>, drawable = <index>, texture = <index> }
--
--  IMPORTANT: pe base game "invizibil" pentru brate/picioare inseamna de fapt
--  "piele goala" (drawable 15 pe comp 3/4).  Daca stream-uiesti un pack de
--  "invisible clothing", pune AICI drawable-urile lui ca sa dispara complet.
--  La "vizibil" regiunea revine la Config.NakedOutfit[gender].components[comp].
--  Ascunderea se vede DOAR cat timp slotul respectiv nu are haina echipata din
--  inventar (hainele au prioritate).
--
--  comp:  3 = brate/maini (uppr)   4 = picioare (lowr)   6 = talpi (feet)
--         8 = tricou/underlayer (accs)   11 = top/geaca (jbib)
-- ----------------------------------------------------------
Config.BodyHide = {
    [0] = { -- Male
        arms  = { { comp = 3,  drawable = 15, texture = 0 } },
        torso = { { comp = 11, drawable = 15, texture = 0 }, { comp = 8, drawable = 15, texture = 0 } },
        legs  = { { comp = 4,  drawable = 15, texture = 0 } },
        feet  = { { comp = 6,  drawable = 34, texture = 0 } },
    },
    [1] = { -- Female
        arms  = { { comp = 3,  drawable = 15, texture = 0 } },
        torso = { { comp = 11, drawable = 15, texture = 0 }, { comp = 8, drawable = 15, texture = 0 } },
        legs  = { { comp = 4,  drawable = 15, texture = 0 } },
        feet  = { { comp = 6,  drawable = 35, texture = 0 } },
    },
}

-- Iteme de haine primite in inventar imediat dupa creare (nu echipate).
-- Cheile din ph_inventory Config.Items (type = 'clothing').
Config.StarterClothing = { 'clothing_jacket', 'clothing_pants', 'clothing_shoes' }

-- ----------------------------------------------------------
--  Camera creatorului: orbita in jurul ped-ului.
--  radius = distanta; pitch/heading in grade; targetZ = inaltimea punctului tinta
--  fata de picioarele ped-ului.  "focus" = preset-uri (Enter game -> body).
-- ----------------------------------------------------------
Config.Camera = {
    default   = { radius = 1.35, heading = 0.0, pitch = 0.0, targetZ = 0.62 },
    minRadius = 0.65,
    maxRadius = 2.60,
    minPitch  = -28.0,
    maxPitch  = 28.0,
    zoomStep  = 0.12,
    dragSpeed = 0.35,     -- grade / pixel
    focus = {
        head = { radius = 0.72, targetZ = 0.62, pitch = 2.0 },
        body = { radius = 1.90, targetZ = 0.45, pitch = 0.0 },
        legs = { radius = 1.55, targetZ = 0.10, pitch = -12.0 },
    },
    -- pozitia unde e mutat ped-ul in modul creator (loc linistit, interior gol)
    scene = { x = -804.72, y = 175.05, z = 76.74, h = 145.0 },
}

-- palete pentru swatch-urile din UI (numar de culori)
Config.Palettes = {
    hair   = 64,   -- SetPedHairColor / highlight
    makeup = 64,   -- SetPedHeadOverlayColor colorType 2
}

-- cate face-features expunem (0..19 = toate)
Config.FaceFeatureCount = 20
