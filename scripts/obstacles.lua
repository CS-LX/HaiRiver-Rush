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
--   浮标缩小后半径约 0.45m；玩家近似半径 1.1m
local BUOY_HW = 0.45 + 1.1   -- 左右 = 1.55m
local BUOY_HL = 0.45 + 1.8   -- 前后 = 2.25m（船较长，纵向放宽）

-- ── 浮标闪烁参数 ─────────────────────────────────────────────
local BLINK_PERIOD = 0.55     -- 闪烁周期（秒）

-- ── 浮标伤害冷却 ─────────────────────────────────────────────
local BUOY_HIT_CD  = 0.50
local buoyLastHit  = -10.0

-- ── 浮标对象池 ───────────────────────────────────────────────
-- 每个 entry: { node=Node, lightNode=Node, side="left"|"right" }
local buoyPool    = {}
local activeBuoys = {}

-- 预建材质（只创建一次）
local buoyMatLeft  = nil   -- 左=红，港左红浮标
local buoyMatRight = nil   -- 右=绿，港右绿浮标

local function GetBuoyMat(side)
    if side == "left" then
        if not buoyMatLeft then
            buoyMatLeft = Material:new()
            buoyMatLeft:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
            buoyMatLeft:SetShaderParameter("MatDiffColor",    Variant(Color(0.9, 0.08, 0.06, 1.0)))
            buoyMatLeft:SetShaderParameter("Metallic",        Variant(0.4))
            buoyMatLeft:SetShaderParameter("Roughness",       Variant(0.45))
            buoyMatLeft:SetShaderParameter("MatEmissiveColor",Variant(Color(1.6, 0.1, 0.1)))
        end
        return buoyMatLeft
    else
        if not buoyMatRight then
            buoyMatRight = Material:new()
            buoyMatRight:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
            buoyMatRight:SetShaderParameter("MatDiffColor",    Variant(Color(0.06, 0.80, 0.12, 1.0)))
            buoyMatRight:SetShaderParameter("Metallic",        Variant(0.4))
            buoyMatRight:SetShaderParameter("Roughness",       Variant(0.45))
            buoyMatRight:SetShaderParameter("MatEmissiveColor",Variant(Color(0.1, 1.6, 0.15)))
        end
        return buoyMatRight
    end
end

-- ─────────────────────────────────────────────────────────────
--  浮标工厂（side = "left" 或 "right"）
-- ─────────────────────────────────────────────────────────────
local function BuildBuoy(side)
    local node = S.mainScene:CreateChild("Buoy")
    node:SetEnabled(false)
    local mdl = node:CreateComponent("StaticModel")
    mdl:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    mdl:SetMaterial(GetBuoyMat(side))
    mdl:SetCastShadows(true)
    -- 浮标缩小：直径 0.9m，高 1.2m
    node:SetScale(Vector3(0.9, 1.2, 0.9))

    -- 顶部闪烁点光源
    local ln = node:CreateChild("BuoyLight")
    ln:SetPosition(Vector3(0, 0.8, 0))
    local light = ln:CreateComponent("Light")
    light.lightType   = LIGHT_POINT
    light.color       = side == "left" and Color(1.0, 0.1, 0.1) or Color(0.1, 1.0, 0.2)
    light.brightness  = 2.0
    light.range       = 6.0
    light.castShadows = false

    return { node = node, lightNode = ln, side = side }
end

local function GetBuoy(side)
    local e
    -- 从池中寻找同侧的浮标
    for i = #buoyPool, 1, -1 do
        if buoyPool[i].side == side then
            e = table.remove(buoyPool, i)
            break
        end
    end
    if not e then e = BuildBuoy(side) end
    e.node:SetEnabled(true)
    e.lightNode:SetEnabled(true)   -- 重置闪烁状态
    return e
end

local function RecycleBuoy(e)
    e.node:SetEnabled(false)
    table.insert(buoyPool, e)
end

-- ─────────────────────────────────────────────────────────────
--  生成一个障碍物（浮标对 or 游船）
--  浮标总是成对生成：左舷红色 + 右舷绿色（航行标准配色）
-- ─────────────────────────────────────────────────────────────
local function SpawnBuoyPair(spawnNode)
    local rad    = math.rad(spawnNode.heading)
    local rightX = math.cos(rad)
    local rightZ = -math.sin(rad)
    -- 浮标贴近两侧岸边，与赛道宽度关联
    local sideOff = C.TRACK_WIDTH * 0.38   -- 距中心约 38% 宽度（靠岸）

    local sides = { { off = -sideOff, side = "left" }, { off = sideOff, side = "right" } }
    for _, s in ipairs(sides) do
        local e = GetBuoy(s.side)
        e.node:SetWorldPosition(Vector3(
            spawnNode.x + rightX * s.off,
            0.6,    -- 浮出水面
            spawnNode.z + rightZ * s.off
        ))
        e.node:SetWorldRotation(Quaternion(0, spawnNode.heading, 0))
        e.blinkTimer = 0.0
        e.lightOn    = true
        table.insert(activeBuoys, e)
    end
end

local function SpawnAt(spawnNode)
    local t       = OBS_TYPES[math.random(1, #OBS_TYPES)]
    local rad     = math.rad(spawnNode.heading)
    local rightX  = math.cos(rad)
    local rightZ  = -math.sin(rad)
    local lanes   = { -C.TRACK_WIDTH / 3.2, 0.0, C.TRACK_WIDTH / 3.2 }
    local laneOff = lanes[math.random(1, 3)]

    if t == "buoy" then
        SpawnBuoyPair(spawnNode)
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

    -- ── 浮标：闪烁更新 + 碰撞检测 + 回收 ────────────────────
    local bp   = S.gameState == "playing" and S.boatNode:GetWorldPosition() or nil
    local now  = time and time:GetElapsedTime() or 0
    local fwdX = math.sin(math.rad(S.boatHeading))
    local fwdZ = math.cos(math.rad(S.boatHeading))

    for i = #activeBuoys, 1, -1 do
        local e = activeBuoys[i]
        if e.node:IsEnabled() then
            -- 闪烁逻辑
            e.blinkTimer = e.blinkTimer + dt
            if e.blinkTimer >= BLINK_PERIOD then
                e.blinkTimer = e.blinkTimer - BLINK_PERIOD
                e.lightOn = not e.lightOn
                e.lightNode:SetEnabled(e.lightOn)
            end

            local p  = e.node:GetWorldPosition()

            -- AABB 碰撞（仅游戏中）
            if bp then
                local dx = math.abs(bp.x - p.x)
                local dz = math.abs(bp.z - p.z)
                if dx < BUOY_HW and dz < BUOY_HL then
                    if (now - buoyLastHit) >= BUOY_HIT_CD then
                        buoyLastHit = now
                        if TakeDurabilityHit then TakeDurabilityHit("buoy") end
                        U.LogInfo("[Obs] 撞浮标！扣耐久")
                    end
                end
            end

            -- 回收落后浮标
            local ddx = p.x - S.boatPosX
            local ddz = p.z - S.boatPosZ
            if ddx * fwdX + ddz * fwdZ < -C.RECYCLE_DIST then
                RecycleBuoy(e)
                table.remove(activeBuoys, i)
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
