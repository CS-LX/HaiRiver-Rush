-- ============================================================
--  utils.lua  —  数学工具、日志、材质创建、类型辅助
-- ============================================================
local M = {}

function M.Lerp(a, b, t)
    t = t < 0 and 0 or (t > 1 and 1 or t)
    return a + (b - a) * t
end

function M.EaseInOut(t)
    t = t < 0 and 0 or (t > 1 and 1 or t)
    return t * t * (3.0 - 2.0 * t)
end

function M.LogInfo(msg)
    log:Write(LOG_INFO, msg)
end

-- 创建带漫反射颜色的 PBR 材质（不透明）
function M.MakeMaterial(r, g, b, metallic, roughness)
    metallic  = metallic  or 0.0
    roughness = roughness or 0.6
    local mat = Material.new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor",    Variant(Color(r, g, b, 1.0)))
    mat:SetShaderParameter("Metallic",        Variant(metallic))
    mat:SetShaderParameter("Roughness",       Variant(roughness))
    return mat
end

-- 创建透明 PBR 材质（玻璃/水晶等）
function M.MakeMaterialAlpha(r, g, b, a, roughness)
    a         = a         or 0.4
    roughness = roughness or 0.05
    local mat = Material.new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, a)))
    mat:SetShaderParameter("Metallic",     Variant(0.0))
    mat:SetShaderParameter("Roughness",    Variant(roughness))
    return mat
end

-- 从障碍物节点名中提取类型，如 "Obs_buoy" → "buoy"
function M.GetObsType(node)
    return string.sub(node:GetName(), 5)
end

return M
