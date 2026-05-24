-- ============================================================
--  buildings.lua  —  沿岸建筑生成系统
--
--  支持的 part 字段：
--    model      "Box"(默认) | "Sphere" | "Cylinder" | "Hemisphere"
--    yBottom    高度比例下界 [0,1]
--    yTop       高度比例上界 [0,1]
--    xScale     spanX 的缩放倍数（>1 = 挑出）
--    zScale     spanZ 的缩放倍数（>1 = 挑出）
--    offsetZ    沿赛道方向的绝对偏移（m），用于分段屋顶/侧翼穹顶
--    offsetX    垂直赛道方向偏移（m），通常为 0
--    absSize    绝对直径/宽度（m），覆盖 xScale/zScale（Hemisphere/Sphere 用）
--    color      { r, g, b }
--    roughness  粗糙度 [0,1]
--    metallic   金属度 [0,1]
-- ============================================================
local C = require "config"
local S = require "state"
local U = require "utils"

local M = {}

-- ─────────────────────────────────────────────────────────────
--  距离常量
-- ─────────────────────────────────────────────────────────────
local GRASS_X1    = C.TRACK_WIDTH * 0.5 + C.WALL_W * 5 + 13.0  -- 34m
local GROUND_Y    = C.WALL_H
local SHORT_ROW_X = 41.0
local TALL_ROW1_X = 62.0
local TALL_ROW2_X = 87.0

-- ─────────────────────────────────────────────────────────────
--  确定性 LCG
-- ─────────────────────────────────────────────────────────────
local lcgState = 0
local function LcgSeed(s)  lcgState = s & 0x7FFFFFFF  end
local function LcgRand()
    lcgState = (lcgState * 1664525 + 1013904223) & 0x7FFFFFFF
    return lcgState / 0x7FFFFFFF
end
local function RandRange(lo, hi)  return lo + LcgRand() * (hi - lo)  end

-- ─────────────────────────────────────────────────────────────
--  坐标变换
-- ─────────────────────────────────────────────────────────────
local function LocalToWorld(midX, midZ, heading, lx, lz)
    local rad = math.rad(heading)
    return midX + lx * math.cos(rad) + lz * math.sin(rad),
           midZ - lx * math.sin(rad) + lz * math.cos(rad)
end

-- ─────────────────────────────────────────────────────────────
--  材质缓存
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
--  CustomGeometry 半球（上半球，正面朝外）
--  radius: 半径（m）  segments: 分段数（建议 20）
-- ─────────────────────────────────────────────────────────────
local function BuildHemisphere(node, radius, segments, mat)
    local rings = math.floor(segments * 0.5)
    local geom  = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    -- 生成顶点网格（上半球 phi: 0→π/2，0=顶点，π/2=赤道）
    local verts = {}
    for ring = 0, rings do
        local phi = (ring / rings) * (math.pi * 0.5)
        local row = {}
        for seg = 0, segments do
            local theta = (seg / segments) * math.pi * 2.0
            local x = radius * math.sin(phi) * math.cos(theta)
            local y = radius * math.cos(phi)
            local z = radius * math.sin(phi) * math.sin(theta)
            row[seg] = { x = x, y = y, z = z, nx = x/radius, ny = y/radius, nz = z/radius }
        end
        verts[ring] = row
    end

    -- 生成三角形（逆时针 = 正面朝外）
    for ring = 0, rings - 1 do
        for seg = 0, segments - 1 do
            local v00 = verts[ring][seg]
            local v01 = verts[ring][seg+1]
            local v10 = verts[ring+1][seg]
            local v11 = verts[ring+1][seg+1]

            -- 三角形 1
            geom:DefineVertex(Vector3(v00.x, v00.y, v00.z))
            geom:DefineNormal(Vector3(v00.nx, v00.ny, v00.nz))
            geom:DefineTexCoord(Vector2(seg/segments, ring/rings))

            geom:DefineVertex(Vector3(v10.x, v10.y, v10.z))
            geom:DefineNormal(Vector3(v10.nx, v10.ny, v10.nz))
            geom:DefineTexCoord(Vector2(seg/segments, (ring+1)/rings))

            geom:DefineVertex(Vector3(v01.x, v01.y, v01.z))
            geom:DefineNormal(Vector3(v01.nx, v01.ny, v01.nz))
            geom:DefineTexCoord(Vector2((seg+1)/segments, ring/rings))

            -- 三角形 2
            geom:DefineVertex(Vector3(v01.x, v01.y, v01.z))
            geom:DefineNormal(Vector3(v01.nx, v01.ny, v01.nz))
            geom:DefineTexCoord(Vector2((seg+1)/segments, ring/rings))

            geom:DefineVertex(Vector3(v10.x, v10.y, v10.z))
            geom:DefineNormal(Vector3(v10.nx, v10.ny, v10.nz))
            geom:DefineTexCoord(Vector2(seg/segments, (ring+1)/rings))

            geom:DefineVertex(Vector3(v11.x, v11.y, v11.z))
            geom:DefineNormal(Vector3(v11.nx, v11.ny, v11.nz))
            geom:DefineTexCoord(Vector2((seg+1)/segments, (ring+1)/rings))
        end
    end

    geom:Commit()
    geom:SetMaterial(mat)
    return geom
end

-- ─────────────────────────────────────────────────────────────
--  程序化窗户生成
--  在建筑局部坐标系中，±X 面是正/背立面（朝/背河道），
--  Z 方向是沿赛道宽度方向。
--  每扇窗由两个 Box 叠成：石材窗框（略大，微凸出）+ 玻璃（深色，薄）
-- ─────────────────────────────────────────────────────────────
local WIN_STEP_Z   = 3.0    -- 列间距（中心到中心，m）
local WIN_STEP_Y   = 3.2    -- 行间距（m）
local WIN_W        = 1.05   -- 玻璃宽（m，沿 Z 轴）
local WIN_H        = 1.65   -- 玻璃高（m）
local WIN_BORDER   = 0.20   -- 石材窗框比玻璃各边宽出量（m）
local FRAME_THICK  = 0.18   -- 窗框凸出厚度（m）
local GLASS_THICK  = 0.06   -- 玻璃厚度（m）

---@type Material|nil
local winGlassMat = nil
---@type Material|nil
local winFrameMat = nil

local function EnsureWinMats()
    if winGlassMat then return end
    -- 深蓝灰玻璃（微金属感，反射室内暗色）
    winGlassMat = GetMat({ color = {0.14, 0.18, 0.28}, roughness = 0.12, metallic = 0.45 })
    -- 石材窗框（与主体立面同色系，略深）
    winFrameMat = GetMat({ color = {0.76, 0.70, 0.56}, roughness = 0.80, metallic = 0.0  })
end

--- 在建筑两侧立面（±X 面）上生成窗户网格
---@param root Node     建筑根节点
---@param def  table    建筑类型定义
---@param height number 实际建筑高度（m）
local function AddWindowsToFacade(root, def, height)
    if not def.addWindows then return end
    EnsureWinMats()

    local spanX      = def.spanX
    local spanZ      = def.spanZ
    local yFracStart = def.winYStart or 0.13   -- 首行窗户起始高度比例
    local yFracEnd   = def.winYEnd   or 0.76   -- 末行窗户终止高度比例

    -- 行范围（窗户中心 Y 坐标）
    local yStart = height * yFracStart + WIN_H * 0.5
    local yEnd   = height * yFracEnd   - WIN_H * 0.5
    if yEnd < yStart then return end

    -- 列数：在 spanZ 去掉两端边距后均匀分布
    local margin = 0.9
    local availZ = spanZ - margin * 2
    if availZ <= 0 then return end
    local nCols = math.max(1, math.floor(availZ / WIN_STEP_Z))
    local stepZ  = (nCols > 1) and (availZ / (nCols - 1)) or 0
    local startZ = -(availZ * 0.5)

    -- 行数
    local nRows = math.max(1, math.floor((yEnd - yStart) / WIN_STEP_Y) + 1)
    local stepY  = (nRows > 1) and ((yEnd - yStart) / (nRows - 1)) or 0

    -- 在 ±X 两个立面上各生成一套窗户
    for _, sx in ipairs({-1, 1}) do
        local faceX = sx * (spanX * 0.5)   -- 面所在 X 平面

        for row = 0, nRows - 1 do
            local winY = yStart + row * stepY
            for col = 0, nCols - 1 do
                local winZ = startZ + col * stepZ

                -- 石材窗框（略大，凸出立面）
                local fn = root:CreateChild("WF")
                fn:SetPosition(Vector3(
                    faceX + sx * FRAME_THICK * 0.5,
                    winY,
                    winZ))
                fn:SetScale(Vector3(
                    FRAME_THICK,
                    WIN_H + WIN_BORDER * 2,
                    WIN_W + WIN_BORDER * 2))
                local sm1 = fn:CreateComponent("StaticModel")
                sm1:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                sm1:SetMaterial(winFrameMat)

                -- 玻璃（深色薄板，略超出框面）
                local gn = root:CreateChild("WG")
                gn:SetPosition(Vector3(
                    faceX + sx * (FRAME_THICK + GLASS_THICK * 0.5),
                    winY,
                    winZ))
                gn:SetScale(Vector3(
                    GLASS_THICK,
                    WIN_H,
                    WIN_W))
                local sm2 = gn:CreateComponent("StaticModel")
                sm2:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                sm2:SetMaterial(winGlassMat)
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
--  放置单栋建筑（支持多模型 + 偏移 + 半球穹顶）
-- ─────────────────────────────────────────────────────────────
local function SpawnBuilding(def, height, wx, wz, rotY)
    local root = S.mainScene:CreateChild("Bldg")
    root:SetPosition(Vector3(wx, GROUND_Y, wz))
    root:SetRotation(Quaternion(0, rotY, 0))

    for _, part in ipairs(def.parts) do
        local model   = part.model or "Box"
        local partH   = (part.yTop - part.yBottom) * height
        local partCY  = (part.yBottom + part.yTop) * 0.5 * height
        local offX    = part.offsetX or 0.0
        local offZ    = part.offsetZ or 0.0
        local mat     = GetMat(part)

        local pn = root:CreateChild("Part")
        pn:SetPosition(Vector3(offX, partCY, offZ))

        if model == "Hemisphere" then
            -- 半球：absSize 为直径，底部朝下（穹顶顶端朝上）
            local diam   = part.absSize or partH
            local radius = diam * 0.5
            -- 半球底圆在 partCY - partH/2，穹顶顶端在 partCY + radius
            -- 节点原点在底圆中心
            pn:SetPosition(Vector3(offX, part.yBottom * height, offZ))
            BuildHemisphere(pn, radius, 24, mat)

        elseif model == "Sphere" then
            local diam = part.absSize or partH
            pn:SetScale(Vector3(diam, diam, diam))
            local sm = pn:CreateComponent("StaticModel")
            sm:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
            sm:SetMaterial(mat)

        elseif model == "Cylinder" then
            -- Cylinder.mdl：直径1、高度1
            local diam = part.absSize or (def.spanX * (part.xScale or 1.0))
            pn:SetScale(Vector3(diam, partH, diam))
            local sm = pn:CreateComponent("StaticModel")
            sm:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
            sm:SetMaterial(mat)

        else  -- Box（默认）
            local partW = def.spanX * (part.xScale or 1.0)
            local partD = def.spanZ * (part.zScale or 1.0)
            pn:SetScale(Vector3(partW, partH, partD))
            local sm = pn:CreateComponent("StaticModel")
            sm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            sm:SetMaterial(mat)
        end
    end

    -- 生成窗户（仅对配置了 addWindows=true 的建筑）
    AddWindowsToFacade(root, def, height)
end

-- ─────────────────────────────────────────────────────────────
--  配置加载
-- ─────────────────────────────────────────────────────────────
---@type table|nil
local config = nil

-- 根据 spanZ 计算最小不重叠瓦片间隔
--   interval = ceil(spanZ / TILE_LEN) + GAP_TILES
--   GAP_TILES：短楼保留 1 瓦片（10m）间隙，高楼保留 2 瓦片（20m）间隙
local function CalcInterval(def)
    local TILE_LEN = C.TILE_LEN   -- 10m
    local gap = (def.tier == "tall") and 2 or 1
    return math.max(1, math.ceil(def.spanZ / TILE_LEN) + gap)
end

local function LoadConfig()
    local ok, cfg = pcall(function() return require "buildings_config" end)
    if not ok or not cfg then
        U.LogInfo("[Buildings] 无法加载 buildings_config: " .. tostring(cfg))
        return false
    end
    for _, def in pairs(cfg.types) do
        for _, part in ipairs(def.parts) do GetMat(part) end
        -- 预计算生成间隔（瓦片数），存入 def 供 SpawnForSide 使用
        def._interval = CalcInterval(def)
        U.LogInfo(string.format("[Buildings] %s: spanZ=%.0fm  interval=%d tiles (%.0fm)",
            def.tier or "?", def.spanZ, def._interval, def._interval * C.TILE_LEN))
    end
    config = cfg
    local n = 0
    for _ in pairs(cfg.types) do n = n + 1 end
    U.LogInfo("[Buildings] 配置加载成功，共 " .. n .. " 种建筑")
    return true
end

-- ─────────────────────────────────────────────────────────────
--  每侧建筑生成
-- ─────────────────────────────────────────────────────────────
local function SpawnForSide(tileIdx, xSign, n)
    local heading = n.heading
    local midX    = n.midX
    local midZ    = n.midZ

    local shortDef  = config.types["european_house"]
    local tallDef   = config.types["glass_tower"]
    local palaceDef = config.types["baroque_palace"]

    -- ── 近岸矮楼行 ─────────────────────────────────────────────
    -- 生成间隔由 spanZ 自动计算（europena_house._interval）
    -- baroque_palace 的间隔同样由其 spanZ 计算，叠加在矮楼行里出现
    local shortInterval  = shortDef  and shortDef._interval  or 2
    local palaceInterval = palaceDef and palaceDef._interval or 5
    if tileIdx % shortInterval == 0 then
        LcgSeed(tileIdx * 193 + xSign * 97 + 7)
        local lz1   = RandRange(-1.5, 1.5)
        local offX1 = RandRange(-1.0, 1.0)
        local lx1   = xSign * (SHORT_ROW_X + offX1)
        local wx1, wz1 = LocalToWorld(midX, midZ, heading, lx1, lz1)

        if palaceDef and tileIdx % palaceInterval == 0 then
            -- 地标建筑：宫殿（自身间隔保证不重叠）
            SpawnBuilding(palaceDef, palaceDef.heightMin, wx1, wz1,
                heading + RandRange(-3, 3))
        else
            local h1 = RandRange(shortDef.heightMin, shortDef.heightMax)
            SpawnBuilding(shortDef, h1, wx1, wz1, heading + RandRange(-6, 6))
        end
    end

    -- ── 高楼第一行 ─────────────────────────────────────────────
    -- 间隔由 spanZ 自动计算（glass_tower._interval）
    local tallInterval = tallDef and tallDef._interval or 3
    if tileIdx % tallInterval == 0 then
        LcgSeed(tileIdx * 251 + xSign * 131 + 13)
        local lz2   = RandRange(-2.0, 2.0)
        local h2    = RandRange(tallDef.heightMin, tallDef.heightMax)
        local offX2 = RandRange(-1.5, 1.5)
        local lx2   = xSign * (TALL_ROW1_X + offX2)
        local wx2, wz2 = LocalToWorld(midX, midZ, heading, lx2, lz2)
        SpawnBuilding(tallDef, h2, wx2, wz2, heading + RandRange(-4, 4))
    end

    -- ── 高楼第二行（错开半个间隔，避免与第一行对齐）──────────────
    -- 偏移 floor(tallInterval/2) 瓦片，让两行高楼交错排列
    local tallOffset = math.floor(tallInterval * 0.5)
    if (tileIdx + tallOffset) % tallInterval == 0 then
        LcgSeed(tileIdx * 337 + xSign * 167 + 19)
        local lz3   = RandRange(-2.0, 2.0)
        local h3    = RandRange(tallDef.heightMin + 15, tallDef.heightMax + 25)
        local offX3 = RandRange(-2.0, 2.0)
        local lx3   = xSign * (TALL_ROW2_X + offX3)
        local wx3, wz3 = LocalToWorld(midX, midZ, heading, lx3, lz3)
        SpawnBuilding(tallDef, h3, wx3, wz3, heading + RandRange(-4, 4))
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
