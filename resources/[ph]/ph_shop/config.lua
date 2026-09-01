-- ==========================================================
--  ph_shop / config  (shared)
--  Magazin cu Premium Points (users.premiumpoints).
-- ==========================================================
Config = Config or {}

-- Cate zile de abonament acorda un bilet la folosire (din inventar).
Config.SubTicketDays = 30

-- Numar de telefon (Phone Number)
Config.Phone = { min = 3, max = 10 }   -- caractere; doar A-Z si 0-9

-- Creare clan
Config.Clan = { nameMin = 3, nameMax = 25, tagMax = 5 }

-- ----------------------------------------------------------
--  Catalog.  kind:
--    'item'    -> da un item de inventar (grant.item)
--    'instant' -> efect direct (grant.vslot = +sloturi de vehicul)
--    'form'    -> deschide un formular (form = 'phone' | 'clan'); se taxeaza la confirmare
--  Ordinea din tabel = ordinea in meniu.
-- ----------------------------------------------------------
Config.Items = {
    {
        key = 'gold_ticket', cost = 100, kind = 'item',
        label = 'Gold Subscription Ticket',
        desc  = '30 days of Gold when used from your inventory.',
        grant = { item = 'sub_ticket_gold' },
    },
    {
        key = 'platinum_ticket', cost = 250, kind = 'item',
        label = 'Platinum Subscription Ticket',
        desc  = '30 days of Platinum when used from your inventory.',
        grant = { item = 'sub_ticket_platinum' },
    },
    {
        key = 'vehicle_slot', cost = 50, kind = 'instant',
        label = 'Vehicle Slot',
        desc  = 'Permanently adds +1 personal vehicle slot.',
        grant = { vslot = 1 },
    },
    {
        key = 'phone_number', cost = 75, kind = 'form', form = 'phone',
        label = 'Phone Number',
        desc  = 'Reserve a 3-10 character handle (A-Z, 0-9). Charged when you confirm.',
    },
    {
        key = 'create_clan', cost = 500, kind = 'form', form = 'clan',
        label = 'Create Clan (30 Days)',
        desc  = 'Files a clan request for staff review. Rejected requests are fully refunded.',
    },
}
