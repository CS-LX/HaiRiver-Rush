-- ============================================================
--  coins.lua  —  金币工厂、对象池、生成与采集
-- ============================================================
local C     = require "config"
local S     = require "state"
local U     = require "utils"
local Track = require "track"

local M = {}

-- ─────────────────────────────────────────────────────────────
--  工厂 / 对象池
-- ─────────────────────────────────────────────────────────────
local function BuildCoin()
    local node = S.mainScene:CreateChild("Coin")
    node:SetEnabled(false)
    local mdl = node:CreateComponent("StaticModel")
    mdl:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    mdl:SetMaterial(U.MakeMaterial(1.0, 0.82, 0.0))
    node:SetScale(Vector3(0.52, 0.13, 0.52))
    return node
end

local function GetCoin()
    if #S.coinPool > 0 then
        local n = table.remove(S.coinPool)
        n:SetEnabled(true)
        return n
    end
    return BuildCoin()
end

local function Recycle(n)
    n:SetEnabled(false)
    table.insert(S.coinPool, n)
end

-- ─────────────────────────────────────────────────────────────
--  生成一行金币，沿赛道前进方向排列
-- ─────────────────────────────────────────────────────────────
local function SpawnRow(boatZ)
    local spawnNode = Track.GetNodeAhead(boatZ, C.SPAWN_DIST + 10.0)
    if not spawnNode then return end

    local rad    = math.rad(spawnNode.heading)
    local fwdX   = math.sin(rad)
    local fwdZ   = math.cos(rad)
    local rightX = math.cos(rad)
    local rightZ = -math.sin(rad)

    -- 随机选一条虚拟通道
    local offsets = { -C.TRACK_WIDTH / 3.5, 0.0, C.TRACK_WIDTH / 3.5 }
    local laneOff = offsets[math.random(1, 3)]

    local arc  = math.random() > 0.5  -- 随机拱形排列
    local cy   = C.BOAT_BASE_Y + 1.0

    for i = 1, C.COIN_ROW_LEN do
        local coin = GetCoin()
        local dist = (i - 1) * C.COIN_GAP
        local arcY = 0.0
        if arc then
            arcY = math.sin((i - 1) / (C.COIN_ROW_LEN - 1) * math.pi) * 1.5
        end
        coin:SetPosition(Vector3(
            spawnNode.x + rightX * laneOff + fwdX * dist,
            cy + arcY,
            spawnNode.z + rightZ * laneOff + fwdZ * dist
        ))
        table.insert(S.activeCoins, coin)
    end
end

-- ─────────────────────────────────────────────────────────────
--  每帧更新
-- ─────────────────────────────────────────────────────────────
function M.Update(dt)
    -- 按障碍物间隔的 1.2 倍生成金币行
    S.coinTimer = S.coinTimer + dt
    if S.coinTimer >= S.obstInterval * 1.2 then
        S.coinTimer = 0.0
        SpawnRow(S.boatPosZ)
    end

    local bp = S.boatNode:GetPosition()

    for i = #S.activeCoins, 1, -1 do
        local coin = S.activeCoins[i]
        if coin:IsEnabled() then
            coin:Rotate(Quaternion(0, 110.0 * dt, 0))

            local p  = coin:GetPosition()
            local dx = math.abs(bp.x - p.x)
            local dy = math.abs(bp.y - p.y)
            local dz = math.abs(bp.z - p.z)

            if dx < 1.3 and dy < 1.4 and dz < 2.2 then
                -- 采集
                S.coinCount = S.coinCount + 1
                Recycle(coin)
                table.remove(S.activeCoins, i)
                U.LogInfo("[Coin] 收集! 共 " .. S.coinCount)
            else
                -- 用前向点积判断是否落后
                local rad  = math.rad(S.boatHeading)
                local fwdX = math.sin(rad)
                local fwdZ = math.cos(rad)
                local ddx  = p.x - S.boatPosX
                local ddz  = p.z - S.boatPosZ
                local dot  = ddx * fwdX + ddz * fwdZ
                if dot < -C.RECYCLE_DIST then
                    Recycle(coin)
                    table.remove(S.activeCoins, i)
                end
            end
        end
    end
end

-- 清空全部活跃金币（重新开始）
function M.ClearAll()
    for i = #S.activeCoins, 1, -1 do
        Recycle(S.activeCoins[i])
        table.remove(S.activeCoins, i)
    end
    S.coinTimer = 0.0
end

return M
