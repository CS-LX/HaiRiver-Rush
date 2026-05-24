-- ============================================================
--  buildings.lua  —  沿岸建筑生成系统
--
--  建筑分两层，从近到远：
--    短楼（欧式小楼，tier="short"）：绿化带外侧约 41m 行
--    高楼第一行（玻璃幕墙写字楼，tier="tall"）：约 62m 行
--    高楼第二行（tier="tall"，更高）：约 87m 行
--
--  从河边看：近处欧式矮楼 → 后排玻璃高层 → 第二排更高玻璃高层
--
--  配置文件：assets/buildings.json
--    types.{id}:
--      tier      "short" | "tall"
--      spanZ     沿赛道方向宽度（m）
--      spanX     垂直赛道方向深度（m）
--      heightMin/heightMax  随机高度范围
--      parts[]:
--        yBottom/yTop   该构件在建筑高度中的比例区间 [0,1]
--        xScale/zScale  构件相对 spanX/spanZ 的缩放（>1 = 挑出/挑檐）
--        color[r,g,b]   PBR 基色
--        roughness      粗糙度 [0,1]
--        metallic       金属度 [0,1]
-- ============================================================
local C    = require "config"
local S    = require "state"
local U    = require "utils"

local M = {}

-- ─────────────────────────────────────────────────────────────
--  距离常量（与 vegetation.lua 保持一致）
-- ─────────────────────────────────────────────────────────────
-- 绿化带外缘 = TRACK_WIDTH/2 + WALL_W*5 + GRASS_W
--           = 12 + 9 + 13 = 34m
local GRASS_X1 = C.TRACK_WIDTH * 0.5 + C.WALL_W * 5 + 13.0

local GROUND_Y = C.WALL_H    -- 城市地面 y = 3.2m

-- 建筑行中心 X（距赛道中心的横向距离）
-- 短楼：绿化带外缘 + 1m 间隙 + spanX/2 = 34 + 1 + 6 = 41m
-- 高楼行1：短楼外缘 + 4m 间隙 + spanX/2 = 48 + 4 + 10 = 62m
-- 高楼行2：高楼行1外缘 + 5m 间隙 + spanX/2 = 72 + 5 + 10 = 87m
local SHORT_ROW_X = 41.0
local TALL_ROW1_X = 62.0
local TALL_ROW2_X = 87.0

-- ─────────────────────────────────────────────────────────────
--  确定性 LCG 随机
-- ─────────────────────────────────────────────────────────────
local lcgState = 0
local function LcgSeed(s)  lcgState = s & 0x7FFFFFFF  end
local function LcgRand()
    lcgState = (lcgState * 1664525 + 1013904223) & 0x7FFFFFFF
    return lcgState / 0x7FFFFFFF
end
local function RandRange(lo, hi)  return lo + LcgRand() * (hi - lo)  end

-- ─────────────────────────────────────────────────────────────
--  瓦片局部坐标 → 世界坐标（同 vegetation.lua）
-- ─────────────────────────────────────────────────────────────
local function LocalToWorld(midX, midZ, heading, lx, lz)
    local rad = math.rad(heading)
    return midX + lx * math.cos(rad) + lz * math.sin(rad),
           midZ - lx * math.sin(rad) + lz * math.cos(rad)
end

-- ─────────────────────────────────────────────────────────────
--  材质缓存（按 r_g_b_roughness_metallic 键复用，避免重复创建）
-- ─────────────────────────────────────────────────────────────
local matCache = {}

local function GetMat(part)
    local c = part.color
    local key = string.format("%.3f_%.3f_%.3f_%.2f_%.2f",
        c[1], c[2], c[3], part.roughness, part.metallic)
    if matCache[key] then return matCache[key] end

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Vector4(c[1], c[2], c[3], 1.0)))
    mat:SetShaderParameter("Roughness",    Variant(part.roughness))
    mat:SetShaderParameter("Metallic",     Variant(part.metallic))
    matCache[key] = mat
    return mat
end

-- ─────────────────────────────────────────────────────────────
--  放置单栋建筑
--  def:    building type table (from JSON)
--  height: 随机化后的实际高度
--  wx, wz: 世界坐标（建筑底面中心）
--  rotY:   旋转（度），0 = 对齐世界轴
-- ─────────────────────────────────────────────────────────────
local function SpawnBuilding(def, height, wx, wz, rotY)
    local root = S.mainScene:CreateChild("Bldg")
    root:SetPosition(Vector3(wx, GROUND_Y, wz))
    root:SetRotation(Quaternion(0, rotY, 0))

    for _, part in ipairs(def.parts) do
        local partH = (part.yTop - part.yBottom) * height
        local partW = def.spanX * part.xScale    -- X 轴（垂直赛道，深度方向）
        local partD = def.spanZ * part.zScale    -- Z 轴（沿赛道，宽度方向）
        local partCY = (part.yBottom + part.yTop) * 0.5 * height

        local pn = root:CreateChild("Part")
        pn:SetPosition(Vector3(0, partCY, 0))
        pn:SetScale(Vector3(partW, partH, partD))
        local sm = pn:CreateComponent("StaticModel")
        sm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        sm:SetMaterial(GetMat(part))
    end
end

-- ─────────────────────────────────────────────────────────────
--  配置加载
-- ─────────────────────────────────────────────────────────────
---@type table|nil
local config = nil

local function LoadConfig()
    local ok, cfg = pcall(function() return require "buildings_config" end)
    if not ok or not cfg then
        U.LogInfo("[Buildings] 无法加载 buildings_config: " .. tostring(cfg))
        return false
    end

    -- 预热材质缓存
    for _, def in pairs(cfg.types) do
        for _, part in ipairs(def.parts) do
            GetMat(part)
        end
    end

    config = cfg
    local n = 0
    for _ in pairs(cfg.types) do n = n + 1 end
    U.LogInfo("[Buildings] 配置加载成功，共 " .. n .. " 种建筑")
    return true
end

-- ─────────────────────────────────────────────────────────────
--  在某一侧（xSign: -1 左 / +1 右）生成该瓦片的建筑
--
--  布局策略：
--    短楼行  ── 每块瓦片 1 栋（形成紧密欧式街墙）
--    高楼行1 ── 每 2 块瓦片 1 栋（密集高层）
--    高楼行2 ── 每 3 块瓦片 1 栋（后排更高，略疏）
-- ─────────────────────────────────────────────────────────────
local function SpawnForSide(tileIdx, xSign, n)
    local heading = n.heading
    local midX    = n.midX
    local midZ    = n.midZ

    local shortDef = config.types["european_house"]
    local tallDef  = config.types["glass_tower"]

    -- ── 短楼（欧式，每瓦片 1 栋）──────────────────────────────
    LcgSeed(tileIdx * 193 + xSign * 97 + 7)
    local lz1  = RandRange(-C.TILE_LEN * 0.44, C.TILE_LEN * 0.44)
    local h1   = RandRange(shortDef.heightMin, shortDef.heightMax)
    local offX1 = RandRange(-1.5, 1.5)   -- 行内轻微随机偏移，避免机械感
    local lx1  = xSign * (SHORT_ROW_X + offX1)
    local wx1, wz1 = LocalToWorld(midX, midZ, heading, lx1, lz1)
    -- 建筑旋转对齐赛道方向，轻微随机扰动（±8°）
    SpawnBuilding(shortDef, h1, wx1, wz1, heading + RandRange(-8, 8))

    -- ── 高楼第一行（每 2 块瓦片 1 栋）──────────────────────────
    if tileIdx % 2 == 0 then
        LcgSeed(tileIdx * 251 + xSign * 131 + 13)
        local lz2  = RandRange(-C.TILE_LEN * 0.45, C.TILE_LEN * 0.45)
        local h2   = RandRange(tallDef.heightMin, tallDef.heightMax)
        local offX2 = RandRange(-2.0, 2.0)
        local lx2  = xSign * (TALL_ROW1_X + offX2)
        local wx2, wz2 = LocalToWorld(midX, midZ, heading, lx2, lz2)
        SpawnBuilding(tallDef, h2, wx2, wz2, heading + RandRange(-5, 5))
    end

    -- ── 高楼第二行（每 3 块瓦片 1 栋，高度更高）────────────────
    if tileIdx % 3 == 0 then
        LcgSeed(tileIdx * 337 + xSign * 167 + 19)
        local lz3  = RandRange(-C.TILE_LEN * 0.45, C.TILE_LEN * 0.45)
        -- 第二行比第一行更高（模拟远处超高层）
        local h3   = RandRange(tallDef.heightMin + 15, tallDef.heightMax + 25)
        local offX3 = RandRange(-3.0, 3.0)
        local lx3  = xSign * (TALL_ROW2_X + offX3)
        local wx3, wz3 = LocalToWorld(midX, midZ, heading, lx3, lz3)
        SpawnBuilding(tallDef, h3, wx3, wz3, heading + RandRange(-5, 5))
    end
end

-- ─────────────────────────────────────────────────────────────
--  公共接口
-- ─────────────────────────────────────────────────────────────
function M.Init()
    if not LoadConfig() then
        U.LogInfo("[Buildings] 配置加载失败，跳过建筑生成")
        return
    end

    local path = S.trackPath
    if not path or #path == 0 then
        U.LogInfo("[Buildings] trackPath 为空，跳过建筑生成")
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

    U.LogInfo(string.format("[Buildings] 完成：%d 个瓦片建筑已生成", count))
end

return M
