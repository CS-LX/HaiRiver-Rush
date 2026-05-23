-- ============================================================
--  gameboat.lua  —  游船障碍物：工厂、对象池、飞行物理、碰撞
--
--  碰撞策略（完全照搬金币的 AABB 距离检测，无物理引擎）：
--    · 每帧比较玩家坐标与游船坐标的轴对齐距离
--    · dx < HW and dz < HL → 判定碰撞
--    · 触碰后：扣玩家耐久 + 游船沿玩家方向撞飞
--    · 玩家不阻挡，直接穿过
-- ============================================================
local C     = require "config"
local S     = require "state"
local U     = require "utils"
local Track = require "track"

local M = {}

-- ── 碰撞范围（AABB，保守估算，与金币同款） ───────────────────
--   游船宽 3.6m → 半宽 1.8m；玩家宽 1.9m → 半宽 0.95m
local HIT_HW = 1.8 + 0.95   -- 水平（左右）触发半宽 = 2.75m
local HIT_HL = 3.75 + 1.8   -- 纵向（前后）触发半长 = 5.55m

-- ── 撞飞参数 ─────────────────────────────────────────────────
local BLAST_SPEED = 30.0    -- 初始水平速度 (m/s)
local BLAST_UP    =  4.0    -- 初始向上速度 (m/s)
local BLAST_DAMP  =  3.5    -- 水平速度指数衰减系数
local BLAST_GRAV  = 14.0    -- 重力加速度 (m/s²)

-- ── 伤害冷却 ─────────────────────────────────────────────────
local HIT_CD      = 0.60
local lastHitTime = -10.0

-- ── 对象池和状态 ─────────────────────────────────────────────
local pool   = {}   -- 闲置节点
local active = {}   -- { node, vx, vz, vy, blasted } 活跃游船列表

-- ─────────────────────────────────────────────────────────────
--  工厂：构建游船视觉节点（无刚体，纯 StaticModel）
-- ─────────────────────────────────────────────────────────────
local function Build()
    local node = S.mainScene:CreateChild("Gameboat")
    node:SetEnabled(false)

    local hull = node:CreateChild("Hull")
    local hMdl = hull:CreateComponent("StaticModel")
    hMdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    hMdl:SetMaterial(U.MakeMaterial(0.18, 0.38, 0.68))
    hull:SetScale(Vector3(3.6, 1.3, 7.5))

    local deck = node:CreateChild("Deck")
    local dMdl = deck:CreateComponent("StaticModel")
    dMdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    dMdl:SetMaterial(U.MakeMaterial(0.78, 0.76, 0.72))
    deck:SetScale(Vector3(3.2, 0.95, 5.8))
    deck:SetPosition(Vector3(0, 1.1, 0))

    return node
end

-- ─────────────────────────────────────────────────────────────
--  对象池：取出 / 回收
-- ─────────────────────────────────────────────────────────────
local function Get()
    local n = #pool > 0 and table.remove(pool) or Build()
    n:SetEnabled(true)
    n:SetWorldRotation(Quaternion.IDENTITY)
    return n
end

local function Recycle(entry)
    entry.node:SetWorldRotation(Quaternion.IDENTITY)
    entry.node:SetEnabled(false)
    table.insert(pool, entry.node)
end

-- ─────────────────────────────────────────────────────────────
--  生成一艘游船（由 obstacles.lua 调用）
-- ─────────────────────────────────────────────────────────────
function M.Spawn(spawnNode, laneOff)
    local node = Get()
    local rad    = math.rad(spawnNode.heading)
    local rightX = math.cos(rad)
    local rightZ = -math.sin(rad)
    node:SetWorldPosition(Vector3(
        spawnNode.x + rightX * laneOff,
        0,
        spawnNode.z + rightZ * laneOff
    ))
    node:SetWorldRotation(Quaternion(0, spawnNode.heading, 0))
    table.insert(active, {
        node    = node,
        vx      = 0, vz = 0, vy = 0,
        blasted = false,
    })
end

-- ─────────────────────────────────────────────────────────────
--  每帧更新：碰撞检测 + 撞飞物理 + 回收
-- ─────────────────────────────────────────────────────────────
function M.Update(dt)
    if #active == 0 then return end

    local bp = S.boatNode:GetWorldPosition()
    local now = time and time:GetElapsedTime() or 0
    local dampFactor = math.exp(-BLAST_DAMP * dt)
    local fwdX = math.sin(math.rad(S.boatHeading))
    local fwdZ = math.cos(math.rad(S.boatHeading))

    for i = #active, 1, -1 do
        local e    = active[i]
        local node = e.node
        if not node:IsEnabled() then
            table.remove(active, i)
        else
            local p  = node:GetWorldPosition()

            -- ── 碰撞检测（AABB，同金币逻辑） ────────────────
            if not e.blasted then
                local dx = math.abs(bp.x - p.x)
                local dz = math.abs(bp.z - p.z)
                if dx < HIT_HW and dz < HIT_HL then
                    -- 扣耐久（有冷却）
                    if (now - lastHitTime) >= HIT_CD then
                        lastHitTime = now
                        if TakeDurabilityHit then TakeDurabilityHit("gameboat") end
                        U.LogInfo("[Gameboat] 碰撞！扣耐久")
                    end
                    -- 撞飞：沿玩家行进方向
                    e.vx      = fwdX * BLAST_SPEED
                    e.vz      = fwdZ * BLAST_SPEED
                    e.vy      = BLAST_UP
                    e.blasted = true
                end
            end

            -- ── 撞飞物理（抛体） ─────────────────────────────
            if e.blasted then
                local nx = p.x + e.vx * dt
                local nz = p.z + e.vz * dt
                e.vy = e.vy - BLAST_GRAV * dt
                local ny = p.y + e.vy * dt
                if ny < 0 then ny = 0; e.vy = 0 end
                e.vx = e.vx * dampFactor
                e.vz = e.vz * dampFactor
                node:SetWorldPosition(Vector3(nx, ny, nz))
                -- 倾翻动画：下落时向前倾
                local tilt = math.max(-75.0, e.vy * -4.0)
                node:SetWorldRotation(Quaternion(tilt, 0, 0))
            end

            -- ── 回收落后的游船 ───────────────────────────────
            local ddx = p.x - S.boatPosX
            local ddz = p.z - S.boatPosZ
            if ddx * fwdX + ddz * fwdZ < -C.RECYCLE_DIST then
                Recycle(e)
                table.remove(active, i)
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
--  清空（重新开始）
-- ─────────────────────────────────────────────────────────────
function M.ClearAll()
    for i = #active, 1, -1 do
        Recycle(active[i])
        table.remove(active, i)
    end
    lastHitTime = -10.0
end

-- 返回活跃游船数量（供调试）
function M.ActiveCount()
    return #active
end

return M
