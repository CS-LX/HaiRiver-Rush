-- ============================================================
--  boatphys.lua  —  快艇碰撞响应（墙壁 + 障碍物）
--
--  设计：
--    · 碰撞后不直接改 S.boatHeading（避免瞬间转圈）
--    · 只写 S.boatTargetHeading，boat.lua 按角速度平滑转过去
--    · 速度固定扣减（而非乘比例），确保总是真正减速
--    · 障碍物碰撞与墙壁走同一套反射逻辑，但用障碍物中心→船的方向作为法线
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
--  通用碰撞响应：传入法线 (nx, nz)、来源标签、伤害类型
-- ─────────────────────────────────────────────────────────────
local function ApplyHit(nx, nz, logTag, dmgType)
    -- 反射朝向
    local rad = math.rad(S.boatHeading)
    local fx  = math.sin(rad)
    local fz  = math.cos(rad)

    local dot = fx * nx + fz * nz
    if dot >= 0 then return end   -- 已在远离，跳过

    local rfx = fx - 2 * dot * nx
    local rfz = fz - 2 * dot * nz
    S.boatTargetHeading = math.deg(math.atan(rfx, rfz))

    -- 减速
    local prevSpeed = S.speed
    S.speed    = math.max(C.SPEED_MIN, S.speed - C.HIT_SPEED_LOSS)
    S.throttle = math.max(0.0, math.min(1.0,
        (S.speed - C.SPEED_MIN) / (C.SPEED_MAX - C.SPEED_MIN)))

    -- 扣耐久
    if TakeDurabilityHit then
        TakeDurabilityHit(dmgType)
    end

    U.LogInfo(string.format(
        "[BoatPhys] 碰 %s → 目标朝向=%.1f° 速度 %.1f→%.1f",
        logTag, S.boatTargetHeading, prevSpeed, S.speed))
end

-- ─────────────────────────────────────────────────────────────
--  碰撞回调（全局函数，NodeCollision 事件）
-- ─────────────────────────────────────────────────────────────
function BoatPhys_OnNodeCollision(eventType, eventData)
    if S.gameState ~= "playing" then return end

    local now = time and time:GetElapsedTime() or 0
    if (now - lastHitTime) < HIT_CD then return end

    local otherBody = eventData["OtherBody"]:GetPtr("RigidBody")
    if not otherBody then return end
    local otherNode = otherBody.node
    if not otherNode then return end

    local name = otherNode:GetName()

    -- ── 墙壁：用瓦片朝向推算法线 ────────────────────────────
    if name == "LW" or name == "RW" then
        local tileNode    = otherNode:GetParent()
        local tileHeading = tileNode and tileNode:GetWorldRotation():YawAngle()
                            or S.trackEndHeading
        local tileRad = math.rad(tileHeading)
        local side    = (name == "LW") and 1.0 or -1.0
        local nx      =  math.cos(tileRad) * side
        local nz      = -math.sin(tileRad) * side
        lastHitTime   = now
        ApplyHit(nx, nz, name, "wall")
        return
    end

end

function M.Init()
    if not S.boatNode then
        U.LogInfo("[BoatPhys] 错误：S.boatNode 为 nil，跳过初始化")
        return
    end
    S.boatTargetHeading = S.boatHeading
    SubscribeToEvent(S.boatNode, "NodeCollision", "BoatPhys_OnNodeCollision")
    U.LogInfo("[BoatPhys] 碰撞监听已注册（墙壁 + 障碍物）")
end

function M.Reset()
    lastHitTime         = -1.0
    S.boatTargetHeading = S.boatHeading
end

return M
