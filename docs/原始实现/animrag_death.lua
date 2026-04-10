-- 核心数据结构（简化的全局表）
Orgn_Rag_Tb_Death = {}
Anim_Rag_Tb_Death = {}

-- 标准骨骼集合（用于阴影控制，也是动态移动表的默认全集）
local NrmTb = {
	["ValveBiped.Bip01_Pelvis"]     = true,
	["ValveBiped.Bip01_Spine1"]     = true,
	["ValveBiped.Bip01_Spine4"]     = true,
	["ValveBiped.Bip01_R_Thigh"]    = true,
	["ValveBiped.Bip01_R_Calf"]     = true,
	["ValveBiped.Bip01_R_Foot"]     = true,
	["ValveBiped.Bip01_L_Thigh"]    = true,
	["ValveBiped.Bip01_L_Calf"]     = true,
	["ValveBiped.Bip01_L_Foot"]     = true,
	["ValveBiped.Bip01_R_Clavicle"] = true,
	["ValveBiped.Bip01_R_UpperArm"] = true,
	["ValveBiped.Bip01_R_Forearm"]  = true,
	["ValveBiped.Bip01_R_Hand"]     = true,
	["ValveBiped.Bip01_L_Clavicle"] = true,
	["ValveBiped.Bip01_L_UpperArm"] = true,
	["ValveBiped.Bip01_L_Forearm"]  = true,
	["ValveBiped.Bip01_L_Hand"]     = true,
	["ValveBiped.Bip01_Head1"]      = true
}

-- 根据伤害类型/命中组选择动画的简化映射（硬编码）
local AnimMap = {
	fire      = { "death_fire_01", "death_fire_02" },
	explosion = { "death_explosion_01" },
	moving    = { "death_moving_01" },
	club      = { "death_blunt_01" },
	head      = { "death_headshot_01", "death_headshot_02" },
	neck      = { "death_neck_01" },
	torso     = { "death_torso_01", "death_torso_02" },
	pelvis    = { "death_pelvis_01" },
	back      = { "death_back_01" },
	leftarm   = { "death_leftarm_01" },
	rightarm  = { "death_rightarm_01" },
	leftleg   = { "death_leftleg_01" },
	rightleg  = { "death_rightleg_01" },
	shotgun   = { "death_shotgun_01" },
	default   = { "death_default_01" }
}

-- 动画名称选择函数（简化版）
local function ChooseDeathAnimation(damageType, hitGroup, isNeck, isShotgun, isPelvis, isBack)
	if damageType == "Fire" then
		return table.Random(AnimMap.fire)
	elseif damageType == "Explosion" then
		return table.Random(AnimMap.explosion)
	elseif damageType == "Moving" then
		return table.Random(AnimMap.moving)
	elseif damageType == "Club" then
		return table.Random(AnimMap.club)
	end

	-- 子弹类伤害根据命中组细分
	if hitGroup == 1 then
		if isNeck then
			return table.Random(AnimMap.neck)
		else
			return table.Random(AnimMap.head)
		end
	elseif isShotgun then
		return table.Random(AnimMap.shotgun)
	elseif hitGroup == 2 or hitGroup == 3 then
		if isPelvis then
			return table.Random(AnimMap.pelvis)
		elseif isBack then
			return table.Random(AnimMap.back)
		else
			return table.Random(AnimMap.torso)
		end
	elseif hitGroup == 4 then
		return table.Random(AnimMap.leftarm)
	elseif hitGroup == 5 then
		return table.Random(AnimMap.rightarm)
	elseif hitGroup == 6 then
		return table.Random(AnimMap.leftleg)
	elseif hitGroup == 7 then
		return table.Random(AnimMap.rightleg)
	end
	return table.Random(AnimMap.default)
end

-- 核心动画启动函数
function Animrag_Death_StartDeathAnimation(ONPC, Orgn_Rag)
	if not IsValid(ONPC) or not IsValid(Orgn_Rag) or not ONPC:LookupBone("ValveBiped.Bip01_Pelvis") then
		return
	end

	-- 禁用零尺寸骨骼的物理碰撞（原逻辑保留）
	for i = 0, Orgn_Rag:GetPhysicsObjectCount() - 1 do
		if Orgn_Rag:GetManipulateBoneScale(Orgn_Rag:TranslatePhysBoneToBone(i)) == Vector(0, 0, 0) then
			local phyObj = Orgn_Rag:GetPhysicsObjectNum(i)
			if phyObj then
				phyObj:EnableCollisions(false)
			end
		end
	end

	-- 选择动画名称
	local Animation = ChooseDeathAnimation(
		ONPC.arDmg or "Bullet",
		ONPC.arHit or 0,
		ONPC.arNeckshot or false,
		ONPC.arShotshot or false,
		ONPC.arPelvshot or false,
		ONPC.arBackshot or false
	)
	if not Animation then return end

	-- 设置血量（固定值，原逻辑中 ConVar 均为启用状态，此处直接取最大值）
	local NPCHp = ONPC:GetMaxHealth()
	Orgn_Rag.Hp_d = NPCHp * 0.5 -- 简化为 50% 最大血量作为动画持续血量

	-- 创建辅助动画实体
	local Anim_Rag = ents.Create("prop_dynamic")
	Anim_Rag:SetModel("models/brutal_deaths/model_anim_modify.mdl")
	Anim_Rag:SetPos(ONPC:GetPos())
	Anim_Rag:SetAngles(ONPC:GetAngles())
	Anim_Rag:Spawn()
	Anim_Rag:SetCollisionGroup(COLLISION_GROUP_WORLD)

	-- 获取动画时长并播放
	local _, Animation_Tm = Anim_Rag:LookupSequence(Animation)
	Anim_Rag:Fire("SetAnimation", Animation)

	-- 关联记录
	Anim_Rag.ORag = Orgn_Rag
	Orgn_Rag.ARag = Anim_Rag
	Orgn_Rag:SetNW2Int("Animation_State", 1)

	-- 动态生成移动表（此处直接使用 NrmTb 全集，代表自然移动模式）
	Orgn_Rag.arMoveTb = NrmTb
	Orgn_Rag.arMoveBone = {}
	for boneName, _ in pairs(Orgn_Rag.arMoveTb) do
		Orgn_Rag.arMoveBone[boneName] = {
			random  = Angle(math.Rand(-15, 15), math.Rand(-15, 15), 0),
			addpos  = Vector(0, 0, 0),
			lastAdd = Vector(0, 0, 0),
			lastHit = Vector(0, 0, 0),
			Fall    = false,
			HitWall = false,
			Gibbed  = false
		}
	end

	Orgn_Rag.Anim_Nm = Animation
	Orgn_Rag.Anim_Tm = Animation_Tm
	Orgn_Rag.Anim_St = CurTime() + Animation_Tm
	Orgn_Rag.Isdead_d = false
	Orgn_Rag.arFall = 0
	Orgn_Rag.arHitWall = 0

	-- 临时固定所有物理骨骼，下一帧恢复运动（保证初始对齐）
	for boneName, _ in pairs(NrmTb) do
		local boneID = Orgn_Rag:LookupBone(boneName)
		if boneID then
			local phyObj = Orgn_Rag:GetPhysicsObjectNum(Orgn_Rag:TranslateBoneToPhysBone(boneID))
			if IsValid(phyObj) then
				phyObj:EnableMotion(false)
			end
		end
	end
	timer.Simple(FrameTime(), function()
		if IsValid(Orgn_Rag) then
			for i = 0, Orgn_Rag:GetPhysicsObjectCount() - 1 do
				local phyObj = Orgn_Rag:GetPhysicsObjectNum(i)
				if IsValid(phyObj) then
					phyObj:EnableMotion(true)
				end
			end
		end
	end)

	-- 加入遍历表
	table.insert(Orgn_Rag_Tb_Death, Orgn_Rag)
	table.insert(Anim_Rag_Tb_Death, Anim_Rag)
end

-- 辅助函数：ComputeShadowControl 核心调用（原定义位于外部文件，此处精简保留关键逻辑）
function Animrag_ComputeShadowControl(ORag)
	if not IsValid(ORag) or not IsValid(ORag.ARag) then return end
	local ARag = ORag.ARag

	-- 遍历移动表内所有骨骼，将 ragdoll 骨骼跟随动画实体对应骨骼
	for boneName, _ in pairs(ORag.arMoveTb) do
		local boneID = ORag:LookupBone(boneName)
		local animBoneID = ARag:LookupBone(boneName)
		if boneID and animBoneID then
			local physID = ORag:TranslateBoneToPhysBone(boneID)
			if physID >= 0 then
				local phyObj = ORag:GetPhysicsObjectNum(physID)
				if IsValid(phyObj) then
					local animPos, animAng = ARag:GetBonePosition(animBoneID)
					if animPos then
						-- 施加随机微调（保持自然感）
						local randAng = ORag.arMoveBone[boneName].random
						animAng:RotateAroundAxis(animAng:Right(), randAng.p)
						animAng:RotateAroundAxis(animAng:Up(), randAng.y)
						animAng:RotateAroundAxis(animAng:Forward(), randAng.r)
						phyObj:SetPos(animPos)
						phyObj:SetAngles(animAng)
						phyObj:Wake()
					end
				end
			end
		end
	end
end

-- 动画终止函数（精简版）
function Animrag_EndAnimation(ORag, orgTable, animTable, mode)
	if not IsValid(ORag) then return end
	ORag.Isdead_d = true
	ORag:SetNW2Int("Animation_State", 0)

	-- 清除动画实体
	if IsValid(ORag.ARag) then
		ORag.ARag:Remove()
		ORag.ARag = nil
	end

	-- 从全局表中移除
	if orgTable then
		for k, v in pairs(orgTable) do
			if v == ORag then
				table.remove(orgTable, k)
				break
			end
		end
	end
	if animTable then
		for k, v in pairs(animTable) do
			if v.ORag == ORag then
				table.remove(animTable, k)
				break
			end
		end
	end

	-- 恢复物理骨骼的运动能力（确保不再被动画控制）
	for i = 0, ORag:GetPhysicsObjectCount() - 1 do
		local phyObj = ORag:GetPhysicsObjectNum(i)
		if IsValid(phyObj) then
			phyObj:EnableMotion(true)
		end
	end
end

-- 伤害记录钩子（精简，仅记录伤害类型与命中组）
hook.Add("ScaleNPCDamage", "Animrag_NPCHit_Core", function(ONPC, hitgrp, dmg)
	ONPC.arHit = hitgrp
	if dmg:GetDamageType() == DMG_BURN or ONPC:IsOnFire() then
		ONPC.arDmg = "Fire"
	elseif dmg:IsExplosionDamage() or dmg:GetDamageType() == DMG_BLAST then
		ONPC.arDmg = "Explosion"
	elseif ONPC:IsOnGround() and ((ONPC:IsPlayer() and ONPC:GetVelocity():LengthSqr() > math.pow(ONPC:GetWalkSpeed(), 2)) or (ONPC:IsNPC() and ONPC:GetIdealMoveSpeed() > 150)) then
		ONPC.arDmg = "Moving"
	elseif dmg:GetDamageType() == DMG_CLUB or dmg:GetDamageType() == DMG_CRUSH then
		ONPC.arDmg = "Club"
	else
		ONPC.arDmg = "Bullet"
	end

	local dmgpos = dmg:GetDamagePosition()
	ONPC.arNeckshot = false
	ONPC.arShotshot = false
	ONPC.arBackshot = false
	ONPC.arPelvshot = false

	if dmg:IsDamageType(DMG_BUCKSHOT) or dmg:GetAmmoType() == 7 then
		ONPC.arShotshot = true
		return
	end
	if ONPC:LookupBone("ValveBiped.Bip01_Head1") and hitgrp == 1 and dmgpos.z < ONPC:GetBonePosition(ONPC:LookupBone("ValveBiped.Bip01_Head1")).z then
		ONPC.arNeckshot = true
		return
	end
	if ONPC:GetForward():Dot((dmgpos - ONPC:GetPos()):GetNormalized()) < 0 then
		ONPC.arBackshot = true
		return
	end
	if ONPC:LookupBone("ValveBiped.Bip01_Pelvis") and dmgpos.z < (ONPC:GetBonePosition(ONPC:LookupBone("ValveBiped.Bip01_Pelvis")).z + 2) then
		ONPC.arPelvshot = true
		return
	end
end)

-- 伤害处理钩子：扣除动画血量
hook.Add("EntityTakeDamage", "Animrag_Damage_Core", function(ent, dmg)
	if ent:IsRagdoll() and ent.Hp_d and ent:GetNW2Int("Animation_State") == 1 then
		ent.Hp_d = ent.Hp_d - math.Round(dmg:GetDamage())
		if ent.Hp_d <= 0 and not ent.Isdead_d then
			Animrag_EndAnimation(ent, Orgn_Rag_Tb_Death, Anim_Rag_Tb_Death, "Death")
		end
	end
end)

-- 布娃娃创建钩子：触发死亡动画
hook.Add("CreateEntityRagdoll", "Animrag_CreateEntityRagdoll_Core", function(ONPC, Orgn_Rag)
	if not IsValid(ONPC) or not IsValid(Orgn_Rag) then return end
	ONPC.ORag = Orgn_Rag
	Animrag_Death_StartDeathAnimation(ONPC, Orgn_Rag)
end)

-- 主 Tick 驱动
hook.Add("Tick", "Animrag_MainTick_D_Core", function()
	if table.IsEmpty(Orgn_Rag_Tb_Death) then return end
	for k, ORag in pairs(Orgn_Rag_Tb_Death) do
		if IsValid(ORag) and IsValid(ORag.ARag) then
			-- 检查提前终止条件（示例：掉落或撞墙次数过多，但原逻辑中未在死亡动画中实际触发，此处仅保留基本时长检查）
			if CurTime() >= ORag.Anim_St and not ORag.Isdead_d then
				Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Death, Anim_Rag_Tb_Death, "Death")
			else
				-- 核心驱动：将布娃娃骨骼跟随动画实体
				Animrag_ComputeShadowControl(ORag)
			end
		end
	end
end)
