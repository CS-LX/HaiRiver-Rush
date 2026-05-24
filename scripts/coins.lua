-- ============================================================
--  coins.lua  —  金币工厂、对象池、生成与采集
--  生成策略：基于赛道索引，每隔固定瓦片数生成一行
--  - 停留原地不会堆积金币
--  - 往后行驶不会触发新生成
--  - 金币高度与船齐平，无需跳跃即可捡到
-- ============================================================
local C     = require "config"
local S     = require "state"
local U     = require "utils"
local Track = require "track"

local M = {}

-- 前方固定瓦片偏移处生成金币（与障碍物错开 4 个节点）
local SPAWN_TILES = math.floor(C.SPAWN_DIST / C.TILE_LEN) + 4

-- 每隔多少个索引生成一行金币（比障碍物稍密）
local COIN_STEP = 6

local lastSpawnIdx = 0

-- 每枚金币的独立旋转角度（度），key = Node 对象
local coinAngle = {}

-- ─────────────────────────────────────────────────────────────
--  工厂 / 对象池
-- ─────────────────────────────────────────────────────────────
local coinMat = nil

local function BuildCoinMat()
    if coinMat then return coinMat end
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor",    Variant(Color(1.0, 0.80, 0.05, 1.0)))
    mat:SetShaderParameter("Metallic",        Variant(0.95))
    mat:SetShaderParameter("Roughness",       Variant(0.12))
    mat:SetShaderParameter("MatEmissiveColor",Variant(Color(0.45, 0.32, 0.0)))  -- 淡金辉，不压金属感
    coinMat = mat
    return mat
end

local function BuildCoin()
    local node = S.mainScene:CreateChild("Coin")
    node:SetEnabled(false)
    local mdl = node:CreateComponent("StaticModel")
    mdl:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    mdl:SetMaterial(BuildCoinMat())
    mdl:SetCastShadows(true)
    -- 金币：直径 1.4m，厚度 0.22m
    node:SetScale(Vector3(1.4, 0.22, 1.4))

    -- 点光源：柔和金色环境光
    local lightNode = node:CreateChild("CoinLight")
    local light = lightNode:CreateComponent("Light")
    light.lightType   = LIGHT_POINT
    light.color       = Color(1.0, 0.85, 0.1)
    light.brightness  = 0.5
    light.range       = 2.8
    light.castShadows = false

    return node
end

local function GetCoin()
    local n
    if #S.coinPool > 0 then
        n = table.remove(S.coinPool)
    else
        n = BuildCoin()
    end
    n:SetEnabled(true)
    return n
end

local function Recycle(n)
    n:SetEnabled(false)
    coinAngle[n] = nil
    table.insert(S.coinPool, n)
end

-- ─────────────────────────────────────────────────────────────
--  生成一行金币，高度与船齐平（无需跳跃）
-- ─────────────────────────────────────────────────────────────
local function SpawnRow(spawnNode)
    local rad    = math.rad(spawnNode.heading)
    local fwdX   = math.sin(rad)
    local fwdZ   = math.cos(rad)
    local rightX = math.cos(rad)
    local rightZ = -math.sin(rad)

    -- 随机选一条虚拟通道
    local offsets = { -C.TRACK_WIDTH / 3.5, 0.0, C.TRACK_WIDTH / 3.5 }
    local laneOff = offsets[math.random(1, 3)]

    -- 高度与船齐平，确保水面行驶即可捡到（去掉拱形高度变化）
    local cy = C.BOAT_BASE_Y + 0.5

    for i = 1, C.COIN_ROW_LEN do
        local coin = GetCoin()
        local dist = (i - 1) * C.COIN_GAP
        coin:SetPosition(Vector3(
            spawnNode.x + rightX * laneOff + fwdX * dist,
            cy,
            spawnNode.z + rightZ * laneOff + fwdZ * dist
        ))
        -- 竖立金币：pitch 90° 站立，随机初始朝向
        coinAngle[coin] = math.random(0, 359)
        coin:SetWorldRotation(Quaternion(0, coinAngle[coin], 0) * Quaternion(90, 0, 0))
        table.insert(S.activeCoins, coin)
    end
end

-- ─────────────────────────────────────────────────────────────
--  每帧更新
-- ─────────────────────────────────────────────────────────────
function M.Update(dt)
    local curIdx = Track.GetCurrentIdx()
    local loopN  = Track.GetLoopN()
    if loopN == 0 then return end

    -- 只有向前行驶超过 COIN_STEP 个索引才生成
    local diff = (curIdx - lastSpawnIdx + loopN) % loopN
    if diff >= COIN_STEP then
        local spawnNode = Track.GetNodeAtOffset(SPAWN_TILES)
        if spawnNode then
            SpawnRow(spawnNode)
        end
        lastSpawnIdx = curIdx
    end

    local bp = S.boatNode:GetPosition()

    for i = #S.activeCoins, 1, -1 do
        local coin = S.activeCoins[i]
        if coin:IsEnabled() then
            -- 竖立绕世界 Y 轴自转：angle 累计，SetWorldRotation 保持 pitch=90° 竖立
            local a = (coinAngle[coin] or 0) + 130.0 * dt
            if a >= 360 then a = a - 360 end
            coinAngle[coin] = a
            coin:SetWorldRotation(Quaternion(0, a, 0) * Quaternion(90, 0, 0))

            local p  = coin:GetPosition()
            local dx = math.abs(bp.x - p.x)
            local dy = math.abs(bp.y - p.y)
            local dz = math.abs(bp.z - p.z)

            -- 采集碰撞范围适配新尺寸
            if dx < 1.6 and dy < 1.2 and dz < 2.4 then
                S.coinCount = S.coinCount + 1
                Recycle(coin)
                table.remove(S.activeCoins, i)
            else
                -- 回收落后的金币
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
    lastSpawnIdx = 0
    S.coinTimer  = 0.0
end

return M
