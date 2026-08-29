# Purple Havoc — FiveM RPG Server

Server GTA V **RPG** (progresie, nivele, skill-uri) construit de la zero, cu framework propriu.
Fără ESX / QBox / QBCore.

## Stadiu actual (v1)

- `ph-core` — framework de bază:
  - conectare cu verificare de licență (deferrals)
  - **NUI login / register** (username + email + parolă; parole hash-uite cu `scrypt`)
  - **creare de personaj**: data nașterii, gen, înălțime (username-ul e și numele în joc, stil SAMP)
  - încărcare / salvare în MySQL + auto-save la 5 min, la deconectare și la oprirea resursei
  - cameră cinematografică peste ecranul de autentificare
  - exports pentru viitoarele resurse: `GetPlayer`, `GetCharacter`, `GetUserId`, `IsPlayerLoaded`
  - event server `ph-core:playerLoaded(src, character)` și event client `ph-core:client:playerLoaded(character)`

### Structura bazei de date (stil SAMP / RageMP)

Un **singur tabel `users`** (cont = personaj, un personaj / cont, legat de `license`):

| coloană | rol |
|---|---|
| `id`, `username`, `email`, `password`, `license` | cont |
| `dob`, `gender`, `height`, `appearance` | personaj (`dob IS NULL` = personaj necreat) |
| `level`, `rp`, `money`, `bank`, `premiumpoints`, `playtime` | progresie |
| `created_at`, `last_login` | evidență |

> `rp` = fostul `xp` (respect points). Ultima poziție nu se salvează încă — spawn fix în Legion Square.

## Ce trebuie să faci tu (o singură dată)

1. **Server artifacts FiveM** — descarcă build-ul recent (Windows) și pune `server.cfg` lângă executabil (sau ajustează căile).
2. **Cheie de licență** — ia una de pe <https://keymaster.fivem.net/> și pune-o la `sv_licenseKey` în `server.cfg`.
3. **MySQL / MariaDB** — instalează local (XAMPP, MariaDB, HeidiSQL etc.).
4. **oxmysql** — descarcă release-ul de la <https://github.com/overextended/oxmysql/releases>, dezarhivează în
   `resources/[core]/oxmysql` (sau oriunde, dar numele resursei trebuie să rămână `oxmysql`).
5. **Baza de date**:
   - creează baza `purple_havoc`
   - importă `sql/001_init.sql` (opțional — `ph-core` creează tabelul `users` automat la pornire dacă lipsește)
6. **Connection string** — în `server.cfg`:
   ```
   set mysql_connection_string "mysql://USER:PAROLA@localhost/purple_havoc?charset=utf8mb4"
   ```
7. **Acces admin** (opțional, pentru `/phresetchar`) — decomentează și completează în `server.cfg`:
   ```
   add_principal identifier.fivem:XXXXXXX group.admin
   ```
   (ID-ul tău FiveM îl vezi cu `status` în consola serverului după ce te conectezi.)

## Pornire

```
FXServer.exe +exec server.cfg
```

sau prin txAdmin (recomandat pentru dev).

## Structură

```
Purple Havoc/
├─ server.cfg
├─ sql/
│  └─ 001_init.sql
└─ resources/
   └─ [core]/
      ├─ oxmysql/                <- îl pui tu
      └─ ph-core/
         ├─ fxmanifest.lua
         ├─ config/config.lua    <- coordonate spawn, cameră, reguli username/parolă
         ├─ shared/utils.lua
         ├─ server/
         │  ├─ crypto.js          <- hashing parole (fără dependințe npm)
         │  ├─ database.lua       <- creează tabelele
         │  ├─ account.lua        <- register / login
         │  ├─ character.lua      <- creare / load / save personaj
         │  └─ main.lua           <- conectare, exports, comenzi
         ├─ client/
         │  ├─ main.lua           <- boot, cameră, freeze
         │  ├─ auth.lua           <- punte NUI <-> server pentru auth
         │  └─ character.lua      <- spawn personaj
         └─ html/                 <- NUI (login / register / creare personaj)
```

## Flux

```
conectare → NUI loading
   ├─ licență fără cont  → ecran REGISTER → creare cont → ecran CREARE PERSONAJ
   └─ licență cu cont    → ecran LOGIN → (fără personaj) → CREARE PERSONAJ
                                       → (cu personaj)   → spawn în joc
```

## Comenzi

| Comandă        | Cine           | Efect                                             |
|----------------|----------------|---------------------------------------------------|
| `/phresetchar` | admin (ace `ph.admin`) sau consolă | resetează datele de personaj (`dob=NULL`, level/rp/bani) și te dă afară — pentru re-testarea creării |

## Următorii pași propuși (v2)

- Editor de aspect al personajului (față, păr, haine) + preview 3D live în NUI (`appearance` există deja)
- Sistem de **RP & leveling** (coloanele `level` / `rp` există deja)
- HUD RPG (bară RP, nivel, bani)
- Salvarea ultimei poziții (adăugăm `pos_x/pos_y/pos_z/pos_a` în `users`)
- Clase / arhetipuri și skill trees
