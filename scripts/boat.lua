-- ============================================================
--  boat.lua  —  快艇构建、转向、物理驱动移动
--  碰墙反弹由 boatphys.lua 通过 NodeCollision 事件处理
-- ============================================================
local C = require "config"
local S = require "state"
local U = require "utils"

local M = {}

-- 螺旋桨动画状态
local propAngle = 0.0
---@type Node
local propNode  = nil

-- ─────────────────────────────────────────────────────────────
--  本地材质辅助（直接构造，确保 SetTechnique 正确）
-- ─────────────────────────────────────────────────────────────
local function Mat(r, g, b, metallic, roughness)
    metallic  = metallic  or 0.0
    roughness = roughness or 0.5
    local mat = Material.new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, 1.0)))
    mat:SetShaderParameter("Metallic",     Variant(metallic))
    mat:SetShaderParameter("Roughness",    Variant(roughness))
    return mat
end

local function MatAlpha(r, g, b, a)
    local mat = Material.new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, a or 0.35)))
    mat:SetShaderParameter("Metallic",     Variant(0.0))
    mat:SetShaderParameter("Roughness",    Variant(0.05))
    return mat
end

-- ─────────────────────────────────────────────────────────────
--  节点辅助（创建子节点，附加 StaticModel，返回节点）
-- ─────────────────────────────────────────────────────────────
local function AddBox(parent, name, mat, sx, sy, sz, px, py, pz, rx, ry, rz)
    local n   = parent:CreateChild(name)
    local mdl = n:CreateComponent("StaticModel")
    mdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    mdl:SetMaterial(mat)
    n:SetScale(Vector3(sx, sy, sz))
    n:SetPosition(Vector3(px or 0, py or 0, pz or 0))
    if rx or ry or rz then
        n:SetRotation(Quaternion(rx or 0, ry or 0, rz or 0))
    end
    return n
end

local function AddCylinder(parent, name, mat, sx, sy, sz, px, py, pz, rx, ry, rz)
    local n   = parent:CreateChild(name)
    local mdl = n:CreateComponent("StaticModel")
    mdl:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    mdl:SetMaterial(mat)
    n:SetScale(Vector3(sx, sy, sz))
    n:SetPosition(Vector3(px or 0, py or 0, pz or 0))
    if rx or ry or rz then
        n:SetRotation(Quaternion(rx or 0, ry or 0, rz or 0))
    end
    return n
end

local function AddSphere(parent, name, mat, s, px, py, pz)
    local n   = parent:CreateChild(name)
    local mdl = n:CreateComponent("StaticModel")
    mdl:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    mdl:SetMaterial(mat)
    n:SetScale(Vector3(s, s, s))
    n:SetPosition(Vector3(px or 0, py or 0, pz or 0))
    return n
end

-- ─────────────────────────────────────────────────────────────
--  构建快艇场景节点
-- ─────────────────────────────────────────────────────────────
function M.Init()
    S.boatNode = S.mainScene:CreateChild("Boat")
    S.boatNode:SetPosition(Vector3(0, C.BOAT_BASE_Y, 0))
    S.boatPosX    = 0.0
    S.boatPosZ    = 0.0
    S.boatHeading = 0.0

    S.boatVisNode = S.boatNode:CreateChild("BoatVis")

    -- ── 预制材质 ─────────────────────────────────────────────
    local matHull      = Mat(0.90, 0.20, 0.08,  0.05, 0.45)  -- 鲜红船壳
    local matDeck      = Mat(0.95, 0.92, 0.86,  0.00, 0.55)  -- 米白甲板
    local matChine     = Mat(1.00, 0.85, 0.10,  0.00, 0.50)  -- 黄色舷线
    local matCabin     = Mat(0.92, 0.90, 0.88,  0.00, 0.45)  -- 浅灰驾驶舱
    local matGlass     = MatAlpha(0.45, 0.72, 0.95, 0.35)     -- 蓝色玻璃
    local matSeat      = Mat(0.12, 0.12, 0.14,  0.00, 0.80)  -- 深灰皮质座椅
    local matEngine    = Mat(0.22, 0.22, 0.25,  0.75, 0.30)  -- 深灰金属发动机
    local matProp      = Mat(0.78, 0.70, 0.25,  0.90, 0.20)  -- 黄铜螺旋桨
    local matNavRed    = Mat(0.95, 0.10, 0.10,  0.00, 0.50)  -- 红色航行灯
    local matNavGreen  = Mat(0.10, 0.88, 0.22,  0.00, 0.50)  -- 绿色航行灯

    -- ── V 型船壳（龙骨 + 左右侧板各倾斜 18°）────────────────
    -- 龙骨（底部中心条，略深色红）
    local matKeel = Mat(0.72, 0.14, 0.06, 0.05, 0.55)
    AddBox(S.boatVisNode, "Keel",  matKeel,  1.10, 0.18, 3.60,  0, -0.20, 0)

    -- 左舷侧壳（绕Z轴 -18° 使底边向内、顶边向外）
    AddBox(S.boatVisNode, "HullL", matHull,  0.52, 0.55, 3.55,
           -0.66, 0.0, 0,  0, 0, -18)
    -- 右舷侧壳（绕Z轴 +18°）
    AddBox(S.boatVisNode, "HullR", matHull,  0.52, 0.55, 3.55,
            0.66, 0.0, 0,  0, 0,  18)

    -- ── 甲板面（平铺在侧壳顶部，略微向前抬起）────────────────
    AddBox(S.boatVisNode, "BowDeck",  matDeck, 1.72, 0.06, 1.60,  0, 0.28, 1.20)
    AddBox(S.boatVisNode, "SternDeck",matDeck, 1.72, 0.06, 0.80,  0, 0.28,-1.50)

    -- ── 船头（Pyramid 顶朝前方 +Z，Scale: X宽, Y前伸长度, Z高）──
    -- Pyramid 默认峰顶在局部 +Y，旋转 90° 使峰顶朝 +Z（前方）
    local bowNode = S.boatVisNode:CreateChild("BowTip")
    do
        local mdl = bowNode:CreateComponent("StaticModel")
        mdl:SetModel(cache:GetResource("Model", "Models/Pyramid.mdl"))
        mdl:SetMaterial(matHull)
    end
    bowNode:SetScale(Vector3(1.55, 1.05, 0.42))
    bowNode:SetPosition(Vector3(0, 0.04, 2.12))
    bowNode:SetRotation(Quaternion(90, 0, 0))  -- 峰顶 +Y → +Z

    -- ── 黄色舷线（左右各一条，视觉亮点）─────────────────────
    AddBox(S.boatVisNode, "ChineL", matChine, 0.06, 0.08, 3.70,
           -0.92, 0.04, -0.05)
    AddBox(S.boatVisNode, "ChineR", matChine, 0.06, 0.08, 3.70,
            0.92, 0.04, -0.05)

    -- ── 驾驶舱主体 ───────────────────────────────────────────
    local cockpitFloor = AddBox(S.boatVisNode, "CockpitFloor", matDeck,
                                1.55, 0.06, 1.30,  0, 0.32, 0.05)
    AddBox(S.boatVisNode, "Dashboard", matCabin,
           1.40, 0.32, 0.08,  0, 0.50, 0.70)

    -- 挡风玻璃（透明蓝色，倾斜前倾 20°）
    local windshield = S.boatVisNode:CreateChild("Windshield")
    do
        local mdl = windshield:CreateComponent("StaticModel")
        mdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        mdl:SetMaterial(matGlass)
    end
    windshield:SetScale(Vector3(1.45, 0.45, 0.06))
    windshield:SetPosition(Vector3(0, 0.72, 0.70))
    windshield:SetRotation(Quaternion(-20, 0, 0))  -- 前倾 20°

    -- 座椅靠背
    AddBox(S.boatVisNode, "SeatBack",    matSeat, 0.70, 0.45, 0.10,  0, 0.60, -0.12)
    -- 座椅坐垫
    AddBox(S.boatVisNode, "SeatCushion", matSeat, 0.70, 0.10, 0.50,  0, 0.38, -0.40)

    -- ── 舷外发动机（船尾，挂外侧）───────────────────────────
    -- 发动机上盖（圆柱）
    AddCylinder(S.boatVisNode, "EngCap", matEngine,
                0.36, 0.38, 0.36,  0, 0.18, -2.05,  90, 0, 0)
    -- 发动机支撑杆
    AddBox(S.boatVisNode, "EngLeg", matEngine,
           0.14, 0.52, 0.14,  0, -0.22, -2.05)
    -- 空穴板（发动机底部水平板）
    AddBox(S.boatVisNode, "CavPlate", matEngine,
           0.52, 0.06, 0.28,  0, -0.50, -2.05)

    -- ── 螺旋桨（3 叶，绕 Z 轴旋转）──────────────────────────
    -- propNode 是旋转父节点，挂在发动机腿正后下方
    propNode = S.boatVisNode:CreateChild("PropRoot")
    propNode:SetPosition(Vector3(0, -0.50, -2.20))

    -- 螺旋桨毂（小圆柱，表示轴心）
    AddCylinder(propNode, "PropHub", matProp,
                0.12, 0.08, 0.12,  0, 0, 0,  90, 0, 0)

    -- 三片桨叶：每隔 120° 一片
    for i = 0, 2 do
        local angle  = i * 120.0
        local bladeRoot = propNode:CreateChild("BladeRoot" .. i)
        bladeRoot:SetRotation(Quaternion(0, 0, angle))

        -- 桨叶（扁平矩形，向 +Y 延伸，绕 bladeRoot 旋转分布）
        local blade = bladeRoot:CreateChild("Blade" .. i)
        local mdl   = blade:CreateComponent("StaticModel")
        mdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        mdl:SetMaterial(matProp)
        blade:SetScale(Vector3(0.10, 0.35, 0.18))   -- 薄、长、稍宽
        blade:SetPosition(Vector3(0, 0.22, 0))       -- 从轴心向外延伸
        blade:SetRotation(Quaternion(0, 15, 0))      -- 桨叶攻角
    end

    -- ── 航行灯（船头左红右绿）───────────────────────────────
    AddSphere(S.boatVisNode, "NavRed",   matNavRed,   0.10, -0.78, 0.30, 1.95)
    AddSphere(S.boatVisNode, "NavGreen", matNavGreen, 0.10,  0.78, 0.30, 1.95)

    -- ── 动态刚体（物理引擎驱动移动，碰墙由 NodeCollision 处理） ──
    local rb = S.boatNode:CreateComponent("RigidBody")
    rb:SetMass(80.0)
    rb:SetLinearFactor(Vector3(1, 0, 1))   -- 锁 Y 轴移动
    rb:SetAngularFactor(Vector3(0, 0, 0))  -- 锁所有旋转
    rb:SetLinearDamping(0.05)
    rb:SetRestitution(0.15)
    rb:SetFriction(0.1)
    rb:SetCollisionLayerAndMask(1, 4)      -- 层1=玩家，掩码4=堤岸

    -- 碰撞体（盒型，与视觉模型匹配）
    local col = S.boatNode:CreateComponent("CollisionShape")
    col:SetBox(Vector3(1.9, 1.1, 3.6), Vector3(0, 0.25, 0), Quaternion.IDENTITY)

    U.LogInfo("[Boat] 精细快艇创建完毕（V型船壳/驾驶舱/螺旋桨）")
end

-- 将角度差规范化到 [-180, 180]（最短路径）
local function NormAngle(a)
    a = a % 360
    if a > 180 then a = a - 360 end
    return a
end

-- ─────────────────────────────────────────────────────────────
--  转向操作（每帧按住时持续调用）
-- ─────────────────────────────────────────────────────────────
function M.Steer(dir, dt)
    S.boatHeading       = S.boatHeading + dir * C.STEER_SPEED * dt
    S.boatTargetHeading = S.boatHeading
    local tiltTarget = -dir * 20.0
    S.boatTiltZ = U.Lerp(S.boatTiltZ, tiltTarget, dt * 8.0)
end

-- 无转向时回正
function M.ReturnCenter(dt)
    S.boatTiltZ = U.Lerp(S.boatTiltZ, 0.0, dt * 6.0)
end

-- ─────────────────────────────────────────────────────────────
--  每帧更新：SetLinearVelocity 驱动，物理引擎处理墙壁碰撞
-- ─────────────────────────────────────────────────────────────
function M.Update(dt)
    -- ── 平滑追逐目标朝向 ──────────────────────────────────────
    local diff = NormAngle(S.boatTargetHeading - S.boatHeading)
    if math.abs(diff) > 0.01 then
        local maxStep = C.HIT_TURN_SPEED * dt
        local step    = math.max(-maxStep, math.min(maxStep, diff))
        S.boatHeading = S.boatHeading + step
    end

    -- ── 物理速度驱动 ─────────────────────────────────────────
    local rad = math.rad(S.boatHeading)
    local rb  = S.boatNode:GetComponent("RigidBody")
    if rb then
        rb:SetLinearVelocity(Vector3(
            math.sin(rad) * S.speed,
            0,
            math.cos(rad) * S.speed
        ))
    end

    -- 读回物理位置
    local pos  = S.boatNode:GetWorldPosition()
    S.boatPosX = pos.x
    S.boatPosZ = pos.z

    -- 朝向由代码控制
    S.boatNode:SetWorldRotation(Quaternion(0, S.boatHeading, 0))
    S.boatVisNode:SetRotation(Quaternion(0, 0, S.boatTiltZ))

    -- ── 螺旋桨旋转（速度正比于油门）─────────────────────────
    if propNode then
        propAngle = propAngle + S.throttle * 900.0 * dt
        if propAngle > 360.0 then propAngle = propAngle - 360.0 end
        propNode:SetRotation(Quaternion(0, 0, propAngle))
    end
end

-- ─────────────────────────────────────────────────────────────
--  重置（重新开始游戏）
-- ─────────────────────────────────────────────────────────────
function M.Reset()
    local rb = S.boatNode:GetComponent("RigidBody")
    if rb then
        rb:SetLinearVelocity(Vector3.ZERO)
        rb:SetAngularVelocity(Vector3.ZERO)
    end
    S.boatPosX          = 0.0
    S.boatPosY          = C.BOAT_BASE_Y
    S.boatPosZ          = 0.0
    S.boatHeading       = 0.0
    S.boatTargetHeading = 0.0
    S.boatTiltZ         = 0.0
    propAngle           = 0.0
    S.boatNode:SetWorldPosition(Vector3(0, C.BOAT_BASE_Y, 0))
    S.boatNode:SetWorldRotation(Quaternion.IDENTITY)
    S.boatVisNode:SetRotation(Quaternion.IDENTITY)
end

return M
