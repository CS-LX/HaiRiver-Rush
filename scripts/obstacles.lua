-- ============================================================
--  obstacles.lua  —  障碍物调度：生成节奏 + 浮标管理
--
--  游船逻辑已独立至 gameboat.lua。
--  本模块负责：
--    · 按赛道索引触发生成（浮标 or 游船）
--    · 浮标：AABB 碰撞检测，仅扣耐久，玩家穿过
--    · 游船：委托 Gameboat 模块处理
-- ============================================================
local C        = require "config"
local S        = require "state"
local U        = require "utils"
local Track    = require "track"
local Gameboat = require "gameboat"

local M = {}

-- ── 生成参数 ─────────────────────────────────────────────────
local OBS_TYPES     = { "buoy", "gameboat" }
local SPAWN_TILES   = math.floor(C.SPAWN_DIST / C.TILE_LEN)
local OBS_STEP_BASE = 8
local lastSpawnIdx  = 0

-- ── 浮标碰撞范围（AABB，同金币逻辑） ─────────────────────────
--   浮标半径 0.75m；玩家近似半径 1.1m
local BUOY_HW = 0.75 + 1.1   -- 左右 = 1.85m
local BUOY_HL = 0.75 + 1.8   -- 前后 = 2.55m（船较长，纵向放宽）

-- ── 浮标伤害冷却 ─────────────────────────────────────────────
local BUOY_HIT_CD  = 0.50
local buoyLastHit  = -10.0

-- ── 浮标对象池 ───────────────────────────────────────────────
local buoyPool   = {}
local activeBuoys = {}

-- ─────────────────────────────────────────────────────────────
--  浮标工厂
-- ─────────────────────────────────────────────────────────────
local function BuildBuoy()
    local node = S.mainScene:CreateChild("Buoy")
    node:SetEnabled(false)
    local mdl = node:CreateComponent("StaticModel")
    mdl:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    mdl:SetMaterial(U.MakeMaterial(0.92, 0.12, 0.08))
    node:SetScale(Vector3(1.5, 1.9, 1.5))
    return node
end

local function GetBuoy()
    local n = #buoyPool > 0 and table.remove(buoyPool) or BuildBuoy()
    n:SetEnabled(true)
    return n
end

local function RecycleBuoy(n)
    n:SetEnabled(false)
    table.insert(buoyPool, n)
end

-- ─────────────────────────────────────────────────────────────
--  生成一个障碍物（浮标 or 游船）
-- ─────────────────────────────────────────────────────────────
local function SpawnAt(spawnNode)
    local t      = OBS_TYPES[math.random(1, #OBS_TYPES)]
    local rad    = math.rad(spawnNode.heading)
    local rightX = math.cos(rad)
    local rightZ = -math.sin(rad)
    local lanes  = { -C.TRACK_WIDTH / 3.2, 0.0, C.TRACK_WIDTH / 3.2 }
    local laneOff = lanes[math.random(1, 3)]

    if t == "buoy" then
        local node = GetBuoy()
        node:SetWorldPosition(Vector3(
            spawnNode.x + rightX * laneOff,
            0,
            spawnNode.z + rightZ * laneOff
        ))
        node:SetWorldRotation(Quaternion(0, spawnNode.heading, 0))
        table.insert(activeBuoys, node)
    else
        Gameboat.Spawn(spawnNode, laneOff)
    end
end

-- ─────────────────────────────────────────────────────────────
--  每帧更新
-- ─────────────────────────────────────────────────────────────
function M.Update(dt)
    -- ── 生成节奏 ─────────────────────────────────────────────
    local speedRatio = (S.speed - C.SPEED_MIN) / (C.SPEED_MAX - C.SPEED_MIN)
    local obsStep    = math.floor(math.max(5, OBS_STEP_BASE + 4 - speedRatio * 4 + 0.5))
    local curIdx     = Track.GetCurrentIdx()
    local loopN      = Track.GetLoopN()
    if loopN == 0 then return end

    local diff = (curIdx - lastSpawnIdx + loopN) % loopN
    if diff >= obsStep then
        local spawnNode = Track.GetNodeAtOffset(SPAWN_TILES)
        if spawnNode then SpawnAt(spawnNode) end
        lastSpawnIdx = curIdx
    end

    -- ── 游船更新（委托） ─────────────────────────────────────
    Gameboat.Update(dt)

    -- ── 浮标：碰撞检测 + 回收 ────────────────────────────────
    if S.gameState == "playing" then
        local bp  = S.boatNode:GetWorldPosition()
        local now = time and time:GetElapsedTime() or 0
        local fwdX = math.sin(math.rad(S.boatHeading))
        local fwdZ = math.cos(math.rad(S.boatHeading))

        for i = #activeBuoys, 1, -1 do
            local node = activeBuoys[i]
            if node:IsEnabled() then
                local p  = node:GetWorldPosition()
                local dx = math.abs(bp.x - p.x)
                local dz = math.abs(bp.z - p.z)

                -- AABB 碰撞（同金币逻辑）
                if dx < BUOY_HW and dz < BUOY_HL then
                    if (now - buoyLastHit) >= BUOY_HIT_CD then
                        buoyLastHit = now
                        if TakeDurabilityHit then TakeDurabilityHit("buoy") end
                        U.LogInfo("[Obs] 撞浮标！扣耐久")
                    end
                end

                -- 回收落后浮标
                local ddx = p.x - S.boatPosX
                local ddz = p.z - S.boatPosZ
                if ddx * fwdX + ddz * fwdZ < -C.RECYCLE_DIST then
                    RecycleBuoy(node)
                    table.remove(activeBuoys, i)
                end
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
--  清空（重新开始）
-- ─────────────────────────────────────────────────────────────
function M.ClearAll()
    for i = #activeBuoys, 1, -1 do
        RecycleBuoy(activeBuoys[i])
        table.remove(activeBuoys, i)
    end
    Gameboat.ClearAll()
    lastSpawnIdx  = 0
    buoyLastHit   = -10.0
    S.obstTimer   = 0.0
    S.obstInterval = 2.0
end

return M
