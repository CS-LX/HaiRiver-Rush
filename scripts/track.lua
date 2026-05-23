-- ============================================================
--  track.lua  —  无限程序化河道赛道
--  负责：瓦片网格构建、弯道段生成、回收、中心线查询
-- ============================================================
local C = require "config"
local S = require "state"
local U = require "utils"

local M = {}

-- 前方最少保持的看前距离（超出时补充新段）
local LOOK_AHEAD = 180.0

-- 瓦片 Z 方向放大系数：消除弯道拼接缝隙（水面 / 堤坝分开控制）
local WATER_OVERLAP = 1.10   -- 水面横向稍微重叠
local WALL_OVERLAP  = 1.30   -- 堤坝更大重叠，彻底封堵角落

-- ─────────────────────────────────────────────────────────────
--  内部：构建一个瓦片节点（水面 + 左岸 + 右岸）
--  堤坝附加 RigidBody(静态) + CollisionShape，碰撞层 = 4
--  注意：瓦片节点默认 disabled，由 AppendTile 在设置好位置后 enable
-- ─────────────────────────────────────────────────────────────
local function CreateTileNode()
    local root = S.mainScene:CreateChild("Tile")
    root:SetEnabled(false)

    -- ── 水面平面 ─────────────────────────────────────────────
    local water = root:CreateChild("W")
    local wMdl  = water:CreateComponent("StaticModel")
    wMdl:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    wMdl:SetMaterial(U.MakeMaterial(0.04, 0.42, 0.62))
    -- Z 方向稍微拉长消除接缝
    water:SetScale(Vector3(C.TRACK_WIDTH, 1.0, C.TILE_LEN * WATER_OVERLAP))

    -- ── 左岸堤坝 ─────────────────────────────────────────────
    local lw     = root:CreateChild("LW")
    local lwMdl  = lw:CreateComponent("StaticModel")
    lwMdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    lwMdl:SetMaterial(U.MakeMaterial(0.38, 0.55, 0.22))
    lw:SetScale(Vector3(C.WALL_W, C.WALL_H, C.TILE_LEN * WALL_OVERLAP))
    lw:SetPosition(Vector3(-(C.TRACK_WIDTH * 0.5 + C.WALL_W * 0.5), C.WALL_H * 0.5, 0))

    -- 左岸物理碰撞（静态刚体，碰撞层 4 = 堤岸）
    local lwRb  = lw:CreateComponent("RigidBody")
    lwRb:SetMass(0)
    lwRb:SetCollisionLayerAndMask(4, 1)
    local lwCol = lw:CreateComponent("CollisionShape")
    -- SetBox 尺寸为节点本地空间（1×1×1），实际物理尺寸由 SetScale 决定
    lwCol:SetBox(Vector3(1, 1, 1), Vector3.ZERO, Quaternion.IDENTITY)

    -- ── 右岸堤坝 ─────────────────────────────────────────────
    local rw     = root:CreateChild("RW")
    local rwMdl  = rw:CreateComponent("StaticModel")
    rwMdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    rwMdl:SetMaterial(U.MakeMaterial(0.38, 0.55, 0.22))
    rw:SetScale(Vector3(C.WALL_W, C.WALL_H, C.TILE_LEN * WALL_OVERLAP))
    rw:SetPosition(Vector3(C.TRACK_WIDTH * 0.5 + C.WALL_W * 0.5, C.WALL_H * 0.5, 0))

    -- 右岸物理碰撞
    local rwRb  = rw:CreateComponent("RigidBody")
    rwRb:SetMass(0)
    rwRb:SetCollisionLayerAndMask(4, 1)
    local rwCol = rw:CreateComponent("CollisionShape")
    rwCol:SetBox(Vector3(1, 1, 1), Vector3.ZERO, Quaternion.IDENTITY)

    return root
end

-- ─────────────────────────────────────────────────────────────
--  内部：追加一块瓦片到赛道末端
--  关键：先设置位置再 Enable，确保物理体在正确位置激活
-- ─────────────────────────────────────────────────────────────
local function AppendTile(prevX, prevZ, heading)
    local midX = (prevX + S.trackEndX) * 0.5
    local midZ = (prevZ + S.trackEndZ) * 0.5

    -- 从池中取或新建（先不 enable）
    local tile
    if #S.tilePool > 0 then
        tile = table.remove(S.tilePool)
    else
        tile = CreateTileNode()
    end

    -- 先设置变换，再 enable——保证静态物理体在正确世界位置初始化
    tile:SetPosition(Vector3(midX, -0.05, midZ))
    tile:SetRotation(Quaternion(0, heading, 0))
    tile:SetEnabled(true)

    table.insert(S.trackMeshes, { node = tile, endZ = S.trackEndZ })
end

local function RecycleTile(n)
    n:SetEnabled(false)
    table.insert(S.tilePool, n)
end

-- ─────────────────────────────────────────────────────────────
--  内部：生成一段赛道（若干块瓦片 + 对应中心线节点）
-- ─────────────────────────────────────────────────────────────
local function GenerateSegment()
    local r = math.random(4)
    -- 直道 50%，左弯 25%，右弯 25%
    local turnPerTile = 0.0
    if r == 3 then
        turnPerTile = -C.CURVE_ANGLE / C.TILES_PER_SEG   -- 左弯
    elseif r == 4 then
        turnPerTile =  C.CURVE_ANGLE / C.TILES_PER_SEG   -- 右弯
    end

    for i = 1, C.TILES_PER_SEG do
        S.trackEndHeading = S.trackEndHeading + turnPerTile
        local heading = S.trackEndHeading
        local rad     = math.rad(heading)

        local prevX = S.trackEndX
        local prevZ = S.trackEndZ

        -- 沿朝向前进一个瓦片
        S.trackEndX = S.trackEndX + math.sin(rad) * C.TILE_LEN
        S.trackEndZ = S.trackEndZ + math.cos(rad) * C.TILE_LEN

        -- 记录中心线节点（末端位置）
        table.insert(S.trackPath, {
            x       = S.trackEndX,
            z       = S.trackEndZ,
            heading = heading,
        })

        AppendTile(prevX, prevZ, heading)
    end
end

-- ─────────────────────────────────────────────────────────────
--  公共接口
-- ─────────────────────────────────────────────────────────────

-- 找距离 (x, z) 最近的中心线节点（用于碰墙检测备用查询）
function M.GetNearestNode(x, z)
    if #S.trackPath == 0 then return nil end
    local best     = nil
    local bestDist = math.huge
    local startIdx = math.max(1, #S.trackPath - 30)
    for i = startIdx, #S.trackPath do
        local n  = S.trackPath[i]
        local dx = x - n.x
        local dz = z - n.z
        local d  = dx * dx + dz * dz
        if d < bestDist then
            bestDist = d
            best     = n
        end
    end
    return best
end

-- 找位于 boatZ 前方 distAhead 处的中心线节点（障碍物/金币生成用）
function M.GetNodeAhead(boatZ, distAhead)
    local targetZ = boatZ + distAhead
    if #S.trackPath == 0 then return nil end
    local best     = nil
    local bestDiff = math.huge
    for i = 1, #S.trackPath do
        local n    = S.trackPath[i]
        local diff = math.abs(n.z - targetZ)
        if diff < bestDiff then
            bestDiff = diff
            best     = n
        end
    end
    return best
end

-- 初始化：预生成若干段
function M.Init()
    S.trackEndX       = 0.0
    S.trackEndZ       = -C.TILE_LEN
    S.trackEndHeading = 0.0
    S.trackPath       = {}
    S.trackMeshes     = {}
    S.tilePool        = {}

    for i = 1, C.NUM_INIT_SEGS do
        GenerateSegment()
    end
    U.LogInfo("[Track] 初始化完毕，节点数=" .. #S.trackPath)
end

-- 每帧更新：生成新段 + 回收旧瓦片
function M.Update(boatX, boatZ)
    while S.trackEndZ < boatZ + LOOK_AHEAD do
        GenerateSegment()
    end

    for i = #S.trackMeshes, 1, -1 do
        local entry = S.trackMeshes[i]
        if entry.endZ < boatZ - C.RECYCLE_DIST then
            RecycleTile(entry.node)
            table.remove(S.trackMeshes, i)
        end
    end

    -- 裁剪过时的中心线节点（避免无限增长）
    while #S.trackPath > 200 do
        table.remove(S.trackPath, 1)
    end
end

-- 重置（重新开始游戏）
function M.Reset()
    for i = #S.trackMeshes, 1, -1 do
        RecycleTile(S.trackMeshes[i].node)
        table.remove(S.trackMeshes, i)
    end
    S.trackPath       = {}
    S.trackEndX       = 0.0
    S.trackEndZ       = -C.TILE_LEN
    S.trackEndHeading = 0.0

    for i = 1, C.NUM_INIT_SEGS do
        GenerateSegment()
    end
    U.LogInfo("[Track] 重置完成")
end

return M
