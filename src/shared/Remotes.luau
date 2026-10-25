--!strict
-- The full list of RemoteEvents. Adding a remote = adding a name here.
-- The server creates them at startup; the client only waits for them.
--
-- Server -> client: StateSnapshot, StormState, StrikeWarning, StrikeLanded, Sold, Forecast,
-- Purchased, Rewarded, GiftNews, Announcement, Settings
-- Client -> server: BuyBottle, BuyBoots, HireResearcher, PostResearcher, DevCommand, Teleport,
-- RemoteSell, SetBoltColour, StartTrial, StoreEvent, ClaimDaily, ClaimGift,
-- GroupJoined, FindPlayer, PrepareGift, SendCredit, CancelGift, AfkRejoin,
-- PromoteResearcher, SaveSettings, ClaimQuest, RerollQuest, ClaimLogRow
-- Both ways: Ascend (asks, then confirms with the server's token; the server
-- answers with the confirm screen's details or the new level), Tutorial
-- (the client asks to "skip"; the server says "finished")

export type RemoteName =
	"StateSnapshot"
	| "StormState"
	| "StrikeWarning"
	| "StrikeLanded"
	| "Forecast"
	| "Sold"
	| "BuyBottle"
	| "BuyBoots"
	| "HireResearcher"
	| "PostResearcher"
	| "DevCommand"
	| "Teleport"
	| "RemoteSell"
	| "SetBoltColour"
	| "StartTrial"
	| "StoreEvent"
	| "Purchased"
	| "ClaimDaily"
	| "ClaimGift"
	| "Rewarded"
	| "GroupJoined"
	| "FindPlayer"
	| "PrepareGift"
	| "SendCredit"
	| "GiftNews"
	| "CancelGift"
	| "Announcement"
	| "AfkRejoin"
	| "PromoteResearcher"
	| "SaveSettings"
	| "Settings"
	| "ClaimQuest"
	| "RerollQuest"
	| "ClaimLogRow"
	| "Ascend"
	| "Tutorial"

local NAMES: { RemoteName } = {
	"StateSnapshot",
	"StormState",
	"StrikeWarning",
	"StrikeLanded",
	"Forecast",
	"Sold",
	"BuyBottle",
	"BuyBoots",
	"HireResearcher",
	"PostResearcher",
	"DevCommand",
	"Teleport",
	"RemoteSell",
	"SetBoltColour",
	"StartTrial",
	"StoreEvent",
	"Purchased",
	"ClaimDaily",
	"ClaimGift",
	"Rewarded",
	"GroupJoined",
	"FindPlayer",
	"PrepareGift",
	"SendCredit",
	"GiftNews",
	"CancelGift",
	"Announcement",
	"AfkRejoin",
	"PromoteResearcher",
	"SaveSettings",
	"Settings",
	"ClaimQuest",
	"RerollQuest",
	"ClaimLogRow",
	"Ascend",
	"Tutorial",
}

return table.freeze(NAMES)
