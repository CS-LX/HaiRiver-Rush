-- ============================================================
--  boat.lua  —  快艇构建、转向、物理驱动移动
--  碰墙反弹由 boatphys.lua 通过 NodeCollision 事件处理
-- ============================================================
local C = require "config"
local S = require "state"
local U = require "utils"

local M = {}

-- ─────────────────────────────────────────────────────────────
--  构建快艇场景节点
-- ─────────────────────────────────────────────────────────────
function M.Init()
    S.boatNode = S.mainScene:CreateChild("Boat")
    S.boatNode:SetPosition(Vector3(0, C.BOAT_BASE_Y, 0))
    S.boatPosX    = 0.0
    S.boatPosZ    = 0.0
    S.boatHeading = 0.0

    S.boatVisNode = S.boatNode:CreateChild("BoatVis")

    -- 船体（红色）
    local body    = S.boatVisNode:CreateChild("Body")
    local bMdl    = body:CreateComponent("StaticModel")
    bMdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    bMdl:SetMaterial(U.MakeMaterial(0.88, 0.22, 0.1))
    body:SetScale(Vector3(1.9, 0.52, 3.6))

    -- 船头
    local bow     = S.boatVisNode:CreateChild("Bow")
    local bowMdl  = bow:CreateComponent("StaticModel")
    bowMdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    bowMdl:SetMaterial(U.MakeMaterial(0.92, 0.28, 0.12))
    bow:SetScale(Vector3(1.3, 0.46, 1.1))
    bow:SetPosition(Vector3(0, 0.02, 2.3))

    -- 驾驶舱
    local cabin    = S.boatVisNode:CreateChild("Cabin")
    local cabinMdl = cabin:CreateComponent("StaticModel")
    cabinMdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    cabinMdl:SetMaterial(U.MakeMaterial(0.25, 0.65, 0.90))
    cabin:SetScale(Vector3(1.35, 0.58, 1.05))
    cabin:SetPosition(Vector3(0, 0.52, 0.35))

    -- 发动机
    local eng     = S.boatVisNode:CreateChild("Engine")
    local engMdl  = eng:CreateComponent("StaticModel")
    engMdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    engMdl:SetMaterial(U.MakeMaterial(0.18, 0.18, 0.18))
    eng:SetScale(Vector3(0.65, 0.75, 0.55))
    eng:SetPosition(Vector3(0, 0.12, -2.0))

    -- ── 动态刚体（物理驱动，碰撞层 = 1，掩码 = 4 堤岸） ─────
    local rb = S.boatNode:CreateComponent("RigidBody")
    rb:SetMass(80.0)
    -- 锁定 Y 轴移动和所有旋转（船不受物理旋转，由代码控制朝向）
    rb:SetLinearFactor(Vector3(1, 0, 1))
    rb:SetAngularFactor(Vector3(0, 0, 0))
    rb:SetLinearDamping(0.05)
    rb:SetRestitution(0.2)    -- 碰墙后轻微弹性（主要靠 boatphys 处理）
    rb:SetFriction(0.1)
    rb:SetCollisionLayerAndMask(1, 4)  -- 只与堤岸（层4）发生物理碰撞

    -- 碰撞体（盒型，与视觉模型匹配）
    local col = S.boatNode:CreateComponent("CollisionShape")
    col:SetBox(Vector3(1.9, 1.1, 3.6), Vector3(0, 0.25, 0), Quaternion.IDENTITY)

    U.LogInfo("[Boat] 快艇创建完毕（动态刚体）")
end

-- 将角度差规范化到 [-180, 180]（最短路径）
local function NormAngle(a)
    a = a % 360
    if a > 180 then a = a - 360 end
    return a
end

-- ─────────────────────────────────────────────────────────────
--  转向操作（每帧按住时持续调用）
-- ─────────────────────────────────────────────────────────────
function M.Steer(dir, dt)
    -- dir: -1 左转，+1 右转
    -- 同步更新 heading 和目标 heading，保持一致
    S.boatHeading       = S.boatHeading + dir * C.STEER_SPEED * dt
    S.boatTargetHeading = S.boatHeading   -- 手动转向时目标 = 当前
    local tiltTarget = -dir * 20.0
    S.boatTiltZ = U.Lerp(S.boatTiltZ, tiltTarget, dt * 8.0)
end

-- 无转向时回正
function M.ReturnCenter(dt)
    S.boatTiltZ = U.Lerp(S.boatTiltZ, 0.0, dt * 6.0)
end

-- ─────────────────────────────────────────────────────────────
--  每帧更新：通过刚体速度驱动，物理引擎负责碰撞推阻
-- ─────────────────────────────────────────────────────────────
function M.Update(dt)
    -- ── 平滑追逐目标朝向（碰墙转向动画） ───────────────────
    local diff = NormAngle(S.boatTargetHeading - S.boatHeading)
    if math.abs(diff) > 0.01 then
        local maxStep = C.HIT_TURN_SPEED * dt
        local step    = math.max(-maxStep, math.min(maxStep, diff))
        S.boatHeading = S.boatHeading + step
    end

    -- ── 物理速度驱动 ─────────────────────────────────────────
    local rad = math.rad(S.boatHeading)
    local rb  = S.boatNode:GetComponent("RigidBody")
    if rb then
        rb:SetLinearVelocity(Vector3(
            math.sin(rad) * S.speed,
            0,
            math.cos(rad) * S.speed
        ))
    end

    -- 读回物理位置
    local pos  = S.boatNode:GetWorldPosition()
    S.boatPosX = pos.x
    S.boatPosZ = pos.z

    -- 旋转由代码控制（不受物理旋转影响）
    S.boatNode:SetWorldRotation(Quaternion(0, S.boatHeading, 0))
    S.boatVisNode:SetRotation(Quaternion(0, 0, S.boatTiltZ))
end

-- ─────────────────────────────────────────────────────────────
--  重置（重新开始游戏）
-- ─────────────────────────────────────────────────────────────
function M.Reset()
    local rb = S.boatNode:GetComponent("RigidBody")
    if rb then
        rb:SetLinearVelocity(Vector3.ZERO)
        rb:SetAngularVelocity(Vector3.ZERO)
    end
    S.boatPosX          = 0.0
    S.boatPosY          = C.BOAT_BASE_Y
    S.boatPosZ          = 0.0
    S.boatHeading       = 0.0
    S.boatTargetHeading = 0.0
    S.boatTiltZ         = 0.0
    S.boatNode:SetWorldPosition(Vector3(0, C.BOAT_BASE_Y, 0))
    S.boatNode:SetWorldRotation(Quaternion.IDENTITY)
    S.boatVisNode:SetRotation(Quaternion.IDENTITY)
end

return M
