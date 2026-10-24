--!strict
-- Every music candidate tools/audio/music_search.py found (see
-- docs/audio/music-shortlist.md), for the Studio Music audition. The game
-- itself plays Config.MUSIC. Generated: don't edit by hand.

export type Track = { slot: string, id: number, title: string }

local MusicShortlist: { Track } = {
	{ slot = "Bay_Calm", id = 94734731611772, title = "Playful Pixel Adventure" },
	{ slot = "Bay_Calm", id = 136150243866984, title = "Seaside View" },
	{ slot = "Bay_Calm", id = 129196538853609, title = "Ambient Adventure Trail" },
	{ slot = "Bay_Calm", id = 136012265808588, title = "Happy Ukulele Day" },
	{ slot = "Bay_Calm", id = 120416151765277, title = "Seaside Smile" },
	{ slot = "Bay_Calm", id = 137535734242043, title = "Light Adventure Echo" },
	{ slot = "Bay_Storm", id = 125777738272639, title = "Driving Shadows (Electronic Music 2025)" },
	{ slot = "Bay_Storm", id = 1836021063, title = "Electro Chase" },
	{ slot = "Bay_Storm", id = 71868660197528, title = "Upbeat Synthpop" },
	{ slot = "Bay_Storm", id = 1841266692, title = "Fresh News" },
	{ slot = "Bay_Storm", id = 73905859114793, title = "Synthesized Shadows" },
	{ slot = "Bay_Storm", id = 9043224162, title = "Cynics" },
	{ slot = "Voltcliff_Calm", id = 97805011981124, title = "Steampunk Clockworks" },
	{ slot = "Voltcliff_Calm", id = 9039372102, title = "Time Traveller" },
	{ slot = "Voltcliff_Calm", id = 116123343811105, title = "Clockwork Symphony" },
	{ slot = "Voltcliff_Calm", id = 9047610291, title = "Follow The Footprints - Underscore" },
	{ slot = "Voltcliff_Calm", id = 9039373061, title = "The Cthulhu Myth Alternate" },
	{ slot = "Voltcliff_Calm", id = 72006124559764, title = "Cog Assembly" },
	{
		slot = "Voltcliff_Storm",
		id = 70881491117119,
		title = "Ecos de Titán (Industrial & Electronic Rock)",
	},
	{ slot = "Voltcliff_Storm", id = 79863038732814, title = "Refresh" },
	{
		slot = "Voltcliff_Storm",
		id = 136266951088751,
		title = "Dubstep Action Gaming Music – Heavy Drops & Energy",
	},
	{ slot = "Voltcliff_Storm", id = 1847588120, title = "Epic Steps A" },
	{ slot = "Voltcliff_Storm", id = 122770769791748, title = "Alarm Glock NO DRM KT" },
	{ slot = "Voltcliff_Storm", id = 1847805060, title = "Hijacker A" },
	{ slot = "Stormspire_Calm", id = 95537109377454, title = "Dreamy midnight flight" },
	{ slot = "Stormspire_Calm", id = 82631091427646, title = "Dreamy Flights" },
	{ slot = "Stormspire_Calm", id = 111480456898998, title = "Floating Islands" },
	{ slot = "Stormspire_Calm", id = 95112044170649, title = "Dreamy Night Flight" },
	{ slot = "Stormspire_Calm", id = 9046598930, title = "Watching the Garden Grow (a)" },
	{ slot = "Stormspire_Calm", id = 85938151220666, title = "Floating Between Islands" },
	{
		slot = "Stormspire_Storm",
		id = 116315815173589,
		title = "Phantom Nova (Underscore Version)",
	},
	{ slot = "Stormspire_Storm", id = 1847492487, title = "21st Centurion A" },
	{ slot = "Stormspire_Storm", id = 117596024497708, title = "Aeon Driver (Underscore Version)" },
	{
		slot = "Stormspire_Storm",
		id = 135102649170289,
		title = "The Great Dynasties (Underscore Version)",
	},
	{ slot = "Stormspire_Storm", id = 128746729733181, title = "SCME Sky Battle Classic" },
	{ slot = "Stormspire_Storm", id = 134766455010964, title = "Cobra Steel (Underscore Version)" },
}

return table.freeze(MusicShortlist)
