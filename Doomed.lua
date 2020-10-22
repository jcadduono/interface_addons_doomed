if select(2, UnitClass('player')) ~= 'WARLOCK' then
	DisableAddOn('Doomed')
	return
end

-- copy heavily accessed global functions into local scope for performance
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellCharges = _G.GetSpellCharges
local GetTime = _G.GetTime
local UnitCastingInfo = _G.UnitCastingInfo
local UnitAura = _G.UnitAura
-- end copy global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
   return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

Doomed = {}
local Opt

SLASH_Doomed1, SLASH_Doomed2 = '/doomed', '/doom'
BINDING_HEADER_DOOMED = 'Doomed'

local function InitOpts()
	local function SetDefaults(t, ref)
		local k, v
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

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

-- specialization constants
local SPEC = {
	NONE = 0,
	AFFLICTION = 1,
	DEMONOLOGY = 2,
	DESTRUCTION = 3,
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	target_mode = 0,
	gcd = 1.5,
	health = 0,
	health_max = 0,
	mana = 0,
	mana_max = 0,
	mana_regen = 0,
	soul_shards = 0,
	soul_shards_max = 0,
	last_swing_taken = 0,
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[165581] = true, -- Crest of Pa'ku (Horde)
		[174044] = true, -- Humming Black Dragonscale (parachute)
	},
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false,
	estimated_range = 30,
}

-- Azerite trait API access
local Azerite = {}

local doomedPanel = CreateFrame('Frame', 'doomedPanel', UIParent)
doomedPanel:SetPoint('CENTER', 0, -169)
doomedPanel:SetFrameStrata('BACKGROUND')
doomedPanel:SetSize(64, 64)
doomedPanel:SetMovable(true)
doomedPanel:Hide()
doomedPanel.icon = doomedPanel:CreateTexture(nil, 'BACKGROUND')
doomedPanel.icon:SetAllPoints(doomedPanel)
doomedPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
doomedPanel.border = doomedPanel:CreateTexture(nil, 'ARTWORK')
doomedPanel.border:SetAllPoints(doomedPanel)
doomedPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')
doomedPanel.border:Hide()
doomedPanel.dimmer = doomedPanel:CreateTexture(nil, 'BORDER')
doomedPanel.dimmer:SetAllPoints(doomedPanel)
doomedPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
doomedPanel.dimmer:Hide()
doomedPanel.swipe = CreateFrame('Cooldown', nil, doomedPanel, 'CooldownFrameTemplate')
doomedPanel.swipe:SetAllPoints(doomedPanel)
doomedPanel.swipe:SetDrawBling(false)
doomedPanel.text = CreateFrame('Frame', nil, doomedPanel)
doomedPanel.text:SetAllPoints(doomedPanel)
doomedPanel.text.tl = doomedPanel.text:CreateFontString(nil, 'OVERLAY')
doomedPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
doomedPanel.text.tl:SetPoint('TOPLEFT', doomedPanel, 'TOPLEFT', 2.5, -3)
doomedPanel.text.tl:SetJustifyH('LEFT')
doomedPanel.text.tl:SetJustifyV('TOP')
doomedPanel.text.tr = doomedPanel.text:CreateFontString(nil, 'OVERLAY')
doomedPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
doomedPanel.text.tr:SetPoint('TOPRIGHT', doomedPanel, 'TOPRIGHT', -2.5, -3)
doomedPanel.text.tr:SetJustifyH('RIGHT')
doomedPanel.text.tr:SetJustifyV('TOP')
doomedPanel.text.bl = doomedPanel.text:CreateFontString(nil, 'OVERLAY')
doomedPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
doomedPanel.text.bl:SetPoint('BOTTOMLEFT', doomedPanel, 'BOTTOMLEFT', 2.5, 3)
doomedPanel.text.bl:SetJustifyH('LEFT')
doomedPanel.text.bl:SetJustifyV('BOTTOM')
doomedPanel.text.br = doomedPanel.text:CreateFontString(nil, 'OVERLAY')
doomedPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
doomedPanel.text.br:SetPoint('BOTTOMRIGHT', doomedPanel, 'BOTTOMRIGHT', -2.5, 3)
doomedPanel.text.br:SetJustifyH('RIGHT')
doomedPanel.text.br:SetJustifyV('BOTTOM')
doomedPanel.button = CreateFrame('Button', nil, doomedPanel)
doomedPanel.button:SetAllPoints(doomedPanel)
doomedPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local doomedPreviousPanel = CreateFrame('Frame', 'doomedPreviousPanel', UIParent)
doomedPreviousPanel:SetFrameStrata('BACKGROUND')
doomedPreviousPanel:SetSize(64, 64)
doomedPreviousPanel:Hide()
doomedPreviousPanel:RegisterForDrag('LeftButton')
doomedPreviousPanel:SetScript('OnDragStart', doomedPreviousPanel.StartMoving)
doomedPreviousPanel:SetScript('OnDragStop', doomedPreviousPanel.StopMovingOrSizing)
doomedPreviousPanel:SetMovable(true)
doomedPreviousPanel.icon = doomedPreviousPanel:CreateTexture(nil, 'BACKGROUND')
doomedPreviousPanel.icon:SetAllPoints(doomedPreviousPanel)
doomedPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
doomedPreviousPanel.border = doomedPreviousPanel:CreateTexture(nil, 'ARTWORK')
doomedPreviousPanel.border:SetAllPoints(doomedPreviousPanel)
doomedPreviousPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')
local doomedCooldownPanel = CreateFrame('Frame', 'doomedCooldownPanel', UIParent)
doomedCooldownPanel:SetSize(64, 64)
doomedCooldownPanel:SetFrameStrata('BACKGROUND')
doomedCooldownPanel:Hide()
doomedCooldownPanel:RegisterForDrag('LeftButton')
doomedCooldownPanel:SetScript('OnDragStart', doomedCooldownPanel.StartMoving)
doomedCooldownPanel:SetScript('OnDragStop', doomedCooldownPanel.StopMovingOrSizing)
doomedCooldownPanel:SetMovable(true)
doomedCooldownPanel.icon = doomedCooldownPanel:CreateTexture(nil, 'BACKGROUND')
doomedCooldownPanel.icon:SetAllPoints(doomedCooldownPanel)
doomedCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
doomedCooldownPanel.border = doomedCooldownPanel:CreateTexture(nil, 'ARTWORK')
doomedCooldownPanel.border:SetAllPoints(doomedCooldownPanel)
doomedCooldownPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')
doomedCooldownPanel.cd = CreateFrame('Cooldown', nil, doomedCooldownPanel, 'CooldownFrameTemplate')
doomedCooldownPanel.cd:SetAllPoints(doomedCooldownPanel)
local doomedInterruptPanel = CreateFrame('Frame', 'doomedInterruptPanel', UIParent)
doomedInterruptPanel:SetFrameStrata('BACKGROUND')
doomedInterruptPanel:SetSize(64, 64)
doomedInterruptPanel:Hide()
doomedInterruptPanel:RegisterForDrag('LeftButton')
doomedInterruptPanel:SetScript('OnDragStart', doomedInterruptPanel.StartMoving)
doomedInterruptPanel:SetScript('OnDragStop', doomedInterruptPanel.StopMovingOrSizing)
doomedInterruptPanel:SetMovable(true)
doomedInterruptPanel.icon = doomedInterruptPanel:CreateTexture(nil, 'BACKGROUND')
doomedInterruptPanel.icon:SetAllPoints(doomedInterruptPanel)
doomedInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
doomedInterruptPanel.border = doomedInterruptPanel:CreateTexture(nil, 'ARTWORK')
doomedInterruptPanel.border:SetAllPoints(doomedInterruptPanel)
doomedInterruptPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')
doomedInterruptPanel.cast = CreateFrame('Cooldown', nil, doomedInterruptPanel, 'CooldownFrameTemplate')
doomedInterruptPanel.cast:SetAllPoints(doomedInterruptPanel)
doomedInterruptPanel.cast:SetDrawBling(false)
local doomedExtraPanel = CreateFrame('Frame', 'doomedExtraPanel', UIParent)
doomedExtraPanel:SetFrameStrata('BACKGROUND')
doomedExtraPanel:SetSize(64, 64)
doomedExtraPanel:Hide()
doomedExtraPanel:RegisterForDrag('LeftButton')
doomedExtraPanel:SetScript('OnDragStart', doomedExtraPanel.StartMoving)
doomedExtraPanel:SetScript('OnDragStop', doomedExtraPanel.StopMovingOrSizing)
doomedExtraPanel:SetMovable(true)
doomedExtraPanel.icon = doomedExtraPanel:CreateTexture(nil, 'BACKGROUND')
doomedExtraPanel.icon:SetAllPoints(doomedExtraPanel)
doomedExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
doomedExtraPanel.border = doomedExtraPanel:CreateTexture(nil, 'ARTWORK')
doomedExtraPanel.border:SetAllPoints(doomedExtraPanel)
doomedExtraPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.AFFLICTION] = {
		{1, ''},
		{2, '2'},
		{3, '3+'},
		{5, '5+'},
		{8, '8+'},
	},
	[SPEC.DEMONOLOGY] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
	[SPEC.DESTRUCTION] = {
		{1, ''},
		{2, '2'},
		{3, '3+'},
		{5, '5+'},
	}
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

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
		[161895] = true, -- Thing From Beyond (40+ Corruption)
	},
}

function autoAoe:Add(guid, update)
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

function autoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function autoAoe:Clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count, i = 0
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

function autoAoe:Purge()
	local update, guid, t
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

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_pet = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		mana_cost = 0,
		shard_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		summon_count = 0,
		max_range = 40,
		velocity = 0,
		last_used = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
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
	return self:Cooldown() <= (seconds or 0)
end

function Ability:Usable()
	if not self.known then
		return false
	end
	if self:Cost() > Player.mana then
		return false
	end
	if self:ShardCost() > Player.soul_shards then
		return false
	end
	if self.requires_pet and not Player.pet_active then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready()
end

function Ability:Remains()
	if self:Casting() or self:Traveling() then
		return self:Duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up()
	return self:Remains() > 0
end

function Ability:Down()
	return not self:Up()
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:Traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if Player.time - self.travel_start[Target.guid] < self.max_range / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:Up() and 1 or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:Cost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana_max) or 0
end

function Ability:ShardCost()
	return self.shard_cost
end

function Ability:Charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
end

function Ability:Channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:CastRegen()
	return Player.mana_regen * self:CastTime() - self:Cost()
end

function Ability:WontCapMana(reduction)
	return (Player.mana + self:CastRegen()) < (Player.mana_max - (reduction or 5))
end

function Ability:Previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:AzeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {}
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	else
		self.auto_aoe.trigger = 'SPELL_DAMAGE'
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
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:Update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:Duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration = self:Duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

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
local GrimoireOfSacrifice = Ability:Add(108503, true, true, 196099)
GrimoireOfSacrifice.buff_duration = 3600
GrimoireOfSacrifice.cooldown_duration = 30
local MortalCoil = Ability:Add(6789, false, true)
MortalCoil.mana_cost = 2
MortalCoil.buff_duration = 3
MortalCoil.cooldown_duration = 45
MortalCoil:SetVelocity(24)
------ Procs
local SoulConduit = Ability:Add(215941, true, true)
------ Permanent Pets
local SummonImp = Ability:Add(688, false, true)
SummonImp.shard_cost = 1
SummonImp.pet_family = 'Imp'
local SummonFelImp = Ability:Add(112866, false, true, 219424)
SummonFelImp.shard_cost = 1
SummonFelImp.pet_family = 'Fel Imp'
local SummonFelhunter = Ability:Add(691, false, true)
SummonFelhunter.shard_cost = 1
SummonFelhunter.pet_family = 'Felhunter'
local SummonObserver = Ability:Add(112869, false, true, 219450)
SummonObserver.shard_cost = 1
SummonObserver.pet_family = 'Observer'
local SummonVoidwalker = Ability:Add(697, false, true)
SummonVoidwalker.shard_cost = 1
SummonVoidwalker.pet_family = 'Voidwalker'
local SummonVoidlord = Ability:Add(112867, false, true, 219445)
SummonVoidlord.shard_cost = 1
SummonVoidlord.pet_family = 'Voidlord'
local SummonSuccubus = Ability:Add(712, false, true)
SummonSuccubus.shard_cost = 1
SummonSuccubus.pet_family = 'Succubus'
local SummonShivarra = Ability:Add(112868, false, true, 219436)
SummonShivarra.shard_cost = 1
SummonShivarra.pet_family = 'Shivarra'
local SummonFelguard = Ability:Add(30146, false, true)
SummonFelguard.shard_cost = 1
SummonFelguard.pet_family = 'Felguard'
local SummonWrathguard = Ability:Add(112870, false, true, 219467)
SummonWrathguard.shard_cost = 1
SummonWrathguard.pet_family = 'Wrathguard'
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
Corruption:TrackAuras()
local SeedOfCorruption = Ability:Add(27243, false, true, 27285)
SeedOfCorruption.shard_cost = 1
SeedOfCorruption.buff_duration = 12
SeedOfCorruption:SetVelocity(30)
SeedOfCorruption.hasted_duration = true
SeedOfCorruption:AutoAoe(true)
SeedOfCorruption:TrackAuras()
local ShadowBolt = Ability:Add(232670, false, true)
ShadowBolt.mana_cost = 2
ShadowBolt:SetVelocity(25)
local SummonDarkglare = Ability:Add(205180, false, true)
SummonDarkglare.mana_cost = 2
SummonDarkglare.cooldown_duration = 180
SummonDarkglare.summon_count = 1
SummonDarkglare.summoning = false
local UnstableAffliction = Ability:Add(30108, false, true)
UnstableAffliction.shard_cost = 1
UnstableAffliction.buff_duration = 8
UnstableAffliction.tick_interval = 2
UnstableAffliction.hasted_duration = true
UnstableAffliction.hasted_ticks = true
UnstableAffliction[1] = Ability:Add(233490, false, true)
UnstableAffliction[2] = Ability:Add(233496, false, true)
UnstableAffliction[3] = Ability:Add(233497, false, true)
UnstableAffliction[4] = Ability:Add(233498, false, true)
UnstableAffliction[5] = Ability:Add(233499, false, true)
------ Talents
local AbsoluteCorruption = Ability:Add(196103, false, true)
local CreepingDeath = Ability:Add(264000, false, true)
local DarkSoulMisery = Ability:Add(113860, true, true)
DarkSoulMisery.buff_duration = 20
DarkSoulMisery.cooldown_duration = 120
local Deathbolt = Ability:Add(264106, false, true)
Deathbolt.mana_cost = 2
Deathbolt.cooldown_duration = 30
Deathbolt:SetVelocity(35)
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
Haunt:SetVelocity(40)
local Nightfall = Ability:Add(108558, false, true, 264571)
Nightfall.buff_duration = 12
local PhantomSingularity = Ability:Add(205179, false, true, 205246)
PhantomSingularity.buff_duration = 16
PhantomSingularity.cooldown_duration = 45
PhantomSingularity.tick_interval = 2
PhantomSingularity.hasted_duration = true
PhantomSingularity.hasted_ticks = true
PhantomSingularity:AutoAoe(false, 'periodic')
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
VileTaint:AutoAoe(true)
local WritheInAgony = Ability:Add(196102, false, true)
---- Demonology
------ Base Abilities
local CallDreadstalkers = Ability:Add(104316, false, true)
CallDreadstalkers.buff_duration = 12
CallDreadstalkers.cooldown_duration = 20
CallDreadstalkers.shard_cost = 2
CallDreadstalkers.summon_count = 2
local Demonbolt = Ability:Add(264178, false, true)
Demonbolt.mana_cost = 2
Demonbolt.shard_cost = -2
Demonbolt:SetVelocity(35)
local HandOfGuldan = Ability:Add(105174, false, true, 86040)
HandOfGuldan.shard_cost = 1
HandOfGuldan:AutoAoe(true)
local Implosion = Ability:Add(196277, false, true, 196278)
Implosion.mana_cost = 2
Implosion:AutoAoe()
local ShadowBoltDemo = Ability:Add(686, false, true)
ShadowBoltDemo.mana_cost = 2
ShadowBoltDemo.shard_cost = -1
ShadowBoltDemo:SetVelocity(20)
local SummonDemonicTyrant = Ability:Add(265187, true, true)
SummonDemonicTyrant.buff_duration = 15
SummonDemonicTyrant.cooldown_duration = 90
SummonDemonicTyrant.mana_cost = 2
SummonDemonicTyrant.summon_count = 1
SummonDemonicTyrant.summoning = false
------ Pet Abilities
local AxeToss = Ability:Add(89766, false, true, 119914)
AxeToss.cooldown_duration = 30
AxeToss.requires_pet = true
AxeToss.triggers_gcd = false
AxeToss.player_triggered = true
local Felstorm = Ability:Add(89751, true, true, 89753)
Felstorm.auraTarget = 'pet'
Felstorm.buff_duration = 5
Felstorm.cooldown_duration = 30
Felstorm.tick_interval = 1
Felstorm.hasted_duration = true
Felstorm.hasted_ticks = true
Felstorm.requires_pet = true
Felstorm.triggers_gcd = false
Felstorm:AutoAoe()
local FelFirebolt = Ability:Add(104318, false, false)
FelFirebolt.triggers_gcd = false
local LegionStrike = Ability:Add(30213, false, true)
LegionStrike.requires_pet = true
LegionStrike:AutoAoe()
------ Talents
local BilescourgeBombers = Ability:Add(267211, false, true, 267213)
BilescourgeBombers.buff_duration = 6
BilescourgeBombers.cooldown_duration = 30
BilescourgeBombers.shard_cost = 2
BilescourgeBombers:AutoAoe(true)
local DemonicCalling = Ability:Add(205145, true, true, 205146)
DemonicCalling.buff_duration = 20
local DemonicConsumption = Ability:Add(267215, false, true)
local DemonicStrength = Ability:Add(267171, true, true)
DemonicStrength.auraTarget = 'pet'
DemonicStrength.buff_duration = 20
DemonicStrength.cooldown_duration = 60
local Doom = Ability:Add(603, false, true)
Doom.mana_cost = 1
Doom.buff_duration = 30
Doom.tick_interval = 30
Doom.hasted_duration = true
local Dreadlash = Ability:Add(264078, false, true)
local FromTheShadows = Ability:Add(267170, false, true, 270569)
FromTheShadows.buff_duration = 12
local InnerDemons = Ability:Add(267216, false, true)
local GrimoireFelguard = Ability:Add(111898, false, true)
GrimoireFelguard.cooldown_duration = 120
GrimoireFelguard.shard_cost = 1
GrimoireFelguard.summon_count = 1
local NetherPortal = Ability:Add(267217, true, true, 267218)
NetherPortal.buff_duration = 15
NetherPortal.cooldown_duration = 180
NetherPortal.shard_cost = 1
local PowerSiphon = Ability:Add(264130, false, true)
PowerSiphon.cooldown_duration = 30
local SoulStrike = Ability:Add(264057, false, true, 267964)
SoulStrike.cooldown_duration = 10
SoulStrike.shard_cost = -1
SoulStrike.requires_pet = true
local SummonVilefiend = Ability:Add(264119, false, true)
SummonVilefiend.buff_duration = 15
SummonVilefiend.cooldown_duration = 45
SummonVilefiend.shard_cost = 1
SummonVilefiend.summon_count = 1
------ Procs
local DemonicCore = Ability:Add(267102, true, true, 264173)
DemonicCore.buff_duration = 20
local DemonicPower = Ability:Add(265273, true, true)
DemonicPower.buff_duration = 15
---- Destruction
------ Base Abilities
local Conflagrate = Ability:Add(17962, false, true)
Conflagrate.cooldown_duration = 12.96
Conflagrate.mana_cost = 1
Conflagrate.requires_charge = true
Conflagrate.hasted_cooldown = true
local Immolate = Ability:Add(348, false, true, 157736)
Immolate.buff_duration = 18
Immolate.mana_cost = 1.5
Immolate.tick_interval = 3
Immolate.hasted_ticks = true
local Incinerate = Ability:Add(29722, false, true)
Incinerate.mana_cost = 2
Incinerate:SetVelocity(25)
local Havoc = Ability:Add(80240, false, true)
Havoc.buff_duration = 10
Havoc.cooldown_duration = 30
Havoc.mana_cost = 2
local ChaosBolt = Ability:Add(116858, false, true)
ChaosBolt.shard_cost = 2
ChaosBolt:SetVelocity(20)
local RainOfFire = Ability:Add(5470, false, true, 42223)
RainOfFire.buff_duration = 8
RainOfFire.shard_cost = 3
RainOfFire.hasted_ticks = true
RainOfFire:AutoAoe(true)
local SummonInfernal = Ability:Add(1122, false, true, 22703)
SummonInfernal.cooldown_duration = 180
SummonInfernal.mana_cost = 2
SummonInfernal.shard_cost = 1
SummonInfernal:AutoAoe(true)
------ Talents
local Cataclysm = Ability:Add(152108, false, true)
Cataclysm.cooldown_duration = 30
Cataclysm:AutoAoe(true)
local ChannelDemonfire = Ability:Add(196447, false, true)
ChannelDemonfire.cooldown_duration = 25
ChannelDemonfire.mana_cost = 1.5
local Inferno = Ability:Add(270545, false, true)
local InternalCombustion = Ability:Add(266134, false, true)
local SoulFire = Ability:Add(6353, false, true)
SoulFire.cooldown_duration = 20
SoulFire.mana_cost = 2
SoulFire:SetVelocity(24)
local Shadowburn = Ability:Add(17877, false, true)
Shadowburn.buff_duration = 5
Shadowburn.cooldown_duration = 12
Shadowburn.mana_cost = 1
Shadowburn.requires_charge = true
------ Procs
local Backdraft = Ability:Add(117828, true, true)
Backdraft.buff_duration = 10
-- Heart of Azeroth
---- Azerite Traits
local BalefulInvocation = Ability:Add(287059, true, true)
local CascadingCalamity = Ability:Add(275372, true, true, 275378)
CascadingCalamity.buff_duration = 15
local DreadfulCalling = Ability:Add(278727, true, true)
local ExplosivePotential = Ability:Add(275395, true, true, 275398)
ExplosivePotential.buff_duration = 15
local InevitableDemise = Ability:Add(273521, true, true, 273525)
InevitableDemise.buff_duration = 20
local PandemicInvocation = Ability:Add(289364, true, true)
local ShadowsBite = Ability:Add(272944, true, true, 272945)
ShadowsBite.buff_duration = 8
---- Major Essences
local BloodOfTheEnemy = Ability:Add({297108, 298273, 298277} , false, true)
BloodOfTheEnemy.buff_duration = 10
BloodOfTheEnemy.cooldown_duration = 120
BloodOfTheEnemy.essence_id = 23
BloodOfTheEnemy.essence_major = true
BloodOfTheEnemy:AutoAoe(true)
local ConcentratedFlame = Ability:Add({295373, 299349, 299353}, true, true, 295378)
ConcentratedFlame.buff_duration = 180
ConcentratedFlame.cooldown_duration = 30
ConcentratedFlame.requires_charge = true
ConcentratedFlame.essence_id = 12
ConcentratedFlame.essence_major = true
ConcentratedFlame:SetVelocity(40)
ConcentratedFlame.dot = Ability:Add(295368, false, true)
ConcentratedFlame.dot.buff_duration = 6
ConcentratedFlame.dot.tick_interval = 2
ConcentratedFlame.dot.essence_id = 12
ConcentratedFlame.dot.essence_major = true
local GuardianOfAzeroth = Ability:Add({295840, 299355, 299358}, false, true)
GuardianOfAzeroth.cooldown_duration = 180
GuardianOfAzeroth.essence_id = 14
GuardianOfAzeroth.essence_major = true
local FocusedAzeriteBeam = Ability:Add({295258, 299336, 299338}, false, true)
FocusedAzeriteBeam.cooldown_duration = 90
FocusedAzeriteBeam.essence_id = 5
FocusedAzeriteBeam.essence_major = true
FocusedAzeriteBeam:AutoAoe()
local MemoryOfLucidDreams = Ability:Add({298357, 299372, 299374}, true, true)
MemoryOfLucidDreams.buff_duration = 15
MemoryOfLucidDreams.cooldown_duration = 120
MemoryOfLucidDreams.essence_id = 27
MemoryOfLucidDreams.essence_major = true
local PurifyingBlast = Ability:Add({295337, 299345, 299347}, false, true, 295338)
PurifyingBlast.cooldown_duration = 60
PurifyingBlast.essence_id = 6
PurifyingBlast.essence_major = true
PurifyingBlast:AutoAoe(true)
local ReapingFlames = Ability:Add({310690, 311194, 311195}, false, true)
ReapingFlames.cooldown_duration = 45
ReapingFlames.essence_id = 35
ReapingFlames.essence_major = true
local RippleInSpace = Ability:Add({302731, 302982, 302983}, true, true)
RippleInSpace.buff_duration = 2
RippleInSpace.cooldown_duration = 60
RippleInSpace.essence_id = 15
RippleInSpace.essence_major = true
local TheUnboundForce = Ability:Add({298452, 299376,299378}, false, true)
TheUnboundForce.cooldown_duration = 45
TheUnboundForce.essence_id = 28
TheUnboundForce.essence_major = true
local VisionOfPerfection = Ability:Add({296325, 299368, 299370}, true, true, 303345)
VisionOfPerfection.buff_duration = 10
VisionOfPerfection.essence_id = 22
VisionOfPerfection.essence_major = true
local WorldveinResonance = Ability:Add({295186, 298628, 299334}, true, true)
WorldveinResonance.cooldown_duration = 60
WorldveinResonance.essence_id = 4
WorldveinResonance.essence_major = true
---- Minor Essences
local AncientFlame = Ability:Add(295367, false, true)
AncientFlame.buff_duration = 10
AncientFlame.essence_id = 12
local CondensedLifeForce = Ability:Add(295367, false, true)
CondensedLifeForce.essence_id = 14
local FocusedEnergy = Ability:Add(295248, true, true)
FocusedEnergy.buff_duration = 4
FocusedEnergy.essence_id = 5
local Lifeblood = Ability:Add(295137, true, true)
Lifeblood.essence_id = 4
local LucidDreams = Ability:Add(298343, true, true)
LucidDreams.buff_duration = 8
LucidDreams.essence_id = 27
local PurificationProtocol = Ability:Add(295305, false, true)
PurificationProtocol.essence_id = 6
PurificationProtocol:AutoAoe()
local RealityShift = Ability:Add(302952, true, true)
RealityShift.buff_duration = 20
RealityShift.cooldown_duration = 30
RealityShift.essence_id = 15
local RecklessForce = Ability:Add(302932, true, true)
RecklessForce.buff_duration = 3
RecklessForce.essence_id = 28
RecklessForce.counter = Ability:Add(302917, true, true)
RecklessForce.counter.essence_id = 28
local StriveForPerfection = Ability:Add(299369, true, true)
StriveForPerfection.essence_id = 22
-- PvP talents
local RotAndDecay = Ability:Add(212371, false, true)
-- Racials

-- Trinket Effects
local ShiverVenom = Ability:Add(301624, false, true) -- Shiver Venom Relic
ShiverVenom.buff_duration = 20
ShiverVenom.tick_interval = 4
ShiverVenom.hasted_ticks = true
-- End Abilities

-- Start Summoned Pets

local SummonedPet, Pet = {}, {}
SummonedPet.__index = SummonedPet
local summonedPets = {
	all = {}
}

function summonedPets:Find(guid)
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	return unitId and self.byUnitId[tonumber(unitId)]
end

function summonedPets:Purge()
	local _, pet, guid, unit
	for _, pet in next, self.known do
		for guid, unit in next, pet.active_units do
			if unit.expires <= Player.time then
				pet.active_units[guid] = nil
			end
		end
	end
end

function summonedPets:Count()
	local _, pet, guid, unit
	local count = 0
	for _, pet in next, self.known do
		count = count + pet:Count()
	end
	return count
end

function summonedPets:EmpoweredRemains()
	return max(0, (self.empowered_ends or 0) - Player.time)
end

function summonedPets:Empowered()
	return self:EmpoweredRemains() > 0
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
	summonedPets.all[#summonedPets.all + 1] = pet
	return pet
end

function SummonedPet:Remains()
	local expires_max, guid, unit = 0
	if self.summon_spell and self.summon_spell.summon_count > 0 and self.summon_spell:Casting() then
		expires_max = self.duration
	end
	for guid, unit in next, self.active_units do
		if unit.expires > expires_max then
			expires_max = unit.expires
		end
	end
	return max(expires_max - Player.time - Player.execute_remains, 0)
end

function SummonedPet:Up()
	return self:Remains() > 0
end

function SummonedPet:Down()
	return self:Remains() <= 0
end

function SummonedPet:Count()
	local count, guid, unit = 0
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
	local count, guid, unit = 0
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

-- Summoned Pets
Pet.Darkglare = SummonedPet:Add(103673, 20, SummonDarkglare)
Pet.DemonicTyrant = SummonedPet:Add(135002, 15, SummonDemonicTyrant)
Pet.Dreadstalker = SummonedPet:Add(98035, 12, CallDreadstalkers)
Pet.Felguard = SummonedPet:Add(17252, 15, GrimoireFelguard)
Pet.Infernal = SummonedPet:Add(89, 30, SummonInfernal)
Pet.Vilefiend = SummonedPet:Add(135816, 15, SummonVilefiend)
Pet.WildImp = SummonedPet:Add(55659, 20, HandOfGuldan)
---- Nether Portal / Inner Demons
Pet.Bilescourge = SummonedPet:Add(136404, 15, NetherPortal)
Pet.Darkhound = SummonedPet:Add(136408, 15, NetherPortal)
Pet.EredarBrute = SummonedPet:Add(136405, 15, NetherPortal)
Pet.EyeOfGuldan = SummonedPet:Add(136401, 15, NetherPortal)
Pet.IllidariSatyr = SummonedPet:Add(136398, 15, NetherPortal)
Pet.PrinceMalchezaar = SummonedPet:Add(136397, 15, NetherPortal)
Pet.Shivarra = SummonedPet:Add(136406, 15, NetherPortal)
Pet.Urzul = SummonedPet:Add(136402, 15, NetherPortal)
Pet.ViciousHellhound = SummonedPet:Add(136399, 15, NetherPortal)
Pet.VoidTerror = SummonedPet:Add(136403, 15, NetherPortal)
Pet.Wrathguard = SummonedPet:Add(136407, 15, NetherPortal)
Pet.WildImpID = SummonedPet:Add(143622, 20, InnerDemons)
-- Heart of Azeroth
Pet.GuardianOfAzeroth = SummonedPet:Add(152396, 30, GuardianOfAzeroth)
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
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:Cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
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
local GreaterFlaskOfEndlessFathoms = InventoryItem:Add(168652)
GreaterFlaskOfEndlessFathoms.buff = Ability:Add(298837, true, true)
local PotionOfUnbridledFury = InventoryItem:Add(169299)
PotionOfUnbridledFury.buff = Ability:Add(300714, true, true)
PotionOfUnbridledFury.buff.triggers_gcd = false
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
Trinket.ShiverVenomRelic = InventoryItem:Add(168905)
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:Init()
	self.locations = {}
	self.traits = {}
	self.essences = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:Update()
	local _, loc, slot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for pid in next, self.essences do
		self.essences[pid] = nil
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			for _, slot in next, C_AzeriteEmpoweredItem.GetAllTierInfo(loc) do
				if slot.azeritePowerIDs then
					for _, pid in next, slot.azeritePowerIDs do
						if C_AzeriteEmpoweredItem.IsPowerSelected(loc, pid) then
							self.traits[pid] = 1 + (self.traits[pid] or 0)
							pinfo = C_AzeriteEmpoweredItem.GetPowerInfo(pid)
							if pinfo and pinfo.spellID then
								--print('Azerite found:', pinfo.azeritePowerID, GetSpellInfo(pinfo.spellID))
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
	for _, loc in next, C_AzeriteEssence.GetMilestones() or {} do
		if loc.slot then
			pid = C_AzeriteEssence.GetMilestoneEssence(loc.ID)
			if pid then
				pinfo = C_AzeriteEssence.GetEssenceInfo(pid)
				self.essences[pid] = {
					id = pid,
					rank = pinfo.rank,
					major = loc.slot == 0,
				}
			end
		end
	end
end

-- End Azerite Trait API

-- Start Player API

function Player:Health()
	return self.health
end

function Player:HealthMax()
	return self.health_max
end

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:ManaDeficit()
	return self.mana_max - self.mana
end

function Player:ManaPct()
	return self.mana / self.mana_max * 100
end

function Player:ManaTimeToMax()
	local deficit = self.mana_max - self.mana
	if deficit <= 0 then
		return 0
	end
	return deficit / self.mana_regen
end

function Player:UnderAttack()
	return (Player.time - self.last_swing_taken) < 3
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	return 0
end

function Player:BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID, slot
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:ImpsIn(seconds)
	local count, guid, unit = 0
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
	if Pet.WildImpID.known then
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
		if HandOfGuldan.cast_shards >= 3 and seconds > 0.5 then
			count = count + 3
		elseif HandOfGuldan.cast_shards >= 2 and seconds > 0.4 then
			count = count + 2
		elseif HandOfGuldan.cast_shards >= 1 and seconds > 0.3 then
			count = count + 1
		end
	end
	return count
end

function Player:UpdatePet()
	self.pet = UnitGUID('pet')
	self.pet_alive = (self.pet and not UnitIsDead('pet') or (self.ability_casting and self.ability_casting.pet_family)) and true
	self.pet_active = (self.pet_alive and not self.pet_stuck or IsFlying()) and true
end

function Player:UpdateAbilities()
	Player.mana_max = UnitPowerMax('player', 0)
	Player.soul_shards_max = UnitPowerMax('player', 7)

	local _, ability, spellId, pet

	for _, ability in next, abilities.all do
		ability.known = false
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) or Azerite.traits[spellId] then
				ability.known = true
				break
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) then
			ability.known = false -- spell is locked, do not mark as known
		elseif ability.essence_id and Azerite.essences[ability.essence_id] then
			if ability.essence_major then
				ability.known = Azerite.essences[ability.essence_id].major
			else
				ability.known = true
			end
		end
	end

	for _, pet in next, summonedPets.all do
		pet.known = false
		if pet.summon_spell then
			if pet.summon_spell.known then
				pet.known = true
			elseif pet.summon_spell == NetherPortal and InnerDemons.known then
				pet.known = true
			end
		end
	end

	if DrainSoul.known then
		ShadowBolt.known = false
	end
	if UnstableAffliction.known then
		UnstableAffliction[1].known = true
		UnstableAffliction[2].known = true
		UnstableAffliction[3].known = true
		UnstableAffliction[4].known = true
		UnstableAffliction[5].known = true
	end
	DemonicPower.known = SummonDemonicTyrant.known
	SummonImp.known = SummonImp.known and not SummonFelImp.known
	SummonFelhunter.known = SummonFelhunter.known and not SummonObserver.known
	SummonVoidwalker.known = SummonVoidwalker.known and not SummonVoidlord.known
	SummonSuccubus.known = SummonSuccubus.known and not SummonShivarra.known
	SummonFelguard.known = SummonFelguard.known and not SummonWrathguard.known
	AxeToss.known = SummonFelguard.known or SummonWrathguard.known
	Felstorm.known = SummonFelguard.known or SummonWrathguard.known
	LegionStrike.known = SummonFelguard.known or SummonWrathguard.known
	SpellLock.known = SummonFelhunter.known or SummonObserver.known
	FelFirebolt.known = Pet.WildImp.known or Pet.WildImpID.known

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				abilities.velocity[#abilities.velocity + 1] = ability
			end
			if ability.auto_aoe then
				abilities.autoAoe[#abilities.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				abilities.trackAuras[#abilities.trackAuras + 1] = ability
			end
		end
	end
	summonedPets.known = {}
	summonedPets.byUnitId = {}
	for _, pet in next, summonedPets.all do
		if pet.known then
			summonedPets.known[#summonedPets.known + 1] = pet
			summonedPets.byUnitId[pet.unitId] = pet
			if pet.unitId2 then
				summonedPets.byUnitId[pet.unitId2] = pet
			end
		end
	end
end

-- End Player API

-- Start Target API

function Target:UpdateHealth()
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	table.remove(self.healthArray, 1)
	self.healthArray[25] = self.health
	self.timeToDieMax = self.health / Player.health_max * 15
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.healthArray[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	if UI:ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = UnitLevel('player')
		self.hostile = true
		local i
		for i = 1, 25 do
			self.healthArray[i] = 0
		end
		self:UpdateHealth()
		if Opt.always_on then
			UI:UpdateCombat()
			doomedPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			doomedPreviousPanel:Hide()
		end
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		local i
		for i = 1, 25 do
			self.healthArray[i] = UnitHealth('target')
		end
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self:UpdateHealth()
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= UnitLevel('player') + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health_max > Player.health_max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		doomedPanel:Show()
		return true
	end
end

-- End Target API

-- Start Ability Modifications

function ConcentratedFlame.dot:Remains()
	if ConcentratedFlame:Traveling() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function Implosion:Usable()
	return Player.imp_count > 0 and Ability.Usable(self)
end

function PowerSiphon:Usable()
	return Player.imp_count > 0 and Ability.Usable(self)
end

function Corruption:Remains()
	if SeedOfCorruption:Up() or SeedOfCorruption:Previous() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function UnstableAffliction:Stack()
	return (
		(UnstableAffliction[1]:Up() and 1 or 0) +
		(UnstableAffliction[2]:Up() and 1 or 0) +
		(UnstableAffliction[3]:Up() and 1 or 0) +
		(UnstableAffliction[4]:Up() and 1 or 0) +
		(UnstableAffliction[5]:Up() and 1 or 0))
end

function UnstableAffliction:Remains()
	return max(UnstableAffliction[1]:Remains(), UnstableAffliction[2]:Remains(), UnstableAffliction[3]:Remains(), UnstableAffliction[4]:Remains(), UnstableAffliction[5]:Remains())
end

function UnstableAffliction:Lowest()
	local ua = UnstableAffliction[1]
	local lowest = Ability.Remains(ua)
	local remains, i
	for i = 2, 5 do
		remains = Ability.Remains(ua)
		if remains > 0 and remains < lowest then
			ua = UnstableAffliction[i]
			lowest = remains
		end
	end
	return ua, lowest
end

function UnstableAffliction:LowestRemains()
	local _, remains = UnstableAffliction:Lowest()
	return remains
end

function UnstableAffliction:Next()
	local i
	for i = 1, 5 do
		if Ability.Remains(UnstableAffliction[i]) <= 0 then
			return UnstableAffliction[i]
		end
	end
	return UnstableAffliction:Lowest()
end

UnstableAffliction[1].Remains = function(self)
	if UnstableAffliction:Casting() and UnstableAffliction:Next() == self then
		return UnstableAffliction:Duration()
	end
	return Ability.Remains(self)
end
UnstableAffliction[2].Remains = UnstableAffliction[1].Remains
UnstableAffliction[3].Remains = UnstableAffliction[1].Remains
UnstableAffliction[4].Remains = UnstableAffliction[1].Remains
UnstableAffliction[5].Remains = UnstableAffliction[1].Remains

SummonImp.Up = function(self)
	if self:Casting() then
		return true
	end
	if not Player.pet_active then
		return false
	end
	return UnitCreatureFamily('pet') == self.pet_family
end
SummonFelImp.Up = SummonImp.Up
SummonFelhunter.Up = SummonImp.Up
SummonObserver.Up = SummonImp.Up
SummonVoidwalker.Up = SummonImp.Up
SummonVoidlord.Up = SummonImp.Up
SummonSuccubus.Up = SummonImp.Up
SummonShivarra.Up = SummonImp.Up
SummonFelguard.Up = SummonImp.Up
SummonWrathguard.Up = SummonImp.Up

function HandOfGuldan:ShardCost()
	return min(max(Player.soul_shards, 1), 3)
end

HandOfGuldan.imp_pool = {}

function HandOfGuldan:CastSuccess()
	if self.cast_shards >= 1 then
		self.imp_pool[#self.imp_pool + 1] = Player.time + 0.3
	end
	if self.cast_shards >= 2 then
		self.imp_pool[#self.imp_pool + 1] = Player.time + 0.4
	end
	if self.cast_shards >= 3 then
		self.imp_pool[#self.imp_pool + 1] = Player.time + 0.5
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
	local expires_min, guid, unit, sacrifice = Player.time + 60
	for guid, unit in next, Pet.WildImp.active_units do
		if unit.expires < expires_min then
			expires_min = unit.expires
			sacrifice = guid
		end
	end
	if Pet.WildImpID.known then
		for guid, unit in next, Pet.WildImpID.active_units do
			if unit.expires < expires_min then
				expires_min = unit.expires
				sacrifice = guid
			end
		end
	end
	if sacrifice then
		if Pet.WildImp.active_units[sacrifice] then
			Pet.WildImp.active_units[sacrifice] = nil
			return
		end
		if Pet.WildImpID.active_units[sacrifice] then
			Pet.WildImpID.active_units[sacrifice] = nil
			return
		end
	end
end

function Implosion:Implode()
	local guid
	for guid in next, Pet.WildImp.active_units do
		Pet.WildImp.active_units[guid] = nil
	end
	if Pet.WildImpID.known then
		for guid in next, Pet.WildImpID.active_units do
			Pet.WildImpID.active_units[guid] = nil
		end
	end
end

function DemonicPower:Remains()
	if SummonDemonicTyrant:Casting() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function DemonicPower:Ends()
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			break
		end
		if id == self.spellId then
			return max(0, Player.time + (expires - Player.ctime))
		end
	end
	return 0
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
		cost = cost - 1
	end
	return cost
end

function SummonDemonicTyrant:ShardCost()
	if BalefulInvocation.known then
		return -5
	end
	return self.shard_cost
end

function DemonicStrength:Usable()
	if Felstorm:Up() then
		return false
	end
	return Ability.Usable(self)
end

function SpellLock:Usable()
	if not (SummonFelhunter:Up() or SummonObserver:Up()) then
		return false
	end
	return Ability.Usable(self)
end

function AxeToss:Usable()
	if not Target.stunnable or not (SummonFelguard:Up() or SummonWrathguard:Up()) then
		return false
	end
	return Ability.Usable(self)
end

function CascadingCalamity:Remains()
	if UnstableAffliction:Casting() and UnstableAffliction:Stack() >= 2 then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function InevitableDemise:Stack()
	if DrainLife:Previous() or DrainLife:Channeling() then
		return 0
	end
	return Ability.Stack(self)
end

-- End Ability Modifications

-- Start Summoned Pet Modifications

function Pet.Darkglare:AddUnit(guid)
	local unit = SummonedPet.AddUnit(self, guid)
	unit.power = 0
	if SummonDarkglare.summoning then
		unit.full = true
		SummonDarkglare.summoning = false
	elseif VisionOfPerfection.known then
		unit.full = false
		unit.expires = Player.time + (self.duration * 0.35)
	end
	return unit
end

function Pet.DemonicTyrant:AddUnit(guid)
	local unit = SummonedPet.AddUnit(self, guid)
	unit.power = 0
	if SummonDemonicTyrant.summoning then
		unit.full = true
		if DemonicConsumption.known then
			self:Consumption(unit)
		end
		self:EmpowerLesser(15)
		SummonDemonicTyrant.summoning = false
	elseif VisionOfPerfection.known then
		unit.full = false
		unit.expires = Player.time + (self.duration * 0.35)
		self:EmpowerLesser(4)
	end
	return unit
end

function Pet.DemonicTyrant:Consumption(unit)
	local guid, imp
	for guid, imp in next, Pet.WildImp.active_units do
		if imp.expires > Player.time then
			unit.power = unit.power + (imp.energy / 2)
		end
		Pet.WildImp.active_units[guid] = nil
	end
	if Pet.WildImpID.known then
		for guid, imp in next, Pet.WildImpID.active_units do
			if imp.expires > Player.time then
				unit.power = unit.power + (imp.energy / 2)
			end
			Pet.WildImpID.active_units[guid] = nil
		end
	end
end

function Pet.DemonicTyrant:EmpowerLesser(seconds)
	local _, pet, guid, unit
	for _, pet in next, summonedPets.known do
		if pet ~= self then
			for guid, unit in next, pet.active_units do
				if unit.expires > Player.time then
					unit.expires = unit.expires + seconds
				end
			end
		end
	end
end

function Pet.DemonicTyrant:Power()
	local _, unit
	for _, unit in next, self.active_units do
		if unit.power > 0 then
			return unit.power
		end
	end
	return 0
end

function Pet.DemonicTyrant:AvailablePower()
	local power, guid, imp = 0
	for guid, imp in next, Pet.WildImp.active_units do
		if (imp.expires - Player.time) > Player.execute_remains then
			power = power + (imp.energy / 2)
		end
	end
	if Pet.WildImpID.known then
		for guid, imp in next, Pet.WildImpID.active_units do
			if (imp.expires - Player.time) > Player.execute_remains then
				power = power + (imp.energy / 2)
			end
		end
	end
	return power
end

function Pet.WildImp:AddUnit(guid)
	local unit = SummonedPet.AddUnit(self, guid)
	unit.energy = 100
	unit.cast_end = 0
	HandOfGuldan:ImpSpawned()
	return unit
end

function Pet.WildImpID:AddUnit(guid)
	local unit = SummonedPet.AddUnit(self, guid)
	unit.energy = 100
	unit.cast_end = 0
	InnerDemons:ImpSpawned()
	return unit
end

function Pet.WildImp:UnitRemains(unit)
	if DemonicConsumption.known and SummonDemonicTyrant:Casting() then
		return 0
	end
	local energy, remains = unit.energy, 0
	if unit.cast_end > Player.time then
		if summonedPets:Empowered() then
			remains = summonedPets:EmpoweredRemains()
		else
			energy = energy - 20
			remains = unit.cast_end - Player.time
		end
		remains = remains + (energy / 20 * FelFirebolt:CastTime())
	else
		unit.cast_end = 0
		remains = unit.expires - Player.time
	end
	return max(remains, 0)
end
Pet.WildImpID.UnitRemains = Pet.WildImp.UnitRemains

function Pet.WildImp:Count()
	if DemonicConsumption.known and SummonDemonicTyrant:Casting() then
		return 0
	end
	local count, guid, unit = 0
	for guid, unit in next, self.active_units do
		if self:UnitRemains(unit) > Player.execute_remains then
			count = count + 1
		end
	end
	for guid, unit in next, HandOfGuldan.imp_pool do
		if (unit - Player.time) < Player.execute_remains then
			count = count + 1
		end
	end
	return count
end

function Pet.WildImpID:Count()
	if DemonicConsumption.known and SummonDemonicTyrant:Casting() then
		return 0
	end
	local count, guid, unit = 0
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
	if DemonicConsumption.known and SummonDemonicTyrant:Casting() then
		return 0
	end
	return SummonedPet.Remains(self)
end
Pet.WildImpID.Remains = Pet.WildImp.Remains

function Pet.WildImp:Casting()
	if Player.combat_start == 0 then
		return false
	end
	local guid, unit = 0
	for guid, unit in next, self.active_units do
		if unit.cast_end >= Player.time then
			return true
		end
	end
	return false
end
Pet.WildImpID.Casting = Pet.WildImp.Casting

function Pet.WildImp:CastStart(unit)
	unit.cast_end = Player.time + FelFirebolt:CastTime()
end
Pet.WildImpID.CastStart = Pet.WildImp.CastStart

function Pet.WildImp:CastSuccess(unit)
	if not summonedPets:Empowered() then
		unit.energy = unit.energy - 20
	end
	if unit.energy <= 0 then
		self.active_units[unit.guid] = nil
		return
	end
	unit.cast_end = 0
end
Pet.WildImpID.CastSuccess = Pet.WildImp.CastSuccess

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

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.AFFLICTION] = {},
	[SPEC.DEMONOLOGY] = {},
	[SPEC.DESTRUCTION] = {}
}

APL[SPEC.AFFLICTION].main = function(self)
	Player.use_cds = Target.boss or Target.timeToDie > 40
	Player.use_seed = (SowTheSeeds.known and Player.enemies >= 3) or (SiphonLife.known and Player.enemies >= 5) or Player.enemies >= 8
	Player.use_db = Agony:Up() and Corruption:Up() and (not SiphonLife.known or SiphonLife:Up()) and (not Haunt.known or not Haunt:Ready()) and (not PhantomSingularity.known or not PhantomSingularity:Ready())
	Player.ua_ct = UnstableAffliction:CastTime()
	Player.ua_stack = UnstableAffliction:Stack()
	Player.ua_remains = UnstableAffliction:Remains()

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
		if GrimoireOfSacrifice.known then
			if GrimoireOfSacrifice:Remains() < 300 then
				if Player.pet_active then
					return GrimoireOfSacrifice
				else
					return SummonImp
				end
			end
		elseif not Player.pet_active then
			return SummonImp
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfEndlessFathoms:Usable() and GreaterFlaskOfEndlessFathoms.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfEndlessFathoms)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
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
		if GrimoireOfSacrifice.known then
			if GrimoireOfSacrifice:Remains() < 300 then
				if Player.pet_active then
					UseExtra(GrimoireOfSacrifice)
				else
					UseExtra(SummonImp)
				end
			end
		elseif not Player.pet_active then
			UseExtra(SummonImp)
		end
	end
--[[
actions=variable,name=use_seed,value=talent.sow_the_seeds.enabled&spell_targets.seed_of_corruption_aoe>=3+raid_event.invulnerable.up|talent.siphon_life.enabled&spell_targets.seed_of_corruption>=5+raid_event.invulnerable.up|spell_targets.seed_of_corruption>=8+raid_event.invulnerable.up
actions+=/variable,name=padding,op=set,value=action.shadow_bolt.execute_time*azerite.cascading_calamity.enabled
actions+=/variable,name=padding,op=reset,value=gcd,if=azerite.cascading_calamity.enabled&(talent.drain_soul.enabled|talent.deathbolt.enabled&cooldown.deathbolt.remains<=gcd)
actions+=/variable,name=maintain_se,value=spell_targets.seed_of_corruption_aoe<=1+talent.writhe_in_agony.enabled+talent.absolute_corruption.enabled*2+(talent.writhe_in_agony.enabled&talent.sow_the_seeds.enabled&spell_targets.seed_of_corruption_aoe>2)+(talent.siphon_life.enabled&!talent.creeping_death.enabled&!talent.drain_soul.enabled)+raid_event.invulnerable.up
actions+=/call_action_list,name=cooldowns
actions+=/drain_soul,interrupt_global=1,chain=1,cycle_targets=1,if=target.time_to_die<=gcd&soul_shard<5
actions+=/unstable_affliction,if=azerite.cascading_calamity.enabled&contagion>cast_time&buff.cascading_calamity.remains<cast_time
actions+=/haunt,if=spell_targets.seed_of_corruption_aoe<=2+raid_event.invulnerable.up
actions+=/summon_darkglare,if=dot.agony.ticking&dot.corruption.ticking&(buff.active_uas.stack=5|soul_shard=0)&(!talent.phantom_singularity.enabled|dot.phantom_singularity.remains)&(!talent.deathbolt.enabled|cooldown.deathbolt.remains<=gcd|!cooldown.deathbolt.remains|spell_targets.seed_of_corruption_aoe>1+raid_event.invulnerable.up)
actions+=/deathbolt,if=cooldown.summon_darkglare.remains&spell_targets.seed_of_corruption_aoe=1+raid_event.invulnerable.up&(!essence.vision_of_perfection.minor&!azerite.dreadful_calling.rank|cooldown.summon_darkglare.remains>30)
actions+=/the_unbound_force,if=buff.reckless_force.remains
actions+=/agony,target_if=min:dot.agony.remains,if=remains<=gcd+action.shadow_bolt.execute_time&target.time_to_die>8
actions+=/memory_of_lucid_dreams,if=time<30
# Temporary fix to make sure azshara's font doesn't break darkglare usage.
actions+=/agony,line_cd=30,if=time>30&cooldown.summon_darkglare.remains<=15&equipped.169314
actions+=/corruption,line_cd=30,if=time>30&cooldown.summon_darkglare.remains<=15&equipped.169314&!talent.absolute_corruption.enabled&(talent.siphon_life.enabled|spell_targets.seed_of_corruption_aoe>1&spell_targets.seed_of_corruption_aoe<=3)
actions+=/siphon_life,line_cd=30,if=time>30&cooldown.summon_darkglare.remains<=15&equipped.169314
actions+=/unstable_affliction,target_if=!contagion&target.time_to_die<=8
actions+=/drain_soul,target_if=min:debuff.shadow_embrace.remains,cancel_if=ticks_remain<5,if=talent.shadow_embrace.enabled&variable.maintain_se&debuff.shadow_embrace.remains&debuff.shadow_embrace.remains<=gcd*2
actions+=/shadow_bolt,target_if=min:debuff.shadow_embrace.remains,if=talent.shadow_embrace.enabled&variable.maintain_se&debuff.shadow_embrace.remains&debuff.shadow_embrace.remains<=execute_time*2+travel_time&!action.shadow_bolt.in_flight
actions+=/phantom_singularity,target_if=max:target.time_to_die,if=time>35&target.time_to_die>16*spell_haste&(!essence.vision_of_perfection.minor&!azerite.dreadful_calling.rank|cooldown.summon_darkglare.remains>45+soul_shard*azerite.dreadful_calling.rank|cooldown.summon_darkglare.remains<15*spell_haste+soul_shard*azerite.dreadful_calling.rank)
actions+=/unstable_affliction,target_if=min:contagion,if=!variable.use_seed&soul_shard=5
actions+=/seed_of_corruption,if=variable.use_seed&soul_shard=5
actions+=/call_action_list,name=dots
actions+=/vile_taint,target_if=max:target.time_to_die,if=time>15&target.time_to_die>=10&(cooldown.summon_darkglare.remains>30|cooldown.summon_darkglare.remains<10&dot.agony.remains>=10&dot.corruption.remains>=10&(dot.siphon_life.remains>=10|!talent.siphon_life.enabled))
actions+=/use_item,name=azsharas_font_of_power,if=time<=3
actions+=/phantom_singularity,if=time<=35
actions+=/vile_taint,if=time<15
actions+=/guardian_of_azeroth,if=(cooldown.summon_darkglare.remains<15+soul_shard*azerite.dreadful_calling.enabled|(azerite.dreadful_calling.rank|essence.vision_of_perfection.rank)&time>30&target.time_to_die>=210)&(dot.phantom_singularity.remains|dot.vile_taint.remains|!talent.phantom_singularity.enabled&!talent.vile_taint.enabled)|target.time_to_die<30+gcd
actions+=/dark_soul,if=cooldown.summon_darkglare.remains<15+soul_shard*azerite.dreadful_calling.enabled&(dot.phantom_singularity.remains|dot.vile_taint.remains)
actions+=/berserking
actions+=/call_action_list,name=spenders
actions+=/call_action_list,name=fillers
]]
	local apl
	if CascadingCalamity.known and (DrainSoul.known or (Deathbolt.known and Deathbolt:Cooldown() <= Player.gcd)) then
		Player.ua_padding = Player.gcd
	else
		Player.ua_padding = ShadowBolt:CastTime() * (CascadingCalamity.known and 1 or 0)
	end
	Player.maintain_se = (Player.enemies <= 1 and 1 or 0) + (WritheInAgony.known and 1 or 0) + (AbsoluteCorruption.known and 2 or 0) + (WritheInAgony.known and SowTheSeeds.known and Player.enemies > 2 and 1 or 0) + (SiphonLife.known and not CreepingDeath.known and not DrainSoul.known and 1 or 0)
	if Player.use_cds then
		self:cooldowns()
	end
	if Opt.trinket and Trinket.ShiverVenomRelic:Usable() then
		if ShiverVenom:Stack() == 5 or (ShiverVenom:Stack() >= 3 and (Target.timeToDie < 2 or ShiverVenom:Remains() < 2)) then
			UseCooldown(Trinket.ShiverVenomRelic)
		end
	end
	if DrainSoul:Usable() and Target.timeToDie <= Player.gcd and Player.soul_shards < 5 then
		return DrainSoul
	end
	if CascadingCalamity.known and UnstableAffliction:Usable() and Player.ua_remains > Player.ua_ct and CascadingCalamity:Remains() < ShadowBolt:CastTime() then
		return UnstableAffliction
	end
	if Haunt:Usable() and Player.enemies <= 2 then
		return Haunt
	end
	if Player.use_cds and SummonDarkglare:Usable() and Agony:Up() and Corruption:Up() and (Player.ua_stack == 5 or Player.soul_shards == 0) and (not PhantomSingularity.known or PhantomSingularity:Up()) and (not Deathbolt.known or Deathbolt:Cooldown() <= Player.gcd or Player.enemies > 1) then
		UseCooldown(SummonDarkglare)
	end
	if Deathbolt:Usable() and Player.use_db and Player.enemies == 1 and not SummonDarkglare:Ready() and (not StriveForPerfection.known or not DreadfulCalling.known or SummonDarkglare:Cooldown() > 30) then
		return Deathbolt
	end
	if TheUnboundForce:Usable() and RecklessForce:Up() then
		return TheUnboundForce
	end
	if Agony:Usable() and Agony:Remains() <= Player.gcd + ShadowBolt:CastTime() and Target.timeToDie > 8 then
		return Agony
	end
	if Player.use_cds and MemoryOfLucidDreams:Usable() and Player:TimeInCombat() < 30 then
		UseCooldown(MemoryOfLucidDreams)
	end
	if UnstableAffliction:Usable() and Target.timeToDie <= 8 and Player.ua_stack < 5 then
		return UnstableAffliction
	end
	if ShadowEmbrace.known and Player.maintain_se and ShadowEmbrace:Up() then
		if DrainSoul:Usable() and ShadowEmbrace:Remains() <= (Player.gcd * 2) then
			return DrainSoul
		end
		if ShadowBolt:Usable() and ShadowEmbrace:Remains() <= (ShadowBolt:CastTime() * 2 + ShadowBolt:TravelTime()) and not ShadowBolt:Traveling() then
			return DrainSoul
		end
	end
	if PhantomSingularity:Usable() and Player:TimeInCombat() > 35 and Target.timeToDie > (16 * Player.haste_factor) and (not StriveForPerfection.known and not DreadfulCalling.known or SummonDarkglare:Cooldown() > (45 * Player.haste_factor + (DreadfulCalling.known and Player.soul_shards or 0)) or SummonDarkglare:Cooldown() < (15 * Player.haste_factor + (DreadfulCalling.known and Player.soul_shards or 0))) then
		UseCooldown(PhantomSingularity)
	end
	if Player.soul_shards == 5 then
		if Player.use_seed then
			if SeedOfCorruption:Usable() then
				return SeedOfCorruption
			end
		else
			if UnstableAffliction:Usable() then
				return UnstableAffliction
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
	if GuardianOfAzeroth:Usable() and ((SummonDarkglare:Ready(15 + (DreadfulCalling.known and Player.soul_shards or 0))) or (((DreadfulCalling.known or StriveForPerfection.known) and Player:TimeInCombat() > 30 and Target.timeToDie >= 210) and (PhantomSingularity:Up() or VileTaint:Up() or (not PhantomSingularity.known and not VileTaint.known))) or Target.timeToDie < (30 + Player.gcd)) then
		UseCooldown(GuardianOfAzeroth)
	end
	if Player.use_cds and DarkSoulMisery:Usable() and SummonDarkglare:Cooldown() < (15 + (DreadfulCalling.known and Player.soul_shards or 0)) and (PhantomSingularity:Up() or VileTaint:Up()) then
		UseCooldown(DarkSoulMisery)
	end
	apl = self:spenders()
	if apl then return apl end
	apl = self:fillers()
	if apl then return apl end
end

APL[SPEC.AFFLICTION].cooldowns = function(self)
--[[
actions.cooldowns=use_item,name=azsharas_font_of_power,if=(!talent.phantom_singularity.enabled|cooldown.phantom_singularity.remains<4*spell_haste|!cooldown.phantom_singularity.remains)&cooldown.summon_darkglare.remains<19*spell_haste+soul_shard*azerite.dreadful_calling.rank&dot.agony.remains&dot.corruption.remains&(dot.siphon_life.remains|!talent.siphon_life.enabled)
actions.cooldowns+=/potion,if=(talent.dark_soul_misery.enabled&cooldown.summon_darkglare.up&cooldown.dark_soul.up)|cooldown.summon_darkglare.up|target.time_to_die<30
actions.cooldowns+=/use_items,if=cooldown.summon_darkglare.remains>70|time_to_die<20|((buff.active_uas.stack=5|soul_shard=0)&(!talent.phantom_singularity.enabled|cooldown.phantom_singularity.remains)&(!talent.deathbolt.enabled|cooldown.deathbolt.remains<=gcd|!cooldown.deathbolt.remains)&!cooldown.summon_darkglare.remains)
actions.cooldowns+=/fireblood,if=!cooldown.summon_darkglare.up
actions.cooldowns+=/blood_fury,if=!cooldown.summon_darkglare.up
actions.cooldowns+=/memory_of_lucid_dreams,if=time>30
actions.cooldowns+=/dark_soul,if=target.time_to_die<20+gcd|spell_targets.seed_of_corruption_aoe>1+raid_event.invulnerable.up|talent.sow_the_seeds.enabled&cooldown.summon_darkglare.remains>=cooldown.summon_darkglare.duration-10
actions.cooldowns+=/blood_of_the_enemy,if=pet.darkglare.remains|(!cooldown.deathbolt.remains|!talent.deathbolt.enabled)&cooldown.summon_darkglare.remains>=80&essence.blood_of_the_enemy.rank>1
# Use damaging on-use trinkets more or less on cooldown, so long as the ICD they incur won't effect any other trinkets usage during cooldowns.
actions.cooldowns+=/use_item,name=pocketsized_computation_device,if=(cooldown.summon_darkglare.remains>=25|target.time_to_die<=30)&(cooldown.deathbolt.remains|!talent.deathbolt.enabled)
actions.cooldowns+=/use_item,name=rotcrusted_voodoo_doll,if=(cooldown.summon_darkglare.remains>=25|target.time_to_die<=30)&(cooldown.deathbolt.remains|!talent.deathbolt.enabled)
actions.cooldowns+=/use_item,name=shiver_venom_relic,if=(cooldown.summon_darkglare.remains>=25|target.time_to_die<=30)&(cooldown.deathbolt.remains|!talent.deathbolt.enabled)
actions.cooldowns+=/use_item,name=aquipotent_nautilus,if=(cooldown.summon_darkglare.remains>=25|target.time_to_die<=30)&(cooldown.deathbolt.remains|!talent.deathbolt.enabled)
actions.cooldowns+=/use_item,name=tidestorm_codex,if=(cooldown.summon_darkglare.remains>=25|target.time_to_die<=30)&(cooldown.deathbolt.remains|!talent.deathbolt.enabled)
actions.cooldowns+=/use_item,name=vial_of_storms,if=(cooldown.summon_darkglare.remains>=25|target.time_to_die<=30)&(cooldown.deathbolt.remains|!talent.deathbolt.enabled)
actions.cooldowns+=/worldvein_resonance,if=buff.lifeblood.stack<3
actions.cooldowns+=/ripple_in_space
]]
	if Opt.pot and Target.boss and not Player:InArenaOrBattleground() then
		if PotionOfUnbridledFury:Usable() and (Target.timeToDie < 30 or Pet.Darkglare:Up() and (not DarkSoulMisery.known or DarkSoulMisery:Up())) then
			return UseCooldown(PotionOfUnbridledFury)
		end
	end
	if Opt.trinket and (not DarkSoulMisery.known or not DarkSoulMisery:Ready()) and (SummonDarkglare:Cooldown() > 70 or Target.timeToDie < 20 or ((Player.ua_stack == 5 or Player.soul_shards == 0) and (not PhantomSingularity.known or PhantomSingularity:Up()) and (not Deathbolt.known or not Deathbolt:Ready(Player.gcd)) and (SummonDarkglare:Ready() or Pet.Darkglare:Up()))) then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
	if MemoryOfLucidDreams:Usable() and Player:TimeInCombat() > 30 then
		return UseCooldown(MemoryOfLucidDreams)
	end
	if DarkSoulMisery:Usable() and (Target.timeToDie < 20 + Player.gcd or Player.enemies > 1 or (SowTheSeeds.known and SummonDarkglare:Cooldown() >= 170)) then
		return UseCooldown(DarkSoulMisery)
	end
	if BloodOfTheEnemy:Usable() and (Pet.Darkglare:Up() or (not Deathbolt.known or Deathbolt:Ready()) and not SummonDarkglare:Ready(80)) then
		return UseCooldown(BloodOfTheEnemy)
	end
	if WorldveinResonance:Usable() and Lifeblood:Stack() < 3 then
		return UseCooldown(WorldveinResonance)
	end
	if RippleInSpace:Usable() then
		return UseCooldown(RippleInSpace)
	end
end

APL[SPEC.AFFLICTION].db_refresh = function(self)
--[[
actions.db_refresh=siphon_life,line_cd=15,if=(dot.siphon_life.remains%dot.siphon_life.duration)<=(dot.agony.remains%dot.agony.duration)&(dot.siphon_life.remains%dot.siphon_life.duration)<=(dot.corruption.remains%dot.corruption.duration)&dot.siphon_life.remains<dot.siphon_life.duration*1.3
actions.db_refresh+=/agony,line_cd=15,if=(dot.agony.remains%dot.agony.duration)<=(dot.corruption.remains%dot.corruption.duration)&(dot.agony.remains%dot.agony.duration)<=(dot.siphon_life.remains%dot.siphon_life.duration)&dot.agony.remains<dot.agony.duration*1.3
actions.db_refresh+=/corruption,line_cd=15,if=(dot.corruption.remains%dot.corruption.duration)<=(dot.agony.remains%dot.agony.duration)&(dot.corruption.remains%dot.corruption.duration)<=(dot.siphon_life.remains%dot.siphon_life.duration)&dot.corruption.remains<dot.corruption.duration*1.3
]]
	local siphon_rd = SiphonLife.known and (SiphonLife:Remains() / SiphonLife:Duration()) or 1.3
	local agony_rd = Agony:Remains() / Agony:Duration()
	local corruption_rd = Corruption:Remains() / Corruption:Duration()
	if SiphonLife:Usable() and siphon_rd < 0.8 and siphon_rd <= agony_rd and siphon_rd <= corruption_rd then
		return SiphonLife
	end
	if Agony:Usable() and agony_rd < 0.8 and agony_rd <= corruption_rd and agony_rd <= siphon_rd then
		return Agony
	end
	if Corruption:Usable() and corruption_rd < 0.8 and corruption_rd <= agony_rd and corruption_rd <= siphon_rd then
		return Corruption
	end
end

APL[SPEC.AFFLICTION].dots = function(self)
--[[
actions.dots=seed_of_corruption,if=dot.corruption.remains<=action.seed_of_corruption.cast_time+time_to_shard+4.2*(1-talent.creeping_death.enabled*0.15)&spell_targets.seed_of_corruption_aoe>=3+raid_event.invulnerable.up+talent.writhe_in_agony.enabled&!dot.seed_of_corruption.remains&!action.seed_of_corruption.in_flight
actions.dots+=/agony,target_if=min:remains,if=talent.creeping_death.enabled&active_dot.agony<6&target.time_to_die>10&(remains<=gcd|cooldown.summon_darkglare.remains>10&(remains<5|!azerite.pandemic_invocation.rank&refreshable))
actions.dots+=/agony,target_if=min:remains,if=!talent.creeping_death.enabled&active_dot.agony<8&target.time_to_die>10&(remains<=gcd|cooldown.summon_darkglare.remains>10&(remains<5|!azerite.pandemic_invocation.rank&refreshable))
actions.dots+=/siphon_life,target_if=min:remains,if=(active_dot.siphon_life<8-talent.creeping_death.enabled-spell_targets.sow_the_seeds_aoe)&target.time_to_die>10&refreshable&(!remains&spell_targets.seed_of_corruption_aoe=1|cooldown.summon_darkglare.remains>soul_shard*action.unstable_affliction.execute_time)
actions.dots+=/corruption,cycle_targets=1,if=spell_targets.seed_of_corruption_aoe<3+raid_event.invulnerable.up+talent.writhe_in_agony.enabled&(remains<=gcd|cooldown.summon_darkglare.remains>10&refreshable)&target.time_to_die>10
]]
	if Player.enemies >= 3 and SeedOfCorruption:Usable() and Corruption:Remains() < (SeedOfCorruption:CastTime() + (Corruption:Duration() * 0.3)) and not (SeedOfCorruption:Up() or SeedOfCorruption:Ticking() > 0) then
		return SeedOfCorruption
	end
	if Agony:Usable() and (Agony:Ticking() < (CreepingDeath.known and 6 or 8) and Target.timeToDie > 10 and (Agony:Remains() <= Player.gcd or SummonDarkglare:Cooldown() > 10 and (Agony:Remains() < 5 or not PandemicInvocation.known and Agony:Refreshable()))) then
		return Agony
	end
	if SiphonLife:Usable() and (SiphonLife:Ticking() < (8 - (CreepingDeath.known and 1 or 0) - Player.enemies)) and Target.timeToDie > 10 and SiphonLife:Refreshable() and (SiphonLife:Down() and Player.enemies == 1 or SummonDarkglare:Cooldown() > (Player.soul_shards * Player.ua_ct)) then
		return SiphonLife
	end
	if Corruption:Usable() and Player.enemies < (3 + (WritheInAgony.known and 1 or 0)) and (Corruption:Remains() <= Player.gcd or SummonDarkglare:Cooldown() > 10 and Corruption:Refreshable()) and Target.timeToDie > 10 then
		return Corruption
	end
end

APL[SPEC.AFFLICTION].fillers = function(self)
--[[
actions.fillers=unstable_affliction,line_cd=15,if=cooldown.deathbolt.remains<=gcd*2&spell_targets.seed_of_corruption_aoe=1+raid_event.invulnerable.up&cooldown.summon_darkglare.remains>20
actions.fillers+=/call_action_list,name=db_refresh,if=talent.deathbolt.enabled&spell_targets.seed_of_corruption_aoe=1+raid_event.invulnerable.up&(dot.agony.remains<dot.agony.duration*0.75|dot.corruption.remains<dot.corruption.duration*0.75|dot.siphon_life.remains<dot.siphon_life.duration*0.75)&cooldown.deathbolt.remains<=action.agony.gcd*4&cooldown.summon_darkglare.remains>20
actions.fillers+=/call_action_list,name=db_refresh,if=talent.deathbolt.enabled&spell_targets.seed_of_corruption_aoe=1+raid_event.invulnerable.up&cooldown.summon_darkglare.remains<=soul_shard*action.agony.gcd+action.agony.gcd*3&(dot.agony.remains<dot.agony.duration*1|dot.corruption.remains<dot.corruption.duration*1|dot.siphon_life.remains<dot.siphon_life.duration*1)
actions.fillers+=/deathbolt,if=cooldown.summon_darkglare.remains>=30+gcd|cooldown.summon_darkglare.remains>140
actions.fillers+=/shadow_bolt,if=buff.movement.up&buff.nightfall.remains
actions.fillers+=/agony,if=buff.movement.up&!(talent.siphon_life.enabled&(prev_gcd.1.agony&prev_gcd.2.agony&prev_gcd.3.agony)|prev_gcd.1.agony)
actions.fillers+=/siphon_life,if=buff.movement.up&!(prev_gcd.1.siphon_life&prev_gcd.2.siphon_life&prev_gcd.3.siphon_life)
actions.fillers+=/corruption,if=buff.movement.up&!prev_gcd.1.corruption&!talent.absolute_corruption.enabled
actions.fillers+=/drain_life,if=buff.inevitable_demise.stack>10&target.time_to_die<=10
actions.fillers+=/drain_life,if=talent.siphon_life.enabled&buff.inevitable_demise.stack>=50-20*(spell_targets.seed_of_corruption_aoe-raid_event.invulnerable.up>=2)&dot.agony.remains>5*spell_haste&dot.corruption.remains>gcd&(dot.siphon_life.remains>gcd|!talent.siphon_life.enabled)&(debuff.haunt.remains>5*spell_haste|!talent.haunt.enabled)&contagion>5*spell_haste
actions.fillers+=/drain_life,if=talent.writhe_in_agony.enabled&buff.inevitable_demise.stack>=50-20*(spell_targets.seed_of_corruption_aoe-raid_event.invulnerable.up>=3)-5*(spell_targets.seed_of_corruption_aoe-raid_event.invulnerable.up=2)&dot.agony.remains>5*spell_haste&dot.corruption.remains>gcd&(debuff.haunt.remains>5*spell_haste|!talent.haunt.enabled)&contagion>5*spell_haste
actions.fillers+=/drain_life,if=talent.absolute_corruption.enabled&buff.inevitable_demise.stack>=50-20*(spell_targets.seed_of_corruption_aoe-raid_event.invulnerable.up>=4)&dot.agony.remains>5*spell_haste&(debuff.haunt.remains>5*spell_haste|!talent.haunt.enabled)&contagion>5*spell_haste
actions.fillers+=/haunt
actions.fillers+=/focused_azerite_beam,if=!talent.haunt.enabled|cooldown.haunt.remains>4.5*spell_haste
actions.fillers+=/purifying_blast
actions.fillers+=/reaping_flames
actions.fillers+=/concentrated_flame,if=!dot.concentrated_flame_burn.remains&!action.concentrated_flame.in_flight
actions.fillers+=/drain_soul,interrupt_global=1,chain=1,interrupt=1,cycle_targets=1,if=target.time_to_die<=gcd
actions.fillers+=/drain_soul,target_if=min:debuff.shadow_embrace.remains,chain=1,interrupt_if=ticks_remain<5,interrupt_global=1,if=talent.shadow_embrace.enabled&variable.maintain_se&!debuff.shadow_embrace.remains
actions.fillers+=/drain_soul,target_if=min:debuff.shadow_embrace.remains,chain=1,interrupt_if=ticks_remain<5,interrupt_global=1,if=talent.shadow_embrace.enabled&variable.maintain_se
actions.fillers+=/drain_soul,interrupt_global=1,chain=1,interrupt=1
actions.fillers+=/shadow_bolt,cycle_targets=1,if=talent.shadow_embrace.enabled&variable.maintain_se&!debuff.shadow_embrace.remains&!action.shadow_bolt.in_flight
actions.fillers+=/shadow_bolt,target_if=min:debuff.shadow_embrace.remains,if=talent.shadow_embrace.enabled&variable.maintain_se
actions.fillers+=/shadow_bolt
]]
	local apl
	if Deathbolt.known and Deathbolt:Ready(Player.gcd * 4) and Player.enemies < 3 and SummonDarkglare:Cooldown() >= (30 + Player.gcd + Deathbolt:Cooldown()) then
		if UnstableAffliction:Usable() and not UnstableAffliction:Previous() and Deathbolt:Cooldown() <= Player.ua_ct and Player.ua_stack < 5 then
			return UnstableAffliction
		end
		if not Deathbolt:Ready() or Player.ua_stack <= 1 then
			apl = self:db_refresh()
			if apl then return apl end
		end
	end
	if Deathbolt:Usable() and Player.use_db and (Target.timeToDie < 10 or SummonDarkglare:Cooldown() >= (30 + Player.gcd)) then
		return Deathbolt
	end
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
		if InevitableDemise:Stack() >= min(max(60 - Agony:Ticking() * 10, 30), 50) and Agony:Remains() > (5 * Player.haste_factor) and Corruption:Remains() > (5 * Player.haste_factor) and (not SiphonLife.known or SiphonLife:Remains() > (5 * Player.haste_factor)) and (not Haunt.known or Haunt:Remains() > (5 * Player.haste_factor)) and Player.ua_remains > (5 * Player.haste_factor) then
			return DrainLife
		end
	end
	if Haunt:Usable() then
		return Haunt
	end
	if FocusedAzeriteBeam:Usable() and not Player.moving and (not Haunt.known or Haunt:Cooldown() > (4.5 * Player.haste_factor)) then
		UseCooldown(FocusedAzeriteBeam)
	end
	if PurifyingBlast:Usable() then
		UseCooldown(PurifyingBlast)
	end
	if ReapingFlames:Usable() then
		UseCooldown(ReapingFlames)
	end
	if ConcentratedFlame:Usable() and ConcentratedFlame.dot:Down() then
		return ConcentratedFlame
	end
	if DrainLife:Usable() then
		if (Player:ManaPct() > 5 and Player:HealthPct() < 20) or (Player:ManaPct() > 20 and Player:HealthPct() < 40) then
			return DrainLife
		end
		if RotAndDecay.known and Player:ManaPct() > (120 - (Player.ua_stack * 20)) then
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
actions.spenders=unstable_affliction,if=cooldown.summon_darkglare.remains<=soul_shard*(execute_time+azerite.dreadful_calling.rank)&(!talent.deathbolt.enabled|cooldown.deathbolt.remains<=soul_shard*execute_time)&(talent.sow_the_seeds.enabled|dot.phantom_singularity.remains|dot.vile_taint.remains)
actions.spenders+=/call_action_list,name=fillers,if=(cooldown.summon_darkglare.remains<time_to_shard*(5-soul_shard)|cooldown.summon_darkglare.up)&time_to_die>cooldown.summon_darkglare.remains
actions.spenders+=/seed_of_corruption,if=variable.use_seed
actions.spenders+=/unstable_affliction,if=!variable.use_seed&!prev_gcd.1.summon_darkglare&(talent.deathbolt.enabled&cooldown.deathbolt.remains<=execute_time&!azerite.cascading_calamity.enabled|(soul_shard>=5&spell_targets.seed_of_corruption_aoe<2|soul_shard>=2&spell_targets.seed_of_corruption_aoe>=2)&target.time_to_die>4+execute_time&spell_targets.seed_of_corruption_aoe=1|target.time_to_die<=8+execute_time*soul_shard)
actions.spenders+=/unstable_affliction,if=!variable.use_seed&contagion<=cast_time+variable.padding
actions.spenders+=/unstable_affliction,cycle_targets=1,if=!variable.use_seed&(!talent.deathbolt.enabled|cooldown.deathbolt.remains>time_to_shard|soul_shard>1)&(!talent.vile_taint.enabled|soul_shard>1)&contagion<=cast_time+variable.padding&(!azerite.cascading_calamity.enabled|buff.cascading_calamity.remains>time_to_shard)
]]
	if UnstableAffliction:Usable() and Player.ua_stack < 5 and SummonDarkglare:Cooldown() <= (Player.soul_shards * (Player.ua_ct + DreadfulCalling:AzeriteRank())) and (not Deathbolt.known or Deathbolt:Cooldown() <= (Player.soul_shards * Player.ua_ct)) and (SowTheSeeds.known or PhantomSingularity:Remains() or VileTaint:Remains()) then
		return UnstableAffliction
	end
	if (SummonDarkglare:Ready(5 - Player.soul_shards) or Player.darkglare_remains > 0) and Target.timeToDie > SummonDarkglare:Cooldown() then
		local apl = self:fillers()
		if apl then return apl end
	end
	if Player.use_seed then
		if SeedOfCorruption:Usable() then
			return SeedOfCorruption
		end
	elseif UnstableAffliction:Usable() then
		if Player.ua_stack < 5 and not SummonDarkglare:Previous() and (Deathbolt.known and Deathbolt:Cooldown() <= Player.ua_ct and not CascadingCalamity.known or (Player.soul_shards >= 5 and Player.enemies < 2 or Player.soul_shards >= 2 and Player.enemies >= 2) and Target.timeToDie > (4 + Player.ua_ct) and Player.enemies  == 1 or Target.timeToDie <= (8 + Player.ua_ct * Player.soul_shards)) then
			return UnstableAffliction
		end
		if Player.ua_remains <= (Player.ua_ct + Player.ua_padding) then
			return UnstableAffliction
		end
		if (not Deathbolt.known or Player.soul_shards > 1) and (not VileTaint.known or Player.soul_shards > 1) and Player.ua_remains <= (Player.ua_ct + Player.ua_padding) and not CascadingCalamity.known then
			return UnstableAffliction
		end
		if Player.soul_shards >= 4 and Agony:Ticking() >= 2 then
			return UnstableAffliction
		end
	end
end

APL[SPEC.DEMONOLOGY].main = function(self)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/summon_pet
actions.precombat+=/inner_demons,if=talent.inner_demons.enabled
actions.precombat+=/snapshot_stats
actions.precombat+=/potion
actions.precombat+=/demonbolt
]]
		if Opt.healthstone and Healthstone:Charges() == 0 and CreateHealthstone:Usable() then
			return CreateHealthstone
		end
		if not Player.pet_active then
			if SummonFelguard:Usable() then
				return SummonFelguard
			elseif SummonWrathguard:Usable() then
				return SummonWrathguard
			end
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfEndlessFathoms:Usable() and GreaterFlaskOfEndlessFathoms.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfEndlessFathoms)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
		if Player.soul_shards < 5 and Player.imp_count < 6 and not (Demonbolt:Casting() or ShadowBoltDemo:Casting()) then
			if Demonbolt:Usable() and (Target.boss or DemonicCore:Up()) and (Player.soul_shards <= 3 or DemonicCore:Up() and DemonicCore:Remains() < (ShadowBoltDemo:CastTime() * 2)) then
				return Demonbolt
			end
			if ShadowBoltDemo:Usable() then
				return ShadowBoltDemo
			end
		end
	else
		if not Player.pet_active then
			if SummonFelguard:Usable() then
				UseExtra(SummonFelguard)
			elseif SummonWrathguard:Usable() then
				UseExtra(SummonWrathguard)
			end
		end
	end
--[[
actions=potion,if=pet.demonic_tyrant.active&(!essence.vision_of_perfection.major|!talent.demonic_consumption.enabled|cooldown.summon_demonic_tyrant.remains>=cooldown.summon_demonic_tyrant.duration-5)&(!talent.nether_portal.enabled|cooldown.nether_portal.remains>160)|target.time_to_die<30
actions+=/use_item,name=azsharas_font_of_power,if=cooldown.summon_demonic_tyrant.remains<=20&!talent.nether_portal.enabled
actions+=/use_items,if=pet.demonic_tyrant.active&(!essence.vision_of_perfection.major|!talent.demonic_consumption.enabled|cooldown.summon_demonic_tyrant.remains>=cooldown.summon_demonic_tyrant.duration-5)|target.time_to_die<=15
actions+=/berserking,if=pet.demonic_tyrant.active&(!essence.vision_of_perfection.major|!talent.demonic_consumption.enabled|cooldown.summon_demonic_tyrant.remains>=cooldown.summon_demonic_tyrant.duration-5)|target.time_to_die<=15
actions+=/blood_fury,if=pet.demonic_tyrant.active&(!essence.vision_of_perfection.major|!talent.demonic_consumption.enabled|cooldown.summon_demonic_tyrant.remains>=cooldown.summon_demonic_tyrant.duration-5)|target.time_to_die<=15
actions+=/fireblood,if=pet.demonic_tyrant.active&(!essence.vision_of_perfection.major|!talent.demonic_consumption.enabled|cooldown.summon_demonic_tyrant.remains>=cooldown.summon_demonic_tyrant.duration-5)|target.time_to_die<=15
actions+=/blood_of_the_enemy,if=pet.demonic_tyrant.active&pet.demonic_tyrant.remains<=15-gcd*3&(!essence.vision_of_perfection.major|!talent.demonic_consumption.enabled|cooldown.summon_demonic_tyrant.remains>=cooldown.summon_demonic_tyrant.duration-5)
actions+=/ripple_in_space,if=pet.demonic_tyrant.active&(!essence.vision_of_perfection.major|!talent.demonic_consumption.enabled|cooldown.summon_demonic_tyrant.remains>=cooldown.summon_demonic_tyrant.duration-5)|target.time_to_die<=15
actions+=/worldvein_resonance,if=buff.lifeblood.stack<3&(pet.demonic_tyrant.active&(!essence.vision_of_perfection.major|!talent.demonic_consumption.enabled|cooldown.summon_demonic_tyrant.remains>=cooldown.summon_demonic_tyrant.duration-5)|target.time_to_die<=15)
actions+=/use_item,name=pocketsized_computation_device,if=cooldown.summon_demonic_tyrant.remains>=20&cooldown.summon_demonic_tyrant.remains<=cooldown.summon_demonic_tyrant.duration-15|target.time_to_die<=30
actions+=/use_item,name=rotcrusted_voodoo_doll,if=(cooldown.summon_demonic_tyrant.remains>=25|target.time_to_die<=30)
actions+=/use_item,name=shiver_venom_relic,if=(cooldown.summon_demonic_tyrant.remains>=25|target.time_to_die<=30)
actions+=/use_item,name=aquipotent_nautilus,if=(cooldown.summon_demonic_tyrant.remains>=25|target.time_to_die<=30)
actions+=/use_item,name=tidestorm_codex,if=(cooldown.summon_demonic_tyrant.remains>=25|target.time_to_die<=30)
actions+=/use_item,name=vial_of_storms,if=(cooldown.summon_demonic_tyrant.remains>=25|target.time_to_die<=30)
actions+=/call_action_list,name=dcon_prep,if=talent.demonic_consumption.enabled&cooldown.summon_demonic_tyrant.remains<5
actions+=/call_action_list,name=tyrant_active,if=pet.demonic_tyrant.active
actions+=/hand_of_guldan,if=azerite.explosive_potential.rank&time<5&soul_shard>=3&buff.explosive_potential.down&buff.wild_imps.stack<3&!prev_gcd.1.hand_of_guldan&!prev_gcd.2.hand_of_guldan
actions+=/demonbolt,if=soul_shard<=3&buff.demonic_core.up&buff.demonic_core.stack=4
actions+=/demonbolt,if=soul_shard<=4&buff.demonic_core.up&buff.demonic_core.remains<(gcd*buff.demonic_core.stack)
actions+=/implosion,if=azerite.explosive_potential.rank&buff.wild_imps.stack>=3&buff.explosive_potential.remains<action.shadow_bolt.execute_time&(!talent.demonic_consumption.enabled|cooldown.summon_demonic_tyrant.remains>12)
actions+=/doom,if=!ticking&time_to_die>30&spell_targets.implosion<2
actions+=/bilescourge_bombers,if=azerite.explosive_potential.rank>0&time<10&spell_targets.implosion<2&buff.dreadstalkers.remains&talent.nether_portal.enabled
actions+=/demonic_strength,if=(buff.wild_imps.stack<6|buff.demonic_power.up)|spell_targets.implosion<2
actions+=/call_action_list,name=nether_portal,if=talent.nether_portal.enabled&spell_targets.implosion<=2
actions+=/call_action_list,name=implosion,if=spell_targets.implosion>1
actions+=/guardian_of_azeroth,if=cooldown.summon_demonic_tyrant.remains<=15|target.time_to_die<=30
actions+=/grimoire_felguard,if=(target.time_to_die>120|target.time_to_die<cooldown.summon_demonic_tyrant.remains+15|cooldown.summon_demonic_tyrant.remains<13)
actions+=/summon_vilefiend,if=cooldown.summon_demonic_tyrant.remains>40|cooldown.summon_demonic_tyrant.remains<12
actions+=/call_dreadstalkers,if=(cooldown.summon_demonic_tyrant.remains<9&buff.demonic_calling.remains)|(cooldown.summon_demonic_tyrant.remains<11&!buff.demonic_calling.remains)|cooldown.summon_demonic_tyrant.remains>14
actions+=/the_unbound_force,if=buff.reckless_force.react
actions+=/bilescourge_bombers
actions+=/hand_of_guldan,if=(azerite.baleful_invocation.enabled|talent.demonic_consumption.enabled)&prev_gcd.1.hand_of_guldan&cooldown.summon_demonic_tyrant.remains<2
actions+=/summon_demonic_tyrant,if=soul_shard<3|target.time_to_die<20
actions+=/power_siphon,if=buff.wild_imps.stack>=2&buff.demonic_core.stack<=2&buff.demonic_power.down&spell_targets.implosion<2
actions+=/doom,if=talent.doom.enabled&refreshable&time_to_die>(dot.doom.remains+30)
actions+=/hand_of_guldan,if=soul_shard>=5
actions+=/hand_of_guldan,if=(soul_shard>=4|soul_shard>=3&talent.soul_conduit.enabled)&buff.memory_of_lucid_dreams.remains>cast_time
actions+=/hand_of_guldan,if=soul_shard>=3&(buff.demonic_core.stack>=3|cooldown.call_dreadstalkers.remains>4&(cooldown.summon_demonic_tyrant.remains>20|cooldown.summon_demonic_tyrant.remains<gcd*4)&(!talent.summon_vilefiend.enabled|cooldown.summon_vilefiend.remains>3))
actions+=/soul_strike,if=soul_shard<5&buff.demonic_core.stack<=2
actions+=/demonbolt,if=soul_shard<=3&buff.demonic_core.up&((cooldown.summon_demonic_tyrant.remains<6|cooldown.summon_demonic_tyrant.remains>22&!azerite.shadows_bite.enabled)|buff.demonic_core.stack>=3|buff.demonic_core.remains<5|time_to_die<25|buff.shadows_bite.remains)
actions+=/focused_azerite_beam,if=!pet.demonic_tyrant.active&(!azerite.explosive_potential.enabled|buff.explosive_potential.remains>4.5*spell_haste)
actions+=/purifying_blast
actions+=/blood_of_the_enemy
actions+=/concentrated_flame,if=!dot.concentrated_flame_burn.remains&!action.concentrated_flame.in_flight&!pet.demonic_tyrant.active
actions+=/reaping_flames,if=!pet.demonic_tyrant.active
actions+=/call_action_list,name=build_a_shard
]]
	if Target.boss and Target.timeToDie < 30 then
		if Opt.pot and not Player:InArenaOrBattleground() and PotionOfUnbridledFury:Usable() and (not NetherPortal.known or not NetherPortal:Ready(160)) then
			UseCooldown(PotionOfUnbridledFury)
		end
		if Opt.trinket and (Target.timeToDie < 15 or PotionOfUnbridledFury.buff:Up()) then
			if Trinket1:Usable() then
				UseCooldown(Trinket1)
			elseif Trinket2:Usable() then
				UseCooldown(Trinket2)
			end
		end
		if WorldveinResonance:Usable() and Lifeblood:Stack() < 3 then
			UseCooldown(WorldveinResonance)
		end
		if RippleInSpace:Usable() then
			UseCooldown(RippleInSpace)
		end
	end
	if Player.tyrant_remains > 0 and (not VisionOfPerfection.known or not DemonicConsumption.known or SummonDemonicTyrant:Cooldown() >= 85) then
		if Opt.pot and Target.boss and not Player:InArenaOrBattleground() and PotionOfUnbridledFury:Usable() and (not NetherPortal.known or not NetherPortal:Ready(160)) then
			UseCooldown(PotionOfUnbridledFury)
		end
		if Opt.trinket then
			if Trinket1:Usable() then
				UseCooldown(Trinket1)
			elseif Trinket2:Usable() then
				UseCooldown(Trinket2)
			end
		end
		if WorldveinResonance:Usable() and Lifeblood:Stack() < 3 then
			UseCooldown(WorldveinResonance)
		end
		if RippleInSpace:Usable() then
			UseCooldown(RippleInSpace)
		end
	end
	if Opt.trinket and Trinket.ShiverVenomRelic:Usable() then
		if ShiverVenom:Stack() == 5 or (ShiverVenom:Stack() >= 3 and (Target.timeToDie < 2 or ShiverVenom:Remains() < 2)) then
			UseCooldown(Trinket.ShiverVenomRelic)
		end
	end
	if DemonicConsumption.known and SummonDemonicTyrant:Ready(5) then
		local apl = self:dcon_prep()
		if apl then return apl end
	end
	if Player.tyrant_remains > 0 then
		local apl = self:tyrant_active()
		if apl then return apl end
	end
	if ExplosivePotential.known and HandOfGuldan:Usable() and Player:TimeInCombat() < 5 and Player.soul_shards >= 3 and ExplosivePotential:Down() and Player.imp_count < 3 and not (HandOfGuldan:Previous(1) or HandOfGuldan:Previous(2)) then
		return HandOfGuldan
	end
	if Demonbolt:Usable() and Player.soul_shards <= 3 and DemonicCore:Stack() == 4 then
		return Demonbolt
	end
	if Demonbolt:Usable() and Player.soul_shards <= 4 and DemonicCore:Up() and DemonicCore:Remains() < (Player.gcd * DemonicCore:Stack()) then
		return Demonbolt
	end
	if ExplosivePotential.known and Implosion:Usable() and Player.imp_count >= 3 and ExplosivePotential:Remains() < ShadowBoltDemo:CastTime() and (not DemonicConsumption.known or not SummonDemonicTyrant:Ready(12)) then
		return Implosion
	end
	if Doom:Usable() and Player.enemies == 1 and Target.timeToDie > 30 and Doom:Down() then
		return Doom
	end
	if BilescourgeBombers:Usable() and ExplosivePotential.known and NetherPortal.known and Player:TimeInCombat() < 10 and Player.enemies == 1 and Pet.Dreadstalker:Up() then
		UseCooldown(BilescourgeBombers)
	end
	if DemonicStrength:Usable() and (Player.enemies == 1 or DemonicPower:Up() or Player.imp_count < 6) then
		UseCooldown(DemonicStrength)
	end
	if NetherPortal.known and Player.enemies < 3 then
--[[
actions.nether_portal=call_action_list,name=nether_portal_building,if=cooldown.nether_portal.remains<20
actions.nether_portal+=/call_action_list,name=nether_portal_active,if=cooldown.nether_portal.remains>165
]]
		if NetherPortal:Ready(20) then
			local apl = self:nether_portal_building()
			if apl then return apl end
		elseif not NetherPortal:Ready(165) then
			local apl = self:nether_portal_active()
			if apl then return apl end
		end
	end
	if Player.enemies > 1 then
		local apl = self:implosion()
		if apl then return apl end
	end
	if GuardianOfAzeroth:Usable() and (SummonDemonicTyrant:Ready(15) or Target.timeToDie <= 30) then
		UseCooldown(GuardianOfAzeroth)
	end
	if GrimoireFelguard:Usable() and (Target.timeToDie > 120 or Target.timeToDie < (SummonDemonicTyrant:Cooldown() + 15) or SummonDemonicTyrant:Ready(13)) then
		UseCooldown(GrimoireFelguard)
	end
	if SummonVilefiend:Usable() and (SummonDemonicTyrant:Ready(12) or not SummonDemonicTyrant:Ready(40)) then
		UseCooldown(SummonVilefiend)
	end
	if CallDreadstalkers:Usable() and (SummonDemonicTyrant:Ready(DemonicCalling:Up() and 9 or 11) or not SummonDemonicTyrant:Ready(14)) then
		return CallDreadstalkers
	end
	if TheUnboundForce:Usable() and RecklessForce:Up() then
		UseCooldown(TheUnboundForce)
	end
	if BilescourgeBombers:Usable() then
		UseCooldown(BilescourgeBombers)
	end
	if Player.tyrant_remains == 0 and Player.enemies >= 4 then
		if FocusedAzeriteBeam:Usable() and not Player.moving then
			UseCooldown(FocusedAzeriteBeam)
		end
		if PurifyingBlast:Usable() then
			UseCooldown(PurifyingBlast)
		end
	end
	if HandOfGuldan:Usable() and (BalefulInvocation.known or DemonicConsumption.known) and HandOfGuldan:Previous(1) and SummonDemonicTyrant:Ready(2) then
		return HandOfGuldan
	end
	if SummonDemonicTyrant:Usable() and (Player.soul_shards < 3 or Target.timeToDie < 20) then
		UseCooldown(SummonDemonicTyrant)
	end
	if PowerSiphon:Usable() and Player.enemies == 1 and Player.imp_count >= 2 and DemonicCore:Stack() <= 2 and DemonicPower:Down() then
		UseCooldown(PowerSiphon)
	end
	if Doom:Usable() and Doom:Refreshable() and Target.timeToDie > (Doom:Remains() + 30) then
		return Doom
	end
	if Demonbolt:Usable() and Player.soul_shards <= 3 and DemonicCore:Up() and DemonicCore:Remains() <= HandOfGuldan:CastTime() then
		return Demonbolt
	end
	if HandOfGuldan:Usable() and Player.soul_shards >= 3 then
		if Player.soul_shards >= 5 then
			return HandOfGuldan
		end
		if MemoryOfLucidDreams.known and (Player.soul_shards >= 4 or SoulConduit.known) and MemoryOfLucidDreams:Remains() > HandOfGuldan:CastTime() then
			return HandOfGuldan
		end
		if DemonicCore:Stack() >= 3 or (not CallDreadstalkers:Ready(4) and (not SummonDemonicTyrant:Ready(20) or SummonDemonicTyrant:Ready(Player.gcd * 4)) and (not SummonVilefiend.known or not SummonVilefiend:Ready(3))) then
			return HandOfGuldan
		end
	end
	if SoulStrike:Usable() and Player.soul_shards < 5 and DemonicCore:Stack() <= 2 then
		return SoulStrike
	end
	if Demonbolt:Usable() and Player.soul_shards <= 3 and DemonicCore:Up() and ((SummonDemonicTyrant:Ready(6) or (not ShadowsBite.known and not SummonDemonicTyrant:Ready(22))) or DemonicCore:Stack() >= 3 or DemonicCore:Remains() < 5 or Target.timeToDie < 25 or (ShadowsBite.known and ShadowsBite:Up())) then
		return Demonbolt
	end
	if FocusedAzeriteBeam:Usable() and Player.tyrant_remains == 0 and (not ExplosivePotential.known or ExplosivePotential:Remains() > (4.5 * Player.haste_factor)) then
		UseCooldown(FocusedAzeriteBeam)
	end
	if PurifyingBlast:Usable() then
		UseCooldown(PurifyingBlast)
	end
	if BloodOfTheEnemy:Usable() then
		UseCooldown(BloodOfTheEnemy)
	end
	if Player.tyrant_remains == 0 then
		if ReapingFlames:Usable() then
			return UseCooldown(ReapingFlames)
		end
		if ConcentratedFlame:Usable() and ConcentratedFlame.dot:Down() then
			return ConcentratedFlame
		end
	end
	return self:build_a_shard()
end

APL[SPEC.DEMONOLOGY].build_a_shard = function(self)
--[[
actions.build_a_shard=memory_of_lucid_dreams,if=soul_shard<2&!talent.demonic_consumption.enabled
actions.build_a_shard+=/soul_strike,if=soul_shard=4|soul_shard=3&buff.memory_of_lucid_dreams.up
actions.build_a_shard+=/demonbolt,if=buff.demonic_core.up&buff.demonic_core.remains<=(action.shadow_bolt.execute_time*(5-soul_shard)+action.hand_of_guldan.execute_time)
actions.build_a_shard+=/demonbolt,if=buff.demonic_core.up&soul_shard<=3&pet.demonic_tyrant.active
actions.build_a_shard+=/soul_strike
actions.build_a_shard+=/shadow_bolt
]]
	if not DemonicConsumption.known and Player.soul_shards < 2 and MemoryOfLucidDreams:Usable() then
		UseCooldown(MemoryOfLucidDreams)
	end
	if SoulStrike:Usable() and (Player.soul_shards == 4 or (Player.soul_shards == 4 and MemoryOfLucidDreams.known and MemoryOfLucidDreams:Up())) then
		return SoulStrike
	end
	if Demonbolt:Usable() and DemonicCore:Up() then
		if DemonicCore:Remains() <= (ShadowBoltDemo:CastTime() * (5 - Player.soul_shards) + HandOfGuldan:CastTime()) then
			return Demonbolt
		end
		if Player.soul_shards <= 3 and Player.tyrant_remains > 0 then
			return Demonbolt
		end
	end
	if SoulStrike:Usable() then
		return SoulStrike
	end
	if ShadowBoltDemo:Usable() then
		return ShadowBoltDemo
	end
end

APL[SPEC.DEMONOLOGY].tyrant_active = function(self)
--[[
actions.tyrant_active=implosion,if=azerite.explosive_potential.enabled&buff.wild_imps.stack>=3&buff.explosive_potential.remains<pet.demonic_tyrant.remains
actions.tyrant_active+=/hand_of_guldan,if=azerite.explosive_potential.enabled&buff.wild_imps.stack<3&soul_shard>=3&buff.explosive_potential.remains<execute_time&!prev_gcd.1.hand_of_guldan&!prev_gcd.2.hand_of_guldan
]]
	if ExplosivePotential.known then
		if Implosion:Usable() and Player.imp_count >= 3 and ExplosivePotential:Remains() < Player.tyrant_remains then
			return Implosion
		end
		if HandOfGuldan:Usable() and Player.imp_count < 3 and Player.soul_shards >= 3 and ExplosivePotential:Remains() < HandOfGuldan:CastTime() and not (HandOfGuldan:Previous(1) or HandOfGuldan:Previous(2)) then
			return HandOfGuldan
		end
	end
end

APL[SPEC.DEMONOLOGY].dcon_prep = function(self)
--[[
actions.dcon_prep=hand_of_guldan,if=prev_gcd.1.hand_of_guldan&prev_gcd.2.hand_of_guldan&!prev_gcd.3.hand_of_guldan&cooldown.summon_demonic_tyrant.remains<execute_time
actions.dcon_prep+=/summon_demonic_tyrant,if=prev_gcd.1.hand_of_guldan&prev_gcd.2.hand_of_guldan&(prev_gcd.3.hand_of_guldan|prev_gcd.4.hand_of_guldan)
actions.dcon_prep+=/demonbolt,if=soul_shard>=2&buff.demonic_core.up&prev_gcd.1.hand_of_guldan&!(prev_gcd.3.hand_of_guldan&prev_gcd.5.hand_of_guldan)&cooldown.summon_demonic_tyrant.remains<execute_time+action.hand_of_guldan.cast_time*2
actions.dcon_prep+=/hand_of_guldan,if=soul_shard>=4&prev_gcd.1.demonbolt&prev_gcd.2.hand_of_guldan&cooldown.summon_demonic_tyrant.remains<execute_time*2
actions.dcon_prep+=/hand_of_guldan,if=prev_gcd.1.hand_of_guldan&prev_gcd.2.demonbolt&prev_gcd.3.hand_of_guldan&cooldown.summon_demonic_tyrant.remains<execute_time
actions.dcon_prep+=/call_dreadstalkers,if=buff.demonic_core.remains<6
actions.dcon_prep+=/implosion,if=azerite.explosive_potential.enabled&buff.explosive_potential.remains<6&buff.wild_imps.stack>=3&soul_shard>=3
actions.dcon_prep+=/hand_of_guldan,if=azerite.explosive_potential.enabled&buff.explosive_potential.down&soul_shard>=3&buff.wild_imps.stack<3&!(prev_gcd.1.hand_of_guldan|prev_gcd.2.hand_of_guldan)
actions.dcon_prep+=/bilescourge_bombers
actions.dcon_prep+=/call_dreadstalkers
actions.dcon_prep+=/summon_vilefiend,if=soul_shard=5
actions.dcon_prep+=/grimoire_felguard,if=soul_shard=5
actions.dcon_prep+=/memory_of_lucid_dreams
actions.dcon_prep+=/hand_of_guldan,if=soul_shard=5
actions.dcon_prep+=/demonbolt,if=soul_shard<=3&buff.demonic_core.stack>=2
actions.dcon_prep+=/doom,if=refreshable&target.time_to_die>remains+30
actions.dcon_prep+=/guardian_of_azeroth
actions.dcon_prep+=/call_action_list,name=build_a_shard
]]
	local tyrant_cd, hog_ct = SummonDemonicTyrant:Cooldown(), HandOfGuldan:CastTime()
	if HandOfGuldan:Usable() and HandOfGuldan:Previous(1) and HandOfGuldan:Previous(2) and not HandOfGuldan:Previous(3) and tyrant_cd < hog_ct then
		return HandOfGuldan
	end
	if SummonDemonicTyrant:Usable() then
		if HandOfGuldan:Previous(1) and HandOfGuldan:Previous(2) and (HandOfGuldan:Previous(3) or HandOfGuldan:Previous(4)) then
			UseCooldown(SummonDemonicTyrant)
		end
		if Player.tyrant_available_power >= 200 then
			local imps_idle = not (Pet.WildImp:Casting() or Pet.WildImpID:Casting())
			if HandOfGuldan:Usable() and imps_idle and (Player.soul_shards >= 2 or Player.tyrant_available_power >= 250) and Player:ImpsIn(hog_ct + SummonDemonicTyrant:CastTime()) >= (Player.imp_count - 2) then
				return HandOfGuldan
			end
			if (HandOfGuldan:Previous(1) and (HandOfGuldan:Previous(2) or imps_idle)) or (Player.tyrant_available_power >= 280 and imps_idle and Player:ImpsIn(SummonDemonicTyrant:CastTime()) >= Player.imp_count) then
				UseCooldown(SummonDemonicTyrant)
			end
		end
	end
	if Demonbolt:Usable() and Player.soul_shards >= 2 and DemonicCore:Up() and HandOfGuldan:Previous(1) and not (HandOfGuldan:Previous(3) and HandOfGuldan:Previous(5)) and tyrant_cd < (Player.gcd + hog_ct * 2) then
		return Demonbolt
	end
	if HandOfGuldan:Usable() then
		if Player.soul_shards >= 4 and Demonbolt:Previous(1) and HandOfGuldan:Previous(2) and tyrant_cd < (hog_ct * 2) then
			return HandOfGuldan
		end
		if HandOfGuldan:Previous(1) and Demonbolt:Previous(2) and HandOfGuldan:Previous(3) and tyrant_cd < hog_ct then
			return HandOfGuldan
		end
	end
	if CallDreadstalkers:Usable() and DemonicCore:Remains() < 6 then
		return CallDreadstalkers
	end
	if ExplosivePotential.known and ExplosivePotential:Remains() < 6 then
		if Implosion:Usable() and Player.imp_count >= 3 and (Player.soul_shards >= 3 or Player:ImpsIn(ShadowBoltDemo:CastTime()) < 3) then
			return Implosion
		end
		if HandOfGuldan:Usable() and Player.imp_count < 3 and Player.soul_shards >= 3 and ExplosivePotential:Down() and not (HandOfGuldan:Previous(1) or HandOfGuldan:Previous(2)) then
			return HandOfGuldan
		end
	end
	if BilescourgeBombers:Usable() then
		UseCooldown(BilescourgeBombers)
	end
	if CallDreadstalkers:Usable() then
		return CallDreadstalkers
	end
	if Player.soul_shards >= 5 then
		if SummonVilefiend:Usable() then
			UseCooldown(SummonVilefiend)
		elseif GrimoireFelguard:Usable() then
			UseCooldown(GrimoireFelguard)
		elseif MemoryOfLucidDreams:Usable() then
			UseCooldown(MemoryOfLucidDreams)
		end
		if HandOfGuldan:Usable() then
			return HandOfGuldan
		end
	end
	if Demonbolt:Usable() and Player.soul_shards <= 3 and DemonicCore:Stack() >= 2 then
		return Demonbolt
	end
	if Doom:Usable() and Doom:Refreshable() and Target.timeToDie > Doom:Remains() + 30 then
		return Doom
	end
	if GuardianOfAzeroth:Usable() then
		UseCooldown(GuardianOfAzeroth)
	end
	return self:build_a_shard()
end

APL[SPEC.DEMONOLOGY].implosion = function(self)
--[[
actions.implosion=implosion,if=(buff.wild_imps.stack>=6&(soul_shard<3|prev_gcd.1.call_dreadstalkers|buff.wild_imps.stack>=9|prev_gcd.1.bilescourge_bombers|(!prev_gcd.1.hand_of_guldan&!prev_gcd.2.hand_of_guldan))&!prev_gcd.1.hand_of_guldan&!prev_gcd.2.hand_of_guldan&buff.demonic_power.down)|(time_to_die<3&buff.wild_imps.stack>0&(!azerite.explosive_potential.rank|buff.wild_imps.stack>3))|(prev_gcd.2.call_dreadstalkers&buff.wild_imps.stack>2&!talent.demonic_calling.enabled)
actions.implosion+=/bilescourge_bombers,if=talent.demonic_consumption.enabled
actions.implosion+=/grimoire_felguard,if=cooldown.summon_demonic_tyrant.remains<13|!equipped.132369
actions.implosion+=/call_dreadstalkers,if=(cooldown.summon_demonic_tyrant.remains<9&buff.demonic_calling.remains)|(cooldown.summon_demonic_tyrant.remains<11&!buff.demonic_calling.remains)|cooldown.summon_demonic_tyrant.remains>14
actions.implosion+=/summon_demonic_tyrant
actions.implosion+=/hand_of_guldan,if=soul_shard>=5
actions.implosion+=/hand_of_guldan,if=(soul_shard>=4|soul_shard>=3&talent.soul_conduit.enabled)&buff.memory_of_lucid_dreams.remains>cast_time
actions.implosion+=/hand_of_guldan,if=soul_shard>=3&(((prev_gcd.2.hand_of_guldan|buff.wild_imps.stack>=3)&buff.wild_imps.stack<9)|cooldown.summon_demonic_tyrant.remains<=gcd*2|buff.demonic_power.remains>gcd*2)
actions.implosion+=/demonbolt,if=prev_gcd.1.hand_of_guldan&soul_shard>=1&(buff.wild_imps.stack<=3|prev_gcd.3.hand_of_guldan)&soul_shard<4&buff.demonic_core.up
actions.implosion+=/summon_vilefiend,if=(cooldown.summon_demonic_tyrant.remains>40&spell_targets.implosion<=2)|cooldown.summon_demonic_tyrant.remains<12
actions.implosion+=/bilescourge_bombers,if=cooldown.summon_demonic_tyrant.remains>9
actions.implosion+=/focused_azerite_beam
actions.implosion+=/purifying_blast
actions.implosion+=/blood_of_the_enemy
actions.implosion+=/concentrated_flame,if=!dot.concentrated_flame_burn.remains&!action.concentrated_flame.in_flight&spell_targets.implosion<5
actions.implosion+=/soul_strike,if=soul_shard<5&buff.demonic_core.stack<=2
actions.implosion+=/demonbolt,if=soul_shard<=3&buff.demonic_core.up&(buff.demonic_core.stack>=3|buff.demonic_core.remains<=gcd*5.7|spell_targets.implosion>=4&cooldown.summon_demonic_tyrant.remains>22)
actions.implosion+=/doom,cycle_targets=1,max_cycle_targets=7,if=refreshable
actions.implosion+=/call_action_list,name=build_a_shard
]]
	if Implosion:Usable() and ((Target.timeToDie < 3 and (not ExplosivePotential.known or Player.imp_count >= 3)) or (Player.imp_count >= 6 and (Player.soul_shards < 3 or CallDreadstalkers:Previous(1) or Player.imp_count >= 9 or BilescourgeBombers:Previous(1) or not (HandOfGuldan:Previous(1) or HandOfGuldan:Previous(2))) and not (HandOfGuldan:Previous(1) or HandOfGuldan:Previous(2) or DemonicPower:Up())) or (not DemonicCalling.known and Player.imp_count > 2 and CallDreadstalkers:Previous(2))) then
		return Implosion
	end
	if DemonicConsumption.known and BilescourgeBombers:Usable() then
		UseCooldown(BilescourgeBombers)
	end
	if GrimoireFelguard:Usable() and SummonDemonicTyrant:Ready(13) then
		UseCooldown(GrimoireFelguard)
	end
	if CallDreadstalkers:Usable() and (SummonDemonicTyrant:Ready(DemonicCalling:Up() and 9 or 11) or not SummonDemonicTyrant:Ready(14)) then
		return CallDreadstalkers
	end
	if SummonDemonicTyrant:Usable() then
		UseCooldown(SummonDemonicTyrant)
	end
	if HandOfGuldan:Usable() and Player.soul_shards >= 3 then
		if Player.soul_shards >= 5 then
			return HandOfGuldan
		end
		if MemoryOfLucidDreams.known and (Player.soul_shards >= 4 or SoulConduit.known) and MemoryOfLucidDreams:Remains() > HandOfGuldan:CastTime() then
			return HandOfGuldan
		end
		if ((HandOfGuldan:Previous(2) or Player.imp_count >= 3) and Player.imp_count < 9) or SummonDemonicTyrant:Ready(Player.gcd * 2) or DemonicPower:Remains() > (Player.gcd * 2) then
			return HandOfGuldan
		end
	end
	if Demonbolt:Usable() and HandOfGuldan:Previous(1) and between(Player.soul_shards, 1, 3) and (Player.imp_count <= 3 or HandOfGuldan:Previous(3)) and DemonicCore:Up() then
		return Demonbolt
	end
	if SummonVilefiend:Usable() and (SummonDemonicTyrant:Ready(12) or (Player.enemies <= 2 and not SummonDemonicTyrant:Ready(40))) then
		UseCooldown(SummonVilefiend)
	end
	if BilescourgeBombers:Usable() and not SummonDemonicTyrant:Ready(9) then
		UseCooldown(BilescourgeBombers)
	end
	if FocusedAzeriteBeam:Usable() and (not ExplosivePotential.known or ExplosivePotential:Remains() > (4.5 * Player.haste_factor)) then
		UseCooldown(FocusedAzeriteBeam)
	end
	if PurifyingBlast:Usable() then
		UseCooldown(PurifyingBlast)
	end
	if BloodOfTheEnemy:Usable() then
		UseCooldown(BloodOfTheEnemy)
	end
	if ConcentratedFlame:Usable() and ConcentratedFlame.dot:Down() and Player.enemies < 5 then
		return ConcentratedFlame
	end
	if SoulStrike:Usable() and Player.soul_shards < 5 and DemonicCore:Stack() <= 2 then
		return SoulStrike
	end
	if Demonbolt:Usable() and Player.soul_shards <= 3 and DemonicCore:Up() and (DemonicCore:Stack() >= 3 or DemonicCore:Remains() <= (Player.gcd * 5.7) or Player.enemies >= 4 and not SummonDemonicTyrant:Ready(22)) then
		return Demonbolt
	end
	if Doom:Usable() and Doom:Refreshable() and Target.timeToDie > (Doom:Remains() + 30) then
		return Doom
	end
	return self:build_a_shard()
end

APL[SPEC.DEMONOLOGY].nether_portal_active = function(self)
--[[
actions.nether_portal_active=bilescourge_bombers
actions.nether_portal_active+=/grimoire_felguard,if=cooldown.summon_demonic_tyrant.remains<13|!equipped.132369
actions.nether_portal_active+=/summon_vilefiend,if=cooldown.summon_demonic_tyrant.remains>40|cooldown.summon_demonic_tyrant.remains<12
actions.nether_portal_active+=/call_dreadstalkers,if=(cooldown.summon_demonic_tyrant.remains<9&buff.demonic_calling.remains)|(cooldown.summon_demonic_tyrant.remains<11&!buff.demonic_calling.remains)|cooldown.summon_demonic_tyrant.remains>14
actions.nether_portal_active+=/call_action_list,name=build_a_shard,if=soul_shard=1&(cooldown.call_dreadstalkers.remains<action.shadow_bolt.cast_time|(talent.bilescourge_bombers.enabled&cooldown.bilescourge_bombers.remains<action.shadow_bolt.cast_time))
actions.nether_portal_active+=/hand_of_guldan,if=((cooldown.call_dreadstalkers.remains>action.demonbolt.cast_time)&(cooldown.call_dreadstalkers.remains>action.shadow_bolt.cast_time))&cooldown.nether_portal.remains>(165+action.hand_of_guldan.cast_time)
actions.nether_portal_active+=/summon_demonic_tyrant,if=buff.nether_portal.remains<5&soul_shard=0
actions.nether_portal_active+=/summon_demonic_tyrant,if=buff.nether_portal.remains<action.summon_demonic_tyrant.cast_time+0.5
actions.nether_portal_active+=/demonbolt,if=buff.demonic_core.up&soul_shard<=3
actions.nether_portal_active+=/call_action_list,name=build_a_shard
]]
	if BilescourgeBombers:Usable() then
		UseCooldown(BilescourgeBombers)
	end
	if GrimoireFelguard:Usable() and SummonDemonicTyrant:Ready(13) then
		UseCooldown(GrimoireFelguard)
	end
	if SummonVilefiend:Usable() and (SummonDemonicTyrant:Ready(12) or not SummonDemonicTyrant:Ready(40)) then
		UseCooldown(SummonVilefiend)
	end
	if CallDreadstalkers:Usable() and (SummonDemonicTyrant:Ready(DemonicCalling:Up() and 9 or 11) or not SummonDemonicTyrant:Ready(14)) then
		return CallDreadstalkers
	end
	if Player.soul_shards == 1 and (CallDreadstalkers:Ready(ShadowBoltDemo:CastTime()) or (BilescourgeBombers.known and BilescourgeBombers:Ready(ShadowBoltDemo:CastTime()))) then
		local apl = self:build_a_shard()
		if apl then return apl end
	end
	if HandOfGuldan:Usable() and not NetherPortal:Ready(165 + HandOfGuldan:CastTime()) and not CallDreadstalkers:Ready(Demonbolt:CastTime()) and not CallDreadstalkers:Ready(ShadowBoltDemo:CastTime())  then
		return HandOfGuldan
	end
	if SummonDemonicTyrant:Usable() and ((Player.soul_shards == 0 and NetherPortal:Remains() < 5) or (NetherPortal:Remains() < SummonDemonicTyrant:CastTime() + 0.5)) then
		UseCooldown(SummonDemonicTyrant)
	end
	if Demonbolt:Usable() and Player.soul_shards <= 3 and DemonicCore:Up() then
		return Demonbolt
	end
	return self:build_a_shard()
end

APL[SPEC.DEMONOLOGY].nether_portal_building = function(self)
--[[
actions.nether_portal_building=use_item,name=azsharas_font_of_power,if=cooldown.nether_portal.remains<=5*spell_haste
actions.nether_portal_building+=/guardian_of_azeroth,if=!cooldown.nether_portal.remains&soul_shard>=5
actions.nether_portal_building+=/nether_portal,if=soul_shard>=5
actions.nether_portal_building+=/call_dreadstalkers,if=time>=30
actions.nether_portal_building+=/hand_of_guldan,if=time>=30&cooldown.call_dreadstalkers.remains>18&soul_shard>=3
actions.nether_portal_building+=/power_siphon,if=time>=30&buff.wild_imps.stack>=2&buff.demonic_core.stack<=2&buff.demonic_power.down&soul_shard>=3
actions.nether_portal_building+=/hand_of_guldan,if=time>=30&soul_shard>=5
actions.nether_portal_building+=/call_action_list,name=build_a_shard
]]
	if GuardianOfAzeroth:Usable() and NetherPortal:Ready() and Player.soul_shards >= 5 then
		UseCooldown(GuardianOfAzeroth)
	end
	if NetherPortal:Usable() and Player.soul_shards >= 5 then
		UseCooldown(NetherPortal)
	end
	if Player:TimeInCombat() >= 30 then
		if CallDreadstalkers:Usable() then
			return CallDreadstalkers
		end
		if Player.soul_shards >= 3 then
			if HandOfGuldan:Usable() and not CallDreadstalkers:Ready(18) then
				return HandOfGuldan
			end
			if PowerSiphon:Usable() and Player.imp_count >= 2 and DemonicCore:Stack() <= 2 and DemonicPower:Down() then
				UseCooldown(PowerSiphon)
			end
			if HandOfGuldan:Usable() and Player.soul_shards >= 5 then
				return HandOfGuldan
			end
		end
	end
	return self:build_a_shard()
end

APL[SPEC.DESTRUCTION].main = function(self)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/summon_pet
actions.precombat+=/grimoire_of_sacrifice,if=talent.grimoire_of_sacrifice.enabled
actions.precombat+=/snapshot_stats
actions.precombat+=/potion
actions.precombat+=/soul_fire
actions.precombat+=/incinerate,if=!talent.soul_fire.enabled
]]
		if Opt.healthstone and Healthstone:Charges() == 0 and CreateHealthstone:Usable() then
			return CreateHealthstone
		end
		if GrimoireOfSacrifice.known then
			if GrimoireOfSacrifice:Remains() < 300 then
				if Player.pet_active then
					return GrimoireOfSacrifice
				else
					return SummonImp
				end
			end
		elseif not Player.pet_active then
			return SummonImp
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfEndlessFathoms:Usable() and GreaterFlaskOfEndlessFathoms.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfEndlessFathoms)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
		if Player.soul_shards < 5 and not (SoulFire:Casting() or Incinerate:Casting()) then
			if SoulFire:Usable() then
				return SoulFire
			end
			if Incinerate:Usable() then
				return Incinerate
			end
		end
	else
		if GrimoireOfSacrifice.known then
			if GrimoireOfSacrifice:Remains() < 300 then
				if Player.pet_active then
					UseExtra(GrimoireOfSacrifice)
				else
					UseExtra(SummonImp)
				end
			end
		elseif not Player.pet_active then
			UseExtra(SummonImp)
		end
	end
--[[
# Havoc uses a special priority list on most multitarget scenarios, but the target threshold can vary depending on talents
actions=call_action_list,name=havoc,if=havoc_active&active_enemies<5-talent.inferno.enabled+(talent.inferno.enabled&talent.internal_combustion.enabled)
# Cataclysm should be used on cooldown as soon as possible
actions+=/cataclysm
# Two target scenarios are handled like single target with Havoc weaved in. Starting with three targets, a specialized AoE priority is required
actions+=/call_action_list,name=aoe,if=active_enemies>2
# Immolate should never fall off the primary target. If Cataclysm will refresh Immolate before it expires, there's no reason to waste time casting it
actions+=/immolate,cycle_targets=1,if=refreshable&(!talent.cataclysm.enabled|cooldown.cataclysm.remains>remains)
# #With Internal Combustion talented, it's possible Immolate will need to be refreshed sooner than the remaining duration says, if there's already a Chaos Bolt on the way to the target.
actions+=/immolate,if=talent.internal_combustion.enabled&action.chaos_bolt.in_flight&remains<duration*0.5
# The general rule of thumb for talents is to maximize the number of uses of each
actions+=/call_action_list,name=cds
actions+=/channel_demonfire
# The if condition here always applies Havoc to something other than the primary target
actions+=/havoc,cycle_targets=1,if=!(target=self.target)&(dot.immolate.remains>dot.immolate.duration*0.5|!talent.internal_combustion.enabled)&(!cooldown.summon_infernal.ready|!talent.grimoire_of_supremacy.enabled|talent.grimoire_of_supremacy.enabled&pet.infernal.remains<=10)
# Soul Fire should be used on cooldown, it does not appear worth saving for generating Soul Shards during cooldowns
actions+=/soul_fire
# Conflagrate should only be used to set up Chaos Bolts. Flashover lets Conflagrate be used earlier to set up an Incinerate before CB. If a major cooldown is coming up, save charges for it
actions+=/conflagrate,if=buff.backdraft.down&soul_shard>=1.5-0.3*talent.flashover.enabled&!variable.pool_soul_shards
# Shadowburn is used as a discount Conflagrate to generate shards if you don't have enough for a Chaos Bolt. The same rules about saving it for major cooldowns applies
actions+=/shadowburn,if=soul_shard<2&(!variable.pool_soul_shards|charges>1)
# It's worth stocking up on Soul Shards before a major cooldown usage
actions+=/variable,name=pool_soul_shards,value=active_enemies>1&cooldown.havoc.remains<=10|cooldown.summon_infernal.remains<=20&(talent.grimoire_of_supremacy.enabled|talent.dark_soul_instability.enabled&cooldown.dark_soul_instability.remains<=20)|talent.dark_soul_instability.enabled&cooldown.dark_soul_instability.remains<=20&(cooldown.summon_infernal.remains>target.time_to_die|cooldown.summon_infernal.remains+cooldown.summon_infernal.duration>target.time_to_die)
# Chaos Bolt has several possible use conditions. Crashing Chaos, Grimoire of Supremacy, and Dark Soul: Instability all favor casting as many CBs as possible when any of them are active
actions+=/chaos_bolt,if=(talent.grimoire_of_supremacy.enabled|azerite.crashing_chaos.enabled)&pet.infernal.active|buff.dark_soul_instability.up
# If Soul Shards are not being pooled and Eradication is not talented, just spend CBs as they become available
actions+=/chaos_bolt,if=!variable.pool_soul_shards&!talent.eradication.enabled
# With Eradication, it's beneficial to maximize the uptime on the debuff. However, it's still better to use Chaos Bolt immediately if Backdraft is up
actions+=/chaos_bolt,if=!variable.pool_soul_shards&talent.eradication.enabled&(debuff.eradication.remains<cast_time|buff.backdraft.up)
# Even when saving, do not overcap on Soul Shards
actions+=/chaos_bolt,if=(soul_shard>=4.5-0.2*active_enemies)
# Don't overcap on charges of Conflagrate
actions+=/conflagrate,if=charges>1
actions+=/incinerate
]]
	if Havoc:Ticking() and Player.enemies < (5 - (Inferno.known and 1 or 0) + (Inferno.known and InternalCombustion.known and 1 or 0)) then
		local apl = self:havoc()
		if apl then return apl end
	end
	if Cataclysm:Usable() then
		UseCooldown(Cataclysm)
	end
	if Player.enemies > 2 then
		local apl = self:aoe()
		if apl then return apl end
	end
	if Immolate:Usable() then
		if Immolate:Refreshable() and (not Cataclysm.known or Cataclysm:Cooldown() > Immolate:Remains()) then
			return Immolate
		end
		if InternalCombustion.known and ChaosBolt:Traveling() and Immolate:Remains() < (Immolate:Duration() * 0.5) then
			return Immolate
		end
	end
	self:cds()
	if ChannelDemonfire:Usable() then
		UseCooldown(ChannelDemonfire)
	end
	if Havoc:Usable() and Player.enemies > 1 and (Immolate:Remains() > (Immolate:Duration() * 0.5) or not InternalCombustion.known) and (not SummonInfernal:Ready() or not GrimoireOfSupremacy.known or GrimoireOfSupremacy.known and Pet.Infernal:Remains() < 10) then
		UseExtra(Havoc)
	end
end

APL[SPEC.DESTRUCTION].aoe = function(self)
--[[
# Rain of Fire is typically the highest priority action, but certain situations favor using Chaos Bolt instead
actions.aoe=rain_of_fire,if=pet.infernal.active&(buff.crashing_chaos.down|!talent.grimoire_of_supremacy.enabled)&(!cooldown.havoc.ready|active_enemies>3)
# Channel Demonfire only needs one Immolate active during its cast for AoE. Primary target is used here for simplicity
actions.aoe+=/channel_demonfire,if=dot.immolate.remains>cast_time
# Similar to single target, there is no need to refresh Immolates if Cataclysm can do it instead
actions.aoe+=/immolate,cycle_targets=1,if=remains<5&(!talent.cataclysm.enabled|cooldown.cataclysm.remains>remains)
# Rules for cooldowns do not change for AoE, so call the same list as on single target
actions.aoe+=/call_action_list,name=cds
# Three targets is an in-between case that gives a slight benefit to higher priority Havoc
actions.aoe+=/havoc,cycle_targets=1,if=!(target=self.target)&active_enemies<4
# Rain of Fire will start to dominate on heavy AoE, but some significant Chaos Bolt buffs will still give higher damage output on occasion
actions.aoe+=/chaos_bolt,if=talent.grimoire_of_supremacy.enabled&pet.infernal.active&(havoc_active|talent.cataclysm.enabled|talent.inferno.enabled&active_enemies<4)
# Barring any exceptions, Rain of Fire will be used as much as possible, since multiple copies of it can stack
actions.aoe+=/rain_of_fire
# Even if the Havoc priority list won't be used, Havoc is pretty much free damage and resources and should be used almost on cooldown
actions.aoe+=/havoc,cycle_targets=1,if=!(target=self.target)&(!talent.grimoire_of_supremacy.enabled|!talent.inferno.enabled|talent.grimoire_of_supremacy.enabled&pet.infernal.remains<=10)
# Use Fire and Brimstone if Backdraft is active, as long as it will not overcap on Soul Shards
actions.aoe+=/incinerate,if=talent.fire_and_brimstone.enabled&buff.backdraft.up&soul_shard<5-0.2*active_enemies
# Other Soul Shard generating abilities are good filler if not using Fire and Brimstone
actions.aoe+=/soul_fire
actions.aoe+=/conflagrate,if=buff.backdraft.down
actions.aoe+=/shadowburn,if=!talent.fire_and_brimstone.enabled
# With Fire and Brimstone, Incinerate will be a strong filler. It's placed here for all talents to prevent accidentally using the single target rotation list
actions.aoe+=/incinerate
]]

end

APL[SPEC.DESTRUCTION].cds = function(self)
--[[
# If both cooldowns are ready, summon the Infernal then activate DSI. If not using DSI, use this on CD
actions.cds=summon_infernal,if=cooldown.dark_soul_instability.ready|!talent.dark_soul_instability.enabled
actions.cds+=/dark_soul_instability,if=pet.infernal.active
# If DSI is not ready but you can get more than one infernal in before the end of the fight, summon the Infernal now
actions.cds+=/summon_infernal,if=target.time_to_die>cooldown.summon_infernal.duration
# If you can get in more than one more DSI before the end of the fight, use that now
actions.cds+=/dark_soul_instability,if=target.time_to_die>cooldown.dark_soul_instability.duration+20
# If the fight will end before DSI is back up, summon the Infernal
actions.cds+=/summon_infernal,if=talent.dark_soul_instability.enabled&cooldown.dark_soul_instability.remains>target.time_to_die
# If the fight will end before infernal is back up, use DSI
actions.cds+=/dark_soul_instability,if=cooldown.summon_infernal.remains>target.time_to_die
# If the fight is about to end, use CDs such that they get as much time up as possible
actions.cds+=/summon_infernal,if=target.time_to_die<30
actions.cds+=/dark_soul_instability,if=target.time_to_die<20
actions.cds+=/potion,if=pet.infernal.active|target.time_to_die<30
actions.cds+=/berserking
actions.cds+=/blood_fury
actions.cds+=/fireblood
actions.cds+=/use_items
]]

end

APL[SPEC.DESTRUCTION].havoc = function(self)
--[[
actions.havoc=conflagrate,if=buff.backdraft.down&soul_shard>=1&soul_shard<=4
actions.havoc+=/immolate,if=talent.internal_combustion.enabled&remains<duration*0.5|!talent.internal_combustion.enabled&refreshable
actions.havoc+=/chaos_bolt,if=cast_time<havoc_remains
actions.havoc+=/soul_fire
actions.havoc+=/shadowburn,if=active_enemies<3|!talent.fire_and_brimstone.enabled
actions.havoc+=/incinerate,if=cast_time<havoc_remains
]]

end

APL.Interrupt = function(self)
	if SpellLock:Usable() then
		return SpellLock
	end
	if AxeToss:Usable() then
		return AxeToss
	end
end

-- End Action Priority Lists

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
	end
end

function UI:CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
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
	UI:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon, i
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
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	doomedPanel:EnableMouse(Opt.aoe or not Opt.locked)
	doomedPanel.button:SetShown(Opt.aoe)
	if Opt.locked then
		doomedPanel:SetScript('OnDragStart', nil)
		doomedPanel:SetScript('OnDragStop', nil)
		doomedPanel:RegisterForDrag(nil)
		doomedPreviousPanel:EnableMouse(false)
		doomedCooldownPanel:EnableMouse(false)
		doomedInterruptPanel:EnableMouse(false)
		doomedExtraPanel:EnableMouse(false)
	else
		if not Opt.aoe then
			doomedPanel:SetScript('OnDragStart', doomedPanel.StartMoving)
			doomedPanel:SetScript('OnDragStop', doomedPanel.StopMovingOrSizing)
			doomedPanel:RegisterForDrag('LeftButton')
		end
		doomedPreviousPanel:EnableMouse(true)
		doomedCooldownPanel:EnableMouse(true)
		doomedInterruptPanel:EnableMouse(true)
		doomedExtraPanel:EnableMouse(true)
	end
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
	['blizzard'] = {
		[SPEC.AFFLICTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		},
		[SPEC.DEMONOLOGY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		},
		[SPEC.DESTRUCTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		}
	},
	['kui'] = {
		[SPEC.AFFLICTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 6 }
		},
		[SPEC.DEMONOLOGY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 6 }
		},
		[SPEC.DESTRUCTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 6 }
		}
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
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	timer.display = 0
	local dim, text_tl, text_tr
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	if Player.spec == SPEC.AFFLICTION then
		if Opt.pet_count then
			text_tl = Player.ua_stack > 0 and Player.ua_stack
		end
		if Opt.tyrant then
			local _, unit, remains
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
				text_tl = Player.imp_count > 0 and Player.imp_count
			else
				text_tl = Player.pet_count > 0 and Player.pet_count
			end
		end
		if Opt.tyrant then
			if DemonicConsumption.known and Player.tyrant_available_power > 0 and (Player.tyrant_cd < 5 or SummonDemonicTyrant:Casting()) then
				text_tr = format('%d%%\n', Player.tyrant_available_power)
			else
				text_tr = ''
			end
			local _, unit, remains
			for _, unit in next, Pet.DemonicTyrant.active_units do
				if unit.full then
					remains = unit.expires - Player.time
					if unit.power > 0 and remains > 5 then
						text_tr = format('%s%d%%\n', text_tr, unit.power)
					elseif remains > 0 then
						text_tr = format('%s%.1fs\n', text_tr, remains)
					end
				end
			end
			for _, unit in next, Pet.DemonicTyrant.active_units do
				if not unit.full then
					remains = unit.expires - Player.time
					if remains > 0 then
						text_tr = format('%s%.1fs\n', text_tr, remains)
					end
				end
			end
		end
	end
	doomedPanel.dimmer:SetShown(dim)
	doomedPanel.text.tl:SetText(text_tl)
	doomedPanel.text.tr:SetText(text_tr)
	--doomedPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
end

function UI:UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.main =  nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	start, duration = GetSpellCooldown(61304)
	Player.gcd_remains = start > 0 and duration - (Player.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	Player.ability_casting = abilities.bySpellId[spellId]
	Player.execute_remains = max(remains and (remains / 1000 - Player.ctime) or 0, Player.gcd_remains)
	Player.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	Player.gcd = 1.5 * Player.haste_factor
	Player.health = UnitHealth('player')
	Player.health_max = UnitHealthMax('player')
	Player.mana_regen = GetPowerRegen()
	Player.mana = UnitPower('player', 0) + (Player.mana_regen * Player.execute_remains)
	Player.soul_shards = UnitPower('player', 7)
	if Player.ability_casting then
		Player.mana = Player.mana - Player.ability_casting:Cost()
		Player.soul_shards = Player.soul_shards - Player.ability_casting:ShardCost()
	end
	Player.mana = min(max(Player.mana, 0), Player.mana_max)
	Player.soul_shards = min(max(Player.soul_shards, 0), Player.soul_shards_max)
	Player.moving = GetUnitSpeed('player') ~= 0
	Player:UpdatePet()

	summonedPets:Purge()
	trackAuras:Purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end

	if Player.spec == SPEC.AFFLICTION then
		Player.darkglare_remains = Pet.Darkglare:Remains()
	elseif Player.spec == SPEC.DEMONOLOGY then
		HandOfGuldan:Purge()
		if Opt.pet_count then
			Player.pet_count = summonedPets:Count() + (Player.pet_alive and 1 or 0)
		end
		Player.imp_count = Pet.WildImp:Count() + (Pet.WildImpID and Pet.WildImpID:Count() or 0)
		Player.tyrant_cd = SummonDemonicTyrant:Cooldown()
		Player.tyrant_remains = Pet.DemonicTyrant:Remains()
		Player.tyrant_power = Pet.DemonicTyrant:Power()
		Player.tyrant_available_power = Pet.DemonicTyrant:AvailablePower()
	end

	Player.main = APL[Player.spec]:main()
	if Player.main then
		doomedPanel.icon:SetTexture(Player.main.icon)
	end
	if Player.cd then
		doomedCooldownPanel.icon:SetTexture(Player.cd.icon)
	end
	if Player.extra then
		doomedExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local ends, notInterruptible
		_, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			doomedInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			doomedInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		doomedInterruptPanel.icon:SetShown(Player.interrupt)
		doomedInterruptPanel.border:SetShown(Player.interrupt)
		doomedInterruptPanel:SetShown(start and not notInterruptible)
	end
	doomedPanel.icon:SetShown(Player.main)
	doomedPanel.border:SetShown(Player.main)
	doomedCooldownPanel:SetShown(Player.cd)
	doomedExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == 'Doomed' then
		Opt = Doomed
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. name .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Doomed1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. name .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
		InitOpts()
		Azerite:Init()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

function events:UI_ERROR_MESSAGE(errorId)
	if (
	    errorId == 394 or -- pet is rooted
	    errorId == 396 or -- target out of pet range
	    errorId == 400    -- no pet path to target
	) then
		Player.pet_stuck = true
	end
end

APL[SPEC.AFFLICTION].combat_event = function(self, eventType, srcGUID, dstGUID, spellId, ability)
	if srcGUID ~= Player.guid then
		return
	end
	if eventType == 'SPELL_CAST_SUCCESS' then
		if ability == Agony then
			ability:RefreshAura(dstGUID)
		end
		return
	end
end

APL[SPEC.DEMONOLOGY].combat_event = function(self, eventType, srcGUID, dstGUID, spellId, ability)
	if ability == FelFirebolt then
		local pet = summonedPets:Find(srcGUID)
		if pet then
			local unit = pet.active_units[srcGUID]
			if unit then
				if eventType == 'SPELL_CAST_START' then
					pet:CastStart(unit)
				elseif eventType == 'SPELL_CAST_SUCCESS' then
					pet:CastSuccess(unit)
				end
			end
		end
		return
	end
	if srcGUID ~= Player.guid then
		return
	end
	if eventType == 'SPELL_CAST_SUCCESS' then
		if ability == Implosion then
			ability:Implode()
		elseif ability == PowerSiphon then
			ability:Sacrifice()
			ability:Sacrifice()
		elseif ability == HandOfGuldan then
			ability:CastSuccess()
		elseif ability == SummonDemonicTyrant or ability == SummonDarkglare then
			ability.summoning = true
		end
		return
	end
	if dstGUID == Player.guid and ability == DemonicPower then
		if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
			summonedPets.empowered_ends = DemonicPower:Ends()
		elseif eventType == 'SPELL_AURA_REMOVED' then
			summonedPets.empowered_ends = 0
		end
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:Remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:Remove(dstGUID)
		end
		local pet = summonedPets:Find(dstGUID)
		if pet then
			pet:RemoveUnit(dstGUID)
		end
		return
	end
	if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
		if dstGUID == Player.guid then
			Player.last_swing_taken = Player.time
		end
		if Opt.auto_aoe then
			if dstGUID == Player.guid or dstGUID == Player.pet then
				autoAoe:Add(srcGUID, true)
			elseif (srcGUID == Player.guid or srcGUID == Player.pet) and not (missType == 'EVADE' or missType == 'IMMUNE') then
				autoAoe:Add(dstGUID, true)
			end
		end
	end

	local ability = spellId and abilities.bySpellId[spellId]

	if APL[Player.spec].combat_event then
		APL[Player.spec]:combat_event(eventType, srcGUID, dstGUID, spellId, ability)
	end

	if (srcGUID ~= Player.guid and srcGUID ~= Player.pet) then
		return
	end

	if eventType == 'SPELL_SUMMON' then
		local pet = summonedPets:Find(dstGUID)
		if pet then
			pet:AddUnit(dstGUID)
		end
		return
	end

	if srcGUID == Player.pet then
		if Player.pet_stuck and (eventType == 'SPELL_CAST_SUCCESS' or eventType == 'SPELL_DAMAGE' or eventType == 'SWING_DAMAGE') then
			Player.pet_stuck = false
		elseif not Player.pet_stuck and eventType == 'SPELL_CAST_FAILED' and missType == 'No path available' then
			Player.pet_stuck = true
		end
	end

	if not ability then
--[[
		if spellId and type(spellName) == 'string' then
			print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName, spellId))
		end
]]
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_ABSORBED' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UI:UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		if srcGUID == Player.guid or ability.player_triggered then
			Player.last_ability = ability
			ability.last_used = Player.time
			if ability.triggers_gcd then
				Player.previous_gcd[10] = nil
				table.insert(Player.previous_gcd, 1, ability)
			end
			if ability.travel_start then
				ability.travel_start[dstGUID] = Player.time
				if not ability.range_est_start then
					ability.range_est_start = Player.time
				end
			end
			if Opt.previous and doomedPanel:IsVisible() then
				doomedPreviousPanel.ability = ability
				doomedPreviousPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')
				doomedPreviousPanel.icon:SetTexture(ability.icon)
				doomedPreviousPanel:Show()
			end
		end
		if Player.pet_stuck and ability.requires_pet then
			Player.pet_stuck = false
		end
		return
	end
	if eventType == 'SPELL_CAST_FAILED' then
		if ability.requires_pet and missType == 'No path available' then
			Player.pet_stuck = true
		end
		return
	end
	if dstGUID == Player.guid or dstGUID == Player.pet then
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (eventType == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and eventType == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if eventType == 'SPELL_ABSORBED' or eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if ability.travel_start and ability.travel_start[dstGUID] then
			ability.travel_start[dstGUID] = nil
		end
		if ability.range_est_start then
			Target.estimated_range = floor(ability.velocity * (Player.time - ability.range_est_start))
			ability.range_est_start = nil
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and doomedPanel:IsVisible() and ability == doomedPreviousPanel.ability then
			doomedPreviousPanel.border:SetTexture('Interface\\AddOns\\Doomed\\misseffect.blp')
		end
	end
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.last_swing_taken = 0
	Player.pet_stuck = false
	Target.estimated_range = 30
	Player.previous_gcd = {}
	if Player.last_ability then
		Player.last_ability = nil
		doomedPreviousPanel:Hide()
	end
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.travel_start do
			ability.travel_start[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:Clear()
		autoAoe:Update()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	local _, i, equipType, hasCooldown
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
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	doomedPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Target:Update()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
	InnerDemons.next_imp = nil
end

function events:SPELL_UPDATE_COOLDOWN()
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
end

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and powerType == 'SOUL_SHARDS' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName, castId, spellId)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
	if srcName == 'player' and spellId == HandOfGuldan.spellId then
		HandOfGuldan.cast_shards = Player.soul_shards
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:AZERITE_ESSENCE_UPDATE()
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:PLAYER_ENTERING_WORLD()
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
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
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

doomedPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	doomedPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local ChatFrame_OnHyperlinkShow_Original = ChatFrame_OnHyperlinkShow
function ChatFrame_OnHyperlinkShow(chatFrame, link, ...)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		return BattleTagInviteFrame_Show(linkData)
	end
	return ChatFrame_OnHyperlinkShow_Original(chatFrame, link, ...)
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
	print('Doomed -', desc .. ':', opt_view, ...)
end

function SlashCmdList.Doomed(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
			else
				Opt.snap = false
				doomedPanel:ClearAllPoints()
			end
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
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra/Pet cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000pet 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
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
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra/pet cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000pet|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
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
		return Status('Show the Doomed UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use Doomed for cooldown management', Opt.cooldown)
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
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Affliction specialization', not Opt.hide.affliction)
			end
			if startsWith(msg[2], 'dem') then
				Opt.hide.demonology = not Opt.hide.demonology
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Demonology specialization', not Opt.hide.demonology)
			end
			if startsWith(msg[2], 'des') then
				Opt.hide.destruction = not Opt.hide.destruction
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Destruction specialization', not Opt.hide.destruction)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000aff|r/|cFFFFD000demo|r/|cFFFFD000dest|r')
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
		return Status('Show Demonology summoned pet counter (topleft)', Opt.pet_count == 'imps' and 'Wild Imps only' or Opt.pet_count)
	end
	if startsWith(msg[1], 'tyr') then
		if msg[2] then
			Opt.tyrant = msg[2] == 'on'
		end
		return Status('Show Demonology Demonic Tyrant power/remains (topright)', Opt.tyrant)
	end
	if msg[1] == 'reset' then
		doomedPanel:ClearAllPoints()
		doomedPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print('Doomed (version: |cFFFFD000' .. GetAddOnMetadata('Doomed', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Doomed UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Doomed UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000pet|r/|cFFFFD000glow|r - adjust the scale of the Doomed UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Doomed UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000pet|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Doomed UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Doomed for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000aff|r/|cFFFFD000demo|r/|cFFFFD000dest|r - toggle disabling Doomed for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'healthstone |cFF00C000on|r/|cFFC00000off|r - show Create Healthstone reminder out of combat',
		'pets |cFF00C000on|r/|cFFFFD000imps|r/|cFFC00000off|r  - Show Demonology summoned pet counter (topleft)',
		'tyrant |cFF00C000on|r/|cFFC00000off|r  - Show Demonology Demonic Tyrant power/remains (topright)',
		'|cFFFFD000reset|r - reset the location of the Doomed UI to default',
	} do
		print('  ' .. SLASH_Doomed1 .. ' ' .. cmd)
	end
	print('Need to threaten with the wrath of doom? You can still use |cFFFFD000/wrath|r!')
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
