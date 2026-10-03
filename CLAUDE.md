# Fable-SD — "Vira van Jambudvipa"

Sanatana Dharma-geïnspireerde actie-RPG in de geest van Fable. Godot 4.7, GDScript,
Forward Plus, procedurele 3D-wereld. Eigenaar: Gerald (spreek Nederlands).

Oorsprong: op 2026-10-02 gebouwd door Haiku in een Claude cloud-sessie ("Initial Fable-SD
game foundation", één commit). Remote: github.com/gpherai/Fable-SD, branch
`ccr-53906461-obn4mq` (er is geen `main`).

## Staat: het spel start, je kunt rondlopen en vechten (MVP stap 1 en 2 klaar, 2026-10-03)

Fundament (door Haiku in de cloud-sessie): data, wereldgeneratie, quests, audio-synthese,
lokalisatie, shaders. Daarbovenop is nu geschreven (MVP stap 1):

- `scripts/entities/Body.gd`: procedurele modellen voor mens en alle vijandvormen, plus loopanimatie
  (`pose_walk`). Modellen kijken naar -Z.
- `scripts/entities/Player.gd`: CharacterBody3D, beweging t.o.v. de camera, muiscamera op SpringArm3D
  (scrollwiel = zoom), sprint (Shift), rol (Spatie, onkwetsbaar), E = interactie met dichtstbijzijnde
  Interactable/NPC, hp/ojas-regeneratie, `take_damage(amount, source)` als ingang voor vijanden,
  veld `combat_mult`. Esc maakt de muis vrij (tijdelijk, tot het pauzemenu er is); klik pakt hem terug.
  Besturing hangt aan `controls_on`, niet aan de OS-muismodus (anders werkt headless niet).
- `scripts/entities/NPC.gd`: CharacterBody3D met naamlabel, draait naar de speler, volgt als `following`,
  `interact()` stuurt `Events.dialogue_started` (het dialoogvenster zelf bestaat nog niet).
- `scripts/entities/Enemy.gd`: model + collider uit `data/enemies.json`, `take_damage` (def, weak/resist,
  invulnerable, sacred_only), `die()` (roept `world.on_enemy_died`), `leash()`. **Geen AI**: `_think(delta)`
  is de lege haak voor stap 2. Vijanden staan nu stil.
- `scripts/entities/Projectile.gd`: rechte vlucht, sterft op terrein/bereik, meldt contact via
  `cfg.on_hit` (Callable). Schade-afhandeling hoort bij stap 2.
- `scripts/combat/Effects.gd`: tapas- en goudorbs die naar de speler vliegen (`Effects.Orb`).
- `scripts/ui/DebugOverlay.gd`: TIJDELIJKE tekst-overlay (regio, hp, goud, hint, meldingen). Wordt
  vervangen door de echte HUD in stap 3.
- `scripts/Main.gd`: zonder argumenten start hij direct een nieuw spel (`Game.new_game("Vira")`, tijdelijk
  tot het hoofdmenu er is). Testhaken: `--validate`, `--check-scripts`, `--gen-test`, `--smoke`,
  `--shot <regio>`, `--game-shot` (venster, slaat `screenshots/game.png` op).
- `World.gd`: zes typefouten opgelost (expliciete types i.p.v. `:=` op ongetypeerde waarden) en
  `Game.world = self` gezet in `_ready` (dat ontbrak; `Game.set_flag` e.d. hangen eraan).

## MVP stap 2 klaar en afgerond (2026-10-03): gevechten, vijand-AI, drankjes, Dhyana

- `scripts/combat/PlayerCombat.gd` (kind van Player): LMB/J = slag, 3 slagen = Sankhala-combo, vasthouden = Mahaprahara,
  RMB/K = blok (Rakshana), blok vlak voor de treffer = parry (Pratiprahara), F = boog/chakra, Tab/MMB = doel vergrendelen,
  1-6 = siddhi's, **H vasthouden = Dhyana**. `Player.take_damage(amount, source, attacker, kind, from_pos)` loopt via `filter_incoming`/`absorb`.
- `scripts/combat/Siddhis.gd`: alle 20 siddhi's uit `siddhis.json`. `scripts/combat/EnemyAI.gd`: AI van alle 44 vijanden
  (aanvallen als getimede acties met telegraaf; leap, teleport, summons, boss-abilities, rise, pack, nonlethal).
- `Enemy.gd` heeft statuseffecten, hp-balkje, `hit_distance()`, `last_hit_fist`; `Projectile.gd` raakt op capsule, stopt op muren, `on_end`.
- **Dhyana** (state `S.MEDITATE`): houd H vast, de held zit in lotushouding (`Body.pose_sit`), Ojas komt 4x zo snel terug
  (`MEDITATE_OJAS_MULT`), maar hij kan niet lopen, slaan, blokken of siddhi's gebruiken. Een treffer of een rol (Spatie) beeindigt het;
  daarna moet H opnieuw worden ingedrukt (edge-gestuurd). Een blauwe ring pulseert elke 1,6 s.
- **Drankjes**: R = Prana-rasa, T = Ojas-rasa (`Game.quaff`, `best_potion`): kleinste drankje dat het tekort vult, anders het grootste;
  geen drankje verspild bij een volle balk; Vishahara (antigif) wordt nooit door R gedronken. Drinken breekt de pratijna `no_potion` via `Events.item_used`.
- **Mushti Yuddha**: zonder melee-wapen (`Game.unequip("melee")`) vecht de held met vuisten (dmg 3, snelheid 1,6, bereik 1,1). Een kill met
  vuisten geeft `Game.FIST_BALA_MULT` (1,5x) Bala-tapas (opts `fist` -> `Enemy.last_hit_fist` -> `World.on_enemy_died`).
- **Balans**: `--balance` (headless) drukt per vijand af hoe lang de held erover doet om hem te doden en omgekeerd, met een bij het
  level passende build (`BALANCE_BUILDS` in Main.gd, zonder pantser en zonder ontwijken). Streef naar ratio 0,6-1,0 voor gewone vijanden
  en 1,5-3 voor bazen. Bijgesteld: `marmara_sparring` hp 140 -> 120 (ratio 1,23 -> ~1,05 met alleen een lathi) en `dvikhadga` hp 1400 -> 1100
  (3,08 -> ~2,4). Speler-hp 100 tegenover vijand-dmg 90 is geen probleem zolang je meegroeit: een held met stat 7 heeft 310 hp en 36% minder schade.
  Multiplier-cap 10 (= 2x tapas) is zo gelaten.
- `DebugOverlay` is nog tijdelijk: toont nu ook drankjes en "(mediteert)", en herstelt de speler 4 s na de dood (echt dood-scherm = stap 3).
- Rooktest (`--smoke`) dekt nu ook drankjes, Dhyana, vuisten en Marmara's duel in haar echte regio met echte slagen (47 controles);
  `tools/check.sh` faalt bij runtime SCRIPT ERROR. Stand: alles groen.
- `--combat-shot` (venster, host) maakt `screenshots/combat_1..4.png` (slag, siddhi's, telegraaf-flits, Dhyana). Schermshots isoleren
  het venster van echte muis/toetsen (`_isolate_window`), zodat meespelen de run niet verstoort (op Wayland niet bewezen: blijf er af tijdens een run).
- Let op voor stap 3: het dood-paneel (`panel_requested`) laat de muis los (`controls_on = false`); iets in de UI moet na de respawn
  `Player.capture_mouse()` aanroepen, zoals DebugOverlay nu doet. De held start in vira_akhara (entry "") op een richel 2,2 m boven het oefenveld:
  niet onderzocht of dat bij echte aankomst via een uitgang ook zo is.

### Proefspel-checklist (alleen Gerald kan dit doen: echte muis en toetsen)

Start het spel op de host en loop dit af; schrijf op wat raar voelt:
1. Slag (LMB/J) driemaal achter elkaar = combo met afmaker; vasthouden (>0,2 s) = geladen slag, bij volle lading flitst de held geel.
2. Blok (RMB/K): vijand die oranje flitst vlak voor de treffer blokkeren (binnen 0,25 s) = parry, de vijand wankelt.
3. Tab of middelste muisknop = doel vergrendelen (rode kegel), nogmaals = volgend doel; camera draait mee.
4. F = boog of chakra (heb er een uitgerust), vasthouden = spannen, loslaten = schieten; kruisje in het midden.
5. 1-6 = siddhi's (eerst leren, zie `Game.learn_siddhi`); let op kosten in Ojas en cooldown.
6. H vasthouden = zitten, Ojas stijgt snel; klap erop = opstaan. R en T = drankjes (je hebt ze alleen als je ze koopt of vindt).
7. Zonder wapen vechten: leg de lathi af (inventaris komt in stap 3; tot dan via code `Game.unequip("melee")`).
8. Marmara: zet `Game.set_flag("marmara_duel_started")` en ga naar `vira_akhara`; ze geeft zich over op 1 hp.
Vragen om op te letten: voelt de parry-timing eerlijk? is het blokkeren te sterk/zwak? is de camera bij Tab-lock prettig? zijn de vijanden te snel of te hard?

Wat er NOG NIET is: HUD, menu's, dialoogvenster, dood-scherm, hoofdmenu (stap 3).

Wat Haiku als "afgerond" opgaf maar **ongetest** is: save/load, arena-waves, dag/nacht, shrines,
vissen/graven, followers, bossbalans. De rooktest raakt alleen start, lopen, vijand doden + orbs,
projectiel en het opbouwen van alle 48 regio's. Vertrouw de rest niet zonder het te draaien.

## Controleren (headless) en draaien

`tools/check.sh <godot-binary>` compileert alle scripts, valideert de data en bouwt alle
48 regio's en draait daarna de rooktest (`--smoke`: start, lopen, vijand doden met orbs, projectiel,
combat, drankjes, Dhyana, vuisten, Marmara's duel, alle 48 regio's bevolkt). Laatste stand (2026-10-03):
scripts 22/22 ok, data 0 fouten, regio's ok (~22.000 nodes), rooktest PASS (47 controles). Exit-code 0 = alles groen.
Losse hooks: `--balance` (balansrapport), `--combat-shot` / `--game-shot` (venster, screenshots).
Scratch-run op de host: rsync de repo naar `laptop:~/.cache/fable-sd-check` (excl. .git/.godot/screenshots), daar `tools/check.sh` draaien.

Godot-binaries:

- **Host** (`ssh laptop`): geen rpm/flatpak. Wel
  `~/Downloads/Godot_v4.7.2-stable_mono_linux_x86_64/Godot_v4.7.2-stable_mono_linux.x86_64`
  (mono-build, werkt voor GDScript). Repo staat daar ook in `~/projects/fable-sd`.
- **Dev-VM**: godot niet geïnstalleerd (Fedora heeft `godot` 4.7.2 in `updates`). Systeemwijzigingen
  horen in Ansible (repo `~/projects/fedora-workstation`), niet met een losse `dnf install`. Raadpleeg
  de `laptop`-skill. Headless checks kunnen in de VM; een speelbaar venster draai je op de host
  (sessie: Wayland, `/run/user/1000/wayland-0`).
- Nooit `ssh laptop sudo ...` (telt als faillock-strike en sluit Gerald uit).

## Projectconventies

- `project.godot` is **gegenereerd** door `tools/gen_project.py` — wijzig dat script, niet het bestand.
- Autoloads: `Events`, `Loc`, `Data`, `Game`, `Audio` (zie `scripts/autoload/`).
- Data in `data/*.json`, teksten NL/EN in `localization/`.
- `.godot/`, `*.import`, `/saves/`, `/screenshots/` staan in `.gitignore`.
- Geen subagents of parallelle agents gebruiken (Gerald's globale regel).
- Fase voor fase: bespreek de aanpak, voer uit, dring niet aan op uitvoering.
- Verifieer vóór je fixt: draai `tools/check.sh` en lees fouten, ga niet gokken.

## Planning staat in project-center (PCC)

Project `fable-sd` (silo labs, status early-development), initiative `speelbare-mvp`. Gebruik de
`project-center`-MCP (`get_project_context fable-sd`) voor het actuele bord. Stand bij overdracht:

Sectie **MVP speelbaar** (P1, op volgorde):
1. Entity-scripts schrijven (Player, NPC, Enemy, Projectile, Effects) zodat het project compileert,
   `tools/check.sh` groen is en `Main.tscn` start.
2. Combat (damage, knockback, effecten) en NPC/Enemy-AI (patrouille, agro, aanvalstiming), op basis
   van `data/enemies.json` en `data/moves.json`. Wacht op 1.
3. UI: health/mana-HUD, inventory, quest log, equipment-menu, hoofdmenu, regio-overgangen/spawn-logica.
   Wacht op 1.

Sectie **Na MVP**: bestaande systemen testen (dialoog, save/load, arena, dag/nacht, shrines,
minigames, rewards, followers, bosses), daarna polish (animaties, geluid, effecten, performance,
grasmesh-culling). Wacht op 2 en 3.

Zet todo's in PCC op `completed` zodra ze klaar zijn en leg niet-afleidbare besluiten vast in
`.project/state.md` of `.project/notes.md`.

## Nog open

- `.project/` (PCC-data) is nog niet gecommit; vraag Gerald of dat in deze repo mag.
- Er staat geen README.
- Headless draaien geeft "ObjectDB instances were leaked at exit": waarschijnlijk de statische materiaalcache in `Props` (niet uitgezocht); geen functioneel effect gezien.
- Alleen op de host kun je spelen; `tools/check.sh` draait ook in de VM als daar een Godot staat.
