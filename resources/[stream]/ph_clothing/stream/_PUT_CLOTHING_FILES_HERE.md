# ph_clothing / stream

## Method A - REPLACE (works immediately, no meta)

Drop `.ydd` (model) and `.ytd` (texture) files here using the **exact game file name**.
Format: `<pedmodel>^<slot><index>_<variant>.ydd` and matching `..._<tex>.ytd`.

Common slot prefixes for `mp_m_freemode_01` / `mp_f_freemode_01`:

| Slot            | component id | file prefix        |
|-----------------|--------------|--------------------|
| Tops / jbib     | 11           | `jbib_`            |
| Torso / arms    | 3            | `uppr_`            |
| Legs            | 4            | `lowr_`            |
| Shoes           | 6            | `feet_`            |
| Undershirt      | 8            | `accs_`            |
| Body armor      | 9            | `teef_` (varies)   |
| Hair            | 2            | `hair_`            |
| Hats (prop 0)   | prop 0       | `p_head_`          |
| Glasses (prop 1)| prop 1       | `p_eyes_`          |

Example (replaces male top drawable 15):
```
mp_m_freemode_01^jbib_015_u.ydd
mp_m_freemode_01^jbib_diff_015_a_uni.ytd
```

## Method B - ADDON (new slots, needs meta/)

Put the model/texture files in `stream/<pedmodel>/` and the pack's `.meta` files in
`../meta/<pedmodel>/`, then uncomment the `data_file` lines in `fxmanifest.lua`.
The new drawables get indices **after** the last vanilla one - find them with `/tryon info`.

After any change: `restart ph_clothing`.
