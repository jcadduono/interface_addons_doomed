local ADDON = 'Doomed'
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

BINDING_CATEGORY_DOOMED = ADDON
BINDING_NAME_DOOMED_TARGETMORE = "Toggle Targets +"
BINDING_NAME_DOOMED_TARGETLESS = "Toggle Targets -"
BINDING_NAME_DOOMED_TARGET1 = "Set Targets to 1"
BINDING_NAME_DOOMED_TARGET2 = "Set Targets to 2"
BINDING_NAME_DOOMED_TARGET3 = "Set Targets to 3"
BINDING_NAME_DOOMED_TARGET4 = "Set Targets to 4"
BINDING_NAME_DOOMED_TARGET5 = "Set Targets to 5+"

local function log(...)
	print(ADDON, '-', ...)
end

if select(2, UnitClass('player')) ~= 'WARLOCK' then
	log('[|cFFFF0000Error|r]', 'Not loading because you are not the correct class! Consider disabling', ADDON, 'for this character.')
	return
end

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local ceil = math.ceil
local floor = math.floor
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetShapeshiftForm = _G.GetShapeshiftForm
local GetSpellCharges = _G.GetSpellCharges
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local UnitAura = _G.UnitAura
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitSpellHaste = _G.UnitSpellHaste
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function clamp(n, min, max)
	return (n < min and min) or (n > max and max) or n
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

Doomed = {}
local Opt -- use this as a local table reference to Doomed

SLASH_Doomed1, SLASH_Doomed2 = '/doom', '/doomed'

local function InitOpts()
	local function SetDefaults(t, ref)
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(Doomed, { -- defaults
		locked = false,
		snap = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
			interrupt = 0.4,
			extra = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			extra = true,
			blizzard = false,
			animation = false,
			color = { r = 1, g = 1, b = 1 },
		},
		hide = {
			affliction = false,
			demonology = false,
			destruction = false,
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		cd_ttd = 10,
		pot = false,
		trinket = true,
		healthstone = true,
		pet_count = 'imps',
		tyrant = true,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local Events = {}

-- player ability template
local Ability = {}
Ability.__index = Ability

-- classified player abilities
local Abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

-- summoned pet template
local SummonedPet = {}
SummonedPet.__index = SummonedPet

-- classified summoned pets
local SummonedPets = {
	all = {},
	known = {},
	byUnitId = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- timers for updating combat/display/hp info
local Timer = {
	combat = 0,
	display = 0,
	health = 0,
}

-- specialization constants
local SPEC = {
	NONE = 0,
	AFFLICTION = 1,
	DEMONOLOGY = 2,
	DESTRUCTION = 3,
}

-- action priority list container
local APL = {
	[SPEC.NONE] = {},
	[SPEC.AFFLICTION] = {},
	[SPEC.DEMONOLOGY] = {},
	[SPEC.DESTRUCTION] = {},
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	spec = 0,
	group_size = 1,
	target_mode = 0,
	gcd = 1.5,
	gcd_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	movement_speed = 100,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	mana = {
		base = 0,
		current = 0,
		max = 100,
		pct = 100,
		regen = 0,
	},
	soul_shards = {
		current = 0,
		max = 5,
		deficit = 5,
		max_spend = 5,
		fragments = 0,
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	channel = {
		chained = false,
		start = 0,
		ends = 0,
		remains = 0,
		tick_count = 0,
		tick_interval = 0,
		ticks = 0,
		ticks_remain = 0,
		ticks_extra = 0,
		interruptible = false,
		early_chainable = false,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		last_taken = 0,
	},
	set_bonus = {
		t29 = 0, -- Scalesworn Cultist's Habit
		t30 = 0, -- Sinister Savant's Cursethreads
		t31 = 0, -- Devout Ashdevil's Pactweave
		t32 = 0, -- Sinister Savant's Cursethreads (Awakened)
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[190958] = true, -- Soleah's Secret Technique
		[193757] = true, -- Ruby Whelp Shell
		[202612] = true, -- Screaming Black Dragonscale
		[203729] = true, -- Ominous Chromatic Essence
	},
	main_freecast = false,
	dot_count = 0,
}

-- base mana pool max for each level
Player.BaseMana = {
	260,	270,	285,	300,	310,	--  5
	330,	345,	360,	380,	400,	-- 10
	430,	465,	505,	550,	595,	-- 15
	645,	700,	760,	825,	890,	-- 20
	965,	1050,	1135,	1230,	1335,	-- 25
	1445,	1570,	1700,	1845,	2000,	-- 30
	2165,	2345,	2545,	2755,	2990,	-- 35
	3240,	3510,	3805,	4125,	4470,	-- 40
	4845,	5250,	5690,	6170,	6685,	-- 45
	7245,	7855,	8510,	9225,	10000,	-- 50
	11745,	13795,	16205,	19035,	22360,	-- 55
	26265,	30850,	36235,	42565,	50000,	-- 60
	58730,	68985,	81030,	95180,	111800,	-- 65
	131325,	154255,	181190,	212830,	250000,	-- 70
}

-- current pet information
local Pet = {
	active = false,
	alive = false,
	stuck = false,
	health = {
		current = 0,
		max = 100,
	},
	count = 0,
	imp_count = 0,
	infernal_count = 0,
	tyrant_power = 0,
	tyrant_available_power = 0,
	tyrant_cd = 0,
	tyrant_remains = 0,
}

-- current target information
local Target = {
	boss = false,
	dummy = false,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
}

-- target dummy unit IDs (count these units as bosses)
Target.Dummies = {
	[189617] = true,
	[189632] = true,
	[194643] = true,
	[194644] = true,
	[194648] = true,
	[194649] = true,
	[197833] = true,
	[198594] = true,
}

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.AFFLICTION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.DEMONOLOGY] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.DESTRUCTION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes[self.spec])
	self.enemies = self.target_modes[self.spec][self.target_mode][1]
	doomedPanel.text.br:SetText(self.target_modes[self.spec][self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes[self.spec] and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes[self.spec] or mode)
end

-- Target Mode Keybinding Wrappers
function Doomed_SetTargetMode(mode)
	Player:SetTargetMode(mode)
end

function Doomed_ToggleTargetMode()
	Player:ToggleTargetMode()
end

function Doomed_ToggleTargetModeReverse()
	Player:ToggleTargetModeReverse()
end

-- End AoE

-- Start Auto AoE

function AutoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if unitId and self.ignored_units[tonumber(unitId)] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function AutoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function AutoAoe:Clear()
	for _, ability in next, Abilities.autoAoe do
		ability.auto_aoe.start_time = nil
		for guid in next, ability.auto_aoe.targets do
			ability.auto_aoe.targets[guid] = nil
		end
	end
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
	self:Update()
end

function AutoAoe:Update()
	local count = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes[Player.spec], 1, -1 do
		if count >= Player.target_modes[Player.spec][i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function AutoAoe:Purge()
	local update
	for guid, t in next, self.targets do
		if Player.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if Player.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_react = false,
		requires_pet = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rank = 0,
		mana_cost = 0,
		shard_cost = 0,
		shard_gain = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		summon_count = 0,
		max_range = 40,
		velocity = 0,
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
	}
	setmetatable(ability, self)
	Abilities.all[#Abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if self:ManaCost() > Player.mana.current then
		return false
	end
	if self:ShardCost() > Player.soul_shards.current then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	if self.requires_pet and not Pet.active then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains()
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(0, expires - Player.ctime - (self.off_gcd and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:Expiring(seconds)
	local remains = self:Remains()
	return remains > 0 and remains < (seconds or Player.gcd)
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up(...)
	return self:Remains(...) > 0
end

function Ability:Down(...)
	return self:Remains(...) <= 0
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.traveling = {}
	else
		self.traveling = nil
		self.velocity = 0
	end
end

function Ability:Traveling(all)
	if not self.traveling then
		return 0
	end
	local count = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity + (self.travel_delay or 0)
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > (self.off_gcd and 0 or Player.execute_remains) then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function Ability:HighestRemains()
	local highest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				highest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not highest or remains > highest) then
				highest = remains
			end
		end
	end
	return highest or 0
end

function Ability:LowestRemains()
	local lowest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				lowest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not lowest or remains < lowest) then
				lowest = remains
			end
		end
	end
	return lowest or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	local remains = duration - (Player.ctime - start)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and count or 0
		end
	end
	return 0
end

function Ability:ManaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana.base) or 0
end

function Ability:ShardCost()
	return self.shard_cost
end

function Ability:ShardGain()
	return self.shard_gain
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + (self.off_gcd and 0 or Player.execute_remains))) / recharge_time)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return recharge_time
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.cast.ability == self
end

function Ability:Channeling()
	return Player.channel.ability == self
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return 0
	end
	return castTime / 1000
end

function Ability:Previous(n)
	local i = n or 1
	if Player.cast.ability then
		if i == 1 then
			return Player.cast.ability == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:UsedWithin(seconds)
	return self.last_used >= (Player.time - seconds)
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
		trigger = 'SPELL_DAMAGE',
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	elseif trigger == 'cast' then
		self.auto_aoe.trigger = 'SPELL_CAST_SUCCESS'
	end
end

function Ability:RecordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:UpdateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		self.auto_aoe.target_count = 0
		if self.auto_aoe.remove then
			for guid in next, AutoAoe.targets do
				AutoAoe.targets[guid] = nil
			end
		end
		for guid in next, self.auto_aoe.targets do
			AutoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		AutoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastFailed(dstGUID, missType)
	if self.requires_pet and missType == 'No path available' then
		Pet.stuck = true
	end
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	if self.requires_pet then
		Pet.stuck = false
	end
	if self.ignore_cast or (self.pet_spell and not self.player_triggered) then
		return
	end
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		AutoAoe:Add(dstGUID, true)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if Opt.previous then
		doomedPreviousPanel.ability = self
		doomedPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		doomedPreviousPanel.icon:SetTexture(self.icon)
		doomedPreviousPanel:SetShown(doomedPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event, missType)
	if self.traveling then
		local oldest
		for guid, cast in next, self.traveling do
			if Player.time - cast.start >= self.max_range / self.velocity + (self.travel_delay or 0) + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = floor(clamp(self.velocity * max(0, Player.time - oldest.start - (self.travel_delay or 0)), 0, self.max_range))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(clamp(self.velocity * (Player.time - self.range_est_start - (self.travel_delay or 0)), 5, self.max_range))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.auto_aoe and self.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not self.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif event == self.auto_aoe.trigger or (self.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			self:RecordTargetHit(dstGUID)
		end
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and doomedPreviousPanel.ability == self then
		doomedPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, Abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	for _, ability in next, Abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid] or {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid, extend)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	return aura
end

function Ability:RefreshAuraAll(extend)
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

--[[
Note: To get talent_node value for a talent, hover over talent and use macro:
/dump GetMouseFocus():GetNodeID()
]]

-- Warlock Abilities
---- Multiple Specializations
local CreateHealthstone = Ability:Add(6201, true, true)
CreateHealthstone.mana_cost = 2
local DrainLife = Ability:Add(234153, false, true)
DrainLife.mana_cost = 3
DrainLife.buff_duration = 6
DrainLife.tick_interval = 1
DrainLife.hasted_duration = true
DrainLife.hasted_ticks = true
local SpellLock = Ability:Add(119910, false, true)
SpellLock.cooldown_duration = 24
SpellLock.player_triggered = true
------ Talents
local FelDomination = Ability:Add(333889, true, true)
FelDomination.buff_duration = 15
FelDomination.cooldown_duration = 180
local GrandWarlocksDesign = Ability:Add(387084, true, true)
local GrimoireOfSacrifice = Ability:Add(108503, true, true, 196099)
GrimoireOfSacrifice.buff_duration = 3600
GrimoireOfSacrifice.cooldown_duration = 30
local MortalCoil = Ability:Add(6789, false, true)
MortalCoil.mana_cost = 2
MortalCoil.buff_duration = 3
MortalCoil.cooldown_duration = 45
MortalCoil:SetVelocity(24)
local SoulConduit = Ability:Add(215941, true, true)
local SummonSoulkeeper = Ability:Add(386244, true, true, 386256)
SummonSoulkeeper.buff_duration = 10
------ Procs
local TormentedSoul = Ability:Add(386251, true, true)
------ Permanent Pets
local SummonImp = Ability:Add(688, false, true)
SummonImp.shard_cost = 1
SummonImp.pet_family = 'Imp'
local SummonFelhunter = Ability:Add(691, false, true)
SummonFelhunter.shard_cost = 1
SummonFelhunter.pet_family = 'Felhunter'
local SummonVoidwalker = Ability:Add(697, false, true)
SummonVoidwalker.shard_cost = 1
SummonVoidwalker.pet_family = 'Voidwalker'
local SummonSuccubus = Ability:Add(712, false, true)
SummonSuccubus.shard_cost = 1
SummonSuccubus.pet_family = 'Succubus'
local SummonFelguard = Ability:Add(30146, false, true)
SummonFelguard.shard_cost = 1
SummonFelguard.pet_family = 'Felguard'
---- Affliction
local Agony = Ability:Add(980, false, true)
Agony.mana_cost = 1
Agony.buff_duration = 18
Agony.tick_interval = 2
Agony.hasted_ticks = true
Agony:TrackAuras()
local Corruption = Ability:Add(172, false, true, 146739)
Corruption.mana_cost = 1
Corruption.buff_duration = 14
Corruption.tick_interval = 2
Corruption.hasted_ticks = true
Corruption.triggers_combat = true
Corruption:TrackAuras()
local MaleficRapture = Ability:Add(324536, false, true)
MaleficRapture.shard_cost = 1
MaleficRapture:AutoAoe(false)
local SeedOfCorruption = Ability:Add(27243, false, true, 27285)
SeedOfCorruption.shard_cost = 1
SeedOfCorruption.buff_duration = 12
SeedOfCorruption:SetVelocity(30)
SeedOfCorruption.hasted_duration = true
SeedOfCorruption.triggers_combat = true
SeedOfCorruption:AutoAoe(true)
SeedOfCorruption:TrackAuras()
local ShadowBoltAffliction = Ability:Add(232670, false, true)
ShadowBoltAffliction.mana_cost = 2
ShadowBoltAffliction.triggers_combat = true
ShadowBoltAffliction:SetVelocity(25)
local SummonDarkglare = Ability:Add(205180, false, true)
SummonDarkglare.mana_cost = 2
SummonDarkglare.cooldown_duration = 180
SummonDarkglare.summon_count = 1
SummonDarkglare.summoning = false
local UnstableAffliction = Ability:Add(316099, false, true)
UnstableAffliction.buff_duration = 16
UnstableAffliction.tick_interval = 2
UnstableAffliction.hasted_ticks = true
UnstableAffliction.triggers_combat = true
UnstableAffliction:TrackAuras()
------ Talents
local AbsoluteCorruption = Ability:Add(196103, false, true)
local CreepingDeath = Ability:Add(264000, false, true)
local DarkSoulMisery = Ability:Add(113860, true, true)
DarkSoulMisery.buff_duration = 20
DarkSoulMisery.cooldown_duration = 120
DarkSoulMisery.mana_cost = 1
local DrainSoul = Ability:Add(198590, false, true)
DrainSoul.mana_cost = 1
DrainSoul.buff_duration = 5
DrainSoul.tick_interval = 1
DrainSoul.hasted_duration = true
DrainSoul.hasted_ticks = true
local Haunt = Ability:Add(48181, false, true)
Haunt.mana_cost = 2
Haunt.buff_duration = 15
Haunt.cooldown_duration = 15
Haunt.triggers_combat = true
Haunt:SetVelocity(40)
local InevitableDemise = Ability:Add(334319, true, true, 334320)
InevitableDemise.buff_duration = 20
local Nightfall = Ability:Add(108558, false, true, 264571)
Nightfall.buff_duration = 12
local PhantomSingularity = Ability:Add(205179, false, true, 205246)
PhantomSingularity.buff_duration = 16
PhantomSingularity.cooldown_duration = 45
PhantomSingularity.tick_interval = 2
PhantomSingularity.hasted_duration = true
PhantomSingularity.hasted_ticks = true
PhantomSingularity:AutoAoe(false, 'periodic')
PhantomSingularity:TrackAuras()
local ShadowEmbrace = Ability:Add(32388, false, true, 32390)
ShadowEmbrace.buff_duration = 10
local Shadowfury = Ability:Add(30283, false, true)
Shadowfury.cooldown_duration = 60
Shadowfury.buff_duration = 3
local SiphonLife = Ability:Add(63106, false, true)
SiphonLife.buff_duration = 15
SiphonLife.tick_interval = 3
SiphonLife.hasted_ticks = true
SiphonLife:TrackAuras()
local SowTheSeeds = Ability:Add(196226, false, true)
local VileTaint = Ability:Add(278350, false, true)
VileTaint.shard_cost = 1
VileTaint.buff_duration = 10
VileTaint.cooldown_duration = 20
VileTaint.tick_interval = 2
VileTaint.hasted_ticks = true
VileTaint.triggers_combat = true
VileTaint:AutoAoe(true)
VileTaint:TrackAuras()
local WritheInAgony = Ability:Add(196102, false, true)
---- Demonology
------ Talents
local BilescourgeBombers = Ability:Add(267211, false, true, 267213)
BilescourgeBombers.buff_duration = 6
BilescourgeBombers.cooldown_duration = 30
BilescourgeBombers:AutoAoe(true)
local CallDreadstalkers = Ability:Add(104316, false, true)
CallDreadstalkers.buff_duration = 12
CallDreadstalkers.cooldown_duration = 20
CallDreadstalkers.shard_cost = 2
CallDreadstalkers.summon_count = 2
CallDreadstalkers.triggers_combat = true
local Demonbolt = Ability:Add(264178, false, true)
Demonbolt.mana_cost = 2
Demonbolt.shard_gain = 2
Demonbolt.triggers_comabt = true
Demonbolt:SetVelocity(35)
local DemonicCalling = Ability:Add(205145, true, true, 205146)
DemonicCalling.buff_duration = 20
local DemonicStrength = Ability:Add(267171, true, true)
DemonicStrength.aura_target = 'pet'
DemonicStrength.buff_duration = 20
DemonicStrength.cooldown_duration = 60
local DemonicPower = Ability:Add(265273, true, true) -- applied to pets after Summon Demonic Tyrant cast
DemonicPower.aura_target = 'pet'
DemonicPower.buff_duration = 15
DemonicPower:TrackAuras()
local Doom = Ability:Add(603, false, true)
Doom.mana_cost = 1
Doom.buff_duration = 20
Doom.tick_interval = 20
Doom.hasted_duration = true
Doom.hasted_ticks = true
local DreadCalling = Ability:Add(387391, true, true, 387393)
local Dreadlash = Ability:Add(264078, false, true, 271971)
local FelSunder = Ability:Add(387399, false, true, 387402)
FelSunder.buff_duration = 8
local FromTheShadows = Ability:Add(267170, false, true, 270569)
FromTheShadows.buff_duration = 12
local GrimoireFelguard = Ability:Add(111898, false, true)
GrimoireFelguard.buff_duration = 17
GrimoireFelguard.cooldown_duration = 120
GrimoireFelguard.shard_cost = 1
GrimoireFelguard.summon_count = 1
local Guillotine = Ability:Add(386833, false, true, 386609)
Guillotine.cooldown_duration = 45
Guillotine.requires_pet = true
Guillotine:AutoAoe()
local HandOfGuldan = Ability:Add(105174, false, true, 86040)
HandOfGuldan.shard_cost = 1
HandOfGuldan.triggers_combat = true
HandOfGuldan:AutoAoe(true)
local ImpGangBoss = Ability:Add(387445, true, true, 387458)
ImpGangBoss:TrackAuras()
local InnerDemons = Ability:Add(267216, false, true)
local Implosion = Ability:Add(196277, false, true, 196278)
Implosion.mana_cost = 2
Implosion:AutoAoe()
local NetherPortal = Ability:Add(267217, true, true, 267218)
NetherPortal.buff_duration = 15
NetherPortal.cooldown_duration = 180
NetherPortal.shard_cost = 1
local PowerSiphon = Ability:Add(264130, false, true)
PowerSiphon.cooldown_duration = 30
local ReignOfTyranny = Ability:Add(427684, false, true)
local SacrificedSouls = Ability:Add(267214, false, true)
local ShadowBoltDemonology = Ability:Add(686, false, true)
ShadowBoltDemonology.mana_cost = 2
ShadowBoltDemonology.shard_gain = 1
ShadowBoltDemonology.triggers_combat = true
ShadowBoltDemonology:SetVelocity(20)
local ShadowsBite = Ability:Add(387322, true, true, 272945)
ShadowsBite.buff_duration = 8
local SoulboundTyrant = Ability:Add(334585, false, true)
SoulboundTyrant.talent_node = 71992
local SoulStrike = Ability:Add(267964, false, true)
SoulStrike.cooldown_duration = 10
SoulStrike.shard_gain = 1
SoulStrike.requires_pet = true
SoulStrike.off_gcd = true
SoulStrike.triggers_gcd = false
SoulStrike.learn_spellId = 428344
local SummonDemonicTyrant = Ability:Add(265187, true, true)
SummonDemonicTyrant.buff_duration = 15
SummonDemonicTyrant.cooldown_duration = 90
SummonDemonicTyrant.mana_cost = 2
SummonDemonicTyrant.summon_count = 1
SummonDemonicTyrant.summoning = false
local SummonVilefiend = Ability:Add(264119, false, true)
SummonVilefiend.buff_duration = 15
SummonVilefiend.cooldown_duration = 45
SummonVilefiend.shard_cost = 1
SummonVilefiend.summon_count = 1
local TheHoundmastersStratagem = Ability:Add(267170, false, true, 270569)
TheHoundmastersStratagem.buff_duration = 12
------ Procs
local DemonicCore = Ability:Add(267102, true, true, 264173)
DemonicCore.buff_duration = 20
------ Pet Abilities
local AxeToss = Ability:Add(89766, false, true, 119914)
AxeToss.cooldown_duration = 30
AxeToss.pet_spell = true
AxeToss.requires_pet = true
AxeToss.triggers_gcd = false
AxeToss.off_gcd = true
AxeToss.player_triggered = true
local Dreadbite = Ability:Add(271971, false, false)
Dreadbite.pet_spell = true
Dreadbite.triggers_gcd = false
Dreadbite.off_gcd = true
Dreadbite:AutoAoe()
local Felstorm = Ability:Add(89751, true, true, 89753)
Felstorm.aura_target = 'pet'
Felstorm.buff_duration = 5
Felstorm.cooldown_duration = 30
Felstorm.tick_interval = 1
Felstorm.pet_spell = true
Felstorm.hasted_duration = true
Felstorm.hasted_ticks = true
Felstorm.requires_pet = true
Felstorm.triggers_gcd = false
Felstorm.off_gcd = true
Felstorm:AutoAoe()
local FelFirebolt = Ability:Add(104318, false, false)
FelFirebolt.pet_spell = true
FelFirebolt.triggers_gcd = false
FelFirebolt.off_gcd = true
local FiendishWrath = Ability:Add(386601, true, false)
FiendishWrath.pet_spell = true
FiendishWrath.aura_target = 'pet'
FiendishWrath.buff_duration = 6
local LegionStrike = Ability:Add(30213, false, true)
LegionStrike.requires_pet = true
LegionStrike.pet_spell = true
LegionStrike.triggers_gcd = false
LegionStrike.off_gcd = true
LegionStrike:AutoAoe()
---- Destruction
local Immolate = Ability:Add(348, false, true, 157736)
Immolate.buff_duration = 18
Immolate.mana_cost = 1.5
Immolate.tick_interval = 3
Immolate.hasted_ticks = true
Immolate.triggers_combat = true
Immolate:AutoAoe(false, 'apply')
Immolate:TrackAuras()
------ Talents
local AvatarOfDestruction = Ability:Add(387159, false, true)
AvatarOfDestruction.summon_count = 1
local Backdraft = Ability:Add(196406, true, true, 117828)
Backdraft.buff_duration = 10
local Backlash = Ability:Add(387384, true, true, 387385)
Backlash.buff_duration = 15
local BurnToAshes = Ability:Add(387153, true, true, 387154)
BurnToAshes.buff_duration = 20
BurnToAshes.max_stack = 6
BurnToAshes.talent_node = 71964
local Cataclysm = Ability:Add(152108, false, true)
Cataclysm.mana_cost = 1
Cataclysm.cooldown_duration = 30
Cataclysm.triggers_combat = true
local ChannelDemonfire = Ability:Add(196447, false, true)
ChannelDemonfire.buff_duration = 3
ChannelDemonfire.cooldown_duration = 25
ChannelDemonfire.mana_cost = 1.5
ChannelDemonfire.tick_interval = 0.2
ChannelDemonfire.hasted_duration = true
ChannelDemonfire.hasted_ticks = true
ChannelDemonfire.triggers_combat = true
local ChaosBolt = Ability:Add(116858, false, true)
ChaosBolt.shard_cost = 2
ChaosBolt.triggers_combat = true
ChaosBolt:SetVelocity(20)
local Chaosbringer = Ability:Add(422057, false, true)
Chaosbringer.talent_node = 71967
local ChaosIncarnate = Ability:Add(387275, false, true)
local Conflagrate = Ability:Add(17962, false, true)
Conflagrate.cooldown_duration = 12.96
Conflagrate.mana_cost = 1
Conflagrate.shard_gain = 0.5
Conflagrate.requires_charge = true
Conflagrate.hasted_cooldown = true
local CrashingChaos = Ability:Add(417234, true, true, 417282)
CrashingChaos.buff_duration = 45
local CryHavoc = Ability:Add(387522, false, true, 387547)
CryHavoc:AutoAoe()
local Decimation = Ability:Add(387176, false, true)
local DiabolicEmbers = Ability:Add(387173, false, true)
local DimensionalRift = Ability:Add(387976, true, true)
DimensionalRift.cooldown_duration = 45
DimensionalRift.shard_gain = 0.3
DimensionalRift.requires_charge = true
local Eradication = Ability:Add(196412, false, true, 196414)
Eradication.buff_duration = 7
Eradication.talent_node = 71984
local FireAndBrimstone = Ability:Add(196408, false, true)
FireAndBrimstone.talent_node = 71982
local Havoc = Ability:Add(80240, false, true)
Havoc.buff_duration = 12
Havoc.cooldown_duration = 30
Havoc.mana_cost = 2
Havoc:AutoAoe(false, 'cast')
Havoc:TrackAuras()
local ImpendingRuin = Ability:Add(387158, true, true) -- Ritual of Ruin progress
ImpendingRuin.buff_duration = 3600
ImpendingRuin.max_stack = 15
local ImprovedImmolate = Ability:Add(387093, false, true)
ImprovedImmolate.talent_node = 71976
local Incinerate = Ability:Add(29722, false, true)
Incinerate.mana_cost = 2
Incinerate.shard_gain = 0.2
Incinerate.triggers_combat = true
Incinerate:SetVelocity(25)
local Inferno = Ability:Add(270545, false, true)
local InternalCombustion = Ability:Add(266134, false, true)
local MasterRitualist = Ability:Add(387165, false, true)
MasterRitualist.talent_node = 71962
local Mayhem = Ability:Add(387506, false, true)
local Pandemonium = Ability:Add(387509, false, true)
local Pyrogenics = Ability:Add(387095, false, true, 387096)
Pyrogenics.buff_duration = 2
local RagingDemonfire = Ability:Add(387166, false, true)
RagingDemonfire.talent_node = 72063
local RainOfChaos = Ability:Add(266086, true, true, 266087)
RainOfChaos.buff_duration = 30
local RainOfFire = Ability:Add(5740, false, true, 42223)
RainOfFire.buff_duration = 8
RainOfFire.shard_cost = 3
RainOfFire.tick_interval = 1
RainOfFire.hasted_duration = true
RainOfFire.hasted_ticks = true
RainOfFire:AutoAoe(true)
local ReverseEntropy = Ability:Add(205148, true, true, 266030)
ReverseEntropy.buff_duration = 8
local RitualOfRuin = Ability:Add(387156, true, true, 387157)
RitualOfRuin.buff_duration = 30
local RoaringBlaze = Ability:Add(205184, false, true, 265931)
RoaringBlaze.buff_duration = 8
local Ruin = Ability:Add(387103, false, true)
Ruin.talent_node = 72062
local Shadowburn = Ability:Add(17877, false, true)
Shadowburn.buff_duration = 5
Shadowburn.cooldown_duration = 12
Shadowburn.mana_cost = 1
Shadowburn.shard_cost = 1
Shadowburn.hasted_cooldown = true
Shadowburn.requires_charge = true
local SoulFire = Ability:Add(6353, false, true)
SoulFire.cooldown_duration = 45
SoulFire.mana_cost = 2
SoulFire.shard_gain = 1
SoulFire.triggers_combat = true
SoulFire:SetVelocity(24)
local SummonInfernal = Ability:Add(1122, false, true, 22703)
SummonInfernal.cooldown_duration = 180
SummonInfernal.mana_cost = 2
SummonInfernal:AutoAoe(true)
------ Pet Abilities
local Immolation = Ability:Add(20153, false, false)
Immolation:AutoAoe()
-- Tier set bonuses
local DoomBrand = Ability:Add(423583, true, true, 423584) -- T31 2pc
DoomBrand.buff_duration = 20
local RiteOfRuvaraad = Ability:Add(409725, true, true) -- T30 4pc
RiteOfRuvaraad.buff_duration = 17
-- Racials

-- PvP talents
local RotAndDecay = Ability:Add(212371, false, true)
-- Trinket effects
local SolarMaelstrom = Ability:Add(422146, false, true) -- Belor'relos
SolarMaelstrom:AutoAoe()
-- Class cooldowns
local PowerInfusion = Ability:Add(10060, true)
PowerInfusion.buff_duration = 15
PowerInfusion.cooldown_duration = 120
-- Aliases
local ShadowBolt = ShadowBoltAffliction
-- End Abilities

-- Start Summoned Pets

function SummonedPets:Find(guid)
	local unitId = guid:match('^Creature%-0%-%d+%-%d+%-%d+%-(%d+)')
	return unitId and self.byUnitId[tonumber(unitId)]
end

function SummonedPets:Purge()
	for _, pet in next, self.known do
		for guid, unit in next, pet.active_units do
			if unit.expires <= Player.time then
				pet.active_units[guid] = nil
			end
		end
	end
end

function SummonedPets:Update()
	wipe(self.known)
	wipe(self.byUnitId)
	for _, pet in next, self.all do
		pet.known = pet.summon_spell and pet.summon_spell.known
		if pet.known then
			self.known[#SummonedPets.known + 1] = pet
			self.byUnitId[pet.unitId] = pet
		end
	end
end

function SummonedPets:Count()
	local count = 0
	for _, pet in next, self.known do
		count = count + pet:Count()
	end
	return count
end

function SummonedPets:Clear()
	for _, pet in next, self.known do
		pet:Clear()
	end
end

function SummonedPet:Add(unitId, duration, summonSpell)
	local pet = {
		unitId = unitId,
		duration = duration,
		active_units = {},
		summon_spell = summonSpell,
		known = false,
	}
	setmetatable(pet, self)
	SummonedPets.all[#SummonedPets.all + 1] = pet
	return pet
end

function SummonedPet:Remains(initial)
	if self.summon_spell and self.summon_spell.summon_count > 0 and self.summon_spell:Casting() then
		return self.duration
	end
	local expires_max = 0
	for guid, unit in next, self.active_units do
		if (not initial or unit.initial) and unit.expires > expires_max then
			expires_max = unit.expires
		end
	end
	return max(0, expires_max - Player.time - Player.execute_remains)
end

function SummonedPet:Up(...)
	return self:Remains(...) > 0
end

function SummonedPet:Down(...)
	return self:Remains(...) <= 0
end

function SummonedPet:Count()
	local count = 0
	if self.summon_spell and self.summon_spell:Casting() then
		count = count + self.summon_spell.summon_count
	end
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time > Player.execute_remains then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:Expiring(seconds)
	local count = 0
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time <= (seconds or Player.execute_remains) then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:AddUnit(guid)
	local unit = {
		guid = guid,
		spawn = Player.time,
		expires = Player.time + self.duration,
	}
	self.active_units[guid] = unit
	return unit
end

function SummonedPet:RemoveUnit(guid)
	if self.active_units[guid] then
		self.active_units[guid] = nil
	end
end

function SummonedPet:ExtendAll(seconds)
	for guid, unit in next, self.active_units do
		if unit.expires > Player.time then
			unit.expires = unit.expires + seconds
		end
	end
end

function SummonedPet:Clear()
	for guid in next, self.active_units do
		self.active_units[guid] = nil
	end
end

-- Summoned Pets
Pet.Darkglare = SummonedPet:Add(103673, 20, SummonDarkglare)
Pet.DemonicTyrant = SummonedPet:Add(135002, 15, SummonDemonicTyrant)
Pet.Dreadstalker = SummonedPet:Add(98035, 12, CallDreadstalkers)
Pet.Felguard = SummonedPet:Add(17252, 17, GrimoireFelguard)
Pet.Infernal = SummonedPet:Add(89, 30, SummonInfernal)
Pet.Vilefiend = SummonedPet:Add(135816, 15, SummonVilefiend)
Pet.WildImp = SummonedPet:Add(55659, 40, HandOfGuldan)
---- Nether Portal / Inner Demons
Pet.Bilescourge = SummonedPet:Add(136404, 15, NetherPortal)
Pet.Darkhound = SummonedPet:Add(136408, 15, NetherPortal)
Pet.EredarBrute = SummonedPet:Add(136405, 15, NetherPortal)
Pet.EyeOfGuldan = SummonedPet:Add(136401, 15, NetherPortal)
Pet.IllidariSatyr = SummonedPet:Add(136398, 15, NetherPortal)
Pet.PitLord = SummonedPet:Add(196111, 10, NetherPortal)
Pet.PrinceMalchezaar = SummonedPet:Add(136397, 15, NetherPortal)
Pet.Shivarra = SummonedPet:Add(136406, 15, NetherPortal)
Pet.Urzul = SummonedPet:Add(136402, 15, NetherPortal)
Pet.ViciousHellhound = SummonedPet:Add(136399, 15, NetherPortal)
Pet.VoidTerror = SummonedPet:Add(136403, 15, NetherPortal)
Pet.Wrathguard = SummonedPet:Add(136407, 15, NetherPortal)
Pet.WildImpID = SummonedPet:Add(143622, 20, InnerDemons)
-- Destruction Talents
Pet.Blasphemy = SummonedPet:Add(185584, 8, AvatarOfDestruction)

-- End Summoned Pets

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
		off_gcd = true,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(self.max_charges, charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(1, count)
	end
	return count
end

function InventoryItem:Cooldown()
	local start, duration
	if self.equip_slot then
		start, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		start, duration = GetItemCooldown(self.itemId)
	end
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
end

function InventoryItem:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function InventoryItem:Equipped()
	return self.equip_slot and true
end

function InventoryItem:Usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:Equipped() and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

-- Inventory Items
local Healthstone = InventoryItem:Add(5512)
Healthstone.created_by = CreateHealthstone
Healthstone.max_charges = 3
-- Equipment
local DreambinderLoomOfTheGreatCycle = InventoryItem:Add(208616)
DreambinderLoomOfTheGreatCycle.cooldown_duration = 120
DreambinderLoomOfTheGreatCycle.off_gcd = false
local IridalTheEarthsMaster = InventoryItem:Add(208321)
IridalTheEarthsMaster.cooldown_duration = 180
IridalTheEarthsMaster.off_gcd = false
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
Trinket.BelorrelosTheSuncaller = InventoryItem:Add(207172)
Trinket.BelorrelosTheSuncaller.cast_spell = SolarMaelstrom
Trinket.BelorrelosTheSuncaller.cooldown_duration = 120
Trinket.BelorrelosTheSuncaller.off_gcd = false
Trinket.NymuesUnravelingSpindle = InventoryItem:Add(208615)
Trinket.NymuesUnravelingSpindle.cooldown_duration = 120
Trinket.NymuesUnravelingSpindle.off_gcd = false
-- End Inventory Items

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.trackAuras)
	for _, ability in next, self.all do
		if ability.known then
			self.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				self.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				self.velocity[#self.velocity + 1] = ability
			end
			if ability.auto_aoe then
				self.autoAoe[#self.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				self.trackAuras[#self.trackAuras + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

function Player:ManaTimeToMax()
	local deficit = self.mana.max - self.mana.current
	if deficit <= 0 then
		return 0
	end
	return deficit / self.mana.regen
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.cast.ability and self.cast.ability.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
end

function Player:BloodlustActive()
	local _, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if not id then
			return false
		elseif (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 381301 or -- Feral Hide Drums (Leatherworking)
			id == 390386    -- Fury of the Aspects (Evoker)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	for i = (slot or 1), (slot or 19) do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId, slot)
	local link, item
	for i = (slot or 1), (slot or 19) do
		link = GetInventoryItemLink('player', i)
		if link then
			item = link:match('Hitem:%d+:([%d:]+)')
			if item then
				for id in item:gmatch('(%d+)') do
					if tonumber(id) == bonusId then
						return true
					end
				end
			end
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateTime(timeStamp)
	self.ctime = GetTime()
	if timeStamp then
		self.time_diff = self.ctime - timeStamp
	end
	self.time = self.ctime - self.time_diff
end

function Player:UpdateKnown()
	local node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.rank = 0
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.talent_node and configId then
			node = C_Traits.GetNodeInfo(configId, ability.talent_node)
			if node then
				ability.rank = node.activeRank
				ability.known = ability.rank > 0
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsUsableSpell(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
		end
	end

	if ShadowBoltAffliction.known then
		ShadowBolt = ShadowBoltAffliction
	elseif ShadowBoltDemonology.known then
		ShadowBolt = ShadowBoltDemonology
	end
	if DrainSoul.known then
		ShadowBolt.known = false
	end
	if SummonFelguard.known then
		AxeToss.known = true
		Felstorm.known = true
		LegionStrike.known = true
	end
	SpellLock.known = SummonFelhunter.known
	Dreadbite.known = Pet.Dreadstalker.known
	FelFirebolt.known = Pet.WildImp.known
	Immolation.known = Pet.Infernal.known
	DemonicPower.known = Pet.DemonicTyrant.known
	ImpendingRuin.known = RitualOfRuin.known
	DoomBrand.known = Player.set_bonus.t31 >= 2 or Player.set_bonus.t32 >= 2
	RiteOfRuvaraad.known = Player.set_bonus.t30 >= 4

	Abilities:Update()
	SummonedPets:Update()

	if APL[self.spec].precombat_variables then
		APL[self.spec]:precombat_variables()
	end
end

function Player:UpdateChannelInfo()
	local channel = self.channel
	local _, _, _, start, ends, _, _, spellId = UnitChannelInfo('player')
	if not spellId then
		channel.ability = nil
		channel.chained = false
		channel.start = 0
		channel.ends = 0
		channel.tick_count = 0
		channel.tick_interval = 0
		channel.ticks = 0
		channel.ticks_remain = 0
		channel.ticks_extra = 0
		channel.interrupt_if = nil
		channel.interruptible = false
		channel.early_chain_if = nil
		channel.early_chainable = false
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if ability then
		if ability == channel.ability then
			channel.chained = true
		end
		channel.interrupt_if = ability.interrupt_if
	else
		channel.interrupt_if = nil
	end
	channel.ability = ability
	channel.ticks = 0
	channel.start = start / 1000
	channel.ends = ends / 1000
	if ability and ability.tick_interval then
		channel.tick_interval = ability:TickTime()
	else
		channel.tick_interval = channel.ends - channel.start
	end
	channel.tick_count = (channel.ends - channel.start) / channel.tick_interval
	if channel.chained then
		channel.ticks_extra = channel.tick_count - floor(channel.tick_count)
	else
		channel.ticks_extra = 0
	end
	channel.ticks_remain = channel.tick_count
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == self.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, start, ends, duration, spellId, speed, max_speed
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.wait_time = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, start, ends, _, _, _, spellId = UnitCastingInfo('player')
	if spellId then
		self.cast.ability = Abilities.bySpellId[spellId]
		self.cast.start = start / 1000
		self.cast.ends = ends / 1000
		self.cast.remains = self.cast.ends - self.ctime
	else
		self.cast.ability = nil
		self.cast.start = 0
		self.cast.ends = 0
		self.cast.remains = 0
	end
	self.execute_remains = max(self.cast.remains, self.gcd_remains)
	if self.channel.tick_count > 1 then
		self.channel.ticks = ((self.ctime - self.channel.start) / self.channel.tick_interval) - self.channel.ticks_extra
		self.channel.ticks_remain = (self.channel.ends - self.ctime) / self.channel.tick_interval
	end
	self.mana.regen = GetPowerRegenForPowerType(0)
	self.mana.current = UnitPower('player', 0) + (self.mana.regen * self.execute_remains)
	if self.spec == SPEC.DESTRUCTION then
		Pet.infernal_count = Pet.Infernal:Count() + (AvatarOfDestruction.known and Pet.Blasphemy:Count() or 0)
		self.soul_shards.current = (UnitPower('player', 7, true) + (Pet.infernal_count * 2 * self.execute_remains)) / 10
	else
		self.soul_shards.current = UnitPower('player', 7)
	end
	if self.cast.ability then
		if self.cast.ability.mana_cost > 0 then
			self.mana.current = self.mana.current - self.cast.ability:ManaCost()
		end
		self.soul_shards.current = self.soul_shards.current - self.cast.ability:ShardCost() + self.cast.ability:ShardGain()
	end
	self.mana.current = clamp(self.mana.current, 0, self.mana.max)
	self.mana.pct = self.mana.current / self.mana.max * 100
	self.soul_shards.current = clamp(self.soul_shards.current, 0, self.soul_shards.max)
	self.soul_shards.deficit = self.soul_shards.max - self.soul_shards.current
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self:UpdateThreat()

	Pet:Update()

	SummonedPets:Purge()
	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	self.main = APL[self.spec]:Main()

	if self.channel.interrupt_if then
		self.channel.interruptible = self.channel.ability ~= self.main and self.channel.interrupt_if()
	end
	if self.channel.early_chain_if then
		self.channel.early_chainable = self.channel.ability == self.main and self.channel.early_chain_if()
	end
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	doomedPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	_, self.instance = IsInInstance()
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Player:ImpsIn(seconds)
	local count = 0
	for guid, unit in next, Pet.WildImp.active_units do
		if Pet.WildImp:UnitRemains(unit) > (self.execute_remains + seconds) then
			count = count + 1
		end
	end
	for guid, unit in next, HandOfGuldan.imp_pool do
		if (unit - self.time) < (self.execute_remains + seconds) then
			count = count + 1
		end
	end
	if InnerDemons.known then
		for guid, unit in next, Pet.WildImpID.active_units do
			if Pet.WildImpID:UnitRemains(unit) > (self.execute_remains + seconds) then
				count = count + 1
			end
		end
		if InnerDemons.next_imp and (InnerDemons.next_imp - self.time) < (self.execute_remains + seconds) then
			count = count + 1
		end
	end
	if HandOfGuldan:Casting() then
		if HandOfGuldan.cast_shards >= 3 and (self.execute_remains + seconds) > 1 then
			count = count + 3
		elseif HandOfGuldan.cast_shards >= 2 and (self.execute_remains + seconds) > 0.8 then
			count = count + 2
		elseif HandOfGuldan.cast_shards >= 1 and (self.execute_remains + seconds) > 0.6 then
			count = count + 1
		end
	end
	return count
end

-- End Player Functions

-- Start Pet Functions

function Pet:Update()
	self.guid = UnitGUID('pet')
	self.alive = self.guid and not UnitIsDead('pet')
	self.active = (self.alive and not self.stuck or IsFlying()) and true
end

-- End Pet Functions

-- Start Target Functions

function Target:UpdateHealth(reset)
	Timer.health = 0
	self.health.current = UnitHealth('target')
	self.health.max = UnitHealthMax('target')
	if self.health.current <= 0 then
		self.health.current = Player.health.max
		self.health.max = self.health.current
	end
	if reset then
		for i = 1, 25 do
			self.health.history[i] = self.health.current
		end
	else
		table.remove(self.health.history, 1)
		self.health.history[25] = self.health.current
	end
	self.timeToDieMax = self.health.current / Player.health.max * 10
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = (
		(self.dummy and 600) or
		(self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec)) or
		self.timeToDieMax
	)
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.uid = nil
		self.boss = false
		self.dummy = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = Player.level
		self.hostile = false
		self:UpdateHealth(true)
		if Opt.always_on then
			UI:UpdateCombat()
			doomedPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			doomedPreviousPanel:Hide()
		end
		return UI:Disappear()
	end
	if guid ~= self.guid then
		self.guid = guid
		self.uid = tonumber(guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)') or 0)
		self:UpdateHealth(true)
	end
	self.boss = false
	self.dummy = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self.level = UnitLevel('target')
	if self.level == -1 then
		self.level = Player.level + 3
	end
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		self.boss = self.level >= (Player.level + 3)
		self.stunnable = self.level < (Player.level + 2)
	end
	if self.Dummies[self.uid] then
		self.boss = true
		self.dummy = true
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		doomedPanel:Show()
		return true
	end
	UI:Disappear()
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self.health.current - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

function Target:Stunned()
	return AxeToss:Up() or Shadowfury:Up()
end

-- End Target Functions

-- Start Ability Modifications

function Implosion:Usable()
	return Pet.imp_count > 0 and Ability.Usable(self)
end
PowerSiphon.Usable = Implosion.Usable

function Corruption:Remains()
	if SeedOfCorruption:Ticking() > 0 or SeedOfCorruption:Previous() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function Conflagrate:Remains()
	return RoaringBlaze:Remains()
end

function Immolate:Duration()
	local duration = self.buff_duration
	if ImprovedImmolate.known then
		duration = duration + (3 * ImprovedImmolate.rank)
	end
	return duration
end

function Immolate:Remains()
	if Cataclysm.known and Cataclysm:Casting() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function Incinerate:Free()
	return Backlash.known and Backlash:Up()
end

function Incinerate:ShardGain()
	local gain = self.shard_gain
	if DiabolicEmbers.known then
		gain = gain + (gain * 1.00)
	end
	return gain
end

function Havoc:Duration()
	local duration = self.buff_duration
	if Pandemonium.known then
		duration = duration + 3
	end
	return duration
end

function Havoc:DotRemains(ability)
	local remains, lowest
	for guid, aura in next, self.aura_targets do
		if aura.expires > (Player.time + Player.execute_remains) then
			if ability:Casting() then
				return ability:Duration()
			end
			if ability.aura_targets[guid] then
				remains = ability.aura_targets[guid].expires - Player.time - Player.execute_remains
				if not lowest or remains < lowest then
					lowest = remains
				end
			end
		end
	end
	return lowest or 0
end

function SummonImp:Remains()
	if self:Casting() or (Pet.active and UnitCreatureFamily('pet') == self.pet_family) then
		return 3600
	end
	return 0
end
SummonFelhunter.Remains = SummonImp.Remains
SummonVoidwalker.Remains = SummonImp.Remains
SummonSuccubus.Remains = SummonImp.Remains
SummonFelguard.Remains = SummonImp.Remains

function SummonImp:ShardCost()
	if FelDomination.known and FelDomination:Up() then
		return 0
	end
	return Ability.ShardCost(self)
end
SummonFelhunter.ShardCost = SummonImp.ShardCost
SummonVoidwalker.ShardCost = SummonImp.ShardCost
SummonSuccubus.ShardCost = SummonImp.ShardCost
SummonFelguard.ShardCost = SummonImp.ShardCost

function HandOfGuldan:ShardCost()
	return clamp(Player.soul_shards.current, 1, 3)
end

HandOfGuldan.cast_shards = 0
HandOfGuldan.imp_pool = {}

function HandOfGuldan:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	if self.cast_shards >= 1 then
		self.imp_pool[#self.imp_pool + 1] = Player.time + 0.7
	end
	if self.cast_shards >= 2 then
		self.imp_pool[#self.imp_pool + 1] = Player.time + 0.9
	end
	if self.cast_shards >= 3 then
		self.imp_pool[#self.imp_pool + 1] = Player.time + 1.1
	end
end

function HandOfGuldan:ImpSpawned()
	if #self.imp_pool == 0 then
		return
	end
	table.remove(self.imp_pool, 1)
end

function HandOfGuldan:Purge()
	while #self.imp_pool > 0 and self.imp_pool[1] < Player.time do
		table.remove(self.imp_pool, 1)
	end
end

function InnerDemons:ImpSpawned()
	self.next_imp = Player.time + 12
end

function PowerSiphon:Sacrifice()
	local energy, sacrifice
	local energy_min = 1000
	local imps = Pet.WildImp.active_units
	for guid, unit in next, imps do
		energy = unit.energy + (unit.gang_boss and 200 or 0) + (Pet.WildImp:Empowered(unit) and 200 or 0)
		if energy < energy_min or (energy == energy_min and unit.spawn < sacrifice.spawn) then
			energy_min = energy
			sacrifice = unit
		end
	end
	for guid, unit in next, Pet.WildImpID.active_units do
		energy = unit.energy + (unit.gang_boss and 200 or 0) + (Pet.WildImpID:Empowered(unit) and 200 or 0)
		if energy < energy_min or (energy == energy_min and unit.spawn < sacrifice.spawn) then
			energy_min = energy
			sacrifice = unit
			imps = Pet.WildImpID.active_units
		end
	end
	if sacrifice then
		imps[sacrifice.guid] = nil
	end
end

function PowerSiphon:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	self:Sacrifice()
	self:Sacrifice()
end

function Implosion:Implode()
	Pet.WildImp:Clear()
	Pet.WildImpID:Clear()
end

function Implosion:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	self:Implode()
end

--[[
function DemonicCore:Remains()
	if Pet.Dreadstalker:Expiring() > 0 then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function DemonicCore:Stack()
	local count = Ability.Stack(self)
	count = count + Pet.Dreadstalker:Expiring()
	return min(count, 4)
end
]]

function CallDreadstalkers:ShardCost()
	local cost = self.shard_cost
	if DemonicCalling:Up() then
		cost = cost - 2
	end
	return max(0, cost)
end

function SummonDemonicTyrant:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	self.summoning = true
end
SummonDarkglare.CastSuccess = SummonDemonicTyrant.CastSuccess
SummonInfernal.CastSuccess = SummonDemonicTyrant.CastSuccess

function SummonDemonicTyrant:CooldownDuration()
	local duration = self.cooldown_duration
	if GrandWarlocksDesign.known then
		duration = duration - 30
	end
	return duration
end
SummonDarkglare.CooldownDuration = SummonDemonicTyrant.CooldownDuration

function SummonInfernal:CooldownDuration()
	local duration = self.cooldown_duration
	if GrandWarlocksDesign.known then
		duration = duration - 60
	end
	return duration
end

function SummonDemonicTyrant:ShardGain()
	local gain = self.shard_gain
	if SoulboundTyrant.known then
		gain = gain + ceil(2.5 * SoulboundTyrant.rank)
	end
	return gain
end

function DemonicStrength:Usable()
	return not (DemonicStrength:Up() or Guillotine:Up() or Felstorm:Up()) and Ability.Usable(self)
end
Guillotine.Usable = DemonicStrength.Usable

function Guillotine:Remains()
	return FiendishWrath:Remains()
end

function SpellLock:Usable()
	if not SummonFelhunter:Up() then
		return false
	end
	return Ability.Usable(self)
end

function AxeToss:Usable()
	if not SummonFelguard:Up() then
		return false
	end
	return Ability.Usable(self)
end

function Shadowfury:Usable()
	return Target.stunnable and Ability.Usable(self)
end
MortalCoil.Usable = Shadowfury.Usable

function InevitableDemise:Stack()
	if DrainLife:Previous() or DrainLife:Channeling() then
		return 0
	end
	return Ability.Stack(self)
end

function RitualOfRuin:Remains()
	if ImpendingRuin:Stack() >= ImpendingRuin:MaxStack() then
		return self:Duration()
	end
	if ChaosBolt:Casting() then
		return 0
	end
	return Ability.Remains(self)
end

function ImpendingRuin:MaxStack()
	local stack = self.max_stack
	if MasterRitualist.known then
		stack = stack - ceil(2.5 * MasterRitualist.rank)
	end
	return stack
end

function ImpendingRuin:Stack()
	if Ability.Remains(RitualOfRuin) > 0 then
		return 0
	end
	local stack = Ability.Stack(self)
	if Player.cast.ability then
		stack = stack + Player.cast.ability.shard_cost
	end
	return clamp(stack, 0, self:MaxStack())
end

function ChaosBolt:ShardCost()
	if RitualOfRuin.known and RitualOfRuin:Up() then
		return 0
	end
	return Ability.ShardCost(self)
end
RainOfFire.ShardCost = ChaosBolt.ShardCost

function ChaosBolt:ShardGain()
	if RitualOfRuin.known and Ability.Remains(RitualOfRuin) > 0 then
		return Ability.ShardCost(self)
	end
	return 0
end

function Backdraft:Stack()
	local stack = Ability.Stack(self)
	if stack > 0 and (ChaosBolt:Casting() or Immolate:Casting() or SoulFire:Casting()) then
		stack = stack - 1
	end
	return stack
end

function Backdraft:Remains()
	if self:Stack() == 0 then
		return 0
	end
	return Ability.Remains(self)
end
CrashingChaos.Remains = Backdraft.Remains

function BurnToAshes:Stack()
	local stack = Ability.Stack(self)
	if ChaosBolt:Casting() then
		stack = stack + 2
	elseif Incinerate:Casting() then
		stack = stack - 1
	end
	return clamp(stack, 0, self.max_stack)
end

function BurnToAshes:Remains()
	if ChaosBolt:Casting() then
		return self:Duration()
	end
	if self:Stack() == 0 then
		return 0
	end
	return Ability.Remains(self)
end

function CrashingChaos:Stack()
	local stack = Ability.Stack(self)
	if stack > 0 and ChaosBolt:Casting() then
		stack = stack - 1
	end
	return stack
end

function Eradication:Remains()
	if ChaosBolt:Casting() or ChaosBolt:Traveling() > 0 then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function SoulFire:Cooldown()
	local remains = Ability.Cooldown(self)
	if Decimation.known and Incinerate:Casting() and Target.health.pct <= 50 then
		remains = remains - 5
	end
	return max(0, remains)
end

function GrimoireOfSacrifice:Usable()
	return Pet.alive and Ability.Usable(self)
end

function ImpGangBoss:ApplyAura(guid)
	local unit = Pet.WildImp.active_units[dstGUID] or Pet.WildImpID.active_units[dstGUID]
	if unit then
		unit.gang_boss = true
	end
end

function DemonicPower:ApplyAura(guid)
	local pet = SummonedPets:Find(guid)
	if pet then
		pet:Empower(guid, self:Duration())
	end
	if ReignOfTyranny.known then
		for guid, unit in next, Pet.DemonicTyrant.active_units do
			if unit.initial then
				unit.power = unit.power + 10
			end
		end
	end
end
DemonicPower.RefreshAura = DemonicPower.ApplyAura

function IridalTheEarthsMaster:Usable(...)
	return Target.health.pct < 35 and InventoryItem.Usable(self, ...)
end

-- End Ability Modifications

-- Start Summoned Pet Modifications

function SummonedPet:Empower(guid, seconds)
	local unit = self.active_units[guid]
	if unit then
		unit.expires = unit.expires + seconds
		unit.empower_expires = Player.time + seconds
	end
end

function SummonedPet:Empowered(unit)
	return unit.empower_expires and (unit.empower_expires - Player.time) > Player.execute_remains
end

function Pet.Darkglare:AddUnit(guid)
	local unit = SummonedPet.AddUnit(self, guid)
	if SummonDarkglare.summoning then
		unit.initial = true
		SummonDarkglare.summoning = false
	end
	return unit
end

function Pet.DemonicTyrant:AddUnit(guid)
	local unit = SummonedPet.AddUnit(self, guid)
	unit.power = 100
	if SummonDemonicTyrant.summoning then
		unit.initial = true
		SummonDemonicTyrant.summoning = false
	end
	return unit
end

function Pet.DemonicTyrant:Power()
	for _, unit in next, self.active_units do
		return unit.power
	end
	return 0
end

function Pet.DemonicTyrant:AvailablePower()
	local power = 100
	if ReignOfTyranny.known then
		power = power + (SummonFelguard:Up() and 10 or 0) + (10 * Pet.Dreadstalker:Count()) + (10 * Pet.Vilefiend:Count()) + (10 * Pet.Felguard:Count()) + (10 * min(15, Player:ImpsIn(SummonDemonicTyrant:CastTime())))
	end
	return power
end

function Pet.WildImp:AddUnit(guid)
	local unit = SummonedPet.AddUnit(self, guid)
	unit.energy = 100
	unit.cast_end = 0
	unit.gang_boss = false
	HandOfGuldan:ImpSpawned()
	return unit
end

function Pet.WildImpID:AddUnit(guid)
	local unit = SummonedPet.AddUnit(self, guid)
	unit.energy = 100
	unit.cast_end = 0
	unit.gang_boss = false
	InnerDemons:ImpSpawned()
	return unit
end

function Pet.WildImp:UnitRemains(unit)
	local energy, remains = unit.energy, 0
	if unit.cast_end > Player.time then
		if self:Empowered(unit) then
			remains = unit.empower_expires - Player.time
		else
			energy = energy - 16
			remains = unit.cast_end - Player.time
		end
		remains = remains + (floor(energy / 16) * FelFirebolt:CastTime())
	else
		unit.cast_end = 0
		remains = unit.expires - Player.time
	end
	return max(0, remains)
end
Pet.WildImpID.UnitRemains = Pet.WildImp.UnitRemains

function Pet.WildImp:Count()
	local count = 0
	for guid, unit in next, self.active_units do
		if self:UnitRemains(unit) > Player.execute_remains then
			count = count + 1
		end
	end
	for guid, spawn in next, HandOfGuldan.imp_pool do
		if (spawn - Player.time) < Player.execute_remains then
			count = count + 1
		end
	end
	return count
end

function Pet.WildImpID:Count()
	local count = 0
	for guid, unit in next, self.active_units do
		if self:UnitRemains(unit) > Player.execute_remains then
			count = count + 1
		end
	end
	if InnerDemons.next_imp and (InnerDemons.next_imp - Player.time) < Player.execute_remains then
		count = count + 1
	end
	return count
end

function Pet.WildImp:Remains()
	return SummonedPet.Remains(self)
end
Pet.WildImpID.Remains = Pet.WildImp.Remains

function Pet.WildImp:Casting()
	if Player.combat_start == 0 then
		return false
	end
	for guid, unit in next, self.active_units do
		if unit.cast_end >= Player.time then
			return true
		end
	end
	return false
end
Pet.WildImpID.Casting = Pet.WildImp.Casting

function Pet.WildImp:RemainsUnder(seconds)
	local count = 0
	for guid, unit in next, self.active_units do
		if between(self:UnitRemains(unit), Player.execute_remains, seconds) then
			count = count + 1
		end
	end
	return count
end
Pet.WildImpID.RemainsUnder = Pet.WildImp.RemainsUnder

function Pet.WildImp:CastStart(unit, spellId, dstGUID)
	if FelFirebolt:Match(spellId) then
		unit.cast_end = Player.time + FelFirebolt:CastTime()
	end
end
Pet.WildImpID.CastStart = Pet.WildImp.CastStart

function Pet.WildImp:CastFailed(unit, spellId, dstGUID)
	if FelFirebolt:Match(spellId) then
		unit.cast_end = 0
	end
end
Pet.WildImpID.CastFailed = Pet.WildImp.CastFailed

function Pet.WildImp:CastSuccess(unit, spellId, dstGUID)
	if FelFirebolt:Match(spellId) then
		if not self:Empowered(unit) then
			unit.energy = unit.energy - 16
			if unit.energy < 16 then
				self.active_units[unit.guid] = nil
				return
			end
		end
		unit.cast_end = 0
	end
end
Pet.WildImpID.CastSuccess = Pet.WildImp.CastSuccess

function Pet.Infernal:AddUnit(guid)
	local unit = SummonedPet.AddUnit(self, guid)
	if SummonInfernal.summoning then
		SummonInfernal.summoning = false -- summoned a full duration infernal
		unit.initial = true
	else -- summoned a Rain of Chaos proc infernal
		unit.expires = Player.time + 8
	end
	return unit
end

function Pet.Infernal:CastLanded(unit, spellId, ...)
	if Immolation:Match(spellId) then
		Immolation:CastLanded(...)
	end
end
Pet.Blasphemy.CastLanded = Pet.Infernal.CastLanded

function Pet.Dreadstalker:CastLanded(unit, spellId, ...)
	if Dreadbite:Match(spellId) then
		Dreadbite:CastLanded(...)
	end
end

function Pet.Felguard:CastLanded(unit, spellId, ...)
	if Felstorm:Match(spellId) then
		Felstorm:CastLanded(...)
	end
end

-- End Summoned Pet Modifications

local function UseCooldown(ability, overwrite)
	if Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not Player.extra or overwrite then
		Player.extra = ability
	end
end

local function WaitFor(ability, wait_time)
	Player.wait_time = wait_time and (Player.ctime + wait_time) or (Player.ctime + ability:Cooldown())
	return ability
end

-- Begin Action Priority Lists

APL[SPEC.NONE].Main = function(self)
end

APL[SPEC.AFFLICTION].Main = function(self)
	self.use_cds = Target.boss or Target.timeToDie > Opt.cd_ttd or (SoulRot.known and SoulRot:Ticking() > 0) or (DarkSoulMisery.known and DarkSoulMisery:Up()) or SummonDarkglare:Up()
	self.use_seed = (SowTheSeeds.known and Player.enemies >= 3) or (SiphonLife.known and Player.enemies >= 5) or Player.enemies >= 8
	Player.dot_count = Agony:Ticking() + Corruption:Ticking() + UnstableAffliction:Ticking() + (SiphonLife.known and SiphonLife:Ticking() or 0) + (PhantomSingularity.known and PhantomSingularity:Ticking() or 0) + (VileTaint.known and VileTaint:Ticking() or 0)

	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/summon_pet
actions.precombat+=/grimoire_of_sacrifice,if=talent.grimoire_of_sacrifice.enabled
actions.precombat+=/snapshot_stats
actions.precombat+=/potion
actions.precombat+=/use_item,name=azsharas_font_of_power
actions.precombat+=/seed_of_corruption,if=spell_targets.seed_of_corruption_aoe>=3&!equipped.169314
actions.precombat+=/haunt
actions.precombat+=/shadow_bolt,if=!talent.haunt.enabled&spell_targets.seed_of_corruption_aoe<3&!equipped.169314
]]
		if Opt.healthstone and Healthstone:Charges() == 0 and CreateHealthstone:Usable() then
			return CreateHealthstone
		end
		if GrimoireOfSacrifice:Usable() then
			return GrimoireOfSacrifice
		end
		if not Pet.active and (not GrimoireOfSacrifice.known or GrimoireOfSacrifice:Remains() < 300) then
			if FelDomination:Usable() then
				UseCooldown(FelDomination)
			end
			if SummonImp:Usable() then
				return SummonImp
			end
		end
		if Player.enemies >= 3 and SeedOfCorruption:Usable() and SeedOfCorruption:Down() then
			return SeedOfCorruption
		end
		if Haunt.known then
			if Haunt:Usable() then
				return Haunt
			end
		elseif Player.enemies < 3 and ShadowBolt:Usable() and not ShadowBolt:Casting() then
			return ShadowBolt
		end
	else
		if GrimoireOfSacrifice:Usable() then
			UseCooldown(GrimoireOfSacrifice)
		end
		if not Pet.active and (not GrimoireOfSacrifice.known or GrimoireOfSacrifice:Remains() < 10) then
			if FelDomination:Usable() then
				UseCooldown(FelDomination)
			end
			if SummonImp:Usable() then
				UseExtra(SummonImp)
			end
		end
	end
--[[
actions=variable,name=use_seed,value=talent.sow_the_seeds.enabled&spell_targets.seed_of_corruption_aoe>=3+raid_event.invulnerable.up|talent.siphon_life.enabled&spell_targets.seed_of_corruption>=5+raid_event.invulnerable.up|spell_targets.seed_of_corruption>=8+raid_event.invulnerable.up
actions+=/variable,name=padding,op=set,value=0
actions+=/variable,name=maintain_se,value=spell_targets.seed_of_corruption_aoe<=1+talent.writhe_in_agony.enabled+talent.absolute_corruption.enabled*2+(talent.writhe_in_agony.enabled&talent.sow_the_seeds.enabled&spell_targets.seed_of_corruption_aoe>2)+(talent.siphon_life.enabled&!talent.creeping_death.enabled&!talent.drain_soul.enabled)+raid_event.invulnerable.up
actions+=/call_action_list,name=cooldowns
actions+=/drain_soul,interrupt_global=1,chain=1,cycle_targets=1,if=target.time_to_die<=gcd&soul_shard<5
actions+=/haunt,if=spell_targets.seed_of_corruption_aoe<=2+raid_event.invulnerable.up
actions+=/summon_darkglare,if=dot.agony.ticking&dot.corruption.ticking&(buff.active_uas.stack=5|soul_shard=0)&(!talent.phantom_singularity.enabled|dot.phantom_singularity.remains)
actions+=/agony,target_if=min:dot.agony.remains,if=remains<=gcd+action.shadow_bolt.execute_time&target.time_to_die>8
# Temporary fix to make sure azshara's font doesn't break darkglare usage.
actions+=/agony,line_cd=30,if=time>30&cooldown.summon_darkglare.remains<=15&equipped.169314
actions+=/corruption,line_cd=30,if=time>30&cooldown.summon_darkglare.remains<=15&equipped.169314&!talent.absolute_corruption.enabled&(talent.siphon_life.enabled|spell_targets.seed_of_corruption_aoe>1&spell_targets.seed_of_corruption_aoe<=3)
actions+=/siphon_life,line_cd=30,if=time>30&cooldown.summon_darkglare.remains<=15&equipped.169314
actions+=/unstable_affliction,target_if=!contagion&target.time_to_die<=8
actions+=/drain_soul,target_if=min:debuff.shadow_embrace.remains,cancel_if=ticks_remain<5,if=talent.shadow_embrace.enabled&variable.maintain_se&debuff.shadow_embrace.remains&debuff.shadow_embrace.remains<=gcd*2
actions+=/shadow_bolt,target_if=min:debuff.shadow_embrace.remains,if=talent.shadow_embrace.enabled&variable.maintain_se&debuff.shadow_embrace.remains&debuff.shadow_embrace.remains<=execute_time*2+travel_time&!action.shadow_bolt.in_flight
actions+=/phantom_singularity,target_if=max:target.time_to_die,if=time>35&target.time_to_die>16*spell_haste
actions+=/unstable_affliction,target_if=min:contagion,if=!variable.use_seed&soul_shard=5
actions+=/seed_of_corruption,if=variable.use_seed&soul_shard=5
actions+=/call_action_list,name=dots
actions+=/vile_taint,target_if=max:target.time_to_die,if=time>15&target.time_to_die>=10&(cooldown.summon_darkglare.remains>30|cooldown.summon_darkglare.remains<10&dot.agony.remains>=10&dot.corruption.remains>=10&(dot.siphon_life.remains>=10|!talent.siphon_life.enabled))
actions+=/use_item,name=azsharas_font_of_power,if=time<=3
actions+=/phantom_singularity,if=time<=35
actions+=/vile_taint,if=time<15
actions+=/dark_soul,if=cooldown.summon_darkglare.remains<15&(dot.phantom_singularity.remains|dot.vile_taint.remains)
actions+=/berserking
actions+=/call_action_list,name=spenders
actions+=/call_action_list,name=fillers
]]
	local apl
	Player.maintain_se = (Player.enemies <= 1 and 1 or 0) + (WritheInAgony.known and 1 or 0) + (AbsoluteCorruption.known and 2 or 0) + (WritheInAgony.known and SowTheSeeds.known and Player.enemies > 2 and 1 or 0) + (SiphonLife.known and not CreepingDeath.known and not DrainSoul.known and 1 or 0)
	if self.use_cds then
		self:cooldowns()
	end
	if DrainSoul:Usable() and Target.timeToDie <= Player.gcd and Player.soul_shards.current < 5 then
		return DrainSoul
	end
	if Haunt:Usable() and Player.enemies <= 2 then
		return Haunt
	end
	if self.use_cds and SummonDarkglare:Usable() and Agony:Up() and Corruption:Up() and UnstableAffliction:Up() and (not PhantomSingularity.known or PhantomSingularity:Up()) and (not SoulRot.known or SoulRot:Up()) then
		UseCooldown(SummonDarkglare)
	end
	if Agony:Usable() and Agony:Remains() <= Player.gcd + ShadowBolt:CastTime() and Target.timeToDie > 8 then
		return Agony
	end
	if UnstableAffliction:Usable() and Target.timeToDie <= 8 and UnstableAffliction:Down() then
		return UnstableAffliction
	end
	if ShadowEmbrace.known and Player.maintain_se and ShadowEmbrace:Up() then
		if DrainSoul:Usable() and ShadowEmbrace:Remains() <= (Player.gcd * 2) then
			return DrainSoul
		end
		if ShadowBolt:Usable() and ShadowEmbrace:Remains() <= (ShadowBolt:CastTime() * 2 + ShadowBolt:TravelTime()) and ShadowBolt:Traveling() == 0 then
			return ShadowBolt
		end
	end
	if PhantomSingularity:Usable() and Player:TimeInCombat() > 35 and Target.timeToDie > (16 * Player.haste_factor) then
		UseCooldown(PhantomSingularity)
	end
	if Player.soul_shards.current == 5 then
		if self.use_seed then
			if SeedOfCorruption:Usable() then
				return SeedOfCorruption
			end
		else
			if MaleficRapture:Usable() and Player.dot_count >= 2 then
				return MaleficRapture
			end
		end
	end
	apl = self:dots()
	if apl then return apl end
	if VileTaint:Usable() and Player:TimeInCombat() > 15 and Target.timeToDie >= 10 and (not between(SummonDarkglare:Cooldown(), 10, 30) and Agony:Remains() >= 10 and Corruption:Remains() >= 10 and (not SiphonLife.known or SiphonLife:Remains() >= 10)) then
		UseCooldown(VileTaint)
	end
	if PhantomSingularity:Usable() and Player:TimeInCombat() <= 35 then
		UseCooldown(PhantomSingularity)
	end
	if VileTaint:Usable() and Player:TimeInCombat() < 15 then
		UseCooldown(VileTaint)
	end
	if self.use_cds and DarkSoulMisery:Usable() and SummonDarkglare:Cooldown() < 15 and (PhantomSingularity:Up() or VileTaint:Up()) then
		UseCooldown(DarkSoulMisery)
	end
	if SoulRot:Usable() and SoulRot:Remains() < SoulRot:CastTime() and (SummonDarkglare:Ready(5) or not SummonDarkglare:Ready(50)) then
		UseCooldown(SoulRot)
	end
	apl = self:spenders()
	if apl then return apl end
	apl = self:fillers()
	if apl then return apl end
end

APL[SPEC.AFFLICTION].cooldowns = function(self)
--[[
actions.cooldowns+=/potion,if=(talent.dark_soul_misery.enabled&cooldown.summon_darkglare.up&cooldown.dark_soul.up)|cooldown.summon_darkglare.up|target.time_to_die<30
actions.cooldowns+=/use_items,if=cooldown.summon_darkglare.remains>70|time_to_die<20|((buff.active_uas.stack=5|soul_shard=0)&(!talent.phantom_singularity.enabled|cooldown.phantom_singularity.remains)&!cooldown.summon_darkglare.remains)
actions.cooldowns+=/fireblood,if=!cooldown.summon_darkglare.up
actions.cooldowns+=/blood_fury,if=!cooldown.summon_darkglare.up
actions.cooldowns+=/dark_soul,if=target.time_to_die<20+gcd|spell_targets.seed_of_corruption_aoe>1+raid_event.invulnerable.up|talent.sow_the_seeds.enabled&cooldown.summon_darkglare.remains>=cooldown.summon_darkglare.duration-10
]]
	if Opt.trinket and (not DarkSoulMisery.known or not DarkSoulMisery:Ready()) and (SummonDarkglare:Cooldown() > 70 or Target.timeToDie < 20 or (UnstableAffliction:Up() and (not PhantomSingularity.known or PhantomSingularity:Up()) and (SummonDarkglare:Ready() or Pet.Darkglare:Up()))) then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
	if DarkSoulMisery:Usable() and (Target.timeToDie < 20 + Player.gcd or Player.enemies > 1 or (SowTheSeeds.known and SummonDarkglare:Cooldown() >= 170)) then
		return UseCooldown(DarkSoulMisery)
	end
end

APL[SPEC.AFFLICTION].dots = function(self)
--[[
actions.dots=seed_of_corruption,if=dot.corruption.remains<=action.seed_of_corruption.cast_time+time_to_shard+4.2*(1-talent.creeping_death.enabled*0.15)&spell_targets.seed_of_corruption_aoe>=3+raid_event.invulnerable.up+talent.writhe_in_agony.enabled&!dot.seed_of_corruption.remains&!action.seed_of_corruption.in_flight
actions.dots+=/agony,target_if=min:remains,if=talent.creeping_death.enabled&active_dot.agony<6&target.time_to_die>10&(remains<=gcd|cooldown.summon_darkglare.remains>10&(remains<5|refreshable))
actions.dots+=/agony,target_if=min:remains,if=!talent.creeping_death.enabled&active_dot.agony<8&target.time_to_die>10&(remains<=gcd|cooldown.summon_darkglare.remains>10&(remains<5|refreshable))
actions.dots+=/siphon_life,target_if=min:remains,if=(active_dot.siphon_life<8-talent.creeping_death.enabled-spell_targets.sow_the_seeds_aoe)&target.time_to_die>10&refreshable&(!remains&spell_targets.seed_of_corruption_aoe=1|cooldown.summon_darkglare.remains>soul_shard*action.unstable_affliction.execute_time)
actions.dots+=/corruption,cycle_targets=1,if=spell_targets.seed_of_corruption_aoe<3+raid_event.invulnerable.up+talent.writhe_in_agony.enabled&(remains<=gcd|cooldown.summon_darkglare.remains>10&refreshable)&target.time_to_die>10
]]
	if Player.enemies >= 3 and SeedOfCorruption:Usable() and Corruption:Remains() < (SeedOfCorruption:CastTime() + (Corruption:Duration() * 0.3)) and SeedOfCorruption:Ticking() == 0 then
		return SeedOfCorruption
	end
	if Agony:Usable() and (Agony:Ticking() < (CreepingDeath.known and 6 or 8) and Target.timeToDie > 10 and (Agony:Remains() <= Player.gcd or SummonDarkglare:Cooldown() > 10 and (Agony:Remains() < 5 or Agony:Refreshable()))) then
		return Agony
	end
	if Corruption:Usable() and Player.enemies < (3 + (WritheInAgony.known and 1 or 0)) and (Corruption:Remains() <= Player.gcd or SummonDarkglare:Cooldown() > 10 and Corruption:Refreshable()) and Target.timeToDie > 10 then
		return Corruption
	end
	if UnstableAffliction:Usable() and (UnstableAffliction:Up() or UnstableAffliction:Ticking() == 0) and UnstableAffliction:Refreshable() and Target.timeToDie > UnstableAffliction:Remains() then
		return UnstableAffliction
	end
	if SiphonLife:Usable() and (SiphonLife:Ticking() < (8 - (CreepingDeath.known and 1 or 0) - Player.enemies)) and Target.timeToDie > 10 and SiphonLife:Refreshable() then
		return SiphonLife
	end
end

APL[SPEC.AFFLICTION].fillers = function(self)
--[[
actions.fillers+=/shadow_bolt,if=buff.movement.up&buff.nightfall.remains
actions.fillers+=/agony,if=buff.movement.up&!(talent.siphon_life.enabled&(prev_gcd.1.agony&prev_gcd.2.agony&prev_gcd.3.agony)|prev_gcd.1.agony)
actions.fillers+=/siphon_life,if=buff.movement.up&!(prev_gcd.1.siphon_life&prev_gcd.2.siphon_life&prev_gcd.3.siphon_life)
actions.fillers+=/corruption,if=buff.movement.up&!prev_gcd.1.corruption&!talent.absolute_corruption.enabled
actions.fillers+=/drain_life,if=buff.inevitable_demise.stack>10&target.time_to_die<=10
actions.fillers+=/drain_life,if=talent.siphon_life.enabled&buff.inevitable_demise.stack>=50-20*(spell_targets.seed_of_corruption_aoe-raid_event.invulnerable.up>=2)&dot.agony.remains>5*spell_haste&dot.corruption.remains>gcd&(dot.siphon_life.remains>gcd|!talent.siphon_life.enabled)&(debuff.haunt.remains>5*spell_haste|!talent.haunt.enabled)&contagion>5*spell_haste
actions.fillers+=/drain_life,if=talent.writhe_in_agony.enabled&buff.inevitable_demise.stack>=50-20*(spell_targets.seed_of_corruption_aoe-raid_event.invulnerable.up>=3)-5*(spell_targets.seed_of_corruption_aoe-raid_event.invulnerable.up=2)&dot.agony.remains>5*spell_haste&dot.corruption.remains>gcd&(debuff.haunt.remains>5*spell_haste|!talent.haunt.enabled)&contagion>5*spell_haste
actions.fillers+=/drain_life,if=talent.absolute_corruption.enabled&buff.inevitable_demise.stack>=50-20*(spell_targets.seed_of_corruption_aoe-raid_event.invulnerable.up>=4)&dot.agony.remains>5*spell_haste&(debuff.haunt.remains>5*spell_haste|!talent.haunt.enabled)&contagion>5*spell_haste
actions.fillers+=/haunt
actions.fillers+=/drain_soul,interrupt_global=1,chain=1,interrupt=1,cycle_targets=1,if=target.time_to_die<=gcd
actions.fillers+=/drain_soul,target_if=min:debuff.shadow_embrace.remains,chain=1,interrupt_if=ticks_remain<5,interrupt_global=1,if=talent.shadow_embrace.enabled&variable.maintain_se&!debuff.shadow_embrace.remains
actions.fillers+=/drain_soul,target_if=min:debuff.shadow_embrace.remains,chain=1,interrupt_if=ticks_remain<5,interrupt_global=1,if=talent.shadow_embrace.enabled&variable.maintain_se
actions.fillers+=/drain_soul,interrupt_global=1,chain=1,interrupt=1
actions.fillers+=/shadow_bolt,cycle_targets=1,if=talent.shadow_embrace.enabled&variable.maintain_se&!debuff.shadow_embrace.remains&!action.shadow_bolt.in_flight
actions.fillers+=/shadow_bolt,target_if=min:debuff.shadow_embrace.remains,if=talent.shadow_embrace.enabled&variable.maintain_se
actions.fillers+=/shadow_bolt
]]
	local apl
	if Player.moving then
		if ShadowBolt:Usable() and Nightfall.known and Nightfall:Up() then
			return ShadowBolt
		end
--[[
		if Agony:Usable() and not (SiphonLife.known and (Agony:Previous() and Agony:Previous(2) and Agony:Previous(3)) or Agony:Previous()) then
			return Agony
		end
		if SiphonLife:Usable() and not (SiphonLife:Previous() or SiphonLife:Previous(2) or SiphonLife:Previous(3)) then
			return SiphonLife
		end
		if Corruption:Usable() and not (AbsoluteCorruption.known or Corruption:Previous()) then
			return Corruption
		end
]]
	end
	if InevitableDemise.known and DrainLife:Usable() then
		if InevitableDemise:Stack() > 10 and Target.timeToDie <= 5 then
			return DrainLife
		end
		if InevitableDemise:Stack() >= clamp(60 - Agony:Ticking() * 10, 30, 50) and Agony:Remains() > (5 * Player.haste_factor) and Corruption:Remains() > (5 * Player.haste_factor) and (not SiphonLife.known or SiphonLife:Remains() > (5 * Player.haste_factor)) and (not Haunt.known or Haunt:Remains() > (5 * Player.haste_factor)) and UnstableAffliction:Remains() > (5 * Player.haste_factor) then
			return DrainLife
		end
	end
	if Haunt:Usable() then
		return Haunt
	end
	if DrainLife:Usable() then
		if (Player.mana.pct > 5 and Player.health.pct < 20) or (Player.mana.pct > 20 and Player.health.pct < 40) then
			return DrainLife
		end
		if RotAndDecay.known and Player.mana.pct > 50 and UnstableAffliction:Up() and Corruption:Remains() > 3 and Agony:Remains() > 3 and (not DrainSoul.known or Target.health.pct > 20) then
			return DrainLife
		end
		if not DrainSoul.known and Target.timeToDie < ShadowBolt:CastTime() then
			return DrainLife
		end
	end
	if DrainSoul:Usable() then
		return DrainSoul
	end
	if ShadowBolt:Usable() then
		return ShadowBolt
	end
end

APL[SPEC.AFFLICTION].spenders = function(self)
--[[
actions.spenders+=/call_action_list,name=fillers,if=(cooldown.summon_darkglare.remains<time_to_shard*(5-soul_shard)|cooldown.summon_darkglare.up)&time_to_die>cooldown.summon_darkglare.remains
actions.spenders+=/seed_of_corruption,if=variable.use_seed
]]
	if self.use_cds and (SummonDarkglare:Ready(5 - Player.soul_shards.current) or Pet.Darkglare:Up()) and Target.timeToDie > SummonDarkglare:Cooldown() then
		local apl = self:fillers()
		if apl then return apl end
	end
	if self.use_seed and SeedOfCorruption:Usable() then
		return SeedOfCorruption
	end
	if MaleficRapture:Usable() and (Player.soul_shards.current >= 5 or ShadowEmbrace:Stack() >= 3 or Player.enemies >= 3 or Target.timeToDie < (MaleficRapture:CastTime() * Player.soul_shards.current)) then
		if Player.soul_shards.current >= 4 and Player.dot_count >= (3 + (SiphonLife.known and 1 or 0)) then
			return MaleficRapture
		end
		if Player.soul_shards.current >= 3 and Player.dot_count >= (3 + (SiphonLife.known and 1 or 0) + (VileTaint.known and 1 or 0)) then
			return MaleficRapture
		end
		if Player.dot_count >= (3 + (SiphonLife.known and 1 or 0) + (VileTaint.known and 1 or 0) + (PhantomSingularity.known and 1 or 0)) then
			return MaleficRapture
		end
	end
end

APL[SPEC.DEMONOLOGY].Main = function(self)
	self:variables()

	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/summon_pet
actions.precombat+=/snapshot_stats
actions.precombat+=/variable,name=shadow_timings,default=0,op=reset
actions.precombat+=/variable,name=shadow_timings,op=set,value=0,if=cooldown.invoke_power_infusion_0.duration!=120
actions.precombat+=/variable,name=trinket_1_buffs,value=trinket.1.has_buff.intellect|trinket.1.has_buff.mastery|trinket.1.has_buff.versatility|trinket.1.has_buff.haste|trinket.1.has_buff.crit|trinket.1.is.mirror_of_fractured_tomorrows
actions.precombat+=/variable,name=trinket_2_buffs,value=trinket.2.has_buff.intellect|trinket.2.has_buff.mastery|trinket.2.has_buff.versatility|trinket.2.has_buff.haste|trinket.2.has_buff.crit|trinket.2.is.mirror_of_fractured_tomorrows
actions.precombat+=/variable,name=trinket_1_exclude,value=trinket.1.is.ruby_whelp_shell|trinket.1.is.whispering_incarnate_icon
actions.precombat+=/variable,name=trinket_2_exclude,value=trinket.2.is.ruby_whelp_shell|trinket.2.is.whispering_incarnate_icon
actions.precombat+=/variable,name=trinket_1_manual,value=trinket.1.is.nymues_unraveling_spindle
actions.precombat+=/variable,name=trinket_2_manual,value=trinket.2.is.nymues_unraveling_spindle
actions.precombat+=/variable,name=trinket_1_sync,op=setif,value=1,value_else=0.5,condition=variable.trinket_1_buffs&(trinket.1.cooldown.duration%%cooldown.summon_demonic_tyrant.duration=0|cooldown.summon_demonic_tyrant.duration%%trinket.1.cooldown.duration=0)
actions.precombat+=/variable,name=trinket_2_sync,op=setif,value=1,value_else=0.5,condition=variable.trinket_2_buffs&(trinket.2.cooldown.duration%%cooldown.summon_demonic_tyrant.duration=0|cooldown.summon_demonic_tyrant.duration%%trinket.2.cooldown.duration=0)
actions.precombat+=/variable,name=trinket_priority,op=setif,value=2,value_else=1,condition=!variable.trinket_1_buffs&variable.trinket_2_buffs|variable.trinket_2_buffs&((trinket.2.cooldown.duration%trinket.2.proc.any_dps.duration)*(1.5+trinket.2.has_buff.intellect)*(variable.trinket_2_sync))>((trinket.1.cooldown.duration%trinket.1.proc.any_dps.duration)*(1.5+trinket.1.has_buff.intellect)*(variable.trinket_1_sync))
actions.precombat+=/power_siphon
actions.precombat+=/demonbolt,if=!buff.power_siphon.up
actions.precombat+=/shadow_bolt
]]
		if Opt.healthstone and Healthstone:Charges() == 0 and CreateHealthstone:Usable() then
			return CreateHealthstone
		end
		if not Pet.active then
			if FelDomination:Usable() then
				UseCooldown(FelDomination)
			end
			if SummonFelguard:Usable() then
				return SummonFelguard
			end
		end
		if PowerSiphon:Usable() and Pet.imp_count >= 2 and (DemonicCore:Stack() <= 2 or DemonicCore:Remains() < (Player.gcd * 3)) and Pet.Dreadstalker:Expiring(Player.gcd * 3) == 0 then
			UseCooldown(PowerSiphon)
		end
		if Target.boss and Pet.count < 6 and Player.soul_shards.current <= 3 then
			if Demonbolt:Usable() and DemonicCore:Down() then
				return Demonbolt
			end
			if ShadowBolt:Usable() then
				return ShadowBolt
			end
		end
	else
		if not Pet.active then
			if FelDomination:Usable() then
				UseCooldown(FelDomination)
			end
			if SummonFelguard:Usable() then
				UseExtra(SummonFelguard)
			end
		end
	end
--[[
actions=call_action_list,name=variables
actions+=/call_action_list,name=racials,if=pet.demonic_tyrant.active|fight_remains<22,use_off_gcd=1
actions+=/call_action_list,name=items,use_off_gcd=1
actions+=/invoke_external_buff,name=power_infusion,if=(buff.nether_portal.up&buff.nether_portal.remains<3&talent.nether_portal)|fight_remains<20|pet.demonic_tyrant.active&fight_remains<100|fight_remains<25|(pet.demonic_tyrant.active|!talent.summon_demonic_tyrant&buff.dreadstalkers.up)
actions+=/call_action_list,name=fight_end,if=fight_remains<30
actions+=/call_action_list,name=tyrant,if=cooldown.summon_demonic_tyrant.remains<15&(!talent.summon_vilefiend.enabled|buff.vilefiend.up|cooldown.summon_vilefiend.remains<gcd.max*5)&(buff.dreadstalkers.up|cooldown.call_dreadstalkers.remains<gcd.max*5)&(!talent.grimoire_felguard.enabled|!set_bonus.tier30_2pc|buff.grimoire_felguard.up|cooldown.grimoire_felguard.remains<10|cooldown.grimoire_felguard.remains>25)&(!variable.shadow_timings|variable.tyrant_cd<15|fight_remains<40|buff.power_infusion.up)
actions+=/summon_demonic_tyrant,if=buff.vilefiend.up|buff.grimoire_felguard.up|cooldown.grimoire_felguard.remains>90
actions+=/summon_vilefiend,if=cooldown.summon_demonic_tyrant.remains>45
actions+=/demonbolt,target_if=(!debuff.doom_brand.up|action.hand_of_guldan.in_flight&debuff.doom_brand.remains<=3),if=buff.demonic_core.up&(((!talent.soul_strike|cooldown.soul_strike.remains>gcd.max*2)&soul_shard<4)|soul_shard<(4-(active_enemies>2)))&!prev_gcd.1.demonbolt&set_bonus.tier31_2pc
actions+=/power_siphon,if=!buff.demonic_core.up&(!debuff.doom_brand.up|(!action.hand_of_guldan.in_flight&debuff.doom_brand.remains<gcd.max+action.demonbolt.travel_time)|(action.hand_of_guldan.in_flight&debuff.doom_brand.remains<gcd.max+action.demonbolt.travel_time+3))&set_bonus.tier31_2pc
actions+=/demonic_strength,if=buff.nether_portal.remains<gcd.max&(fight_remains>63&!(fight_remains>cooldown.summon_demonic_tyrant.remains+69)|cooldown.summon_demonic_tyrant.remains>30|variable.shadow_timings|buff.rite_of_ruvaraad.up|!talent.summon_demonic_tyrant|!talent.grimoire_felguard|!set_bonus.tier30_2pc)
actions+=/bilescourge_bombers
actions+=/guillotine,if=buff.nether_portal.remains<gcd.max&(cooldown.demonic_strength.remains|!talent.demonic_strength)
actions+=/call_dreadstalkers,if=cooldown.summon_demonic_tyrant.remains>25|variable.tyrant_cd>25|buff.nether_portal.up
# If Tyrant is not up, it Implodes naturally. On 3-4t it waits till <6s left on Tyrant. On 5t+ it waits till <8s left on Tyrant
actions+=/implosion,if=two_cast_imps>0&variable.impl&!prev_gcd.1.implosion&buff.wild_imps.stack>8
actions+=/summon_soulkeeper,if=buff.tormented_soul.stack=10&active_enemies>1
actions+=/demonic_strength,if=(fight_remains>63&!(fight_remains>cooldown.summon_demonic_tyrant.remains+69)|cooldown.summon_demonic_tyrant.remains>30|buff.rite_of_ruvaraad.up|variable.shadow_timings|!talent.summon_demonic_tyrant|!talent.grimoire_felguard|!set_bonus.tier30_2pc)
# Uses HoG as long as you will have 2 shards ready for Dogs or are capped on Shards (1T and Wilf only)
actions+=/hand_of_guldan,if=((soul_shard>2&cooldown.call_dreadstalkers.remains>gcd.max*4&cooldown.summon_demonic_tyrant.remains>17)|soul_shard=5|soul_shard=4&talent.soul_strike&cooldown.soul_strike.remains<gcd.max*2)&(active_enemies=1&talent.grand_warlocks_design)
actions+=/hand_of_guldan,if=soul_shard>2&!(active_enemies=1&talent.grand_warlocks_design)
# Demonbolt if we have more than one core
actions+=/demonbolt,target_if=(!debuff.doom_brand.up|action.hand_of_guldan.in_flight&debuff.doom_brand.remains<=3)|active_enemies<4,if=buff.demonic_core.stack>1&((soul_shard<4&!talent.soul_strike|cooldown.soul_strike.remains>gcd.max*2)|soul_shard<3)&!variable.pool_cores_for_tyrant
# Demonbolt if 2pc is safe
actions+=/demonbolt,target_if=(!debuff.doom_brand.up|action.hand_of_guldan.in_flight&debuff.doom_brand.remains<=3)|active_enemies<4,if=set_bonus.tier31_2pc&(debuff.doom_brand.remains>10&buff.demonic_core.up&soul_shard<4)&!variable.pool_cores_for_tyrant
actions+=/demonbolt,if=fight_remains<buff.demonic_core.stack*gcd.max
# Aggressive Core usage if PS is coming off CD
actions+=/demonbolt,target_if=(!debuff.doom_brand.up|action.hand_of_guldan.in_flight&debuff.doom_brand.remains<=3)|active_enemies<4,if=buff.demonic_core.up&(cooldown.power_siphon.remains<4)&(soul_shard<4)&!variable.pool_cores_for_tyrant
actions+=/power_siphon,if=!buff.demonic_core.up
actions+=/summon_vilefiend,if=fight_remains<cooldown.summon_demonic_tyrant.remains+5
actions+=/doom,target_if=refreshable
actions+=/shadow_bolt
]]
	self:racials()
	self:items()
	local apl
	if Target.boss and Target.timeToDie < 30 then
		apl = self:fight_end()
		if apl then return apl end
	end
	if self.use_cds and self.tyrant_condition and SummonDemonicTyrant:Usable(15) and (
		(Pet.tyrant_cd < 15 or Target.timeToDie < 40 or PowerInfusion:Up()) and
		(Target.boss or Target.timeToDie > 25 or (Target.classification == 'elite' and Player.enemies > 1))
	) then
		self.tyrant_prep = true
	end
	if self.tyrant_prep then
		apl = self:tyrant()
		if apl then return apl end
	end
	if self.use_cds and SummonVilefiend:Usable() and not SummonDemonicTyrant:Ready(45) then
		UseCooldown(SummonVilefiend)
	end
	if DoomBrand.known then
		if Demonbolt:Usable() and DemonicCore:Up() and not Demonbolt:Previous() and (
			((not SoulStrike.known or not SoulStrike:Ready(Player.gcd * 2)) and Player.soul_shards.current < 4) or
			Player.soul_shards.current < (4 - (Player.enemies > 2 and 1 or 0))
		) then
			return Demonbolt
		end
		if PowerSiphon:Usable() and DemonicCore:Down() and Pet.imp_count >= 2 and (
			DoomBrand:Down() or
			(DoomBrand:Remains() < (Player.gcd + Demonbolt:TravelTime() + (HandOfGuldan:Traveling() and 3 or 0)))
		) then
			UseCooldown(PowerSiphon)
		end
	end
	if self.use_cds and DemonicStrength:Usable() and (not NetherPortal.known or NetherPortal:Remains() < Player.gcd) and (
		(Target.timeToDie > 63 and not (Target.timeToDie > (SummonDemonicTyrant:Cooldown() + 69))) or
		not SummonDemonicTyrant:Ready(30) or
		(RiteOfRuvaraad.known and RiteOfRuvaraad:Up()) or
		not SummonDemonicTyrant.known or
		not GrimoireFelguard.known or
		Player.set_bonus.t30 < 2
	) then
		UseCooldown(DemonicStrength)
	end
	if self.use_cds and BilescourgeBombers:Usable() then
		UseCooldown(BilescourgeBombers)
	end
	if self.use_cds and Guillotine:Usable() and (not NetherPortal.known or NetherPortal:Remains() < Player.gcd) and (not DemonicStrength.known or not DemonicStrength:Ready()) then
		UseCooldown(Guillotine)
	end
	if CallDreadstalkers:Usable() and (not self.use_cds or not SummonDemonicTyrant:Ready(25) or Pet.tyrant_cd > 25 or (Player.set_bonus.t30 >= 2 and GrimoireFelguard.known and not GrimoireFelguard:Ready(25)) or (NetherPortal.known and NetherPortal:Up())) then
		return CallDreadstalkers
	end
	if Implosion:Usable() and self.impl and Pet.imp_count > 8 and (Pet.WildImp:RemainsUnder(3 * Player.haste_factor) + Pet.WildImpID:RemainsUnder(3 * Player.haste_factor)) > 0 then
		return Implosion
	end
	if self.use_cds and SummonSoulkeeper:Usable() and TormentedSoul:Stack() >= 10 and Player.enemies > 1 then
		UseCooldown(SummonSoulkeeper)
	end
	if self.use_cds and DemonicStrength:Usable() and (
		(Target.timeToDie > 63 and not (Target.timeToDie > (SummonDemonicTyrant:Cooldown() + 69))) or
		not SummonDemonicTyrant:Ready(30) or
		(RiteOfRuvaraad.known and RiteOfRuvaraad:Up()) or
		not SummonDemonicTyrant.known or
		not GrimoireFelguard.known or
		Player.set_bonus.t30 < 2
	) then
		UseCooldown(DemonicStrength)
	end
	if Demonbolt:Usable() and DemonicCore:Up() and (
		(Player.soul_shards.current < 5 and DemonicCore:Remains() < (Player.gcd * 2)) or
		(Player.soul_shards.current < 4 and (DemonicCore:Stack() + Pet.Dreadstalker:Expiring(Player.gcd * 2)) > 4)
	) then
		return Demonbolt
	end
	if HandOfGuldan:Usable() and Player.soul_shards.current > 2 and (
		self.shard_capped or
		(not CallDreadstalkers:Ready(Player.gcd * 4) and not SummonDemonicTyrant:Ready(17)) or
		(Player.soul_shards.current == 4 and SoulStrike.known and SoulStrike:Ready(Player.gcd * 2) and GrandWarlocksDesign.known and Player.enemies == 1) or
		not (Player.enemies == 1 and GrandWarlocksDesign.known)
	) then
		return HandOfGuldan
	end
	if Demonbolt:Usable() and DemonicCore:Up() and not self.pool_cores_for_tyrant and (
		(DemonicCore:Stack() > 1 and (
			Player.soul_shards.current < 3 or
			(Player.soul_shards.current < 4 and not SoulStrike.known) or
			(SoulStrike.known and not SoulStrike:Ready(Player.gcd * 2))
		)) or
		(DoomBrand.known and DoomBrand:Remains() > 10 and Player.soul_shards.current < 4) or
		(Target.boss and Target.timeToDie < (DemonicCore:Stack() * Player.gcd)) or
		(PowerSiphon.known and PowerSiphon:Ready(4) and Player.soul_shards.current < 4)
	) then
		return Demonbolt
	end
	if PowerSiphon:Usable() and Pet.imp_count >= 2 and DemonicCore:Down() then
		UseCooldown(PowerSiphon)
	end
	if self.use_cds and SummonVilefiend:Usable() and Target.boss and Target.timeToDie < (SummonDemonicTyrant:Cooldown() + 5) then
		UseCooldown(SummonVilefiend)
	end
	if Doom:Usable() and Doom:Refreshable() and Target.timeToDie > (Doom:Remains() + Doom:TickTime()) then
		return Doom
	end
	if ShadowBolt:Usable() then
		return ShadowBolt
	end
end

APL[SPEC.DEMONOLOGY].tyrant = function(self)
--[[
actions.tyrant=invoke_external_buff,name=power_infusion,if=variable.pet_expire>0&variable.pet_expire<action.summon_demonic_tyrant.execute_time+(buff.demonic_core.down*action.shadow_bolt.execute_time+buff.demonic_core.up*gcd.max)+gcd.max
actions.tyrant+=/hand_of_guldan,if=variable.pet_expire>gcd.max+action.summon_demonic_tyrant.cast_time&variable.pet_expire<gcd.max*4
actions.tyrant+=/call_action_list,name=items,if=variable.pet_expire>0&variable.pet_expire<action.summon_demonic_tyrant.execute_time+(buff.demonic_core.down*action.shadow_bolt.execute_time+buff.demonic_core.up*gcd.max)+gcd.max,use_off_gcd=1
actions.tyrant+=/call_action_list,name=racials,if=variable.pet_expire>0&variable.pet_expire<action.summon_demonic_tyrant.execute_time+(buff.demonic_core.down*action.shadow_bolt.execute_time+buff.demonic_core.up*gcd.max)+gcd.max,use_off_gcd=1
actions.tyrant+=/potion,if=variable.pet_expire>0&variable.pet_expire<action.summon_demonic_tyrant.execute_time+(buff.demonic_core.down*action.shadow_bolt.execute_time+buff.demonic_core.up*gcd.max)+gcd.max,use_off_gcd=1
actions.tyrant+=/summon_demonic_tyrant,if=variable.pet_expire>0&variable.pet_expire<action.summon_demonic_tyrant.execute_time+(buff.demonic_core.down*action.shadow_bolt.execute_time+buff.demonic_core.up*gcd.max)+gcd.max
actions.tyrant+=/implosion,if=buff.wild_imps.stack>3&(buff.dreadstalkers.down&buff.grimoire_felguard.down&buff.vilefiend.down)&(active_enemies>3|active_enemies>2&talent.grand_warlocks_design)
actions.tyrant+=/shadow_bolt,if=prev_gcd.1.grimoire_felguard&time>30&buff.nether_portal.down&buff.demonic_core.down
actions.tyrant+=/power_siphon,if=buff.demonic_core.stack<4&(!buff.vilefiend.up|!talent.summon_vilefiend&(!buff.dreadstalkers.up))&(buff.nether_portal.down)
actions.tyrant+=/shadow_bolt,if=buff.vilefiend.down&buff.nether_portal.down&buff.dreadstalkers.down&soul_shard<5-buff.demonic_core.stack
actions.tyrant+=/nether_portal,if=soul_shard=5
actions.tyrant+=/summon_vilefiend,if=(soul_shard=5|buff.nether_portal.up)&cooldown.summon_demonic_tyrant.remains<13&variable.np
actions.tyrant+=/call_dreadstalkers,if=(buff.vilefiend.up|!talent.summon_vilefiend&(!talent.nether_portal|buff.nether_portal.up|cooldown.nether_portal.remains>30)&(buff.nether_portal.up|buff.grimoire_felguard.up|soul_shard=5|cooldown.grimoire_felguard.remains&buff.vilefiend.remains<9))&cooldown.summon_demonic_tyrant.remains<11&variable.np
actions.tyrant+=/grimoire_felguard,if=buff.vilefiend.up|!talent.summon_vilefiend&(!talent.nether_portal|buff.nether_portal.up|cooldown.nether_portal.remains>30)&(buff.nether_portal.up|buff.dreadstalkers.up|soul_shard=5)&variable.np
actions.tyrant+=/hand_of_guldan,if=soul_shard>2&(buff.vilefiend.up|!talent.summon_vilefiend&buff.dreadstalkers.up)&(soul_shard>2|buff.vilefiend.remains<gcd.max*2+2%spell_haste)
actions.tyrant+=/demonbolt,cycle_targets=1,if=soul_shard<4&buff.demonic_core.up&(buff.vilefiend.up|!talent.summon_vilefiend&buff.dreadstalkers.up)
actions.tyrant+=/power_siphon,if=buff.demonic_core.stack<3&variable.pet_expire>action.summon_demonic_tyrant.execute_time+gcd.max*3|variable.pet_expire=0
actions.tyrant+=/shadow_bolt
]]
	if HandOfGuldan:Usable() and self.pet_expire > (0.2 + HandOfGuldan:CastTime() + SummonDemonicTyrant:CastTime()) and SummonDemonicTyrant:Ready(HandOfGuldan:CastTime()) and self.pet_expire < (Player.gcd * 4) then
		return HandOfGuldan
	end
	if self.pet_expire > 0 and (
		(self.pet_expire < (SummonDemonicTyrant:CastTime() + Player.gcd + (DemonicCore:Up() and Player.gcd or ShadowBolt:CastTime()))) or
		(Player.soul_shards.current < 2 and DemonicCore:Down() and Player:ImpsIn(SummonDemonicTyrant:CastTime()) >= 10) or
		(ReignOfTyranny.known and Player:ImpsIn(SummonDemonicTyrant:CastTime()) >= 15)
	) then
		self:items()
		self:racials()
		-- potion
		if SummonDemonicTyrant:Usable() then
			UseCooldown(SummonDemonicTyrant)
		end
	end
	if Demonbolt:Usable() and Player.soul_shards.current < 4 and DemonicCore:Up() and (
		DemonicCore:Remains() < (Player.gcd * 2) or
		(DemonicCore:Stack() + Pet.Dreadstalker:Expiring(Player.gcd * 2)) > 4
	) then
		return Demonbolt
	end
	if PowerSiphon:Usable() and Pet.imp_count >= 2 and DemonicCore:Stack() < (3 - Pet.Dreadstalker:Expiring(Player.gcd * 3)) and (not NetherPortal.known or NetherPortal:Down()) and (Pet.Vilefiend:Down() or (not SummonVilefiend.known and Pet.Dreadstalker:Down())) then
		UseCooldown(PowerSiphon)
	end
	if Implosion:Usable() and self.impl and Pet.imp_count > 5 and (Pet.WildImp:RemainsUnder(3 * Player.haste_factor) + Pet.WildImpID:RemainsUnder(3 * Player.haste_factor)) > 0 and Pet.Dreadstalker:Down() and Pet.Felguard:Down() and Pet.Vilefiend:Down() then
		return Implosion
	end
	if NetherPortal:Usable() and self.shard_capped then
		UseCooldown(NetherPortal)
	end
	if GrimoireFelguard:Usable() and (
		(SummonVilefiend.known and (Pet.Vilefiend:Up() or SummonVilefiend:Ready(Player.gcd * 2))) or
		(not SummonVilefiend.known and self.np and (NetherPortal:Up() or Pet.Dreadstalker:Up() or self.shard_capped))
	) then
		UseCooldown(GrimoireFelguard)
	end
	if SummonVilefiend:Usable() and self.np and SummonDemonicTyrant:Ready(13) and (self.shard_capped or NetherPortal:Up()) then
		UseCooldown(SummonVilefiend)
	end
	if CallDreadstalkers:Usable() and self.np and SummonDemonicTyrant:Ready(11) and (
		(SummonVilefiend.known and Pet.Vilefiend:Up() and (DemonicCalling:Up() or Pet.Vilefiend:Remains() < 9)) or
		(
			(not SummonVilefiend.known or not SummonVilefiend:Ready(20)) and
			(not GrimoireFelguard.known or Pet.Felguard:Up() or GrimoireFelguard:Ready(6) or not GrimoireFelguard:Ready(20)) and
			(self.shard_capped or NetherPortal:Up() or Pet.Felguard:Up())
		)
	) then
		return CallDreadstalkers
	end
	if Demonbolt:Usable() and Player.soul_shards.current < 4 and DemonicCore:Up() and self.pet_expire > (0.2 + SummonDemonicTyrant:CastTime() + Player.gcd + HandOfGuldan:CastTime()) and Pet.Dreadstalker:Up() and (not SummonVilefiend.known or Pet.Vilefiend:Up()) then
		return Demonbolt
	end
	if ShadowBolt:Usable() and not self.shard_capped and self.pet_expire > (SummonDemonicTyrant:CastTime() + Player.gcd * (3 + (DemonicCore:Stack() * 2))) and (not SummonVilefiend.known or Pet.Vilefiend:Up()) then
		return ShadowBolt
	end
	if HandOfGuldan:Usable() and (self.shard_capped or (Player.soul_shards.current > 2 and (Pet.Vilefiend:Up() or (not SummonVilefiend.known and Pet.Dreadstalker:Up())))) then
		return HandOfGuldan
	end
	if Demonbolt:Usable() and DemonicCore:Up() and DemonicCore:Remains() < (Player.gcd * DemonicCore:Stack()) then
		return Demonbolt
	end
	if PowerSiphon:Usable() and Pet.imp_count >= 2 and DemonicCore:Stack() < (3 - Pet.Dreadstalker:Expiring(Player.gcd * 3)) and (self.pet_expire == 0 or self.pet_expire > (SummonDemonicTyrant:CastTime() + Player.gcd * (3 + DemonicCore:Stack()))) then
		UseCooldown(PowerSiphon)
	end
	if ShadowBolt:Usable() then
		return ShadowBolt
	end
end

APL[SPEC.DEMONOLOGY].fight_end = function(self)
--[[
actions.fight_end=grimoire_felguard,if=fight_remains<20
actions.fight_end+=/call_dreadstalkers,if=fight_remains<20
actions.fight_end+=/summon_vilefiend,if=fight_remains<20
actions.fight_end+=/nether_portal,if=fight_remains<30
actions.fight_end+=/summon_demonic_tyrant,if=fight_remains<20
actions.fight_end+=/demonic_strength,if=fight_remains<10
actions.fight_end+=/power_siphon,if=buff.demonic_core.stack<3&fight_remains<20
actions.fight_end+=/implosion,if=fight_remains<2*gcd.max
]]
	if Target.timeToDie < 20 then
		if GrimoireFelguard:Usable() then
			UseCooldown(GrimoireFelguard)
		end
		if CallDreadstalkers:Usable() then
			return CallDreadstalkers
		end
		if SummonVilefiend:Usable() then
			UseCooldown(SummonVilefiend)
		end
	end
	if NetherPortal:Usable() and Target.timeToDie < 30 then
		UseCooldown(NetherPortal)
	end
	if SummonDemonicTyrant:Usable() and Target.timeToDie < 20 then
		UseCooldown(SummonDemonicTyrant)
	end
	if DemonicStrength:Usable() and Target.timeToDie < 10 then
		UseCooldown(DemonicStrength)
	end
	if PowerSiphon:Usable() and Pet.imp_count >= 2 and DemonicCore:Stack() < (3 - Pet.Dreadstalker:Expiring(Player.gcd * 3)) and Target.timeToDie < 20 then
		UseCooldown(PowerSiphon)
	end
	if Implosion:Usable() and Target.timeToDie < (2 * Player.gcd) then
		return Implosion
	end
end

APL[SPEC.DEMONOLOGY].racials = function(self)
--[[
actions.racials=berserking,use_off_gcd=1
actions.racials+=/blood_fury
actions.racials+=/fireblood
actions.racials+=/ancestral_call
]]

end

APL[SPEC.DEMONOLOGY].items = function(self)
--[[
actions.items=use_item,use_off_gcd=1,slot=trinket1,if=variable.trinket_1_buffs&!variable.trinket_1_manual&(!pet.demonic_tyrant.active&trinket.1.cast_time>0|!trinket.1.cast_time>0)&(pet.demonic_tyrant.active)&(variable.trinket_2_exclude|!trinket.2.has_cooldown|trinket.2.cooldown.remains|variable.trinket_priority=1)|trinket.1.proc.any_dps.duration>=fight_remains
actions.items+=/use_item,use_off_gcd=1,slot=trinket2,if=variable.trinket_2_buffs&!variable.trinket_2_manual&(!pet.demonic_tyrant.active&trinket.2.cast_time>0|!trinket.2.cast_time>0)&(pet.demonic_tyrant.active)&(variable.trinket_1_exclude|!trinket.1.has_cooldown|trinket.1.cooldown.remains|variable.trinket_priority=2)|trinket.2.proc.any_dps.duration>=fight_remains
actions.items+=/use_item,use_off_gcd=1,slot=trinket1,if=!variable.trinket_1_buffs&!variable.trinket_1_manual&(!variable.trinket_1_buffs&(trinket.2.cooldown.remains|!variable.trinket_2_buffs)|(trinket.1.cast_time>0&!pet.demonic_tyrant.active|!trinket.1.cast_time>0)|cooldown.demonic_tyrant.remains_expected>20)
actions.items+=/use_item,use_off_gcd=1,slot=trinket2,if=!variable.trinket_2_buffs&!variable.trinket_2_manual&(!variable.trinket_2_buffs&(trinket.1.cooldown.remains|!variable.trinket_1_buffs)|(trinket.2.cast_time>0&!pet.demonic_tyrant.active|!trinket.2.cast_time>0)|cooldown.demonic_tyrant.remains_expected>20)
actions.items+=/use_item,use_off_gcd=1,slot=main_hand,if=(!variable.trinket_1_buffs|trinket.1.cooldown.remains)&(!variable.trinket_2_buffs|trinket.2.cooldown.remains)
actions.items+=/use_item,name=nymues_unraveling_spindle,if=pet.demonic_tyrant.active&!cooldown.demonic_strength.ready|fight_remains<22
actions.items+=/use_item,slot=trinket1,if=!variable.trinket_1_buffs&(trinket.2.cooldown.remains|!variable.trinket_2_buffs)
actions.items+=/use_item,slot=trinket2,if=!variable.trinket_2_buffs&(trinket.1.cooldown.remains|!variable.trinket_1_buffs)
]]
	if Opt.trinket and (Pet.tyrant_remains > 0 or (Target.boss and Target.timeToDie < 22)) then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		elseif Trinket.NymuesUnravelingSpindle:Usable() and (not DemonicStrength.known or not DemonicStrength:Ready()) then
			return UseCooldown(Trinket.NymuesUnravelingSpindle)
		end
	end
	if DreambinderLoomOfTheGreatCycle:Usable() and (
		(Pet.tyrant_remains == 0 and (not self.tyrant_prep or self.pet_expire == 0)) or
		(Pet.tyrant_remains > 0 and (not DemonicStrength.known or not DemonicStrength:Ready()))
	) then
		return UseCooldown(DreambinderLoomOfTheGreatCycle)
	end
	if IridalTheEarthsMaster:Usable() and (
		(Pet.tyrant_remains == 0 and (not self.tyrant_prep or self.pet_expire == 0)) or
		(Pet.tyrant_remains > 0 and (not DemonicStrength.known or not DemonicStrength:Ready()))
	) then
		return UseCooldown(IridalTheEarthsMaster)
	end
end

APL[SPEC.DEMONOLOGY].variables = function(self)
--[[
actions.variables=variable,name=tyrant_cd,op=setif,value=cooldown.invoke_power_infusion_0.remains,value_else=cooldown.summon_demonic_tyrant.remains,condition=((((fight_remains+time)%%120<=85&(fight_remains+time)%%120>=25)|time>=210)&variable.shadow_timings)&cooldown.invoke_power_infusion_0.duration>0&!talent.grand_warlocks_design
actions.variables+=/variable,name=pet_expire,op=set,value=(buff.dreadstalkers.remains>?buff.vilefiend.remains)-gcd*0.5,if=buff.vilefiend.up&buff.dreadstalkers.up
actions.variables+=/variable,name=pet_expire,op=set,value=(buff.dreadstalkers.remains>?buff.grimoire_felguard.remains)-gcd*0.5,if=!talent.summon_vilefiend&talent.grimoire_felguard&buff.dreadstalkers.up
actions.variables+=/variable,name=pet_expire,op=set,value=(buff.dreadstalkers.remains)-gcd*0.5,if=!talent.summon_vilefiend&(!talent.grimoire_felguard|!set_bonus.tier30_2pc)&buff.dreadstalkers.up
actions.variables+=/variable,name=pet_expire,op=set,value=0,if=!buff.vilefiend.up&talent.summon_vilefiend|!buff.dreadstalkers.up
actions.variables+=/variable,name=np,op=set,value=(!talent.nether_portal|cooldown.nether_portal.remains>30|buff.nether_portal.up)
actions.variables+=/variable,name=impl,op=set,value=0
actions.variables+=/variable,name=impl,op=set,value=buff.tyrant.down,if=active_enemies>1+(talent.sacrificed_souls.enabled)
actions.variables+=/variable,name=impl,op=set,value=buff.tyrant.remains<6,if=active_enemies>2+(talent.sacrificed_souls.enabled)&active_enemies<5+(talent.sacrificed_souls.enabled)
actions.variables+=/variable,name=impl,op=set,value=buff.tyrant.remains<8,if=active_enemies>4+(talent.sacrificed_souls.enabled)
actions.variables+=/variable,name=pool_cores_for_tyrant,op=set,value=cooldown.summon_demonic_tyrant.remains<20&variable.tyrant_cd<20&(buff.demonic_core.stack<=2|!buff.demonic_core.up)&cooldown.summon_vilefiend.remains<gcd.max*5&cooldown.call_dreadstalkers.remains<gcd.max*5
]]
	HandOfGuldan:Purge()
	Pet.count = SummonedPets:Count() + (Pet.alive and 1 or 0)
	Pet.imp_count = Pet.WildImp:Count() + Pet.WildImpID:Count()
	Pet.tyrant_cd = SummonDemonicTyrant:Cooldown()
	Pet.tyrant_remains = Pet.DemonicTyrant:Remains()
	Pet.tyrant_power = Pet.DemonicTyrant:Power()
	Pet.tyrant_available_power = Pet.DemonicTyrant:AvailablePower()
	if Pet.tyrant_cd > 20 then
		self.tyrant_prep = false
	end
	self.use_cds = Opt.cooldown and (Target.boss or Target.player or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd) or Pet.tyrant_remains > 0)
	self.shard_capped = Player.soul_shards.current >= (5 - ((SoulStrike.known and SoulStrike:Ready(Player.gcd * 2)) and 1 or 0))
	self.pet_expire = Pet.Dreadstalker:Remains()
	if self.pet_expire > 0 then
		if SummonVilefiend.known and (Pet.Vilefiend:Up() or SummonVilefiend:Ready(12)) then
			self.pet_expire = min(self.pet_expire, Pet.Vilefiend:Remains())
		end
		if GrimoireFelguard.known and (Pet.Felguard:Up() or (Pet.Vilefiend:Down() and GrimoireFelguard:Ready(12))) then
			self.pet_expire = min(self.pet_expire, Pet.Felguard:Remains())
		end
		self.pet_expire = max(0, self.pet_expire - Player.gcd * 0.5)
	end
	self.np = not NetherPortal.known or not NetherPortal:Ready(30) or NetherPortal:Up()
	self.impl = false
	if Player.enemies > (1 + (SacrificedSouls.known and 1 or 0)) then
		self.impl = Pet.tyrant_remains == 0
	end
	if Player.enemies > (2 + (SacrificedSouls.known and 1 or 0)) and Player.enemies < (5 + (SacrificedSouls.known and 1 or 0)) then
		self.impl = Pet.tyrant_remains < 6
	end
	if Player.enemies > (4 + (SacrificedSouls.known and 1 or 0)) then
		self.impl = Pet.tyrant_remains < 8
	end
	self.tyrant_condition = self.use_cds and Pet.tyrant_cd < 20 and (
		(not SummonVilefiend.known or Pet.Vilefiend:Up() or SummonVilefiend:Ready(Player.gcd * 5)) and
		(Pet.Dreadstalker:Up() or CallDreadstalkers:Ready(Player.gcd * 5)) and
		(not GrimoireFelguard.known or Player.set_bonus.t30 < 2 or Pet.Felguard:Up() or GrimoireFelguard:Ready(15))
	)
	self.pool_cores_for_tyrant = self.tyrant_condition and SummonDemonicTyrant:Usable(20) and DemonicCore:Stack() <= 2
end

APL[SPEC.DEMONOLOGY].precombat_variables = function(self)
	self.tyrant_prep = false
end

APL[SPEC.DESTRUCTION].Main = function(self)
	self:variables()

	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/summon_pet
actions.precombat+=/variable,name=cleave_apl,default=0,op=reset
actions.precombat+=/variable,name=trinket_1_buffs,value=trinket.1.has_use_buff
actions.precombat+=/variable,name=trinket_2_buffs,value=trinket.2.has_use_buff
actions.precombat+=/variable,name=trinket_1_sync,op=setif,value=1,value_else=0.5,condition=variable.trinket_1_buffs&(trinket.1.cooldown.duration%%cooldown.summon_infernal.duration=0|cooldown.summon_infernal.duration%%trinket.1.cooldown.duration=0)
actions.precombat+=/variable,name=trinket_2_sync,op=setif,value=1,value_else=0.5,condition=variable.trinket_2_buffs&(trinket.2.cooldown.duration%%cooldown.summon_infernal.duration=0|cooldown.summon_infernal.duration%%trinket.2.cooldown.duration=0)
actions.precombat+=/variable,name=trinket_1_manual,value=trinket.1.is.belorrelos_the_suncaller|trinket.1.is.nymues_unraveling_spindle|trinket.1.is.timethiefs_gambit
actions.precombat+=/variable,name=trinket_2_manual,value=trinket.2.is.belorrelos_the_suncaller|trinket.2.is.nymues_unraveling_spindle|trinket.2.is.timethiefs_gambit
actions.precombat+=/variable,name=trinket_1_exclude,value=trinket.1.is.ruby_whelp_shell|trinket.1.is.whispering_incarnate_icon
actions.precombat+=/variable,name=trinket_2_exclude,value=trinket.2.is.ruby_whelp_shell|trinket.2.is.whispering_incarnate_icon
actions.precombat+=/variable,name=trinket_1_buff_duration,value=trinket.1.proc.any_dps.duration+(trinket.1.is.mirror_of_fractured_tomorrows*20)+(trinket.1.is.nymues_unraveling_spindle*2)
actions.precombat+=/variable,name=trinket_2_buff_duration,value=trinket.2.proc.any_dps.duration+(trinket.2.is.mirror_of_fractured_tomorrows*20)+(trinket.2.is.nymues_unraveling_spindle*2)
actions.precombat+=/variable,name=trinket_priority,op=setif,value=2,value_else=1,condition=!variable.trinket_1_buffs&variable.trinket_2_buffs|variable.trinket_2_buffs&((trinket.2.cooldown.duration%variable.trinket_2_buff_duration)*(1+0.5*trinket.2.has_buff.intellect)*(variable.trinket_2_sync)*(1-0.5*trinket.2.is.mirror_of_fractured_tomorrows))>((trinket.1.cooldown.duration%variable.trinket_1_buff_duration)*(1+0.5*trinket.1.has_buff.intellect)*(variable.trinket_1_sync)*(1-0.5*trinket.1.is.mirror_of_fractured_tomorrows))
actions.precombat+=/grimoire_of_sacrifice,if=talent.grimoire_of_sacrifice.enabled
actions.precombat+=/snapshot_stats
actions.precombat+=/soul_fire
actions.precombat+=/cataclysm,if=raid_event.adds.in>15
actions.precombat+=/incinerate
]]
		if Opt.healthstone and Healthstone:Charges() == 0 and CreateHealthstone:Usable() then
			return CreateHealthstone
		end
		if GrimoireOfSacrifice:Usable() then
			return GrimoireOfSacrifice
		end
		if not Pet.active and (not GrimoireOfSacrifice.known or GrimoireOfSacrifice:Remains() < 300) then
			if FelDomination:Usable() then
				UseCooldown(FelDomination)
			end
			if SummonImp:Usable() then
				return SummonImp
			end
		end
		if Target.boss and SoulFire:Usable() and Player.soul_shards.deficit > 2.2 then
			return SoulFire
		end
		if self.use_cds and Cataclysm:Usable() then
			UseCooldown(Cataclysm)
		end
		if Incinerate:Usable() and Player.soul_shards.deficit > 1.5 then
			return Incinerate
		end
	else
		if GrimoireOfSacrifice:Usable() then
			UseCooldown(GrimoireOfSacrifice)
		end
		if not Pet.active and (not GrimoireOfSacrifice.known or GrimoireOfSacrifice:Remains() < 10) then
			if FelDomination:Usable() then
				UseCooldown(FelDomination)
			end
			if SummonImp:Usable() then
				UseExtra(SummonImp)
			end
		end
	end
--[[
actions=call_action_list,name=variables
actions+=/call_action_list,name=aoe,if=(active_enemies>=3-(talent.inferno&!talent.chaosbringer))&!(!talent.inferno&talent.chaosbringer&talent.chaos_incarnate&active_enemies<4)&!variable.cleave_apl
actions+=/call_action_list,name=cleave,if=active_enemies!=1|variable.cleave_apl
actions+=/call_action_list,name=ogcd
actions+=/call_action_list,name=items
actions+=/conflagrate,if=(talent.roaring_blaze&debuff.conflagrate.remains<1.5)&soul_shard>1.5|charges=max_charges
actions+=/dimensional_rift,if=soul_shard<4.7&(charges>2|fight_remains<cooldown.dimensional_rift.duration)
actions+=/cataclysm,if=raid_event.adds.in>15
actions+=/channel_demonfire,if=talent.raging_demonfire&(dot.immolate.remains-5*(action.chaos_bolt.in_flight&talent.internal_combustion))>cast_time&(debuff.conflagrate.remains>execute_time|!talent.roaring_blaze)
actions+=/soul_fire,if=soul_shard<=3.5&(debuff.conflagrate.remains>cast_time+travel_time|!talent.roaring_blaze&buff.backdraft.up)
actions+=/immolate,if=(((dot.immolate.remains-5*(action.chaos_bolt.in_flight&talent.internal_combustion))<dot.immolate.duration*0.3)|dot.immolate.remains<3|(dot.immolate.remains-action.chaos_bolt.execute_time)<5&talent.internal_combustion&action.chaos_bolt.usable)&(!talent.cataclysm|cooldown.cataclysm.remains>dot.immolate.remains)&(!talent.soul_fire|cooldown.soul_fire.remains+action.soul_fire.cast_time>(dot.immolate.remains-5*talent.internal_combustion))&target.time_to_die>8
actions+=/channel_demonfire,if=dot.immolate.remains>cast_time&set_bonus.tier30_4pc
actions+=/chaos_bolt,if=cooldown.summon_infernal.remains=0&soul_shard>4&talent.crashing_chaos
actions+=/summon_infernal
actions+=/chaos_bolt,if=pet.infernal.active|pet.blasphemy.active|soul_shard>=4
actions+=/channel_demonfire,if=talent.ruin.rank>1&!(talent.diabolic_embers&talent.avatar_of_destruction&(talent.burn_to_ashes|talent.chaos_incarnate))&dot.immolate.remains>cast_time
actions+=/chaos_bolt,if=buff.rain_of_chaos.remains>cast_time
actions+=/chaos_bolt,if=buff.backdraft.up
actions+=/channel_demonfire,if=!(talent.diabolic_embers&talent.avatar_of_destruction&(talent.burn_to_ashes|talent.chaos_incarnate))&dot.immolate.remains>cast_time
actions+=/dimensional_rift
actions+=/chaos_bolt,if=fight_remains<5&fight_remains>cast_time+travel_time
actions+=/conflagrate,if=charges>(max_charges-1)|fight_remains<gcd.max*charges
actions+=/conflagrate,if=talent.backdraft&soul_shard>1.5&charges_fractional>1.5&buff.backdraft.down
actions+=/incinerate
]]
	if (Player.enemies >= (3 - (Inferno.known and not Chaosbringer.known and 1 or 0))) and not (not Inferno.known and Chaosbringer.known and ChaosIncarnate.known and Player.enemies < 4) and not self.cleave_apl then
		local apl = self:aoe()
		if apl then return apl end
	end
	if Player.enemies > 1 or self.cleave_apl then
		local apl = self:cleave()
		if apl then return apl end
	end
	self:ogcd()
	self:items()
	if Conflagrate:Usable() and (
		((RoaringBlaze.known and Conflagrate:Remains() < 1.5) and Player.soul_shards.current > 1.5) or
		Conflagrate:FullRechargeTime() == 0
	) then
		return Conflagrate
	end
	if self.use_cds then
		if DimensionalRift:Usable() and Player.soul_shards.current < 4.7 and (
			DimensionalRift:Charges() > 2 or
			(Target.boss and Target.timeToDie < DimensionalRift:CooldownDuration())
		) then
			UseCooldown(DimensionalRift)
		end
		if Cataclysm:Usable() then
			UseCooldown(Cataclysm)
		end
		if RagingDemonfire.known and ChannelDemonfire:Usable() and (Immolate:Remains() - (InternalCombustion.known and ChaosBolt:Traveling() > 0 and 5 or 0)) > (3 * Player.haste_factor) and (not RoaringBlaze.known or Conflagrate:Remains() > (3 * Player.haste_factor)) then
			UseCooldown(ChannelDemonfire)
		end
		if SoulFire:Usable() and Player.soul_shards.current <= 3.5 and Target.timeToDie > (SoulFire:CastTime() + SoulFire:TravelTime()) and (
			Conflagrate:Remains() > (SoulFire:CastTime() + SoulFire:TravelTime()) or
			(Backdraft.known and not RoaringBlaze.known and Backdraft:Up())
		) then
			UseCooldown(SoulFire)
		end
	end
	if Immolate:Usable() and Target.timeToDie > 8 and (
		Immolate:Remains() < 3 or
		((Immolate:Remains() - ChaosBolt:CastTime()) < 5 and InternalCombustion.known and ChaosBolt:Usable()) or
		((Immolate:Remains() - (InternalCombustion.known and ChaosBolt:Traveling() > 0 and 5 or 0)) < (Immolate:Duration() * 0.3))
	) and (not self.use_cds or not Cataclysm.known or Cataclysm:Cooldown() > Immolate:Remains()) and (not self.use_cds or not SoulFire.known or (SoulFire:Cooldown() + SoulFire:CastTime()) > (Immolate:Remains() - (InternalCombustion.known and 5 or 0))) then
		return Immolate
	end
	if self.use_cds then
		if ChannelDemonfire:Usable() and Immolate:Remains() > (3 * Player.haste_factor) and Player.set_bonus.t30 >= 4 then
			UseCooldown(ChannelDemonfire)
		end
		if CrashingChaos.known and ChaosBolt:Usable() and SummonInfernal:Ready() and Player.soul_shards.current > 4 then
			return ChaosBolt
		end
		if SummonInfernal:Usable() then
			UseCooldown(SummonInfernal)
		end
	end
	if ChaosBolt:Usable() and (Pet.infernal_count > 0 or Player.soul_shards.current >= 4) then
		return ChaosBolt
	end
	if self.use_cds and ChannelDemonfire:Usable() and Ruin.rank > 1 and not (DiabolicEmbers.known and AvatarOfDestruction.known and (BurnToAshes.known or ChaosIncarnate.known)) and Immolate:Remains() > (3 * Player.haste_factor) then
		UseCooldown(ChannelDemonfire)
	end
	if ChaosBolt:Usable() and (
		(RainOfChaos.known and RainOfChaos:Remains() > ChaosBolt:CastTime()) or
		(Backdraft.known and Backdraft:Up())
	) then
		return ChaosBolt
	end
	if self.use_cds and ChannelDemonfire:Usable() and not (DiabolicEmbers.known and AvatarOfDestruction.known and (BurnToAshes.known or ChaosIncarnate.known)) and Immolate:Remains() > (3 * Player.haste_factor) then
		UseCooldown(ChannelDemonfire)
	end
	if self.use_cds and DimensionalRift:Usable() then
		UseCooldown(DimensionalRift)
	end
	if Target.boss and ChaosBolt:Usable() and between(Target.timeToDie, ChaosBolt:CastTime() + ChaosBolt:TravelTime(), 5) then
		return ChaosBolt
	end
	if Conflagrate:Usable() and (
		Conflagrate:Charges() > (Conflagrate:MaxCharges() - 1) or
		(Target.boss and Target.timeToDie < (Player.gcd * Conflagrate:Charges())) or
		(Backdraft.known and Player.soul_shards.current > 1.5 and Conflagrate:ChargesFractional() > 1.5 and Backdraft:Down())
	) then
		return Conflagrate
	end
	if Incinerate:Usable() then
		return Incinerate
	end
end

APL[SPEC.DESTRUCTION].aoe = function(self)
--[[
actions.aoe=call_action_list,name=ogcd
actions.aoe+=/call_action_list,name=items
actions.aoe+=/call_action_list,name=havoc,if=havoc_active&havoc_remains>gcd.max&active_enemies<5+(talent.cry_havoc&!talent.inferno)&(!cooldown.summon_infernal.up|!talent.summon_infernal)
actions.aoe+=/dimensional_rift,if=soul_shard<4.7&(charges>2|fight_remains<cooldown.dimensional_rift.duration)
actions.aoe+=/rain_of_fire,if=pet.infernal.active|pet.blasphemy.active
actions.aoe+=/rain_of_fire,if=fight_remains<12
actions.aoe+=/rain_of_fire,if=soul_shard>=(4.5-0.1*active_dot.immolate)&time>5
actions.aoe+=/chaos_bolt,if=soul_shard>3.5-(0.1*active_enemies)&!talent.rain_of_fire
actions.aoe+=/cataclysm,if=raid_event.adds.in>15
actions.aoe+=/havoc,target_if=min:((-target.time_to_die)<?-15)+dot.immolate.remains+99*(self.target=target),if=(!cooldown.summon_infernal.up|!talent.summon_infernal|(talent.inferno&active_enemies>4))&target.time_to_die>8
actions.aoe+=/immolate,target_if=min:dot.immolate.remains+99*debuff.havoc.remains,if=dot.immolate.refreshable&(!talent.cataclysm.enabled|cooldown.cataclysm.remains>dot.immolate.remains)&(!talent.raging_demonfire|cooldown.channel_demonfire.remains>remains|time<5)&active_dot.immolate<=4&target.time_to_die>18
actions.aoe+=/channel_demonfire,if=dot.immolate.remains>cast_time&talent.raging_demonfire
actions.aoe+=/summon_soulkeeper,if=buff.tormented_soul.stack=10|buff.tormented_soul.stack>3&fight_remains<10
actions.aoe+=/call_action_list,name=ogcd
actions.aoe+=/summon_infernal,if=cooldown.invoke_power_infusion_0.up|cooldown.invoke_power_infusion_0.duration=0|fight_remains>=190&!talent.grand_warlocks_design
actions.aoe+=/rain_of_fire,if=debuff.pyrogenics.down&active_enemies<=4
actions.aoe+=/channel_demonfire,if=dot.immolate.remains>cast_time
actions.aoe+=/immolate,target_if=min:dot.immolate.remains+99*debuff.havoc.remains,if=((dot.immolate.refreshable&(!talent.cataclysm.enabled|cooldown.cataclysm.remains>dot.immolate.remains))|active_enemies>active_dot.immolate)&target.time_to_die>10&!havoc_active
actions.aoe+=/immolate,target_if=min:dot.immolate.remains+99*debuff.havoc.remains,if=((dot.immolate.refreshable&variable.havoc_immo_time<5.4)|(dot.immolate.remains<2&dot.immolate.remains<havoc_remains)|!dot.immolate.ticking|(variable.havoc_immo_time<2)*havoc_active)&(!talent.cataclysm.enabled|cooldown.cataclysm.remains>dot.immolate.remains)&target.time_to_die>11
actions.aoe+=/dimensional_rift
actions.aoe+=/soul_fire,if=buff.backdraft.up
actions.aoe+=/incinerate,if=talent.fire_and_brimstone.enabled&buff.backdraft.up
actions.aoe+=/conflagrate,if=buff.backdraft.stack<2|!talent.backdraft
actions.aoe+=/incinerate
]]
	self:ogcd()
	self:items()
	if self.havoc_remains > Player.gcd and Player.enemies < (5 + (CryHavoc.known and not Inferno.known and 1 or 0)) and (not SummonInfernal.known or not SummonInfernal:Ready()) then
		local apl = self:havoc()
		if apl then return apl end
	end
	if self.use_cds and DimensionalRift:Usable() and Player.soul_shards.current < 4.7 and (
		DimensionalRift:Charges() > 2 or
		(Target.boss and Target.timeToDie < DimensionalRift:CooldownDuration())
	) then
		UseCooldown(DimensionalRift)
	end
	if RainOfFire:Usable() and (
		Pet.infernal_count > 0 or
		(Target.boss and Target.timeToDie < 12) or
		(Player.soul_shards.current >= (4.5 - (0.1 * Immolate:Ticking())) and Player:TimeInCombat() > 5)
	) then
		return RainOfFire
	end
	if not RainOfFire.known and ChaosBolt:Usable() and Player.soul_shards.current > (3.5 - (0.1 * Player.enemies)) then
		return ChaosBolt
	end
	if self.use_cds and Cataclysm:Usable() then
		UseCooldown(Cataclysm)
	end
	if self.use_cds and Havoc:Usable() and Target.timeToDie > 8 and (not SummonInfernal.known or not SummonInfernal:Ready() or (Inferno.known and Player.enemies> 4)) then
		UseCooldown(Havoc)
	end
	if Immolate:Usable() and Target.timeToDie > 18 and Immolate:Refreshable() and (not self.use_cds or not Cataclysm.known or Cataclysm:Cooldown() > Immolate:Remains()) and (not RagingDemonfire.known or ChannelDemonfire:Cooldown() > Immolate:Remains() or Player:TimeInCombat() < 5) and Immolate:Ticking() <= 4 then
		return Immolate
	end
	if self.use_cds then
		if RagingDemonfire.known and ChannelDemonfire:Usable() and Immolate:Remains() > (3 * Player.haste_factor) then
			UseCooldown(ChannelDemonfire)
		end
		if SummonSoulkeeper:Usable() and (TormentedSoul:Stack() >= 10 or (Target.boss and Target.timeToDie < 10 and TormentedSoul:Stack() > 3)) then
			UseCooldown(SummonSoulkeeper)
		end
		if SummonInfernal:Usable() then
			UseCooldown(SummonInfernal)
		end
	end
	if RainOfFire:Usable() and Player.enemies <= 4 and (not Pyrogenics.known or Pyrogenics:Down()) then
		return RainOfFire
	end
	if self.use_cds and ChannelDemonfire:Usable() and Immolate:Remains() > (3 * Player.haste_factor) then
		UseCooldown(ChannelDemonfire)
	end
	if Immolate:Usable() and Target.timeToDie > 10 and self.havoc_remains == 0 and Immolate:Refreshable() and (not self.use_cds or not Cataclysm.known or Cataclysm:Cooldown() > Immolate:Remains()) then
		return Immolate
	end
	if Immolate:Usable() and Target.timeToDie > 11 and (not self.use_cds or not Cataclysm.known or Cataclysm:Cooldown() > Immolate:Remains()) and (
		(Immolate:Refreshable() and self.havoc_immo_time < 5.4) or
		(Immolate:Remains() < 2 and Immolate:Remains() < self.havoc_remains) or
		Immolate:Down() or
		(self.havoc_immo_time < 2 and self.havoc_remains > 0)
	) then
		return Immolate
	end
	if self.use_cds then
		if DimensionalRift:Usable() then
			UseCooldown(DimensionalRift)
		end
		if SoulFire:Usable() and Backdraft.known and Target.timeToDie > (SoulFire:CastTime() + SoulFire:TravelTime()) and Backdraft:Up() then
			UseCooldown(SoulFire)
		end
	end
	if Backdraft.known and FireAndBrimstone.known and Incinerate:Usable() and Backdraft:Up() then
		return Incinerate
	end
	if Conflagrate:Usable() and (not Backdraft.known or Backdraft:Stack() < 2) then
		return Conflagrate
	end
	if Incinerate:Usable() then
		return Incinerate
	end
end

APL[SPEC.DESTRUCTION].cleave = function(self)
--[[
actions.cleave=call_action_list,name=items
actions.cleave+=/call_action_list,name=ogcd
actions.cleave+=/call_action_list,name=havoc,if=havoc_active&havoc_remains>gcd.max
actions.cleave+=/variable,name=pool_soul_shards,value=cooldown.havoc.remains<=10|talent.mayhem
actions.cleave+=/conflagrate,if=(talent.roaring_blaze.enabled&debuff.conflagrate.remains<1.5)|charges=max_charges&!variable.pool_soul_shards
actions.cleave+=/dimensional_rift,if=soul_shard<4.7&(charges>2|fight_remains<cooldown.dimensional_rift.duration)
actions.cleave+=/cataclysm,if=raid_event.adds.in>15
actions.cleave+=/channel_demonfire,if=talent.raging_demonfire&active_dot.immolate=2
actions.cleave+=/soul_fire,if=soul_shard<=3.5&(debuff.conflagrate.remains>cast_time+travel_time|!talent.roaring_blaze&buff.backdraft.up)&!variable.pool_soul_shards
actions.cleave+=/immolate,target_if=min:dot.immolate.remains+99*debuff.havoc.remains,if=(dot.immolate.refreshable&(dot.immolate.remains<cooldown.havoc.remains|!dot.immolate.ticking))&(!talent.cataclysm|cooldown.cataclysm.remains>remains)&(!talent.soul_fire|cooldown.soul_fire.remains+(!talent.mayhem*action.soul_fire.cast_time)>dot.immolate.remains)&target.time_to_die>15
actions.cleave+=/havoc,target_if=min:((-target.time_to_die)<?-15)+dot.immolate.remains+99*(self.target=target),if=(!cooldown.summon_infernal.up|!talent.summon_infernal)&target.time_to_die>8
actions.cleave+=/dimensional_rift,if=soul_shard<4.5&variable.pool_soul_shards
actions.cleave+=/chaos_bolt,if=pet.infernal.active|pet.blasphemy.active|soul_shard>=4
actions.cleave+=/summon_infernal
actions.cleave+=/channel_demonfire,if=talent.ruin.rank>1&!(talent.diabolic_embers&talent.avatar_of_destruction&(talent.burn_to_ashes|talent.chaos_incarnate))
actions.cleave+=/chaos_bolt,if=soul_shard>3.5
actions.cleave+=/chaos_bolt,if=buff.rain_of_chaos.remains>cast_time
actions.cleave+=/chaos_bolt,if=buff.backdraft.up
actions.cleave+=/soul_fire,if=soul_shard<=4&talent.mayhem
actions.cleave+=/chaos_bolt,if=talent.eradication&debuff.eradication.remains<cast_time+action.chaos_bolt.travel_time+1&!action.chaos_bolt.in_flight
actions.cleave+=/channel_demonfire,if=!(talent.diabolic_embers&talent.avatar_of_destruction&(talent.burn_to_ashes|talent.chaos_incarnate))
actions.cleave+=/dimensional_rift
actions.cleave+=/chaos_bolt,if=soul_shard>3.5&!variable.pool_soul_shards
actions.cleave+=/chaos_bolt,if=fight_remains<5&fight_remains>cast_time+travel_time
actions.cleave+=/summon_soulkeeper,if=buff.tormented_soul.stack=10|buff.tormented_soul.stack>3&fight_remains<10
actions.cleave+=/conflagrate,if=charges>(max_charges-1)|fight_remains<gcd.max*charges
actions.cleave+=/incinerate
]]
	self:items()
	self:ogcd()
	if self.havoc_remains > Player.gcd then
		local apl = self:havoc()
		if apl then return apl end
	end
	self.pool_soul_shards = Mayhem.known or Havoc:Ready(10)
	if Conflagrate:Usable() and (
		(RoaringBlaze.known and Conflagrate:Remains() < 1.5) or
		(not self.pool_soul_shards and Conflagrate:FullRechargeTime() == 0)
	) then
		return Conflagrate
	end
	if self.use_cds then
		if DimensionalRift:Usable() and Player.soul_shards.current < 4.7 and (
			DimensionalRift:Charges() > 2 or
			(Target.boss and Target.timeToDie < DimensionalRift:CooldownDuration())
		) then
			UseCooldown(DimensionalRift)
		end
		if Cataclysm:Usable() then
			UseCooldown(Cataclysm)
		end
		if RagingDemonfire.known and ChannelDemonfire:Usable() and Immolate:Ticking() >= 2 then
			UseCooldown(ChannelDemonfire)
		end
		if SoulFire:Usable() and Player.soul_shards.current <= 3.5 and not self.pool_soul_shards and Target.timeToDie > (SoulFire:CastTime() + SoulFire:TravelTime()) and (
			(Conflagrate:Remains() > (SoulFire:CastTime() + SoulFire:TravelTime())) or
			(Backdraft.known and not RoaringBlaze.known and Backdraft:Up())
		) then
			UseCooldown(SoulFire)
		end
	end
	if Immolate:Usable() and Target.timeToDie > 15 and Immolate:Refreshable() and (Immolate:Down() or Immolate:Remains() < Havoc:Cooldown()) and (not self.use_cds or not Cataclysm.known or Cataclysm:Cooldown() > Immolate:Remains()) and (not SoulFire.known or (SoulFire:Cooldown() + (not Mayhem.known and SoulFire:CastTime() or 0)) > Immolate:Remains()) then
		return Immolate
	end
	if self.use_cds then
		if Havoc:Usable() and Target.timeToDie > 8 and (not SummonInfernal.known or not SummonInfernal:Ready()) then
			UseCooldown(Havoc)
		end
		if DimensionalRift:Usable() and Player.soul_shards.current < 4.5 and self.pool_soul_shards then
			UseCooldown(DimensionalRift)
		end
	end
	if ChaosBolt:Usable() and (
		Pet.infernal_count > 0 or
		Player.soul_shards.current >= 4
	) then
		return ChaosBolt
	end
	if self.use_cds then
		if SummonInfernal:Usable() then
			UseCooldown(SummonInfernal)
		end
		if ChannelDemonfire:Usable() and Ruin.rank > 1 and not (DiabolicEmbers.known and AvatarOfDestruction.known and (BurnToAshes.known or ChaosIncarnate.known)) then
			UseCooldown(ChannelDemonfire)
		end
	end
	if ChaosBolt:Usable() and (
		Player.soul_shards.current > 3.5 or
		(RainOfChaos.known and RainOfChaos:Remains() > ChaosBolt:CastTime()) or
		(Backdraft.known or Backdraft:Up())
	) then
		return ChaosBolt
	end
	if self.use_cds and SoulFire:Usable() and Mayhem.known and Player.soul_shards.current <= 4 and Target.timeToDie > (SoulFire:CastTime() + SoulFire:TravelTime()) then
		UseCooldown(SoulFire)
	end
	if Eradication.known and ChaosBolt:Usable() and Eradication:Remains() < (ChaosBolt:CastTime() + ChaosBolt:TravelTime() + 1) and ChaosBolt:Traveling() == 0 then
		return ChaosBolt
	end
	if self.use_cds then
		if ChannelDemonfire:Usable() and not (DiabolicEmbers.known and AvatarOfDestruction.known and (BurnToAshes.known or ChaosIncarnate.known)) then
			UseCooldown(ChannelDemonfire)
		end
		if DimensionalRift:Usable() then
			UseCooldown(DimensionalRift)
		end
	end
	if ChaosBolt:Usable() and (
		(Player.soul_shards.current > 3.5 and not self.pool_soul_shards) or
		(Target.boss and Target.timeToDie < 5 and Target.timeToDie > (ChaosBolt:CastTime() + ChaosBolt:TravelTime()))
	) then
		return ChaosBolt
	end
	if self.use_cds and SummonSoulkeeper:Usable() and (TormentedSoul:Stack() >= 10 or (Target.boss and Target.timeToDie < 10 and TormentedSoul:Stack() > 3)) then
		UseCooldown(SummonSoulkeeper)
	end
	if Conflagrate:Usable() and (
		Conflagrate:Charges() > (Conflagrate:MaxCharges() - 1) or
		(Target.boss and Target.timeToDie < (Player.gcd * Conflagrate:Charges()))
	) then
		return Conflagrate
	end
	if Incinerate:Usable() then
		return Incinerate
	end
end

APL[SPEC.DESTRUCTION].havoc = function(self)
--[[
actions.havoc=conflagrate,if=talent.backdraft&buff.backdraft.down&soul_shard>=1&soul_shard<=4
actions.havoc+=/soul_fire,if=cast_time<havoc_remains&soul_shard<2.5
actions.havoc+=/channel_demonfire,if=soul_shard<4.5&talent.raging_demonfire.rank=2
actions.havoc+=/immolate,target_if=min:dot.immolate.remains+100*debuff.havoc.remains,if=(((dot.immolate.refreshable&variable.havoc_immo_time<5.4)&target.time_to_die>5)|((dot.immolate.remains<2&dot.immolate.remains<havoc_remains)|!dot.immolate.ticking|variable.havoc_immo_time<2)&target.time_to_die>11)&soul_shard<4.5
actions.havoc+=/chaos_bolt,if=((talent.cry_havoc&!talent.inferno)|!talent.rain_of_fire)&cast_time<havoc_remains
actions.havoc+=/chaos_bolt,if=cast_time<havoc_remains&(active_enemies<=3-talent.inferno+(talent.chaosbringer&!talent.inferno))
actions.havoc+=/rain_of_fire,if=active_enemies>=3&talent.inferno
actions.havoc+=/rain_of_fire,if=(active_enemies>=4-talent.inferno+talent.chaosbringer)
actions.havoc+=/rain_of_fire,if=active_enemies>2&(talent.avatar_of_destruction|(talent.rain_of_chaos&buff.rain_of_chaos.up))&talent.inferno.enabled
actions.havoc+=/channel_demonfire,if=soul_shard<4.5
actions.havoc+=/conflagrate,if=!talent.backdraft
actions.havoc+=/dimensional_rift,if=soul_shard<4.7&(charges>2|fight_remains<cooldown.dimensional_rift.duration)
actions.havoc+=/incinerate,if=cast_time<havoc_remains
]]
	if Backdraft.known and Conflagrate:Usable() and Backdraft:Down() and between(Player.soul_shards.current, 1, 4) then
		return Conflagrate
	end
	if SoulFire:Usable() and SoulFire:CastTime() < self.havoc_remains and Player.soul_shards.current < 2.5 then
		return SoulFire
	end
	if ChannelDemonfire:Usable() and Player.soul_shards.current < 4.5 and RagingDemonfire.rank >= 2 then
		UseCooldown(ChannelDemonfire)
	end
	if Immolate:Usable() and Player.soul_shards.current < 4.5 and (
		(Immolate:Refreshable() and self.havoc_immo_time < 5.4 and Target.timeToDie > 5) or
		(Target.timeToDie > 11 and (
			(Immolate:Remains() < 2 and Immolate:Remains() < self.havoc_remains) or
			Immolate:Down() or
			self.havoc_immo_time < 2
		))
	) then
		return Immolate
	end
	if ChaosBolt:Usable() and ChaosBolt:CastTime() < self.havoc_remains and (
		(not RainOfFire.known or (CryHavoc.known and not Inferno.known)) or
		(Player.enemies <= (3 - (Inferno.known and 1 or 0) + (Chaosbringer.known and not Inferno.known and 1 or 0)))
	) then
		return ChaosBolt
	end
	if RainOfFire:Usable() and (
		(Player.enemies >= 3 and Inferno.known) or
		(Player.enemies >= (4 - (Inferno.known and 1 or 0) + (Chaosbringer.known and 1 or 0))) or
		(Player.enemies > 2 and Inferno.known and (AvatarOfDestruction.known or (RainOfChaos.known and RainOfChaos:Up())))
	) then
		return RainOfFire
	end
	if ChannelDemonfire:Usable() and Player.soul_shards.current < 4.5 then
		UseCooldown(ChannelDemonfire)
	end
	if not Backdraft.known and Conflagrate:Usable() then
		return Conflagrate
	end
	if DimensionalRift:Usable() and Player.soul_shards.current < 4.7 and (
		DimensionalRift:Charges() > 2 or
		(Target.boss and Target.timeToDie < DimensionalRift:CooldownDuration())
	) then
		UseCooldown(DimensionalRift)
	end
	if Incinerate:Usable() and Incinerate:CastTime() < self.havoc_remains then
		return Incinerate
	end
end

APL[SPEC.DESTRUCTION].items = function(self)
--[[
actions.items=use_item,use_off_gcd=1,name=belorrelos_the_suncaller,if=((time>20&cooldown.summon_infernal.remains>20)|(trinket.1.is.belorrelos_the_suncaller&(trinket.2.cooldown.remains|!variable.trinket_2_buffs|trinket.1.is.time_thiefs_gambit))|(trinket.2.is.belorrelos_the_suncaller&(trinket.1.cooldown.remains|!variable.trinket_1_buffs|trinket.2.is.time_thiefs_gambit)))&(!raid_event.adds.exists|raid_event.adds.up|spell_targets.belorrelos_the_suncaller>=5)|fight_remains<20
actions.items+=/use_item,name=nymues_unraveling_spindle,if=(variable.infernal_active|!talent.summon_infernal|(variable.trinket_1_will_lose_cast&trinket.1.is.nymues_unraveling_spindle)|(variable.trinket_2_will_lose_cast&trinket.2.is.nymues_unraveling_spindle))|fight_remains<20
# We want to use trinkets with Infernal unless we will miss a trinket use. The trinket with highest estimated value, will be used first.
actions.items+=/use_item,slot=trinket1,if=(variable.infernal_active|!talent.summon_infernal|variable.trinket_1_will_lose_cast)&(variable.trinket_priority=1|variable.trinket_2_exclude|!trinket.2.has_cooldown|(trinket.2.cooldown.remains|variable.trinket_priority=2&cooldown.summon_infernal.remains>20&!variable.infernal_active&trinket.2.cooldown.remains<cooldown.summon_infernal.remains))&variable.trinket_1_buffs&!variable.trinket_1_manual|(variable.trinket_1_buff_duration+1>=fight_remains)
actions.items+=/use_item,slot=trinket2,if=(variable.infernal_active|!talent.summon_infernal|variable.trinket_2_will_lose_cast)&(variable.trinket_priority=2|variable.trinket_1_exclude|!trinket.1.has_cooldown|(trinket.1.cooldown.remains|variable.trinket_priority=1&cooldown.summon_infernal.remains>20&!variable.infernal_active&trinket.1.cooldown.remains<cooldown.summon_infernal.remains))&variable.trinket_2_buffs&!variable.trinket_2_manual|(variable.trinket_2_buff_duration+1>=fight_remains)
actions.items+=/use_item,name=time_thiefs_gambit,if=variable.infernal_active|!talent.summon_infernal|fight_remains<15|((trinket.1.cooldown.duration<cooldown.summon_infernal.remains_expected+5)&active_enemies=1)|(active_enemies>1&havoc_active)
# If only one on use trinket provied a buff, use the other on cooldown, Or if neither trinket provied a buff, use both on cooldown.
actions.items+=/use_item,use_off_gcd=1,slot=trinket1,if=!variable.trinket_1_buffs&!variable.trinket_1_manual&(!variable.trinket_1_buffs&(trinket.2.cooldown.remains|!variable.trinket_2_buffs)|talent.summon_infernal&cooldown.summon_infernal.remains_expected>20&!prev_gcd.1.summon_infernal|!talent.summon_infernal)
actions.items+=/use_item,use_off_gcd=1,slot=trinket2,if=!variable.trinket_2_buffs&!variable.trinket_2_manual&(!variable.trinket_2_buffs&(trinket.1.cooldown.remains|!variable.trinket_1_buffs)|talent.summon_infernal&cooldown.summon_infernal.remains_expected>20&!prev_gcd.1.summon_infernal|!talent.summon_infernal)
actions.items+=/use_item,use_off_gcd=1,slot=main_hand
]]
	if Opt.trinket and self.use_cds then
		if Trinket.BelorrelosTheSuncaller:Usable() and ((Target.boss and Target.timeToDie < 21) or (Player:TimeInCombat() > 20 and not SummonInfernal:Ready(20)) or not (Trinket1:Usable() or Trinket2:Usable())) then
			return UseCooldown(Trinket.BelorrelosTheSuncaller)
		end
		if (self.infernal_active or (Target.boss and Target.timeToDie < 21)) then
			if Trinket.NymuesUnravelingSpindle:Usable() then
				return UseCooldown(Trinket.NymuesUnravelingSpindle:Usable())
			elseif Trinket1:Usable() then
				return UseCooldown(Trinket1)
			elseif Trinket2:Usable() then
				return UseCooldown(Trinket2)
			end
		end
	end
	if DreambinderLoomOfTheGreatCycle:Usable() then
		return UseCooldown(DreambinderLoomOfTheGreatCycle)
	end
	if IridalTheEarthsMaster:Usable() then
		return UseCooldown(IridalTheEarthsMaster)
	end
end

APL[SPEC.DESTRUCTION].ogcd = function(self)
--[[
actions.ogcd=potion,if=variable.infernal_active|!talent.summon_infernal
actions.ogcd+=/invoke_external_buff,name=power_infusion,if=variable.infernal_active|!talent.summon_infernal|(fight_remains<cooldown.summon_infernal.remains_expected+10+cooldown.invoke_power_infusion_0.duration&fight_remains>cooldown.invoke_power_infusion_0.duration)|fight_remains<cooldown.summon_infernal.remains_expected+15
actions.ogcd+=/berserking,if=variable.infernal_active|!talent.summon_infernal|(fight_remains<(cooldown.summon_infernal.remains_expected+cooldown.berserking.duration)&(fight_remains>cooldown.berserking.duration))|fight_remains<cooldown.summon_infernal.remains_expected
actions.ogcd+=/blood_fury,if=variable.infernal_active|!talent.summon_infernal|(fight_remains<cooldown.summon_infernal.remains_expected+10+cooldown.blood_fury.duration&fight_remains>cooldown.blood_fury.duration)|fight_remains<cooldown.summon_infernal.remains
actions.ogcd+=/fireblood,if=variable.infernal_active|!talent.summon_infernal|(fight_remains<cooldown.summon_infernal.remains_expected+10+cooldown.fireblood.duration&fight_remains>cooldown.fireblood.duration)|fight_remains<cooldown.summon_infernal.remains_expected
actions.ogcd+=/ancestral_call,if=variable.infernal_active|!talent.summon_infernal|(fight_remains<(cooldown.summon_infernal.remains_expected+cooldown.berserking.duration)&(fight_remains>cooldown.berserking.duration))|fight_remains<cooldown.summon_infernal.remains_expected
]]

end

APL[SPEC.DESTRUCTION].variables = function(self)
--[[
actions.variables=variable,name=havoc_immo_time,op=reset
actions.variables+=/cycling_variable,name=havoc_immo_time,op=add,value=dot.immolate.remains*debuff.havoc.up
actions.variables+=/variable,name=infernal_active,op=set,value=pet.infernal.active|(cooldown.summon_infernal.duration-cooldown.summon_infernal.remains)<20
# If we can have more use of trinket than use of infernal, we want to it, but we want to sync if we don't lose a cast, and if we sync we don't lose it too late
actions.variables+=/variable,name=trinket_1_will_lose_cast,value=((floor((fight_remains%trinket.1.cooldown.duration)+1)!=floor((fight_remains+(cooldown.summon_infernal.duration-cooldown.summon_infernal.remains))%cooldown.summon_infernal.duration))&(floor((fight_remains%trinket.1.cooldown.duration)+1))!=(floor(((fight_remains-cooldown.summon_infernal.remains)%trinket.1.cooldown.duration)+1))|((floor((fight_remains%trinket.1.cooldown.duration)+1)=floor((fight_remains+(cooldown.summon_infernal.duration-cooldown.summon_infernal.remains))%cooldown.summon_infernal.duration))&(((fight_remains-cooldown.summon_infernal.remains%%trinket.1.cooldown.duration)-cooldown.summon_infernal.remains-variable.trinket_1_buff_duration)>0)))&cooldown.summon_infernal.remains>20
actions.variables+=/variable,name=trinket_2_will_lose_cast,value=((floor((fight_remains%trinket.2.cooldown.duration)+1)!=floor((fight_remains+(cooldown.summon_infernal.duration-cooldown.summon_infernal.remains))%cooldown.summon_infernal.duration))&(floor((fight_remains%trinket.2.cooldown.duration)+1))!=(floor(((fight_remains-cooldown.summon_infernal.remains)%trinket.2.cooldown.duration)+1))|((floor((fight_remains%trinket.2.cooldown.duration)+1)=floor((fight_remains+(cooldown.summon_infernal.duration-cooldown.summon_infernal.remains))%cooldown.summon_infernal.duration))&(((fight_remains-cooldown.summon_infernal.remains%%trinket.2.cooldown.duration)-cooldown.summon_infernal.remains-variable.trinket_2_buff_duration)>0)))&cooldown.summon_infernal.remains>20
]]
	self.infernal_up = Pet.Infernal:Up(true)
	self.use_cds = Opt.cooldown and (Target.boss or Target.player or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd) or self.infernal_up)
	self.havoc_remains = Havoc:HighestRemains()
	self.havoc_immo_time = self.havoc_remains > 0 and Havoc:DotRemains(Immolate) or 0
	self.infernal_active = self.infernal_up or (SummonInfernal:CooldownDuration() - SummonInfernal:Cooldown()) < 20
end

APL.Interrupt = function(self)
	if SpellLock:Usable() then
		return SpellLock
	end
	if AxeToss:Usable() then
		return AxeToss
	end
	if MortalCoil:Usable() then
		return MortalCoil
	end
	if Shadowfury:Usable() then
		return Shadowfury
	end
end

-- End Action Priority Lists

-- Start UI Functions

function UI.DenyOverlayGlow(actionButton)
	if Opt.glow.blizzard then
		return
	end
	local alert = actionButton.SpellActivationAlert
	if not alert then
		return
	end
	if alert.ProcStartAnim:IsPlaying() then
		alert.ProcStartAnim:Stop()
	end
	alert:Hide()
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r, g, b = Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.ProcStartFlipbook:SetVertexColor(r, g, b)
		glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
	end
end

function UI:DisableOverlayGlows()
	if LibStub and LibStub.GetLibrary and not Opt.glow.blizzard then
		local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
		if lib then
			lib.ShowOverlayGlow = function(self)
				return
			end
		end
	end
end

function UI:CreateOverlayGlows()
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.ProcStartAnim:Play() -- will bug out if ProcLoop plays first
			glow.button = button
			self.glows[#self.glows + 1] = glow
		end
	end
	for i = 1, 12 do
		GenerateGlow(_G['ActionButton' .. i])
		GenerateGlow(_G['MultiBarLeftButton' .. i])
		GenerateGlow(_G['MultiBarRightButton' .. i])
		GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
		GenerateGlow(_G['MultiBarBottomRightButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['PetActionButton' .. i])
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	end
	if Dominos then
		for i = 1, 60 do
			GenerateGlow(_G['DominosActionButton' .. i])
		end
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['LUIBarBottom' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarLeft' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
	end
	self:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon
	for i = 1, #self.glows do
		glow = self.glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
			) then
			if not glow:IsVisible() then
				glow:Show()
				if Opt.glow.animation then
					glow.ProcStartAnim:Play()
				else
					glow.ProcLoop:Play()
				end
			end
		elseif glow:IsVisible() then
			if glow.ProcStartAnim:IsPlaying() then
				glow.ProcStartAnim:Stop()
			end
			if glow.ProcLoop:IsPlaying() then
				glow.ProcLoop:Stop()
			end
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	doomedPanel:SetMovable(not Opt.snap)
	doomedPreviousPanel:SetMovable(not Opt.snap)
	doomedCooldownPanel:SetMovable(not Opt.snap)
	doomedInterruptPanel:SetMovable(not Opt.snap)
	doomedExtraPanel:SetMovable(not Opt.snap)
	if not Opt.snap then
		doomedPanel:SetUserPlaced(true)
		doomedPreviousPanel:SetUserPlaced(true)
		doomedCooldownPanel:SetUserPlaced(true)
		doomedInterruptPanel:SetUserPlaced(true)
		doomedExtraPanel:SetUserPlaced(true)
	end
	doomedPanel:EnableMouse(draggable or Opt.aoe)
	doomedPanel.button:SetShown(Opt.aoe)
	doomedPreviousPanel:EnableMouse(draggable)
	doomedCooldownPanel:EnableMouse(draggable)
	doomedInterruptPanel:EnableMouse(draggable)
	doomedExtraPanel:EnableMouse(draggable)
end

function UI:UpdateAlpha()
	doomedPanel:SetAlpha(Opt.alpha)
	doomedPreviousPanel:SetAlpha(Opt.alpha)
	doomedCooldownPanel:SetAlpha(Opt.alpha)
	doomedInterruptPanel:SetAlpha(Opt.alpha)
	doomedExtraPanel:SetAlpha(Opt.alpha)
end

function UI:UpdateScale()
	doomedPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	doomedPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	doomedCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	doomedInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	doomedExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

function UI:SnapAllPanels()
	doomedPreviousPanel:ClearAllPoints()
	doomedPreviousPanel:SetPoint('TOPRIGHT', doomedPanel, 'BOTTOMLEFT', -3, 40)
	doomedCooldownPanel:ClearAllPoints()
	doomedCooldownPanel:SetPoint('TOPLEFT', doomedPanel, 'BOTTOMRIGHT', 3, 40)
	doomedInterruptPanel:ClearAllPoints()
	doomedInterruptPanel:SetPoint('BOTTOMLEFT', doomedPanel, 'TOPRIGHT', 3, -21)
	doomedExtraPanel:ClearAllPoints()
	doomedExtraPanel:SetPoint('BOTTOMRIGHT', doomedPanel, 'TOPLEFT', -3, -21)
end

UI.anchor_points = {
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[SPEC.AFFLICTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 },
		},
		[SPEC.DEMONOLOGY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 },
		},
		[SPEC.DESTRUCTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 },
		}
	},
	kui = { -- Kui Nameplates
		[SPEC.AFFLICTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 },
		},
		[SPEC.DEMONOLOGY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 },
		},
		[SPEC.DESTRUCTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 },
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		doomedPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap and UI.anchor.points then
		local p = UI.anchor.points[Player.spec][Opt.snap]
		doomedPanel:ClearAllPoints()
		doomedPanel:SetPoint(p[1], UI.anchor.frame, p[2], p[3], p[4])
		UI:SnapAllPanels()
	end
end

function UI:HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		self.anchor.points = self.anchor_points.kui
		self.anchor.frame = KuiNameplatesPlayerAnchor
	else
		self.anchor.points = self.anchor_points.blizzard
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateBar()
	end
	if self.anchor.frame then
		self.anchor.frame:HookScript('OnHide', self.OnResourceFrameHide)
		self.anchor.frame:HookScript('OnShow', self.OnResourceFrameShow)
	end
end

function UI:ShouldHide()
	return (Player.spec == SPEC.NONE or
		(Player.spec == SPEC.AFFLICTION and Opt.hide.affliction) or
		(Player.spec == SPEC.DEMONOLOGY and Opt.hide.demonology) or
		(Player.spec == SPEC.DESTRUCTION and Opt.hide.destruction))
end

function UI:Disappear()
	doomedPanel:Hide()
	doomedPanel.icon:Hide()
	doomedPanel.border:Hide()
	doomedCooldownPanel:Hide()
	doomedInterruptPanel:Hide()
	doomedExtraPanel:Hide()
	Player.main = nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	self:UpdateGlows()
end

function UI:Reset()
	doomedPanel:ClearAllPoints()
	doomedPanel:SetPoint('CENTER', 0, -169)
	self:SnapAllPanels()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, dim, dim_cd, text_center, text_cd, text_tl, text_tr
	local channel = Player.channel

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.main then
		if Player.main.requires_react then
			local react = Player.main:React()
			if react > 0 then
				text_center = format('%.1f', react)
			end
		end
		if Player.main_freecast then
			border = 'freecast'
		end
	end
	if Player.cd then
		if Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd = format('%.1f', react)
			end
		end
	end
	if Player.wait_time then
		local deficit = Player.wait_time - GetTime()
		if deficit > 0 then
			text_center = format('WAIT\n%.1fs', deficit)
			dim = Opt.dimmer
		end
	end
	if channel.ability and not channel.ability.ignore_channel and channel.tick_count > 0 then
		dim = Opt.dimmer
		if channel.tick_count > 1 then
			local ctime = GetTime()
			channel.ticks = ((ctime - channel.start) / channel.tick_interval) - channel.ticks_extra
			channel.ticks_remain = (channel.ends - ctime) / channel.tick_interval
			text_center = format('TICKS\n%.1f', max(0, channel.ticks))
			if channel.ability == Player.main then
				if channel.ticks_remain < 1 or channel.early_chainable then
					dim = false
					text_center = '|cFF00FF00CHAIN'
				end
			elseif channel.interruptible then
				dim = false
			end
		end
	end
	if Player.spec == SPEC.AFFLICTION then
		if Opt.pet_count and Player.dot_count > 0 then
			text_tl = Player.dot_count
		end
		if Opt.tyrant then
			local remains
			text_tr = ''
			for _, unit in next, Pet.Darkglare.active_units do
				remains = unit.expires - Player.time
				if remains > 0 then
					text_tr = format('%s%.1fs\n', text_tr, remains)
				end
			end
		end
	elseif Player.spec == SPEC.DEMONOLOGY then
		if Opt.pet_count then
			if Opt.pet_count == 'imps' then
				if Pet.imp_count > 0 then
					text_tl = Pet.imp_count
				end
			elseif Pet.count > 0 then
				text_tl = Pet.count
			end
		end
		if Opt.tyrant then
			if ReignOfTyranny.known and (Pet.tyrant_cd < 5 or SummonDemonicTyrant:Casting()) then
				text_tr = format('%d%%\n', Pet.tyrant_available_power)
			else
				text_tr = ''
			end
			local remains
			for _, unit in next, Pet.DemonicTyrant.active_units do
				if unit.initial then
					remains = unit.expires - Player.time
					if unit.power > 100 and remains > 5 then
						text_tr = format('%s%d%%\n', text_tr, unit.power)
					elseif remains > 0 then
						text_tr = format('%s%.1fs\n', text_tr, remains)
					end
				end
			end
			for _, unit in next, Pet.DemonicTyrant.active_units do
				if not unit.initial then
					remains = unit.expires - Player.time
					if remains > 0 then
						text_tr = format('%s%.1fs\n', text_tr, remains)
					end
				end
			end
		end
	elseif Player.spec == SPEC.DESTRUCTION then
		if Opt.pet_count and Pet.infernal_count > 0 then
			text_tl = Pet.infernal_count
		end
		if Opt.tyrant then
			local remains
			text_tr = ''
			for _, unit in next, Pet.Infernal.active_units do
				if unit.initial then
					remains = unit.expires - Player.time
					if remains > 0 then
						text_tr = format('%s%.1fs\n', text_tr, remains)
					end
				end
			end
			for _, unit in next, Pet.Infernal.active_units do
				if not unit.initial then
					remains = unit.expires - Player.time
					if remains > 0 then
						text_tr = format('%s%.1fs\n', text_tr, remains)
					end
				end
			end
			for _, unit in next, Pet.Blasphemy.active_units do
				remains = unit.expires - Player.time
				if remains > 0 then
					text_tr = format('%s%.1fs\n', text_tr, remains)
				end
			end
		end
	end
	if border ~= doomedPanel.border.overlay then
		doomedPanel.border.overlay = border
		doomedPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	doomedPanel.dimmer:SetShown(dim)
	doomedPanel.text.center:SetText(text_center)
	doomedPanel.text.tl:SetText(text_tl)
	doomedPanel.text.tr:SetText(text_tr)
	--doomedPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	doomedCooldownPanel.text:SetText(text_cd)
	doomedCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		doomedPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.shard_cost > 0 and Player.main:ShardCost() == 0) or (Player.main.Free and Player.main.Free())
	end
	if Player.cd then
		doomedCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local start, duration = GetSpellCooldown(Player.cd.spellId)
			doomedCooldownPanel.swipe:SetCooldown(start, duration)
		end
	end
	if Player.extra then
		doomedExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			doomedInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			doomedInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		doomedInterruptPanel.icon:SetShown(Player.interrupt)
		doomedInterruptPanel.border:SetShown(Player.interrupt)
		doomedInterruptPanel:SetShown(start and not notInterruptible)
	end
	if Opt.previous and doomedPreviousPanel.ability then
		if (Player.time - doomedPreviousPanel.ability.last_used) > 10 then
			doomedPreviousPanel.ability = nil
			doomedPreviousPanel:Hide()
		end
	end

	doomedPanel.icon:SetShown(Player.main)
	doomedPanel.border:SetShown(Player.main)
	doomedCooldownPanel:SetShown(Player.cd)
	doomedExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - Timer.combat > seconds then
		Timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI Functions

-- Start Event Handling

function Events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Doomed
		local firstRun = not Opt.frequency
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		if firstRun then
			log('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			log('Type |cFFFFD000' .. SLASH_Doomed1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			log('[|cFFFFD000Warning|r]', ADDON, 'is not designed for players under level 10, and almost certainly will not operate properly!')
		end
	end
end

CombatEvent.TRIGGER = function(timeStamp, event, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
	Player:UpdateTime(timeStamp)
	local e = event
	if (
	   e == 'UNIT_DESTROYED' or
	   e == 'UNIT_DISSIPATES' or
	   e == 'SPELL_INSTAKILL' or
	   e == 'PARTY_KILL')
	then
		e = 'UNIT_DIED'
	elseif (
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_ABSORBED' or
	   e == 'SPELL_ENERGIZE' or
	   e == 'SPELL_PERIODIC_DAMAGE' or
	   e == 'SPELL_MISSED' or
	   e == 'SPELL_AURA_APPLIED' or
	   e == 'SPELL_AURA_REFRESH' or
	   e == 'SPELL_AURA_REMOVED')
	then
		e = 'SPELL'
	end
	if CombatEvent[e] then
		return CombatEvent[e](event, srcGUID, dstGUID, ...)
	end
end

CombatEvent.UNIT_DIED = function(event, srcGUID, dstGUID)
	trackAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
	local pet = SummonedPets:Find(dstGUID)
	if pet then
		pet:RemoveUnit(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL_SUMMON = function(event, srcGUID, dstGUID)
	if srcGUID ~= Player.guid then
		return
	end
	local pet = SummonedPets:Find(dstGUID)
	if pet then
		pet:AddUnit(dstGUID)
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if not (srcGUID == Player.guid or srcGUID == Pet.guid) then
		local pet = SummonedPets:Find(srcGUID)
		if pet then
			local unit = pet.active_units[srcGUID]
			if unit then
				if event == 'SPELL_CAST_SUCCESS' and pet.CastSuccess then
					pet:CastSuccess(unit, spellId, dstGUID)
				elseif event == 'SPELL_CAST_START' and pet.CastStart then
					pet:CastStart(unit, spellId, dstGUID)
				elseif event == 'SPELL_CAST_FAILED' and pet.CastFailed then
					pet:CastFailed(unit, spellId, dstGUID, missType)
				elseif (event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH') and pet.CastLanded then
					pet:CastLanded(unit, spellId, dstGUID, event, missType)
				end
				--log(format('PET %d EVENT %s SPELL %s ID %d', pet.unitId, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
			end
		end
		return
	end

	if srcGUID == Pet.guid then
		if Pet.stuck and (event == 'SPELL_CAST_SUCCESS' or event == 'SPELL_DAMAGE' or event == 'SWING_DAMAGE') then
			Pet.stuck = false
		elseif not Pet.stuck and event == 'SPELL_CAST_FAILED' and missType == 'No path available' then
			Pet.stuck = true
		end
	end

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
		--log(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability.CastFailed and ability:CastFailed(dstGUID, missType)
	elseif event == 'SPELL_ENERGIZE' then
		return ability.Energize and ability:Energize(missType, overCap, powerType)
	end
	if ability.aura_targets then
		if event == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif event == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif event == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if dstGUID == Player.guid or dstGUID == Pet.guid then
		if event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
			ability.last_gained = Player.time
		end
		return -- ignore buffs beyond here
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function Events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function Events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function Events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth(unitId)
		Player.health.max = UnitHealthMax(unitId)
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function Events:UNIT_MAXPOWER(unitId)
	if unitId == 'player' then
		Player.level = UnitLevel(unitId)
		Player.mana.base = Player.BaseMana[Player.level]
		Player.mana.max = UnitPowerMax(unitId, 0)
		Player.soul_shards.max = UnitPowerMax(unitId, 7)
	end
end

function Events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
	if unitId == 'player' and HandOfGuldan:Match(spellId) then
		HandOfGuldan.cast_shards = Player.soul_shards.current
	end
end

function Events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
Events.UNIT_SPELLCAST_FAILED = Events.UNIT_SPELLCAST_STOP
Events.UNIT_SPELLCAST_INTERRUPTED = Events.UNIT_SPELLCAST_STOP

function Events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function Events:UNIT_SPELLCAST_CHANNEL_UPDATE(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:UpdateChannelInfo()
	end
end
Events.UNIT_SPELLCAST_CHANNEL_START = Events.UNIT_SPELLCAST_CHANNEL_UPDATE
Events.UNIT_SPELLCAST_CHANNEL_STOP = Events.UNIT_SPELLCAST_CHANNEL_UPDATE

function Events:UNIT_PET(unitId)
	if unitId ~= 'player' then
		return
	end
	Pet:Update()
end

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Pet.stuck = false
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		doomedPreviousPanel:Hide()
	end
	for _, ability in next, Abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		AutoAoe:Clear()
	end
	if APL[Player.spec].precombat_variables then
		APL[Player.spec]:precombat_variables()
	end
end

function Events:PLAYER_EQUIPMENT_CHANGED()
	local _, equipType, hasCooldown
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	for _, i in next, Trinket do -- use custom APL lines for these trinkets
		if Trinket1.itemId == i.itemId then
			Trinket1.itemId = 0
		end
		if Trinket2.itemId == i.itemId then
			Trinket2.itemId = 0
		end
	end
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Player:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end

	Player.set_bonus.t29 = (Player:Equipped(200333) and 1 or 0) + (Player:Equipped(200335) and 1 or 0) + (Player:Equipped(200336) and 1 or 0) + (Player:Equipped(200337) and 1 or 0) + (Player:Equipped(200338) and 1 or 0)
	Player.set_bonus.t30 = (Player:Equipped(202531) and 1 or 0) + (Player:Equipped(202532) and 1 or 0) + (Player:Equipped(202533) and 1 or 0) + (Player:Equipped(202534) and 1 or 0) + (Player:Equipped(202536) and 1 or 0)
	Player.set_bonus.t31 = (Player:Equipped(207270) and 1 or 0) + (Player:Equipped(207271) and 1 or 0) + (Player:Equipped(207272) and 1 or 0) + (Player:Equipped(207273) and 1 or 0) + (Player:Equipped(207275) and 1 or 0)
	Player.set_bonus.t32 = (Player:Equipped(217211) and 1 or 0) + (Player:Equipped(217212) and 1 or 0) + (Player:Equipped(217213) and 1 or 0) + (Player:Equipped(217214) and 1 or 0) + (Player:Equipped(217215) and 1 or 0)

	Player:UpdateKnown()
end

function Events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	doomedPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	Events:UNIT_MAXPOWER('player')
	InnerDemons.next_imp = nil
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end

function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		doomedPanel.swipe:SetCooldown(start, duration)
	end
	if Implosion.known and IsFlying() and GetSpellCount(Implosion.spellId) == 0 then
		Pet.WildImp:Clear()
		Pet.WildImpID:Clear()
	end
end

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function Events:GROUP_ROSTER_UPDATE()
	Player.group_size = clamp(GetNumGroupMembers(), 1, 40)
end

function Events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() Events:PLAYER_EQUIPMENT_CHANGED() end)
end

function Events:UI_ERROR_MESSAGE(errorId)
	if (
	    errorId == 394 or -- pet is rooted
	    errorId == 396 or -- target out of pet range
	    errorId == 400    -- no pet path to target
	) then
		Pet.stuck = true
	end
end

doomedPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Player:ToggleTargetMode()
		elseif button == 'RightButton' then
			Player:ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Player:SetTargetMode(1)
		end
	end
end)

doomedPanel:SetScript('OnUpdate', function(self, elapsed)
	Timer.combat = Timer.combat + elapsed
	Timer.display = Timer.display + elapsed
	Timer.health = Timer.health + elapsed
	if Timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if Timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if Timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

doomedPanel:SetScript('OnEvent', function(self, event, ...) Events[event](self, ...) end)
for event in next, Events do
	doomedPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local SetHyperlink = ItemRefTooltip.SetHyperlink
ItemRefTooltip.SetHyperlink = function(self, link)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		BattleTagInviteFrame_Show(linkData)
		return
	end
	SetHyperlink(self, link)
end

local function Status(desc, opt, ...)
	local opt_view
	if type(opt) == 'string' then
		if opt:sub(1, 2) == '|c' then
			opt_view = opt
		else
			opt_view = '|cFFFFD000' .. opt .. '|r'
		end
	elseif type(opt) == 'number' then
		opt_view = '|cFFFFD000' .. opt .. '|r'
	else
		opt_view = opt and '|cFF00C000On|r' or '|cFFC00000Off|r'
	end
	log(desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		if Opt.aoe or Opt.snap then
			Status('Warning', 'Panels cannot be moved when aoe or snap are enabled!')
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
				Opt.locked = true
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
				Opt.locked = true
			else
				Opt.snap = false
				Opt.locked = false
				UI:Reset()
			end
			UI:UpdateDraggable()
			UI.OnResourceFrameShow()
		end
		return Status('Snap to the Personal Resource Display frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UI:UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = clamp(tonumber(msg[2]) or 100, 0, 100) / 100
			UI:UpdateAlpha()
		end
		return Status('Icon transparency', Opt.alpha * 100 .. '%')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return Status('Calculation frequency (max time to wait between each update): Every', Opt.frequency, 'seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if startsWith(msg[2], 'anim') then
			if msg[3] then
				Opt.glow.animation = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Use extended animation (shrinking circle)', Opt.glow.animation)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = clamp(tonumber(msg[3]) or 0, 0, 1)
				Opt.glow.color.g = clamp(tonumber(msg[4]) or 0, 0, 1)
				Opt.glow.color.b = clamp(tonumber(msg[5]) or 0, 0, 1)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, |cFFFFD000animation|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			Target:Update()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			Target:Update()
		end
		return Status('Show the ' .. ADDON .. ' UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use ' .. ADDON .. ' for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
		end
		return Status('Dim main ability icon when you don\'t have enough resources to use it', Opt.dimmer)
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return Status('Red border around previous ability when it fails to hit', Opt.miss_effect)
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Player:SetTargetMode(1)
			UI:UpdateDraggable()
		end
		return Status('Allow clicking main ability icon to toggle amount of targets (disables moving)', Opt.aoe)
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return Status('Only use cooldowns on bosses', Opt.boss_only)
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'a') then
				Opt.hide.affliction = not Opt.hide.affliction
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Affliction specialization', not Opt.hide.affliction)
			end
			if startsWith(msg[2], 'dem') then
				Opt.hide.demonology = not Opt.hide.demonology
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Demonology specialization', not Opt.hide.demonology)
			end
			if startsWith(msg[2], 'des') then
				Opt.hide.destruction = not Opt.hide.destruction
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Destruction specialization', not Opt.hide.destruction)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000affliction|r/|cFFFFD000demonology|r/|cFFFFD000destruction|r')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return Status('Show an icon for interruptable spells', Opt.interrupt)
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return Status('Automatically change target mode on AoE spells', Opt.auto_aoe)
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return Status('Length of time target exists in auto AoE after being hit', Opt.auto_aoe_ttl, 'seconds')
	end
	if msg[1] == 'ttd' then
		if msg[2] then
			Opt.cd_ttd = tonumber(msg[2]) or 10
		end
		return Status('Minimum enemy lifetime to use cooldowns on (ignored on bosses)', Opt.cd_ttd, 'seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return Status('Show flasks and battle potions in cooldown UI', Opt.pot)
	end
	if startsWith(msg[1], 'tri') then
		if msg[2] then
			Opt.trinket = msg[2] == 'on'
		end
		return Status('Show on-use trinkets in cooldown UI', Opt.trinket)
	end
	if startsWith(msg[1], 'health') then
		if msg[2] then
			Opt.healthstone = msg[2] == 'on'
		end
		return Status('Show Create Healthstone reminder out of combat', Opt.healthstone)
	end
	if startsWith(msg[1], 'pet') then
		if msg[2] then
			if startsWith(msg[2], 'imp') then
				Opt.pet_count = 'imps'
			else
				Opt.pet_count = msg[2] == 'on'
			end
		end
		return Status('Show summoned pet counter (topleft)', Opt.pet_count == 'imps' and 'Wild Imps only' or Opt.pet_count)
	end
	if startsWith(msg[1], 'tyr') then
		if msg[2] then
			Opt.tyrant = msg[2] == 'on'
		end
		return Status('Show Tyrant/Infernal/Darkglare power/remains (topright)', Opt.tyrant)
	end
	if msg[1] == 'reset' then
		UI:Reset()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r/|cFFFFD000animation|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000affliction|r/|cFFFFD000demonology|r/|cFFFFD000destruction|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'healthstone |cFF00C000on|r/|cFFC00000off|r - show Create Healthstone reminder out of combat',
		'pets |cFF00C000on|r/|cFFFFD000imps|r/|cFFC00000off|r  - Show summoned pet counter (topleft)',
		'tyrant |cFF00C000on|r/|cFFC00000off|r  - Show Tyrant/Infernal/Darkglare power/remains (topright)',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Doomed1 .. ' ' .. cmd)
	end
	print('Need to threaten with the wrath of doom? You can still use |cFFFFD000/wrath|r!')
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
