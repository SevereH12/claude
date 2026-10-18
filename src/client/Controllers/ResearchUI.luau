--!strict
-- Research panel: one card per researcher with their perk, field data, a post
-- picker and a Hire button. Hiring and posting just ask the server, which
-- re-checks everything (including that you're standing in the Research Office).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Net = require(ReplicatedStorage.Shared.Net)
local ResearchMath = require(ReplicatedStorage.Shared.Util.Research)
local ResearchSites = require(ReplicatedStorage.Shared.Util.ResearchSites)
local Types = require(ReplicatedStorage.Shared.Types)
local ResearcherModels = require(script.Parent.Parent.Lib.ResearcherModels)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local COLORS = UI.COLORS

type Card = {
	def: Types.ResearcherDef,
	index: number,
	level: TextLabel,
	now: TextLabel,
	next: TextLabel,
	status: TextLabel,
	fill: Frame,
	barText: TextLabel,
	hire: TextButton,
	posts: { [string]: TextButton },
}

local ResearchUI = {}

local screenGui: ScreenGui
local panel: Frame
local cards: { Card } = {}
local hireRemote: RemoteEvent
local postRemote: RemoteEvent
local postIds: { string } = { "Office" }
local postNames: { [string]: string } = { Office = "Office" }
local knownLevels: { [string]: number } = {}

function ResearchUI.toggle()
	UI.togglePanel(panel)
end

local function perkText(def: Types.ResearcherDef, level: number): string
	return (string.gsub(def.perk, "{v}", tostring(ResearchMath.perkValue(def.id, level))))
end

local function inOffice(): boolean
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and ResearchSites.inOffice(root.Position)
end

local function render(snapshot: Types.Snapshot)
	local atOffice = inOffice()
	local now = workspace:GetServerTimeNow()
	for _, card in cards do
		local def = card.def
		local save = snapshot.researchers[def.id]
		local previous = Config.RESEARCHERS[card.index - 1]
		local unlocked = previous == nil or snapshot.researchers[previous.id] ~= nil

		if save then
			local nextAt = ResearchMath.nextThreshold(save.level)
			card.level.Text = `LV {save.level}`
			card.now.Text = perkText(def, save.level)
			card.next.Text = if nextAt
				then `Next (Lv {save.level + 1}): {perkText(def, save.level + 1)}`
				else "Max level"
			card.fill.Size =
				UDim2.fromScale(if nextAt then math.clamp(save.data / nextAt, 0, 1) else 1, 1)
			card.barText.Text = if nextAt
				then `{Format.abbreviate(save.data)} / {Format.abbreviate(nextAt)} data`
				else `{Format.abbreviate(save.data)} data`
			local readyIn = (snapshot.setupUntil[def.id] or 0) - now
			card.status.Text = if save.post == "Office"
				then "At the Research Office"
				elseif
					readyIn > 0
				then `Setting up in {postNames[save.post] or save.post}... {math.ceil(
					readyIn
				)}s`
				else `Working in {postNames[save.post] or save.post}`
			card.hire.Text = "HIRED"
			UI.setEnabled(card.hire, false, COLORS.green)
		else
			card.level.Text = "LV -"
			card.now.Text = perkText(def, 1)
			card.next.Text = ""
			card.fill.Size = UDim2.fromScale(0, 1)
			card.barText.Text = "Not hired"
			card.status.Text = if unlocked
				then (if atOffice then "Ready to hire" else "Visit the Research Office to hire")
				else `Hire {previous.name} first`
			card.hire.Text = `{Format.abbreviate(def.price)} ⚡`
			UI.setEnabled(
				card.hire,
				unlocked and atOffice and snapshot.volts >= def.price,
				COLORS.green
			)
		end

		for postId, button in card.posts do
			local selected = save ~= nil and save.post == postId
			UI.setEnabled(button, save ~= nil and not selected, COLORS.storm)
			if selected then
				button.BackgroundColor3 = COLORS.volt
			end
		end
	end
end

local function buildCard(list: Instance, index: number, def: Types.ResearcherDef)
	local frame = UI.make(Instance.new("Frame"), {
		Name = def.id,
		LayoutOrder = index,
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.panelDark,
		Parent = list,
	})
	UI.corner(frame, UDim.new(0, 12))
	UI.stroke(frame, 3)
	UI.padding(frame, 8)
	UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})

	local function row(order: number, height: number): Frame
		return UI.make(Instance.new("Frame"), {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, height),
			BackgroundTransparency = 1,
			Parent = frame,
		})
	end
	local function text(parent: Instance, props: { [string]: any }, max: number): TextLabel
		props.Parent = parent
		props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
		local label = UI.label(props)
		UI.maxText(label, max)
		return label
	end

	local titleRow = row(1, 28)
	text(titleRow, {
		Title = true,
		Text = string.upper(`{def.name} · {def.role}`),
		Size = UDim2.fromScale(0.75, 1),
	}, 24)
	local level = text(titleRow, {
		Title = true,
		Text = "LV -",
		TextColor3 = COLORS.volt,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.22, 1),
	}, 24)

	-- portrait on the left, perk and next-level text beside it
	local portraitRow = row(2, 64)
	local portrait = UI.make(Instance.new("ViewportFrame"), {
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = COLORS.stroke,
		BackgroundTransparency = 0.4,
		Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = Color3.fromRGB(255, 250, 235),
		Parent = portraitRow,
	})
	UI.corner(portrait, UDim.new(0, 8))
	local model = ResearcherModels.build(def.id)
	model.Parent = portrait
	local camera = Instance.new("Camera")
	local box, extent = model:GetBoundingBox()
	local fov = 35
	local reach = math.max(extent.X, extent.Y) / (2 * math.tan(math.rad(fov / 2)))
	camera.FieldOfView = fov
	camera.CFrame =
		CFrame.lookAt(box.Position + Vector3.new(0, 0, -(reach * 1.1 + extent.Z / 2)), box.Position)
	camera.Parent = portrait
	portrait.CurrentCamera = camera

	local now = text(portraitRow, {
		Text = "",
		Position = UDim2.new(0, 72, 0, 0),
		Size = UDim2.new(1, -72, 0.55, 0),
	}, 16)
	local next = text(portraitRow, {
		Text = "",
		TextColor3 = COLORS.subtext,
		Position = UDim2.new(0, 72, 0.55, 0),
		Size = UDim2.new(1, -72, 0.45, 0),
	}, 14)

	local bar = row(4, 18)
	bar.BackgroundTransparency = 0
	bar.BackgroundColor3 = COLORS.stroke
	UI.corner(bar, UDim.new(0.5, 0))
	local clip = UI.make(Instance.new("CanvasGroup"), {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = bar,
	})
	UI.corner(clip, UDim.new(0.5, 0))
	local fill = UI.make(Instance.new("Frame"), {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLORS.storm,
		BorderSizePixel = 0,
		Parent = clip,
	})
	local barText = text(bar, {
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
	}, 13)

	local status = text(row(5, 18), {
		Text = "",
		TextColor3 = COLORS.calm,
		Size = UDim2.fromScale(1, 1),
	}, 14)

	-- post picker: Office plus each zone in Config order
	local picker = UI.make(Instance.new("Frame"), {
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = frame,
	})
	UI.make(Instance.new("UIGridLayout"), {
		CellSize = UDim2.new(0.32, 0, 0, 28),
		CellPadding = UDim2.fromOffset(4, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = picker,
	})
	local posts: { [string]: TextButton } = {}
	for order, postId in postIds do
		local button = UI.button({
			Name = postId,
			Text = string.upper(postNames[postId]),
			LayoutOrder = order,
			BackgroundColor3 = COLORS.storm,
			Parent = picker,
		})
		UI.maxText(button, 16)
		button.Activated:Connect(function()
			local save = if State.current then State.current.researchers[def.id] else nil
			if save and save.post ~= postId then
				UI.pop(button)
				postRemote:FireServer(def.id, postId)
			end
		end)
		posts[postId] = button
	end

	local hire = UI.button({
		Name = "Hire",
		Text = "...",
		LayoutOrder = 7,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = COLORS.green,
		Parent = frame,
	})
	UI.maxText(hire, 22)
	hire.Activated:Connect(function()
		local snapshot = State.current
		if snapshot and not snapshot.researchers[def.id] and inOffice() then
			UI.pop(hire)
			hireRemote:FireServer(def.id)
		end
	end)

	table.insert(cards, {
		def = def,
		index = index,
		level = level,
		now = now,
		next = next,
		status = status,
		fill = fill,
		barText = barText,
		hire = hire,
		posts = posts,
	})
end

local function showToast(def: Types.ResearcherDef, level: number)
	local toast = UI.panel({
		Name = "LevelToast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -60),
		Size = UDim2.fromScale(0.34, 0.07),
		Parent = screenGui,
	})
	UI.sizeLimits(toast, Vector2.new(240, 44), Vector2.new(420, 60))
	local label = UI.label({
		Title = true,
		Text = `{string.upper(def.name)} reached LV {level}!`,
		TextColor3 = COLORS.volt,
		Position = UDim2.fromScale(0.04, 0.1),
		Size = UDim2.fromScale(0.92, 0.8),
		Parent = toast,
	})
	UI.maxText(label, 26)
	TweenService:Create(toast, UI.TWEEN.open, { Position = UDim2.new(0.5, 0, 0, 90) }):Play()
	task.delay(3, function()
		local out =
			TweenService:Create(toast, UI.TWEEN.fast, { Position = UDim2.new(0.5, 0, 0, -60) })
		out.Completed:Once(function()
			toast:Destroy()
		end)
		out:Play()
	end)
end

-- The server publishes "<post>:<level>" in Research_<RoleId> on the player;
-- a rising level is a level-up (the first value we see is just loading in).
local function watchLevels()
	local player = Players.LocalPlayer
	for _, def in Config.RESEARCHERS do
		local name = `Research_{def.id}`
		local function check()
			local value = player:GetAttribute(name)
			local level = if typeof(value) == "string"
				then tonumber(string.match(value, ":(%d+)$"))
				else nil
			if not level then
				return
			end
			local before = knownLevels[def.id]
			knownLevels[def.id] = level
			if before and level > before then
				showToast(def, level)
			end
		end
		check()
		player:GetAttributeChangedSignal(name):Connect(check)
	end
end

function ResearchUI.init()
	hireRemote = Net.get("HireResearcher")
	postRemote = Net.get("PostResearcher")
	for _, zone in Formulas.sortedZones() do
		table.insert(postIds, zone.id)
		postNames[zone.id] = zone.displayName
	end

	screenGui = UI.make(Instance.new("ScreenGui"), {
		Name = "StormBottlerResearch",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	panel = UI.panel({
		Name = "ResearchPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.74),
		Visible = false,
		Parent = screenGui,
	})
	UI.sizeLimits(panel, Vector2.new(340, 320), Vector2.new(640, 640))

	local header = UI.make(Instance.new("Frame"), {
		Name = "Header",
		Size = UDim2.fromScale(1, 0.12),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = panel,
	})
	UI.corner(header, UDim.new(0, 14))
	UI.gradient(header, COLORS.storm, COLORS.stormDeep)
	local title = UI.label({
		Title = true,
		Text = "🔬 STORM SOCIETY",
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.05, 0.15),
		Size = UDim2.fromScale(0.7, 0.7),
		Parent = header,
	})
	UI.maxText(title, 36)
	local close = UI.button({
		Name = "Close",
		Text = "X",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.975, 0.5),
		Size = UDim2.fromScale(0.75, 0.75),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = COLORS.red,
		Parent = header,
	})
	close.Activated:Connect(ResearchUI.toggle)

	local hint = UI.label({
		Text = "Hire at the Research Office, then post them at a zone. They work while you play there.",
		TextColor3 = COLORS.subtext,
		Position = UDim2.fromScale(0.05, 0.135),
		Size = UDim2.fromScale(0.9, 0.05),
		Parent = panel,
	})
	UI.maxText(hint, 16)

	local list = UI.make(Instance.new("ScrollingFrame"), {
		Name = "List",
		Position = UDim2.fromScale(0.04, 0.2),
		Size = UDim2.fromScale(0.92, 0.78),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = panel,
	})
	UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	UI.make(Instance.new("UIPadding"), {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		Parent = list,
	})
	for index, def in Config.RESEARCHERS do
		buildCard(list, index, def)
	end
	watchLevels()
end

function ResearchUI.start()
	if State.current then
		render(State.current)
	end
	State.Changed:Connect(render)
	-- standing in the office and set-up countdowns change without a snapshot
	while true do
		task.wait(0.25)
		if panel.Visible and State.current then
			render(State.current)
		end
	end
end

return ResearchUI
