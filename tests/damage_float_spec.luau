-- Unit tests for the pure damage-float label helper.
--
-- These tests do not create Instances. They do not cover BillboardGui,
-- TweenService, Adornee lookup, Destroy, or connection cleanup. Those are
-- Studio smoke checks.

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	local DamageFloat = require("../src/ReplicatedStorage/Shared/Combat/DamageFloat")

	local function numbersIn(text: string): { string }
		local found = {}
		for run in string.gmatch(text, "%d+%.?%d*") do
			table.insert(found, run)
		end
		return found
	end

	test("non-hit payloads produce no label", function()
		eq(DamageFloat.normalizeHit(nil), nil)
		eq(DamageFloat.normalizeHit("Hit"), nil)
		eq(DamageFloat.normalizeHit({ Kind = "Evaded", Damage = 10 }), nil)
		eq(DamageFloat.normalizeHit({ Kind = "Killed", Damage = 10 }), nil)
		eq(DamageFloat.normalizeHit({ Kind = "hit", Damage = 10 }), nil)
		eq(DamageFloat.normalizeHit({ Action = "Attack", Slot = "MainHand", AttackId = "Primary", Damage = 999 }), nil)
	end)

	test("malformed damage is ignored", function()
		eq(DamageFloat.normalizeHit({ Kind = "Hit" }), nil)
		eq(DamageFloat.normalizeHit({ Kind = "Hit", Damage = "12" }), nil)
		eq(DamageFloat.normalizeHit({ Kind = "Hit", Damage = 0 / 0 }), nil)
		eq(DamageFloat.normalizeHit({ Kind = "Hit", Damage = math.huge }), nil)
		eq(DamageFloat.normalizeHit({ Kind = "Hit", Damage = -math.huge }), nil)
		eq(DamageFloat.normalizeHit({ Kind = "Hit", Damage = -1 }), nil)
	end)

	test("a server hit shows that damage and no other number", function()
		local display = DamageFloat.normalizeHit({
			Kind = "Hit",
			Damage = 12,
			Target = "not-validated-here",
			Reflected = 40,
			GuardBroken = true,
			Raw = 80,
		})
		assert(display ~= nil, "display")
		eq(display.Damage, 12, "Damage")
		eq(display.Blocked, nil, "Blocked")
		eq(display.Absorbed, nil, "Absorbed")
		eq(display.Text, "12", "Text")
		eq(display.Tone, "Damage", "Tone")
		local numbers = numbersIn(display.Text)
		eq(#numbers, 1, "number count")
		eq(numbers[1], "12", "shown number")
	end)

	test("fractional server damage is not rounded to another integer", function()
		local display = DamageFloat.normalizeHit({ Kind = "Hit", Damage = 12.5 })
		assert(display ~= nil, "display")
		eq(display.Text, "12.5", "Text")
		eq(numbersIn(display.Text)[1], "12.5", "shown number")
	end)

	test("over-time hits with only Damage still show that damage", function()
		local display = DamageFloat.normalizeHit({ Kind = "Hit", Damage = 3, OverTime = true })
		assert(display ~= nil, "display")
		eq(display.Text, "3", "Text")
		eq(display.Tone, "Damage", "Tone")
		eq(display.Blocked, nil, "Blocked")
		eq(display.Absorbed, nil, "Absorbed")
	end)

	test("full block keeps the server zero and does not invent the blocked amount", function()
		local display = DamageFloat.normalizeHit({ Kind = "Hit", Damage = 0, Blocked = 9, Absorbed = 0 })
		assert(display ~= nil, "display")
		eq(display.Text, "0 Block", "Text")
		eq(display.Tone, "FullBlock", "Tone")
		eq(display.Blocked, 9, "Blocked")
		eq(numbersIn(display.Text)[1], "0", "shown number")
		eq(#numbersIn(display.Text), 1, "number count")
	end)

	test("partial block labels the server damage without summing mitigation", function()
		local display = DamageFloat.normalizeHit({ Kind = "Hit", Damage = 4, Blocked = 9 })
		assert(display ~= nil, "display")
		eq(display.Text, "4 Block", "Text")
		eq(display.Tone, "PartialBlock", "Tone")
		eq(numbersIn(display.Text)[1], "4", "shown number")
		assert(string.find(display.Text, "9", 1, true) == nil, "blocked amount is not printed as a second number")
		assert(string.find(display.Text, "13", 1, true) == nil, "no derived total")
	end)

	test("absorb labels use only the provided absorb field", function()
		local full = DamageFloat.normalizeHit({ Kind = "Hit", Damage = 0, Absorbed = 6 })
		assert(full ~= nil, "full")
		eq(full.Text, "0 Absorb", "full text")
		eq(full.Tone, "Absorb", "full tone")
		local partial = DamageFloat.normalizeHit({ Kind = "Hit", Damage = 2, Absorbed = 6, Blocked = 0 })
		assert(partial ~= nil, "partial")
		eq(partial.Text, "2 Absorb", "partial text")
		eq(partial.Tone, "PartialAbsorb", "partial tone")
		eq(#numbersIn(partial.Text), 1, "number count")
	end)

	test("block and absorb together stay labels on the server damage", function()
		local display = DamageFloat.normalizeHit({ Kind = "Hit", Damage = 1, Blocked = 2, Absorbed = 3 })
		assert(display ~= nil, "display")
		eq(display.Text, "1 Block Absorb", "Text")
		eq(display.Tone, "PartialBlock", "Tone")
		eq(#numbersIn(display.Text), 1, "number count")
		local stopped = DamageFloat.normalizeHit({ Kind = "Hit", Damage = 0, Blocked = 2, Absorbed = 3 })
		assert(stopped ~= nil, "stopped")
		eq(stopped.Text, "0 Block Absorb", "stopped text")
		eq(stopped.Tone, "FullBlock", "stopped tone")
	end)

	test("bad block or absorb fields reject the whole event", function()
		eq(DamageFloat.normalizeHit({ Kind = "Hit", Damage = 5, Blocked = "full" }), nil)
		eq(DamageFloat.normalizeHit({ Kind = "Hit", Damage = 5, Blocked = 0 / 0 }), nil)
		eq(DamageFloat.normalizeHit({ Kind = "Hit", Damage = 5, Blocked = -2 }), nil)
		eq(DamageFloat.normalizeHit({ Kind = "Hit", Damage = 5, Absorbed = math.huge }), nil)
		eq(DamageFloat.normalizeHit({ Kind = "Hit", Damage = 5, Absorbed = -1 }), nil)
	end)

	test("tone colors stay distinct and unknown tones have none", function()
		local damage = DamageFloat.toneRgb("Damage")
		local blocked = DamageFloat.toneRgb("FullBlock")
		local absorb = DamageFloat.toneRgb("Absorb")
		assert(damage ~= nil and blocked ~= nil and absorb ~= nil, "colors")
		eq(damage[1], 255, "damage red")
		assert(damage[1] ~= blocked[1] or damage[2] ~= blocked[2], "block differs")
		assert(damage[3] ~= absorb[3], "absorb differs")
		eq(DamageFloat.toneRgb("Crit"), nil)
	end)

	test("simultaneous labels stay capped by retiring the oldest slots", function()
		eq(DamageFloat.MAX_SIMULTANEOUS, 8, "cap")
		eq(DamageFloat.LIFETIME_SECONDS, 0.8, "lifetime")
		assert(DamageFloat.LIFETIME_SECONDS > 0 and DamageFloat.LIFETIME_SECONDS < 2, "short lifetime")
		eq(DamageFloat.slotsToRetire(0), 0, "empty")
		eq(DamageFloat.slotsToRetire(7), 0, "one free slot")
		eq(DamageFloat.slotsToRetire(8), 1, "at cap")
		eq(DamageFloat.slotsToRetire(10), 3, "over cap")
		eq(DamageFloat.slotsToRetire(-1), nil, "negative")
		eq(DamageFloat.slotsToRetire(1.5), nil, "fraction")
		eq(DamageFloat.slotsToRetire(math.huge), nil, "infinite")
	end)
end
