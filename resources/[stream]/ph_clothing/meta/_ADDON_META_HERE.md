# ph_clothing / meta  (Method B - ADDON only)

Only needed if you add **new** clothing slots instead of replacing vanilla ones.

Layout expected by the commented `data_file` lines in `fxmanifest.lua`:

```
meta/
  mp_m_freemode_01/
    shop_clothing.meta        -- SHOP_PED_APPAREL_META_FILE
    mp_m_freemode_01.meta     -- (some packs also need this one)
  mp_f_freemode_01/
    shop_clothing.meta
    mp_f_freemode_01.meta
```

Steps:
1. Drop the pack's `.meta` files in the folders above.
2. Drop the pack's `.ydd` / `.ytd` in `../stream/<pedmodel>/`.
3. Uncomment the `files { ... }` block and the matching `data_file` lines in `fxmanifest.lua`.
4. `restart ph_clothing`.
5. In-game: `/tryon info` to see the new drawable count, then
   `/tryon component 11 <newIndex> 0` to preview.

If you only ever use Method A (replace), this whole folder can stay empty / be deleted.
