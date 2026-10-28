--!strict
-- Friends and invites, as pure rules (Systems/Friends and Systems/Invites
-- use them; tools/harness/test_social.luau tests them).
--
--   Friends boost: each Roblox friend in your server adds
--     Config.FRIENDS.perFriend Volts on every sale, counting up to
--     Config.FRIENDS.max of them (Util/Passes applies it).
--   Invites: when a brand-new player (no saved profile yet) joins from an
--     invite, they get a welcome gift; the inviter gets a reward, but only
--     if the new player's account is old enough, once the new player has
--     really played (Social.inviteEarned), and if the inviter hasn't had
--     Config.INVITES.dailyCap rewarded invites already today (UTC).

local Config = require(script.Parent.Parent.Config)
local Stats = require(script.Parent.Stats)

local Social = {}

-- How many friends count for the boost (0 to Config.FRIENDS.max).
function Social.countedFriends(present: number): number
	return math.clamp(math.floor(present), 0, Config.FRIENDS.max)
end

-- The boost's extra: 0.05 per counted friend (3 friends = +0.15).
function Social.friendsBonus(present: number): number
	return Social.countedFriends(present) * Config.FRIENDS.perFriend
end

-- The HUD chip: "👥 +10% friends", or "" with no friends here.
function Social.chipText(present: number): string
	local counted = Social.countedFriends(present)
	if counted <= 0 then
		return ""
	end
	return `👥 +{math.round(Social.friendsBonus(counted) * 100)}% friends`
end

-- Who joined, as the invite rules need it.
export type Join = {
	isNew: boolean, -- no saved profile before this visit
	userId: number,
	referrerId: any, -- Player:GetJoinData().ReferredByPlayerId (anything)
	accountAge: number, -- Player.AccountAge, in days
}

-- Why a join gets nothing from an invite, or nil if it's a real invite of
-- a new player: "notInvited", "notNew" or "self".
function Social.welcomeRefusal(join: Join): string?
	local referrer = join.referrerId
	if typeof(referrer) ~= "number" or referrer ~= math.floor(referrer) or referrer <= 0 then
		return "notInvited"
	end
	if not join.isNew then
		return "notNew"
	end
	if referrer == join.userId then
		return "self"
	end
	return nil
end

-- Why the inviter gets no reward for this join (before the daily cap), or
-- nil: the welcome refusals, plus "tooYoung" for an account under
-- Config.INVITES.minAccountAgeDays days old.
function Social.inviterRefusal(join: Join): string?
	local refusal = Social.welcomeRefusal(join)
	if refusal then
		return refusal
	end
	if join.accountAge < Config.INVITES.minAccountAgeDays then
		return "tooYoung"
	end
	return nil
end

-- Has the invited player played enough for their inviter to be paid?
-- Config.INVITES.playMinutes minutes in all, or a first sale (`lifetime`:
-- their lifetime stat counters, Util/Stats).
function Social.inviteEarned(lifetime: { [string]: number }): boolean
	return (lifetime[Stats.PLAYTIME_MINUTES] or 0) >= Config.INVITES.playMinutes
		or (lifetime[Stats.SALES] or 0) >= 1
end

-- An inviter's saved count (DataStore StormBottler_Invites): the UTC day
-- and who was rewarded for that day.
export type InviteRecord = { day: number, ids: { number } }

-- Counts `newUserId` as one of today's rewarded invites: the record to
-- save and true, or the record unchanged and false (today's cap is
-- reached, or this player was counted already). A new day starts at 0.
function Social.countInvite(record: any, today: number, newUserId: number): (InviteRecord, boolean)
	local ids: { number } = {}
	if typeof(record) == "table" and record.day == today and typeof(record.ids) == "table" then
		for _, id in record.ids do
			if typeof(id) == "number" then
				table.insert(ids, id)
			end
		end
	end
	local current: InviteRecord = { day = today, ids = ids }
	if table.find(ids, newUserId) or #ids >= Config.INVITES.dailyCap then
		return current, false
	end
	local updated = table.clone(ids)
	table.insert(updated, newUserId)
	return { day = today, ids = updated }, true
end

-- The inviter's reward's gift inbox id: one per new player, so it can only
-- ever arrive once.
function Social.inviteGiftId(newUserId: number): string
	return `invite-{newUserId}`
end

return Social
