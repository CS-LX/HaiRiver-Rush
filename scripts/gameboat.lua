-- ============================================================
--  gameboat.lua  —  游船障碍物（海河游轮外观）
--
--  外观参考：白色大型内河游览船
--    · 白色平底宽体船壳，船头尖削
--    · 全封闭玻璃观光舱，两侧大全景窗（8 扇/侧）
--    · 圆弧形白色舱顶
--    · 船头驾驶台（玻璃围挡 + 小顶棚）
--    · 船头左侧旗杆 + 蓝白旗
--    · 船尾开放甲板，金属围栏
--
--  碰撞策略（AABB 距离检测，无物理引擎）：
--    · 每帧比较玩家坐标与游船坐标的轴对齐距离
--    · dx < HW and dz < HL → 判定碰撞
--    · 触碰后：扣玩家耐久 + 游船沿玩家方向撞飞
-- ============================================================
local C     = require "config"
local S     = require "state"
local U     = require "utils"
local Track = require "track"

local M = {}

-- ── 碰撞范围（AABB，船宽 2.8m + 玩家半宽 0.95m）───────────────
local HIT_HW = 1.4 + 0.95   -- 水平触发半宽 = 2.35m
local HIT_HL = 4.5 + 1.8    -- 纵向触发半长 = 6.30m

-- ── 撞飞参数 ─────────────────────────────────────────────────
local BLAST_SPEED = 30.0
local BLAST_UP    =  4.0
local BLAST_DAMP  =  3.5
local BLAST_GRAV  = 14.0

-- ── 伤害冷却 ─────────────────────────────────────────────────
local HIT_CD      = 0.60
local lastHitTime = -10.0

-- ── 对象池和状态 ─────────────────────────────────────────────
local pool   = {}
local active = {}

-- ─────────────────────────────────────────────────────────────
--  本地材质辅助
-- ─────────────────────────────────────────────────────────────
local function Mat(r, g, b, metallic, roughness)
    local mat = Material.new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, 1.0)))
    mat:SetShaderParameter("Metallic",     Variant(metallic  or 0.0))
    mat:SetShaderParameter("Roughness",    Variant(roughness or 0.5))
    return mat
end

local function MatAlpha(r, g, b, a)
    local mat = Material.new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, a or 0.40)))
    mat:SetShaderParameter("Metallic",     Variant(0.0))
    mat:SetShaderParameter("Roughness",    Variant(0.08))
    return mat
end

-- ─────────────────────────────────────────────────────────────
--  节点辅助
-- ─────────────────────────────────────────────────────────────
local function AddBox(parent, name, mat, sx, sy, sz, px, py, pz, rx, ry, rz)
    local n = parent:CreateChild(name)
    local m = n:CreateComponent("StaticModel")
    m:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    m:SetMaterial(mat)
    m:SetCastShadows(true)
    n:SetScale(Vector3(sx, sy, sz))
    n:SetPosition(Vector3(px or 0, py or 0, pz or 0))
    if rx or ry or rz then
        n:SetRotation(Quaternion(rx or 0, ry or 0, rz or 0))
    end
    return n
end

local function AddCylinder(parent, name, mat, sx, sy, sz, px, py, pz, rx, ry, rz)
    local n = parent:CreateChild(name)
    local m = n:CreateComponent("StaticModel")
    m:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    m:SetMaterial(mat)
    m:SetCastShadows(true)
    n:SetScale(Vector3(sx, sy, sz))
    n:SetPosition(Vector3(px or 0, py or 0, pz or 0))
    if rx or ry or rz then
        n:SetRotation(Quaternion(rx or 0, ry or 0, rz or 0))
    end
    return n
end

-- ─────────────────────────────────────────────────────────────
--  工厂：构建精细游船节点
--
--  游船尺寸（参考图片）：
--    全长  ≈ 9.0 m，船宽 ≈ 2.8 m，整体高 ≈ 2.5 m
--    坐标约定：+Z = 船头（前方），-Z = 船尾（后方），Y = 上
-- ─────────────────────────────────────────────────────────────
local function Build()
    local node = S.mainScene:CreateChild("Gameboat")
    node:SetEnabled(false)

    -- ── 预制材质 ─────────────────────────────────────────────
    local matHull    = Mat(0.94, 0.94, 0.94, 0.15, 0.35)   -- 白色船壳
    local matDeck    = Mat(0.88, 0.88, 0.88, 0.10, 0.50)   -- 浅灰甲板
    local matCabin   = Mat(0.97, 0.97, 0.97, 0.05, 0.40)   -- 白色舱体
    local matRoof    = Mat(0.96, 0.96, 0.96, 0.05, 0.50)   -- 白色顶棚
    local matGlass   = MatAlpha(0.55, 0.75, 0.90, 0.45)    -- 蓝灰玻璃
    local matFrame   = Mat(0.72, 0.74, 0.76, 0.55, 0.35)   -- 银色金属框
    local matRail    = Mat(0.80, 0.82, 0.84, 0.70, 0.25)   -- 高光栏杆
    local matAccent  = Mat(0.30, 0.35, 0.40, 0.80, 0.20)   -- 深灰舷线
    local matFlag    = Mat(0.20, 0.45, 0.80, 0.00, 0.80)   -- 蓝色旗帜
    local matFlagW   = Mat(0.95, 0.95, 0.95, 0.00, 0.80)   -- 白色旗帜条纹

    -- ── 1. 主船壳（平底，宽体） ──────────────────────────────
    --  船壳：9.0m 长 × 2.8m 宽 × 0.55m 高（吃水线以上）
    AddBox(node, "Hull", matHull, 2.80, 0.55, 9.00, 0, 0, 0)

    -- 底部压舱加深（深色）
    local matKeel = Mat(0.55, 0.57, 0.59, 0.30, 0.50)
    AddBox(node, "Keel", matKeel, 2.70, 0.18, 8.80, 0, -0.33, 0)

    -- 船头削尖（Pyramid，峰顶朝前 +Z）
    local bow = node:CreateChild("Bow")
    do
        local m = bow:CreateComponent("StaticModel")
        m:SetModel(cache:GetResource("Model", "Models/Pyramid.mdl"))
        m:SetMaterial(matHull)
        m:SetCastShadows(true)
    end
    bow:SetScale(Vector3(2.80, 0.55, 1.40))
    bow:SetPosition(Vector3(0, 0, 5.20))
    bow:SetRotation(Quaternion(90, 0, 0))  -- 峰顶 +Y → +Z（船头方向）

    -- 船头削尖加深（深色底）
    local bowKeel = node:CreateChild("BowKeel")
    do
        local m = bowKeel:CreateComponent("StaticModel")
        m:SetModel(cache:GetResource("Model", "Models/Pyramid.mdl"))
        m:SetMaterial(matKeel)
        m:SetCastShadows(true)
    end
    bowKeel:SetScale(Vector3(2.70, 0.18, 1.38))
    bowKeel:SetPosition(Vector3(0, -0.33, 5.18))
    bowKeel:SetRotation(Quaternion(90, 0, 0))

    -- 舷线装饰条（左右各一，分隔船壳与舱体）
    AddBox(node, "BeltL", matAccent, 0.05, 0.12, 9.20, -1.43, 0.22, 0)
    AddBox(node, "BeltR", matAccent, 0.05, 0.12, 9.20,  1.43, 0.22, 0)

    -- ── 2. 主甲板（舱体地板）────────────────────────────────
    AddBox(node, "MainDeck", matDeck, 2.76, 0.08, 8.90, 0, 0.30, 0)

    -- ── 3. 全封闭观光舱 ──────────────────────────────────────
    --  舱体：覆盖船体中后段（-3.8 ~ +2.8 之间），高 1.55m
    --  舱壁（前/后）
    AddBox(node, "CabinFront", matCabin, 2.76, 1.55, 0.10, 0, 1.115, 2.80)
    AddBox(node, "CabinRear",  matCabin, 2.76, 1.55, 0.10, 0, 1.115, -3.80)

    -- 舱壁左右两侧（实体白墙，窗框之间的列）
    --  左右各 8 扇大窗，每扇宽 0.62m，窗柱宽 0.12m
    --  舱段长度 6.6m，分 8 格
    local cabinZStart =  2.80 - 0.05   -- 前端（留出前壁）
    local cabinZEnd   = -3.80 + 0.05   -- 后端
    local cabinLen    = cabinZStart - cabinZEnd  -- ≈ 6.60m
    local nWin        = 8              -- 窗扇数
    local cellW       = cabinLen / nWin          -- 每格 ≈ 0.825m
    local winW        = cellW - 0.12   -- 窗净宽 ≈ 0.705m
    local winH        = 1.00           -- 窗净高
    local winY        = 1.10           -- 窗中心 Y（相对于主甲板面）
    local wallY       = 1.115          -- 墙中心 Y

    for i = 0, nWin - 1 do
        local zCenter = cabinZStart - (i + 0.5) * cellW

        -- 窗柱（窗格之间的实体立柱）
        local postZ = cabinZStart - i * cellW
        if i < nWin then
            AddBox(node, "PostL"..i, matFrame, 0.06, 1.55, 0.08, -1.40, wallY, postZ)
            AddBox(node, "PostR"..i, matFrame, 0.06, 1.55, 0.08,  1.40, wallY, postZ)
        end

        -- 玻璃窗（左右侧各一）
        AddBox(node, "WinL"..i, matGlass, 0.07, winH, winW, -1.40, winY, zCenter)
        AddBox(node, "WinR"..i, matGlass, 0.07, winH, winW,  1.40, winY, zCenter)

        -- 窗框下缘横梁
        AddBox(node, "SillL"..i, matFrame, 0.07, 0.06, winW, -1.40, 0.56, zCenter)
        AddBox(node, "SillR"..i, matFrame, 0.07, 0.06, winW,  1.40, 0.56, zCenter)
        -- 窗框上缘横梁
        AddBox(node, "LintelL"..i, matFrame, 0.07, 0.06, winW, -1.40, 1.62, zCenter)
        AddBox(node, "LintelR"..i, matFrame, 0.07, 0.06, winW,  1.40, 1.62, zCenter)
    end
    -- 最后一根窗柱
    do
        local postZ = cabinZEnd
        AddBox(node, "PostLEnd", matFrame, 0.06, 1.55, 0.08, -1.40, wallY, postZ)
        AddBox(node, "PostREnd", matFrame, 0.06, 1.55, 0.08,  1.40, wallY, postZ)
    end

    -- ── 4. 圆弧舱顶（用多层倾斜薄片叠出弧形）───────────────
    --  舱顶覆盖整个观光舱 + 驾驶台
    local roofZ  = -3.80   -- 舱顶起始（后端）
    local roofZE =  3.80   -- 舱顶结束（延伸到驾驶台）
    local roofLen = roofZE - roofZ  -- 7.60m

    -- 顶板主体（平板，白色）
    AddBox(node, "RoofMain", matRoof, 2.78, 0.10, roofLen, 0, 1.95, (roofZ + roofZE) * 0.5)

    -- 侧向弧度：左右各 3 层渐窄叠加模拟弧线
    local arcSegs = {
        {wx=2.78, y=0.00, dy=0.00, rx=0},
        {wx=2.60, y=0.10, dy=0.05, rx= 8},
        {wx=2.30, y=0.18, dy=0.05, rx=15},
        {wx=1.80, y=0.22, dy=0.04, rx=22},
    }
    for si, seg in ipairs(arcSegs) do
        AddBox(node, "RoofArc"..si, matRoof, seg.wx, 0.08, roofLen,
               0, 1.95 + seg.y + 0.04, (roofZ + roofZE) * 0.5, seg.rx, 0, 0)
    end

    -- 舱顶左右边沿装饰条
    AddBox(node, "RoofEdgeL", matAccent, 0.05, 0.08, roofLen, -1.40, 1.93, (roofZ + roofZE) * 0.5)
    AddBox(node, "RoofEdgeR", matAccent, 0.05, 0.08, roofLen,  1.40, 1.93, (roofZ + roofZE) * 0.5)

    -- ── 5. 驾驶台（船头观光舱前方，Z: 2.80 ~ 3.80）────────
    --  驾驶台比观光舱略窄，全玻璃围挡，带小顶棚
    local cbZ = 3.30  -- 驾驶台中心 Z

    -- 驾驶台地板
    AddBox(node, "BridgeDeck", matDeck, 2.60, 0.08, 0.96, 0, 0.30, cbZ)

    -- 前挡风玻璃（轻微前倾 10°）
    local bfWin = node:CreateChild("BridgeFront")
    do
        local m = bfWin:CreateComponent("StaticModel")
        m:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        m:SetMaterial(matGlass)
        m:SetCastShadows(true)
    end
    bfWin:SetScale(Vector3(2.55, 1.25, 0.07))
    bfWin:SetPosition(Vector3(0, 0.985, 3.78))
    bfWin:SetRotation(Quaternion(-10, 0, 0))

    -- 驾驶台左右侧玻璃
    AddBox(node, "BridgeSideL", matGlass,  0.07, 1.15, 0.90, -1.30, 0.93, cbZ)
    AddBox(node, "BridgeSideR", matGlass,  0.07, 1.15, 0.90,  1.30, 0.93, cbZ)

    -- 驾驶台后方小舱壁（连接观光舱）
    AddBox(node, "BridgeRear", matCabin, 2.55, 1.45, 0.08, 0, 1.065, 2.84)

    -- 驾驶台顶棚
    AddBox(node, "BridgeRoof", matRoof, 2.65, 0.08, 1.05, 0, 1.62, cbZ)

    -- 驾驶台框架立柱（四角）
    AddBox(node, "BrPostFL", matFrame, 0.07, 1.45, 0.07, -1.30, 1.065, 3.82)
    AddBox(node, "BrPostFR", matFrame, 0.07, 1.45, 0.07,  1.30, 1.065, 3.82)
    AddBox(node, "BrPostRL", matFrame, 0.07, 1.45, 0.07, -1.30, 1.065, 2.84)
    AddBox(node, "BrPostRR", matFrame, 0.07, 1.45, 0.07,  1.30, 1.065, 2.84)

    -- ── 6. 船尾开放甲板（Z: -3.80 ~ -4.50）──────────────────
    AddBox(node, "SternDeck", matDeck, 2.76, 0.08, 0.70, 0, 0.30, -4.15)

    -- 船尾矮围墙
    AddBox(node, "SternWall", matCabin, 2.76, 0.45, 0.08, 0, 0.50, -4.50)

    -- ── 7. 船尾围栏（金属栏杆，左右各 3 根竖杆 + 1 根横杆）──
    local railH = 1.05   -- 栏杆高度
    local railY = 0.30 + railH * 0.5  -- 中心 Y
    local sternZ = -3.85

    -- 左侧舷栏（沿船身纵向，从观光舱后壁到船尾）
    for i = 0, 3 do
        local rz = sternZ - i * 0.22
        AddCylinder(node, "RailPostSL"..i, matRail, 0.05, railH, 0.05,
                    -1.38, railY, rz,  0, 0, 0)
        AddCylinder(node, "RailPostSR"..i, matRail, 0.05, railH, 0.05,
                     1.38, railY, rz,  0, 0, 0)
    end
    -- 左右各一根纵向横杆
    AddBox(node, "RailTopSL",  matRail, 0.04, 0.04, 0.70, -1.38, 0.30 + railH, sternZ - 0.33)
    AddBox(node, "RailTopSR",  matRail, 0.04, 0.04, 0.70,  1.38, 0.30 + railH, sternZ - 0.33)
    -- 船尾横向栏杆
    AddBox(node, "RailSternH", matRail, 2.80, 0.04, 0.04, 0, 0.30 + railH, -4.50)

    -- ── 8. 船头围栏（驾驶台两侧各两根立杆 + 横杆） ──────────
    local bowRailZ = 4.20
    AddCylinder(node, "RailBowL1", matRail, 0.05, railH, 0.05, -1.38, railY, bowRailZ)
    AddCylinder(node, "RailBowL2", matRail, 0.05, railH, 0.05, -1.38, railY, bowRailZ + 0.55)
    AddCylinder(node, "RailBowR1", matRail, 0.05, railH, 0.05,  1.38, railY, bowRailZ)
    AddCylinder(node, "RailBowR2", matRail, 0.05, railH, 0.05,  1.38, railY, bowRailZ + 0.55)
    AddBox(node, "RailBowHL", matRail, 0.04, 0.04, 0.60, -1.38, 0.30 + railH, bowRailZ + 0.27)
    AddBox(node, "RailBowHR", matRail, 0.04, 0.04, 0.60,  1.38, 0.30 + railH, bowRailZ + 0.27)
    -- 船头横向围栏
    AddBox(node, "RailBowFront", matRail, 2.80, 0.04, 0.04, 0, 0.30 + railH, bowRailZ + 0.55)

    -- ── 9. 旗杆 + 旗帜（船头左侧）────────────────────────────
    local poleX = -0.60
    local poleZ =  4.70
    local poleBaseY = 0.35
    -- 旗杆（细长圆柱）
    AddCylinder(node, "FlagPole", matRail, 0.04, 1.60, 0.04,
                poleX, poleBaseY + 0.80, poleZ)
    -- 旗帜主体（蓝色）
    AddBox(node, "FlagBlue",  matFlag,  0.02, 0.28, 0.44,
           poleX - 0.22, poleBaseY + 1.45, poleZ)
    -- 旗帜白色条纹
    AddBox(node, "FlagWhite", matFlagW, 0.02, 0.08, 0.44,
           poleX - 0.22, poleBaseY + 1.22, poleZ)

    -- ── 10. 船头装饰件（锚链孔盖、防撞护舷）──────────────────
    -- 船头前端防撞橡皮条（深色细条）
    local matBumper = Mat(0.25, 0.26, 0.28, 0.20, 0.90)
    AddBox(node, "BumperFront", matBumper, 2.78, 0.22, 0.08, 0, 0.05, 5.18)

    return node
end

-- ─────────────────────────────────────────────────────────────
--  对象池
-- ─────────────────────────────────────────────────────────────
local function Get()
    local n = #pool > 0 and table.remove(pool) or Build()
    n:SetEnabled(true)
    n:SetWorldRotation(Quaternion.IDENTITY)
    return n
end

local function Recycle(entry)
    entry.node:SetWorldRotation(Quaternion.IDENTITY)
    entry.node:SetEnabled(false)
    table.insert(pool, entry.node)
end

-- ─────────────────────────────────────────────────────────────
--  生成一艘游船（由 obstacles.lua 调用）
-- ─────────────────────────────────────────────────────────────
function M.Spawn(spawnNode, laneOff)
    local node = Get()
    local rad    = math.rad(spawnNode.heading)
    local rightX = math.cos(rad)
    local rightZ = -math.sin(rad)
    node:SetWorldPosition(Vector3(
        spawnNode.x + rightX * laneOff,
        0,
        spawnNode.z + rightZ * laneOff
    ))
    node:SetWorldRotation(Quaternion(0, spawnNode.heading, 0))
    table.insert(active, {
        node    = node,
        vx = 0, vz = 0, vy = 0,
        blasted = false,
    })
end

-- ─────────────────────────────────────────────────────────────
--  每帧更新：碰撞检测 + 撞飞物理 + 回收
-- ─────────────────────────────────────────────────────────────
function M.Update(dt)
    if #active == 0 then return end

    local bp = S.boatNode:GetWorldPosition()
    local now = time and time:GetElapsedTime() or 0
    local dampFactor = math.exp(-BLAST_DAMP * dt)
    local fwdX = math.sin(math.rad(S.boatHeading))
    local fwdZ = math.cos(math.rad(S.boatHeading))

    for i = #active, 1, -1 do
        local e    = active[i]
        local node = e.node
        if not node:IsEnabled() then
            table.remove(active, i)
        else
            local p = node:GetWorldPosition()

            -- ── 碰撞检测（AABB） ──────────────────────────────
            if not e.blasted then
                local dx = math.abs(bp.x - p.x)
                local dz = math.abs(bp.z - p.z)
                if dx < HIT_HW and dz < HIT_HL then
                    if (now - lastHitTime) >= HIT_CD then
                        lastHitTime = now
                        if TakeDurabilityHit then TakeDurabilityHit("gameboat") end
                        U.LogInfo("[Gameboat] 碰撞！扣耐久")
                    end
                    e.vx      = fwdX * BLAST_SPEED
                    e.vz      = fwdZ * BLAST_SPEED
                    e.vy      = BLAST_UP
                    e.blasted = true
                end
            end

            -- ── 撞飞物理 ─────────────────────────────────────
            if e.blasted then
                local nx = p.x + e.vx * dt
                local nz = p.z + e.vz * dt
                e.vy = e.vy - BLAST_GRAV * dt
                local ny = p.y + e.vy * dt
                if ny < 0 then ny = 0; e.vy = 0 end
                e.vx = e.vx * dampFactor
                e.vz = e.vz * dampFactor
                node:SetWorldPosition(Vector3(nx, ny, nz))
                local tilt = math.max(-75.0, e.vy * -4.0)
                node:SetWorldRotation(Quaternion(tilt, 0, 0))
            end

            -- ── 回收落后的游船 ────────────────────────────────
            local ddx = p.x - S.boatPosX
            local ddz = p.z - S.boatPosZ
            if ddx * fwdX + ddz * fwdZ < -C.RECYCLE_DIST then
                Recycle(e)
                table.remove(active, i)
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
--  清空（重新开始）
-- ─────────────────────────────────────────────────────────────
function M.ClearAll()
    for i = #active, 1, -1 do
        Recycle(active[i])
        table.remove(active, i)
    end
    lastHitTime = -10.0
end

function M.ActiveCount()
    return #active
end

return M
