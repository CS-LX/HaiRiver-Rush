-- ============================================================
--  scene.lua  —  场景基础初始化（Octree、灯光、天空、雾效）
-- ============================================================
local S        = require "state"
local U        = require "utils"
local SkyUtils = require "urhox-libs.Rendering.SkyUtils"

local M = {}

function M.Init()
    S.mainScene = Scene()
    S.mainScene:CreateComponent("Octree")
    S.mainScene:CreateComponent("PhysicsWorld")

    -- ── 1. LightGroup（白天预设：含太阳方向光、IBL、预烘焙SH）────────
    local lgFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    local lgNode = S.mainScene:CreateChild("LightGroup")
    lgNode:LoadXML(lgFile:GetRoot())

    -- ── 2. 微调方向光（增强一点阳光亮度）──────────────────────────────
    local sun = lgNode:GetComponent("Light", true)
    if sun then
        sun:SetBrightness(3.5)
        sun:SetCastShadows(true)
    end

    -- ── 3. 从 LightGroup 获取 Zone，把雾推远──────────────────────────
    --   河道赛车需要较远视距，fogStart/fogEnd 拉到数百米
    --   fogColor 和天空地平线色保持一致，避免远处色差线
    local zone = lgNode:GetComponent("Zone", true)
    if zone then
        zone.fogColor = Color(0.62, 0.88, 1.00)   -- 与天空地平线 horizon 色对齐（明亮天蓝）
        zone.fogStart = 300.0                      -- 300m 开始淡入雾
        zone.fogEnd   = 600.0                      -- 600m 完全融入背景
        zone.fogDensity = 0.85                     -- 稍减深度雾浓度，让远景更通透
        -- Zone bbox 覆盖相机可能到达的所有位置
        zone:SetBoundingBox(BoundingBox(Vector3(-3000, -500, -3000), Vector3(3000, 500, 3000)))
    end

    -- ── 4. 程序化渐变天空──────────────────────────────────────────────
    --   zenith  = 深蓝天顶
    --   horizon = 淡蓝地平线（≈ fogColor，无缝衔接）
    --   ground  = 深灰地面（相机不会看到地面，但防止 cubemap 翻转时露底）
    SkyUtils.CreateGradientSky(S.mainScene, {
        zenith   = Color(0.05, 0.36, 0.92),   -- 鲜艳饱和蓝天顶
        horizon  = Color(0.62, 0.88, 1.00),   -- 明亮天蓝地平线（与 fogColor 一致）
        ground   = Color(0.50, 0.78, 0.92),   -- 浅蓝地面（无灰色调）
        skyExp   = 0.42,                       -- 渐变偏向地平线，更自然
        hdrBoost = 2.4,                        -- 补偿 ACES，让天空更亮更通透
    })

    U.LogInfo("[Scene] 初始化完毕（LightGroup/Daytime + 渐变天空，视距 300-600m，farClip 1200m）")
end

return M
