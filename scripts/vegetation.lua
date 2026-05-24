-- ============================================================
--  vegetation.lua  —  沿岸草坪与树木（天津风格）
--
--  城市地面（d_outer=21m 起）生成：
--    • 草坪色带：宽 4m（d=21~25m），程序化绿色 PBR 平面
--    • 灌木：草坪带内，每瓦片每侧 1 株
--    • 树木：从草坪内缘开始（d=21~32m），树根扎在绿化带上
--             每瓦片每侧 1 株（每隔一块瓦片生成，密度适中）
--
--  天津（温带季风气候）适用树种：
--    松树02_03  model uuid://FtwVYTCFMz3bxvKCSVb0rRv8（北方常绿松）
--    松树06_03  model uuid://B46QGR91PhsQXmv1eZ3fGzYW（油松/华山松）
-- ============================================================
local C = require "config"
local S = require "state"
local U = require "utils"

local M = {}

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
-- 树木：每隔一块瓦片生成 1 株，见 SpawnForSide 中的奇偶判断

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

-- ─────────────────────────────────────────────────────────────
--  生成一簇花（5～8 朵，每朵 = Cone 茎 + Sphere 花冠）
-- ─────────────────────────────────────────────────────────────
local function SpawnFlowerCluster(wx, wz, flowerMat)
    -- 绿色茎秆材质（整个场景共用一份）
    if not M._stemMat then
        M._stemMat = Material:new()
        M._stemMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        M._stemMat:SetShaderParameter("MatDiffColor", Variant(Vector4(0.18, 0.62, 0.12, 1.0)))
        M._stemMat:SetShaderParameter("Roughness",    Variant(0.9))
        M._stemMat:SetShaderParameter("Metallic",     Variant(0.0))
    end

    local count = 5 + math.floor(LcgRand() * 4)   -- 5～8 朵
    for _ = 1, count do
        local ox     = (LcgRand() - 0.5) * 1.6     -- 散布范围 ±0.8m
        local oz     = (LcgRand() - 0.5) * 1.6
        local stemH  = 0.55 + LcgRand() * 0.35     -- 茎高 0.55～0.90m
        local headR  = 0.28 + LcgRand() * 0.18     -- 花冠半径 0.28～0.46m

        -- 茎（Cone，尖端朝上）
        local stemNode = S.mainScene:CreateChild("FlowerStem")
        stemNode:SetPosition(Vector3(wx + ox, GROUND_Y + stemH * 0.5, wz + oz))
        stemNode:SetRotation(Quaternion(180, 0, 0))    -- Cone 尖端朝上
        stemNode:SetScale(Vector3(0.10, stemH, 0.10))
        local stemSm = stemNode:CreateComponent("StaticModel")
        stemSm:SetModel(cache:GetResource("Model", "Models/Cone.mdl"))
        stemSm:SetMaterial(M._stemMat)
        stemSm:SetCastShadows(true)

        -- 花冠（Sphere，扁球形）
        local headNode = S.mainScene:CreateChild("FlowerHead")
        headNode:SetPosition(Vector3(wx + ox, GROUND_Y + stemH + headR * 0.55, wz + oz))
        headNode:SetScale(Vector3(headR * 2.2, headR * 1.4, headR * 2.2))
        local headSm = headNode:CreateComponent("StaticModel")
        headSm:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        headSm:SetMaterial(flowerMat)
        headSm:SetCastShadows(true)
    end
end

-- ─────────────────────────────────────────────────────────────
--  放置植物节点
-- ─────────────────────────────────────────────────────────────
local function SpawnPlant(def, wx, wz, scale, rotY)
    local node = S.mainScene:CreateChild("Veg")
    node:SetPosition(Vector3(wx, GROUND_Y, wz))
    node:SetRotation(Quaternion(0, rotY, 0))
    node:SetScale(Vector3(scale, scale, scale))
    local sm = node:CreateComponent("StaticModel")
    sm:SetModel(cache:GetResource("Model", def.model))
    for idx, matUuid in ipairs(def.mats) do
        sm:SetMaterial(idx - 1, cache:GetResource("Material", matUuid))
    end
    sm:SetCastShadows(true)
end

-- ─────────────────────────────────────────────────────────────
--  在某一侧生成该瓦片的植被
-- ─────────────────────────────────────────────────────────────
local function SpawnForSide(tileIdx, xSign, n)
    local heading = n.heading
    local midX    = n.midX
    local midZ    = n.midZ
    local seed0   = tileIdx * 137 + (xSign == 1 and 71 or 0)

    -- ── 草坪色带 ──────────────────────────────────────────────
    local grassCx  = xSign * (GRASS_X0 + GRASS_W * 0.5)
    local wx0, wz0 = LocalToWorld(midX, midZ, heading, grassCx, 0)
    local grassNode = S.mainScene:CreateChild("Grass")
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
        SpawnPlant(BUSH, wx, wz, RandRange(BUSH.scaleMin, BUSH.scaleMax), RandRange(0, 360))
    end

    -- ── 树木：每隔一块瓦片生成 1 株（奇偶交替），树根在绿化带上 ──
    if tileIdx % 2 == 1 then
        LcgSeed(seed0 + 50)
        local lx    = xSign * RandRange(TREE_X0, TREE_X1)
        local lz    = RandRange(-C.TILE_LEN * 0.42, C.TILE_LEN * 0.42)
        local wx, wz = LocalToWorld(midX, midZ, heading, lx, lz)
        local tDef  = TREES[RandInt(#TREES)]
        SpawnPlant(tDef, wx, wz, RandRange(tDef.scaleMin, tDef.scaleMax), RandRange(0, 360))
    end

    -- ── 花簇：每 3 块瓦片生成一簇，粉/黄交替，散布在草坪内侧 ──
    if tileIdx % 3 == 0 then
        LcgSeed(seed0 + 90)
        local lx  = xSign * RandRange(GRASS_X0 + 0.8, GRASS_X0 + 5.0)
        local lz  = RandRange(-C.TILE_LEN * 0.35, C.TILE_LEN * 0.35)
        local wx, wz = LocalToWorld(midX, midZ, heading, lx, lz)
        local isPink = ((tileIdx // 3 + (xSign == 1 and 1 or 0)) % 2 == 0)
        SpawnFlowerCluster(wx, wz, GetFlowerMat(isPink))
    end
end

-- ─────────────────────────────────────────────────────────────
--  公共接口
-- ─────────────────────────────────────────────────────────────
function M.Init()
    local path = S.trackPath
    if not path or #path == 0 then
        U.LogInfo("[Vegetation] trackPath 为空，跳过植被生成")
        return
    end

    local count = 0
    for i = 1, #path do
        local n = path[i]
        if n.midX and n.midZ then
            SpawnForSide(i, -1, n)
            SpawnForSide(i,  1, n)
            count = count + 1
        end
    end

    U.LogInfo(string.format("[Vegetation] 完成：%d 个瓦片植被已生成", count))
end

return M
