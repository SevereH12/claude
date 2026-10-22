--!nocheck
-- The toast queue behind UI.toast (client/Lib/ToastQueue), with a fake clock.
--   lune run tools/harness/test_toast.luau
local World = require("./World")

local world = World.new("src")
local ToastQueue = world:require("StarterPlayer.StarterPlayerScripts.Client.Lib.ToastQueue")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local t = 0
local function clock()
	return t
end
local function texts(queue)
	local out = {}
	for _, entry in ToastQueue.active(queue) do
		table.insert(out, entry.text)
	end
	return table.concat(out, ",")
end

-- a toast expires
local q = ToastQueue.new(clock, 2)
local a = ToastQueue.push(q, "A", "info", 3)
check(texts(q) == "A", "a new toast is up")
t = 2.9
check(not ToastQueue.hide(q, a.id, a.generation), "it isn't hidden early")
t = 3
check(ToastQueue.hide(q, a.id, a.generation), "its own hide takes it down on time")
check(texts(q) == "", "and it's gone")

-- the same text restarts its timer instead of stacking
t = 10
q = ToastQueue.new(clock, 2)
local first = ToastQueue.push(q, "Bottle full", "warn", 3)
t = 12
local again, evicted = ToastQueue.push(q, "Bottle full", "warn", 3)
check(again.id == first.id, "the same text reuses its toast")
check(#evicted == 0 and texts(q) == "Bottle full", "and doesn't stack")
t = 13
check(not ToastQueue.hide(q, first.id, first.generation), "the first show's hide is stale")
check(texts(q) == "Bottle full", "so it stays up after its first 3 seconds")
t = 15
check(ToastQueue.hide(q, again.id, again.generation), "the restarted timer takes it down")

-- at most two at once: the oldest goes first
t = 20
q = ToastQueue.new(clock, 2)
local one = ToastQueue.push(q, "one", "info", 3)
ToastQueue.push(q, "two", "info", 3)
local _, pushedOut = ToastQueue.push(q, "three", "info", 3)
check(texts(q) == "two,three", "a third toast leaves the newest two")
check(#pushedOut == 1 and pushedOut[1].id == one.id, "and pushes the oldest out")

-- an old hide can't hide a newer toast
t = 30
q = ToastQueue.new(clock, 2)
local old = ToastQueue.push(q, "Mesa locked", "warn", 3)
t = 33
check(ToastQueue.hide(q, old.id, old.generation), "the old toast goes")
local newer = ToastQueue.push(q, "Mesa locked", "warn", 3)
check(newer.id ~= old.id, "showing it again later is a new toast")
check(ToastQueue.hide(q, old.id, old.generation), "a late duplicate of the old hide only reports it gone")
check(texts(q) == "Mesa locked", "and the newer toast stays up")
t = 35
local restarted = ToastQueue.push(q, "Mesa locked", "warn", 3)
t = 36
check(not ToastQueue.hide(q, newer.id, newer.generation), "the newer toast's first hide is stale after a restart")
check(texts(q) == "Mesa locked", "so the restarted toast stays")
t = 38
check(ToastQueue.hide(q, restarted.id, restarted.generation), "its current hide takes it down")

-- expired toasts drop out even if their hide hasn't run yet
t = 50
q = ToastQueue.new(clock, 2)
local quiet = ToastQueue.push(q, "quiet", "info", 3)
t = 60
check(texts(q) == "", "an expired toast isn't listed")
check(ToastQueue.hide(q, quiet.id, quiet.generation), "and its late hide still clears its frame")

-- a tapped toast (one with an action) goes at once
t = 70
q = ToastQueue.new(clock, 2)
local tapped = ToastQueue.push(q, "tap me", "info", 5)
ToastQueue.dismiss(q, tapped.id)
check(texts(q) == "", "a tapped toast goes at once")
check(ToastQueue.hide(q, tapped.id, tapped.generation), "and its timer's hide finds nothing left")

if failures > 0 then
	error(`{failures} toast checks failed`)
end
print("toast checks passed")
