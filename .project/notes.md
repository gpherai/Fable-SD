## Polish-onderzoek (2026-10-03, nog niets uitgevoerd)

Gerald: de game is alleen voor desktop (mobiele input vervalt). Gelezen: Body, NPC, Enemy, EnemyAI, Player, PlayerCombat (pose-code),
Effects, Projectile, Audio, World, WorldGen, Props (basis), shaders, Main, Settings, gen_project.py.

### Bevindingen
- **Geluid**: 36 synth-sfx, maar `step` wordt nergens gespeeld (geen voetstappen). Ambient is een 6 s drone-loop per biome: de fasen
  eindigen niet op hele cycli, dus er zit een tik op het looppunt. Geen natuurgeluid (wind, vogels), geen muzieklagen, geen afwisseling
  per oppervlak. Audio.play heeft 10 spelers; daarna valt een geluid stil weg.
- **Animatie**: `Body.pose_walk` stuurt alleen LegL/LegR/ArmL/ArmR aan. Vierpotigen (wolf, tijger, draak) hebben Leg0-3 en insecten
  geen benen: ze glijden. NPC's staan stil (alleen draaien naar de speler), geen idle-adem. Dood-animatie is voor iedereen hetzelfde
  (omvallen); spare knielt. Poses zijn rotaties van losse blokken zonder ellebogen of knieen.
- **Effecten**: `Effects.ring/wedge/bolt/sparks` maken per aanroep nieuwe Mesh + Material + Tween (geen hergebruik). Orbs en
  schade-nummers zijn losse nodes. Er is geen slag-trail, hit-stop of camerashake.
- **Performance** (`--perf`, host, Iris Xe, 1600x900, vsync uit). LET OP: gemeten terwijl de Incus-VM, Docker, Claude Code en Codex
  draaiden; de absolute tijden (22-75 ms) zijn daardoor te somber. Gerald speelde daarna met alles uit en zag geen haperingen.
  De verhoudingen zijn wel bruikbaar. Kosten per onderdeel (ms van de frame, medianen van de rustige regio's):
  MSAA 2x ~10 ms (grootste post), SSAO 3-6 ms, glow 2-3 ms, schaduwen 3 ms maar vooral draw calls (1066 -> 393 zonder), actors tot
  ~26 ms bij 14 vijanden, omni-lichten 1-3 ms, bomen 0-10 ms, gras 0-10 ms (~2000 instanties, een knelpunt is het niet).
  Draw calls: 400-1070 per regio, ~40 meshes per mens/vijand (elk eigen MeshInstance3D en eigen Mesh-resource).
- `quality low` zet alleen het gras op 60% en de zonneschaduw uit; MSAA en SSAO blijven aan. Makkelijke winst voor zwakkere machines.
- Spawn met entry "" (nieuw spel, testhaken) valt terug op `points.hub`, het midden waar de grote objecten staan (kampvuur, dhuni):
  de held kan daar in een object beginnen. Bij reizen via een uitgang speelt dit niet (6 m binnen de rand).

### Voorgestelde volgorde (Gerald koos de eerste polish-todo; geen uitvoering zonder akkoord op de aanpak)
1. Geluid: voetstappen (per snelheid/oppervlak), drone-loop naadloos, natuurgeluid per biome, nachtlaag, meer varianten.
2. Animatie: pose_walk voor Leg0-3 en insecten, NPC- en vijand-idle, dood-animaties per vorm.
3. Effecten: gedeelde meshes/materialen, hit-stop, trails, lichte camerashake.
4. Performance: quality low ook MSAA/SSAO uit, schaduwafstand, modellen samenvoegen, pas daarna gras-culling.

Testhaak: `--perf` (venster, host) in Main.gd; draai hem tegen een rustige machine voor voor/na-vergelijkingen, direct na elkaar.
