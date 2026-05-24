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
--  流式加载参数
--  只保留玩家前方 STREAM_AHEAD 个瓦片、后方 STREAM_BEHIND 个瓦片的建筑
--  360 个瓦片中始终只有 ~70 个处于活跃状态（↓ ~81% 节点数）
-- ─────────────────────────────────────────────────────────────
local STREAM_AHEAD  = 55   -- 前方可见瓦片数（~550m）
local STREAM_BEHIND = 15   -- 后方保留瓦片数（~150m）

local tileRoots  = {}  -- [tileIdx] = { root, root, ... }  已生成建筑根节点
local frameCount = 0   -- 用于定期清理

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
---
--- 支持两种模式：
---   1. 默认（def.winZGroups 为 nil）：在整个 spanZ 宽度均匀布窗
---   2. 分区（def.winZGroups 为数组）：仅在指定 Z 范围内布窗
---      用于有镂空/门洞的建筑，跳过虚空区域
---      每个分组格式：{ zMin=<m>, zMax=<m> }（相对于建筑局部中心）
---
---@param root Node     建筑根节点
---@param def  table    建筑类型定义
---@param height number 实际建筑高度（m）
local function AddWindowsToFacade(root, def, height)
    if not def.addWindows then return end
    EnsureWinMats()

    local spanX      = def.spanX
    local yFracStart = def.winYStart or 0.13
    local yFracEnd   = def.winYEnd   or 0.76

    local yStart = height * yFracStart + WIN_H * 0.5
    local yEnd   = height * yFracEnd   - WIN_H * 0.5
    if yEnd < yStart then return end

    local nRows = math.max(1, math.floor((yEnd - yStart) / WIN_STEP_Y) + 1)
    local stepY = (nRows > 1) and ((yEnd - yStart) / (nRows - 1)) or 0

    -- 决定 Z 分区：有 winZGroups 则按分区，否则全宽单区
    local zGroups
    if def.winZGroups then
        zGroups = def.winZGroups
    else
        local margin = 0.9
        local half = def.spanZ * 0.5 - margin
        zGroups = {{ zMin = -half, zMax = half }}
    end

    for _, sx in ipairs({-1, 1}) do
        local faceX = sx * (spanX * 0.5)

        for _, zg in ipairs(zGroups) do
            local groupW = zg.zMax - zg.zMin
            if groupW < WIN_W then goto continue_group end

            local nCols = math.max(1, math.floor(groupW / WIN_STEP_Z))
            local stepZ = (nCols > 1) and ((groupW - WIN_W) / (nCols - 1)) or 0
            -- 窗格网格在分区内水平居中
            local startZ = (zg.zMin + zg.zMax) * 0.5 - (nCols - 1) * stepZ * 0.5

            for row = 0, nRows - 1 do
                local winY = yStart + row * stepY
                for col = 0, nCols - 1 do
                    local winZ = startZ + col * stepZ

                    -- 石材窗框（略大，凸出立面）
                    local fn = root:CreateChild("WF")
                    fn:SetPosition(Vector3(
                        faceX + sx * FRAME_THICK * 0.5,
                        winY, winZ))
                    fn:SetScale(Vector3(
                        FRAME_THICK,
                        WIN_H + WIN_BORDER * 2,
                        WIN_W + WIN_BORDER * 2))
                    local sm1 = fn:CreateComponent("StaticModel")
                    sm1:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                    sm1:SetMaterial(winFrameMat)
                    sm1:SetCastShadows(true)

                    -- 玻璃（深色薄板）
                    local gn = root:CreateChild("WG")
                    gn:SetPosition(Vector3(
                        faceX + sx * (FRAME_THICK + GLASS_THICK * 0.5),
                        winY, winZ))
                    gn:SetScale(Vector3(GLASS_THICK, WIN_H, WIN_W))
                    local sm2 = gn:CreateComponent("StaticModel")
                    sm2:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                    sm2:SetMaterial(winGlassMat)
                    sm2:SetCastShadows(true)
                end
            end
            ::continue_group::
        end
    end
end

-- ─────────────────────────────────────────────────────────────
--  幕墙常量（单位：米）
-- ─────────────────────────────────────────────────────────────
local CW_GLASS_D   = 0.05   -- 玻璃板厚度
local CW_BAND_H    = 0.40   -- 横向楼板带高度
local CW_BAND_D    = 0.14   -- 楼板带凸出玻璃面的深度
local CW_MULL_W    = 0.24   -- 竖挺宽度
local CW_MULL_D    = 0.08   -- 竖挺凸出玻璃面深度
local CW_FLOOR_H   = 3.4    -- 层高（m）
local CW_MULL_STEP = 2.6    -- 竖挺间距（m）

---@type Material|nil
local cwConcrMat  = nil

-- 7 种鲜艳幕墙玻璃调色板（高金属度 + 极低粗糙度，接近镜面反射）
local CW_GLASS_PALETTE = {
    { color = {0.04, 0.08, 0.22}, roughness = 0.04, metallic = 0.82 }, -- 深海蓝
    { color = {0.04, 0.20, 0.32}, roughness = 0.05, metallic = 0.78 }, -- 水鸭蓝
    { color = {0.04, 0.28, 0.18}, roughness = 0.05, metallic = 0.76 }, -- 翡翠绿
    { color = {0.26, 0.14, 0.04}, roughness = 0.06, metallic = 0.80 }, -- 铜棕金
    { color = {0.14, 0.06, 0.28}, roughness = 0.05, metallic = 0.78 }, -- 紫罗兰
    { color = {0.04, 0.16, 0.40}, roughness = 0.04, metallic = 0.82 }, -- 亮天蓝
    { color = {0.05, 0.24, 0.24}, roughness = 0.05, metallic = 0.76 }, -- 青碧
}

local function EnsureCwMats()
    if cwConcrMat then return end
    -- 浅暖灰混凝土格条（所有建筑共用）
    cwConcrMat = GetMat({ color = {0.72, 0.68, 0.60}, roughness = 0.82, metallic = 0.0 })
    -- 预热调色板所有材质
    for _, g in ipairs(CW_GLASS_PALETTE) do GetMat(g) end
end

--- 选取幕墙玻璃材质：优先用 def.glassColor；否则按建筑世界坐标确定性选调色板
local function PickCwGlassMat(def, wx, wz)
    if def.glassColor then
        return GetMat({ color = def.glassColor,
                        roughness = def.glassRoughness or 0.04,
                        metallic  = def.glassMetallic  or 0.80 })
    end
    -- 用坐标哈希保证相邻建筑颜色不同，且每次生成稳定
    local idx = (math.floor(math.abs(wx) * 7 + math.abs(wz) * 3)) % #CW_GLASS_PALETTE + 1
    return GetMat(CW_GLASS_PALETTE[idx])
end

--- 在建筑两侧立面（±X 面）上生成玻璃幕墙
---   · 整面大玻璃板（一个 Z 组一块）
---   · 每 CW_FLOOR_H 一道横向混凝土楼板带（凸出玻璃面）
---   · 每 CW_MULL_STEP 一道竖向混凝土竖挺（凸出玻璃面）
---
--- 触发条件：def.curtainWall = true
---
---@param root   Node
---@param def    table
---@param height number
---@param wx     number  建筑世界坐标 X（用于确定性选色）
---@param wz     number  建筑世界坐标 Z（用于确定性选色）
local function AddCurtainWallToFacade(root, def, height, wx, wz)
    if not def.curtainWall then return end
    EnsureCwMats()
    local glassMat = PickCwGlassMat(def, wx or 0, wz or 0)

    local spanX         = def.spanX
    local defYFracStart = def.winYStart or 0.03
    local defYFracEnd   = def.winYEnd   or 0.97

    -- 决定 Z 分区（每组可通过 yFracStart/yFracEnd 覆盖全局值）
    local zGroups
    if def.winZGroups then
        zGroups = def.winZGroups
    else
        local margin = 0.5
        local half = def.spanZ * 0.5 - margin
        zGroups = {{ zMin = -half, zMax = half }}
    end

    for _, sx in ipairs({-1, 1}) do
        local faceX = sx * (spanX * 0.5)   -- 立面 X 坐标（局部）

        for _, zg in ipairs(zGroups) do
            local groupW = zg.zMax - zg.zMin
            if groupW < 1.0 then goto cw_next_group end
            local groupCZ = (zg.zMin + zg.zMax) * 0.5

            -- 每组独立 Y 范围（优先用组内 yFracStart/yFracEnd）
            local yStart = height * (zg.yFracStart or defYFracStart)
            local yEnd   = height * (zg.yFracEnd   or defYFracEnd)
            local totalH = yEnd - yStart
            if totalH <= 0 then goto cw_next_group end
            local yCen = yStart + totalH * 0.5

            -- ① 整面玻璃板（thin box，与立面齐平）
            local gn = root:CreateChild("CwGlass")
            gn:SetPosition(Vector3(
                faceX + sx * CW_GLASS_D * 0.5,
                yCen,
                groupCZ))
            gn:SetScale(Vector3(CW_GLASS_D, totalH, groupW))
            local smg = gn:CreateComponent("StaticModel")
            smg:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            smg:SetMaterial(glassMat)
            smg:SetCastShadows(true)

            -- ② 横向楼板带（每层一道，凸出玻璃面）
            local nFloors = math.max(1, math.floor(totalH / CW_FLOOR_H))
            for f = 0, nFloors do
                local bandY = yStart + f * CW_FLOOR_H
                if bandY > yEnd + 0.01 then break end
                local bn = root:CreateChild("CwBand")
                bn:SetPosition(Vector3(
                    faceX + sx * (CW_GLASS_D + CW_BAND_D * 0.5),
                    bandY,
                    groupCZ))
                bn:SetScale(Vector3(CW_BAND_D, CW_BAND_H, groupW))
                local smb = bn:CreateComponent("StaticModel")
                smb:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                smb:SetMaterial(cwConcrMat)
                smb:SetCastShadows(true)
            end

            -- ③ 竖向竖挺（等间距，凸出玻璃面）
            local nMulls = math.max(0, math.floor(groupW / CW_MULL_STEP) - 1)
            if nMulls > 0 then
                local mullSpacing = groupW / (nMulls + 1)
                for m = 1, nMulls do
                    local mz = zg.zMin + m * mullSpacing
                    local mn = root:CreateChild("CwMull")
                    mn:SetPosition(Vector3(
                        faceX + sx * (CW_GLASS_D + CW_MULL_D * 0.5),
                        yCen,
                        mz))
                    mn:SetScale(Vector3(CW_MULL_D, totalH, CW_MULL_W))
                    local smm = mn:CreateComponent("StaticModel")
                    smm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
                    smm:SetMaterial(cwConcrMat)
                    smm:SetCastShadows(true)
                end
            end

            ::cw_next_group::
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
            sm:SetCastShadows(true)

        elseif model == "Cylinder" then
            -- Cylinder.mdl：直径1、高度1
            local diam = part.absSize or (def.spanX * (part.xScale or 1.0))
            pn:SetScale(Vector3(diam, partH, diam))
            local sm = pn:CreateComponent("StaticModel")
            sm:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
            sm:SetMaterial(mat)
            sm:SetCastShadows(true)

        else  -- Box（默认）
            local partW = def.spanX * (part.xScale or 1.0)
            local partD = def.spanZ * (part.zScale or 1.0)
            pn:SetScale(Vector3(partW, partH, partD))
            local sm = pn:CreateComponent("StaticModel")
            sm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            sm:SetMaterial(mat)
            sm:SetCastShadows(true)
        end
    end

    -- 生成立面装饰：幕墙 或 逐窗网格（二选一）
    if def.curtainWall then
        AddCurtainWallToFacade(root, def, height, wx, wz)
    else
        AddWindowsToFacade(root, def, height)
    end

    return root
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
--  每侧建筑生成（返回本次生成的所有根节点）
-- ─────────────────────────────────────────────────────────────
local function SpawnForSide(tileIdx, xSign, n)
    local heading = n.heading
    local midX    = n.midX
    local midZ    = n.midZ
    local roots   = {}   -- 收集本侧所有建筑根节点

    local shortDef  = config.types["european_house"]
    local tallDef   = config.types["glass_tower"]
    local palaceDef = config.types["baroque_palace"]
    local portalDef = config.types["portal_tower"]
    local ctfDef    = config.types["ctf_tower"]

    local tallPool = {}
    for _, k in ipairs({
        "glass_tower",    "glass_tower",
        "ivory_classic",  "ivory_classic",
        "concrete_office","concrete_office",
        "teal_glass",
        "dark_step",
    }) do
        local d = config.types[k]
        if d then tallPool[#tallPool + 1] = d end
    end
    local poolSize = #tallPool

    local function PickTall()
        local idx = math.floor(LcgRand() * poolSize) + 1
        return tallPool[math.max(1, math.min(poolSize, idx))]
    end

    -- ── 近岸矮楼行 ─────────────────────────────────────────────
    local shortInterval  = shortDef  and shortDef._interval  or 2
    local palaceInterval = palaceDef and palaceDef._interval or 5
    if tileIdx % shortInterval == 0 then
        LcgSeed(tileIdx * 193 + xSign * 97 + 7)
        local lz1   = RandRange(-1.5, 1.5)
        local offX1 = RandRange(-1.0, 1.0)
        local lx1   = xSign * (SHORT_ROW_X + offX1)
        local wx1, wz1 = LocalToWorld(midX, midZ, heading, lx1, lz1)

        if palaceDef and tileIdx % palaceInterval == 0 then
            roots[#roots+1] = SpawnBuilding(palaceDef, palaceDef.heightMin, wx1, wz1,
                heading + RandRange(-3, 3))
        else
            local h1 = RandRange(shortDef.heightMin, shortDef.heightMax)
            roots[#roots+1] = SpawnBuilding(shortDef, h1, wx1, wz1, heading + RandRange(-6, 6))
        end
    end

    -- ── 高楼第一行 ─────────────────────────────────────────────
    local tallInterval   = tallDef   and tallDef._interval         or 3
    local portalInterval = portalDef and (portalDef._interval * 3) or 24
    if tileIdx % tallInterval == 0 then
        LcgSeed(tileIdx * 251 + xSign * 131 + 13)
        local lz2   = RandRange(-2.0, 2.0)
        local offX2 = RandRange(-1.5, 1.5)
        local lx2   = xSign * (TALL_ROW1_X + offX2)
        local wx2, wz2 = LocalToWorld(midX, midZ, heading, lx2, lz2)

        if portalDef and tileIdx % portalInterval == 0 then
            roots[#roots+1] = SpawnBuilding(portalDef, portalDef.heightMin, wx2, wz2,
                heading + RandRange(-2, 2))
        else
            local picked2 = PickTall()
            local h2 = RandRange(picked2.heightMin, picked2.heightMax)
            roots[#roots+1] = SpawnBuilding(picked2, h2, wx2, wz2, heading + RandRange(-4, 4))
        end
    end

    -- ── 高楼第二行 ─────────────────────────────────────────────
    local tallOffset  = math.floor(tallInterval * 0.5)
    local ctfInterval = ctfDef and (ctfDef._interval * 5) or 20
    if (tileIdx + tallOffset) % tallInterval == 0 then
        LcgSeed(tileIdx * 337 + xSign * 167 + 19)
        local lz3   = RandRange(-2.0, 2.0)
        local offX3 = RandRange(-2.0, 2.0)
        local lx3   = xSign * (TALL_ROW2_X + offX3)
        local wx3, wz3 = LocalToWorld(midX, midZ, heading, lx3, lz3)

        if ctfDef and tileIdx % ctfInterval == 0 then
            local h3 = RandRange(ctfDef.heightMin, ctfDef.heightMax)
            roots[#roots+1] = SpawnBuilding(ctfDef, h3, wx3, wz3, heading + RandRange(-2, 2))
        else
            local picked3 = PickTall()
            local h3 = RandRange(picked3.heightMin + 12, picked3.heightMax + 22)
            roots[#roots+1] = SpawnBuilding(picked3, h3, wx3, wz3, heading + RandRange(-4, 4))
        end
    end

    return roots
end

-- ─────────────────────────────────────────────────────────────
--  单瓦片建筑生成 / 移除
-- ─────────────────────────────────────────────────────────────
local function SpawnTile(i)
    if tileRoots[i] then return end
    local path = S.trackPath
    if not path or not path[i] then return end
    local n = path[i]
    if not n.midX then return end

    local roots = {}
    for _, r in ipairs(SpawnForSide(i, -1, n)) do roots[#roots+1] = r end
    for _, r in ipairs(SpawnForSide(i,  1, n)) do roots[#roots+1] = r end
    tileRoots[i] = roots
end

local function RemoveTile(i)
    local roots = tileRoots[i]
    if not roots then return end
    for _, r in ipairs(roots) do
        r:Remove()
    end
    tileRoots[i] = nil
end

-- 判断瓦片 i 是否在 [curIdx-BEHIND, curIdx+AHEAD] 范围内
local function InRange(i, curIdx, loopN)
    local fwd = (i - curIdx + loopN) % loopN
    return fwd <= STREAM_AHEAD or fwd >= loopN - STREAM_BEHIND
end

-- ─────────────────────────────────────────────────────────────
--  公共接口
-- ─────────────────────────────────────────────────────────────
function M.Init()
    if not LoadConfig() then
        U.LogInfo("[Buildings] 配置加载失败，跳过建筑生成")
        return
    end
    U.LogInfo("[Buildings] 配置加载完毕，等待流式加载（Update 驱动）")
end

-- 每帧调用，curIdx / loopN 由 Track 提供
function M.Update(curIdx, loopN)
    if loopN == 0 or not config then return end

    -- 生成进入范围的瓦片
    for offset = -STREAM_BEHIND, STREAM_AHEAD do
        local i = (curIdx - 1 + offset + loopN) % loopN + 1
        if not tileRoots[i] then
            SpawnTile(i)
        end
    end

    -- 每 90 帧清理一次超出范围的瓦片（~1.5s @60fps）
    frameCount = frameCount + 1
    if frameCount % 90 == 0 then
        for i in pairs(tileRoots) do
            if not InRange(i, curIdx, loopN) then
                RemoveTile(i)
            end
        end
    end
end

-- 重置时清空所有已生成建筑（重开一局位置归零）
function M.Reset()
    for i in pairs(tileRoots) do
        RemoveTile(i)
    end
    tileRoots  = {}
    frameCount = 0
end

return M
