--!strict
-- The full list of RemoteEvents. Adding a remote = adding a name here.
-- The server creates them at startup; the client only waits for them.

export type RemoteName = "Click" | "BuyUpgrade" | "Rebirth" | "StateSnapshot"

local NAMES: { RemoteName } = { "Click", "BuyUpgrade", "Rebirth", "StateSnapshot" }

return table.freeze(NAMES)
