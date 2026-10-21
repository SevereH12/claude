--!strict
-- Portals between worlds, from your side: a welcome banner when the server
-- moves you to another world (Systems/Travel sets your World attribute),
-- and why a portal won't take you yet when you walk into it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Portals = require(ReplicatedStorage.Shared.Util.Portals)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)
local ZoneBanner = require(script.Parent.ZoneBanner)

local player = Players.LocalPlayer

local Travel = {}

function Travel.start()
	local shown = Portals.worldOf(player).id
	player:GetAttributeChangedSignal(Portals.WORLD_ATTRIBUTE):Connect(function()
		local world = Portals.worldOf(player)
		if world.id ~= shown then
			shown = world.id
			ZoneBanner.show(
				`WELCOME TO {string.upper(world.displayName)}`,
				world.tagline,
				world.color
			)
		end
	end)

	local explained: string? = nil -- the locked portal you're standing in
	while true do
		task.wait(0.2)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local snapshot = State.current
		if root and root:IsA("BasePart") and snapshot then
			local world = Portals.at(root.Position)
			local reason = if world then Progression.worldLockReason(snapshot, world) else nil
			if world and reason and explained ~= world.id then
				explained = world.id
				ZoneBanner.show(`🔒 {string.upper(world.displayName)}`, reason, UI.COLORS.red)
			elseif not reason then
				explained = nil
			end
		end
	end
end

return Travel
