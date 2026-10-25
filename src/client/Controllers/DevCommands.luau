--!strict
-- TEMPORARY test buttons: one sets your Volts to 1 trillion (shown in
-- Studio or to the place's owner), one turns Pretend Premium on and off
-- (Studio only), PASSES opens one "Pretend owns <pass>" toggle per Game
-- Pass and "Send test gift to me" and "Send test boost gift" buttons, and
-- REWARDS opens Next day, +5 min playtime, Clear boosts (and the Server
-- Storm and Surge), Start Server Storm, +500 research data, +100 Glints, Force golden
-- bolt (where you stand), Supercell in 30 s, a Pretend event toggle (Double
-- Volts Weekend), Server goal +25% (a full meter starts a Server Surge), Simulate idle 17 min (the AFK Lounge's
-- idle handler, Controllers/AfkUI), a Pretend group member toggle, the
-- Sound board, which plays every sound in order with its name, and the Music
-- audition, every shortlisted track for 20 s, Complete quest, +Log entry,
-- Ready to ascend, Restart tutorial and Pretend friends +1 (all Studio
-- only). The server (Systems/DevCommands) checks again. To
-- remove it: delete this file and Systems/DevCommands.luau, and take
-- "DevCommand" out of Shared/Remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Weather = require(ReplicatedStorage.Shared.Util.Weather)
local Layout = require(script.Parent.Parent.Lib.Layout)
local LayoutMath = require(script.Parent.Parent.Lib.LayoutMath)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local UI = require(script.Parent.Parent.Lib.UI)
local AfkUI = require(script.Parent.AfkUI)
local Music = require(script.Parent.Music)

local DevCommands = {}

local function isOwner(): boolean
	return RunService:IsStudio()
		or (
			game.CreatorType == Enum.CreatorType.User
			and Players.LocalPlayer.UserId == game.CreatorId
		)
end

function DevCommands.init()
	if not isOwner() then
		return
	end
	local devRemote = Net.get("DevCommand")
	local _, screenGui = Layout.screen("StormBottlerTest", 1)
	-- under the MENU button (LayoutMath.hud.test: two rows)
	local button = UI.button({
		Name = "TestVolts",
		Text = "TEST: 1T ⚡",
		BackgroundColor3 = UI.COLORS.volt,
		Parent = screenGui,
	})
	UI.maxText(button, 22)
	button.Activated:Connect(function()
		UI.pop(button)
		devRemote:FireServer("volts")
	end)
	local function row(index: number): LayoutMath.Rect
		local area = Layout.hud.test
		local height = (area.h - LayoutMath.GAP) / 2
		return {
			x = area.x,
			y = area.y + (index - 1) * (height + LayoutMath.GAP),
			w = area.w,
			h = height,
		}
	end
	UI.onLayout(function()
		UI.place(button, row(1))
	end)

	if not RunService:IsStudio() then
		return
	end
	local player = Players.LocalPlayer
	local premium = UI.button({
		Name = "PretendPremium",
		Text = "",
		BackgroundColor3 = UI.COLORS.storm,
		Parent = screenGui,
	})
	UI.onLayout(function()
		UI.place(premium, row(2))
	end)
	UI.maxText(premium, 16)
	local function pretending(): boolean
		return player:GetAttribute(Progression.PRETEND_PREMIUM) == true
	end
	local function refresh()
		local state = if pretending() then "ON" else "OFF"
		premium.Text = `{Progression.PREMIUM_ICON} PRETEND: {state}`
	end
	refresh()
	player:GetAttributeChangedSignal(Progression.PRETEND_PREMIUM):Connect(refresh)
	premium.Activated:Connect(function()
		UI.pop(premium)
		devRemote:FireServer("premium", not pretending())
	end)

	-- PASSES: a grid of Pretend toggles beside the TEST buttons
	local passes = UI.button({
		Name = "PretendPasses",
		Text = "🎟 PASSES ▸",
		BackgroundColor3 = UI.COLORS.panelTop,
		Parent = screenGui,
	})
	UI.maxText(passes, 16)
	local list = UI.make(Instance.new("Frame"), {
		Name = "PretendPassList",
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screenGui,
	})
	UI.make(Instance.new("UIGridLayout"), {
		CellSize = UDim2.new(0.5, -4, 0, 40),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	UI.onLayout(function()
		local third = row(3)
		UI.place(passes, third)
		local area = Layout.hud.test
		UI.place(list, {
			x = area.x + area.w + LayoutMath.GAP,
			y = area.y,
			w = 380,
			h = math.ceil((#Config.PASSES + 2) / 2) * 48,
		})
	end)
	-- REWARDS: three test tools, in the same place (one list open at a time)
	local rewards = UI.button({
		Name = "RewardTools",
		Text = "🎁 REWARDS ▸",
		BackgroundColor3 = UI.COLORS.panelTop,
		Parent = screenGui,
	})
	UI.maxText(rewards, 16)
	-- it scrolls: there are more tools than fit under the menu
	local tools = UI.make(Instance.new("ScrollingFrame"), {
		Name = "RewardToolList",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Visible = false,
		Parent = screenGui,
	})
	UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tools,
	})
	UI.onLayout(function()
		UI.place(rewards, row(4))
		local area = Layout.hud.test
		local top = math.min(area.y, Layout.area.Y * 0.2)
		local height = math.max(4 * 48, Layout.area.Y - top - LayoutMath.MARGIN)
		UI.place(tools, { x = area.x + area.w + LayoutMath.GAP, y = top, w = 228, h = height })
	end)
	local function showLists(passesOn: boolean, rewardsOn: boolean)
		list.Visible = passesOn
		tools.Visible = rewardsOn
		passes.Text = if passesOn then "🎟 PASSES ◂" else "🎟 PASSES ▸"
		rewards.Text = if rewardsOn then "🎁 REWARDS ◂" else "🎁 REWARDS ▸"
	end
	passes.Activated:Connect(function()
		UI.pop(passes)
		showLists(not list.Visible, false)
	end)
	rewards.Activated:Connect(function()
		UI.pop(rewards)
		showLists(false, not tools.Visible)
	end)
	for index, tool in
		{
			{ text = "📅 Next day", command = "nextDay" },
			{ text = "⏱ +5 min playtime", command = "playtime" },
			{ text = "🧹 Clear boosts", command = "clearBoosts" },
			{ text = "🌩️ Start Server Storm", command = "serverStorm" },
			{ text = "🔬 +500 research data", command = "researchData" },
			{ text = "✨ +100 Glints (this tier)", command = "glints" },
			{ text = "🌟 Force golden bolt", command = "goldenBolt" },
			{ text = "⛈ Supercell in 30 s", command = "supercell" },
		}
	do
		local toolButton = UI.button({
			Name = tool.command,
			LayoutOrder = if index > 6 then index + 4 else index,
			Text = tool.text,
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = UI.COLORS.panelDark,
			Parent = tools,
		})
		UI.maxText(toolButton, 16)
		toolButton.Activated:Connect(function()
			UI.pop(toolButton)
			devRemote:FireServer(tool.command)
		end)
	end
	-- Server goal +25%: as if you sold a quarter of the goal (four fill it
	-- and start a Server Surge)
	local goalButton = UI.button({
		Name = "ServerGoal",
		LayoutOrder = 14,
		Text = "⚡ Server goal +25%",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = UI.COLORS.panelDark,
		Parent = tools,
	})
	UI.maxText(goalButton, 16)
	goalButton.Activated:Connect(function()
		UI.pop(goalButton)
		devRemote:FireServer("serverGoal")
	end)
	-- Complete quest: your first unfinished quest counts as done (CLAIM it
	-- in REWARDS > QUESTS)
	local questButton = UI.button({
		Name = "CompleteQuest",
		LayoutOrder = 15,
		Text = "📋 Complete quest",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = UI.COLORS.panelDark,
		Parent = tools,
	})
	UI.maxText(questButton, 16)
	questButton.Activated:Connect(function()
		UI.pop(questButton)
		devRemote:FireServer("completeQuest")
	end)
	-- +Log entry: the next Storm Log entry counts as found (REWARDS > LOG)
	local logButton = UI.button({
		Name = "LogEntry",
		LayoutOrder = 16,
		Text = "📖 +Log entry",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = UI.COLORS.panelDark,
		Parent = tools,
	})
	UI.maxText(logButton, 16)
	logButton.Activated:Connect(function()
		UI.pop(logButton)
		devRemote:FireServer("logEntry")
	end)
	-- Ready to ascend: the top bottle and enough Volts (SHOP > BOTTLES > ASCEND)
	local ascendButton = UI.button({
		Name = "ReadyAscend",
		LayoutOrder = 17,
		Text = "🌟 Ready to ascend",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = UI.COLORS.panelDark,
		Parent = tools,
	})
	UI.maxText(ascendButton, 16)
	ascendButton.Activated:Connect(function()
		UI.pop(ascendButton)
		devRemote:FireServer("readyAscend")
	end)
	-- Restart tutorial: the new-player tutorial from step 1 again
	local tutorialButton = UI.button({
		Name = "RestartTutorial",
		LayoutOrder = 18,
		Text = "🎓 Restart tutorial",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = UI.COLORS.panelDark,
		Parent = tools,
	})
	UI.maxText(tutorialButton, 16)
	tutorialButton.Activated:Connect(function()
		UI.pop(tutorialButton)
		devRemote:FireServer("restartTutorial")
	end)
	-- Pretend friends: one more pretend friend in the server (0-3, then 0)
	local friendsButton = UI.button({
		Name = "PretendFriends",
		LayoutOrder = 19,
		Text = "👥 Pretend friends +1",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = UI.COLORS.panelDark,
		Parent = tools,
	})
	UI.maxText(friendsButton, 16)
	friendsButton.Activated:Connect(function()
		UI.pop(friendsButton)
		devRemote:FireServer("friends")
	end)
	-- Simulate idle 17 min (Studio only): runs the AFK idle handler, so the
	-- VirtualUser nudge and the server-hop backup can be checked
	if RunService:IsStudio() then
		local idle = UI.button({
			Name = "SimulateIdle",
			LayoutOrder = 8,
			Text = `💤 Simulate idle {Config.AFK.idleRejoinMinutes} min`,
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = UI.COLORS.panelDark,
			Parent = tools,
		})
		UI.maxText(idle, 16)
		idle.Activated:Connect(function()
			UI.pop(idle)
			AfkUI.simulateIdle()
		end)
	end
	-- Sound board (Studio only): every sound in order, its name in a toast
	-- (loops play for a few seconds); tap again to stop
	if RunService:IsStudio() then
		local board = UI.button({
			Name = "SoundBoard",
			LayoutOrder = 9,
			Text = "🔊 Sound board",
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = UI.COLORS.panelDark,
			Parent = tools,
		})
		UI.maxText(board, 16)
		local playing = 0
		board.Activated:Connect(function()
			UI.pop(board)
			playing += 1
			local mine = playing
			if mine % 2 == 0 then
				board.Text = "🔊 Sound board"
				return -- the second tap stops it
			end
			board.Text = "⏹ Stop sound board"
			task.spawn(function()
				for index, name in Sfx.names() do
					if playing ~= mine then
						return
					end
					local sound = Sfx.play(name)
					UI.toast(`🔊 {index}. {name}`, "info", 2)
					local length = Sfx.length(name)
					if sound and sound.Looped then
						task.wait(4)
						sound:Stop()
					else
						task.wait(length + 0.5)
					end
				end
				if playing == mine then
					playing += 1
					board.Text = "🔊 Sound board"
				end
			end)
		end)
	end
	-- Music audition (Studio only): every shortlisted track for 20 s with its
	-- name (docs/audio/music-shortlist.md); tap again to stop
	if RunService:IsStudio() then
		local audition = UI.button({
			Name = "MusicAudition",
			LayoutOrder = 10,
			Text = "🎵 Music audition",
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = UI.COLORS.panelDark,
			Parent = tools,
		})
		UI.maxText(audition, 16)
		audition.Activated:Connect(function()
			UI.pop(audition)
			Music.audition()
		end)
	end
	-- Pretend group member: the group bonus without joining (Systems/Group)
	local groupToggle = UI.button({
		Name = "PretendGroup",
		LayoutOrder = 7,
		Text = "",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = UI.COLORS.panelDark,
		Parent = tools,
	})
	UI.maxText(groupToggle, 16)
	local function showGroup()
		local on = player:GetAttribute("PretendGroup") == true
		groupToggle.Text = `👥 Group member: {if on then "ON" else "OFF"}`
		groupToggle.BackgroundColor3 = if on then UI.COLORS.green else UI.COLORS.panelDark
	end
	showGroup()
	player:GetAttributeChangedSignal("PretendGroup"):Connect(showGroup)
	groupToggle.Activated:Connect(function()
		UI.pop(groupToggle)
		devRemote:FireServer("group", player:GetAttribute("PretendGroup") ~= true)
	end)
	-- Pretend event: the first scheduled event (Config.EVENTS) is on
	local eventToggle = UI.button({
		Name = "PretendEvent",
		LayoutOrder = 13,
		Text = "",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = UI.COLORS.panelDark,
		Parent = tools,
	})
	UI.maxText(eventToggle, 16)
	local function showEvent()
		local on = workspace:GetAttribute(Weather.PRETEND_EVENT) == true
		eventToggle.Text = `🎉 Pretend event: {if on then "ON" else "OFF"}`
		eventToggle.BackgroundColor3 = if on then UI.COLORS.green else UI.COLORS.panelDark
	end
	showEvent()
	workspace:GetAttributeChangedSignal(Weather.PRETEND_EVENT):Connect(showEvent)
	eventToggle.Activated:Connect(function()
		UI.pop(eventToggle)
		devRemote:FireServer("event", workspace:GetAttribute(Weather.PRETEND_EVENT) ~= true)
	end)
	for index, pass in Config.PASSES do
		local attribute = `PretendPass_{pass.key}`
		local toggle = UI.button({
			Name = pass.key,
			LayoutOrder = index,
			Text = "",
			BackgroundColor3 = UI.COLORS.panelDark,
			Parent = list,
		})
		UI.maxText(toggle, 16)
		local function show()
			local on = player:GetAttribute(attribute) == true
			toggle.Text = `{pass.name}: {if on then "ON" else "OFF"}`
			toggle.BackgroundColor3 = if on then UI.COLORS.green else UI.COLORS.panelDark
		end
		show()
		player:GetAttributeChangedSignal(attribute):Connect(show)
		toggle.Activated:Connect(function()
			UI.pop(toggle)
			devRemote:FireServer("pass", pass.key, player:GetAttribute(attribute) ~= true)
		end)
	end
	-- a gift of a pass you don't have, through your own inbox (Systems/Gifts)
	local testGift = UI.button({
		Name = "TestGift",
		LayoutOrder = #Config.PASSES + 1,
		Text = "🎁 Send test gift to me",
		BackgroundColor3 = Color3.fromRGB(255, 120, 170),
		Parent = list,
	})
	UI.maxText(testGift, 16)
	testGift.Activated:Connect(function()
		UI.pop(testGift)
		devRemote:FireServer("testGift")
	end)
	-- a 2x Volts Boost gift, the same way
	local testBoost = UI.button({
		Name = "TestBoostGift",
		LayoutOrder = #Config.PASSES + 2,
		Text = "⚡ Send test boost gift",
		BackgroundColor3 = Color3.fromRGB(255, 120, 170),
		Parent = list,
	})
	UI.maxText(testBoost, 16)
	testBoost.Activated:Connect(function()
		UI.pop(testBoost)
		devRemote:FireServer("testGift", true)
	end)
end

return DevCommands
