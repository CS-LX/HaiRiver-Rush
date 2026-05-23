-- ============================================================
--  obstacles.lua  —  障碍物工厂、对象池、生成与回收
--  生成策略：基于赛道索引，每隔固定瓦片数生成一次
--  - 不再使用时间计时器，停留原地不会堆积
--  - 往后倒退不会触发新生成
--  - 回收：障碍物落后船 RECYCLE_DIST 后归池
-- ============================================================
local C     = require "config"
local S     = require "state"
local U     = require "utils"
local Track = require "track"

local M = {}

local OBS_TYPES = { "buoy", "gameboat" }

-- 前方固定瓦片偏移处生成障碍物
local SPAWN_TILES = math.floor(C.SPAWN_DIST / C.TILE_LEN)  -- ~12 个瓦片

-- 上次生成时船在第几号索引（每隔 OBS_STEP 个索引生成一次）
local lastSpawnIdx = 0
-- 每隔多少个赛道索引生成一次障碍物（随速度动态调整）
local OBS_STEP_BASE = 8   -- 正常速度：每 8 个节点一个障碍

-- ─────────────────────────────────────────────────────────────
--  工厂：构建新的障碍物节点
-- ─────────────────────────────────────────────────────────────
local function BuildNode(t)
    local node = S.mainScene:CreateChild("Obs_" .. t)
    node:SetEnabled(false)

    if t == "buoy" then
        local mdl = node:CreateComponent("StaticModel")
        mdl:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
        mdl:SetMaterial(U.MakeMaterial(0.92, 0.12, 0.08))
        node:SetScale(Vector3(0.75, 1.9, 0.75))
        local col = node:CreateComponent("CollisionShape")
        col:SetCylinder(0.75, 1.9, Vector3.ZERO, Quaternion.IDENTITY)

    elseif t == "gameboat" then
        local hull  = node:CreateChild("Hull")
        local hMdl  = hull:CreateComponent("StaticModel")
        hMdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        hMdl:SetMaterial(U.MakeMaterial(0.18, 0.38, 0.68))
        hull:SetScale(Vector3(3.6, 1.3, 7.5))

        local deck  = node:CreateChild("Deck")
        local dMdl  = deck:CreateComponent("StaticModel")
        dMdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        dMdl:SetMaterial(U.MakeMaterial(0.78, 0.76, 0.72))
        deck:SetScale(Vector3(3.2, 0.95, 5.8))
        deck:SetPosition(Vector3(0, 1.1, 0))

        local col = node:CreateComponent("CollisionShape")
        col:SetBox(Vector3(3.6, 2.5, 7.5), Vector3.ZERO, Quaternion.IDENTITY)
    end

    local rb = node:CreateComponent("RigidBody")
    rb:SetMass(0)
    rb:SetKinematic(true)
    rb:SetCollisionLayerAndMask(2, 1)

    return node
end

-- ─────────────────────────────────────────────────────────────
--  对象池
-- ─────────────────────────────────────────────────────────────
local function GetNode(t)
    for i = 1, #S.obstaclePool do
        if U.GetObsType(S.obstaclePool[i]) == t then
            local n = table.remove(S.obstaclePool, i)
            n:SetEnabled(true)
            return n
        end
    end
    return BuildNode(t)
end

local function Recycle(n)
    n:SetEnabled(false)
    table.insert(S.obstaclePool, n)
end

-- ─────────────────────────────────────────────────────────────
--  在指定节点处生成一个随机障碍物
-- ─────────────────────────────────────────────────────────────
local function SpawnAt(spawnNode)
    local t    = OBS_TYPES[math.random(1, #OBS_TYPES)]
    local node = GetNode(t)

    local rad    = math.rad(spawnNode.heading)
    local rightX = math.cos(rad)
    local rightZ = -math.sin(rad)
    local offsets = { -C.TRACK_WIDTH / 3.2, 0.0, C.TRACK_WIDTH / 3.2 }
    local laneOff = offsets[math.random(1, 3)]

    node:SetPosition(Vector3(
        spawnNode.x + rightX * laneOff,
        0,
        spawnNode.z + rightZ * laneOff
    ))
    node:SetRotation(Quaternion(0, spawnNode.heading, 0))

    table.insert(S.activeObstacles, node)
end

-- ─────────────────────────────────────────────────────────────
--  每帧更新
-- ─────────────────────────────────────────────────────────────
function M.Update(dt)
    -- 根据速度动态调整生成间隔（速度越快间距越小）
    -- 速度 16 m/s → step 10；速度 55 m/s → step 5
    local speedRatio = (S.speed - C.SPEED_MIN) / (C.SPEED_MAX - C.SPEED_MIN)
    local obsStep = math.floor(math.max(5, OBS_STEP_BASE + 4 - speedRatio * 4 + 0.5))

    local curIdx = Track.GetCurrentIdx()

    -- 只有向前行驶（当前索引超过上次生成索引 + step）才生成
    -- 使用环形距离判断"向前"
    local loopN  = Track.GetLoopN()
    if loopN == 0 then return end

    local diff = (curIdx - lastSpawnIdx + loopN) % loopN
    if diff >= obsStep then
        -- 在前方固定偏移处生成
        local spawnNode = Track.GetNodeAtOffset(SPAWN_TILES)
        if spawnNode then
            SpawnAt(spawnNode)
        end
        -- 更新生成索引（对齐到当前，避免连续触发）
        lastSpawnIdx = curIdx
    end

    -- 回收落后的障碍物
    local rad  = math.rad(S.boatHeading)
    local fwdX = math.sin(rad)
    local fwdZ = math.cos(rad)

    for i = #S.activeObstacles, 1, -1 do
        local obs = S.activeObstacles[i]
        if obs:IsEnabled() then
            local p   = obs:GetPosition()
            local dx  = p.x - S.boatPosX
            local dz  = p.z - S.boatPosZ
            local dot = dx * fwdX + dz * fwdZ
            if dot < -C.RECYCLE_DIST then
                Recycle(obs)
                table.remove(S.activeObstacles, i)
            end
        end
    end
end

-- 清空全部活跃障碍物（重新开始）
function M.ClearAll()
    for i = #S.activeObstacles, 1, -1 do
        Recycle(S.activeObstacles[i])
        table.remove(S.activeObstacles, i)
    end
    lastSpawnIdx   = 0
    S.obstTimer    = 0.0
    S.obstInterval = 2.0
end

return M
