if select(2, UnitClass('player')) ~= 'WARLOCK' then
	DisableAddOn('Doomed')
	return
end

-- useful functions
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

local function InitializeVariables()
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
			color = { r = 1, g = 1, b = 1 }
		},
		hide = {
			affliction = false,
			demonology = false,
			destruction = false
		},
		alpha = 1,
		frequency = 0.05,
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
		healthstone = true,
		pot = false
	})
end

-- specialization constants
local SPEC = {
	NONE = 0,
	AFFLICTION = 1,
	DEMONOLOGY = 2,
	DESTRUCTION = 3
}

local events, glows = {}, {}

local abilityTimer, currentSpec, targetMode, combatStartTime = 0, 0, 0, 0

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false
}

-- list of previous GCD abilities
local PreviousGCD = {}

-- items equipped with special effects
local ItemEquipped = {

}

-- Azerite trait API access
local Azerite = {}

local var = {
	gcd = 1.5
}

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

local autoAoe = {
	abilities = {},
	targets = {}
}

function autoAoe:update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Automagically_SetTargetMode(1)
		return
	end
	for i = #targetModes[currentSpec], 1, -1 do
		if count >= targetModes[currentSpec][i][1] then
			Automagically_SetTargetMode(i)
			return
		end
	end
end

function autoAoe:add(guid)
	local new = not self.targets[guid]
	self.targets[guid] = GetTime()
	if new then
		self:update()
	end
end

function autoAoe:remove(guid)
	if self.targets[guid] then
		self.targets[guid] = nil
		self:update()
	end
end

function autoAoe:purge()
	local update, guid, t
	local now = GetTime()
	for guid, t in next, self.targets do
		if now - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	if update then
		self:update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability, abilities, abilityBySpellId, abilitiesAutoAoe = {}, {}, {}, {}
Ability.__index = Ability

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
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		velocity = 0,
		last_used = 0,
		auraTarget = buff == 'pet' and 'pet' or buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, Ability)
	abilities[#abilities + 1] = ability
	abilityBySpellId[spellId] = ability
	return ability
end

function Ability:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function Ability:usable(seconds)
	if not self.known then
		return false
	end
	if self:cost() > var.mana then
		return false
	end
	if self:shardCost() > var.soul_shards then
		return false
	end
	if self.requires_pet and not var.pet_exists then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

function Ability:remains()
	if self:traveling() then
		return self:duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == self.spellId or id == self.spellId2 then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - var.time - var.execute_remains, 0)
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
	if self:traveling() then
		return true
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return false
		end
		if id == self.spellId or id == self.spellId2 then
			return expires == 0 or expires - var.time > var.execute_remains
		end
	end
end

function Ability:down()
	return not self:up()
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
		if var.time - self.travel_start[Target.guid] < 40 / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:ticking()
	if self.aura_targets then
		local count, guid, expires = 0
		for guid, expires in next, self.aura_targets do
			if expires - var.time > var.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:up() and 1 or 0
end

function Ability:cooldownDuration()
	return self.hasted_cooldown and (var.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (var.time - start) - var.execute_remains)
end

function Ability:stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == self.spellId or id == self.spellId2 then
			return (expires == 0 or expires - var.time > var.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:cost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * var.mana_max) or 0
end

function Ability:charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:chargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, var.time - recharge_start + var.execute_remains)) / recharge_time)
end

function Ability:fullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (var.time - recharge_start) - var.execute_remains)
end

function Ability:maxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:duration()
	return self.hasted_duration and (var.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return UnitCastingInfo('player') == self.name
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and var.gcd or 0
	end
	return castTime / 1000
end

function Ability:castRegen()
	return var.mana_regen * self:castTime() - self:cost()
end

function Ability:wontCapMana(reduction)
	return (var.mana + self:castRegen()) < (var.mana_max - (reduction or 5))
end

function Ability:tickTime()
	return self.hasted_ticks and (var.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:previous()
	if self:casting() or self:channeling() then
		return true
	end
	return PreviousGCD[1] == self or var.last_ability == self
end

function Ability:azeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:setAutoAoe(enabled)
	if enabled and not self.auto_aoe then
		self.auto_aoe = true
		self.first_hit_time = nil
		self.targets_hit = {}
		autoAoe.abilities[#autoAoe.abilities + 1] = self
	end
	if not enabled and self.auto_aoe then
		self.auto_aoe = nil
		self.first_hit_time = nil
		self.targets_hit = nil
		local i
		for i = 1, #autoAoe.abilities do
			if autoAoe.abilities[i] == self then
				autoAoe.abilities[i] = nil
				break
			end
		end
	end
end

function Ability:recordTargetHit(guid)
	local t = GetTime()
	self.targets_hit[guid] = t
	if not self.first_hit_time then
		self.first_hit_time = t
	end
end

function Ability:updateTargetsHit()
	if self.first_hit_time and GetTime() - self.first_hit_time >= 0.3 then
		self.first_hit_time = nil
		local guid, t
		for guid in next, autoAoe.targets do
			if not self.targets_hit[guid] then
				autoAoe.targets[guid] = nil
			end
		end
		for guid, t in next, self.targets_hit do
			autoAoe.targets[guid] = t
			self.targets_hit[guid] = nil
		end
		autoAoe:update()
	end
end

-- start DoT tracking

local trackAuras = {
	abilities = {}
}

function trackAuras:purge()
	local now = GetTime()
	local _, ability, guid, expires
	for _, ability in next, self.abilities do
		for guid, expires in next, ability.aura_targets do
			if expires <= now then
				ability:removeAura(guid)
			end
		end
	end
end

function Ability:trackAuras()
	self.aura_targets = {}
	trackAuras.abilities[self.spellId] = self
	if self.spellId2 then
		trackAuras.abilities[self.spellId2] = self
	end
end

function Ability:applyAura(guid)
	if self.aura_targets and UnitGUID(self.auraTarget) == guid then -- for now, we can only track if the enemy is targeted
		local _, i, id, expires
		for i = 1, 40 do
			_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
			if not id then
				return
			end
			if id == self.spellId or id == self.spellId2 then
				self.aura_targets[guid] = expires
				return
			end
		end
	end
end

function Ability:removeAura(guid)
	if self.aura_targets then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Warlock Abilities
---- Multiple Specializations
local CreateHealthstone = Ability.add(6201, true, true) -- Used for GCD calculation
CreateHealthstone.mana_cost = 5
local LifeTap = Ability.add(1454, false, true)
LifeTap.mana_cost = -30
local ShadowLock = Ability.add(171138, 'pet', false)
ShadowLock.cooldown_duration = 24
local SpellLock = Ability.add(119910, 'pet', false)
SpellLock.cooldown_duration = 24
------ Talents
local DemonicPower = Ability.add(196099, true, true) -- Grimoire of Sacrifice buff
local GrimoireOfSacrifice = Ability.add(108503, true, true)
local GrimoireOfSupremacy = Ability.add(152107, true, true)
local SoulHarvest = Ability.add(196098, true, true)
SoulHarvest.buff_duration = 12
SoulHarvest.cooldown_duration = 120
------ Procs
local SoulConduit = Ability.add(215941, true, true)
local SephuzsSecret = Ability.add(208052, true, true)
SephuzsSecret.cooldown_duration = 30
------ Permanent Pets
local SummonDoomguard = Ability.add(157757, false, true) -- Grimoire of Supremacy
SummonDoomguard.shard_cost = 1
SummonDoomguard.pet_family = 'Doomguard'
local SummonInfernal = Ability.add(157898, false, true) -- Grimoire of Supremacy
SummonInfernal.shard_cost = 1
SummonInfernal.pet_family = 'Infernal'
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
Agony.mana_cost = 3
Agony.buff_duration = 18
Agony.tick_interval = 2
local Corruption = Ability.add(172, false, true, 146739)
Corruption.mana_cost = 3
Corruption.buff_duration = 14
Corruption.tick_interval = 2
local DeadwindHarvester = Ability.add(216708, true, true)
local DrainSoul = Ability.add(198590, false, true)
DrainSoul.mana_cost = 3
DrainSoul.buff_duration = 6
DrainSoul.tick_interval = 1
DrainSoul.hasted_duration = true
local ReapSouls = Ability.add(216698, true, true, 216695)
ReapSouls.cooldown_duration = 5
ReapSouls.buff_duration = 60
ReapSouls.triggers_gcd = false
local SeedOfCorruption = Ability.add(27243, false, true, 27285)
SeedOfCorruption.shard_cost = 1
SeedOfCorruption.buff_duration = 18
SeedOfCorruption.hasted_duration = true
SeedOfCorruption:setAutoAoe(true)
local TormentedSouls = ReapSouls
local UnstableAffliction = Ability.add(30108, false, true)
UnstableAffliction.shard_cost = 1
UnstableAffliction.buff_duration = 8
UnstableAffliction.tick_interval = 2
UnstableAffliction.hasted_duration = true
UnstableAffliction[1] = Ability.add(233490, false, true)
UnstableAffliction[2] = Ability.add(233496, false, true)
UnstableAffliction[3] = Ability.add(233497, false, true)
UnstableAffliction[4] = Ability.add(233498, false, true)
UnstableAffliction[5] = Ability.add(233499, false, true)
------ Talents
local Contagion = Ability.add(196105, false, true)
local DeathsEmbrace = Ability.add(234876, false, true)
local EmpoweredLifeTap = Ability.add(235157, true, true, 235156)
EmpoweredLifeTap.buff_duration = 20
local Haunt = Ability.add(48181, false, true)
Haunt.mana_cost = 5
Haunt.buff_duration = 10
Haunt.cooldown_duration = 25
local MaleficGrasp = Ability.add(235155, false, true)
local PhantomSingularity = Ability.add(205179, false, true)
PhantomSingularity.buff_duration = 16
PhantomSingularity.cooldown_duration = 40
PhantomSingularity.hasted_duration = true
PhantomSingularity:setAutoAoe(true)
local SiphonLife = Ability.add(63106, false, true)
SiphonLife.tick_interval = 3
local SowTheSeeds = Ability.add(196226, false, true)
---- Demonology
------ Base Abilities
local CallDreadstalkers = Ability.add(104316, true, true)
CallDreadstalkers.cooldown_duration = 15
CallDreadstalkers.shard_cost = 2
local Demonwrath = Ability.add(193440, 'pet', true, 193439)
Demonwrath.mana_cost = 2.5
Demonwrath.buff_duration = 3
Demonwrath.tick_interval = 1
Demonwrath.hasted_duration = true
Demonwrath:setAutoAoe(true)
local DemonicEmpowerment = Ability.add(193396, 'pet', true)
DemonicEmpowerment.mana_cost = 6
DemonicEmpowerment.buff_duration = 12
local Doom = Ability.add(603, false, true)
Doom.mana_cost = 2
Doom.buff_duration = 20
Doom.tick_interval = 20
Doom.hasted_duration = true
Doom.tick_targets = {}
local DrainLife = Ability.add(234153, false, true)
DrainLife.mana_cost = 3
DrainLife.buff_duration = 6
DrainLife.tick_interval = 1
DrainLife.hasted_duration = true
local HandOfGuldan = Ability.add(105174, false, true, 86040)
HandOfGuldan.shard_cost = 1
HandOfGuldan:setAutoAoe(true)
local ShadowBolt = Ability.add(686, false, true)
ShadowBolt.mana_cost = 6
ShadowBolt.shard_cost = -1
local SummonDoomguardCD = Ability.add(18540, false, true)
SummonDoomguardCD.cooldown_duration = 180
SummonDoomguardCD.shard_cost = 1
local SummonInfernalCD = Ability.add(1122, false, true)
SummonInfernalCD.cooldown_duration = 180
SummonInfernalCD.shard_cost = 1
local ThalkielsConsumption = Ability.add(211714, false, true)
ThalkielsConsumption.cooldown_duration = 45
------ Pet Abilities
local AxeToss = Ability.add(89766, 'pet', true)
AxeToss.triggers_gcd = false
AxeToss.requires_pet = true
AxeToss.cooldown_duration = 30
local Felstorm = Ability.add(89753, 'pet', true, 119914)
Felstorm.requires_pet = true
Felstorm.triggers_gcd = false
Felstorm.buff_duration = 6
Felstorm.tick_interval = 1
Felstorm.cooldown_duration = 45
Felstorm:setAutoAoe(true)
local Wrathstorm = Ability.add(115831, 'pet', true, 115832)
Wrathstorm.requires_pet = true
Wrathstorm.triggers_gcd = false
Wrathstorm.buff_duration = 6
Wrathstorm.tick_interval = 1
Wrathstorm.cooldown_duration = 45
Wrathstorm:setAutoAoe(true)
local Immolation = Ability.add(20153, 'pet', true)
Immolation.tick_interval = 1.5
Immolation:setAutoAoe(true)
------ Talents Abilities
local Demonbolt = Ability.add(157695, false, true)
Demonbolt.mana_cost = 4.8
Demonbolt.shard_cost = -1
local GrimoireFelguard = Ability.add(111898, false, true)
GrimoireFelguard.cooldown_duration = 90
GrimoireFelguard.shard_cost = 1
local HandOfDoom = Ability.add(196283, false, true)
local ImpendingDoom = Ability.add(196270, false, true)
local Implosion = Ability.add(196277, false, true)
Implosion.mana_cost = 6
local ImprovedDreadstalkers = Ability.add(196272, false, true)
local Shadowflame = Ability.add(205181, false, true)
Shadowflame.requires_charge = true
Shadowflame.cooldown_duration = 14
Shadowflame.shard_cost = -1
local SummonDarkglare = Ability.add(205180, false, true)
SummonDarkglare.cooldown_duration = 24
SummonDarkglare.shard_cost = 1
------ Procs
local DemonicCalling = Ability.add(205145, true, true, 205146)
local DemonicSynergy = Ability.add(171975, true, false, 171982)
DemonicSynergy.buff_duration = 15
local DemonicSynergyPet = Ability.add(171975, 'pet', true, 171982)
DemonicSynergyPet.buff_duration = 15
local PowerTrip = Ability.add(196605, true, true)
local ShadowyInspiration = Ability.add(196269, true, true, 196606)
ShadowyInspiration.buff_duration = 15
-- Tier Bonuses
-- Racials
local ArcaneTorrent = Ability.add(136222, true, false) -- Blood Elf
ArcaneTorrent.mana_cost = -3
ArcaneTorrent.triggers_gcd = false
-- Potion Effects
local ProlongedPower = Ability.add(229206, true, true)
ProlongedPower.triggers_gcd = false
-- Trinket Effects

-- End Abilities

-- Start Summoned Pets

local SummonedPet, petsByUnitName = {}, {}
SummonedPet.__index = SummonedPet

function SummonedPet.add(name, duration)
	local pet = {
		name = name,
		duration = duration,
		active_units = {}
	}
	setmetatable(pet, SummonedPet)
	petsByUnitName[name] = pet
	return pet
end

function SummonedPet:remains()
	local remains, guid, unit, unit_remains = 0
	for guid, unit in next, self.active_units do
		unit_remains = unit.spawn_time + self.duration - var.time
		if unit_remains <= 0 then
			self.active_units[guid] = nil
		elseif unit_remains > remains then
			remains = unit_remains
		end
	end
	return min(self.duration, max(0, remains - var.execute_remains))
end

function SummonedPet:up()
	return self:remains() > 0
end

function SummonedPet:down()
	return self:remains() <= 0
end

function SummonedPet:count()
	local count, guid, unit, unit_remains = 0
	for guid, unit in next, self.active_units do
		unit_remains = unit.spawn_time + self.duration - var.time
		if unit_remains <= 0 then
			self.active_units[guid] = nil
		elseif unit_remains > var.execute_remains then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:empowered()
	local count, guid, unit, unit_remains, empower_remains = 0
	local casting_de = DemonicEmpowerment:casting()
	for guid, unit in next, self.active_units do
		unit_remains = unit.spawn_time + self.duration - var.time
		if unit_remains <= 0 then
			self.active_units[guid] = nil
		elseif unit_remains > var.execute_remains then
			if casting_de then
				count = count + 1
			elseif unit.empower_time then
				empower_remains = unit.empower_time + DemonicEmpowerment.buff_duration - var.time
				if empower_remains <= 0 then
					unit.empower_time = nil
				elseif empower_remains > var.execute_remains then
					count = count + 1
				end
			end
		end
	end
	return count
end

function SummonedPet:notEmpowered()
	if DemonicEmpowerment:casting() then
		return 0
	end
	local count, guid, unit, unit_remains, empower_remains = 0
	for guid, unit in next, self.active_units do
		unit_remains = unit.spawn_time + self.duration - var.time
		if unit_remains <= 0 then
			self.active_units[guid] = nil
		elseif unit_remains > var.execute_remains then
			if unit.empower_time then
				empower_remains = unit.empower_time + DemonicEmpowerment.buff_duration - var.time
				if empower_remains <= var.execute_remains then
					if empower_remains <= 0 then
						unit.empower_time = nil
					end
					count = count + 1
				end
			else
				count = count + 1
			end
		end
	end
	return count
end

function SummonedPet:addUnit(guid)
	self.active_units[guid] = {
		spawn_time = GetTime()
	}
end

function SummonedPet:removeUnit(guid, reason)
	if self.active_units[guid] then
		self.active_units[guid] = nil
	end
end

function SummonedPet:empowerUnit(guid)
	if self.active_units[guid] then
		self.active_units[guid].empower_time = GetTime()
	end
end

-- Summoned Pets
local Darkglare = SummonedPet.add('Darkglare', 12)
local Dreadstalker = SummonedPet.add('Dreadstalker', 12)
local WildImp = SummonedPet.add('Wild Imp', 12)
local Doomguard = SummonedPet.add('Doomguard', 25)
local Infernal = SummonedPet.add('Infernal', 25)
local ServiceFelguard = SummonedPet.add('Felguard', 25)

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
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:cooldown()
	local startTime, duration = GetItemCooldown(self.itemId)
	return startTime == 0 and 0 or duration - (var.time - startTime)
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

local function Mana()
	return var.mana
end

local function ManaDeficit()
	return var.mana_max - var.mana
end

local function ManaRegen()
	return var.mana_regen
end

local function ManaMax()
	return var.mana_max
end

local function ManaTimeToMax()
	local deficit = var.mana_max - var.mana
	if deficit <= 0 then
		return 0
	end
	return deficit / var.mana_regen
end

local function SoulShards()
	return var.soul_shards
end

local function GCD()
	return var.gcd
end

local function Enemies()
	return targetModes[currentSpec][targetMode][1]
end

local function TimeInCombat()
	return combatStartTime > 0 and var.time - combatStartTime or 0
end

local function BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or	-- Bloodlust (Horde Shaman)
			id == 32182 or	-- Heroism (Alliance Shaman)
			id == 80353 or	-- Time Warp (Mage)
			id == 90355 or	-- Ancient Hysteria (Mage Pet - Core Hound)
			id == 160452 or -- Netherwinds (Mage Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Mage Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

local function PlayerIsMoving()
	return GetUnitSpeed('player') ~= 0
end

local function TargetIsStunnable()
	if Target.stunnable ~= '?' then
		return Target.stunnable
	end
	if UnitIsPlayer('target') then
		return true
	end
	if Target.boss then
		return false
	end
	if var.instance == 'raid' then
		return false
	end
	if UnitHealthMax('target') > UnitHealthMax('player') * 10 then
		return false
	end
	return true
end

local function InArenaOrBattleground()
	return var.instance == 'arena' or var.instance == 'pvp'
end

local function GetExecuteManaRegen()
	return var.mana_regen * var.execute_remains - (var.cast_ability and var.cast_ability:cost() or 0)
end

local function GetAvailableSoulShards()
	local shards = UnitPower('player', SPELL_POWER_SOUL_SHARDS)
	if currentSpec == SPEC.DEMONOLOGY and var.execute_remains > 0 then
		shards = min(5, shards + Doom:soulShardsGeneratedDuringCast())
	end
	if var.cast_ability then
		shards = min(5, max(0, shards - var.cast_ability:shardCost()))
	end
	return shards
end

local function SpellHasteFactor()
	return var.haste_factor
end

local function PetIsSummoned()
	return (IsMounted() or (UnitExists('pet') and not UnitIsDead('pet')) or
		SummonFelguard:up() or SummonWrathguard:up() or
		SummonDoomguard:up() or SummonInfernal:up() or
		SummonFelhunter:up() or SummonObserver:up() or
		SummonImp:up() or SummonFelImp:up() or
		SummonVoidwalker:up() or SummonVoidlord:up() or
		SummonSuccubus:up() or SummonShivarra:up())
end

-- End Helpful Functions

-- Start Ability Modifications

function LifeTap:usable()
	if (UnitHealth('player') / UnitHealthMax('player')) <= 0.10 then
		return false
	end
	return Ability.usable(self)
end

function Doom:duration()
	return var.haste_factor * (self.buff_duration - (ImpendingDoom.known and 3 or 0))
end

function Doom:up()
	if HandOfDoom.known and (HandOfGuldan:previous() or var.last_gcd == HandOfGuldan) then
		return true
	end
	return Ability.up(self)
end

function Doom:remains()
	if HandOfDoom.known and (HandOfGuldan:previous() or var.last_gcd == HandOfGuldan) then
		return self:duration()
	end
	return Ability.remains(self)
end

function Doom:addTarget(guid)
	local start = GetTime()
	local duration = Doom:duration()
	self.tick_targets[guid] = {
		last_tick = start,
		tick_duration = duration,
		expires = start + duration
	}
end

function Doom:tickTarget(guid)
	local t = self.tick_targets[guid]
	if not t then
		return
	end
	if not t.refreshed then
		self.tick_targets[guid] = nil
		return
	end
	t.refreshed = nil
	t.last_tick = GetTime()
	t.tick_duration = self:duration()
end

function Doom:refreshTarget(guid)
	local t = self.tick_targets[guid]
	if not t then
		return
	end
	t.refreshed = GetTime()
	local duration = Doom:duration()
	t.expires = t.refreshed + min(1.3 * duration, t.expires - t.refreshed + duration)
end

function Doom:removeTarget(guid)
	if self.tick_targets[guid] then
		self.tick_targets[guid] = nil
	end
end

--[[
function Doom:nextTick()
	local earliest, next_tick, guid, t
	for guid, t in next, self.tick_targets do
		if var.time > t.expires then
			self.tick_targets[guid] = nil
		else
			next_tick = min(t.expires, t.last_tick + t.tick_duration)
			if not earliest or next_tick < earliest then
				earliest = next_tick
			end
		end
	end
	return earliest or 0
end
]]

function Doom:soulShardsGeneratedDuringCast()
	if var.execute_remains == 0 then
		return 0
	end
	local shards, guid, t = 0
	for guid, t in next, self.tick_targets do
		if var.time > t.expires then
			self.tick_targets[guid] = nil
		elseif min(t.expires, t.last_tick + t.tick_duration) < var.time + var.execute_remains then
			shards = shards + 1
		end
	end
	return shards
end

function Doom:soulShardsGeneratedNextCast(ability)
	local castTime = ability:castTime()
	if castTime == 0 then
		return 0
	end
	local shards, next_tick, guid, t = 0
	for guid, t in next, self.tick_targets do
		if var.time > t.expires then
			self.tick_targets[guid] = nil
		else
			next_tick = min(t.expires, t.last_tick + t.tick_duration)
			if next_tick >= var.time + var.execute_remains and next_tick < var.time + var.execute_remains + castTime then
				shards = shards + 1
			end
		end
	end
	return shards
end

function ShadowyInspiration:up()
	if ShadowyInspiration.known and (DemonicEmpowerment:previous() or var.last_gcd == DemonicEmpowerment) then
		return true
	end
	return Ability.up(self)
end

function ShadowyInspiration:remains()
	if ShadowyInspiration.known and (DemonicEmpowerment:previous() or var.last_gcd == DemonicEmpowerment) then
		return self:duration()
	end
	return Ability.remains(self)
end

function Implosion:usable()
	return WildImp:count() > 0 and Ability.usable(self)
end

function Corruption:up()
	return Ability.up(self) or SeedOfCorruption:up()
end

function Corruption:remains()
	if SeedOfCorruption:up() or SeedOfCorruption:previous() or var.last_gcd == SeedOfCorruption then
		return Corruption:duration()
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

function UnstableAffliction:up()
	return UnstableAffliction[1]:up() or UnstableAffliction[2]:up() or UnstableAffliction[3]:up() or UnstableAffliction[4]:up() or UnstableAffliction[5]:up()
end

local function UnstableAfflictionRemains(self)
	if UnstableAffliction:casting() and UnstableAffliction:next() == self then
		return UnstableAffliction:duration()
	end
	return Ability.remains(self)
end

local function UnstableAfflictionUp(self)
	if UnstableAffliction:casting() and UnstableAffliction:next() == self then
		return true
	end
	return Ability.up(self)
end

local i
for i = 1, 5 do
	UnstableAffliction[i].remains = UnstableAfflictionRemains
	UnstableAffliction[i].up = UnstableAfflictionUp
end

local function SummonPetUp(self)
	if self:casting() then
		return true
	end
	if UnitIsDead('pet') then
		return false
	end
	return UnitCreatureFamily('pet') == self.pet_family
end

SummonDoomguard.up = SummonPetUp
SummonInfernal.up = SummonPetUp
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
	return min(4, max(UnitPower('player', SPELL_POWER_SOUL_SHARDS), self.shard_cost))
end

function CallDreadstalkers:shardCost()
	local cost = self.shard_cost
	if DemonicCalling:up() then
		cost = 0
	end
	if ItemEquipped.RecurrentRitual then
		cost = cost - 1
	end
	return cost
end

function AxeToss:usable(seconds)
	if not (SummonFelguard:up() or SummonWrathguard:up()) then
		return false
	end
	if Felstorm:up() or Wrathstorm:up() then
		return false
	end
	if not TargetIsStunnable() then
		return false
	end
	return self:ready(seconds)
end

-- End Ability Modifications

-- Start Summoned Pet Modifications

function Dreadstalker:count()
	local count = SummonedPet.count(self)
	if CallDreadstalkers:casting() then
		count = count + 2
	end
	return count
end

function Dreadstalker:remains()
	if CallDreadstalkers:casting() then
		return self.duration
	end
	return SummonedPet.remains(self)
end

function Dreadstalker:notEmpowered()
	local count = SummonedPet.notEmpowered(self)
	if CallDreadstalkers:casting() then
		count = count + 2
	end
	return count
end

function WildImp:count()
	local count = SummonedPet.count(self)
	if HandOfGuldan:casting() then
		count = count + 4
	end
	if ImprovedDreadstalkers.known and CallDreadstalkers:casting() then
		count = count + 2
	end
	if ImpendingDoom.known then
		count = count + Doom:soulShardsGeneratedDuringCast()
	end
	return count
end

function WildImp:remains()
	if HandOfGuldan:casting() or (ImprovedDreadstalkers.known and CallDreadstalkers:casting()) then
		return self.duration
	end
	return SummonedPet.remains(self)
end

function WildImp:notEmpowered()
	local count = SummonedPet.notEmpowered(self)
	if HandOfGuldan:casting() then
		count = count + 4
	end
	if ImprovedDreadstalkers.known and CallDreadstalkers:casting() then
		count = count + 2
	end
	if ImpendingDoom.known then
		count = count + Doom:soulShardsGeneratedDuringCast()
	end
	return count
end

-- End Summoned Pet Modifications

local function UpdateVars()
	local _, start, duration, remains, hp, hp_lost, spellId
	var.last_main = var.main
	var.last_cd = var.cd
	var.last_extra = var.extra
	var.main =  nil
	var.cd = nil
	var.extra = nil
	var.time = GetTime()
	start, duration = GetSpellCooldown(61304)
	var.gcd_remains = start > 0 and duration - (var.time - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	var.execute_remains = max(remains and (remains / 1000 - var.time) or 0, var.gcd_remains)
	var.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	var.gcd = 1.5 * var.haste_factor
	var.mana_regen = GetPowerRegen()
	var.mana_max = UnitPowerMax('player', 0)
	var.mana = min(var.mana_max, floor(UnitPower('player', 0) + (var.mana_regen * var.execute_remains)))
	var.soul_shards = GetAvailableSoulShards()
	var.pet = UnitGUID('pet')
	var.pet_exists = UnitExists('pet') and not UnitIsDead('pet')
	hp = UnitHealth('target')
	table.remove(Target.healthArray, 1)
	Target.healthArray[#Target.healthArray + 1] = hp
	Target.timeToDieMax = hp / UnitHealthMax('player') * 5
	Target.healthPercentage = Target.guid == 0 and 100 or (hp / UnitHealthMax('target') * 100)
	hp_lost = Target.healthArray[1] - hp
	Target.timeToDie = hp_lost > 0 and min(Target.timeToDieMax, hp / (hp_lost / 3)) or Target.timeToDieMax
end

local function UseCooldown(ability, overwrite, always)
	if always or (Opt.cooldown and (not Opt.boss_only or Target.boss) and (not var.cd or overwrite)) then
		var.cd = ability
	end
end

local function UseExtra(ability, overwrite, always)
	if always or (not var.extra or overwrite) then
		var.extra = ability
	end
end

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = function() end
}

APL[SPEC.AFFLICTION] = function()
	if TimeInCombat() == 0 then
		if Opt.healthstone and Healthstone:charges() == 0 and CreateHealthstone:usable() then
			return CreateHealthstone
		end
		if not PetIsSummoned() then
			return SummonImp
		end
		if GrimoireOfSacrifice.known then
			if GrimoireOfSacrifice:remains() < 300 then
				if PetIsSummoned() then
					return GrimoireOfSacrifice
				else
					return SummonImp
				end
			end
		elseif not PetIsSummoned() then
			return SummonImp
		end
		if Opt.pot and PotionOfProlongedPower:usable() then
			UseCooldown(PotionOfProlongedPower)
		end
	else
		if GrimoireOfSacrifice.known then
			if GrimoireOfSacrifice:remains() < 300 then
				if PetIsSummoned() then
					UseExtra(GrimoireOfSacrifice)
				else
					UseExtra(SummonImp)
				end
			end
		elseif not PetIsSummoned() then
			UseExtra(SummonImp)
		end
	end
end

APL[SPEC.DEMONOLOGY] = function()
	if TimeInCombat() == 0 then
		if Opt.healthstone and Healthstone:charges() == 0 and CreateHealthstone:usable() then
			return CreateHealthstone
		end
		if not PetIsSummoned() then
			return SummonImp
		end
		if GrimoireOfSacrifice.known then
			if GrimoireOfSacrifice:remains() < 300 then
				if PetIsSummoned() then
					return GrimoireOfSacrifice
				else
					return SummonImp
				end
			end
		elseif not PetIsSummoned() then
			return SummonImp
		end
		if Opt.pot and PotionOfProlongedPower:usable() then
			UseCooldown(PotionOfProlongedPower)
		end
	else
		if GrimoireOfSacrifice.known then
			if GrimoireOfSacrifice:remains() < 300 then
				if PetIsSummoned() then
					UseExtra(GrimoireOfSacrifice)
				else
					UseExtra(SummonImp)
				end
			end
		elseif not PetIsSummoned() then
			UseExtra(SummonImp)
		end
	end
end

APL[SPEC.DESTRUCTION] = function()
	if TimeInCombat() == 0 then
		if Opt.healthstone and Healthstone:charges() == 0 and CreateHealthstone:usable() then
			return CreateHealthstone
		end
		if not PetIsSummoned() then
			return SummonImp
		end
		if GrimoireOfSacrifice.known then
			if GrimoireOfSacrifice:remains() < 300 then
				if PetIsSummoned() then
					return GrimoireOfSacrifice
				else
					return SummonImp
				end
			end
		elseif not PetIsSummoned() then
			return SummonImp
		end
		if Opt.pot and PotionOfProlongedPower:usable() then
			UseCooldown(PotionOfProlongedPower)
		end
	else
		if GrimoireOfSacrifice.known then
			if GrimoireOfSacrifice:remains() < 300 then
				if PetIsSummoned() then
					UseExtra(GrimoireOfSacrifice)
				else
					UseExtra(SummonImp)
				end
			end
		elseif not PetIsSummoned() then
			UseExtra(SummonImp)
		end
	end
end

APL.Interrupt = function()
	if SummonDoomguard:up() and ShadowLock:ready() then
		return ShadowLock
	end
	if SummonFelhunter:up() and SpellLock:ready() then
		return SpellLock
	end
end

-- End Action Priority Lists

local function UpdateInterrupt()
	local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
	if not start then
		_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
	end
	if not start or notInterruptible then
		var.interrupt = nil
		doomedInterruptPanel:Hide()
		return
	end
	var.interrupt = APL.Interrupt()
	if var.interrupt then
		doomedInterruptPanel.icon:SetTexture(var.interrupt.icon)
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
			(Opt.glow.main and var.main and icon == var.main.icon) or
			(Opt.glow.cooldown and var.cd and icon == var.cd.icon) or
			(Opt.glow.interrupt and var.interrupt and icon == var.interrupt.icon) or
			(Opt.glow.extra and var.extra and icon == var.extra.icon)
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
	return (currentSpec == SPEC.NONE or
		   (currentSpec == SPEC.AFFLICTION and Opt.hide.affliction) or
		   (currentSpec == SPEC.DEMONOLOGY and Opt.hide.demonology) or
		   (currentSpec == SPEC.DESTRUCTION and Opt.hide.destruction))
end

local function Disappear()
	doomedPanel:Hide()
	doomedPanel.icon:Hide()
	doomedPanel.border:Hide()
	doomedCooldownPanel:Hide()
	doomedInterruptPanel:Hide()
	doomedExtraPanel:Hide()
	var.main, var.last_main = nil
	var.cd, var.last_cd = nil
	var.interrupt = nil
	var.extra, var.last_extra = nil
	UpdateGlows()
end

function Doomed_ToggleTargetMode()
	local mode = targetMode + 1
	Doomed_SetTargetMode(mode > #targetModes[currentSpec] and 1 or mode)
end

function Doomed_ToggleTargetModeReverse()
	local mode = targetMode - 1
	Doomed_SetTargetMode(mode < 1 and #targetModes[currentSpec] or mode)
end

function Doomed_SetTargetMode(mode)
	targetMode = min(mode, #targetModes[currentSpec])
	doomedPanel.targets:SetText(targetModes[currentSpec][targetMode][2])
end

function Equipped(name, slot)
	local function SlotMatches(name, slot)
		local ilink = GetInventoryItemLink('player', slot)
		if ilink then
			local iname = ilink:match('%[(.*)%]')
			return (iname and iname:find(name))
		end
		return false
	end
	if slot then
		return SlotMatches(name, slot)
	end
	local i
	for i = 1, 19 do
		if SlotMatches(name, i) then
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
		local p = ResourceFramePoints[resourceAnchor.name][currentSpec][Opt.snap]
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
		resourceAnchor.frame = NamePlatePlayerResourceFrame
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

local function UpdateHealthArray()
	Target.healthArray = {}
	local i
	for i = 1, floor(3 / Opt.frequency) do
		Target.healthArray[i] = 0
	end
end

local function UpdateCombat()
	abilityTimer = 0
	UpdateVars()
	var.main = APL[currentSpec]()
	if var.main ~= var.last_main then
		if var.main then
			doomedPanel.icon:SetTexture(var.main.icon)
			doomedPanel.icon:Show()
			doomedPanel.border:Show()
		else
			doomedPanel.icon:Hide()
			doomedPanel.border:Hide()
		end
	end
	if var.cd ~= var.last_cd then
		if var.cd then
			doomedCooldownPanel.icon:SetTexture(var.cd.icon)
			doomedCooldownPanel:Show()
		else
			doomedCooldownPanel:Hide()
		end
	end
	if var.extra ~= var.last_extra then
		if var.extra then
			doomedExtraPanel.icon:SetTexture(var.extra.icon)
			doomedExtraPanel:Show()
		else
			doomedExtraPanel:Hide()
		end
	end
	if Opt.dimmer then
		if not var.main then
			doomedPanel.dimmer:Hide()
		elseif var.main.spellId and IsUsableSpell(var.main.spellId) then
			doomedPanel.dimmer:Hide()
		elseif var.main.itemId and IsUsableItem(var.main.itemId) then
			doomedPanel.dimmer:Hide()
		else
			doomedPanel.dimmer:Show()
		end
	end
	if Opt.interrupt then
		UpdateInterrupt()
	end
	UpdateGlows()
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
		InitializeVariables()
		Azerite:initialize()
		UpdateHealthArray()
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

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags, dstRaidFlags, spellId, spellName, spellSchool, extraType = CombatLogGetCurrentEventInfo()
	if Opt.auto_aoe then
		if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
			if dstGUID == var.player then
				autoAoe:add(srcGUID)
			elseif srcGUID == var.player then
				autoAoe:add(dstGUID)
			end
		elseif eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
			autoAoe:remove(dstGUID)
		end
	end
	if srcGUID ~= var.player and srcGUID ~= var.pet then
		return
	end
	local castedAbility = abilityBySpellId[spellId]
	if not castedAbility then
		return
	end
--[[ DEBUG ]
	print(format('EVENT %s TRACK CHECK FOR %s ID %d', eventType, spellName, spellId))
	if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' or eventType == 'SPELL_PERIODIC_DAMAGE' or eventType == 'SPELL_DAMAGE' then
		print(format('%s: %s - time: %.2f - time since last: %.2f', eventType, spellName, timeStamp, timeStamp - (castedAbility.last_trigger or timeStamp)))
		castedAbility.last_trigger = timeStamp
	end
--[ DEBUG ]]
	if eventType == 'SPELL_CAST_SUCCESS' then
		var.last_ability = castedAbility
		castedAbility.last_used = GetTime()
		if castedAbility.triggers_gcd then
			PreviousGCD[10] = nil
			table.insert(PreviousGCD, 1, castedAbility)
		end
		if castedAbility.travel_start then
			castedAbility.travel_start[dstGUID] = castedAbility.last_used
		end
		if Opt.previous and doomedPanel:IsVisible() then
			doomedPreviousPanel.ability = castedAbility
			doomedPreviousPanel.border:SetTexture('Interface\\AddOns\\Automagically\\border.blp')
			doomedPreviousPanel.icon:SetTexture(castedAbility.icon)
			doomedPreviousPanel:Show()
		end
		if Opt.auto_aoe then
			if spellId == Corruption.spellId then
				if targetMode > 1 then
					Doomed_SetTargetMode(1)
				end
			elseif spellId == ShadowBolt.spellId then
				if targetMode > 2 then
					Doomed_SetTargetMode(2)
				end
			end
		end
		return
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if castedAbility.travel_start and castedAbility.travel_start[dstGUID] then
			castedAbility.travel_start[dstGUID] = nil
		end
		if Opt.auto_aoe and castedAbility.auto_aoe then
			castedAbility:recordTargetHit(dstGUID)
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and doomedPanel:IsVisible() and castedAbility == doomedPreviousPanel.ability then
			doomedPreviousPanel.border:SetTexture('Interface\\AddOns\\Automagically\\misseffect.blp')
		end
	end
	if castedAbility.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
			castedAbility:applyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' or eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
			castedAbility:removeAura(dstGUID)
		end
	end
	if petsByUnitName[dstName] then
		if eventType == 'SPELL_SUMMON' then
			petsByUnitName[dstName]:addUnit(dstGUID)
		elseif eventType == 'UNIT_DIED' or eventType == 'SPELL_INSTAKILL' then
			petsByUnitName[dstName]:removeUnit(dstGUID)
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
		Target.hostile = true
		Target.stunnable = false
		local i
		for i = 1, #Target.healthArray do
			Target.healthArray[i] = 0
		end
		if Opt.always_on then
			UpdateCombat()
			doomedPanel:Show()
			return true
		end
		return
	end
	if guid ~= Target.guid then
		Target.guid = guid
		Target.stunnable = TargetIsStunnable()
		local i
		for i = 1, #Target.healthArray do
			Target.healthArray[i] = UnitHealth('target')
		end
	end
	Target.level = UnitLevel('target')
	if UnitIsPlayer('target') then
		Target.boss = false
	elseif Target.level == -1 then
		Target.boss = true
	elseif var.instance == 'party' and Target.level >= UnitLevel('player') + 2 then
		Target.boss = true
	else
		Target.boss = false
	end
	Target.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if Target.hostile or Opt.always_on then
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
	combatStartTime = GetTime()
end

function events:PLAYER_REGEN_ENABLED()
	combatStartTime = 0
	local _, ability, guid
	for _, ability in next, abilities do
		if ability.travel_start then
			for guid in next, ability.travel_start do
				ability.travel_start[guid] = nil
			end
		end
		if ability.aura_targets then
			for guid in next, ability.aura_targets do
				ability.aura_targets[guid] = nil
			end
		end
	end
	if Opt.auto_aoe then
		for guid in next, autoAoe.targets do
			autoAoe.targets[guid] = nil
		end
		Automagically_SetTargetMode(1)
	end
	if var.last_ability then
		var.last_ability = nil
		doomedPreviousPanel:Hide()
	end
end

local function UpdateAbilityData()
	local _, ability
	for _, ability in next, abilities do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = (IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) or Azerite.traits[ability.spellId]) and true or false
	end
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName == 'player' then
		Azerite:update()
		UpdateAbilityData()
		local _, i
		for i = 1, #inventoryItems do
			inventoryItems[i].name, _, _, _, _, _, _, _, _, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId)
		end
		doomedPreviousPanel.ability = nil
		PreviousGCD = {}
		currentSpec = GetSpecialization() or 0
		Automagically_SetTargetMode(1)
		UpdateTargetInfo()
	end
end

function events:PLAYER_ENTERING_WORLD()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	if #glows == 0 then
		CreateOverlayGlows()
		HookResourceFrame()
	end
	local _
	_, var.instance = IsInInstance()
	var.player = UnitGUID('player')
	UpdateVars()
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
	abilityTimer = abilityTimer + elapsed
	if abilityTimer >= Opt.frequency then
		trackAuras:purge()
		if Opt.auto_aoe then
			local _, ability
			for _, ability in next, autoAoe.abilities do
				ability:updateTargetsHit()
			end
			autoAoe:purge()
		end
		UpdateCombat()
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
		if startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				doomedExtraPanel:SetScale(Opt.scale.extra)
			end
			return print('Doomed - Pet cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.extra .. '|r times')
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
			Opt.frequency = tonumber(msg[2]) or 0.05
			UpdateHealthArray()
		end
		return print('Doomed - Calculation frequency: Every |cFFFFD000' .. Opt.frequency .. '|r seconds')
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
		if startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Doomed - Glowing ability buttons (pet cooldown icon): ' .. (Opt.glow.extra and '|cFF00C000On' or '|cFFC00000Off'))
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
		return print('Automagically - Length of time target exists in auto AoE after being hit: |cFFFFD000' .. Opt.auto_aoe_ttl .. '|r seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return print('Doomed - Show Battle potions in cooldown UI: ' .. (Opt.pot and '|cFF00C000On' or '|cFFC00000Off'))
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
		'pot |cFF00C000on|r/|cFFC00000off|r - show Battle potions in cooldown UI',
		'healthstone |cFF00C000on|r/|cFFC00000off|r - show Create Healthstone reminder out of combat',
		'|cFFFFD000reset|r - reset the location of the Doomed UI to default',
	} do
		print('  ' .. SLASH_Doomed1 .. ' ' .. cmd)
	end
	print('Need to threaten with the wrath of doom? You can still use |cFFFFD000/wrath|r!')
	print('Got ideas for improvement or found a bug? Contact |cFF9482C9Baad|cFFFFD000-Dalaran|r or |cFFFFD000Spy#1955|r (the author of this addon)')
end
