-- ============================================================
--  boatphys.lua  —  快艇碰墙响应
--
--  设计：
--    · 碰墙后不直接改 S.boatHeading（避免瞬间转圈）
--    · 只写 S.boatTargetHeading，boat.lua 按角速度平滑转过去
--    · 速度固定扣减（而非乘比例），确保总是真正减速
-- ============================================================
local C = require "config"
local S = require "state"
local U = require "utils"

local M = {}

local lastHitTime = -1.0
local HIT_CD      = 0.30   -- 同一次碰撞多帧触发的冷却（秒）

-- 将角度差规范化到 [-180, 180]
local function NormAngle(a)
    a = a % 360
    if a > 180 then a = a - 360 end
    return a
end

-- ─────────────────────────────────────────────────────────────
--  碰撞回调（全局函数）
-- ─────────────────────────────────────────────────────────────
function BoatPhys_OnNodeCollision(eventType, eventData)
    local now = time and time:GetElapsedTime() or 0
    if (now - lastHitTime) < HIT_CD then return end

    local otherBody = eventData["OtherBody"]:GetPtr("RigidBody")
    if not otherBody then return end
    local otherNode = otherBody.node
    if not otherNode then return end

    local name = otherNode:GetName()
    if name ~= "LW" and name ~= "RW" then return end

    -- ── 取得墙壁朝内法线 ─────────────────────────────────────
    local tileNode = otherNode:GetParent()
    local tileHeading = tileNode and tileNode:GetWorldRotation():YawAngle()
                        or S.trackEndHeading
    local tileRad = math.rad(tileHeading)

    -- 赛道右方向 = (cos(rad), 0, -sin(rad))
    -- LW 朝内法线 = +右；RW 朝内法线 = -右
    local side = (name == "LW") and 1.0 or -1.0
    local nx   =  math.cos(tileRad) * side
    local nz   = -math.sin(tileRad) * side

    -- ── 用当前 boatHeading 计算反射 ──────────────────────────
    local rad = math.rad(S.boatHeading)
    local fx  = math.sin(rad)
    local fz  = math.cos(rad)

    local dot = fx * nx + fz * nz
    if dot >= 0 then return end          -- 已经在远离墙，跳过

    -- 反射公式：f' = f - 2*(f·n)*n
    local rfx = fx - 2 * dot * nx
    local rfz = fz - 2 * dot * nz

    -- ── 写入目标朝向（boat.lua 平滑追逐，不直接跳变） ────────
    S.boatTargetHeading = math.deg(math.atan(rfx, rfz))

    -- ── 固定速度扣减（而非乘比例，保证真正减速） ─────────────
    -- 减去一个固定值，但不低于 SPEED_MIN
    S.speed = math.max(C.SPEED_MIN, S.speed - C.HIT_SPEED_LOSS)

    -- 油门同步回退（防止松手后速度立即爬回来）
    local newThrottle = (S.speed - C.SPEED_MIN) / (C.SPEED_MAX - C.SPEED_MIN)
    S.throttle = math.max(0.0, math.min(1.0, newThrottle))

    lastHitTime = now

    -- ── 扣耐久度 ──────────────────────────────────────────────
    if TakeDurabilityHit then
        TakeDurabilityHit("wall")
    end

    U.LogInfo(string.format(
        "[BoatPhys] 碰%s → 目标朝向=%.1f° 速度=%.1f→%.1f",
        name,
        S.boatTargetHeading,
        S.speed + C.HIT_SPEED_LOSS,   -- log 显示碰前速度
        S.speed
    ))
end

function M.Init()
    if not S.boatNode then
        U.LogInfo("[BoatPhys] 错误：S.boatNode 为 nil，跳过初始化")
        return
    end
    -- 初始化时目标朝向与当前保持一致
    S.boatTargetHeading = S.boatHeading
    SubscribeToEvent(S.boatNode, "NodeCollision", "BoatPhys_OnNodeCollision")
    U.LogInfo("[BoatPhys] 碰撞监听已注册")
end

function M.Reset()
    lastHitTime         = -1.0
    S.boatTargetHeading = S.boatHeading
end

return M
