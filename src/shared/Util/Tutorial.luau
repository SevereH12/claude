--!strict
-- The new-player tutorial's rules, as pure maths (Systems/Tutorial runs it,
-- Controllers/Tutorial shows it, tools/harness/test_social.luau tests it).
-- Its steps follow the onboarding funnel (Systems/Analytics):
--   1 WALK   walk to the first zone (Config.TUTORIAL.zone)
--   2 CATCH  catch Config.TUTORIAL.catches bolts
--   3 SELL   fill the bottle, then take it to the sell pad
--   4 BUY    open the menu, the SHOP, and buy the next bottle (the Vial)
--   then FINISHED: "You're a Storm Bottler!" and the reward; the saved
--   step goes to DONE.
-- Doing a later step early skips ahead (selling before 3 catches is fine).
-- The step is saved in the profile (profile.tutorialStep), so it carries on
-- after a rejoin; the catch count isn't (step 2 counts again from 0).

local Config = require(script.Parent.Parent.Config)

local Tutorial = {}

Tutorial.DONE = 0 -- finished or skipped: nothing shows
Tutorial.WALK = 1
Tutorial.CATCH = 2
Tutorial.SELL = 3
Tutorial.BUY = 4
Tutorial.FINISHED = 5 -- only for a moment: the reward is paid, then DONE

-- What happened: entered a zone, caught a bolt, the bottle is full, sold,
-- bought a bottle.
export type Event = "zone" | "caught" | "full" | "sold" | "bottle"

-- Where a player is: the step and, in step 2, the bolts caught so far.
export type Progress = { step: number, caught: number }

-- Profiles that never see it: anyone who has owned a Vial or better (an
-- Ascension resets the bottle, so ascended players count too).
function Tutorial.isOldPlayer(profile: { bottleTier: number, ascension: number }): boolean
	return profile.bottleTier >= 2 or profile.ascension > 0
end

-- The step a profile starts at when it loads: DONE for old players,
-- otherwise the saved step (a real step, or DONE).
function Tutorial.loadStep(
	profile: { bottleTier: number, ascension: number, tutorialStep: any }
): number
	local step = profile.tutorialStep
	if Tutorial.isOldPlayer(profile) then
		return Tutorial.DONE
	end
	if typeof(step) ~= "number" or step ~= math.floor(step) then
		return Tutorial.DONE
	end
	if step < Tutorial.WALK or step > Tutorial.BUY then
		return Tutorial.DONE
	end
	return step
end

-- Is the tutorial showing at this step?
function Tutorial.isActive(step: number): boolean
	return step >= Tutorial.WALK and step <= Tutorial.BUY
end

-- The progress after `event`. FINISHED means pay the reward.
function Tutorial.advance(progress: Progress, event: Event): Progress
	local step, caught = progress.step, progress.caught
	if not Tutorial.isActive(step) then
		return progress
	end
	if event == "bottle" then
		return { step = Tutorial.FINISHED, caught = caught }
	elseif event == "sold" then
		if step < Tutorial.BUY then
			return { step = Tutorial.BUY, caught = caught }
		end
	elseif event == "full" then
		if step < Tutorial.SELL then
			return { step = Tutorial.SELL, caught = caught }
		end
	elseif event == "caught" then
		if step <= Tutorial.CATCH then
			caught += 1
			if caught >= Config.TUTORIAL.catches then
				return { step = Tutorial.SELL, caught = caught }
			end
			return { step = Tutorial.CATCH, caught = caught }
		end
	elseif event == "zone" then
		if step == Tutorial.WALK then
			return { step = Tutorial.CATCH, caught = caught }
		end
	end
	return progress
end

-- SKIP (after "Skip the tutorial?"): straight to DONE, with no reward.
function Tutorial.skip(_progress: Progress): Progress
	return { step = Tutorial.DONE, caught = 0 }
end

-- The Studio TEST button: from the start again.
function Tutorial.restart(): Progress
	return { step = Tutorial.WALK, caught = 0 }
end

-- The step card's one line (`calm`: the storm is over, step 2 explains the
-- timer; `full`: the bottle is full; `secondsLeft`: until the storm;
-- `nextBottle`: the bottle to buy; `canAfford`: they have the Volts).
export type CardInfo = {
	calm: boolean,
	secondsLeft: number,
	caught: number,
	full: boolean,
	nextBottle: string,
	price: number,
	volts: number,
}

function Tutorial.cardText(step: number, info: CardInfo): string
	if step == Tutorial.WALK then
		return `Follow the glowing path to {Config.ZONES[Config.TUTORIAL.zone].displayName}`
	elseif step == Tutorial.CATCH then
		if info.calm then
			local s = math.max(0, math.ceil(info.secondsLeft))
			return string.format(
				"It's calm. The storm timer (top left) says it's back in %d:%02d",
				s // 60,
				s % 60
			)
		end
		return `Run to where lightning strikes to catch it! ({info.caught}/{Config.TUTORIAL.catches})`
	elseif step == Tutorial.SELL then
		if info.full then
			return "Bottle full! Follow the path to the sell pad"
		end
		return "Keep catching until your bottle is full"
	elseif step == Tutorial.BUY then
		if info.volts < info.price then
			return `Catch and sell to save up for the {info.nextBottle}: {math.floor(info.volts)} / {info.price} ⚡`
		end
		return `Open the MENU, then the SHOP, and buy the {info.nextBottle}`
	elseif step == Tutorial.FINISHED then
		return "You're a Storm Bottler!"
	end
	return ""
end

return Tutorial
