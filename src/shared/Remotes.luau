--!strict
-- The full list of RemoteEvents. Adding a remote = adding a name here.
-- The server creates them at startup; the client only waits for them.
--
-- Server -> client: StateSnapshot, StormState, StrikeWarning, StrikeLanded, Sold, Forecast,
-- Purchased, Rewarded, GiftNews, Announcement
-- Client -> server: BuyBottle, BuyBoots, HireResearcher, PostResearcher, DevCommand, Teleport,
-- RemoteSell, SetBoltColour, StartTrial, StoreEvent, ClaimDaily, ClaimGift,
-- GroupJoined, FindPlayer, PrepareGift, SendCredit, CancelGift, AfkRejoin

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
}

return table.freeze(NAMES)
