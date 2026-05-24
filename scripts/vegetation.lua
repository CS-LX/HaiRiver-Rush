-- ============================================================
--  vegetation.lua  —  沿岸草坪与树木（天津风格）—— 流式加载版
--
--  城市地面（d_outer=21m 起）生成：
--    • 草坪色带：宽 4m（d=21~25m），程序化绿色 PBR 平面
--    • 灌木：草坪带内，每瓦片每侧 1 株
--    • 树木：从草坪内缘开始（d=21~32m），树根扎在绿化带上
--             每瓦片每侧 1 株（每隔一块瓦片生成，密度适中）
--
--  流式策略：
--    仅在 [curIdx - STREAM_BEHIND, curIdx + STREAM_AHEAD] 范围内的瓦片保持节点
--    超出范围的瓦片节点会被 Remove()，下次进入范围时重新生成
-- ============================================================
local C = require "config"
local S = require "state"
local U = require "utils"

local M = {}

-- ─────────────────────────────────────────────────────────────
--  流式常量
-- ─────────────────────────────────────────────────────────────
local STREAM_AHEAD  = 55   -- 提前加载 55 个瓦片（~550m）
local STREAM_BEHIND = 15   -- 保留身后 15 个瓦片（~150m）

-- [tileIdx] = { root, root, ... }（每个瓦片可能有多个根节点）
local tileRoots = {}
local frameCount = 0

-- ─────────────────────────────────────────────────────────────
--  常量
-- ─────────────────────────────────────────────────────────────
local D_OUTER  = C.TRACK_WIDTH * 0.5 + C.WALL_W * 5   -- 21.0 m（台阶外缘）
local GROUND_Y = C.WALL_H                              -- 3.2 m（城市地面高度）

-- 草坪带（紧贴台阶外缘，宽 13m，完整覆盖树木区域）
local GRASS_W  = 13.0
local GRASS_X0 = D_OUTER                               -- 草坪内缘  21.0 m
local GRASS_X1 = D_OUTER + GRASS_W                     -- 草坪外缘  34.0 m

-- 树木区：从草坪内缘到外缘内侧，全程在绿化带内
local TREE_X0  = GRASS_X0 + 0.5                        -- 21.5 m
local TREE_X1  = GRASS_X1 - 1.0                        -- 33.0 m（绿化带内留 1m 边距）

-- 每侧每瓦片生成数量
local BUSH_PER_TILE = 1    -- 灌木：每瓦片每侧 1 株

-- ─────────────────────────────────────────────────────────────
--  植物定义（仅保留天津适用树种）
-- ─────────────────────────────────────────────────────────────
local TREES = {
    {   -- 松树02_03（北方常绿松，天津市常见行道树）
        model = "uuid://FtwVYTCFMz3bxvKCSVb0rRv8",
        mats  = {
            "uuid://BZ1nqatkaaJ2ukQH2oweAAd9",
            "uuid://EzElKfmtWe7gk-ocY4WYL6An",
        },
        scaleMin = 1.4, scaleMax = 2.6,
    },
    {   -- 松树06_03（油松/华山松，天津常见园林绿化树）
        model = "uuid://B46QGR91PhsQXmv1eZ3fGzYW",
        mats  = {
            "uuid://BZ1nqatkaaJ2ukQH2oweAAd9",
            "uuid://BOb-ubR27niRGAkB6MmTTU-s",
        },
        scaleMin = 1.2, scaleMax = 2.4,
    },
}

local BUSH = {
    model = "uuid://BOIeQUEFW8eOx-D44nUXpD8w",
    mats  = { "uuid://A8hOgRfgwV6NxsRz6d23T3cK" },
    scaleMin = 0.5, scaleMax = 1.0,
}

-- ─────────────────────────────────────────────────────────────
--  确定性 LCG 随机（基于种子）
-- ─────────────────────────────────────────────────────────────
local lcgState = 0

local function LcgSeed(s)
    lcgState = s & 0x7FFFFFFF
end

local function LcgRand()
    lcgState = (lcgState * 1664525 + 1013904223) & 0x7FFFFFFF
    return lcgState / 0x7FFFFFFF
end

local function RandRange(lo, hi)
    return lo + LcgRand() * (hi - lo)
end

local function RandInt(n)
    return math.floor(LcgRand() * n) + 1
end

-- ─────────────────────────────────────────────────────────────
--  瓦片局部坐标 → 世界坐标
-- ─────────────────────────────────────────────────────────────
local function LocalToWorld(midX, midZ, heading, lx, lz)
    local rad = math.rad(heading)
    local wx  = midX + lx * math.cos(rad) + lz * math.sin(rad)
    local wz  = midZ - lx * math.sin(rad) + lz * math.cos(rad)
    return wx, wz
end

-- ─────────────────────────────────────────────────────────────
--  草坪材质（仅创建一次）
-- ─────────────────────────────────────────────────────────────
---@type Material|nil
local grassMat    = nil
---@type Material|nil
local flowerMatPink   = nil
---@type Material|nil
local flowerMatYellow = nil
---@type Material|nil
local stemMat = nil

local function GetGrassMat()
    if grassMat then return grassMat end
    grassMat = Material:new()
    grassMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    grassMat:SetShaderParameter("MatDiffColor", Variant(Vector4(0.12, 0.78, 0.10, 1.0)))
    grassMat:SetShaderParameter("Roughness",    Variant(0.9))
    grassMat:SetShaderParameter("Metallic",     Variant(0.0))
    return grassMat
end

local function GetFlowerMat(pink)
    if pink then
        if flowerMatPink then return flowerMatPink end
        flowerMatPink = Material:new()
        flowerMatPink:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        flowerMatPink:SetShaderParameter("MatDiffColor", Variant(Vector4(0.95, 0.38, 0.60, 1.0)))
        flowerMatPink:SetShaderParameter("Roughness",    Variant(0.8))
        flowerMatPink:SetShaderParameter("Metallic",     Variant(0.0))
        return flowerMatPink
    else
        if flowerMatYellow then return flowerMatYellow end
        flowerMatYellow = Material:new()
        flowerMatYellow:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        flowerMatYellow:SetShaderParameter("MatDiffColor", Variant(Vector4(1.0, 0.88, 0.08, 1.0)))
        flowerMatYellow:SetShaderParameter("Roughness",    Variant(0.75))
        flowerMatYellow:SetShaderParameter("Metallic",     Variant(0.0))
        return flowerMatYellow
    end
end

local function GetStemMat()
    if stemMat then return stemMat end
    stemMat = Material:new()
    stemMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    stemMat:SetShaderParameter("MatDiffColor", Variant(Vector4(0.18, 0.62, 0.12, 1.0)))
    stemMat:SetShaderParameter("Roughness",    Variant(0.9))
    stemMat:SetShaderParameter("Metallic",     Variant(0.0))
    return stemMat
end

-- ─────────────────────────────────────────────────────────────
--  生成一簇花（5～8 朵），所有子节点挂在 clusterRoot 下
-- ─────────────────────────────────────────────────────────────
local function SpawnFlowerCluster(parent, wx, wz, flowerMat)
    local clusterRoot = parent:CreateChild("FlowerCluster")
    clusterRoot:SetPosition(Vector3(wx, 0, wz))   -- 相对 scene 为世界坐标

    local count = 5 + math.floor(LcgRand() * 4)   -- 5～8 朵
    for _ = 1, count do
        local ox     = (LcgRand() - 0.5) * 1.6
        local oz     = (LcgRand() - 0.5) * 1.6
        local stemH  = 0.55 + LcgRand() * 0.35
        local headR  = 0.28 + LcgRand() * 0.18

        -- 茎（Cone，尖端朝上）
        local stemNode = clusterRoot:CreateChild("FlowerStem")
        stemNode:SetPosition(Vector3(ox, GROUND_Y + stemH * 0.5, oz))
        stemNode:SetRotation(Quaternion(180, 0, 0))
        stemNode:SetScale(Vector3(0.10, stemH, 0.10))
        local stemSm = stemNode:CreateComponent("StaticModel")
        stemSm:SetModel(cache:GetResource("Model", "Models/Cone.mdl"))
        stemSm:SetMaterial(GetStemMat())
        stemSm:SetCastShadows(true)

        -- 花冠（Sphere，扁球形）
        local headNode = clusterRoot:CreateChild("FlowerHead")
        headNode:SetPosition(Vector3(ox, GROUND_Y + stemH + headR * 0.55, oz))
        headNode:SetScale(Vector3(headR * 2.2, headR * 1.4, headR * 2.2))
        local headSm = headNode:CreateComponent("StaticModel")
        headSm:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        headSm:SetMaterial(flowerMat)
        headSm:SetCastShadows(true)
    end

    return clusterRoot
end

-- ─────────────────────────────────────────────────────────────
--  放置植物节点（挂在 parent 下），返回节点
-- ─────────────────────────────────────────────────────────────
local function SpawnPlant(parent, def, wx, wz, scale, rotY)
    local node = parent:CreateChild("Veg")
    node:SetPosition(Vector3(wx, GROUND_Y, wz))
    node:SetRotation(Quaternion(0, rotY, 0))
    node:SetScale(Vector3(scale, scale, scale))
    local sm = node:CreateComponent("StaticModel")
    sm:SetModel(cache:GetResource("Model", def.model))
    for idx, matUuid in ipairs(def.mats) do
        sm:SetMaterial(idx - 1, cache:GetResource("Material", matUuid))
    end
    sm:SetCastShadows(true)
    return node
end

-- ─────────────────────────────────────────────────────────────
--  在某一侧生成该瓦片的植被，所有节点挂在 sideRoot 下，返回 sideRoot
-- ─────────────────────────────────────────────────────────────
local function SpawnForSide(tileIdx, xSign, n)
    local heading = n.heading
    local midX    = n.midX
    local midZ    = n.midZ
    local seed0   = tileIdx * 137 + (xSign == 1 and 71 or 0)

    -- 创建此侧的根节点（所有子节点都挂在这里，Remove 它即清理全部）
    -- 保持在世界原点，子节点使用 LocalToWorld 计算出的世界坐标直接赋值
    local sideRoot = S.mainScene:CreateChild("VegSide")

    -- ── 草坪色带 ──────────────────────────────────────────────
    local grassCx  = xSign * (GRASS_X0 + GRASS_W * 0.5)
    local wx0, wz0 = LocalToWorld(midX, midZ, heading, grassCx, 0)
    local grassNode = sideRoot:CreateChild("Grass")
    grassNode:SetPosition(Vector3(wx0, GROUND_Y + 0.01, wz0))
    grassNode:SetRotation(Quaternion(0, heading, 0))
    grassNode:SetScale(Vector3(GRASS_W, 0.05, C.TILE_LEN))
    local gsm = grassNode:CreateComponent("StaticModel")
    gsm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    gsm:SetMaterial(GetGrassMat())
    gsm:SetCastShadows(true)

    -- ── 灌木：草坪带内，每瓦片每侧 1 株 ──────────────────────
    for k = 1, BUSH_PER_TILE do
        LcgSeed(seed0 + k)
        local lx = xSign * RandRange(GRASS_X0 + 0.4, GRASS_X1 - 0.4)
        local lz = RandRange(-C.TILE_LEN * 0.38, C.TILE_LEN * 0.38)
        local wx, wz = LocalToWorld(midX, midZ, heading, lx, lz)
        SpawnPlant(sideRoot, BUSH, wx, wz,
            RandRange(BUSH.scaleMin, BUSH.scaleMax), RandRange(0, 360))
    end

    -- ── 树木：每隔一块瓦片生成 1 株（奇偶交替），树根在绿化带上 ──
    if tileIdx % 2 == 1 then
        LcgSeed(seed0 + 50)
        local lx    = xSign * RandRange(TREE_X0, TREE_X1)
        local lz    = RandRange(-C.TILE_LEN * 0.42, C.TILE_LEN * 0.42)
        local wx, wz = LocalToWorld(midX, midZ, heading, lx, lz)
        local tDef  = TREES[RandInt(#TREES)]
        SpawnPlant(sideRoot, tDef, wx, wz,
            RandRange(tDef.scaleMin, tDef.scaleMax), RandRange(0, 360))
    end

    -- ── 花簇：每 3 块瓦片生成一簇，粉/黄交替，散布在草坪内侧 ──
    if tileIdx % 3 == 0 then
        LcgSeed(seed0 + 90)
        local lx  = xSign * RandRange(GRASS_X0 + 0.8, GRASS_X0 + 5.0)
        local lz  = RandRange(-C.TILE_LEN * 0.35, C.TILE_LEN * 0.35)
        local wx, wz = LocalToWorld(midX, midZ, heading, lx, lz)
        local isPink = ((tileIdx // 3 + (xSign == 1 and 1 or 0)) % 2 == 0)
        SpawnFlowerCluster(sideRoot, wx, wz, GetFlowerMat(isPink))
    end

    return sideRoot
end

-- ─────────────────────────────────────────────────────────────
--  流式：生成 / 删除 / 范围判断
-- ─────────────────────────────────────────────────────────────
local function SpawnTile(i)
    if tileRoots[i] then return end
    local path = S.trackPath
    if not path then return end
    local n = path[i]
    if not n or not n.midX then return end

    local roots = {}
    roots[1] = SpawnForSide(i, -1, n)
    roots[2] = SpawnForSide(i,  1, n)
    tileRoots[i] = roots
end

local function RemoveTile(i)
    local roots = tileRoots[i]
    if not roots then return end
    for _, r in ipairs(roots) do
        if r and r.valid then r:Remove() end
    end
    tileRoots[i] = nil
end

local function InRange(i, curIdx, loopN)
    local fwd = (i - curIdx + loopN) % loopN
    return fwd <= STREAM_AHEAD or fwd >= loopN - STREAM_BEHIND
end

-- ─────────────────────────────────────────────────────────────
--  公共接口
-- ─────────────────────────────────────────────────────────────
function M.Init()
    -- 仅做预检，不再立刻生成所有瓦片（由 M.Update 驱动流式加载）
    local path = S.trackPath
    if not path or #path == 0 then
        U.LogInfo("[Vegetation] trackPath 为空，跳过植被生成")
        return
    end
    U.LogInfo(string.format("[Vegetation] 配置完毕（共 %d 个瓦片），等待流式加载", #path))
end

function M.Update(curIdx, loopN)
    if loopN == 0 then return end
    local path = S.trackPath
    if not path or #path == 0 then return end

    -- 加载范围内未加载的瓦片
    for offset = -STREAM_BEHIND, STREAM_AHEAD do
        local i = (curIdx - 1 + offset + loopN) % loopN + 1
        if not tileRoots[i] then
            SpawnTile(i)
        end
    end

    -- 每 90 帧清理一次超出范围的瓦片（约 1.5s @60fps）
    frameCount = frameCount + 1
    if frameCount % 90 == 0 then
        for i in pairs(tileRoots) do
            if not InRange(i, curIdx, loopN) then
                RemoveTile(i)
            end
        end
    end
end

function M.Reset()
    for i in pairs(tileRoots) do
        RemoveTile(i)
    end
    tileRoots  = {}
    frameCount = 0
    U.LogInfo("[Vegetation] 已清除所有植被节点")
end

return M
