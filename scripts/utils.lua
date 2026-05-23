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

-- 创建带漫反射颜色的基础材质
function M.MakeMaterial(r, g, b, a)
    a = a or 1.0
    local mat = Material.new()
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, a)))
    mat:SetShaderParameter("MatSpecColor",  Variant(Color(0.3, 0.3, 0.3, 1.0)))
    mat:SetShaderParameter("MatSpecPower",  Variant(16.0))
    return mat
end

-- 从障碍物节点名中提取类型，如 "Obs_buoy" → "buoy"
function M.GetObsType(node)
    return string.sub(node:GetName(), 5)
end

return M
