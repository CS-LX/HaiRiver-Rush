-- ============================================================
--  water.lua  —  水面渲染
--  使用引擎内置 SingleLayerWater.xml 材质（含内置波纹动画着色器）
--  根据赛道 AABB 动态确定水面中心和尺寸，完整覆盖整条赛道
-- ============================================================
local S     = require "state"
local Track = require "track"

local M = {}

---@type Node
local waterNode = nil

function M.Init()
    -- 赛道 AABB + 200m 边距，确保水面延伸到两岸护堤之外
    local bounds = Track.GetBounds(200)
    local cx     = bounds.centerX
    local cz     = bounds.centerZ
    local sx     = bounds.sizeX
    local sz     = bounds.sizeZ

    local U = require "utils"
    U.LogInfo(string.format("[Water] bounds: X[%.0f,%.0f] Z[%.0f,%.0f] → center(%.0f,%.0f) size(%.0f×%.0f)",
        bounds.minX, bounds.maxX, bounds.minZ, bounds.maxZ, cx, cz, sx, sz))

    waterNode = S.mainScene:CreateChild("Water")
    -- 水面 Y=0，低于赛道面（track tile Y=-0.05）一点，避免 Z-fighting
    waterNode:SetPosition(Vector3(cx, -0.02, cz))

    local mdl = waterNode:CreateComponent("StaticModel")
    mdl:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    -- 引擎内置水面材质（含波纹动画，无需自定义着色器）
    local mat = cache:GetResource("Material", "Materials/SingleLayerWater.xml")
    mat:SetShaderParameter("WaterTint", Variant(Color(0.08, 0.38, 0.72)))
    mdl:SetMaterial(mat)

    -- Plane.mdl 原始边长 = 1，scale 对应实际米数
    waterNode:SetScale(Vector3(sx, 1, sz))
end

-- 水面着色器自带波纹动画，无需每帧 Update
function M.Update(dt) end

function M.Reset() end

return M
