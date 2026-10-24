--!strict
-- Every music candidate tools/audio/music_search.py found (see
-- docs/audio/music-shortlist.md), for the Studio Music audition. The game
-- itself plays Config.MUSIC. Generated: don't edit by hand.

export type Track = { slot: string, id: number, title: string }

local MusicShortlist: { Track } = {
	{
		slot = "Bay_Calm",
		id = 133196125967338,
		title = "Cheerful Classroom Celebration Instrumental",
	},
	{ slot = "Bay_Calm", id = 88298878796645, title = "Seaside Reflections" },
	{ slot = "Bay_Calm", id = 1838661059, title = "Magical Adventure (Light Vs)" },
	{ slot = "Bay_Calm", id = 136251871500167, title = "Happier Times Underscore No Guitar" },
	{
		slot = "Bay_Calm",
		id = 80528649276922,
		title = "Clear Sky Adventures – Light And Free Pop Vibe",
	},
	{ slot = "Bay_Calm", id = 1839712363, title = "So Good" },
	{ slot = "Bay_Storm", id = 9044545570, title = "Night Run" },
	{ slot = "Bay_Storm", id = 92504170192114, title = "Roller coaster?" },
	{ slot = "Bay_Storm", id = 129146412554158, title = "Funk Drift" },
	{ slot = "Bay_Storm", id = 9039704032, title = "I'm a Believer - Instrumental" },
	{ slot = "Bay_Storm", id = 85418758234941, title = "Funk Pulse Ignition" },
	{ slot = "Bay_Storm", id = 90436125586978, title = "Stop and think" },
	{ slot = "Voltcliff_Calm", id = 9047610291, title = "Follow The Footprints - Underscore" },
	{ slot = "Voltcliff_Calm", id = 9039374146, title = "Time in Gears" },
	{ slot = "Voltcliff_Calm", id = 1842365805, title = "Heavenly Clockwork" },
	{ slot = "Voltcliff_Calm", id = 9047603123, title = "The Game Is Afoot" },
	{ slot = "Voltcliff_Calm", id = 9047609075, title = "The Mysterious Case - Narrative" },
	{ slot = "Voltcliff_Calm", id = 9048058406, title = "Ant Farm (a)" },
	{ slot = "Voltcliff_Storm", id = 122770769791748, title = "Alarm Glock NO DRM KT" },
	{ slot = "Voltcliff_Storm", id = 131880535514102, title = "Macho Manhunt" },
	{ slot = "Voltcliff_Storm", id = 101746788451393, title = "Loco Motive NO ORCH" },
	{ slot = "Voltcliff_Storm", id = 104298882631750, title = "Gears Are Turning" },
	{ slot = "Voltcliff_Storm", id = 99404450789073, title = "Tundra (Instrumental)" },
	{ slot = "Voltcliff_Storm", id = 132510789595381, title = "List Of Triggers NO WEPN FX" },
	{ slot = "Stormspire_Calm", id = 9046598930, title = "Watching the Garden Grow (a)" },
	{ slot = "Stormspire_Calm", id = 9046599262, title = "Pizzicato Spritz (a)" },
	{ slot = "Stormspire_Calm", id = 9046601476, title = "The Whimsical Waltz (c)" },
	{ slot = "Stormspire_Calm", id = 9046270989, title = "Playful Penguins C" },
	{ slot = "Stormspire_Calm", id = 98741106695284, title = "Eydal, Whimsical Forest" },
	{ slot = "Stormspire_Calm", id = 1842071889, title = "Whimsical Carousel (a)" },
	{
		slot = "Stormspire_Storm",
		id = 116315815173589,
		title = "Phantom Nova (Underscore Version)",
	},
	{ slot = "Stormspire_Storm", id = 117596024497708, title = "Aeon Driver (Underscore Version)" },
	{
		slot = "Stormspire_Storm",
		id = 135102649170289,
		title = "The Great Dynasties (Underscore Version)",
	},
	{ slot = "Stormspire_Storm", id = 134766455010964, title = "Cobra Steel (Underscore Version)" },
	{ slot = "Stormspire_Storm", id = 125611478346478, title = "Chase Your Epic Dream" },
	{ slot = "Stormspire_Storm", id = 1836707766, title = "Battle For The Sky 1" },
}

return table.freeze(MusicShortlist)
