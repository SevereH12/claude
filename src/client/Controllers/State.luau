--!strict
-- Holds the latest state the server sent us. Read-only on the client:
-- changing it here changes nothing on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)

local State = {}

State.current = nil :: Types.Snapshot?
State.Changed = Signal.new() :: Signal.Signal<Types.Snapshot>

function State.init()
	-- remote events queue until connected, so the first snapshot isn't missed
	Net.get("StateSnapshot").OnClientEvent:Connect(function(snapshot: Types.Snapshot)
		State.current = snapshot
		State.Changed:Fire(snapshot)
	end)
end

return State
