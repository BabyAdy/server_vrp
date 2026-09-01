# ph_cars / data

One subfolder per custom vehicle with its `.meta` files:

```
data/
  adder2/
    vehicles.meta          (required - defines the spawn name / model)
    carvariations.meta      (required - colours, mod kits, plate type)
    carcols.meta            (optional - liveries / colour combos)
    handling.meta           (required - drive model; handling id must match vehicles.meta)
    vehiclelayouts.meta     (optional - seats / enter-exit anims)
```

The `fxmanifest.lua` already globs `data/**/*.meta`, so you never edit the manifest —
just create the folder and drop files in.

After adding files: `restart ph_cars`, then add the catalog entry in
`resources/[ph]/ph_vehicles/data/custom.lua` and `restart ph_vehicles`.

### Common mistakes
- `handlingId` in `handling.meta` must exactly match `<handlingId>` in `vehicles.meta`.
- Two custom cars sharing a `modelName` / `txdName` will conflict - keep them unique.
- Missing `_hi.yft` / `+hi.ytd` is fine (no LOD detail) but the game logs a warning.
