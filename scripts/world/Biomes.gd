## Biome palettes and parameters for the procedural regions.
extends RefCounted

static func c(hex: String) -> Color:
	return Color(hex)

static func get_biome(id: String) -> Dictionary:
	var b := _base()
	match id:
		"village":
			b.merge({"ground": c("#5f8f3a"), "ground2": c("#7fa848"), "path": c("#b59a6a"), "tree_kind": "deciduous", "tree_density": 0.25, "grass_density": 0.6, "mood": "village",
				"sky_top": c("#4a8fd8"), "sky_horizon": c("#cfe3f5"), "fog": c("#cfe0ee"), "fog_density": 0.004}, true)
		"akhara":
			b.merge({"ground": c("#6e8f45"), "ground2": c("#8aa65a"), "path": c("#c9b48a"), "tree_kind": "deciduous", "tree_density": 0.18, "grass_density": 0.45, "mood": "akhara",
				"sky_top": c("#5a95d8"), "sky_horizon": c("#f1e2c8"), "fog": c("#e6dcc6"), "fog_density": 0.004}, true)
		"forest":
			b.merge({"ground": c("#3f6b2a"), "ground2": c("#5b8a37"), "path": c("#8f7a52"), "tree_kind": "deciduous", "tree_density": 0.75, "grass_density": 0.7, "rock_density": 0.25, "mood": "forest",
				"sky_top": c("#4682c8"), "sky_horizon": c("#bcd8c8"), "fog": c("#a9c8a8"), "fog_density": 0.009, "sun_energy": 1.1}, true)
		"hill":
			b.merge({"ground": c("#6f8f4a"), "ground2": c("#9aa560"), "path": c("#b0a07a"), "tree_kind": "deciduous", "tree_density": 0.2, "grass_density": 0.5, "rock_density": 0.5, "mood": "overworld",
				"sky_top": c("#3f7fd0"), "sky_horizon": c("#d8e6f2"), "fog": c("#d0dde8"), "fog_density": 0.003}, true)
		"lake":
			b.merge({"ground": c("#4f7f35"), "ground2": c("#6f9a45"), "path": c("#9c8a63"), "tree_kind": "deciduous", "tree_density": 0.45, "grass_density": 0.65, "mood": "lake",
				"sky_top": c("#4a8fd8"), "sky_horizon": c("#d4e8f2"), "fog": c("#c6dde4"), "fog_density": 0.005}, true)
		"city":
			b.merge({"ground": c("#a89a7c"), "ground2": c("#b8aa8c"), "path": c("#8c7a5e"), "tree_kind": "deciduous", "tree_density": 0.08, "grass_density": 0.15, "mood": "city",
				"sky_top": c("#4f8fd0"), "sky_horizon": c("#f0dcc0"), "fog": c("#e8d8c0"), "fog_density": 0.003}, true)
		"coast":
			b.merge({"ground": c("#c9b98a"), "ground2": c("#7f9a4a"), "path": c("#b8a67a"), "tree_kind": "palm", "tree_density": 0.3, "grass_density": 0.3, "rock_density": 0.4, "mood": "coast",
				"sky_top": c("#3f8fe0"), "sky_horizon": c("#e0f0ff"), "fog": c("#d6e8f4"), "fog_density": 0.004, "water_shallow": c("#3fb0b8"), "water_deep": c("#0f4f7a")}, true)
		"farm":
			b.merge({"ground": c("#6f9340"), "ground2": c("#a0a848"), "path": c("#b59a6a"), "tree_kind": "mango", "tree_density": 0.35, "grass_density": 0.5, "mood": "village",
				"sky_top": c("#4a8fd8"), "sky_horizon": c("#f3e6c8"), "fog": c("#e0dcc0"), "fog_density": 0.004}, true)
		"cave":
			b.merge({"ground": c("#5a5048"), "ground2": c("#6e6258"), "path": c("#4a403a"), "rock": c("#3e3630"), "tree_kind": "none", "tree_density": 0.0, "grass_density": 0.0, "rock_density": 0.7, "mood": "cave",
				"interior": true, "fog": c("#141010"), "fog_density": 0.03, "ambient": 0.15, "sun_energy": 0.0, "ceiling": c("#2a2420"), "water_shallow": c("#2a5a60"), "water_deep": c("#0a2a30")}, true)
		"ice_cave":
			b.merge({"ground": c("#b8d4e8"), "ground2": c("#d8ecf8"), "path": c("#9ab8cc"), "rock": c("#7fa0c0"), "tree_kind": "none", "tree_density": 0.0, "grass_density": 0.0, "rock_density": 0.6, "mood": "cave",
				"interior": true, "fog": c("#1a2838"), "fog_density": 0.03, "ambient": 0.25, "sun_energy": 0.0, "ceiling": c("#5a7a98"), "snow": true}, true)
		"gorge":
			b.merge({"ground": c("#5a7a3a"), "ground2": c("#8a8a6a"), "path": c("#9a8a66"), "rock": c("#6a6660"), "tree_kind": "deciduous", "tree_density": 0.3, "grass_density": 0.4, "rock_density": 0.8, "mood": "forest",
				"sky_top": c("#4682c8"), "sky_horizon": c("#c8d8d8"), "fog": c("#b8c8c0"), "fog_density": 0.007}, true)
		"dark_forest":
			b.merge({"ground": c("#2a3a28"), "ground2": c("#3a4a34"), "path": c("#4a4038"), "rock": c("#3a3a40"), "tree_kind": "dead", "tree_density": 0.8, "grass_density": 0.3, "rock_density": 0.3, "mood": "dark",
				"sky_top": c("#2a2a4a"), "sky_horizon": c("#6a5a7a"), "fog": c("#4a3a5a"), "fog_density": 0.02, "sun_energy": 0.45, "sun_color": c("#b8a8d8"), "ambient": 0.35, "grass_base": c("#243424"), "grass_tip": c("#4a5a3a")}, true)
		"dark_lake":
			b.merge({"ground": c("#2a3a28"), "ground2": c("#3a4a34"), "path": c("#4a4038"), "tree_kind": "dead", "tree_density": 0.5, "grass_density": 0.3, "mood": "dark",
				"sky_top": c("#1a1a3a"), "sky_horizon": c("#5a4a6a"), "fog": c("#3a3050"), "fog_density": 0.018, "sun_energy": 0.4, "sun_color": c("#a898c8"), "ambient": 0.3, "water_shallow": c("#20303a"), "water_deep": c("#050a10"), "grass_base": c("#243424"), "grass_tip": c("#4a5a3a")}, true)
		"marsh":
			b.merge({"ground": c("#3a4a2a"), "ground2": c("#5a6a3a"), "path": c("#5a5040"), "tree_kind": "dead", "tree_density": 0.45, "grass_density": 0.8, "mood": "dark",
				"sky_top": c("#2a3a4a"), "sky_horizon": c("#7a7a6a"), "fog": c("#5a6a58"), "fog_density": 0.02, "sun_energy": 0.5, "ambient": 0.35, "water_shallow": c("#3a4a30"), "water_deep": c("#101a10"), "grass_base": c("#2e4a2a"), "grass_tip": c("#6a7a3a")}, true)
		"ruins":
			b.merge({"ground": c("#6a6a52"), "ground2": c("#8a8a68"), "path": c("#8a7a5a"), "rock": c("#7a7466"), "tree_kind": "dead", "tree_density": 0.25, "grass_density": 0.35, "rock_density": 0.6, "mood": "dark",
				"sky_top": c("#3a3a5a"), "sky_horizon": c("#9a8a7a"), "fog": c("#6a6060"), "fog_density": 0.012, "sun_energy": 0.7, "ambient": 0.3}, true)
		"graveyard":
			b.merge({"ground": c("#4a5a3a"), "ground2": c("#6a6a4a"), "path": c("#6a6050"), "rock": c("#5a5a58"), "tree_kind": "dead", "tree_density": 0.3, "grass_density": 0.4, "rock_density": 0.3, "mood": "graveyard",
				"sky_top": c("#2a2a44"), "sky_horizon": c("#8a7a8a"), "fog": c("#5a5068"), "fog_density": 0.015, "sun_energy": 0.6, "sun_color": c("#c8b8d8"), "ambient": 0.3}, true)
		"necropolis":
			b.merge({"ground": c("#8a98a8"), "ground2": c("#b8c4d0"), "path": c("#6a7484"), "rock": c("#5a6470"), "tree_kind": "dead", "tree_density": 0.15, "grass_density": 0.0, "rock_density": 0.4, "mood": "graveyard",
				"sky_top": c("#2a3048"), "sky_horizon": c("#8a8aa0"), "fog": c("#6a7088"), "fog_density": 0.014, "sun_energy": 0.6, "sun_color": c("#c0c8e8"), "ambient": 0.35, "snow": true}, true)
		"witchwood":
			b.merge({"ground": c("#3a3a5a"), "ground2": c("#5a4a7a"), "path": c("#6a5a6a"), "rock": c("#4a4060"), "tree_kind": "purple", "tree_density": 0.7, "grass_density": 0.5, "rock_density": 0.3, "mood": "witch",
				"sky_top": c("#2a1a4a"), "sky_horizon": c("#9a6ab8"), "fog": c("#6a4a8a"), "fog_density": 0.014, "sun_energy": 0.6, "sun_color": c("#d8b8f8"), "ambient": 0.4, "grass_base": c("#3a2a5a"), "grass_tip": c("#8a5aa8")}, true)
		"temple":
			b.merge({"ground": c("#8a9a5a"), "ground2": c("#a8b870"), "path": c("#d8c8a0"), "tree_kind": "deciduous", "tree_density": 0.15, "grass_density": 0.4, "mood": "temple",
				"sky_top": c("#4a8fe0"), "sky_horizon": c("#ffe8c0"), "fog": c("#f0e0c0"), "fog_density": 0.003, "sun_energy": 1.3}, true)
		"arena":
			b.merge({"ground": c("#b8a070"), "ground2": c("#c8b080"), "path": c("#a89060"), "rock": c("#8a7a60"), "tree_kind": "none", "tree_density": 0.0, "grass_density": 0.05, "rock_density": 0.2, "mood": "arena",
				"sky_top": c("#3f80d0"), "sky_horizon": c("#f0d8b0"), "fog": c("#e0ccaa"), "fog_density": 0.003}, true)
		"prison":
			b.merge({"ground": c("#4a4a4e"), "ground2": c("#5a5a60"), "path": c("#3a3a3e"), "rock": c("#2a2a30"), "tree_kind": "none", "tree_density": 0.0, "grass_density": 0.0, "rock_density": 0.0, "mood": "prison",
				"interior": true, "fog": c("#101014"), "fog_density": 0.025, "ambient": 0.18, "sun_energy": 0.0, "ceiling": c("#1e1e24")}, true)
		"chamber":
			b.merge({"ground": c("#3a2a3a"), "ground2": c("#5a3a5a"), "path": c("#4a3048"), "rock": c("#2a1a2a"), "tree_kind": "none", "tree_density": 0.0, "grass_density": 0.0, "rock_density": 0.0, "mood": "boss",
				"interior": true, "fog": c("#180a18"), "fog_density": 0.02, "ambient": 0.25, "sun_energy": 0.0, "ceiling": c("#1a0a1a")}, true)
		"camp":
			b.merge({"ground": c("#5a6a38"), "ground2": c("#7a7a44"), "path": c("#8a7a5a"), "tree_kind": "deciduous", "tree_density": 0.3, "grass_density": 0.4, "mood": "camp",
				"sky_top": c("#3a5a8a"), "sky_horizon": c("#d8b890"), "fog": c("#b8a890"), "fog_density": 0.008, "sun_energy": 0.8}, true)
		"snow":
			b.merge({"ground": c("#dde8f4"), "ground2": c("#f4f8fc"), "path": c("#b8c4d0"), "rock": c("#6a7484"), "tree_kind": "pine", "tree_density": 0.45, "grass_density": 0.0, "rock_density": 0.5, "mood": "snow",
				"sky_top": c("#6a90c8"), "sky_horizon": c("#e8f0f8"), "fog": c("#dce8f4"), "fog_density": 0.012, "sun_energy": 0.9, "sun_color": c("#e8f0ff"), "snow": true, "water_shallow": c("#a8c8e8"), "water_deep": c("#2a4a6a")}, true)
	return b

static func _base() -> Dictionary:
	return {
		"ground": c("#5f8f3a"), "ground2": c("#7fa848"), "path": c("#b59a6a"), "rock": c("#7a7468"), "sand": c("#d8c89a"),
		"tree_kind": "deciduous", "tree_density": 0.3, "grass_density": 0.5, "rock_density": 0.3,
		"grass_base": c("#2d6a1e"), "grass_tip": c("#8fc14a"),
		"sky_top": c("#4a8fd8"), "sky_horizon": c("#cfe3f5"), "sky_ground": c("#4a4a3a"),
		"fog": c("#cfe0ee"), "fog_density": 0.005, "ambient": 0.6, "sun_energy": 1.0, "sun_color": c("#fff2d8"),
		"mood": "overworld", "interior": false, "ceiling": c("#222222"), "snow": false,
		"water_shallow": c("#3a8fa0"), "water_deep": c("#0c3550"),
	}
