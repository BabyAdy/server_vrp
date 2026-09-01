Config = Config or {}

-- Grad minim pentru /tryon (comanda de test a hainelor)
Config.TryOnPerm = 'manager'

-- Sloturi GTA pe caracter (pentru referinta la /tryon <slot> ...)
--   component <id>:
--     0 face        1 mask         2 hair        3 torso (upper/arms)
--     4 legs        5 backpack     6 shoes       7 accessory (chains/ties)
--     8 undershirt  9 body armor  10 decal      11 top (jbib)
--   prop <id>:
--     0 hat/helmet  1 glasses      2 ears        6 watch       7 bracelet
Config.Components = { 0,1,2,3,4,5,6,7,8,9,10,11 }
Config.Props      = { 0,1,2,6,7 }
