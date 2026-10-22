--!strict
-- The full list of RemoteEvents. Adding a remote = adding a name here.
-- The server creates them at startup; the client only waits for them.
--
-- Server -> client: StateSnapshot, StormState, StrikeWarning, StrikeLanded, Sold, Forecast,
-- Purchased, Rewarded
-- Client -> server: BuyBottle, BuyBoots, HireResearcher, PostResearcher, DevCommand, Teleport,
-- RemoteSell, SetBoltColour, StartTrial, StoreEvent, ClaimDaily, ClaimGift,
-- GroupJoined

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
}

return table.freeze(NAMES)
