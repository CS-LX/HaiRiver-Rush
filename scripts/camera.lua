-- ============================================================
--  camera.lua  —  第三人称追尾摄像机（单一 camYaw 驱动，全程丝滑）
--
--  设计原则：
--    · camYaw 是唯一的方向数据源，位置和 LookAt 全部基于它
--    · camYaw 用指数衰减追逐 S.boatHeading（帧率无关）
--    · 低速（撞墙后）：追逐慢，防止 180° 翻转
--    · 高速（正常）：追逐快，视角跟手
--    · 位置用高速指数平滑吸收物理抖动，不引入额外延迟感
-- ============================================================
local C = require "config"
local S = require "state"
local U = require "utils"

local M = {}

-- 摄像机独立偏航角（度）
local camYaw = 0.0

-- 将角度差规范化到 [-180, 180]，保证走最短路径
local function NormAngle(a)
    a = a % 360
    if a > 180 then a = a - 360 end
    return a
end

-- 速度因子：0（SPEED_MIN）→ 1（SPEED_MAX）
local function SpeedFactor()
    return math.max(0.0, math.min(1.0,
        (S.speed - C.SPEED_MIN) / (C.SPEED_MAX - C.SPEED_MIN)))
end

-- 每帧用指数衰减平滑追逐目标偏航（帧率无关）
local function UpdateCamYaw(dt)
    local diff = NormAngle(S.boatHeading - camYaw)
    if math.abs(diff) < 0.001 then return end

    local sf = SpeedFactor()

    -- 衰减速率：低速 1.5 → 高速 7.0（影响"粘性"）
    local rate = 1.5 + sf * 5.5
    -- 角速度上限：低速 60°/s → 高速 220°/s（防止大角度时飞速旋转）
    local maxStep = (60.0 + sf * 160.0) * dt

    local step = diff * (1.0 - math.exp(-rate * dt))
    step = math.max(-maxStep, math.min(maxStep, step))
    camYaw = camYaw + step
end

function M.Init()
    S.cameraNode = S.mainScene:CreateChild("Camera")
    local cam    = S.cameraNode:CreateComponent("Camera")
    cam:SetFarClip(1200.0)
    cam:SetFov(70.0)
    renderer:SetViewport(0, Viewport:new(S.mainScene, cam))

    -- 启动时对齐船头，避免补偿抖动
    camYaw = S.boatHeading

    local bp  = S.boatNode:GetWorldPosition()
    local rad = math.rad(camYaw)
    S.cameraNode:SetWorldPosition(Vector3(
        bp.x - math.sin(rad) * C.CAM_BACK,
        bp.y + C.CAM_UP,
        bp.z - math.cos(rad) * C.CAM_BACK
    ))
    S.cameraNode:LookAt(bp + Vector3(0, 1.0, 0))
    U.LogInfo("[Camera] 摄像机初始化完毕")
end

function M.Update(dt)
    UpdateCamYaw(dt)

    local bp  = S.boatNode:GetWorldPosition()
    local rad = math.rad(camYaw)  -- ← 唯一来源

    -- 理想位置：船身后方 camYaw 方向
    local idealX = bp.x - math.sin(rad) * C.CAM_BACK
    local idealY = bp.y + C.CAM_UP
    local idealZ = bp.z - math.cos(rad) * C.CAM_BACK

    -- 用指数平滑吸收物理引擎位置抖动（rate=10，快速跟随，不引入延迟感）
    local cur   = S.cameraNode:GetWorldPosition()
    local alpha = 1.0 - math.exp(-10.0 * dt)
    S.cameraNode:SetWorldPosition(Vector3(
        cur.x + (idealX - cur.x) * alpha,
        cur.y + (idealY - cur.y) * alpha,
        cur.z + (idealZ - cur.z) * alpha
    ))

    -- LookAt 也用 camYaw（与位置一致，消除方向冲突）
    local lookX = bp.x + math.sin(rad) * 5.0
    local lookY = bp.y + 1.0
    local lookZ = bp.z + math.cos(rad) * 5.0
    S.cameraNode:LookAt(Vector3(lookX, lookY, lookZ))
end

-- 重开时对齐，避免补偿动画
function M.Reset()
    camYaw = S.boatHeading
    -- 同时重置相机物理位置，防止残留旧位置
    local bp  = S.boatNode:GetWorldPosition()
    local rad = math.rad(camYaw)
    if S.cameraNode then
        S.cameraNode:SetWorldPosition(Vector3(
            bp.x - math.sin(rad) * C.CAM_BACK,
            bp.y + C.CAM_UP,
            bp.z - math.cos(rad) * C.CAM_BACK
        ))
    end
end

return M
