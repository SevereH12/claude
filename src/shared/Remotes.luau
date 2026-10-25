--!strict
-- The full list of RemoteEvents. Adding a remote = adding a name here.
-- The server creates them at startup; the client only waits for them.
--
-- Server -> client: StateSnapshot, StormState, StrikeWarning, StrikeLanded, Sold, Forecast,
-- Purchased, Rewarded, GiftNews, Announcement, Settings
-- Client -> server: BuyBottle, BuyBoots, HireResearcher, PostResearcher, DevCommand, Teleport,
-- RemoteSell, SetBoltColour, StartTrial, StoreEvent, ClaimDaily, ClaimGift,
-- GroupJoined, FindPlayer, PrepareGift, SendCredit, CancelGift, AfkRejoin,
-- PromoteResearcher, SaveSettings, ClaimQuest, RerollQuest

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
}

return table.freeze(NAMES)
