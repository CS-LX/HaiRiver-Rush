-- ============================================================
--  track.lua  —  预烘焙封闭椭圆环形赛道
--  ┌──────────────────────────────────────────────────────┐
--  │  赛道形状：标准跑道（stadium）形椭圆               │
--  │  LOOP_SEGS = {                                       │
--  │    { tiles=60, dh=0.0 },  -- 直道 600 m             │
--  │    { tiles=30, dh=6.0 },  -- 右弯 180°(6°/tile)    │
--  │    { tiles=60, dh=0.0 },  -- 直道 600 m             │
--  │    { tiles=30, dh=6.0 },  -- 右弯 180°              │
--  │  }                                                   │
--  │  共 180 瓦片，周长 ~1800 m，宽 ~189 m，长 ~610 m   │
--  │  数学验证封闭：回到 (0,0) 朝向 0° ✓               │
--  └──────────────────────────────────────────────────────┘
-- ============================================================
local C = require "config"
local S = require "state"
local U = require "utils"

local M = {}

-- ─────────────────────────────────────────────────────────────
--  环形路径定义
--  设计原则：两段直道净转向 0°（S 形弯道相互抵消）+ 两段 180° 大弯
--  总转向 = 0 + 180 + 0 + 180 = 360° → 数学封闭 ✓
--  总瓦片 = 120 + 60 + 120 + 60 = 360，周长 ~3600 m
-- ─────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────
--  ABBA 菊花弯数学证明：
--  AB 对 (+dh×N, -dh×N)：净航向 = 0，但侧向漂移 ≠ 0，导致起终点偏移！
--  ABBA 组 (+dh, -dh, -dh, +dh)：
--    弧段 1+2 从全局 heading=H 出发产生漂移 D；
--    弧段 3+4 从 heading=H 出发（与 1+2 完全镜像）产生漂移 -D；
--    总漂移 = D + (-D) = 0 ← 精确封闭 ✓
-- ─────────────────────────────────────────────────────────────
local LOOP_SEGS = {
    -- ── 直道 1（120 瓦片，净 0°，ABBA 菊花弯，侧向漂移精确为零）─
    { tiles =  5, dh =  0.0 },
    { tiles = 10, dh =  1.5 }, { tiles = 10, dh = -1.5 },   -- AB
    { tiles = 10, dh = -1.5 }, { tiles = 10, dh =  1.5 },   -- BA → ABBA ✓
    { tiles =  5, dh =  0.0 },
    { tiles =  8, dh =  1.8 }, { tiles =  8, dh = -1.8 },   -- AB
    { tiles =  8, dh = -1.8 }, { tiles =  8, dh =  1.8 },   -- BA → ABBA ✓
    { tiles =  5, dh =  0.0 },
    { tiles =  7, dh =  2.0 }, { tiles =  7, dh = -2.0 },   -- AB
    { tiles =  7, dh = -2.0 }, { tiles =  7, dh =  2.0 },   -- BA → ABBA ✓
    { tiles =  5, dh =  0.0 },
    -- 小计：5+40+5+32+5+28+5 = 120 ✓  净 0°，侧向漂移 0 ✓

    -- ── 右弯 1（60 瓦片，净 +180°）─────────────────────────────
    { tiles = 60, dh =  3.0 },

    -- ── 直道 2（120 瓦片，净 0°，ABBA 菊花弯，侧向漂移精确为零）─
    { tiles =  5, dh =  0.0 },
    { tiles =  9, dh = -1.5 }, { tiles =  9, dh =  1.5 },   -- AB（左起）
    { tiles =  9, dh =  1.5 }, { tiles =  9, dh = -1.5 },   -- BA → ABBA ✓
    { tiles =  5, dh =  0.0 },
    { tiles = 10, dh =  2.0 }, { tiles = 10, dh = -2.0 },   -- AB
    { tiles = 10, dh = -2.0 }, { tiles = 10, dh =  2.0 },   -- BA → ABBA ✓
    { tiles =  5, dh =  0.0 },
    { tiles =  6, dh = -1.8 }, { tiles =  6, dh =  1.8 },   -- AB（左起）
    { tiles =  6, dh =  1.8 }, { tiles =  6, dh = -1.8 },   -- BA → ABBA ✓
    { tiles =  5, dh =  0.0 },
    -- 小计：5+36+5+40+5+24+5 = 120 ✓  净 0°，侧向漂移 0 ✓

    -- ── 右弯 2（60 瓦片，净 +180°）─────────────────────────────
    { tiles = 60, dh =  3.0 },
    -- 总计：120+60+120+60 = 360 瓦片  总净 360° → 精确封闭 ✓
}

local LOOP_N       = 0           -- 总瓦片数（烘焙后 = 360）
local loopNodes    = {}          -- { x, z, heading } 中心线节点数组（长度 LOOP_N）
local loopTiles    = {}          -- 场景节点数组（永久存在，不回收）
local currentIdx   = 1           -- 船当前所在节点索引
local lapFirstRun  = true        -- 启动时屏蔽假圈数检测

-- 重叠系数（消除瓦片拼接缝隙）
-- WALL_OVERLAP 不宜太大，弯道处墙体会视觉交叉产生"叉路"感
local WATER_OVERLAP = 1.10
local WALL_OVERLAP  = 1.05

-- ─────────────────────────────────────────────────────────────
--  内部：构建一个瓦片节点（复用旧逻辑；默认 disabled）
-- ─────────────────────────────────────────────────────────────
local function CreateTileNode()
    local root = S.mainScene:CreateChild("Tile")
    root:SetEnabled(false)

    -- 水面
    local water = root:CreateChild("W")
    local wMdl  = water:CreateComponent("StaticModel")
    wMdl:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    wMdl:SetMaterial(U.MakeMaterial(0.04, 0.42, 0.62))
    water:SetScale(Vector3(C.TRACK_WIDTH, 1.0, C.TILE_LEN * WATER_OVERLAP))

    -- 左岸
    local lw    = root:CreateChild("LW")
    local lwMdl = lw:CreateComponent("StaticModel")
    lwMdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    lwMdl:SetMaterial(U.MakeMaterial(0.38, 0.55, 0.22))
    lw:SetScale(Vector3(C.WALL_W, C.WALL_H, C.TILE_LEN * WALL_OVERLAP))
    lw:SetPosition(Vector3(-(C.TRACK_WIDTH * 0.5 + C.WALL_W * 0.5), C.WALL_H * 0.5, 0))
    local lwRb  = lw:CreateComponent("RigidBody")
    lwRb:SetMass(0)
    lwRb:SetCollisionLayerAndMask(4, 1)
    local lwCol = lw:CreateComponent("CollisionShape")
    lwCol:SetBox(Vector3(1, 1, 1), Vector3.ZERO, Quaternion.IDENTITY)

    -- 右岸
    local rw    = root:CreateChild("RW")
    local rwMdl = rw:CreateComponent("StaticModel")
    rwMdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    rwMdl:SetMaterial(U.MakeMaterial(0.38, 0.55, 0.22))
    rw:SetScale(Vector3(C.WALL_W, C.WALL_H, C.TILE_LEN * WALL_OVERLAP))
    rw:SetPosition(Vector3(C.TRACK_WIDTH * 0.5 + C.WALL_W * 0.5, C.WALL_H * 0.5, 0))
    local rwRb  = rw:CreateComponent("RigidBody")
    rwRb:SetMass(0)
    rwRb:SetCollisionLayerAndMask(4, 1)
    local rwCol = rw:CreateComponent("CollisionShape")
    rwCol:SetBox(Vector3(1, 1, 1), Vector3.ZERO, Quaternion.IDENTITY)

    return root
end

-- ─────────────────────────────────────────────────────────────
--  内部：烘焙整条封闭环形路径
--  计算所有 loopNodes，然后按中点放置瓦片
-- ─────────────────────────────────────────────────────────────
local function BakeLoop()
    loopNodes = {}
    loopTiles = {}
    LOOP_N    = 0

    -- 第一遍：计算所有中心线节点（末端位置）
    local cx      = 0.0
    local cz      = 0.0
    local heading = 0.0

    for _, seg in ipairs(LOOP_SEGS) do
        for _ = 1, seg.tiles do
            heading = heading + seg.dh
            local rad = math.rad(heading)
            cx = cx + math.sin(rad) * C.TILE_LEN
            cz = cz + math.cos(rad) * C.TILE_LEN
            LOOP_N = LOOP_N + 1
            loopNodes[LOOP_N] = { x = cx, z = cz, heading = heading }
        end
    end

    U.LogInfo(string.format("[Track] 路径节点数=%d  末端(%.1f, %.1f) 朝向=%.1f°",
        LOOP_N, cx, cz, heading % 360))

    -- 第二遍：在相邻节点中点放置瓦片
    -- 节点 i 的瓦片放在节点 i-1 与节点 i 的中点
    -- 节点 0（虚拟起始点）= (0, 0)
    local prevX = 0.0
    local prevZ = 0.0

    for i = 1, LOOP_N do
        local n    = loopNodes[i]
        local midX = (prevX + n.x) * 0.5
        local midZ = (prevZ + n.z) * 0.5

        local tile = CreateTileNode()
        -- 先设位置再 Enable，保证静态物理体在正确位置初始化
        tile:SetPosition(Vector3(midX, -0.05, midZ))
        tile:SetRotation(Quaternion(0, n.heading, 0))
        tile:SetEnabled(true)

        loopTiles[i] = tile

        prevX = n.x
        prevZ = n.z
    end

    lapStartZ = 0.0   -- 起始 Z，用于圈数检测
    currentIdx = 1

    -- 同步旧接口需要的 state 字段（障碍物/金币系统可能读取）
    S.trackPath       = loopNodes
    S.trackEndX       = loopNodes[LOOP_N].x
    S.trackEndZ       = loopNodes[LOOP_N].z
    S.trackEndHeading = loopNodes[LOOP_N].heading
end

-- ─────────────────────────────────────────────────────────────
--  内部：更新 currentIdx（每帧调用）
--  在窗口 [-3, +20] 内找到离船最近的节点
-- ─────────────────────────────────────────────────────────────
local function UpdateCurrentIdx(boatX, boatZ)
    if LOOP_N == 0 then return end

    local bestDist = math.huge
    local bestIdx  = currentIdx

    -- 扫描前后窗口，避免全量搜索
    local SCAN_BACK  = 3
    local SCAN_FRONT = 20

    for offset = -SCAN_BACK, SCAN_FRONT do
        local idx = ((currentIdx - 1 + offset) % LOOP_N) + 1
        local n   = loopNodes[idx]
        local dx  = boatX - n.x
        local dz  = boatZ - n.z
        local d2  = dx * dx + dz * dz
        if d2 < bestDist then
            bestDist = d2
            bestIdx  = idx
        end
    end

    -- 检测是否完成一圈（从末尾索引跨回索引 1 附近）
    if bestIdx < currentIdx - SCAN_BACK and currentIdx > LOOP_N - SCAN_FRONT then
        if lapFirstRun then
            -- 游戏启动时船在终点附近，忽略首次假圈数
            lapFirstRun = false
        else
            S.lapCount = S.lapCount + 1
            U.LogInfo("[Track] 完成第 " .. S.lapCount .. " 圈")
        end
    end

    currentIdx = bestIdx
end

-- ─────────────────────────────────────────────────────────────
--  公共接口
-- ─────────────────────────────────────────────────────────────

-- 找 boatZ 前方 distAhead 处的中心线节点（障碍物/金币生成用）
-- 保持旧签名以兼容 obstacles.lua / coins.lua
function M.GetNodeAhead(boatZ, distAhead)
    if LOOP_N == 0 then return nil end
    local tilesAhead = math.max(1, math.floor(distAhead / C.TILE_LEN))
    local idx = ((currentIdx - 1 + tilesAhead) % LOOP_N) + 1
    return loopNodes[idx]
end

-- 找离 (x, z) 最近的中心线节点（boatphys 碰墙检测备用）
function M.GetNearestNode(x, z)
    if LOOP_N == 0 then return nil end
    local best     = nil
    local bestDist = math.huge
    -- 在 currentIdx 附近扫描，足够覆盖碰撞检测需求
    for offset = -5, 10 do
        local idx = ((currentIdx - 1 + offset) % LOOP_N) + 1
        local n   = loopNodes[idx]
        local dx  = x - n.x
        local dz  = z - n.z
        local d2  = dx * dx + dz * dz
        if d2 < bestDist then
            bestDist = d2
            best     = n
        end
    end
    return best
end

-- 初始化：烘焙封闭环形赛道（只在游戏启动时调用一次）
function M.Init()
    BakeLoop()
    U.LogInfo("[Track] 初始化完毕，共 " .. LOOP_N .. " 个瓦片（永久放置）")
end

-- 每帧更新：更新当前节点索引，不再需要动态生成/回收
function M.Update(boatX, boatZ)
    UpdateCurrentIdx(boatX, boatZ)
end

-- 重置（重新开始游戏）：瓦片不动，只重置索引和圈数
function M.Reset()
    currentIdx   = 1
    lapFirstRun  = true   -- 重新屏蔽启动假圈数
    S.lapCount   = 0
    U.LogInfo("[Track] 重置完成（瓦片保留，圈数归零）")
end

return M
