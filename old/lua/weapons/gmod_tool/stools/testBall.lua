-- TOOL.Category = "Test"
-- TOOL.Name = "Test Ball"

-- function TOOL:LeftClick(tr)
--     local clickPos = tr.HitPos
--     local ent = ents.Create("prop_physics")
--     ent:SetModel("models/props_phx/ball.mdl")
--     ent:SetPos(clickPos)
--     ent:Spawn()

--     local rag = ents.Create("prop_ragdoll")
--     rag:SetModel("models/player/tfa_cso2/ct_choi.mdl")
--     rag:SetPos(clickPos)
--     rag:Spawn()
-- end

-- function TOOL:RightClick(tr)
--     local clickEnt = tr.Entity
--     if IsValid(clickEnt) then
--         print("Class: " .. clickEnt:GetClass())
--         print("Model:" .. clickEnt:GetModel())
--     end
-- end
