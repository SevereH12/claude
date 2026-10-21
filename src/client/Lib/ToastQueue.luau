--!strict
-- The bookkeeping behind UI.toast, with no Roblox UI in it so the harness
-- can test it with a fake clock (tools/harness/test_toast.luau):
--   * every toast expires `seconds` after it was last shown
--   * showing text that's already up restarts its timer instead of stacking
--   * at most `max` at once: a new one pushes the oldest out
--   * every show bumps a generation number; a hide only works if it names
--     the generation it was scheduled for, so an old hide can't touch a
--     newer message

export type Entry = {
	id: number, -- one per toast on screen (a re-shown text keeps its id)
	text: string,
	kind: string,
	generation: number,
	expires: number, -- clock time it goes
}

export type Queue = {
	entries: { Entry }, -- oldest first
	max: number,
	now: () -> number,
	nextId: number,
	nextGeneration: number,
}

local ToastQueue = {}

function ToastQueue.new(now: () -> number, max: number?): Queue
	return { entries = {}, max = max or 2, now = now, nextId = 1, nextGeneration = 1 }
end

-- Drops toasts whose time is up (as if their hides had run).
local function prune(queue: Queue)
	local t = queue.now()
	for i = #queue.entries, 1, -1 do
		if queue.entries[i].expires <= t then
			table.remove(queue.entries, i)
		end
	end
end

-- Shows `text`. Returns the entry to show (new, or the same text restarted)
-- and the entries pushed out to make room.
function ToastQueue.push(
	queue: Queue,
	text: string,
	kind: string,
	seconds: number
): (Entry, { Entry })
	prune(queue)
	local generation = queue.nextGeneration
	queue.nextGeneration += 1
	local expires = queue.now() + seconds
	for _, entry in queue.entries do
		if entry.text == text then
			entry.kind = kind
			entry.generation = generation
			entry.expires = expires
			return entry, {}
		end
	end
	local entry: Entry = {
		id = queue.nextId,
		text = text,
		kind = kind,
		generation = generation,
		expires = expires,
	}
	queue.nextId += 1
	table.insert(queue.entries, entry)
	local evicted: { Entry } = {}
	while #queue.entries > queue.max do
		table.insert(evicted, table.remove(queue.entries, 1) :: Entry)
	end
	return entry, evicted
end

-- A scheduled hide for toast `id` at `generation`: true when that toast
-- should leave the screen now (its time is up, or it already went). False
-- when it was shown again since (a newer generation) or isn't due yet.
-- Ids are never reused, so this can't hide a different, newer toast.
function ToastQueue.hide(queue: Queue, id: number, generation: number): boolean
	for i, entry in queue.entries do
		if entry.id == id then
			if entry.generation ~= generation or entry.expires > queue.now() + 1e-6 then
				return false
			end
			table.remove(queue.entries, i)
			return true
		end
	end
	return true
end

-- The toasts on screen now, oldest first.
function ToastQueue.active(queue: Queue): { Entry }
	prune(queue)
	return queue.entries
end

return ToastQueue
