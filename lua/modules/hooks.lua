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
    ply:SetShouldServerRagdoll(true)
end)
hook.Add("PostPlayerDeath", "EDAE_PostPlayerDeath", function(ply)
    local rag = ply:GetRagdollEntity()
    if rag and IsValid(rag) then
        rag:Remove()
    end
end)
