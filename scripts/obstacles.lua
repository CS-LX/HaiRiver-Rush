-- ============================================================
--  obstacles.lua  —  障碍物工厂、对象池、生成与回收
-- ============================================================
local C     = require "config"
local S     = require "state"
local U     = require "utils"
local Track = require "track"

local M = {}

-- 只保留浮标和游船（去掉桥，因为没有跳跃/俯冲机制）
local OBS_TYPES = { "buoy", "gameboat" }

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
--  生成一个随机障碍物，沿赛道中心线放置
-- ─────────────────────────────────────────────────────────────
local function Spawn(boatZ)
    local spawnNode = Track.GetNodeAhead(boatZ, C.SPAWN_DIST)
    if not spawnNode then return end

    local t    = OBS_TYPES[math.random(1, #OBS_TYPES)]
    local node = GetNode(t)

    local rad    = math.rad(spawnNode.heading)
    -- 赛道右方向
    local rightX = math.cos(rad)
    local rightZ = -math.sin(rad)
    -- 随机横向偏移（3条虚拟通道）
    local offsets = { -C.TRACK_WIDTH / 3.2, 0.0, C.TRACK_WIDTH / 3.2 }
    local laneOff = offsets[math.random(1, 3)]

    node:SetPosition(Vector3(
        spawnNode.x + rightX * laneOff,
        0,
        spawnNode.z + rightZ * laneOff
    ))
    -- 障碍物朝向跟随赛道
    node:SetRotation(Quaternion(0, spawnNode.heading, 0))

    table.insert(S.activeObstacles, node)
    U.LogInfo("[Obs] 生成 " .. t ..
        "  pos=(" .. string.format("%.1f", spawnNode.x + rightX * laneOff) ..
        ", " .. string.format("%.1f", spawnNode.z + rightZ * laneOff) .. ")")
end

-- ─────────────────────────────────────────────────────────────
--  每帧更新
-- ─────────────────────────────────────────────────────────────
function M.Update(dt)
    -- 动态生成间隔
    S.obstInterval = math.max(0.9, 2.0 - (S.speed - 16.0) * 0.022)

    S.obstTimer = S.obstTimer + dt
    if S.obstTimer >= S.obstInterval then
        S.obstTimer = 0.0
        Spawn(S.boatPosZ)
    end

    -- 回收已经落后的障碍物
    -- 使用前向方向点积判断是否落后（支持弯道）
    local rad  = math.rad(S.boatHeading)
    local fwdX = math.sin(rad)
    local fwdZ = math.cos(rad)

    for i = #S.activeObstacles, 1, -1 do
        local obs = S.activeObstacles[i]
        if obs:IsEnabled() then
            local p  = obs:GetPosition()
            local dx = p.x - S.boatPosX
            local dz = p.z - S.boatPosZ
            -- 点积为负且距离足够大则说明落后
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
    S.obstTimer    = 0.0
    S.obstInterval = 2.0
end

return M
