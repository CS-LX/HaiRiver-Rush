-- ============================================================
--  water.lua  —  水面渲染
--  使用引擎内置 SingleLayerWater.xml 材质（含内置波纹动画着色器）
--  大型静态 Plane 覆盖整条赛道，无需逐帧重建网格
-- ============================================================
local S = require "state"

local M = {}

---@type Node
local waterNode = nil

function M.Init()
    waterNode = S.mainScene:CreateChild("Water")
    waterNode:SetPosition(Vector3(0, 0, 0))

    local mdl = waterNode:CreateComponent("StaticModel")
    mdl:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    -- 引擎内置水面材质（含波纹动画，无需自定义着色器）
    local mat = cache:GetResource("Material", "Materials/SingleLayerWater.xml")
    mat:SetShaderParameter("WaterTint", Variant(Color(0.08, 0.38, 0.72)))
    mdl:SetMaterial(mat)

    -- 赛道环形周长约 3600m，用 2000×2000 的平面完整覆盖
    -- Plane.mdl 原始尺寸 1×1，scale=2000 → 2000m×2000m
    waterNode:SetScale(Vector3(2000, 1, 2000))
end

-- 水面着色器自带波纹动画，无需每帧 Update
function M.Update(dt) end

function M.Reset() end

return M
