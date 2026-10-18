--!strict
-- The full list of RemoteEvents. Adding a remote = adding a name here.
-- The server creates them at startup; the client only waits for them.
--
-- Server -> client: StateSnapshot, StormState, StrikeWarning, StrikeLanded, Sold, Forecast
-- Client -> server: BuyBottle, BuyBoots, HireResearcher, PostResearcher, DevCommand

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
}

return table.freeze(NAMES)
