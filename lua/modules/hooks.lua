local function recordDamageInfo(actor, hitgroup, dmginfo)
    if not IsValid(actor) then return end -- we should trust the game engine that the actor passed in must be npc or player
end

hook.Add("ScaleNPCDamage", "EDAE_ScaleNPCDamage", function(npc, hitgroup, dmginfo)
    recordDamageInfo(npc, hitgroup, dmginfo)
end)

hook.Add("ScalePlayerDamage", "EDAE_ScalePlayerDamage", function(ply, hitgroup, dmginfo)
    recordDamageInfo(ply, hitgroup, dmginfo)
end)

hook.Add("PlayerDeath", "EDAE_PlayerDeath", function(ply)
    print("player health at PlayerDeath: " .. tostring(ply:Health()))
    ply:SetHealth(50)
    print("player health at PlayerDeath after set: " .. tostring(ply:Health()))
    ply:SetShouldServerRagdoll(true)
end)
hook.Add("PostPlayerDeath", "EDAE_PostPlayerDeath", function(ply)
    print("player health at PostPlayerDeath: " .. tostring(ply:Health()))
    ply:SetHealth(100)
    print("player health at PostPlayerDeath after set: " .. tostring(ply:Health()))
    local rag = ply:GetRagdollEntity()
    if rag and IsValid(rag) then
        rag:Remove()
    end
end)

hook.Add("EntityTakeDamage", "TEST_EntityTakeDamage", function(target, dmg)
    -- if not IsValid(target) then return end
    local localPlayer = Entity(1)
    if target == localPlayer then
        return
    end
    hook.Run("ScalePlayerDamage", localPlayer, HITGROUP_HEAD, dmg)
end)

hook.Add("PostEntityTakeDamage", "TEST_PostEntityTakeDamage", function(ent, dmginfo, wasDamageTaken)
    local localPlayer = Entity(1)
    if ent == localPlayer then
        return
    end
    hook.Run("PostEntityTakeDamage", localPlayer, dmginfo, wasDamageTaken)
end)

hook.Add("CreateEntityRagdoll", "EDAE_CreateEntityRagdoll", function(owner, ragdoll)

end)
