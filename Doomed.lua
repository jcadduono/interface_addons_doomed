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

local function InitializeOpts()
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
		healthstone = true,
	})
end

-- specialization constants
local SPEC = {
	NONE = 0,
	AFFLICTION = 1,
	DEMONOLOGY = 2,
	DESTRUCTION = 3,
}

local events, glows = {}, {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	gcd = 1.5,
	health = 0,
	health_max = 0,
	mana = 0,
	mana_max = 0,
	mana_regen = 0,
	soul_shards = 0,
	soul_shards_max = 0,
	previous_gcd = {},-- list of previous GCD abilities
	equipped = {-- items equipped with special effects
		WilfredsSigilOfSuperiorSummoning = false
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
doomedPanel.swipe = CreateFrame('Cooldown', nil, doomedPanel, 'CooldownFrameTemplate')
doomedPanel.swipe:SetAllPoints(doomedPanel)
doomedPanel.dimmer = doomedPanel:CreateTexture(nil, 'BORDER')
doomedPanel.dimmer:SetAllPoints(doomedPanel)
doomedPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
doomedPanel.dimmer:Hide()
doomedPanel.text = doomedPanel:CreateFontString(nil, 'OVERLAY')
doomedPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
doomedPanel.text:SetPoint('TOPLEFT', doomedPanel, 'TOPLEFT', 4, -4)
doomedPanel.targets = doomedPanel:CreateFontString(nil, 'OVERLAY')
doomedPanel.targets:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
doomedPanel.targets:SetPoint('BOTTOMRIGHT', doomedPanel, 'BOTTOMRIGHT', -1.5, 3)
doomedPanel.button = CreateFrame('Button', 'doomedPanelButton', doomedPanel)
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

-- Start Auto AoE

local targetModes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.AFFLICTION] = {
		{1, ''},
		{2, '2+'},
		{3, '3+'},
		{5, '5+'}
	},
	[SPEC.DEMONOLOGY] = {
		{1, ''},
		{2, '2+'},
		{3, '3+'},
		{5, '5+'}
	},
	[SPEC.DESTRUCTION] = {
		{1, ''},
		{2, '2+'},
		{3, '3+'},
		{5, '5+'}
	}
}

local function SetTargetMode(mode)
	if mode == targetMode then
		return
	end
	targetMode = min(mode, #targetModes[Player.spec])
	Player.enemies = targetModes[Player.spec][targetMode][1]
	doomedPanel.targets:SetText(targetModes[Player.spec][targetMode][2])
end
Doomed_SetTargetMode = SetTargetMode

function ToggleTargetMode()
	local mode = targetMode + 1
	SetTargetMode(mode > #targetModes[Player.spec] and 1 or mode)
end
Doomed_ToggleTargetMode = ToggleTargetMode

local function ToggleTargetModeReverse()
	local mode = targetMode - 1
	SetTargetMode(mode < 1 and #targetModes[Player.spec] or mode)
end
Doomed_ToggleTargetModeReverse = ToggleTargetModeReverse

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:add(guid, update)
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
		self:update()
	end
end

function autoAoe:remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:update()
	end
end

function autoAoe:clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #targetModes[Player.spec], 1, -1 do
		if count >= targetModes[Player.spec][i][1] then
			SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function autoAoe:purge()
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
		self:update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability.add(spellId, buff, player, spellId2)
	local ability = {
		spellId = spellId,
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
		max_range = 40,
		velocity = 0,
		last_used = 0,
		auraTarget = buff == 'pet' and 'pet' or buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, Ability)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end


function Ability:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function Ability:usable()
	if not self.known then
		return false
	end
	if self:cost() > Player.mana then
		return false
	end
	if self:shardCost() > Player.soul_shards then
		return false
	end
	if self.requires_pet and not Player.pet_active then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	return self:ready()
end

function Ability:remains()
	if self:traveling() or self:casting() then
		return self:duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:refreshable()
	if self.buff_duration > 0 then
		return self:remains() < self:duration() * 0.3
	end
	return self:down()
end

function Ability:up()
	return self:remains() > 0
end

function Ability:down()
	return self:remains() <= 0
end

function Ability:setVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if Player.time - self.travel_start[Target.guid] < self.max_range / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:travelTime()
	return Target.estimated_range / self.velocity
end

function Ability:ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:up() and 1 or 0
end

function Ability:cooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:cost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana_max) or 0
end

function Ability:shardCost()
	return self.shard_cost
end

function Ability:charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:chargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:fullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:maxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return Player.ability_casting == self
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:castRegen()
	return Player.mana_regen * self:castTime() - self:cost()
end

function Ability:tickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:wontCapMana(reduction)
	return (Player.mana + self:castRegen()) < (Player.mana_max - (reduction or 5))
end

function Ability:previous(n)
	if n and n > 1 then
		return Player.previous_gcd[n] == self
	end
	if self:casting() or self:channeling() then
		return true
	end
	return Player.previous_gcd[1] == self or Player.last_ability == self
end

function Ability:azeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:autoAoe(removeUnaffected, trigger)
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

function Ability:recordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:updateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:clear()
		end
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:removeAura(guid)
			end
		end
	end
end

function trackAuras:remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:removeAura(guid)
	end
end

function Ability:trackAuras()
	self.aura_targets = {}
end

function Ability:applyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:refreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(guid)
		return
	end
	local remains = aura.expires - Player.time
	local duration = self:duration()
	aura.expires = Player.time + min(duration * 1.3, remains + duration)
end

function Ability:removeAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Warlock Abilities
---- Multiple Specializations
local CreateHealthstone = Ability.add(6201, true, true)
CreateHealthstone.mana_cost = 2
local DrainLife = Ability.add(234153, false, true)
DrainLife.mana_cost = 3
DrainLife.buff_duration = 6
DrainLife.tick_interval = 1
DrainLife.hasted_duration = true
DrainLife.hasted_ticks = true
local SpellLock = Ability.add(119910, false, true)
SpellLock.cooldown_duration = 24
SpellLock.player_triggered = true
------ Talents
local GrimoireOfSacrifice = Ability.add(108503, true, true, 196099)
GrimoireOfSacrifice.buff_duration = 3600
GrimoireOfSacrifice.cooldown_duration = 30
local MortalCoil = Ability.add(6789, false, true)
MortalCoil.mana_cost = 2
MortalCoil.buff_duration = 3
MortalCoil.cooldown_duration = 45
MortalCoil:setVelocity(24)
------ Procs
local SoulConduit = Ability.add(215941, true, true)
------ Permanent Pets
local SummonImp = Ability.add(688, false, true)
SummonImp.shard_cost = 1
SummonImp.pet_family = 'Imp'
local SummonFelImp = Ability.add(112866, false, true, 219424)
SummonFelImp.shard_cost = 1
SummonFelImp.pet_family = 'Fel Imp'
local SummonFelhunter = Ability.add(691, false, true)
SummonFelhunter.shard_cost = 1
SummonFelhunter.pet_family = 'Felhunter'
local SummonObserver = Ability.add(112869, false, true, 219450)
SummonObserver.shard_cost = 1
SummonObserver.pet_family = 'Observer'
local SummonVoidwalker = Ability.add(697, false, true)
SummonVoidwalker.shard_cost = 1
SummonVoidwalker.pet_family = 'Voidwalker'
local SummonVoidlord = Ability.add(112867, false, true, 219445)
SummonVoidlord.shard_cost = 1
SummonVoidlord.pet_family = 'Voidlord'
local SummonSuccubus = Ability.add(712, false, true)
SummonSuccubus.shard_cost = 1
SummonSuccubus.pet_family = 'Succubus'
local SummonShivarra = Ability.add(112868, false, true, 219436)
SummonShivarra.shard_cost = 1
SummonShivarra.pet_family = 'Shivarra'
local SummonFelguard = Ability.add(30146, false, true)
SummonFelguard.shard_cost = 1
SummonFelguard.pet_family = 'Felguard'
local SummonWrathguard = Ability.add(112870, false, true, 219467)
SummonWrathguard.shard_cost = 1
SummonWrathguard.pet_family = 'Wrathguard'
---- Affliction
local Agony = Ability.add(980, false, true)
Agony.mana_cost = 1
Agony.buff_duration = 18
Agony.tick_interval = 2
Agony.hasted_ticks = true
Agony:trackAuras()
local Corruption = Ability.add(172, false, true, 146739)
Corruption.mana_cost = 1
Corruption.buff_duration = 14
Corruption.tick_interval = 2
Corruption.hasted_ticks = true
Corruption:trackAuras()
local SeedOfCorruption = Ability.add(27243, false, true, 27285)
SeedOfCorruption.shard_cost = 1
SeedOfCorruption.buff_duration = 12
SeedOfCorruption:setVelocity(30)
SeedOfCorruption.hasted_duration = true
SeedOfCorruption:autoAoe(true)
SeedOfCorruption:trackAuras()
local ShadowBolt = Ability.add(232670, false, true)
ShadowBolt.mana_cost = 2
ShadowBolt:setVelocity(25)
local SummonDarkglare = Ability.add(205180, false, true)
SummonDarkglare.mana_cost = 2
SummonDarkglare.cooldown_duration = 180
SummonDarkglare.summon_count = 1
local UnstableAffliction = Ability.add(30108, false, true)
UnstableAffliction.shard_cost = 1
UnstableAffliction.buff_duration = 8
UnstableAffliction.tick_interval = 2
UnstableAffliction.hasted_duration = true
UnstableAffliction.hasted_ticks = true
UnstableAffliction[1] = Ability.add(233490, false, true)
UnstableAffliction[2] = Ability.add(233496, false, true)
UnstableAffliction[3] = Ability.add(233497, false, true)
UnstableAffliction[4] = Ability.add(233498, false, true)
UnstableAffliction[5] = Ability.add(233499, false, true)
------ Talents
local AbsoluteCorruption = Ability.add(196103, false, true)
local CreepingDeath = Ability.add(264000, false, true)
local DarkSoulMisery = Ability.add(113860, true, true)
DarkSoulMisery.buff_duration = 20
DarkSoulMisery.cooldown_duration = 120
local Deathbolt = Ability.add(264106, false, true)
Deathbolt.mana_cost = 2
Deathbolt.cooldown_duration = 30
Deathbolt:setVelocity(35)
local DrainSoul = Ability.add(198590, false, true)
DrainSoul.mana_cost = 1
DrainSoul.buff_duration = 5
DrainSoul.tick_interval = 1
DrainSoul.hasted_duration = true
DrainSoul.hasted_ticks = true
local Haunt = Ability.add(48181, false, true)
Haunt.mana_cost = 2
Haunt.buff_duration = 15
Haunt.cooldown_duration = 15
Haunt:setVelocity(40)
local Nightfall = Ability.add(108558, false, true, 264571)
Nightfall.buff_duration = 12
local PhantomSingularity = Ability.add(205179, false, true, 205246)
PhantomSingularity.buff_duration = 16
PhantomSingularity.cooldown_duration = 45
PhantomSingularity.tick_interval = 2
PhantomSingularity.hasted_duration = true
PhantomSingularity.hasted_ticks = true
PhantomSingularity:autoAoe(false, 'periodic')
local ShadowEmbrace = Ability.add(32388, false, true, 32390)
ShadowEmbrace.buff_duration = 10
local Shadowfury = Ability.add(30283, false, true)
Shadowfury.cooldown_duration = 60
Shadowfury.buff_duration = 3
local SiphonLife = Ability.add(63106, false, true)
SiphonLife.buff_duration = 15
SiphonLife.tick_interval = 3
SiphonLife.hasted_ticks = true
SiphonLife:trackAuras()
local SowTheSeeds = Ability.add(196226, false, true)
local VileTaint = Ability.add(278350, false, true)
VileTaint.shard_cost = 1
VileTaint.buff_duration = 10
VileTaint.cooldown_duration = 20
VileTaint.tick_interval = 2
VileTaint.hasted_ticks = true
VileTaint:autoAoe(true)
local WritheInAgony = Ability.add(196102, false, true)
---- Demonology
------ Base Abilities
local CallDreadstalkers = Ability.add(104316, false, true)
CallDreadstalkers.buff_duration = 12
CallDreadstalkers.cooldown_duration = 20
CallDreadstalkers.shard_cost = 2
CallDreadstalkers.summon_count = 2
local Demonbolt = Ability.add(264178, false, true)
Demonbolt.mana_cost = 2
Demonbolt.shard_cost = -2
Demonbolt:setVelocity(35)
local HandOfGuldan = Ability.add(105174, false, true, 86040)
HandOfGuldan.shard_cost = 1
HandOfGuldan:autoAoe(true)
local Implosion = Ability.add(196277, false, true, 196278)
Implosion.mana_cost = 2
Implosion:autoAoe()
local ShadowBoltDemo = Ability.add(686, false, true)
ShadowBoltDemo.mana_cost = 2
ShadowBoltDemo.shard_cost = -1
ShadowBoltDemo:setVelocity(20)
local SummonDemonicTyrant = Ability.add(265187, true, true)
SummonDemonicTyrant.buff_duration = 15
SummonDemonicTyrant.cooldown_duration = 90
SummonDemonicTyrant.mana_cost = 2
SummonDemonicTyrant.summon_count = 1
------ Pet Abilities
local AxeToss = Ability.add(89766, false, true, 119914)
AxeToss.cooldown_duration = 30
AxeToss.requires_pet = true
AxeToss.triggers_gcd = false
AxeToss.player_triggered = true
local Felstorm = Ability.add(89751, 'pet', true, 89753)
Felstorm.buff_duration = 5
Felstorm.cooldown_duration = 30
Felstorm.tick_interval = 1
Felstorm.hasted_duration = true
Felstorm.hasted_ticks = true
Felstorm.requires_pet = true
Felstorm.triggers_gcd = false
Felstorm:autoAoe()
local FelFirebolt = Ability.add(104318, false, false)
FelFirebolt.triggers_gcd = false
local LegionStrike = Ability.add(30213, false, true)
LegionStrike.requires_pet = true
LegionStrike:autoAoe()
------ Talents Abilities
local BilescourgeBombers = Ability.add(267211, false, true, 267213)
BilescourgeBombers.buff_duration = 6
BilescourgeBombers.cooldown_duration = 30
BilescourgeBombers.shard_cost = 2
BilescourgeBombers:autoAoe(true)
local DemonicCalling = Ability.add(205145, true, true, 205146)
DemonicCalling.buff_duration = 20
local DemonicConsumption = Ability.add(267215, false, true)
local DemonicStrength = Ability.add(267171, 'pet', true)
DemonicStrength.buff_duration = 20
DemonicStrength.cooldown_duration = 60
local Doom = Ability.add(603, false, true)
Doom.mana_cost = 1
Doom.buff_duration = 30
Doom.tick_interval = 30
Doom.hasted_duration = true
local Dreadlash = Ability.add(264078, false, true)
local FromTheShadows = Ability.add(267170, false, true, 270569)
FromTheShadows.buff_duration = 12
local InnerDemons = Ability.add(267216, false, true)
local GrimoireFelguard = Ability.add(111898, false, true)
GrimoireFelguard.cooldown_duration = 120
GrimoireFelguard.shard_cost = 1
GrimoireFelguard.summon_count = 1
local NetherPortal = Ability.add(267217, true, true, 267218)
NetherPortal.buff_duration = 15
NetherPortal.cooldown_duration = 180
NetherPortal.shard_cost = 1
local PowerSiphon = Ability.add(264130, false, true)
PowerSiphon.cooldown_duration = 30
local SoulStrike = Ability.add(264057, false, true, 267964)
SoulStrike.cooldown_duration = 10
SoulStrike.shard_cost = -1
SoulStrike.requires_pet = true
local SummonVilefiend = Ability.add(264119, false, true)
SummonVilefiend.buff_duration = 15
SummonVilefiend.cooldown_duration = 45
SummonVilefiend.shard_cost = 1
SummonVilefiend.summon_count = 1
------ Procs
local DemonicCore = Ability.add(267102, true, true, 264173)
DemonicCore.buff_duration = 20
local DemonicPower = Ability.add(265273, true, true)
DemonicPower.buff_duration = 15
-- Azerite Traits
local BalefulInvocation = Ability.add(287059, true, true)
local CascadingCalamity = Ability.add(275372, true, true, 275378)
CascadingCalamity.buff_duration = 15
local ExplosivePotential = Ability.add(275395, true, true, 275398)
ExplosivePotential.buff_duration = 15
local InevitableDemise = Ability.add(273521, true, true, 273522)
local PandemicInvocation = Ability.add(289364, true, true)
local ShadowsBite = Ability.add(272944, true, true, 272945)
ShadowsBite.buff_duration = 8
-- Racials

-- Trinket Effects

-- End Abilities

-- Start Summoned Pets

local SummonedPet, Pet = {}, {}
SummonedPet.__index = SummonedPet
local summonedPets = {
	all = {}
}

function summonedPets:find(guid)
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	return unitId and self.byUnitId[tonumber(unitId)]
end

function summonedPets:purge()
	local _, pet, guid, unit
	for _, pet in next, self.known do
		for guid, unit in next, pet.active_units do
			if unit.expires <= Player.time then
				pet.active_units[guid] = nil
			end
		end
	end
end

function summonedPets:count()
	local _, pet, guid, unit
	local count = 0
	for _, pet in next, self.known do
		count = count + pet:count()
	end
	return count
end

function summonedPets:extend(seconds)
	local _, pet, guid, unit
	for _, pet in next, self.known do
		for guid, unit in next, pet.active_units do
			if unit.expires > Player.time then
				unit.expires = unit.expires + seconds
			end
		end
	end
end

function summonedPets:empowered()
	return Player.time < (self.empowered_ends or 0)
end

function summonedPets:empoweredRemains()
	return max((self.empowered_ends or 0) - Player.time, 0)
end

function SummonedPet.add(unitId, duration, unitId2)
	local pet = {
		unitId = unitId,
		unitId2 = unitId2,
		duration = duration,
		active_units = {},
		known = false,
	}
	setmetatable(pet, SummonedPet)
	summonedPets.all[#summonedPets.all + 1] = pet
	return pet
end

function SummonedPet:remains()
	local expires_max, guid, unit = 0
	if self.summon_spell and self.summon_spell:casting() then
		expires_max = self.duration
	end
	for guid, unit in next, self.active_units do
		if unit.expires > expires_max then
			expires_max = unit.expires
		end
	end
	return max(expires_max - Player.time - Player.execute_remains, 0)
end

function SummonedPet:up()
	return self:remains() > 0
end

function SummonedPet:down()
	return self:remains() <= 0
end

function SummonedPet:count()
	local count, guid, unit = 0
	if self.summon_spell and self.summon_spell:casting() then
		count = count + self.summon_spell.summon_count
	end
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time > Player.execute_remains then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:expiring(seconds)
	local count, guid, unit = 0
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time <= (seconds or Player.execute_remains) then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:addUnit(guid)
	local unit = {
		guid = guid,
		expires = Player.time + self.duration,
	}
	self.active_units[guid] = unit
	return unit
end

function SummonedPet:removeUnit(guid)
	if self.active_units[guid] then
		self.active_units[guid] = nil
	end
end

-- Summoned Pets
Pet.Darkglare = SummonedPet.add(103673, 20)
Pet.Darkglare.summon_spell = SummonDarkglare
Pet.DemonicTyrant = SummonedPet.add(135002, 15)
Pet.DemonicTyrant.summon_spell = SummonDemonicTyrant
Pet.Dreadstalker = SummonedPet.add(98035, 12)
Pet.Dreadstalker.summon_spell = CallDreadstalkers
Pet.Felguard = SummonedPet.add(17252, 15)
Pet.Felguard.summon_spell = GrimoireFelguard
Pet.Vilefiend = SummonedPet.add(135816, 15)
Pet.Vilefiend.summon_spell = SummonVilefiend
Pet.WildImp = SummonedPet.add(55659, 20, 143622)
---- Nether Portal / Inner Demons
Pet.Bilescourge = SummonedPet.add(136404, 15)
Pet.Darkhound = SummonedPet.add(136408, 15)
Pet.EredarBrute = SummonedPet.add(136405, 15)
Pet.EyeOfGuldan = SummonedPet.add(136401, 15)
Pet.IllidariSatyr = SummonedPet.add(136398, 15)
Pet.PrinceMalchezaar = SummonedPet.add(136397, 15)
Pet.Shivarra = SummonedPet.add(136406, 15)
Pet.Urzul = SummonedPet.add(136402, 15)
Pet.ViciousHellhound = SummonedPet.add(136399, 15)
Pet.VoidTerror = SummonedPet.add(136403, 15)
Pet.Wrathguard = SummonedPet.add(136407, 15)
-- End Summoned Pets

-- Start Inventory Items

local InventoryItem, inventoryItems = {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem.add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon
	}
	setmetatable(item, InventoryItem)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:cooldown()
	local startTime, duration = GetItemCooldown(self.itemId)
	return startTime == 0 and 0 or duration - (Player.time - startTime)
end

function InventoryItem:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function InventoryItem:usable(seconds)
	if self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

-- Inventory Items
local Healthstone = InventoryItem.add(5512)
Healthstone.created_by = CreateHealthstone
Healthstone.max_charges = 3
local FlaskOfEndlessFathoms = InventoryItem.add(152693)
FlaskOfEndlessFathoms.buff = Ability.add(251837, true, true)
local BattlePotionOfIntellect = InventoryItem.add(163222)
BattlePotionOfIntellect.buff = Ability.add(279151, true, true)
BattlePotionOfIntellect.buff.triggers_gcd = false
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:initialize()
	self.locations = {}
	self.traits = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:update()
	local _, loc, tinfo, tslot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			tinfo = C_AzeriteEmpoweredItem.GetAllTierInfo(loc)
			for _, tslot in next, tinfo do
				if tslot.azeritePowerIDs then
					for _, pid in next, tslot.azeritePowerIDs do
						if C_AzeriteEmpoweredItem.IsPowerSelected(loc, pid) then
							self.traits[pid] = 1 + (self.traits[pid] or 0)
							pinfo = C_AzeriteEmpoweredItem.GetPowerInfo(pid)
							if pinfo and pinfo.spellID then
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
end

-- End Azerite Trait API

-- Start Helpful Functions

local function HealthPct()
	return Player.health / Player.health_max * 100
end

local function ManaDeficit()
	return Player.mana_max - Player.mana
end

local function ManaTimeToMax()
	local deficit = Player.mana_max - Player.mana
	if deficit <= 0 then
		return 0
	end
	return deficit / Player.mana_regen
end

local function TimeInCombat()
	if Player.combat_start > 0 then
		return Player.time - Player.combat_start
	end
	if Player.ability_casting then
		return 0.1
	end
	return 0
end

local function BloodlustActive()
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

function GetPetActive()
	return (IsFlying() or (UnitExists('pet') and not (UnitIsDead('pet') or Player.pet_stuck)) or
		SummonFelhunter:up() or SummonObserver:up() or
		SummonImp:up() or SummonFelImp:up() or
		SummonVoidwalker:up() or SummonVoidlord:up() or
		SummonSuccubus:up() or SummonShivarra:up() or
		SummonFelguard:up() or SummonWrathguard:up())
end

-- End Helpful Functions

-- Start Ability Modifications

function Implosion:usable()
	return Player.imp_count > 0 and Ability.usable(self)
end

function PowerSiphon:usable()
	return Player.imp_count > 0 and Ability.usable(self)
end

function Corruption:remains()
	if SeedOfCorruption:up() or SeedOfCorruption:previous() then
		return self:duration()
	end
	return Ability.remains(self)
end

function UnstableAffliction:stack()
	return (
		(UnstableAffliction[1]:up() and 1 or 0) +
		(UnstableAffliction[2]:up() and 1 or 0) +
		(UnstableAffliction[3]:up() and 1 or 0) +
		(UnstableAffliction[4]:up() and 1 or 0) +
		(UnstableAffliction[5]:up() and 1 or 0))
end

function UnstableAffliction:remains()
	return max(UnstableAffliction[1]:remains(), UnstableAffliction[2]:remains(), UnstableAffliction[3]:remains(), UnstableAffliction[4]:remains(), UnstableAffliction[5]:remains())
end

function UnstableAffliction:lowest()
	local ua = UnstableAffliction[1]
	local lowest = Ability.remains(ua)
	local remains, i
	for i = 2, 5 do
		remains = Ability.remains(ua)
		if remains > 0 and remains < lowest then
			ua = UnstableAffliction[i]
			lowest = remains
		end
	end
	return ua, lowest
end

function UnstableAffliction:lowestRemains()
	local _, remains = UnstableAffliction:lowest()
	return remains
end

function UnstableAffliction:next()
	local i
	for i = 1, 5 do
		if not Ability.up(UnstableAffliction[i]) then
			return UnstableAffliction[i]
		end
	end
	return UnstableAffliction:lowest()
end

UnstableAffliction[1].remains = function(self)
	if UnstableAffliction:casting() and UnstableAffliction:next() == self then
		return UnstableAffliction:duration()
	end
	return Ability.remains(self)
end
UnstableAffliction[2].remains = UnstableAffliction[1].remains
UnstableAffliction[3].remains = UnstableAffliction[1].remains
UnstableAffliction[4].remains = UnstableAffliction[1].remains
UnstableAffliction[5].remains = UnstableAffliction[1].remains

local function SummonPetUp(self)
	if self:casting() then
		return true
	end
	if UnitIsDead('pet') or Player.pet_stuck then
		return false
	end
	return UnitCreatureFamily('pet') == self.pet_family
end

SummonImp.up = SummonPetUp
SummonFelImp.up = SummonPetUp
SummonFelhunter.up = SummonPetUp
SummonObserver.up = SummonPetUp
SummonVoidwalker.up = SummonPetUp
SummonVoidlord.up = SummonPetUp
SummonSuccubus.up = SummonPetUp
SummonShivarra.up = SummonPetUp
SummonFelguard.up = SummonPetUp
SummonWrathguard.up = SummonPetUp

function HandOfGuldan:shardCost()
	return min(max(Player.soul_shards, 1), 3)
end

--[[
function DemonicCore:remains()
	if Pet.Dreadstalker:expiring() > 0 then
		return self:duration()
	end
	return Ability.remains(self)
end

function DemonicCore:stack()
	local count = Ability.stack(self)
	count = count + Pet.Dreadstalker:expiring()
	return min(count, 4)
end
]]

function CallDreadstalkers:shardCost()
	local cost = self.shard_cost
	if DemonicCalling:up() then
		cost = cost - 1
	end
	return cost
end

function SummonDemonicTyrant:shardCost()
	if BalefulInvocation.known then
		return -5
	end
	return self.shard_cost
end

function SpellLock:usable()
	if not (SummonFelhunter:up() or SummonObserver:up()) then
		return false
	end
	return Ability.usable(self)
end

function AxeToss:usable()
	if not Target.stunnable or not (SummonFelguard:up() or SummonWrathguard:up()) then
		return false
	end
	return Ability.usable(self)
end

-- End Ability Modifications

-- Start Summoned Pet Modifications

function Pet.WildImp:addUnit(guid)
	local unit = SummonedPet.addUnit(self, guid)
	unit.energy = 100
	unit.cast_end = 0
	return unit
end

function Pet.WildImp:getUnit(guid)
	return self.active_units[guid]
end

function Pet.WildImp:count()
	if DemonicConsumption.known and SummonDemonicTyrant:casting() then
		return 0
	end
	return SummonedPet.count(self)
end

function Pet.WildImp:remains()
	if DemonicConsumption.known and SummonDemonicTyrant:casting() then
		return 0
	end
	return SummonedPet.remains(self)
end

function Pet.WildImp:unitRemains(unit)
	if DemonicConsumption.known and SummonDemonicTyrant:casting() then
		return 0
	end
	local energy, remains = unit.energy, 0
	if unit.cast_end > 0 then
		if summonedPets:empowered() then
			remains = summonedPets:empoweredRemains()
		else
			energy = energy - 20
			remains = unit.cast_end - Player.time
		end
		remains = remains + (energy / 20 * FelFirebolt:castTime())
	else
		remains = unit.expires - Player.time
	end
	return max(remains, 0)
end

function Pet.WildImp:impsIn(seconds)
	local count, guid, unit = 0
	for guid, unit in next, self.active_units do
		if self:unitRemains(unit) > (Player.execute_remains + seconds) then
			count = count + 1
		end
	end
	return count
end

function Pet.WildImp:castStart(unit)
	unit.cast_end = Player.time + FelFirebolt:castTime()
end

function Pet.WildImp:castSuccess(unit)
	if not summonedPets:empowered() then
		unit.energy = unit.energy - 20
	end
	if unit.energy <= 0 then
		self.active_units[unit.guid] = nil
		return
	end
	unit.cast_end = 0
end

function Pet.WildImp:sacrifice()
	local expires_min, guid, unit, sacrifice = Player.time + 60
	for guid, unit in next, self.active_units do
		if unit.expires < expires_min then
			expires_min = unit.expires
			sacrifice = guid
		end
	end
	if sacrifice then
		self.active_units[sacrifice] = nil
	end
end

function Pet.WildImp:implode()
	local guid
	for guid in next, self.active_units do
		self.active_units[guid] = nil
	end
end

-- End Summoned Pet Modifications

local function UseCooldown(ability, overwrite, always)
	if always or (Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite)) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite, always)
	if always or (not Player.extra or overwrite) then
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
	if TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/summon_pet
actions.precombat+=/grimoire_of_sacrifice,if=talent.grimoire_of_sacrifice.enabled
actions.precombat+=/snapshot_stats
actions.precombat+=/potion
actions.precombat+=/seed_of_corruption,if=spell_targets.seed_of_corruption_aoe>=3
actions.precombat+=/haunt
actions.precombat+=/shadow_bolt,if=!talent.haunt.enabled&spell_targets.seed_of_corruption_aoe<3
]]
		if Opt.healthstone and Healthstone:charges() == 0 and CreateHealthstone:usable() then
			return CreateHealthstone
		end
		if GrimoireOfSacrifice.known then
			if GrimoireOfSacrifice:remains() < 300 then
				if Player.pet_active then
					return GrimoireOfSacrifice
				else
					return SummonImp
				end
			end
		elseif not Player.pet_active then
			return SummonImp
		end
		if Opt.pot and Target.boss then
			if FlaskOfEndlessFathoms:usable() and FlaskOfEndlessFathoms.buff:remains() < 300 then
				UseCooldown(FlaskOfEndlessFathoms)
			end
			if BattlePotionOfIntellect:usable() then
				UseCooldown(BattlePotionOfIntellect)
			end
		end
		if Player.enemies >= 3 and SeedOfCorruption:usable() and SeedOfCorruption:down() then
			return SeedOfCorruption
		end
		if Haunt.known then
			if Haunt:usable() then
				return Haunt
			end
		elseif Player.enemies < 3 and ShadowBolt:usable() then
			return ShadowBolt
		end
		
	else
		if GrimoireOfSacrifice.known then
			if GrimoireOfSacrifice:remains() < 300 then
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
actions+=/haunt,if=spell_targets.seed_of_corruption_aoe<=2+raid_event.invulnerable.up
actions+=/summon_darkglare,if=dot.agony.ticking&dot.corruption.ticking&(buff.active_uas.stack=5|soul_shard=0)&(!talent.phantom_singularity.enabled|dot.phantom_singularity.remains)&(!talent.deathbolt.enabled|cooldown.deathbolt.remains<=gcd|!cooldown.deathbolt.remains|spell_targets.seed_of_corruption_aoe>1+raid_event.invulnerable.up)
actions+=/deathbolt,if=cooldown.summon_darkglare.remains&spell_targets.seed_of_corruption_aoe=1+raid_event.invulnerable.up
actions+=/agony,target_if=min:dot.agony.remains,if=remains<=gcd+action.shadow_bolt.execute_time&target.time_to_die>8
actions+=/unstable_affliction,target_if=!contagion&target.time_to_die<=8
actions+=/drain_soul,target_if=min:debuff.shadow_embrace.remains,cancel_if=ticks_remain<5,if=talent.shadow_embrace.enabled&variable.maintain_se&debuff.shadow_embrace.remains&debuff.shadow_embrace.remains<=gcd*2
actions+=/shadow_bolt,target_if=min:debuff.shadow_embrace.remains,if=talent.shadow_embrace.enabled&variable.maintain_se&debuff.shadow_embrace.remains&debuff.shadow_embrace.remains<=execute_time*2+travel_time&!action.shadow_bolt.in_flight
actions+=/phantom_singularity,target_if=max:target.time_to_die,if=time>35&target.time_to_die>16*spell_haste
actions+=/vile_taint,target_if=max:target.time_to_die,if=time>15&target.time_to_die>=10
actions+=/unstable_affliction,target_if=min:contagion,if=!variable.use_seed&soul_shard=5
actions+=/seed_of_corruption,if=variable.use_seed&soul_shard=5
actions+=/call_action_list,name=dots
actions+=/phantom_singularity,if=time<=35
actions+=/vile_taint,if=time<15
actions+=/dark_soul,if=cooldown.summon_darkglare.remains<10&dot.phantom_singularity.remains|target.time_to_die<20+gcd|spell_targets.seed_of_corruption_aoe>1+raid_event.invulnerable.up
actions+=/berserking
actions+=/call_action_list,name=spenders
actions+=/call_action_list,name=fillers
]]
	local apl
	Player.use_seed = (SowTheSeeds.known and Player.enemies >= 3) or (SiphonLife.known and Player.enemies >= 5) or Player.enemies >= 8
	if CascadingCalamity.known and (DrainSoul.known or (Deathbolt.known and Deathbolt:cooldown() <= Player.gcd)) then
		Player.padding = Player.gcd
	else
		Player.padding = ShadowBolt:castTime() * (CascadingCalamity.known and 1 or 0)
	end
	Player.maintain_se = (Player.enemies <= 1 and 1 or 0) + (WritheInAgony.known and 1 or 0) + (AbsoluteCorruption.known and 2 or 0) + (WritheInAgony.known and SowTheSeeds.known and Player.enemies > 2 and 1 or 0) + (SiphonLife.known and not CreepingDeath.known and not DrainSoul.known and 1 or 0)
	apl = self:cooldowns()
	if apl then return apl end
	if DrainSoul:usable() and Target.timeToDie <= Player.gcd and Player.soul_shards < 5 then
		return DrainSoul
	end
	if Haunt:usable() and Player.enemies <= 2 then
		return Haunt
	end
	if SummonDarkglare:usable() and Agony:up() and Corruption:up() and (UnstableAffliction:stack() == 5 or Player.soul_shards == 0) and (not PhantomSingularity.known or PhantomSingularity:up()) and (not Deathbolt.known or Deathbolt:cooldown() <= Player.gcd or Player.enemies > 1) then
		UseCooldown(SummonDarkglare)
	end
	if Deathbolt:usable() and not SummonDarkglare:ready() and Player.enemies == 1 then
		return Deathbolt
	end
	if Agony:usable() and Agony:remains() <= Player.gcd + ShadowBolt:castTime() and Target.timeToDie > 8 then
		return Agony
	end
	if UnstableAffliction:usable() and Target.timeToDie <= 8 then
		return UnstableAffliction
	end
	if ShadowEmbrace.known and Player.maintain_se and ShadowEmbrace:up() then
		if DrainSoul:usable() and ShadowEmbrace:remains() <= (Player.gcd * 2) then
			return DrainSoul
		end
		if ShadowBolt:usable() and ShadowEmbrace:remains() <= (ShadowBolt:castTime() * 2 + ShadowBolt:travelTime()) and not ShadowBolt:traveling() then
			return DrainSoul
		end
	end
	if PhantomSingularity:usable() and TimeInCombat() > 35 and Target.timeToDie > PhantomSingularity:duration() then
		UseCooldown(PhantomSingularity)
	end
	if VileTaint:usable() and TimeInCombat() > 15 and Target.timeToDie >= 10 then
		UseCooldown(VileTaint)
	end
	if Player.soul_shards == 5 then
		if Player.use_seed then
			if SeedOfCorruption:usable() then
				return SeedOfCorruption
			end
		else
			if UnstableAffliction:usable() then
				return UnstableAffliction
			end
		end
	end
	apl = self:dots()
	if apl then return apl end
	if PhantomSingularity:usable() and TimeInCombat() <= 35 then
		UseCooldown(PhantomSingularity)
	end
	if VileTaint:usable() and TimeInCombat() < 15 then
		UseCooldown(VileTaint)
	end
	if DarkSoulMisery:usable() and (SummonDarkglare:cooldown() < 10 and PhantomSingularity:up() or Target.timeToDie < 20 + Player.gcd or Player.enemies > 1) then
		UseCooldown(DarkSoulMisery)
	end
	apl = self:spenders()
	if apl then return apl end
	apl = self:fillers()
	if apl then return apl end
end

APL[SPEC.AFFLICTION].cooldowns = function(self)
--[[
actions.cooldowns=potion,if=(talent.dark_soul_misery.enabled&cooldown.summon_darkglare.up&cooldown.dark_soul.up)|cooldown.summon_darkglare.up|target.time_to_die<30
actions.cooldowns+=/use_items,if=!cooldown.summon_darkglare.up,if=cooldown.summon_darkglare.remains>70|time_to_die<20|((buff.active_uas.stack=5|soul_shard=0)&(!talent.phantom_singularity.enabled|cooldown.phantom_singularity.remains)&(!talent.deathbolt.enabled|cooldown.deathbolt.remains<=gcd|!cooldown.deathbolt.remains)&!cooldown.summon_darkglare.remains)
actions.cooldowns+=/fireblood,if=!cooldown.summon_darkglare.up
actions.cooldowns+=/blood_fury,if=!cooldown.summon_darkglare.up
]]
end

APL[SPEC.AFFLICTION].db_refresh = function(self)
--[[
actions.db_refresh=siphon_life,line_cd=15,if=(dot.siphon_life.remains%dot.siphon_life.duration)<=(dot.agony.remains%dot.agony.duration)&(dot.siphon_life.remains%dot.siphon_life.duration)<=(dot.corruption.remains%dot.corruption.duration)&dot.siphon_life.remains<dot.siphon_life.duration*1.3
actions.db_refresh+=/agony,line_cd=15,if=(dot.agony.remains%dot.agony.duration)<=(dot.corruption.remains%dot.corruption.duration)&(dot.agony.remains%dot.agony.duration)<=(dot.siphon_life.remains%dot.siphon_life.duration)&dot.agony.remains<dot.agony.duration*1.3
actions.db_refresh+=/corruption,line_cd=15,if=(dot.corruption.remains%dot.corruption.duration)<=(dot.agony.remains%dot.agony.duration)&(dot.corruption.remains%dot.corruption.duration)<=(dot.siphon_life.remains%dot.siphon_life.duration)&dot.corruption.remains<dot.corruption.duration*1.3
]]
	local siphon_rd = SiphonLife.known and (SiphonLife:remains() / SiphonLife:duration()) or 1.3
	local agony_rd = Agony:remains() / Agony:duration()
	local corruption_rd = Corruption:remains() / Corruption:duration()
	if SiphonLife:usable() and siphon_rd < 0.8 and siphon_rd <= agony_rd and siphon_rd <= corruption_rd then
		return SiphonLife
	end
	if Agony:usable() and agony_rd < 0.8 and agony_rd <= corruption_rd and agony_rd <= siphon_rd then
		return Agony
	end
	if Corruption:usable() and corruption_rd < 0.8 and corruption_rd <= agony_rd and corruption_rd <= siphon_rd then
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
	if Player.enemies >= 3 and SeedOfCorruption:usable() and Corruption:remains() < (SeedOfCorruption:castTime() + (Corruption:duration() * 0.3)) and not (SeedOfCorruption:up() or SeedOfCorruption:ticking() > 0) then
		return SeedOfCorruption
	end
	if Agony:usable() and (Agony:ticking() < (CreepingDeath.known and 6 or 8) and Target.timeToDie > 10 and (Agony:remains() <= Player.gcd or SummonDarkglare:cooldown() > 10 and (Agony:remains() < 5 or not PandemicInvocation.known and Agony:refreshable()))) then
		return Agony
	end
	if SiphonLife:usable() and (SiphonLife:ticking() < (8 - (CreepingDeath.known and 1 or 0) - Player.enemies)) and Target.timeToDie > 10 and SiphonLife:refreshable() and (SiphonLife:down() and Player.enemies == 1 or SummonDarkglare:cooldown() > (Player.soul_shards * UnstableAffliction:castTime())) then
		return SiphonLife
	end
	if Corruption:usable() and Player.enemies < (3 + (WritheInAgony.known and 1 or 0)) and (Corruption:remains() <= Player.gcd or SummonDarkglare:cooldown() > 10 and Corruption:refreshable()) and Target.timeToDie > 10 then
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
actions.fillers+=/drain_life,if=(buff.inevitable_demise.stack>=40-(spell_targets.seed_of_corruption_aoe-raid_event.invulnerable.up>2)*20&(cooldown.deathbolt.remains>execute_time|!talent.deathbolt.enabled)&(cooldown.phantom_singularity.remains>execute_time|!talent.phantom_singularity.enabled)&(cooldown.dark_soul.remains>execute_time|!talent.dark_soul_misery.enabled)&(cooldown.vile_taint.remains>execute_time|!talent.vile_taint.enabled)&cooldown.summon_darkglare.remains>execute_time+10|buff.inevitable_demise.stack>10&target.time_to_die<=10)
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
	if Deathbolt.known and Deathbolt:cooldown() <= (Player.gcd * 4) and Player.enemies < 3 and SummonDarkglare:cooldown() >= (30 + Player.gcd + Deathbolt:cooldown()) then
		if UnstableAffliction:usable() and not UnstableAffliction:previous() and Deathbolt:cooldown() <= UnstableAffliction:castTime() then
			return UnstableAffliction
		end
		apl = self:db_refresh()
		if apl then return apl end
	end
	if Deathbolt:usable() and SummonDarkglare:cooldown() >= (30 + Player.gcd) then
		return Deathbolt
	end
	if Player.moving then
		if ShadowBolt:usable() and Nightfall.known and Nightfall:up() then
			return ShadowBolt
		end
		if Agony:usable() and not (SiphonLife.known and (Agony:previous() and Agony:previous(2) and Agony:previous(3)) or Agony:previous()) then
			return Agony
		end
		if SiphonLife:usable() and not (SiphonLife:previous() or SiphonLife:previous(2) or SiphonLife:previous(3)) then
			return SiphonLife
		end
		if Corruption:usable() and not (AbsoluteCorruption.known or Corruption:previous()) then
			return Corruption
		end
	end
	if Haunt:usable() then
		return Haunt
	end
	if DrainSoul:usable() then
		return DrainSoul
	end
	if ShadowBolt:usable() then
		return ShadowBolt
	end
end

APL[SPEC.AFFLICTION].spenders = function(self)
--[[
actions.spenders=unstable_affliction,if=cooldown.summon_darkglare.remains<=soul_shard*execute_time&(!talent.deathbolt.enabled|cooldown.deathbolt.remains<=soul_shard*execute_time)
actions.spenders+=/call_action_list,name=fillers,if=(cooldown.summon_darkglare.remains<time_to_shard*(6-soul_shard)|cooldown.summon_darkglare.up)&time_to_die>cooldown.summon_darkglare.remains
actions.spenders+=/seed_of_corruption,if=variable.use_seed
actions.spenders+=/unstable_affliction,if=!variable.use_seed&!prev_gcd.1.summon_darkglare&(talent.deathbolt.enabled&cooldown.deathbolt.remains<=execute_time&!azerite.cascading_calamity.enabled|(soul_shard>=5&spell_targets.seed_of_corruption_aoe<2|soul_shard>=2&spell_targets.seed_of_corruption_aoe>=2)&target.time_to_die>4+execute_time&spell_targets.seed_of_corruption_aoe=1|target.time_to_die<=8+execute_time*soul_shard)
actions.spenders+=/unstable_affliction,if=!variable.use_seed&contagion<=cast_time+variable.padding
actions.spenders+=/unstable_affliction,cycle_targets=1,if=!variable.use_seed&(!talent.deathbolt.enabled|cooldown.deathbolt.remains>time_to_shard|soul_shard>1)&(!talent.vile_taint.enabled|soul_shard>1)&contagion<=cast_time+variable.padding&(!azerite.cascading_calamity.enabled|buff.cascading_calamity.remains>time_to_shard)
]]
	local ua_ct = UnstableAffliction:castTime()
	if UnstableAffliction:usable() and SummonDarkglare:cooldown() <= (Player.soul_shards * ua_ct) and (not Deathbolt.known or Deathbolt:cooldown() <= (Player.soul_shards * ua_ct)) then
		return UnstableAffliction
	end
	if SummonDarkglare:ready() and Target.timeToDie > SummonDarkglare:cooldown() then
		local apl = self:fillers()
		if apl then return apl end
	end
	if Player.use_seed then
		if SeedOfCorruption:usable() then
			return SeedOfCorruption
		end
	elseif UnstableAffliction:usable() then
		if not SummonDarkglare:previous() and (Deathbolt.known and Deathbolt:cooldown() <= ua_ct and not CascadingCalamity.known or (Player.soul_shards >= 5 and Player.enemies < 2 or Player.soul_shards >= 2 and Player.enemies >= 2) and Target.timeToDie > (4 + ua_ct) and Player.enemies  == 1 or Target.timeToDie <= (8 + ua_ct * Player.soul_shards)) then
			return UnstableAffliction
		end
		if UnstableAffliction:remains() <= (ua_ct + Player.padding) then
			return UnstableAffliction
		end
		if (not Deathbolt.known or Player.soul_shards > 1) and (not VileTaint.known or Player.soul_shards > 1) and UnstableAffliction:remains() <= (ua_ct + Player.padding) and not CascadingCalamity.known then
			return UnstableAffliction
		end
	end
end

APL[SPEC.DEMONOLOGY].main = function(self)
	if TimeInCombat() == 0 then
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
		if Opt.healthstone and Healthstone:charges() == 0 and CreateHealthstone:usable() then
			return CreateHealthstone
		end
		if not Player.pet_active then
			if SummonFelguard:usable() then
				return SummonFelguard
			elseif SummonWrathguard:usable() then
				return SummonWrathguard
			end
		end
		if Opt.pot and Target.boss then
			if FlaskOfEndlessFathoms:usable() and FlaskOfEndlessFathoms.buff:remains() < 300 then
				UseCooldown(FlaskOfEndlessFathoms)
			end
			if BattlePotionOfIntellect:usable() then
				UseCooldown(BattlePotionOfIntellect)
			end
		end
		if Demonbolt:usable() and (Target.boss or DemonicCore:up()) then
			return Demonbolt
		end
	else
		if not Player.pet_active then
			if SummonFelguard:usable() then
				UseExtra(SummonFelguard)
			elseif SummonWrathguard:usable() then
				UseExtra(SummonWrathguard)
			end
		end
	end
--[[
actions=potion,if=pet.demonic_tyrant.active&(!talent.nether_portal.enabled|cooldown.nether_portal.remains>160)|target.time_to_die<30
actions+=/use_items,if=pet.demonic_tyrant.active|target.time_to_die<=15
actions+=/berserking,if=pet.demonic_tyrant.active|target.time_to_die<=15
actions+=/blood_fury,if=pet.demonic_tyrant.active|target.time_to_die<=15
actions+=/fireblood,if=pet.demonic_tyrant.active|target.time_to_die<=15
actions+=/call_action_list,name=dcon_opener,if=talent.demonic_consumption.enabled&time<30&!cooldown.summon_demonic_tyrant.remains
actions+=/hand_of_guldan,if=azerite.explosive_potential.rank&time<5&soul_shard>2&buff.explosive_potential.down&buff.wild_imps.stack<3&!prev_gcd.1.hand_of_guldan&&!prev_gcd.2.hand_of_guldan
actions+=/demonbolt,if=soul_shard<=3&buff.demonic_core.up&buff.demonic_core.stack=4
actions+=/implosion,if=azerite.explosive_potential.rank&buff.wild_imps.stack>2&buff.explosive_potential.remains<action.shadow_bolt.execute_time&(!talent.demonic_consumption.enabled|cooldown.summon_demonic_tyrant.remains>12)
actions+=/doom,if=!ticking&time_to_die>30&spell_targets.implosion<2
actions+=/bilescourge_bombers,if=azerite.explosive_potential.rank>0&time<10&spell_targets.implosion<2&buff.dreadstalkers.remains&talent.nether_portal.enabled
actions+=/demonic_strength,if=(buff.wild_imps.stack<6|buff.demonic_power.up)|spell_targets.implosion<2
actions+=/call_action_list,name=nether_portal,if=talent.nether_portal.enabled&spell_targets.implosion<=2
actions+=/call_action_list,name=implosion,if=spell_targets.implosion>1
actions+=/grimoire_felguard,if=(target.time_to_die>120|target.time_to_die<cooldown.summon_demonic_tyrant.remains+15|cooldown.summon_demonic_tyrant.remains<13)
actions+=/summon_vilefiend,if=cooldown.summon_demonic_tyrant.remains>40|cooldown.summon_demonic_tyrant.remains<12
actions+=/call_dreadstalkers,if=(cooldown.summon_demonic_tyrant.remains<9&buff.demonic_calling.remains)|(cooldown.summon_demonic_tyrant.remains<11&!buff.demonic_calling.remains)|cooldown.summon_demonic_tyrant.remains>14
actions+=/bilescourge_bombers,if=cooldown.summon_demonic_tyrant.remains>20|target.time_to_die<8+cooldown.summon_demonic_tyrant.remains
actions+=/hand_of_guldan,if=(azerite.baleful_invocation.enabled|talent.demonic_consumption.enabled)&prev_gcd.1.hand_of_guldan&cooldown.summon_demonic_tyrant.remains<2
# 2000%spell_haste is shorthand for the cast time of Demonic Tyrant. The intent is to only begin casting if a certain number of imps will be out by the end of the cast.
actions+=/summon_demonic_tyrant,if=soul_shard<3&(!talent.demonic_consumption.enabled|buff.wild_imps.stack+imps_spawned_during.2000%spell_haste>=6&time_to_imps.all.remains<cast_time)|target.time_to_die<20
actions+=/power_siphon,if=buff.wild_imps.stack>=2&buff.demonic_core.stack<=2&buff.demonic_power.down&spell_targets.implosion<2
actions+=/doom,if=talent.doom.enabled&refreshable&time_to_die>(dot.doom.remains+30)
actions+=/hand_of_guldan,if=soul_shard>=5|(soul_shard>=3&cooldown.call_dreadstalkers.remains>4&(cooldown.summon_demonic_tyrant.remains>20|(cooldown.summon_demonic_tyrant.remains<gcd*2&talent.demonic_consumption.enabled|cooldown.summon_demonic_tyrant.remains<gcd*4&!talent.demonic_consumption.enabled))&(!talent.summon_vilefiend.enabled|cooldown.summon_vilefiend.remains>3))
actions+=/soul_strike,if=soul_shard<5&buff.demonic_core.stack<=2
actions+=/demonbolt,if=soul_shard<=3&buff.demonic_core.up&((cooldown.summon_demonic_tyrant.remains<6|cooldown.summon_demonic_tyrant.remains>22&!azerite.shadows_bite.enabled)|buff.demonic_core.stack>=3|buff.demonic_core.remains<5|time_to_die<25|buff.shadows_bite.remains)
actions+=/call_action_list,name=build_a_shard
]]
	if Opt.pot and Target.boss and BattlePotionOfIntellect:usable() and (Target.timeToDie < 30 or Pet.DemonicTyrant:up() and (not NetherPortal.known or not NetherPortal:ready(160))) then
		UseCooldown(BattlePotionOfIntellect)
	end
	local apl
	if DemonicConsumption.known and TimeInCombat() < 30 and SummonDemonicTyrant:ready() then
		apl = self:dcon_opener()
		if apl then return apl end
	end
	if ExplosivePotential.known and HandOfGuldan:usable() and TimeInCombat() < 5 and Player.soul_shards > 2 and ExplosivePotential:down() and Player.imp_count < 3 and not (HandOfGuldan:previous(1) or HandOfGuldan:previous(2)) then
		return HandOfGuldan
	end
	if Demonbolt:usable() and Player.soul_shards <= 3 and DemonicCore:stack() == 4 then
		return Demonbolt
	end
	if Demonbolt:usable() and Player.soul_shards <= 4 and DemonicCore:up() and DemonicCore:remains() < (Player.gcd * DemonicCore:stack()) then
		return Demonbolt
	end
	if ExplosivePotential.known and Implosion:usable() and Player.imp_count >= 3 and ExplosivePotential:remains() < ShadowBoltDemo:castTime() and (not DemonicConsumption.known or not SummonDemonicTyrant:ready(12)) then
		return Implosion
	end
	if Doom:usable() and Player.enemies == 1 and Target.timeToDie > 30 and Doom:down() then
		return Doom
	end
	if BilescourgeBombers:usable() and ExplosivePotential.known and NetherPortal.known and TimeInCombat() < 10 and Player.enemies == 1 and Pet.Dreadstalker:up() then
		UseCooldown(BilescourgeBombers)
	end
	if DemonicStrength:usable() and (Player.enemies == 1 or DemonicPower:up() or Player.imp_count < 6) then
		UseCooldown(DemonicStrength)
	end
	if NetherPortal.known and Player.enemies < 3 then
--[[
actions.nether_portal=call_action_list,name=nether_portal_building,if=cooldown.nether_portal.remains<20
actions.nether_portal+=/call_action_list,name=nether_portal_active,if=cooldown.nether_portal.remains>165
]]
		if NetherPortal:ready(20) then
			apl = self:nether_portal_building()
		elseif not NetherPortal:ready(165) then
			apl = self:nether_portal_active()
		end
		if apl then return apl end
	end
	if Player.enemies > 1 then
		apl = self:implosion()
		if apl then return apl end
	end
	if GrimoireFelguard:usable() and (Target.timeToDie > 120 or Target.timeToDie < (SummonDemonicTyrant:cooldown() + 15) or SummonDemonicTyrant:ready(13)) then
		UseCooldown(GrimoireFelguard)
	end
	if SummonVilefiend:usable() and (SummonDemonicTyrant:ready(12) or not SummonDemonicTyrant:ready(40)) then
		UseCooldown(SummonVilefiend)
	end
	if CallDreadstalkers:usable() and (SummonDemonicTyrant:ready(DemonicCalling:up() and 9 or 11) or not SummonDemonicTyrant:ready(14)) then
		return CallDreadstalkers
	end
	if BilescourgeBombers:usable() and (not SummonDemonicTyrant:ready(20) or Target.timeToDie < (8 + SummonDemonicTyrant:cooldown())) then
		UseCooldown(BilescourgeBombers)
	end
	if HandOfGuldan:usable() and (BalefulInvocation.known or DemonicConsumption.known) and HandOfGuldan:previous(1) and SummonDemonicTyrant:ready(2) then
		return HandOfGuldan
	end
	if SummonDemonicTyrant:usable() and Player.soul_shards < 3 and (not DemonicConsumption.known or Target.timeToDie < 20 or Pet.WildImp:impsIn(SummonDemonicTyrant:castTime()) >= 6) then
		UseCooldown(SummonDemonicTyrant)
	end
	if PowerSiphon:usable() and Player.enemies == 1 and Player.imp_count >= 2 and DemonicCore:stack() <= 2 and DemonicPower:down() then
		UseCooldown(PowerSiphon)
	end
	if Doom:usable() and Doom:refreshable() and Target.timeToDie > (Doom:remains() + 30) then
		return Doom
	end
	if Demonbolt:usable() and Player.soul_shards <= 3 and DemonicCore:up() and DemonicCore:remains() <= HandOfGuldan:castTime() then
		return Demonbolt
	end
	if HandOfGuldan:usable() and (Player.soul_shards >= 5 or (Player.soul_shards >= 3 and not CallDreadstalkers:ready(4) and (not SummonDemonicTyrant:ready(20) or (SummonDemonicTyrant:ready(Player.gcd * (DemonicConsumption.known and 2 or 4)))) and (not SummonVilefiend.known or not SummonVilefiend:ready(3)))) then
		return HandOfGuldan
	end
	if SoulStrike:usable() and Player.soul_shards < 5 and DemonicCore:stack() <= 2 then
		return SoulStrike
	end
	if Demonbolt:usable() and Player.soul_shards <= 3 and DemonicCore:up() and ((SummonDemonicTyrant:ready(6) or (not ShadowsBite.known and not SummonDemonicTyrant:ready(22))) or DemonicCore:stack() >= 3 or DemonicCore:remains() < 5 or Target.timeToDie < 25 or (ShadowsBite.known and ShadowsBite:up())) then
		return Demonbolt
	end
	return self:build_a_shard()
end

APL[SPEC.DEMONOLOGY].build_a_shard = function(self)
--[[
actions.build_a_shard=soul_strike,if=!talent.demonic_consumption.enabled|time>15|prev_gcd.1.hand_of_guldan&!buff.bloodlust.remains
actions.build_a_shard+=/shadow_bolt
]]
	if Demonbolt:usable() and DemonicCore:up() and DemonicCore:remains() <= ShadowBoltDemo:castTime() then
		return Demonbolt
	end
	if SoulStrike:usable() and (not DemonicConsumption.known or TimeInCombat() > 15 or (HandOfGuldan:previous(1) and not BloodlustActive())) then
		return SoulStrike
	end
	if ShadowBoltDemo:usable() then
		return ShadowBoltDemo
	end
end

APL[SPEC.DEMONOLOGY].dcon_opener = function(self)
--[[
actions.dcon_opener=/implosion,if=azerite.explosive_potential.enabled&buff.wild_imps.stack>2&buff.explosive_potential.down
actions.dcon_opener+=hand_of_guldan,if=azerite.explosive_potential.enabled&buff.explosive_potential.down&soul_shard>=3&!prev_gcd.1.hand_of_guldan
actions.dcon_opener+=/doom,if=!dot.doom.remains&target.time_to_die>30
actions.dcon_opener+=/hand_of_guldan,if=prev_gcd.1.hand_of_guldan&soul_shard>0&prev_gcd.2.soul_strike
actions.dcon_opener+=/demonic_strength,if=prev_gcd.1.hand_of_guldan&!prev_gcd.2.hand_of_guldan&(buff.wild_imps.stack>1&action.hand_of_guldan.in_flight)
actions.dcon_opener+=/bilescourge_bombers
actions.dcon_opener+=/soul_strike,if=soul_shard<5&(!buff.bloodlust.remains|prev_gcd.1.hand_of_guldan)
actions.dcon_opener+=/summon_vilefiend,if=soul_shard=5
actions.dcon_opener+=/grimoire_felguard,if=soul_shard=5
actions.dcon_opener+=/call_dreadstalkers,if=soul_shard=5
actions.dcon_opener+=/hand_of_guldan,if=soul_shard=5
actions.dcon_opener+=/hand_of_guldan,if=soul_shard>=3&prev_gcd.2.hand_of_guldan&(prev_gcd.1.soul_strike|!talent.soul_strike.enabled&prev_gcd.1.shadow_bolt)
# 2000%spell_haste is shorthand for the cast time of Demonic Tyrant. The intent is to only begin casting if a certain number of imps will be out by the end of the cast.
actions.dcon_opener+=/summon_demonic_tyrant,if=prev_gcd.1.demonic_strength|prev_gcd.1.hand_of_guldan&prev_gcd.2.hand_of_guldan|!talent.demonic_strength.enabled&buff.wild_imps.stack+imps_spawned_during.2000%spell_haste>=6
actions.dcon_opener+=/demonbolt,if=soul_shard<=3&buff.demonic_core.remains
actions.dcon_opener+=/call_action_list,name=build_a_shard
]]
	if ExplosivePotential.known and ExplosivePotential:down() then
		if Implosion:usable() and Player.imp_count >= 3 then
			return Implosion
		end
		if HandOfGuldan:usable() and Player.soul_shards >= 3 and Player.imp_count < 3 and not HandOfGuldan:previous(1) then
			return HandOfGuldan
		end
	end
	if Doom:usable() and Doom:down() and Target.timeToDie > 30 then
		return Doom
	end
	if HandOfGuldan:usable() and HandOfGuldan:previous(1) and SoulStrike:previous(2) then
		return HandOfGuldan
	end
	if DemonicStrength:usable() and HandOfGuldan:previous(1) and not HandOfGuldan:previous(2) and Player.imp_count > 1 then
		UseCooldown(DemonicStrength)
	end
	if BilescourgeBombers:usable() then
		UseCooldown(BilescourgeBombers)
	end
	if Player.soul_shards < 5 then
		if SoulStrike:usable() and (not BloodlustActive() or HandOfGuldan:previous(1)) then
			return SoulStrike
		end
		if HandOfGuldan:usable() and Player.soul_shards >= 3 and HandOfGuldan:previous(2) and (SoulStrike:previous(1) or (not SoulStrike.known and ShadowBoltDemo:previous(1))) then
			return HandOfGuldan
		end
	else
		if SummonVilefiend:usable() then
			UseCooldown(SummonVilefiend)
		elseif GrimoireFelguard:usable() then
			UseCooldown(GrimoireFelguard)
		end
		if CallDreadstalkers:usable() then
			return CallDreadstalkers
		end
		if HandOfGuldan:usable() then
			return HandOfGuldan
		end
	end
	if SummonDemonicTyrant:usable() and (DemonicStrength:previous(1) or (HandOfGuldan:previous(1) and HandOfGuldan:previous(2)) or (not DemonicStrength.known and Pet.WildImp:impsIn(SummonDemonicTyrant:castTime()) >= 6)) then
		UseCooldown(SummonDemonicTyrant)
	end
	if Demonbolt:usable() and Player.soul_shards <= 3 and DemonicCore:up() then
		return Demonbolt
	end
	return self:build_a_shard()
end

APL[SPEC.DEMONOLOGY].implosion = function(self)
--[[
actions.implosion=implosion,if=(buff.wild_imps.stack>=6&(soul_shard<3|prev_gcd.1.call_dreadstalkers|buff.wild_imps.stack>=9|prev_gcd.1.bilescourge_bombers|(!prev_gcd.1.hand_of_guldan&!prev_gcd.2.hand_of_guldan))&!prev_gcd.1.hand_of_guldan&!prev_gcd.2.hand_of_guldan&buff.demonic_power.down)|(time_to_die<3&buff.wild_imps.stack>0)|(prev_gcd.2.call_dreadstalkers&buff.wild_imps.stack>2&!talent.demonic_calling.enabled)
actions.implosion+=/grimoire_felguard,if=cooldown.summon_demonic_tyrant.remains<13|!equipped.132369
actions.implosion+=/call_dreadstalkers,if=(cooldown.summon_demonic_tyrant.remains<9&buff.demonic_calling.remains)|(cooldown.summon_demonic_tyrant.remains<11&!buff.demonic_calling.remains)|cooldown.summon_demonic_tyrant.remains>14
actions.implosion+=/summon_demonic_tyrant
actions.implosion+=/hand_of_guldan,if=soul_shard>=5
actions.implosion+=/hand_of_guldan,if=soul_shard>=3&(((prev_gcd.2.hand_of_guldan|buff.wild_imps.stack>=3)&buff.wild_imps.stack<9)|cooldown.summon_demonic_tyrant.remains<=gcd*2|buff.demonic_power.remains>gcd*2)
actions.implosion+=/demonbolt,if=prev_gcd.1.hand_of_guldan&soul_shard>=1&(buff.wild_imps.stack<=3|prev_gcd.3.hand_of_guldan)&soul_shard<4&buff.demonic_core.up
actions.implosion+=/summon_vilefiend,if=(cooldown.summon_demonic_tyrant.remains>40&spell_targets.implosion<=2)|cooldown.summon_demonic_tyrant.remains<12
actions.implosion+=/bilescourge_bombers,if=cooldown.summon_demonic_tyrant.remains>9
actions.implosion+=/soul_strike,if=soul_shard<5&buff.demonic_core.stack<=2
actions.implosion+=/demonbolt,if=soul_shard<=3&buff.demonic_core.up&(buff.demonic_core.stack>=3|buff.demonic_core.remains<=gcd*5.7)
actions.implosion+=/doom,cycle_targets=1,max_cycle_targets=7,if=refreshable
actions.implosion+=/call_action_list,name=build_a_shard
]]
	if Implosion:usable() and ((Player.imp_count >= 6 and (Player.soul_shards < 3 or CallDreadstalkers:previous(1) or Player.imp_count >= 9 or BilescourgeBombers:previous(1) or not (HandOfGuldan:previous(1) or HandOfGuldan:previous(2))) and not (HandOfGuldan:previous(1) or HandOfGuldan:previous(2) or DemonicPower:up())) or Target.timeToDie < 3 or (not DemonicCalling.known and Player.imp_count > 2 and CallDreadstalkers:previous(2))) then
		return Implosion
	end
	if GrimoireFelguard:usable() and SummonDemonicTyrant:ready(13) and not Player.equipped.WilfredsSigilOfSuperiorSummoning then
		UseCooldown(GrimoireFelguard)
	end
	if CallDreadstalkers:usable() and (SummonDemonicTyrant:ready(DemonicCalling:up() and 9 or 11) or not SummonDemonicTyrant:ready(14)) then
		return CallDreadstalkers
	end
	if SummonDemonicTyrant:usable() then
		UseCooldown(SummonDemonicTyrant)
	end
	if HandOfGuldan:usable() and (Player.soul_shards >= 5 or (Player.soul_shards >= 3 and (((HandOfGuldan:previous(2) or Player.imp_count >= 3) and Player.imp_count < 9) or SummonDemonicTyrant:ready(Player.gcd * 2) or DemonicPower:remains() > (Player.gcd * 2)))) then
		return HandOfGuldan
	end
	if Demonbolt:usable() and HandOfGuldan:previous(1) and between(Player.soul_shards, 1, 3) and (Player.imp_count <= 3 or HandOfGuldan:previous(3)) and DemonicCore:up() then
		return Demonbolt
	end
	if SummonVilefiend:usable() and (SummonDemonicTyrant:ready(12) or (Player.enemies <= 2 and not SummonDemonicTyrant:ready(40))) then
		UseCooldown(SummonVilefiend)
	end
	if BilescourgeBombers:usable() and not SummonDemonicTyrant:ready(9) then
		UseCooldown(BilescourgeBombers)
	end
	if SoulStrike:usable() and Player.soul_shards < 5 and DemonicCore:stack() <= 2 then
		return SoulStrike
	end
	if Demonbolt:usable() and Player.soul_shards <= 3 and DemonicCore:up() and (DemonicCore:stack() >= 3 or DemonicCore:remains() <= (Player.gcd * 5.7)) then
		return Demonbolt
	end
	if Doom:usable() and Doom:refreshable() and Target.timeToDie > (Doom:remains() + 30) then
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
	if BilescourgeBombers:usable() then
		UseCooldown(BilescourgeBombers)
	end
	if GrimoireFelguard:usable() and SummonDemonicTyrant:ready(13) and not Player.equipped.WilfredsSigilOfSuperiorSummoning then
		UseCooldown(GrimoireFelguard)
	end
	if SummonVilefiend:usable() and (SummonDemonicTyrant:ready(12) or not SummonDemonicTyrant:ready(40)) then
		UseCooldown(SummonVilefiend)
	end
	if CallDreadstalkers:usable() and (SummonDemonicTyrant:ready(DemonicCalling:up() and 9 or 11) or not SummonDemonicTyrant:ready(14)) then
		return CallDreadstalkers
	end
	if Player.soul_shards == 1 and (CallDreadstalkers:ready(ShadowBoltDemo:castTime()) or (BilescourgeBombers.known and BilescourgeBombers:ready(ShadowBoltDemo:castTime()))) then
		local apl = self:build_a_shard()
		if apl then return apl end
	end
	if HandOfGuldan:usable() and not NetherPortal:ready(165 + HandOfGuldan:castTime()) and not CallDreadstalkers:ready(Demonbolt:castTime()) and not CallDreadstalkers:ready(ShadowBoltDemo:castTime())  then
		return HandOfGuldan
	end
	if SummonDemonicTyrant:usable() and ((Player.soul_shards == 0 and NetherPortal:remains() < 5) or (NetherPortal:remains() < SummonDemonicTyrant:castTime() + 0.5)) then
		UseCooldown(SummonDemonicTyrant)
	end
	if Demonbolt:usable() and Player.soul_shards <= 3 and DemonicCore:up() then
		return Demonbolt
	end
	return self:build_a_shard()
end

APL[SPEC.DEMONOLOGY].nether_portal_building = function(self)
--[[
actions.nether_portal_building=nether_portal,if=soul_shard>=5&(!talent.power_siphon.enabled|buff.demonic_core.up)
actions.nether_portal_building+=/call_dreadstalkers
actions.nether_portal_building+=/hand_of_guldan,if=cooldown.call_dreadstalkers.remains>18&soul_shard>=3
actions.nether_portal_building+=/power_siphon,if=buff.wild_imps.stack>=2&buff.demonic_core.stack<=2&buff.demonic_power.down&soul_shard>=3
actions.nether_portal_building+=/hand_of_guldan,if=soul_shard>=5
actions.nether_portal_building+=/call_action_list,name=build_a_shard
]]
	if NetherPortal:usable() and Player.soul_shards >= 5 and (not PowerSiphon.known or DemonicCore:up()) then
		UseCooldown(NetherPortal)
	end
	if CallDreadstalkers:usable() then
		return CallDreadstalkers
	end
	if Player.soul_shards >= 3 then
		if HandOfGuldan:usable() and not CallDreadstalkers:ready(18) then
			return HandOfGuldan
		end
		if PowerSiphon:usable() and Player.imp_count >= 2 and DemonicCore:stack() <= 2 and DemonicPower:down() then
			UseCooldown(PowerSiphon)
		end
		if HandOfGuldan:usable() and Player.soul_shards >= 5 then
			return HandOfGuldan
		end
	end
	return self:build_a_shard()
end

APL[SPEC.DESTRUCTION].main = function(self)
	if TimeInCombat() == 0 then
		if Opt.healthstone and Healthstone:charges() == 0 and CreateHealthstone:usable() then
			return CreateHealthstone
		end
		if GrimoireOfSacrifice.known then
			if GrimoireOfSacrifice:remains() < 300 then
				if Player.pet_active then
					return GrimoireOfSacrifice
				else
					return SummonImp
				end
			end
		elseif not Player.pet_active then
			return SummonImp
		end
		if Opt.pot and Target.boss then
			if FlaskOfEndlessFathoms:usable() and FlaskOfEndlessFathoms.buff:remains() < 300 then
				UseCooldown(FlaskOfEndlessFathoms)
			end
			if BattlePotionOfIntellect:usable() then
				UseCooldown(BattlePotionOfIntellect)
			end
		end
	else
		if GrimoireOfSacrifice.known then
			if GrimoireOfSacrifice:remains() < 300 then
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
end

APL.Interrupt = function(self)
	if SpellLock:usable() then
		return SpellLock
	end
	if AxeToss:usable() then
		return AxeToss
	end
end

-- End Action Priority Lists

local function UpdateInterrupt()
	local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
	if not start then
		_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
	end
	if not start or notInterruptible then
		Player.interrupt = nil
		doomedInterruptPanel:Hide()
		return
	end
	Player.interrupt = APL.Interrupt()
	if Player.interrupt then
		doomedInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		doomedInterruptPanel.icon:Show()
		doomedInterruptPanel.border:Show()
	else
		doomedInterruptPanel.icon:Hide()
		doomedInterruptPanel.border:Hide()
	end
	doomedInterruptPanel:Show()
	doomedInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
end

local function DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end

hooksecurefunc('ActionButton_ShowOverlayGlow', DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

local function UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #glows do
		glow = glows[i]
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

local function CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			glows[#glows + 1] = glow
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
	UpdateGlowColorAndScale()
end

local function UpdateGlows()
	local glow, icon, i
	for i = 1, #glows do
		glow = glows[i]
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

function events:ACTIONBAR_SLOT_CHANGED()
	UpdateGlows()
end

local function ShouldHide()
	return (Player.spec == SPEC.NONE or
		   (Player.spec == SPEC.AFFLICTION and Opt.hide.affliction) or
		   (Player.spec == SPEC.DEMONOLOGY and Opt.hide.demonology) or
		   (Player.spec == SPEC.DESTRUCTION and Opt.hide.destruction))
end

local function Disappear()
	doomedPanel:Hide()
	doomedPanel.icon:Hide()
	doomedPanel.border:Hide()
	doomedCooldownPanel:Hide()
	doomedInterruptPanel:Hide()
	doomedExtraPanel:Hide()
	Player.main, Player.last_main = nil
	Player.cd, Player.last_cd = nil
	Player.interrupt = nil
	Player.extra, Player.last_extra = nil
	UpdateGlows()
end

local function Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true
		end
	end
	return false
end

local function UpdateDraggable()
	doomedPanel:EnableMouse(Opt.aoe or not Opt.locked)
	if Opt.aoe then
		doomedPanel.button:Show()
	else
		doomedPanel.button:Hide()
	end
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

local function SnapAllPanels()
	doomedPreviousPanel:ClearAllPoints()
	doomedPreviousPanel:SetPoint('BOTTOMRIGHT', doomedPanel, 'BOTTOMLEFT', -10, -5)
	doomedCooldownPanel:ClearAllPoints()
	doomedCooldownPanel:SetPoint('BOTTOMLEFT', doomedPanel, 'BOTTOMRIGHT', 10, -5)
	doomedInterruptPanel:ClearAllPoints()
	doomedInterruptPanel:SetPoint('TOPLEFT', doomedPanel, 'TOPRIGHT', 16, 25)
	doomedExtraPanel:ClearAllPoints()
	doomedExtraPanel:SetPoint('TOPRIGHT', doomedPanel, 'TOPLEFT', -16, 25)
end

local resourceAnchor = {}

local ResourceFramePoints = {
	['blizzard'] = {
		[SPEC.AFFLICTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 18 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.DEMONOLOGY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 18 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.DESTRUCTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 18 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		}
	},
	['kui'] = {
		[SPEC.AFFLICTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.DEMONOLOGY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.DESTRUCTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		}
	},
}

local function OnResourceFrameHide()
	if Opt.snap then
		doomedPanel:ClearAllPoints()
	end
end

local function OnResourceFrameShow()
	if Opt.snap then
		doomedPanel:ClearAllPoints()
		local p = ResourceFramePoints[resourceAnchor.name][Player.spec][Opt.snap]
		doomedPanel:SetPoint(p[1], resourceAnchor.frame, p[2], p[3], p[4])
		SnapAllPanels()
	end
end

local function HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		resourceAnchor.name = 'kui'
		resourceAnchor.frame = KuiNameplatesPlayerAnchor
	else
		resourceAnchor.name = 'blizzard'
		resourceAnchor.frame = ClassNameplateManaBarFrame
	end
	resourceAnchor.frame:HookScript("OnHide", OnResourceFrameHide)
	resourceAnchor.frame:HookScript("OnShow", OnResourceFrameShow)
end

local function UpdateAlpha()
	doomedPanel:SetAlpha(Opt.alpha)
	doomedPreviousPanel:SetAlpha(Opt.alpha)
	doomedCooldownPanel:SetAlpha(Opt.alpha)
	doomedInterruptPanel:SetAlpha(Opt.alpha)
	doomedExtraPanel:SetAlpha(Opt.alpha)
end

local function UpdateTargetHealth()
	timer.health = 0
	Target.health = UnitHealth('target')
	table.remove(Target.healthArray, 1)
	Target.healthArray[15] = Target.health
	Target.timeToDieMax = Target.health / UnitHealthMax('player') * 15
	Target.healthPercentage = Target.healthMax > 0 and (Target.health / Target.healthMax * 100) or 100
	Target.healthLostPerSec = (Target.healthArray[1] - Target.health) / 3
	Target.timeToDie = Target.healthLostPerSec > 0 and min(Target.timeToDieMax, Target.health / Target.healthLostPerSec) or Target.timeToDieMax
end

local function UpdateDisplay()
	timer.display = 0
	local dim, text = false, false
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	if Player.spec == SPEC.DEMONOLOGY and Player.pet_count > 0 then
		doomedPanel.text:SetText(Player.pet_count)
		text = true
	end
	doomedPanel.dimmer:SetShown(dim)
	doomedPanel.text:SetShown(text)
end

local function UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.last_main = Player.main
	Player.last_cd = Player.cd
	Player.last_extra = Player.extra
	Player.main =  nil
	Player.cd = nil
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
		Player.mana = Player.mana - Player.ability_casting:cost()
		Player.soul_shards = Player.soul_shards - Player.ability_casting:shardCost()
	end
	Player.mana = min(max(Player.mana, 0), Player.mana_max)
	Player.soul_shards = min(max(Player.soul_shards, 0), Player.soul_shards_max)
	Player.pet = UnitGUID('pet')
	Player.pet_active = GetPetActive()
	Player.moving = GetUnitSpeed('player') ~= 0

	summonedPets:purge()
	trackAuras:purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:updateTargetsHit()
		end
		autoAoe:purge()
	end

	if Player.spec == SPEC.DEMONOLOGY then
		Player.pet_count = summonedPets:count()
		Player.imp_count = Pet.WildImp:count()
	end

	Player.main = APL[Player.spec]:main()
	if Player.main ~= Player.last_main then
		if Player.main then
			doomedPanel.icon:SetTexture(Player.main.icon)
			doomedPanel.icon:Show()
			doomedPanel.border:Show()
		else
			doomedPanel.icon:Hide()
			doomedPanel.border:Hide()
		end
	end
	if Player.cd ~= Player.last_cd then
		if Player.cd then
			doomedCooldownPanel.icon:SetTexture(Player.cd.icon)
			doomedCooldownPanel:Show()
		else
			doomedCooldownPanel:Hide()
		end
	end
	if Player.extra ~= Player.last_extra then
		if Player.extra then
			doomedExtraPanel.icon:SetTexture(Player.extra.icon)
			doomedExtraPanel:Show()
		else
			doomedExtraPanel:Hide()
		end
	end
	if Opt.interrupt then
		UpdateInterrupt()
	end
	UpdateGlows()
	UpdateDisplay()
end

local function UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local start, duration
		local _, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
			if start <= 0 then
				return doomedPanel.swipe:Hide()
			end
		end
		doomedPanel.swipe:SetCooldown(start, duration)
		doomedPanel.swipe:Show()
	end
end

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and powerType == 'SOUL_SHARDS' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:ADDON_LOADED(name)
	if name == 'Doomed' then
		Opt = Doomed
		if not Opt.frequency then
			print('It looks like this is your first time running Doomed, why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000/doom|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] Doomed is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitializeOpts()
		Azerite:initialize()
		UpdateDraggable()
		UpdateAlpha()
		SnapAllPanels()
		doomedPanel:SetScale(Opt.scale.main)
		doomedPreviousPanel:SetScale(Opt.scale.previous)
		doomedCooldownPanel:SetScale(Opt.scale.cooldown)
		doomedInterruptPanel:SetScale(Opt.scale.interrupt)
		doomedExtraPanel:SetScale(Opt.scale.extra)
	end
end

APL[SPEC.DEMONOLOGY].combat_event = function(self, eventType, srcGUID, dstGUID, spellId, ability)
	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		local pet = summonedPets:find(dstGUID)
		if pet then
			pet:removeUnit(dstGUID)
		end
		return
	end
	if ability == FelFirebolt then
		local unit = Pet.WildImp:getUnit(srcGUID)
		if unit then
			if eventType == 'SPELL_CAST_START' then
				Pet.WildImp:castStart(unit)
			elseif eventType == 'SPELL_CAST_SUCCESS' then
				Pet.WildImp:castSuccess(unit)
			end
		end
	end
	if srcGUID ~= Player.guid then
		return
	end
	if eventType == 'SPELL_SUMMON' then
		local pet = summonedPets:find(dstGUID)
		if pet then
			if pet == DemonicTyrant then
				summonedPets:extend(15)
			end
			pet:addUnit(dstGUID)
		end
	elseif eventType == 'SPELL_CAST_SUCCESS' then
		if ability == Implosion or (DemonicConsumption.known and ability == SummonDemonicTyrant) then
			Pet.WildImp:implode()
		elseif ability == PowerSiphon then
			Pet.WildImp:sacrifice()
			Pet.WildImp:sacrifice()
		end
	end
	if dstGUID == Player.guid then
		if ability == DemonicPower then
			if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
				summonedPets.empowered_ends = Player.time + 15
			elseif eventType == 'SPELL_AURA_REMOVED' then
				summonedPets.empowered_ends = 0
			end
		end
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

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:remove(dstGUID)
		end
	end
	if Opt.auto_aoe and (eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED') then
		if dstGUID == Player.guid or dstGUID == Player.pet then
			autoAoe:add(srcGUID, true)
		elseif (srcGUID == Player.guid or srcGUID == Player.pet) and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:add(dstGUID, true)
		end
	end

	local ability = spellId and abilities.bySpellId[spellId]

	if APL[Player.spec].combat_event then
		APL[Player.spec]:combat_event(eventType, srcGUID, dstGUID, spellId, ability)
	end

	if (srcGUID ~= Player.guid and srcGUID ~= Player.pet) then
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
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName, spellId))
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		if srcGUID == Player.guid or ability.player_triggered then
			Player.last_ability = ability
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
			ability:applyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:refreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:removeAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:remove(dstGUID)
		elseif ability.auto_aoe and eventType == ability.auto_aoe.trigger then
			ability:recordTargetHit(dstGUID)
		end
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
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

local function UpdateTargetInfo()
	Disappear()
	if ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		Target.guid = nil
		Target.boss = false
		Target.player = false
		Target.hostile = true
		Target.stunnable = false
		Target.healthMax = 0
		local i
		for i = 1, 15 do
			Target.healthArray[i] = 0
		end
		if Opt.always_on then
			UpdateTargetHealth()
			UpdateCombat()
			doomedPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			doomedPreviousPanel:Hide()
		end
		return
	end
	if guid ~= Target.guid then
		Target.guid = guid
		local i
		for i = 1, 15 do
			Target.healthArray[i] = UnitHealth('target')
		end
	end
	Target.boss = false
	Target.stunnable = true
	Target.level = UnitLevel('target')
	Target.healthMax = UnitHealthMax('target')
	Target.player = UnitIsPlayer('target')
	if not Target.player then
		if Target.level == -1 or (Player.instance == 'party' and Target.level >= UnitLevel('player') + 2) then
			Target.boss = true
			Target.stunnable = false
		elseif Player.instance == 'raid' or (Target.healthMax > Player.health_max * 10) then
			Target.stunnable = false
		end
	end
	Target.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if Target.hostile or Opt.always_on then
		UpdateTargetHealth()
		UpdateCombat()
		doomedPanel:Show()
		return true
	end
end

function events:PLAYER_TARGET_CHANGED()
	UpdateTargetInfo()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.pet_stuck = false
	Target.estimated_range = 30
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
		autoAoe:clear()
		autoAoe:update()
	end
	if Player.last_ability then
		Player.last_ability = nil
		doomedPreviousPanel:Hide()
	end
end

local function UpdateAbilityData()
	Player.mana_max = UnitPowerMax('player', 0)
	Player.soul_shards_max = UnitPowerMax('player', 7)
	local _, ability, pet

	for _, ability in next, abilities.all do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = (IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) or Azerite.traits[ability.spellId]) and true or false
	end
	for _, pet in next, summonedPets.all do
		pet.known = false
	end

	if UnstableAffliction.known then
		UnstableAffliction[1].known = true
		UnstableAffliction[2].known = true
		UnstableAffliction[3].known = true
		UnstableAffliction[4].known = true
		UnstableAffliction[5].known = true
	end
	DemonicPower.known = SummonDemonicTyrant.known
	Pet.Darkglare.known = SummonDarkglare.known
	Pet.DemonicTyrant.known = SummonDemonicTyrant.known
	Pet.Dreadstalker.known = CallDreadstalkers.known
	Pet.Felguard.known = GrimoireFelguard.known
	Pet.Vilefiend.known = SummonVilefiend.known
	Pet.WildImp.known = HandOfGuldan.known
	if InnerDemons.known or NetherPortal.known then
		Pet.Bilescourge.known = true
		Pet.Darkhound.known = true
		Pet.EredarBrute.known = true
		Pet.EyeOfGuldan.known = true
		Pet.IllidariSatyr.known = true
		Pet.PrinceMalchezaar.known = true
		Pet.Shivarra.known = true
		Pet.Urzul.known = true
		Pet.ViciousHellhound.known = true
		Pet.VoidTerror.known = true
		Pet.Wrathguard.known = true
	end
	SummonImp.known = SummonImp.known and not SummonFelImp.known
	SummonFelhunter.known = SummonFelhunter.known and not SummonObserver.known
	SummonVoidwalker.known = SummonVoidwalker.known and not SummonVoidlord.known
	SummonSuccubus.known = SummonSuccubus.known and not SummonShivarra.known
	SummonFelguard.known = SummonFelguard.known and not SummonWrathguard.known
	AxeToss.known = SummonFelguard.known or SummonWrathguard.known
	Felstorm.known = SummonFelguard.known or SummonWrathguard.known
	LegionStrike.known = SummonFelguard.known or SummonWrathguard.known
	SpellLock.known = SummonFelhunter.known or SummonObserver.known
	FelFirebolt.known = Pet.WildImp.known

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

function events:PLAYER_EQUIPMENT_CHANGED()
	Azerite:update()
	UpdateAbilityData()
	Player.equipped.WilfredsSigilOfSuperiorSummoning = Equipped(132369)
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName == 'player' then
		Player.spec = GetSpecialization() or 0
		Azerite:update()
		UpdateAbilityData()
		local _, i
		for i = 1, #inventoryItems do
			inventoryItems[i].name, _, _, _, _, _, _, _, _, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId)
		end
		doomedPreviousPanel.ability = nil
		Player.previous_gcd = {}
		SetTargetMode(1)
		UpdateTargetInfo()
		events:PLAYER_REGEN_ENABLED()
	end
end

function events:PLAYER_PVP_TALENT_UPDATE()
	UpdateAbilityData()
end

function events:PLAYER_ENTERING_WORLD()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	if #glows == 0 then
		CreateOverlayGlows()
		HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
end

doomedPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Doomed_ToggleTargetMode()
		elseif button == 'RightButton' then
			Doomed_ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Doomed_SetTargetMode(1)
		end
	end
end)

doomedPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UpdateCombat()
	end
	if timer.display >= 0.05 then
		UpdateDisplay()
	end
	if timer.health >= 0.2 then
		UpdateTargetHealth()
	end
end)

doomedPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	doomedPanel:RegisterEvent(event)
end

function SlashCmdList.Doomed(msg, editbox)
	msg = { strsplit(' ', strlower(msg)) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UpdateDraggable()
		end
		return print('Doomed - Locked: ' .. (Opt.locked and '|cFF00C000On' or '|cFFC00000Off'))
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
			OnResourceFrameShow()
		end
		return print('Doomed - Snap to Blizzard combat resources frame: ' .. (Opt.snap and ('|cFF00C000' .. Opt.snap) or '|cFFC00000Off'))
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				doomedPreviousPanel:SetScale(Opt.scale.previous)
			end
			return print('Doomed - Previous ability icon scale set to: |cFFFFD000' .. Opt.scale.previous .. '|r times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				doomedPanel:SetScale(Opt.scale.main)
			end
			return print('Doomed - Main ability icon scale set to: |cFFFFD000' .. Opt.scale.main .. '|r times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				doomedCooldownPanel:SetScale(Opt.scale.cooldown)
			end
			return print('Doomed - Cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.cooldown .. '|r times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				doomedInterruptPanel:SetScale(Opt.scale.interrupt)
			end
			return print('Doomed - Interrupt ability icon scale set to: |cFFFFD000' .. Opt.scale.interrupt .. '|r times')
		end
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				doomedExtraPanel:SetScale(Opt.scale.extra)
			end
			return print('Doomed - Extra/Pet cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.extra .. '|r times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return print('Doomed - Action button glow scale set to: |cFFFFD000' .. Opt.scale.glow .. '|r times')
		end
		return print('Doomed - Default icon scale options: |cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000pet 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UpdateAlpha()
		end
		return print('Doomed - Icon transparency set to: |cFFFFD000' .. Opt.alpha * 100 .. '%|r')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return print('Doomed - Calculation frequency (max time to wait between each update): Every |cFFFFD000' .. Opt.frequency .. '|r seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Doomed - Glowing ability buttons (main icon): ' .. (Opt.glow.main and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Doomed - Glowing ability buttons (cooldown icon): ' .. (Opt.glow.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Doomed - Glowing ability buttons (interrupt icon): ' .. (Opt.glow.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Doomed - Glowing ability buttons (extra/pet cooldown icon): ' .. (Opt.glow.extra and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Doomed - Blizzard default proc glow: ' .. (Opt.glow.blizzard and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UpdateGlowColorAndScale()
			end
			return print('Doomed - Glow color:', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return print('Doomed - Possible glow options: |cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000pet|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Doomed - Previous ability icon: ' .. (Opt.previous and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Doomed - Show the Doomed UI without a target: ' .. (Opt.always_on and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return print('Doomed - Use Doomed for cooldown management: ' .. (Opt.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
			if not Opt.spell_swipe then
				doomedPanel.swipe:Hide()
			end
		end
		return print('Doomed - Spell casting swipe animation: ' .. (Opt.spell_swipe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
			if not Opt.dimmer then
				doomedPanel.dimmer:Hide()
			end
		end
		return print('Doomed - Dim main ability icon when you don\'t have enough mana to use it: ' .. (Opt.dimmer and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return print('Doomed - Red border around previous ability when it fails to hit: ' .. (Opt.miss_effect and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Doomed_SetTargetMode(1)
			UpdateDraggable()
		end
		return print('Doomed - Allow clicking main ability icon to toggle amount of targets (disables moving): ' .. (Opt.aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return print('Doomed - Only use cooldowns on bosses: ' .. (Opt.boss_only and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'aff') then
				Opt.hide.affliction = not Opt.hide.affliction
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Doomed - Affliction specialization: |cFFFFD000' .. (Opt.hide.affliction and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'demo') then
				Opt.hide.demonology = not Opt.hide.demonology
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Doomed - Demonology specialization: |cFFFFD000' .. (Opt.hide.demonology and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'dest') then
				Opt.hide.destruction = not Opt.hide.destruction
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Doomed - Destruction specialization: |cFFFFD000' .. (Opt.hide.destruction and '|cFFC00000Off' or '|cFF00C000On'))
			end
		end
		return print('Doomed - Possible hidespec options: |cFFFFD000aff|r/|cFFFFD000demo|r/|cFFFFD000dest|r - toggle disabling Doomed for specializations')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return print('Doomed - Show an icon for interruptable spells: ' .. (Opt.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return print('Doomed - Automatically change target mode on AoE spells: ' .. (Opt.auto_aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return print('Doomed - Length of time target exists in auto AoE after being hit: |cFFFFD000' .. Opt.auto_aoe_ttl .. '|r seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return print('Doomed - Show flasks and battle potions in cooldown UI: ' .. (Opt.pot and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'health') then
		if msg[2] then
			Opt.healthstone = msg[2] == 'on'
		end
		return print('Doomed - Show Create Healthstone reminder out of combat: ' .. (Opt.healthstone and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'reset' then
		doomedPanel:ClearAllPoints()
		doomedPanel:SetPoint('CENTER', 0, -169)
		SnapAllPanels()
		return print('Doomed - Position has been reset to default')
	end
	print('Doomed (version: |cFFFFD000' .. GetAddOnMetadata('Doomed', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Doomed UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Doomed UI to the Blizzard combat resources frame',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000pet|r/|cFFFFD000glow|r - adjust the scale of the Doomed UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Doomed UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.05 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000pet|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Doomed UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Doomed for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough mana to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000aff|r/|cFFFFD000demo|r/|cFFFFD000dest|r - toggle disabling Doomed for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'healthstone |cFF00C000on|r/|cFFC00000off|r - show Create Healthstone reminder out of combat',
		'|cFFFFD000reset|r - reset the location of the Doomed UI to default',
	} do
		print('  ' .. SLASH_Doomed1 .. ' ' .. cmd)
	end
	print('Need to threaten with the wrath of doom? You can still use |cFFFFD000/wrath|r!')
	print('Got ideas for improvement or found a bug? Contact |cFF9482C9Baad|cFFFFD000-Dalaran|r or |cFFFFD000Spy#1955|r (the author of this addon)')
end
