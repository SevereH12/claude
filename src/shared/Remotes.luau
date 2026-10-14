--!strict
-- The full list of RemoteEvents. Adding a remote = adding a name here.
-- The server creates them at startup; the client only waits for them.
--
-- Server -> client: StateSnapshot, StormState, StrikeWarning, StrikeLanded, Sold
-- Client -> server: BuyBottle (the only request a client can make)

export type RemoteName =
	"StateSnapshot"
	| "StormState"
	| "StrikeWarning"
	| "StrikeLanded"
	| "Sold"
	| "BuyBottle"

local NAMES: { RemoteName } = {
	"StateSnapshot",
	"StormState",
	"StrikeWarning",
	"StrikeLanded",
	"Sold",
	"BuyBottle",
}

return table.freeze(NAMES)
