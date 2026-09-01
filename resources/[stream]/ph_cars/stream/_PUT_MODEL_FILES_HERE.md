# ph_cars / stream

Drop the model files for each custom vehicle here, ideally one subfolder per vehicle:

```
stream/
  adder2/
    adder2.yft
    adder2_hi.yft
    adder2.ytd
    adder2.ycd            (optional - animations/doors)
    adder2+hi.ytd         (optional)
  vagner/
    vagner.yft
    ...
```

FiveM scans every folder named `stream` recursively, so the subfolder names are only
for your own tidiness — the spawn name comes from inside `vehicles.meta`, not the folder.

Matching `.meta` files go in `../data/<vehicle>/`.
After adding files: `restart ph_cars`.
