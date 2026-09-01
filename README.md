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
   ├─ licență fără cont  → ecran REGISTER → creare cont → CREARE PERSONAJ (dob/gen/înălțime)
   └─ licență cu cont    → ecran LOGIN → (fără personaj) → CREARE PERSONAJ
                                       → (fără aspect)   → CHARACTER CREATOR (ph_appearance)
                                       → (cu personaj)   → spawn în joc (aspect + haine auto)
```

## Comenzi

| Comandă        | Cine           | Efect                                             |
|----------------|----------------|---------------------------------------------------|
| `/phresetchar` | admin (ace `ph.admin`) sau consolă | resetează datele de personaj (`dob=NULL`, level/rp/bani) și te dă afară — pentru re-testarea creării |
| `/setstaff <id> <grad>` | ace `ph.admin` / consolă | setează gradul de staff (persistent). Ex: `setstaff 1 owner` |
| `/staffmenu`   | staff ≥ `trialhelper` | deschide meniul de staff |
| `/ticket [categorie] <mesaj>` | orice jucător | creează un tichet (categorii: general, bug, report, question, refund) |
| `I`            | orice jucător | deschide inventarul |
| `/giveitem <id> <item> [n]` | ace `ph.admin` / consolă | dă iteme unui jucător |
| `/setslots <id> <n>` | ace `ph.admin` / consolă | mărește sloturile de inventar (default 100) — se face prin ticket |
| `/stats` | orice jucător | își vede **doar** propriile date în chat (Info / Economy / Faction / Clan / Admin / Helper / Leader — rândurile condiționale apar doar dacă e cazul) |
| `/givemoney <id> <amount>` | staff ≥ `manager` | dă (sau `-ia`, plafonat la 0) cash; merge și offline. Anunț la staff ≥ `trialadmin`: `Staff: [grad] X gave Y [Id: id] the amount of N Money!` |
| `/givebmoney <id> <amount>` | staff ≥ `manager` | idem pentru `bank` |
| `/givepp <id> <amount>` | staff ≥ `manager` | idem pentru `premiumpoints` |
| `/editcharacter <id>` | staff ≥ `manager` | editor de aspect pe ped-ul tău, plecând de la aspectul țintei (switch M/F, **Save** = live, **Save Character** = preset) |
| `/resetcharacter <id>` | staff ≥ `manager` | bagă jucătorul (online) în creatorul de caracter; hainele purtate → inventar (ce nu încape → Post Office) |

### Unde stau comenzile (`/`)

Fiecare resursă își ține **toate** comenzile `/` într-un singur fișier dedicat,
încărcat **după** `server.lua`/`client.lua` (folosește helperele lui printr-un tabel
global expus de resursă, ex. `SMENV`, `SUBENV`, `INVENV`, `PHW_*`):

| Resursă | Fișier | Comenzi |
|---|---|---|
| `ph-core` | `server/commands.lua` | `/phresetchar`, `/setstaff`, `/removestaff`, `/getbeta`, `/staffmenu`, `/stats` |
| `ph_appearance` | `appearance_cmd.lua` | `/editcharacter` [sqlId], `/resetcharacter` [sqlId] (staff ≥ manager) |
| `staff_menu` | `staff_cmd.lua` | `/ticket`, `/heal`, `/revive`, `/dv`, `/fix`, `/flip`, `/maxperf`, `/spawncar`, `/setvw`, `/doorinfo`, `/dvall`, `/givemoney`, `/givebmoney`, `/givepp` |
| `ph_factions` | `faction_cmd.lua` | `/factionmenu` + `/devfactionmenu` (client), `/duty`, `/fcreate`, `/fsetleader`, `/fseedvanilla`, `/fdelete`, `/setleader`, `/setfmember`, `/makeleader`, `/changerankname`, `/auninvite`+`/uninvite`, `/removeleader` |
| `ph_world` | `commands.lua` | `/time`, `/weather` |
| `ph_chat` | `commands.lua` | `/pc` |
| `ph_subscriptions` | `commands.lua` | `/subadd`, `/subset`, `/subclear`, `/subcheck`, `/debugsubs` |
| `ph_inventory` | `commands.lua` | `/giveitem`, `/setslots` |
| `ph_postoffice` | `commands.lua` | `/po`, `/postoffice` |
| `ph_hud` | `commands.lua` | `/hudtest` |
| `ph_clothing` | `commands.lua` | `/tryon` |

Excepție: legările de taste (`RegisterKeyMapping` + `+`/`-` stubs: noclip, inventar,
deschidere chat) rămân lângă logica lor de UI în `client.lua`.

## Inventar (`resources/[ph]/ph_inventory`)

Layout ca în screenshot: **echipament** stânga-sus (haine/accesorii care apar pe caracter),
**FAST SLOTS** 1–5 stânga-jos (pui o armă pe slot 1 → apeși `1` → o scoți în mână),
grid central cu greutate `current/max`, **NEARBY ITEMS** + **DROP ITEMS** dreapta.

- sloturi default **100** (coloana `users.inv_slots`, măresc prin `/setslots` = ticket); greutate max `Config.MaxWeight`
- click-dreapta pe item → **use / split / drop**
- **drop**: itemele stau **10 minute** pe jos, le ridică orice jucător din apropiere (`E`)
- **arme**: tragi stiva de gloanțe **peste armă** ca s-o încarci (max **500**, tipul de muniție trebuie să se potrivească); fiecare foc scade gloanțele încărcate **și durabilitatea**; durabilitate 0 = arma nu se mai poate echipa; ții cursorul ~2s pe armă → tooltip cu gloanțe/durabilitate
- itemele din `Config.Items` sunt exemple — le înlocuiești cu ale tale
- SQL: [sql/003_inventory.sql](sql/003_inventory.sql) (coloane `users.inventory` / `users.inv_slots`) sau auto-creat la pornire
- roata de arme nativă GTA e dezactivată — armele ies doar din fast slots
- `Drop` folosește poziția pe server → **OneSync pornit**

### Icoane pentru iteme

Pui fișiere PNG în `resources/[ph]/ph_inventory/html/img/`, denumite **exact ca cheia itemului**
din `Config.Items` (ex: `weapon_pistol.png`, `water.png`, `ammo_pistol.png`). Se încarcă automat,
nu configurezi nimic. Recomandat 96×96 sau 128×128, fundal transparent.

- alt nume de fișier? pune-l pe item: `water = { ..., image = 'apa.png' }`
- lipsă imagine ⇒ apare un badge cu primele 3 litere (comportamentul de acum)
- formate: `.png .webp .jpg .svg`
- după ce adaugi imagini: `restart ph_inventory`

## Staff menu (`resources/[ph]/staff_menu`)

Meniu mov, 5 tab-uri. Fiecare acțiune e re-verificată pe server după `Config.Perms` din
[staff_menu/config.lua](resources/[ph]/staff_menu/config.lua) (acțiune → grad minim). Nu poți acționa
asupra unui staff de rang egal/superior.

- **Staff** — Goto / Bring / Spectate / Freeze / Revive / Heal / Warn / Kick / Ban / Unban / Announce (filtrate după grad; țintă aleasă din *Players*)
- **Tickets** — ticketele deschise; Accept / Close
- **Active Tickets** — ticketele acceptate de tine; Goto / Reply / Close
- **Players** — listă live, căutare după SQL ID / Username, Select → țintă pentru tab-ul Staff
- **Developer** (grad ≥ `manager`) — set staff, restart resursă, TP la coordonate, info server

SQL: importă [sql/002_staff.sql](sql/002_staff.sql) (tabele `tickets`, `ticket_replies`, `staff_logs`,
`bans`, `warns`) — sau lasă `staff_menu` să le creeze la pornire. Ban-urile se verifică la conectare
(`bans.expires_at` = unix secunde, `NULL` = permanent).

> `Goto` / `Bring` / `Spectate` citesc poziția țintei pe server → **necesită OneSync pornit** (txAdmin → Settings → FXServer).

## Factions (`resources/[ph]/ph_factions`)

Două meniuri NUI separate, fiecare cu comanda ei:

### `/factionmenu` — pentru membri (`faction_rank >= 6`, adică Co-Leader / Leader)

- **Members** — tabel `Avatar | Username | Days | Rank | Badge` + acțiuni.
  - *Avatar* = monogramă (inițiala username-ului, culoare din hash-ul numelui).
  - *Days* = zile (2 zecimale) de la `users.faction_join`.
  - *Rank* = numele rank-ului + numărul, ex. `Chief (7)`.
  - *Badge* = un singur badge / rând, prioritate **Leader > Co-Leader > Supervisor > Tester** (culori/iconuri în `Config.Badges`).
  - Butoane: `Rank +/-` (**doar Leader, rank 7**), `Promote/Remove Tester`, `Promote/Remove Supervisor`, `Give/Remove Warn` (toate **rank ≥ 6**). Ținta trebuie să fie **online**.
- **Logs** — ultimele `Config.LogLimit` (100) rânduri din `faction_logs` pentru factiunea proprie.
- Recrutarea **nu** e în meniu — urmează un `/invite [sqlId]` + accept din panel. Kick / transfer de leadership se fac din comenzile de staff (`/auninvite`, `/setleader`).

### `/devfactionmenu` — pentru staff (`staff >= Config.DevGrade`, implicit `developer`)

- **Create Faction** — `Name` + `Short Name` (auto din primele 3 litere dacă e gol). ID-ul e AUTO_INCREMENT.
- **Edit Faction** — se alege factiunea dintr-un dropdown:
  - *Add Vehicle* (`Model Name | Display Name | Rank`, pe categorie car/heli/boat) și *Remove Faction Vehicle* (listă cu `×` + input de rank).
  - *Set HQ Exterior* / *Set HQ Interior* (interiorul salvează și `hq_vw` = routing bucket-ul curent) / *Create Vehicle|Heli|Boat Garage* — toate la poziția curentă a utilizatorului.
  - *Ranks* — cele 7 denumiri (Rank 1..5, Co-Leader, Leader) + Save.
  - *Leadership* — Set Leader / Set Manager după `sqlId`.
  - *Danger zone* — Seed vanilla vehicles (min rank) + Delete faction.

SQL: [sql/007_factions.sql](sql/007_factions.sql) (`factions`, `faction_vehicles`, `faction_logs` + coloane pe `users`) — sau lăsate să se creeze la pornire.

## Conținut custom (mașini & haine)

Fișierele streamate stau în `resources/[stream]/`. Cataloagele / logica stau în `[ph]`.

### Mașini custom — `resources/[stream]/ph_cars`

1. Modelele în `stream/<nume>/` (`.yft`, `_hi.yft`, `.ytd`, `.ycd`).
2. Meta-urile în `data/<nume>/` (`vehicles.meta`, `carvariations.meta`, `carcols.meta`,
   `handling.meta`, opțional `vehiclelayouts.meta`). Manifestul are glob `data/**/*.meta`,
   deci nu-l editezi.
3. Adaugi intrarea în catalog: `resources/[ph]/ph_vehicles/data/custom.lua`
   → `{ model = 'nume', label = 'Nume Frumos', category = 'car', price = 0 }`.
4. `restart ph_cars ; restart ph_vehicles`.

`exports['ph_vehicles']` indexează acum vanilla **+** custom; în plus:
`:IsCustom(model)` și `:Price(model)`. `/spawncar <nume>` (staff ≥ `generaladmin`) le spawnează
și le marchează mission entity, deci nu le șterge `ph_world`.

### Haine custom — `resources/[stream]/ph_clothing`

- **Replace** (imediat, fără meta): pui `.ydd` / `.ytd` cu numele exact din joc în `stream/`.
- **Addon** (sloturi noi): fișiere `<pedModel>_<colecție>^<comp>_<idx>_...` în `stream/` +
  un `.meta` `SShopPedApparel` în `meta/` declarat cu
  `data_file 'SHOP_PED_APPAREL_META_FILE' 'meta/<colecție>.meta'` în `fxmanifest.lua`.
- Test: `/tryon component|prop <id> <drawable> [texture]`, `/tryon reset`, `/tryon info`
  (staff ≥ `Config.TryOnPerm`, implicit `manager`). `info` scrie în consola F8 câte
  drawable-uri are fiecare slot — așa afli indexul unei haine addon nou adăugate.

**Exemplu montat: colecția `mp_f_freemode_01_staff`** (hanorace staff F, `jbib` / slot `jacket`):
un model (`jbib_002`) cu 3 texturi. Iteme în `ph_inventory` (`type = 'clothing'`, `slot = 'jacket'`,
`drawable = STAFF_F_JBIB_DRAWABLE` din `ph_inventory/config.lua`, `texture` 0/1/2):

| Item | Textură | Grad |
|---|---|---|
| `staff_f_owner_jacket` | 0 (`_a`) | Owner |
| `staff_f_developer_jacket` | 1 (`_b`) | Developer |
| `staff_f_manager_jacket` | 2 (`_c`) | Manager |

`/giveitem <id> staff_f_owner_jacket 1` etc. merg direct (sunt în `Config.Items`); se echipează
din inventar pe slotul *Geacă*. **Pași după `restart ph_clothing`:** `/tryon info` → vezi noul
număr de variații pentru component 11; `/tryon component 11 <N> <0|1|2>` până apare hanoracul;
pui `<N>` în `STAFF_F_JBIB_DRAWABLE`. Se aplică doar pe `mp_f_freemode_01` (femeie).

> `ph_cars` / `ph_clothing` trebuie `ensure`-uite **înainte** ca jucătorii să se conecteze
> (meta-urile se înregistrează la load-ul jocului) — deja adăugate în `server.cfg`.

## Character Creator (`resources/[ph]/ph_appearance`)

Editor de aspect freemode (**fără haine**). Randarea e ped-ul din joc în spatele unui
panel NUI; camera orbitează (drag = rotire, scroll = zoom, butoane Head/Body/Legs/Reset).

### Haine = iteme de inventar

`ph_appearance` aplică doar aspectul + un **base „dezbrăcat"** (`Config.NakedOutfit` / gen),
care devine reperul „fără haine de inventar" pe care îl captează `ph_inventory`. Nu se pun
haine de la server:

- La **prima creare**, jucătorul primește `Config.StarterClothing` (`clothing_jacket` +
  `clothing_pants` + `clothing_shoes`) **ca iteme în inventar** (nu echipate) și le pune el
  din inventar pe sloturile de echipament 5001–5011.
- Dacă avea haine puse de server, `NakedOutfit` le elimină (torso/undershirt/top/pantaloni
  → lenjerie); dacă nu are nimic echipat pe sloturile de haine → apare dezbrăcat.
- `/editcharacter → Save` re-aplică `NakedOutfit` apoi cere lui `ph_inventory` să re-echipeze
  (`ph_appearance:cl:reapplyEquipment`).

### Flux de creare

- După ecranul de dob/gen/înălțime din `ph-core`, dacă `users.appearance IS NULL`, `ph-core`
  predă controlul lui `ph_appearance` (`ph-core:hideAuthUI` + `ph_appearance:cl:startCreator`).
  La *Enter game* aspectul se scrie în `users.appearance` (+ `users.gender`) și
  `ph_appearance:createDone` re-declanșează spawn-ul.
- **Secțiuni**: Model (M/F), Heritage (mamă/tată 0–45 + resemblance & skin blend),
  Face (cele 20 de face-features grupate), Hair (stil + culoare + highlight),
  Brows, Beard (stil + opacitate + culoare), Eyes (culoare), Skin
  (ageing / complexion / sun damage / blemishes / moles), Makeup (doar F: makeup / blush / lipstick).

### `/editcharacter [sqlId]` — `staff >= Config.EditCharacterGrade` (implicit `manager`)

Deschide editorul pe **ped-ul tău**, pornind de la aspectul țintei (funcționează și offline).
Switch M/F în editor. Două butoane:

- **Save** — scrie aspectul **live** al țintei (`users.appearance` + `users.gender`); dacă
  ținta e online i se aplică pe loc și `ph-core` își sincronizează cache-ul.
- **Save Character** — salvează un **preset** în `character_templates (user_id, gender)`.
  La un `/editcharacter` următor, când selectezi acel gen, un banner îți oferă *Load template*
  (sau *Start fresh*).

### `/resetcharacter [sqlId]` — `staff >= Config.EditCharacterGrade` (implicit `manager`)

Bagă jucătorul **online** în creatorul de caracter (`appearance` → NULL), îi trece hainele
purtate din echipament în grid prin `exports['ph_inventory']:UnequipAllToInventory` (ce nu
încape → Post Office). La *Enter game* re-face spawn-ul (fără set de start — deja are haine).

SQL: [sql/008_appearance.sql](sql/008_appearance.sql) (`character_templates`) — sau lăsat să se creeze la pornire.

## /stats & clanuri

`/stats` (ph-core) trimite în chat, **doar** jucătorului care rulează, propriile date:

```
<username> - Stats
Info: [ID: x] | Level: x | RP: x/<necesari next level> | Hours: x.xx | Warns: x/3 |
Economy: [Money: x$] | [Bank Money: x$] | [PP: x] |
Faction: <f_name> | Rank: <nume (nr)> | Days: x.xx | FW: x/3 |     (doar dacă faction ≠ 0)
Clan: <c_name> | Rank: <nume (nr)> | Days: x.xx | CW: x/3 |        (doar dacă clan ≠ 0)
Admin: [VW: x] | [Staff: grad] | [SW: x/3] |                       (doar dacă staff ≥ trialadmin)
Helper: [Staff: grad] | [SW: x/3] |                               (doar dacă staff ∈ {trialhelper,helper,headhelper})
Leader: [LW: x/3]                                                  (doar dacă faction_rank == 7)
```

- Money e formatat cu `.` la mii (`1.234.567$`). RP `x/y`: `y` din `Config.LevelUp` /
  `Config.LevelUpFormula` din ph-core (seed: level 2 = 1.000$ + 3 RP; `money` folosit de
  viitorul `/buylevel`).
- Warn-uri (toate `/3`): `users.warns` (player, incrementat de `/warn` din staff_menu),
  `faction_warns` (FW), `clan_warns` (CW), `staff_warns` (SW), `leader_warns` (LW).
- **Clanuri**: doar schema (`clans` + coloanele `clan*` pe `users`) — sistemul propriu-zis
  de clanuri vine separat; deocamdată `/stats` doar citește.

SQL: [sql/009_stats_clans.sql](sql/009_stats_clans.sql) — sau lăsat să se creeze la pornire
(coloanele în `ph-core/server/database.lua` + `ph_chat` pentru `chat_scale`).

## Chat — opțiuni

Panoul de Opțiuni (⚙ din bara de scris) are **Linii vizibile** (5–20) și **Mărime chat**
(70–140%, pas 10). Ambele se persistă în `users.chat_lines` / `users.chat_scale` prin
`ph_chat:setOption` și se re-trimit la conectare via `ph_chat:options`. Resize-ul scalează
toată fereastra (`#chat { transform: scale(var(--chat-scale)) }`).
`ph_appearance` e `ensure`-uit imediat după `ph-core` în `server.cfg`.

## Următorii pași propuși (v2)

- Preview 3D live în NUI (acum se folosește ped-ul din joc în spatele panelului)
- Sistem de **RP & leveling** (coloanele `level` / `rp` există deja)
- HUD RPG (bară RP, nivel, bani)
- Salvarea ultimei poziții (adăugăm `pos_x/pos_y/pos_z/pos_a` în `users`)
- Clase / arhetipuri și skill trees
