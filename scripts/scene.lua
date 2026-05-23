-- ============================================================
--  scene.lua  —  场景基础初始化（Octree、Zone、灯光）
-- ============================================================
local S = require "state"
local U = require "utils"

local M = {}

function M.Init()
    S.mainScene = Scene()
    S.mainScene:CreateComponent("Octree")
    S.mainScene:CreateComponent("PhysicsWorld")

    -- 环境区域（雾、环境光）
    local zone = S.mainScene:CreateComponent("Zone")
    zone:SetBoundingBox(BoundingBox(-2000, 2000))
    zone:SetAmbientColor(Color(0.35, 0.50, 0.65))
    zone:SetFogColor(Color(0.55, 0.75, 0.92))
    zone:SetFogStart(70.0)
    zone:SetFogEnd(130.0)

    -- 主方向光（太阳）
    local sunNode = S.mainScene:CreateChild("Sun")
    local sun = sunNode:CreateComponent("Light")
    sun:SetLightType(LIGHT_DIRECTIONAL)
    sun:SetColor(Color(1.0, 0.93, 0.82))
    sun:SetBrightness(1.1)
    sun:SetCastShadows(true)
    sunNode:SetDirection(Vector3(0.5, -1.0, 0.7))

    -- 补光
    local fillNode = S.mainScene:CreateChild("FillLight")
    local fill = fillNode:CreateComponent("Light")
    fill:SetLightType(LIGHT_DIRECTIONAL)
    fill:SetColor(Color(0.4, 0.55, 0.85))
    fill:SetBrightness(0.45)
    fillNode:SetDirection(Vector3(-0.6, -0.4, -0.3))

    U.LogInfo("[Scene] 初始化完毕")
end

return M
