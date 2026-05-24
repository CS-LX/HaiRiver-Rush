-- ============================================================
--  bridges.lua  —  跨河桥梁系统（含天津之眼摩天轮地标）
--
--  桥梁横跨海河：从驳岸外缘 -D_OUTER 到 +D_OUTER（约 ±21m）
--  桥面高度与驳岸顶面平齐：WALL_H = 3.2m
--
--  内置模型尺寸（engine-docs/built-in-models.md）：
--    Box      1.0×1.0×1.0  → SetScale(sx,sy,sz) 直接等于米数
--    Sphere   1.0×1.0×1.0  → SetScale(d,d,d) 直接等于直径米数
--    Cylinder 1.0×1.0×1.0  → SetScale(d,h,d) 直接等于米数
--    Torus    1.2776×0.2555×1.2776 → 需补偿：scale = target/1.2776
--
--  普通拱桥：桥面板 + 12 段半圆拱 + 桥墩 + 栏杆 + 桥头灯柱
--
--  天津之眼（天津眼 Ferris Wheel Bridge）：
--    桥面同普通桥 + 桁架 + 摩天轮（Torus外圈 + Cylinder辐条 + Sphere轮毂 + 48个Box吊舱）
--    + Y 形支柱
-- ============================================================
local C = require "config"
local S = require "state"
local U = require "utils"

local M = {}

-- ─────────────────────────────────────────────────────────────
--  场景尺寸常量
-- ─────────────────────────────────────────────────────────────
local D_OUTER     = C.TRACK_WIDTH * 0.5 + C.WALL_W * 5  -- 21.0m（驳岸外缘）
local DECK_Y      = C.WALL_H                             -- 3.2m（桥面底高）
local BRIDGE_SPAN = D_OUTER * 2.0                        -- 42.0m（桥全跨）
local DECK_THICK  = 0.7
local DECK_BREAD  = 16.0                                 -- 桥面宽（沿赛道方向）
local DECK_W      = BRIDGE_SPAN + 2.0                    -- 44m（跨度含搭在驳岸上的部分）

-- Torus 原始宽度，用于缩放补偿
local TORUS_NATIVE_DIAM = 1.2776
local TORUS_NATIVE_H    = 0.2555

-- 天津之眼出现的瓦片索引
local TIANJIN_EYE_TILE  = 90
-- 普通桥间隔（每隔 N 个瓦片出现一座，跳过天津之眼周围 ±5 瓦片）
local BRIDGE_INTERVAL   = 60

-- ─────────────────────────────────────────────────────────────
--  材质缓存
-- ─────────────────────────────────────────────────────────────
local matCache = {}
local function GetMat(r, g, b, rough, metal)
    local key = string.format("%.3f_%.3f_%.3f_%.2f_%.2f", r, g, b, rough, metal)
    if matCache[key] then return matCache[key] end
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Vector4(r, g, b, 1.0)))
    mat:SetShaderParameter("Roughness",    Variant(rough))
    mat:SetShaderParameter("Metallic",     Variant(metal))
    matCache[key] = mat
    return mat
end

-- 预定义材质
local function StoneMat()    return GetMat(0.76, 0.74, 0.68, 0.86, 0.00) end -- 石灰岩桥体
local function WhiteMat()    return GetMat(0.92, 0.94, 0.96, 0.28, 0.50) end -- 白色钢结构
local function RoadMat()     return GetMat(0.52, 0.52, 0.50, 0.92, 0.00) end -- 路面
local function RailMat()     return GetMat(0.78, 0.76, 0.70, 0.62, 0.12) end -- 栏杆
local function LampPoleMat() return GetMat(0.28, 0.28, 0.32, 0.40, 0.72) end -- 灯柱
local function LampLightMat()return GetMat(1.00, 0.95, 0.70, 0.10, 0.00) end -- 灯头
local function HubMat()      return GetMat(0.88, 0.92, 0.96, 0.18, 0.76) end -- 轮毂银白
local function GondolaMat()  return GetMat(0.90, 0.12, 0.08, 0.40, 0.22) end -- 吊舱红色
local function SignMat()     return GetMat(0.92, 0.86, 0.62, 0.60, 0.10) end -- 牌匾

-- ─────────────────────────────────────────────────────────────
--  辅助：创建节点并附加 StaticModel
--  所有坐标均在 root（桥中心节点）的局部坐标系中
-- ─────────────────────────────────────────────────────────────
local function MkNode(parent, model, lx, ly, lz, sx, sy, sz, rx, ry, rz, mat)
    local nd = parent:CreateChild("BP")
    nd:SetPosition(Vector3(lx, ly, lz))
    nd:SetRotation(Quaternion(rx or 0, ry or 0, rz or 0))
    nd:SetScale(Vector3(sx, sy, sz))
    local sm = nd:CreateComponent("StaticModel")
    sm:SetModel(cache:GetResource("Model", "Models/" .. model .. ".mdl"))
    sm:SetMaterial(mat)
    sm:SetCastShadows(true)
end

-- 便捷包装
local function MkBox(p, lx,ly,lz, sx,sy,sz, ry, mat)
    MkNode(p, "Box", lx,ly,lz, sx,sy,sz, 0,ry or 0,0, mat)
end
local function MkCyl(p, lx,ly,lz, d,h, rx,ry,rz, mat)
    MkNode(p, "Cylinder", lx,ly,lz, d,h,d, rx or 0,ry or 0,rz or 0, mat)
end
local function MkSphere(p, lx,ly,lz, d, mat)
    MkNode(p, "Sphere", lx,ly,lz, d,d,d, 0,0,0, mat)
end

-- ─────────────────────────────────────────────────────────────
--  LocalToWorld
-- ─────────────────────────────────────────────────────────────
local function LocalToWorld(midX, midZ, heading, lx, lz)
    local rad = math.rad(heading)
    return midX + lx * math.cos(rad) + lz * math.sin(rad),
           midZ - lx * math.sin(rad) + lz * math.cos(rad)
end

-- ─────────────────────────────────────────────────────────────
--  共用：桥面板 + 栏杆 + 灯柱
--  root 的位置在桥中心，Y=0，旋转已含 heading
-- ─────────────────────────────────────────────────────────────
local function SpawnDeck(root, withLamps)
    local stMat  = StoneMat()
    local rdMat  = RoadMat()
    local rlMat  = RailMat()
    local lpMat  = LampPoleMat()
    local liMat  = LampLightMat()

    -- 桥面板（X 轴跨河，Z 轴为桥宽）
    MkBox(root, 0, DECK_Y + DECK_THICK * 0.5, 0,
          DECK_W, DECK_THICK, DECK_BREAD, 0, stMat)

    -- 路面薄层
    MkBox(root, 0, DECK_Y + DECK_THICK + 0.02, 0,
          DECK_W - 4.0, 0.05, DECK_BREAD - 2.0, 0, rdMat)

    -- 栏杆（两侧）
    local railTopY = DECK_Y + DECK_THICK + 1.1
    for _, rz in ipairs({ -DECK_BREAD * 0.5 + 0.55, DECK_BREAD * 0.5 - 0.55 }) do
        -- 扶手横条
        MkBox(root, 0, railTopY, rz,  DECK_W, 0.12, 0.12, 0, rlMat)
        -- 底部踢脚条
        MkBox(root, 0, DECK_Y + DECK_THICK + 0.15, rz,  DECK_W, 0.12, 0.12, 0, rlMat)
        -- 竖杆（间距 3m）
        local pN = math.floor(DECK_W / 3.0) + 1
        for pi = 0, pN - 1 do
            local px = -DECK_W * 0.5 + pi * 3.0
            if math.abs(px) <= DECK_W * 0.5 then
                MkBox(root, px, DECK_Y + DECK_THICK + 0.55, rz,
                      0.12, 1.1, 0.12, 0, rlMat)
            end
        end
    end

    -- 桥头灯柱（可选）
    if withLamps then
        for _, lx in ipairs({ -DECK_W * 0.5 + 1.2, DECK_W * 0.5 - 1.2 }) do
            for _, lz in ipairs({ -DECK_BREAD * 0.5 + 0.55, DECK_BREAD * 0.5 - 0.55 }) do
                MkCyl(root, lx, DECK_Y + DECK_THICK + 2.2, lz,
                      0.20, 4.2, 0, 0, 0, lpMat)
                MkSphere(root, lx, DECK_Y + DECK_THICK + 4.5, lz, 0.32, liMat)
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
--  普通拱桥
-- ─────────────────────────────────────────────────────────────
local function SpawnNormalBridge(wx, wz, heading)
    local root = S.mainScene:CreateChild("Bridge")
    root:SetPosition(Vector3(wx, 0, wz))
    root:SetRotation(Quaternion(0, heading, 0))

    local stMat = StoneMat()
    local wMat  = WhiteMat()

    -- 桥面 + 栏杆 + 灯柱
    SpawnDeck(root, true)

    -- ── 拱券（12 段 Cylinder 拼成半圆弧，位于桥面下方）──────────
    --   半圆圆心：X=0, Y = DECK_Y（桥面底高），拱从两侧驳岸起脚
    --   起脚点 X = ±archR，圆心 Y = DECK_Y，拱顶 Y = DECK_Y + archR
    --   但我们要在桥面 *下方* 做支撑拱，圆心在 DECK_Y 处，往上拱
    --   实际常见: 半圆拱下缘贴河面（Y≈0），拱顶刚好到桥面高度
    local archR   = BRIDGE_SPAN * 0.5        -- 21m（半圆半径）
    local archN   = 12
    local archD   = 2.4                      -- 拱断面直径
    local archDepth = DECK_BREAD * 0.5       -- 拱沿 Z 方向深度（穿透桥宽一半）

    for i = 0, archN - 1 do
        local a1  = math.pi * i       / archN   -- 0 → π
        local a2  = math.pi * (i + 1) / archN
        local aM  = (a1 + a2) * 0.5
        -- 圆心在 Y = DECK_Y - archR（即拱底，在Y=0附近，桥面减拱半径）
        -- 段中点：圆心 + r*（cos aM 在X, sin aM 在Y）
        -- 半圆从 0 到 π，cos(0)=1, cos(π)=-1，sin(0)=sin(π)=0，sin(π/2)=1
        -- X = archrR * cos(π - aM)  →  从 +archR 到 -archR
        local cx = archR * math.cos(math.pi - aM)
        local cy = (DECK_Y - archR) + archR * math.sin(aM)
        -- 段长
        local segLen = archR * (a2 - a1) * 1.06
        -- Cylinder 旋转：长轴（Y轴）沿弧线切线，切线方向 = aM + 90°
        -- 切线在 XY 平面：dx = -sin(π-aM) = sin(aM), dy = cos(π-aM) = -cos(aM)
        -- 需要绕 Z 轴旋转使 Y 轴对准切线：角度 = atan2(-cos(aM), sin(aM)) → in deg
        local tiltRad = math.atan(-math.cos(aM), math.sin(aM))
        local tiltDeg = math.deg(tiltRad)
        MkNode(root, "Cylinder",
               cx, cy, 0,
               archD, segLen, archDepth,
               0, 0, tiltDeg,
               stMat)
    end

    -- 桥墩（四根，±9m 处，从 Y=0 到桥面底）
    local pierH = DECK_Y
    for _, px in ipairs({ -9.0, 9.0 }) do
        for _, pz in ipairs({ -DECK_BREAD * 0.32, DECK_BREAD * 0.32 }) do
            MkBox(root, px, pierH * 0.5, pz,
                  2.2, pierH, 2.2, 0, stMat)
        end
    end

    -- 装饰：桥头端墙（两端各一道）
    for _, ex in ipairs({ -DECK_W * 0.5 + 0.5, DECK_W * 0.5 - 0.5 }) do
        MkBox(root, ex, DECK_Y + DECK_THICK + 1.8, 0,
              0.6, 3.4, DECK_BREAD, 0, stMat)
    end

    U.LogInfo(string.format("[Bridges] 普通桥 @ (%.1f, %.1f) h=%.0f°", wx, wz, heading))
end

-- ─────────────────────────────────────────────────────────────
--  天津之眼摩天轮桥
-- ─────────────────────────────────────────────────────────────
local function SpawnTianjinEye(wx, wz, heading)
    local root = S.mainScene:CreateChild("TianjinEye")
    root:SetPosition(Vector3(wx, 0, wz))
    root:SetRotation(Quaternion(0, heading, 0))

    local stMat = StoneMat()
    local wMat  = WhiteMat()
    local rlMat = RailMat()

    -- ── 桥面 + 栏杆（无灯柱，摩天轮自带）───────────────────────
    SpawnDeck(root, false)

    -- ── 桁架下弦梁（3 根纵梁）────────────────────────────────
    for _, tz in ipairs({ -DECK_BREAD * 0.36, 0, DECK_BREAD * 0.36 }) do
        MkBox(root, 0, DECK_Y - 1.4, tz,
              DECK_W, 0.6, 0.5, 0, wMat)
    end
    -- 桁架斜撑
    local diagSpan = DECK_W / 11.0
    for i = 0, 10 do
        local fx = -DECK_W * 0.5 + (i + 0.5) * diagSpan
        for _, tz in ipairs({ -DECK_BREAD * 0.36, DECK_BREAD * 0.36 }) do
            MkBox(root, fx, DECK_Y - 0.7, tz, 0.28, 1.6, 0.28, 0, wMat)
        end
    end

    -- 桥墩（四根）
    local pierH = DECK_Y
    for _, px in ipairs({ -10.0, 10.0 }) do
        for _, pz in ipairs({ -DECK_BREAD * 0.36, DECK_BREAD * 0.36 }) do
            MkBox(root, px, pierH * 0.5, pz, 2.4, pierH, 2.4, 0, stMat)
        end
    end

    -- ── 摩天轮 ────────────────────────────────────────────────
    --   轮轴位于桥中心正上方
    --   摩天轮直径 55m（半径 27.5m）
    local wheelR = 27.5
    -- 轮轴 Y 高度 = 桥面顶 + 轮半径 + 小间隙（让最低吊舱离桥面约 2m）
    local wheelY = DECK_Y + DECK_THICK + wheelR + 2.4

    -- 外轮圈（Torus竖立）
    -- Torus 原始 bounding box: 1.2776 × 0.2555 × 1.2776
    -- 我们想要：外径 = wheelR*2 = 55m，管径 ≈ 1.8m
    -- scale.x（横向）= 目标外径 / 1.2776
    -- scale.y（高度）= 目标管径 / 0.2555
    -- 竖立 Torus：绕 X 轴旋转 90°（原本躺平，变成竖圆）
    local rimDiam = wheelR * 2.0
    local tubeDiam = 1.8
    local torusScaleXZ = rimDiam / TORUS_NATIVE_DIAM         -- ≈ 43.05
    local torusScaleY  = tubeDiam / TORUS_NATIVE_H            -- ≈ 7.05
    local rimNd = root:CreateChild("WheelRim")
    rimNd:SetPosition(Vector3(0, wheelY, 0))
    rimNd:SetRotation(Quaternion(90, 0, 0))  -- 竖立
    rimNd:SetScale(Vector3(torusScaleXZ, torusScaleY, torusScaleXZ))
    local rimSM = rimNd:CreateComponent("StaticModel")
    rimSM:SetModel(cache:GetResource("Model", "Models/Torus.mdl"))
    rimSM:SetMaterial(wMat)
    rimSM:SetCastShadows(true)

    -- 内加强圈（略小一号）
    local innerDiam  = wheelR * 1.62
    local iScaleXZ   = innerDiam / TORUS_NATIVE_DIAM
    local iScaleY    = 1.2 / TORUS_NATIVE_H
    local innerNd = root:CreateChild("WheelInner")
    innerNd:SetPosition(Vector3(0, wheelY, 0))
    innerNd:SetRotation(Quaternion(90, 0, 0))
    innerNd:SetScale(Vector3(iScaleXZ, iScaleY, iScaleXZ))
    local innerSM = innerNd:CreateComponent("StaticModel")
    innerSM:SetModel(cache:GetResource("Model", "Models/Torus.mdl"))
    innerSM:SetMaterial(wMat)
    innerSM:SetCastShadows(true)

    -- 轮毂（中心大 Sphere）
    MkSphere(root, 0, wheelY, 0, 3.2, HubMat())

    -- 辐条：24 根（从轮毂边缘到外圈内表面，Cylinder Y轴=径向方向）
    local spokeN    = 24
    local spokeD    = 0.38     -- 辐条直径
    local spLen     = wheelR - 1.6 - 0.9   -- 有效辐条长度（轮毂外 ~ 外圈内）
    local spMidR    = 1.6 + spLen * 0.5    -- 辐条中点到轮轴的距离
    for i = 1, spokeN do
        local ang    = (i / spokeN) * math.pi * 2.0
        local spX    = math.cos(ang) * spMidR
        local spY    = wheelY + math.sin(ang) * spMidR
        -- Cylinder Y 轴需对准辐条方向（即从圆心射出的径向方向）
        -- 径向方向在 XY 平面：(cos ang, sin ang, 0)
        -- 将 Cylinder Y 轴 (0,1,0) 旋转到 (cos ang, sin ang, 0)
        -- 绕 Z 轴旋转 ang 度（注意 ang 单位为弧度）
        local angDeg = math.deg(ang)
        MkNode(root, "Cylinder",
               spX, spY, 0,
               spokeD, spLen, spokeD,
               0, 0, angDeg,
               wMat)
    end

    -- 吊舱：48 个红色小 Box 均匀分布在外轮圈外侧
    local gondolaN  = 48
    local gondolaW, gondolaH, gondolaD = 1.4, 1.4, 1.0
    local gondolaR  = wheelR + 0.5   -- 吊舱中心到轮轴距离（略超出外圈）
    for i = 1, gondolaN do
        local ang = (i / gondolaN) * math.pi * 2.0
        local gx  = math.cos(ang) * gondolaR
        local gy  = wheelY + math.sin(ang) * gondolaR
        MkBox(root, gx, gy, 0,
              gondolaW, gondolaH, gondolaD, 0, GondolaMat())
    end

    -- ── Y 形支柱（桥面两侧各一个，向上撑住轮轴）─────────────────
    -- 支柱底座：从桥面往上一根主干，顶部叉成两根斜臂
    -- 实际天津之眼：支柱在桥面正中，两侧延伸（Z方向）
    local trunkTopY = DECK_Y + DECK_THICK + wheelY * 0.55  -- 主干顶部高度

    for _, side in ipairs({ -1, 1 }) do
        local pz = side * (DECK_BREAD * 0.5 + 1.5)  -- 支柱 Z 位置（外侧）

        -- 主干
        local trunkH = trunkTopY - (DECK_Y + DECK_THICK)
        MkBox(root, 0, DECK_Y + DECK_THICK + trunkH * 0.5, pz,
              2.0, trunkH, 2.0, 0, wMat)

        -- 两根叉臂（向左右斜上方，各倾斜约 22°）
        local forkLen  = (wheelY - trunkTopY) * 1.18
        local forkTilt = 22.0   -- 偏离竖直的角度
        local forkMidY = trunkTopY + forkLen * 0.5 * math.cos(math.rad(forkTilt))
        local forkMidX = math.sin(math.rad(forkTilt)) * forkLen * 0.5

        -- 左叉（X 负方向）
        MkNode(root, "Box",
               -forkMidX, forkMidY, pz,
               1.4, forkLen, 1.4,
               0, 0, -forkTilt,    -- 绕 Z 轴倾斜
               wMat)
        -- 右叉（X 正方向）
        MkNode(root, "Box",
               forkMidX, forkMidY, pz,
               1.4, forkLen, 1.4,
               0, 0, forkTilt,
               wMat)
    end

    -- ── 桥头端塔（两端各一座方形塔）───────────────────────────
    for _, ex in ipairs({ -DECK_W * 0.5 + 1.5, DECK_W * 0.5 - 1.5 }) do
        -- 塔身
        MkBox(root, ex, DECK_Y + DECK_THICK + 5.0, 0,
              3.2, 9.8, DECK_BREAD, 0, stMat)
        -- 牌匾
        MkBox(root, ex, DECK_Y + DECK_THICK + 7.0, -DECK_BREAD * 0.5 - 0.1,
              2.8, 2.0, 0.2, 0, SignMat())
    end

    U.LogInfo(string.format("[Bridges] 天津之眼 @ (%.1f, %.1f) h=%.0f°", wx, wz, heading))
end

-- ─────────────────────────────────────────────────────────────
--  公共接口
-- ─────────────────────────────────────────────────────────────
function M.Init()
    local path = S.trackPath
    if not path or #path == 0 then
        U.LogInfo("[Bridges] trackPath 为空，跳过桥梁生成")
        return
    end

    local cnt = 0
    for i = 1, #path do
        local n = path[i]
        if not (n.midX and n.midZ) then goto continue end

        if i == TIANJIN_EYE_TILE then
            SpawnTianjinEye(n.midX, n.midZ, n.heading)
            cnt = cnt + 1
        elseif (i % BRIDGE_INTERVAL == 0)
           and math.abs(i - TIANJIN_EYE_TILE) >= 6 then
            SpawnNormalBridge(n.midX, n.midZ, n.heading)
            cnt = cnt + 1
        end

        ::continue::
    end

    U.LogInfo(string.format("[Bridges] 完成：共生成 %d 座桥（含天津之眼1座）", cnt))
end

return M
