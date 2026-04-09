include("autorun/server/animrag_allconvar.lua")
include("autorun/server/animrag_allfunctions.lua")

util.AddNetworkString( "AnimRag_PoseFingerBone_sTc" )
util.AddNetworkString( "AnimRag_DrawHPDebugBar_sTc" )

util.AddNetworkString( "PlayerRag_StartDeathCam" )
util.AddNetworkString( "PlayerRag_PlayerSpawn" )
util.AddNetworkString( "PlayerRag_RotateHead" )

util.AddNetworkString( "CreateAnimRag_KeepCorpseOff_CreateRag_Death" )
util.AddNetworkString( "CreateAnimRag_KeepCorpseOff_TransfRag_Death" )
util.AddNetworkString( "CreateAnimRag_KeepCorpseOff_CreateRag_Crawl" )
util.AddNetworkString( "CreateAnimRag_KeepCorpseOff_TransfRag_Crawl" )
util.AddNetworkString( "CreateAnimRag_KeepCorpseOff_Crawl_Repeat" )
util.AddNetworkString( "CreateAnimRag_KeepCorpseOff_Crawl_PosAng" )
util.AddNetworkString( "CreateAnimRag_KeepCorpseOff_RemoveRag" )
util.AddNetworkString( "CreateAnimRag_KeepCorpseOff_cTs" )
util.AddNetworkString( "CreateAnimRag_KeepCorpseOff_sTc" )
	
util.AddNetworkString( "ChangeWeaponlist_cTs" )
util.AddNetworkString( "ChangeEndposition_cTs" )
util.AddNetworkString( "ChangeNPClist_cTs" )

file.CreateDir("enhanced_death_animations")

--[====[ 全局状态表：死亡动画中的布娃娃 ]====]
-- 用途：存储所有正在播放死亡动画的 Ragdoll 实体。
-- 抽象建议：可抽象为动画状态管理器。
Orgn_Rag_Tb_Death = {}

--[====[ 全局状态表：死亡动画中的动画代理 ]====]
-- 用途：存储与死亡动画对应的 Anim_Rag 实体。
Anim_Rag_Tb_Death = {}

--[====[ 全局状态表：所有 Ragdoll ]====]
-- 用途：记录地图上所有 Ragdoll，用于批量清理。
All_Rag_Tb = {}

--[====[ 数据配置：伤害类型到动画列表的映射表 ]====]
-- 用途：根据所受伤害类型，获取对应的死亡动画名称列表。
-- 抽象建议：可移至独立配置文件（如 anim_table.json）。
local AnimTb = {}

--[====[ 数据配置：正常骨骼名称列表 ]====]
-- 用途：存储标准人形骨骼名称。
-- 抽象建议：可定义为常量模块。
local NrmTb = {
    -- 包含骨盆、脊椎、四肢、头部等骨骼...
}

--[====[ 数据配置：运动骨骼表（动态）]====]
-- 用途：决定哪些骨骼跟随动画运动，其余骨骼自由落体。
-- 抽象建议：可设计为策略模式，不同预设对应不同运动约束。
local MoveTb_D = {}

--[====[ 数据配置：运动骨骼表预设1 ]====]
local MoveTb_1 = {
    -- 包含几乎所有骨骼...
}

--[====[ 数据配置：运动骨骼表预设2 ]====]
local MoveTb_2 = {
    -- 部分骨骼被注释（不跟随运动）...
}

--[====[ 数据配置：运动骨骼表预设3 ]====]
local MoveTb_3 = {
    -- 另一组骨骼配置...
}

--[====[ 数据配置：僵尸NPC类别表 ]====]
local Zombie_Tb = {
    -- 僵尸类NPC名称...
}

--[====[ 数据配置：半截僵尸NPC类别表 ]====]
local Zombie_Torso = {
    -- 只有躯干的僵尸类NPC...
}

--[====[ 配置：运动骨骼表选择 ]====]
-- 用途：选择默认的运动骨骼预设（假设功能全开）。
MoveTb_D = MoveTb_1

--[====[ 数据配置：武器列表（来自客户端）]====]
ar_Weaponlist = {}

--[====[ 数据配置：NPC列表（来自客户端）]====]
ar_NPClist = {}

--[====[ 数据配置：通用列表（来自客户端）]====]
ar_Everylist = {}

--[====[ 数据配置：动画结束位置百分比表 ]====]
ar_EndposTb = {}

--[====[ 初始化：从文件读取列表并建立映射 ]====]
hook.Add("PlayerInitialSpawn", "Animrag_GetLists_D", function()
	timer.Simple(0.5, function()
		-- 读取武器列表
		local weapon_file = file.Open("enhanced_death_animations/weaponlist.txt", "r", "DATA")
		ar_Weaponlist = util.JSONToTable( file.Read("enhanced_death_animations/weaponlist.txt", "DATA") )

		-- 读取NPC列表
		local npclist_file = file.Open("enhanced_death_animations/npclist.txt", "r", "DATA")
		ar_NPClist = util.JSONToTable( file.Read("enhanced_death_animations/npclist.txt", "DATA") )

		-- 读取everylist并转换为表格
		local everylist_file = file.Open("enhanced_death_animations/everylist.txt", "r", "DATA")
		local everylist_file_content = everylist_file:Read()
		everylist_file:Close()
		for word in string.gmatch(everylist_file_content, "[^,\n]+") do
			table.insert(ar_Everylist, word)
		end

		-- 从everylist构建ar_EndposTb
		for _, mixName in pairs(ar_Everylist) do
			local store = {}
			for v in string.gmatch(mixName, "[^/]+") do
				table.insert(store, v)
			end
			local mix = {}
			mix.cent = store[1]
			mix.name = store[2]
			table.insert(ar_EndposTb, mix)
		end
	end)
end)

--[====[ 网络接收：更新武器列表 ]====]
net.Receive("ChangeWeaponlist_cTs", function()
	ar_Weaponlist = net.ReadTable()
end)

--[====[ 网络接收：更新NPC列表 ]====]
net.Receive("ChangeNPClist_cTs", function()
	ar_NPClist = net.ReadTable()
end)

--[====[ 网络接收：更新动画结束位置百分比 ]====]
net.Receive("ChangeEndposition_cTs", function()
	ar_EndposTb = net.ReadTable()
end)

--[====[ 辅助函数：获取动画结束百分比 ]====]
-- 功能说明：根据动画名称查找对应的结束位置百分比。
-- 抽象建议：可归入动画配置查询模块。
function Animrag_Death_GetEndPos(anim)
	local percent = 100
	for k, v in pairs(ar_EndposTb) do
		if v.name == anim then
			percent = v.cent
		end
	end
	return percent
end

--[====[ 辅助函数：从动画列表中移除黑名单条目 ]====]
-- 功能说明：过滤掉黑名单中的动画，确保不会播放禁用动画。
-- 抽象建议：可扩展为通用的集合过滤工具。
function Animrag_Death_RemoveBlacklist(tb, blacklist)
	for k, black in pairs(blacklist) do
		for i = #tb, 1, -1 do
			if tb[i] == black then
				table.remove(tb, i)
			end
		end
	end
	return tb
end

--[====[ 核心决策：选择死亡动画 ]====]
-- 功能说明：根据NPC受伤部位、伤害类型、黑名单等选择具体的死亡动画。
-- 抽象建议：属于“动画选择策略”，可提取为独立的决策器模块。
function Animrag_Death_AnimChoose(ONPC)
	-- 读取黑名单
	local blacklist = {}
	local blacklist_file = file.Open("enhanced_death_animations/blacklist.txt", "r", "DATA")
	local blacklist_file_content = blacklist_file:Read()
	blacklist_file:Close()
	for word in string.gmatch(blacklist_file_content, "[^,\n]+") do
		table.insert(blacklist, word)
	end

	-- 读取动画配置表
	AnimTb = util.JSONToTable( file.Read("enhanced_death_animations/anim_table.txt", "DATA") )

	local anim
	local isHead = false
	local isFire = false
	local fixTb = {}

	-- 根据伤害类型选择动画组
	if ONPC.arDmg == "Fire" then
		fixTb = Animrag_Death_RemoveBlacklist(AnimTb["fire"], blacklist)
		anim = table.Random(fixTb)
		isFire = true
	elseif ONPC.arDmg == "Explosion" then
		fixTb = Animrag_Death_RemoveBlacklist(AnimTb["exp"], blacklist)
		anim = table.Random(fixTb)
	elseif ONPC.arDmg == "Moving" then
		fixTb = Animrag_Death_RemoveBlacklist(AnimTb["moving"], blacklist)
		anim = table.Random(fixTb)
	elseif ONPC.arDmg == "Club" then
		fixTb = Animrag_Death_RemoveBlacklist(AnimTb["club"], blacklist)
		anim = table.Random(fixTb)
	else
		-- 子弹伤害，根据击中部位细分
		if ONPC.arHit == 1 then
			if ONPC.arNeckshot then
				fixTb = Animrag_Death_RemoveBlacklist(AnimTb["bd_neck"], blacklist)
				anim = table.Random(fixTb)
			else
				fixTb = Animrag_Death_RemoveBlacklist(AnimTb["bd_head"], blacklist)
				anim = table.Random(fixTb)
			end
			isHead = true
		elseif ONPC.arShotshot then
			fixTb = Animrag_Death_RemoveBlacklist(AnimTb["bd_shotgun"], blacklist)
			anim = table.Random(fixTb)
		elseif ONPC.arHit == 2 or ONPC.arHit == 3 then
			if ONPC.arPelvshot then
				fixTb = Animrag_Death_RemoveBlacklist(AnimTb["bd_pelvis"], blacklist)
				anim = table.Random(fixTb)
			elseif ONPC.arBackshot then
				fixTb = Animrag_Death_RemoveBlacklist(AnimTb["bd_back"], blacklist)
				anim = table.Random(fixTb)
			else
				fixTb = Animrag_Death_RemoveBlacklist(AnimTb["bd_torso"], blacklist)
				anim = table.Random(fixTb)
			end
		elseif ONPC.arHit == 4 then
			fixTb = Animrag_Death_RemoveBlacklist(AnimTb["bd_larm"], blacklist)
			anim = table.Random(fixTb)
		elseif ONPC.arHit == 5 then
			fixTb = Animrag_Death_RemoveBlacklist(AnimTb["bd_rarm"], blacklist)
			anim = table.Random(fixTb)
		elseif ONPC.arHit == 6 then
			fixTb = Animrag_Death_RemoveBlacklist(AnimTb["bd_lleg"], blacklist)
			anim = table.Random(fixTb)
		elseif ONPC.arHit == 7 then
			fixTb = Animrag_Death_RemoveBlacklist(AnimTb["bd_rleg"], blacklist)
			anim = table.Random(fixTb)
		else
			fixTb = Animrag_Death_RemoveBlacklist(AnimTb["dying"], blacklist)
			anim = table.Random(fixTb)
		end
	end

	return anim, isHead, isFire
end

--[====[ 辅助函数：获取敌我关系表 ]====]
-- 功能说明：分析NPC周围的敌人和友军，用于爬行时的回避逻辑和复活机制。
-- 抽象建议：属于“感知模块”，可提取为独立的敌对关系分析器。
function Animrag_Death_GetDispositionTb(ONPC, Orgn_Rag)
	local Hostile1 = {}
	local Hostile2 = {}
	local Hostile  = {}
	local Friends  = {}

	-- 遍历所有实体，建立敌友关系
	for _, other_npc in pairs(ents.GetAll()) do
		if other_npc:IsNPC() then
			local D = other_npc:Disposition(ONPC)
			if D == D_HT or D == D_FR then
				table.insert(Hostile1, other_npc)
			elseif D == D_LI then
				table.insert(Friends, other_npc)
			else
				if other_npc:GetClass() == ONPC:GetClass() then
					table.insert(Friends, other_npc)
				end
			end
		elseif other_npc:IsPlayer() and ONPC:IsNPC() then
			local D = ONPC:Disposition(other_npc)
			if D == D_HT or D == D_FR then
				Orgn_Rag:SetNW2Bool("EnemyPlayer: " .. tostring(other_npc), true)
				table.insert(Hostile1, other_npc)
			elseif D == D_LI then
				table.insert(Friends, other_npc)
			else
				if other_npc:GetClass() == ONPC:GetClass() then
					table.insert(Friends, other_npc)
				end
			end
		end
	end

	-- 将所有玩家加入敌对（假设配置开启）
	for _, PLY in pairs(player.GetAll()) do
		table.insert(Hostile1, PLY)
	end

	-- 去重
	for _, v in pairs(Hostile1) do
		Hostile2[v] = true
	end
	for k, _ in pairs(Hostile2) do
		table.insert(Hostile, k)
	end

	return Hostile, Friends
end

--[====[ 核心函数：启动死亡动画 ]====]
-- 功能说明：NPC死亡时创建Anim_Rag，配置运动参数，开始映射动画到Ragdoll。
-- 抽象建议：属于“动画生命周期管理”中的“启动”环节，后续可拆分为初始化、配置、启动三个子阶段。
function Animrag_Death_StartDeathAnimation(ONPC, Orgn_Rag)
	-- 记录Ragdoll到全局清理表
	table.insert(All_Rag_Tb, Orgn_Rag)

	--[====[ 第1步：处理肢解导致的碰撞禁用 ]====]
	-- 功能说明：遍历物理对象，若骨骼被缩放为0（肢解），则禁用其碰撞。
	-- 抽象建议：属于“肢解兼容”逻辑，可抽象为GibCollisionHandler。
	for i=0, Orgn_Rag:GetPhysicsObjectCount()-1 do
		if Orgn_Rag:GetManipulateBoneScale(Orgn_Rag:TranslatePhysBoneToBone(i)) == Vector(0, 0, 0) then
			local phyObj = Orgn_Rag:GetPhysicsObjectNum(i)
			phyObj:EnableCollisions(false)
		end
	end

	--[====[ 第2步：纠正复活中的敌友关系 ]====]
	-- 功能说明：如果该NPC在复活过程中被击杀，需恢复原始关系。
	-- 抽象建议：属于“复活状态回滚”，可提取为RelationshipManager。
	if ONPC.RevivingTB then
		for _, ply in pairs(player.GetAll()) do
			if ONPC.RevivingTB and ONPC.RevivingTB.Relation_PLY then
				if ONPC.RevivingTB.Relation_PLY[ply] then
					ONPC:AddEntityRelationship(ply, ONPC.RevivingTB.Relation_PLY[ply], 99)
				end
			end
		end
		for _, other_npc in ipairs(ents.GetAll()) do
			if ONPC.RevivingTB and ONPC.RevivingTB.Relation_PLY then
				if other_npc:IsNPC() and ONPC.RevivingTB.Relation_NPC[other_npc] then
					ONPC:AddEntityRelationship(other_npc, ONPC.RevivingTB.Relation_NPC[other_npc], 99)
				end
			end
		end
	end

	--[====[ 第3步：检查NPC列表黑名单 ]====]
	-- 功能说明：如果NPC的模型在ar_NPClist中，则不播放死亡动画。
	-- 抽象建议：属于“动画过滤”逻辑，可提取为AnimationBlocker。
	for k, v in pairs(ar_NPClist) do
		if v == ONPC:GetModel() then return end
	end

	--[====[ 第4步：获取动画所需参数 ]====]
	local NPCHp = ONPC:GetMaxHealth()
	local Animation, isHead, isFire = Animrag_Death_AnimChoose(ONPC)

	--[====[ 第5步：判断是否为僵尸并检查相关开关 ]====]
	local isZombie = false
	if Zombie_Tb[ONPC:GetClass()] then
		isZombie = true
	end
	if isZombie then return end
	if Zombie_Torso[ONPC:GetClass()] then return end

	--[====[ 第6步：玩家死亡的特殊处理（传递数据给摄像机） ]====]
	if ONPC:IsPlayer() then
		ONPC:SetNW2Bool("PlayerIsDeadNow", true)
		ONPC:SetNW2Int("PlayerORagID", Orgn_Rag:EntIndex())
		ONPC.arWeapons = {}
		for k, wep in pairs(ONPC:GetWeapons()) do
			table.insert(ONPC.arWeapons, wep:GetClass())
		end
		Orgn_Rag:SetNW2Bool("isPlayer", true)
		Orgn_Rag:SetNW2String("isPlayer_Name", ONPC:Nick())
		Orgn_Rag.OwnerPLY = ONPC

		net.Start("PlayerRag_StartDeathCam")
			net.WriteInt(Orgn_Rag:EntIndex(), 32)
		net.Send(ONPC)
	end
	
	--[====[ 第7步：伤口捂住逻辑 ]====]
	-- 功能说明：根据最后受伤位置，让Ragdoll做出捂住伤口的姿态。
	-- 抽象建议：属于“反应动画”，可提取为WoundReaction模块。
	if ONPC.ClosestHitPos and ONPC.ClosestHitPos != Vector(0, 0, 0) then
		Animrag_GetDamagedBone(Orgn_Rag, ONPC.ClosestHitPos)
		Animrag_Writhe_GrabWound(Orgn_Rag, Orgn_Rag.ClosestHitPos, Orgn_Rag.ClosestPhyID)
	end

	--[====[ 第8步：增加Ragdoll重量 ]====]
	-- 功能说明：使Ragdoll更重，增加真实感。
	-- 抽象建议：属于“物理调优”，可提取为PhysicsTweaker。
	if not Orgn_Rag.AlreadyHeavier then
		for i=0, Orgn_Rag:GetPhysicsObjectCount()-1 do
			local phyObj = Orgn_Rag:GetPhysicsObjectNum(i)
			local mass = phyObj:GetMass()
			phyObj:SetMass(mass*2)
		end
		Orgn_Rag.AlreadyHeavier = true
	end

	--[====[ 第9步：死亡动画核心逻辑 ]====]
	-- 功能说明：创建Anim_Rag，播放选定动画，并准备所有运动参数。
	-- 抽象建议：属于“动画映射引擎”的核心启动流程。
	if Animation then
		-- 计算Ragdoll的“超杀”生命值（假设超杀未启用，设为极大值）
		Orgn_Rag.Hp_d = 9999

		-- 创建动画代理实体
		local Anim_Rag = ents.Create("prop_dynamic")
		Anim_Rag:SetModel("models/brutal_deaths/model_anim_modify.mdl")
		Anim_Rag:SetPos(ONPC:GetPos())
		Anim_Rag:SetAngles(ONPC:GetAngles())
		Anim_Rag:Spawn()
		Anim_Rag:SetCollisionGroup(COLLISION_GROUP_WORLD)
	
		-- 获取NPC身高用于缩放
		if ONPC:LookupAttachment('eyes') > 0 then
			local eye_height = ONPC:GetAttachment(ONPC:LookupAttachment('eyes')).Pos.z
			local npc_origin = ONPC:GetPos().z
			Orgn_Rag.BodyHeight = math.abs(eye_height-npc_origin)
		end

		-- 缩放Anim_Rag以匹配Ragdoll尺寸
		Animrag_ScaleAnimRag(Orgn_Rag, Anim_Rag)		
		
		-- 播放动画
		local _, Animation_Tm = Anim_Rag:LookupSequence(Animation)
		local Animation_Endpos = Animrag_Death_GetEndPos(Animation)
		Animation_Tm = Animation_Tm * (Animation_Endpos/100)
		Anim_Rag:Fire("SetAnimation", Animation)
		if isFire then Orgn_Rag:Ignite(Animation_Tm + math.Rand(5, 20)) end

		-- 双向关联
		Anim_Rag.ORag = Orgn_Rag
		Orgn_Rag.ARag = Anim_Rag

		-- 设置动画状态标记
		Orgn_Rag:SetNW2Int("Animation_State", 1)
		Orgn_Rag.arMoveTb = MoveTb_D
		Orgn_Rag.arMoveBone = {}
		for boneName, _ in pairs(Orgn_Rag.arMoveTb) do
			Orgn_Rag.arMoveBone[boneName] = {}
			Orgn_Rag.arMoveBone[boneName]["random"] = Angle(math.Rand(-15, 15), math.Rand(-15, 15), 0)
			Orgn_Rag.arMoveBone[boneName]["addpos"] = Vector(0, 0, 0)
			Orgn_Rag.arMoveBone[boneName]["lastAdd"] = Vector(0, 0, 0)
			Orgn_Rag.arMoveBone[boneName]["lastHit"] = Vector(0, 0, 0)
			Orgn_Rag.arMoveBone[boneName]["Fall"] = false
			Orgn_Rag.arMoveBone[boneName]["HitWall"] = false
			Orgn_Rag.arMoveBone[boneName]["Gibbed"] = false
		end

		-- 记录动画元数据
		Orgn_Rag.Anim_Nm = Animation
		Orgn_Rag.Anim_Tm = Animation_Tm
		Orgn_Rag.Anim_St = Animation_Tm + CurTime()
		Orgn_Rag.arHeadID = Orgn_Rag:LookupBone("ValveBiped.Bip01_Head1")
		Orgn_Rag.Isdead_d = false
		Orgn_Rag.arFall = 0
		Orgn_Rag.arHitWall = 0

		-- 临时禁用所有骨骼运动，防止子弹冲击干扰
		for boneName, _ in pairs(NrmTb) do
			local boneID = Orgn_Rag:LookupBone(boneName)
			if boneID then
				local phyObj = Orgn_Rag:GetPhysicsObjectNum(Orgn_Rag:TranslateBoneToPhysBone(boneID))
				phyObj:EnableMotion(false)
			end
		end
		
		timer.Simple(FrameTime(), function()
			for i=0, Orgn_Rag:GetPhysicsObjectCount()-1 do
				local phyObj = Orgn_Rag:GetPhysicsObjectNum(i)
				phyObj:EnableMotion(true)
			end
		end)

		-- 加入全局动画队列
		table.insert(Orgn_Rag_Tb_Death, Orgn_Rag)
		table.insert(Anim_Rag_Tb_Death, Anim_Rag)
	end

	--[====[ 第10步：爬行/挣扎动画的准入条件 ]====]
	-- 功能说明：决定该Ragdoll是否允许后续进入爬行或挣扎状态。
	-- 抽象建议：属于“状态转移条件”，可提取为StateTransitionGuard。
	Orgn_Rag.CanCrawl_Writhe = false
	if not isZombie and isHead then return end
	if isFire then return end
	if ONPC.DmgOverflow then return end
	if IsValid(ONPC.arDmgInfo) and ONPC.arDmgInfo != NULL and bit.band(ONPC.arDmgInfo:GetDamageType(), DMG_CLUB) ~= 0 then return end

	Orgn_Rag.CanCrawl_Writhe = true
	Orgn_Rag.NoMoreCrawl = ONPC.NoMoreCrawl

	-- 获取敌友关系
	local Hostile, Friends = Animrag_Death_GetDispositionTb(ONPC, Orgn_Rag)

	-- 获取NPC关键值
	local NPCKeyValue = ONPC:GetTable() and ONPC:GetTable().NPCTable and ONPC:GetTable().NPCTable.KeyValues or {}

	-- 保存爬行/复活所需参数
	Orgn_Rag.arNPCHp   = NPCHp
	Orgn_Rag.arHostile = Hostile
	Orgn_Rag.arFriends = Friends
	Orgn_Rag.arSpClass = ONPC:GetClass()
	Orgn_Rag.arWeapons = ONPC.arWeapons
	Orgn_Rag.arNPCKeyValue = Animrag_CopyTable(NPCKeyValue)
end

--[====[ 钩子：NPC死亡生成Ragdoll ]====]
-- 功能说明：当NPC死亡变成Ragdoll时，调用死亡动画启动函数。
-- 抽象建议：属于“事件监听”层，可保留为轻量级适配器。
hook.Add("CreateEntityRagdoll", "Animrag_CreateEntityRagdoll", function(ONPC, Orgn_Rag)
	if ONPC.WaitingForReplace then
		Ragdollize_NPC(ONPC)
	end

	ONPC.ORag = Orgn_Rag
	if ONPC.NRag then
		ONPC.ORag = Ragdollize_SwitchRagdoll(ONPC)
	end

	Animrag_Death_StartDeathAnimation(ONPC, ONPC.ORag)
end)

--[====[ 钩子：获取NPC武器列表 ]====]
hook.Add("OnNPCKilled", "Animrag_OnNPCKilled", function(ONPC, attacker, inflictor)
	if ONPC:IsNPC() then
		if ONPC:GetWeapons() then
			ONPC.arWeapons = {}
			for k, wep in pairs(ONPC:GetWeapons()) do
				table.insert(ONPC.arWeapons, wep:GetClass())
			end
		end
	end
end)

--[====[ 主Tick：死亡动画骨骼映射 ]====]
-- 功能说明：每帧计算Anim_Rag的骨骼位置/角度，并应用到Ragdoll上。
-- 抽象建议：属于“动画映射引擎”的核心循环，可抽象为BonePoseSolver。
hook.Add("Tick", "Animrag_MainTick_D", function()
	for k, ORag in pairs(Orgn_Rag_Tb_Death) do
		--[====[ 终止条件：坠落或撞墙过多 ]====]
		if ORag.arFall >= 5 or ORag.arHitWall >= table.Count(ORag.arMoveTb) then 
			Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Death, Anim_Rag_Tb_Death, "Death")
		end

		--[====[ 核心映射计算 ]====]
		Animrag_ComputeShadowControl(ORag)

		--[====[ 终止条件：动画播放完毕 ]====]
		if CurTime() >= ORag.Anim_St and not ORag.Isdead_d then
			Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Death, Anim_Rag_Tb_Death, "Death")
		end
	end
end)

--[====[ 钩子：记录NPC所受伤害信息 ]====]
-- 功能说明：在NPC受伤时记录击中部位、伤害类型等，供动画选择使用。
-- 抽象建议：属于“伤害分析”模块，可提取为DamageAnalyzer。
hook.Add("ScaleNPCDamage", "Animrag_NPCHit", function(ONPC, hitgrp, dmg)
	ONPC.arHit = hitgrp
	ONPC.arDmgInfo = dmg

	-- 判断伤害类型
	if dmg:GetDamageType() == DMG_BURN or ONPC:IsOnFire() then
		ONPC.arDmg = "Fire"
	elseif dmg:IsExplosionDamage() or dmg:GetDamageType() == DMG_BLAST then
		ONPC.arDmg = "Explosion"
	elseif ONPC:IsOnGround() and ((ONPC:IsPlayer() and ONPC:GetVelocity():LengthSqr() > math.pow(ONPC:GetWalkSpeed(), 2)) or (ONPC:IsNPC() and ONPC:GetIdealMoveSpeed() > 150)) then
		ONPC.arDmg = "Moving"
	elseif (dmg:GetDamageType() == DMG_CLUB or dmg:GetDamageType() == DMG_CRUSH) then
		ONPC.arDmg = "Club"
	else
		ONPC.arDmg = "Bullet"
	end

	-- 武器超越控制
	local attacker = dmg:GetAttacker()
	if attacker:IsNPC() or attacker:IsPlayer() then 
		local awep = attacker:GetActiveWeapon()
		if ar_Weaponlist then
			for k, v in pairs(ar_Weaponlist) do
				if v.wep == awep:GetPrintName() then
					ONPC.arDmg = v.typ
				end
			end
		end
	end

	local dmgpos = dmg:GetDamagePosition()

	ONPC.arNeckshot = false
	ONPC.arShotshot = false
	ONPC.arBackshot = false
	ONPC.arPelvshot = false

	if ONPC.arDmg == "Shotgun" then
		ONPC.arDmg = "Bullet"
		ONPC.arShotshot = true
		return
	end

	if ONPC:LookupBone("ValveBiped.Bip01_Head1") and (ONPC.arHit == 1 and dmgpos.z < ONPC:GetBonePosition(ONPC:LookupBone("ValveBiped.Bip01_Head1")).z) then
		ONPC.arNeckshot = true
		return
	end
	
	if (dmg:IsDamageType(DMG_BUCKSHOT) or dmg:GetAmmoType() == 7) then
		ONPC.arShotshot = true
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

--[====[ 钩子：处理Ragdoll受到的伤害（超杀、头部终结等）]====]
-- 功能说明：在Ragdoll状态下受到伤害时，更新超杀生命值或直接终止动画。
-- 抽象建议：属于“伤害反馈”模块，可提取为DamageReactionSystem。
hook.Add("EntityTakeDamage", "Animrag_Damage", function(ent, dmg)
	if ent:IsNPC() or ent:IsRagdoll() then 
		-- 记录受伤位置及对应骨骼
		if ent:IsNPC() then
			ent.ClosestHitPos = dmg:GetDamagePosition()
		elseif ent:IsRagdoll() then
			Animrag_GetDamagedBone(ent, dmg:GetDamagePosition())
		end

		-- 火焰伤害标记
		if ent:IsNPC() and ent:IsOnFire() then
			ent.arDmg = "Fire"
		end	

		-- 伤害溢出标记（简化：假设未启用）
		if ent:IsNPC() then
			local ONPC = ent
			-- 原Overflow逻辑已移除，假设不触发
		end

		-- Ragdoll受伤处理
		if ent:IsRagdoll() then
			local ORag = ent

			-- 头部受伤（非挤压）则立即终止当前动画
			if ORag.ClosestBoneName == "ValveBiped.Bip01_Head1" and dmg:GetDamageType() != DMG_CRUSH then
				if ORag:GetManipulateBoneScale(ORag:LookupBone("ValveBiped.Bip01_Head1")) != Vector(0, 0, 0) then
					local AnimState = ORag:GetNW2Int("Animation_State")
					if AnimState == 1 then
						if ORag.Hp_c then
							ORag.PreStop = true
							Animrag_EndAnimation(ORag, nil, nil, "Crawl")
						else
							Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Death, Anim_Rag_Tb_Death, "Death")
						end
					elseif AnimState == 2 then
						Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Crawl, Anim_Rag_Tb_Crawl, "Writhe")				
					else
						Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Crawl, Anim_Rag_Tb_Crawl, "Crawl")				
					end
				end
			end

			-- 动画中的伤害缩放（挤压伤害缩放已移除）
			if ORag:GetNW2Int("Animation_State") >= 1 then
				dmg:SetDamage(math.Round(dmg:GetDamage()))
			end
		end
		
		-- 死亡动画中的超杀生命值计算
		if ent:IsRagdoll() and ent.Hp_d and not ent.IsRagdollizedRagdoll2 then
			local ORag = ent
			ORag.Hp_d = ORag.Hp_d - math.Round(dmg:GetDamage())
			if ORag.Hp_d <= 0 and not ORag.Isdead_d then
				Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Death, Anim_Rag_Tb_Death, "Death")
			end
		end

		-- 爬行/挣扎/复活动画中的生命值计算
		if ent:IsRagdoll() then
			local ORag = ent
			local AnimState = ORag:GetNW2Int("Animation_State")
				
			if AnimState == 1 and ORag.Hp_c then
				ORag.Hp_c = ORag.Hp_c - dmg:GetDamage()
				if ORag.Hp_c <= 0 and not ORag.PreStop then
					ORag.PreStop = true
					Animrag_EndAnimation(ORag, nil, nil, "Crawl")
				end
			end
	
			if AnimState >= 2 and ORag.Hp_c and dmg:GetDamageType() != DMG_CRUSH then
				ORag.Hp_c = ORag.Hp_c - dmg:GetDamage()
				if ORag.Hp_c <= 0 and not ORag.Isdead_c then
					if AnimState == 2 then
						Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Crawl, Anim_Rag_Tb_Crawl, "Writhe")
					else
						Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Crawl, Anim_Rag_Tb_Crawl, "Crawl")
					end
				end
			end
		end
	end
end)

--[====[ 钩子：玩家死亡 - 方案A ]====]
hook.Add("DoPlayerDeath", "Animrag_PlayerDeath", function(ply)
	timer.Simple(FrameTime(), function()
		ply:GetRagdollEntity():Remove()
	end)

	local NewRag = ents.Create("prop_ragdoll")
	NewRag:SetModel(ply:GetModel())
	NewRag:SetColor(ply:GetColor())
	NewRag:SetSkin(ply:GetSkin())
	for k, v in pairs(ply:GetBodyGroups()) do
		NewRag:SetBodygroup(v.id, ply:GetBodygroup(v.id))
	end
	NewRag:SetPos(ply:GetPos())
	NewRag:SetAngles(ply:GetAngles())
	NewRag:Spawn()
	NewRag:Activate()

	for i = 0, NewRag:GetPhysicsObjectCount() - 1 do
		local NewPhyBone = NewRag:GetPhysicsObjectNum( i )
		local boneName = NewRag:GetBoneName(NewRag:TranslatePhysBoneToBone(i))
		local pos, ang = ply:GetBonePosition(ply:LookupBone(boneName))
		if pos then NewPhyBone:SetPos( pos ) end
		if ang then NewPhyBone:SetAngles( ang ) end
	end

	Animrag_Death_StartDeathAnimation(ply, NewRag)

	-- 动态表情（假设启用）
	DynamicExpression_Initialize(NewRag)
	DynamicExpression_Start(NewRag, true)
end)

--[====[ 钩子：玩家死亡 - 方案B ]====]
hook.Add("PlayerDeath", "Animrag_PlayerDeath2", function(ply)
	ply:SetShouldServerRagdoll(true)
end)
hook.Add("PostPlayerDeath","Animrag_PlayerDeath22", function(ply)
	local PRag = ply:GetRagdollEntity()
	PRag:Remove()
end)

--[====[ 钩子：玩家重生清理 ]====]
hook.Add("PlayerSpawn", "Animrag_PlayerSpawn", function(ply)
	if ply:GetNW2Int("PlayerORagID") != 0 then
		local ORag = Entity(ply:GetNW2Int("PlayerORagID"))
		if ORag:GetNW2Int("Animation_State") >= 2 then
			Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Crawl, Anim_Rag_Tb_Crawl, "Crawl")
		end
	end

	ply:SetNW2Bool("PlayerIsDeadNow", false)
	ply:SetNW2Int("PlayerORagID", nil)

	net.Start("PlayerRag_PlayerSpawn")
	net.Send(ply)
end)

--[====[ 钩子：记录玩家受伤信息 ]====]
hook.Add("ScalePlayerDamage", "Animrag_PlayerHit", function(PLY, hitgrp, dmg)
	PLY.arHit = hitgrp

	if dmg:GetDamageType() == DMG_BURN or PLY:IsOnFire() then
		PLY.arDmg = "Fire"
	elseif dmg:IsExplosionDamage() or dmg:GetDamageType() == DMG_BLAST then
		PLY.arDmg = "Explosion"
	elseif PLY:IsOnGround() and PLY:GetVelocity():LengthSqr() >= math.pow(PLY:GetWalkSpeed(), 2) then
		PLY.arDmg = "Moving"
	elseif (dmg:GetDamageType() == DMG_CLUB or dmg:GetDamageType() == DMG_CRUSH) then
		PLY.arDmg = "Club"
	else
		PLY.arDmg = "Bullet"
	end

	local attacker = dmg:GetAttacker()
	if attacker:IsNPC() or attacker:IsPlayer() then 
		local awep = attacker:GetActiveWeapon()
		if ar_Weaponlist then
			for k, v in pairs(ar_Weaponlist) do
				if v.wep == awep:GetPrintName() then
					PLY.arDmg = v.typ
				end
			end
		end
	end

	local dmgpos = dmg:GetDamagePosition()
	
	PLY.arNeckshot = false
	PLY.arShotshot = false
	PLY.arPelvshot = false

	if PLY.arDmg == "Shotgun" then
		PLY.arDmg = "Bullet"
		PLY.arShotshot = true
		return
	end

	if PLY:LookupBone("ValveBiped.Bip01_Head1") then
		PLY.arNeckshot = (PLY.arHit == 1 and dmgpos.z < PLY:GetBonePosition(PLY:LookupBone("ValveBiped.Bip01_Head1")).z)
		if PLY.arNeckshot then return end
	end

	if (dmg:IsDamageType(DMG_BUCKSHOT) or dmg:GetAmmoType() == 7) then
		PLY.arShotshot = true
		return
	end

	if PLY:LookupBone("ValveBiped.Bip01_Pelvis") then
		PLY.arPelvshot = dmgpos.z < (PLY:GetBonePosition(PLY:LookupBone("ValveBiped.Bip01_Pelvis")).z + 2)
	end
end)

--[====[ 钩子：撤销时清理动画 ]====]
hook.Add("PostUndo", "Animrag_Undo", function(undo)
	for _, ent in pairs(undo.Entities) do
		if ent:IsRagdoll() then
			if ent:GetNW2Int("Animation_State") == 1 then
				if ent:GetClass() == "prop_dynamic" then
					for k, ARag in pairs(Anim_Rag_Tb_Death) do
						if ARag == ent then
							for k2, v in pairs(Orgn_Rag_Tb_Death) do
								if v == ARag.ORag then
									table.remove(Orgn_Rag_Tb_Death, k2)
								end
							end
							table.remove(Anim_Rag_Tb_Death, k)
						end
					end
				end
				for k, ORag in pairs(Orgn_Rag_Tb_Death) do
					if ORag == ent then
						Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Death, Anim_Rag_Tb_Death, "Death")
					end
				end
			elseif ent:GetNW2Int("Animation_State") >= 2 then
				if ent:GetClass() == "prop_dynamic" then
					for k, ARag in pairs(Anim_Rag_Tb_Crawl) do
						if ARag == ent then
							for k2, v in pairs(Orgn_Rag_Tb_Crawl) do
								if v == ARag.ORag then
									table.remove(Orgn_Rag_Tb_Crawl, k2)
								end
							end
							table.remove(Anim_Rag_Tb_Crawl, k)
						end
					end
				end
				for k, ORag in pairs(Orgn_Rag_Tb_Crawl) do
					if ORag == ent then
						Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Crawl, Anim_Rag_Tb_Crawl, "Crawl")
					end
				end
			end

			for k, ORag in pairs(All_Rag_Tb) do
				if ORag == ent then
					table.remove(All_Rag_Tb, k)
				end
			end
		end
	end
end)

--[====[ 钩子：地图清理重置状态 ]====]
hook.Add("PostCleanupMap" , "Animrag_ResetAll" , function()
	Orgn_Rag_Tb_Death = {}
	Anim_Rag_Tb_Death = {}
	Orgn_Rag_Tb_Crawl = {}
	Anim_Rag_Tb_Crawl = {}
	All_Rag_Tb = {}
	All_AllyNPC_Tb = {}
end)