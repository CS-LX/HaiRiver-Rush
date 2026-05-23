-- ============================================================
--  particles.lua  —  快艇粒子特效
--    · 螺旋桨打水水花（船尾，随速度线性增减发射率）
--    · 漂移水花（左/右舷，侧倾超过阈值时触发）
--    · 黑烟（耐久 < 50%）
--    · 火焰（耐久 < 25%）
-- ============================================================
local S = require "state"
local M = {}

---@type ParticleEmitter
local propEmitter  = nil
---@type ParticleEffect
local propEffect   = nil

---@type ParticleEmitter
local driftEmitL   = nil
---@type ParticleEmitter
local driftEmitR   = nil

---@type ParticleEmitter
local smokeEmitter = nil
---@type ParticleEffect
local smokeEffect  = nil
---@type ParticleEmitter
local fireEmitY    = nil   -- 黄色火焰
---@type ParticleEffect
local fireEffectY  = nil
---@type ParticleEmitter
local fireEmitO    = nil   -- 橙色火焰
---@type ParticleEffect
local fireEffectO  = nil
---@type ParticleEmitter
local fireEmitR    = nil   -- 红色火焰
---@type ParticleEffect
local fireEffectR  = nil

-- 漂移判断阈值（度），与 boat.lua 中 tiltTarget=20° 对应
local DRIFT_TILT_THR = 7.0
-- 耐久阈值
local DMG_SMOKE = 0.50   -- < 50% 冒黑烟
local DMG_FIRE  = 0.25   -- < 25% 冒火

-- ─────────────────────────────────────────────────────────────
--  材质函数
--  水花/火焰用 NoTextureUnlit（不透明，避免水面深度冲突）
--  黑烟用 PBRNoTextureAlpha（半透明，烟在船上方不贴水面，安全）
-- ─────────────────────────────────────────────────────────────
local function MakeWaterMat()
    local mat = Material.new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))
    return mat
end

-- 不透明纯色（用于火焰）
local function MakeColorMat(r, g, b)
    local mat = Material.new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, 1.0)))
    return mat
end

-- 半透明（用于烟雾）
local function MakeAlphaMat(r, g, b, a)
    local mat = Material.new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor",  Variant(Color(r, g, b, a)))
    mat:SetShaderParameter("Metallic",      Variant(0.0))
    mat:SetShaderParameter("Roughness",     Variant(1.0))
    return mat
end

-- ─────────────────────────────────────────────────────────────
--  程序化构建 ParticleEffect（不依赖 XML 文件）
--  参数说明（世界空间方向，relative=false）：
--    minDir / maxDir : 粒子发射方向范围（Vector3，归一化即可）
--    minV   / maxV   : 粒子速度 m/s
--    minTTL / maxTTL : 粒子生命周期（秒）
--    minSz  / maxSz  : 粒子尺寸（米）
--    gravity         : 恒定力（模拟重力拖拽）
-- ─────────────────────────────────────────────────────────────
local function MakeEffect(mat, numP, minRate, maxRate,
                           minDir, maxDir,
                           minV, maxV,
                           minTTL, maxTTL,
                           minSz, maxSz,
                           gravity)
    local fx = ParticleEffect:new()
    fx:SetMaterial(mat)
    fx:SetNumParticles(numP)
    fx:SetMinEmissionRate(minRate)
    fx:SetMaxEmissionRate(maxRate)
    fx:SetRelative(false)          -- 发射后在世界空间自由运动，不随船走
    fx:SetEmitterType(EMITTER_SPHERE)
    fx:SetEmitterSize(Vector3(0.18, 0.04, 0.18))
    fx:SetMinDirection(minDir)
    fx:SetMaxDirection(maxDir)
    fx:SetMinVelocity(minV)
    fx:SetMaxVelocity(maxV)
    fx:SetMinTimeToLive(minTTL)
    fx:SetMaxTimeToLive(maxTTL)
    fx:SetMinParticleSize(Vector2(minSz, minSz))
    fx:SetMaxParticleSize(Vector2(maxSz, maxSz))
    -- 尺寸随时间缩小至消失（代替 alpha 淡出）
    fx:SetSizeAdd(-maxSz * 1.2)
    fx:SetSizeMul(1.0)
    if gravity then
        fx:SetConstantForce(gravity)
    end
    -- 颜色帧：浅蓝 → 深蓝（靠缩小消失）
    fx:SetNumColorFrames(3)
    fx:SetColorFrame(0, ColorFrame(Color(0.50, 0.80, 1.00, 1.0), 0.00))
    fx:SetColorFrame(1, ColorFrame(Color(0.15, 0.55, 1.00, 1.0), 0.45))
    fx:SetColorFrame(2, ColorFrame(Color(0.05, 0.35, 0.85, 1.0), 1.00))
    return fx
end

-- ─────────────────────────────────────────────────────────────
--  初始化（必须在 Boat.Init() 之后调用）
-- ─────────────────────────────────────────────────────────────
function M.Init()
    local vis = S.boatVisNode

    -- ── 螺旋桨打水粒子 ──────────────────────────────────────
    -- 船体 BOAT_BASE_Y=0.35，水面 y≈0，局部 y 必须 > -0.35 才在水面以上
    -- 设为 0.15 → 世界 y = 0.35+0.15 = 0.50，安全在水面上方
    local propNode = vis:CreateChild("PropSprayNode")
    propNode:SetPosition(Vector3(0, 0.15, -2.25))

    propEffect = MakeEffect(
        MakeWaterMat(),
        120,
        25.0, 55.0,
        -- 斜抛水花：主要向后喷，带一定上抛角
        Vector3(-0.40, 0.30, -0.90),
        Vector3( 0.40, 0.80, -0.30),
        4.0, 8.0,
        0.40, 0.90,
        0.03, 0.08,
        Vector3(0, -9.8, 0)
    )

    propEmitter = propNode:CreateComponent("ParticleEmitter")
    propEmitter.effect = propEffect
    propEmitter:SetEmitting(false)

    -- ── 漂移水花：左舷（boatTiltZ > DRIFT_TILT_THR 时激活）──
    -- 局部 y=0.18 → 世界 y=0.53，确保在水面以上
    local driftLNode = vis:CreateChild("DriftSprayL")
    driftLNode:SetPosition(Vector3(-0.95, 0.18, 0.0))

    local fxL = MakeEffect(
        MakeWaterMat(),
        60,
        35.0, 60.0,
        Vector3(-0.90, 0.20, -0.40),  -- 向左侧斜抛
        Vector3(-0.30, 0.60,  0.10),
        3.0, 7.0,
        0.35, 0.80,
        0.03, 0.07,
        Vector3(0, -9.8, 0)
    )
    driftEmitL = driftLNode:CreateComponent("ParticleEmitter")
    driftEmitL.effect = fxL
    driftEmitL:SetEmitting(false)

    -- ── 漂移水花：右舷（boatTiltZ < -DRIFT_TILT_THR 时激活）─
    local driftRNode = vis:CreateChild("DriftSprayR")
    driftRNode:SetPosition(Vector3(0.95, 0.18, 0.0))

    local fxR = MakeEffect(
        MakeWaterMat(),
        60,
        35.0, 60.0,
        Vector3(0.30, 0.20, -0.40),   -- 向右侧斜抛
        Vector3(0.90, 0.60,  0.10),
        3.0, 7.0,
        0.35, 0.80,
        0.03, 0.07,
        Vector3(0, -9.8, 0)
    )
    driftEmitR = driftRNode:CreateComponent("ParticleEmitter")
    driftEmitR.effect = fxR
    driftEmitR:SetEmitting(false)

    -- ── 黑烟（发动机上方，耐久 < 50% 激活）──────────────────
    -- PBRNoTextureAlpha 半透明，烟在船身上方不贴水面，无深度冲突
    local smokeNode = vis:CreateChild("SmokeNode")
    smokeNode:SetPosition(Vector3(0, 0.65, -1.55))

    smokeEffect = MakeEffect(
        MakeAlphaMat(0.12, 0.12, 0.12, 0.55),
        80,
        0.0, 0.0,
        Vector3(-0.25, 0.70, -0.20),
        Vector3( 0.25, 1.00,  0.20),
        0.5, 1.2,
        1.50, 2.80,
        0.07, 0.16,      -- 缩小尺寸，不那么方块
        Vector3(0, 0.5, 0)
    )
    -- 烟雾膨胀扩散
    smokeEffect:SetSizeAdd(0.04)
    smokeEffect:SetSizeMul(1.0)
    -- 颜色+alpha 双重淡出
    smokeEffect:SetNumColorFrames(3)
    smokeEffect:SetColorFrame(0, ColorFrame(Color(0.18, 0.18, 0.18, 0.60), 0.00))
    smokeEffect:SetColorFrame(1, ColorFrame(Color(0.10, 0.10, 0.10, 0.35), 0.55))
    smokeEffect:SetColorFrame(2, ColorFrame(Color(0.05, 0.05, 0.05, 0.00), 1.00))

    smokeEmitter = smokeNode:CreateComponent("ParticleEmitter")
    smokeEmitter.effect = smokeEffect
    smokeEmitter:SetEmitting(false)

    -- ── 火焰（三色并行发射，耐久 < 25% 激活）──────────────
    -- 火焰节点略低于烟雾（火在下，烟在上）
    local fireBase = vis:CreateChild("FireBase")
    fireBase:SetPosition(Vector3(0, 0.42, -1.55))

    -- 辅助：创建单色火焰 effect
    local function MakeFireFx(mat, sizeMin, sizeMax, speedMin, speedMax, ttlMin, ttlMax)
        local fx = ParticleEffect:new()
        fx:SetMaterial(mat)
        fx:SetNumParticles(40)
        fx:SetMinEmissionRate(0.0)
        fx:SetMaxEmissionRate(0.0)
        fx:SetRelative(false)
        fx:SetEmitterType(EMITTER_SPHERE)
        fx:SetEmitterSize(Vector3(0.12, 0.06, 0.12))
        fx:SetMinDirection(Vector3(-0.22, 0.65, -0.15))
        fx:SetMaxDirection(Vector3( 0.22, 1.00,  0.15))
        fx:SetMinVelocity(speedMin)
        fx:SetMaxVelocity(speedMax)
        fx:SetMinTimeToLive(ttlMin)
        fx:SetMaxTimeToLive(ttlMax)
        fx:SetMinParticleSize(Vector2(sizeMin, sizeMin))
        fx:SetMaxParticleSize(Vector2(sizeMax, sizeMax))
        fx:SetSizeAdd(-sizeMax * 1.4)   -- 快速缩小消失
        fx:SetSizeMul(1.0)
        fx:SetConstantForce(Vector3(0, 2.0, 0))
        fx:SetNumColorFrames(2)
        return fx
    end

    -- 黄色火焰（火芯，最亮最快）
    fireEffectY = MakeFireFx(MakeColorMat(1.00, 0.92, 0.15), 0.03, 0.07, 2.0, 4.5, 0.20, 0.45)
    fireEffectY:SetColorFrame(0, ColorFrame(Color(1.00, 0.95, 0.30, 1.0), 0.00))
    fireEffectY:SetColorFrame(1, ColorFrame(Color(0.90, 0.70, 0.05, 1.0), 1.00))
    local fireNodeY = fireBase:CreateChild("FireY")
    fireNodeY:SetPosition(Vector3(0, 0.05, 0))
    fireEmitY = fireNodeY:CreateComponent("ParticleEmitter")
    fireEmitY.effect = fireEffectY
    fireEmitY:SetEmitting(false)

    -- 橙色火焰（中层）
    fireEffectO = MakeFireFx(MakeColorMat(1.00, 0.45, 0.05), 0.04, 0.09, 1.5, 3.5, 0.25, 0.55)
    fireEffectO:SetColorFrame(0, ColorFrame(Color(1.00, 0.50, 0.08, 1.0), 0.00))
    fireEffectO:SetColorFrame(1, ColorFrame(Color(0.70, 0.25, 0.02, 1.0), 1.00))
    local fireNodeO = fireBase:CreateChild("FireO")
    fireNodeO:SetPosition(Vector3(0, 0, 0))
    fireEmitO = fireNodeO:CreateComponent("ParticleEmitter")
    fireEmitO.effect = fireEffectO
    fireEmitO:SetEmitting(false)

    -- 红色火焰（外焰，最暗最慢）
    fireEffectR = MakeFireFx(MakeColorMat(0.85, 0.10, 0.02), 0.05, 0.10, 1.0, 2.8, 0.30, 0.65)
    fireEffectR:SetColorFrame(0, ColorFrame(Color(0.90, 0.18, 0.03, 1.0), 0.00))
    fireEffectR:SetColorFrame(1, ColorFrame(Color(0.20, 0.05, 0.02, 1.0), 1.00))
    local fireNodeR = fireBase:CreateChild("FireR")
    fireNodeR:SetPosition(Vector3(0, -0.05, 0))
    fireEmitR = fireNodeR:CreateComponent("ParticleEmitter")
    fireEmitR.effect = fireEffectR
    fireEmitR:SetEmitting(false)

    log:Write(LOG_INFO, "[Particles] 粒子系统初始化完成")
end

-- ─────────────────────────────────────────────────────────────
--  每帧更新
-- ─────────────────────────────────────────────────────────────
function M.Update(dt)
    -- ── 螺旋桨水花：速度 > 2 m/s 时喷，发射率随速度线性增减 ──
    local speedOn = S.speed > 2.0
    if propEmitter then
        if propEmitter:IsEmitting() ~= speedOn then
            propEmitter:SetEmitting(speedOn)
        end
        if speedOn and propEffect then
            -- 速度 4~55 → 发射率 8~70（线性映射）
            local t    = math.max(0, math.min(1, (S.speed - 4.0) / 51.0))
            local rate = 8.0 + t * 62.0
            propEffect:SetMinEmissionRate(rate * 0.55)
            propEffect:SetMaxEmissionRate(rate)
        end
    end

    -- ── 漂移水花：根据侧倾方向决定哪侧飞溅 ─────────────────
    -- boatTiltZ < 0 → 向右转，右舷吃水 → 右侧喷
    -- boatTiltZ > 0 → 向左转，左舷吃水 → 左侧喷
    local tilt  = S.boatTiltZ
    local wantL = tilt < -DRIFT_TILT_THR
    local wantR = tilt >  DRIFT_TILT_THR

    if driftEmitL then
        if driftEmitL:IsEmitting() ~= wantL then
            driftEmitL:SetEmitting(wantL)
        end
    end
    if driftEmitR then
        if driftEmitR:IsEmitting() ~= wantR then
            driftEmitR:SetEmitting(wantR)
        end
    end

    -- ── 黑烟：耐久 < 50%，损伤越重烟越浓 ─────────────────
    local dur = S.durability
    if smokeEmitter and smokeEffect then
        local wantSmoke = dur < DMG_SMOKE
        if smokeEmitter:IsEmitting() ~= wantSmoke then
            smokeEmitter:SetEmitting(wantSmoke)
        end
        if wantSmoke then
            -- 耐久 50%→0%：发射率 4→35
            local t = 1.0 - dur / DMG_SMOKE
            local rate = 4.0 + t * 31.0
            smokeEffect:SetMinEmissionRate(rate * 0.6)
            smokeEffect:SetMaxEmissionRate(rate)
        end
    end

    -- ── 火焰（三色）：耐久 < 25%，损伤越重火越猛 ──────────
    local wantFire = dur < DMG_FIRE
    local fireT    = wantFire and (1.0 - dur / DMG_FIRE) or 0.0
    -- 黄色：火芯，发射率最高
    if fireEmitY and fireEffectY then
        if fireEmitY:IsEmitting() ~= wantFire then fireEmitY:SetEmitting(wantFire) end
        if wantFire then
            local r = 6.0 + fireT * 44.0
            fireEffectY:SetMinEmissionRate(r * 0.6) ; fireEffectY:SetMaxEmissionRate(r)
        end
    end
    -- 橙色：中层
    if fireEmitO and fireEffectO then
        if fireEmitO:IsEmitting() ~= wantFire then fireEmitO:SetEmitting(wantFire) end
        if wantFire then
            local r = 5.0 + fireT * 35.0
            fireEffectO:SetMinEmissionRate(r * 0.6) ; fireEffectO:SetMaxEmissionRate(r)
        end
    end
    -- 红色：外焰，最稀疏
    if fireEmitR and fireEffectR then
        if fireEmitR:IsEmitting() ~= wantFire then fireEmitR:SetEmitting(wantFire) end
        if wantFire then
            local r = 4.0 + fireT * 26.0
            fireEffectR:SetMinEmissionRate(r * 0.6) ; fireEffectR:SetMaxEmissionRate(r)
        end
    end
end

-- ─────────────────────────────────────────────────────────────
--  重置（游戏重开时停止所有发射）
-- ─────────────────────────────────────────────────────────────
function M.Reset()
    if propEmitter  then propEmitter:SetEmitting(false)  end
    if driftEmitL   then driftEmitL:SetEmitting(false)   end
    if driftEmitR   then driftEmitR:SetEmitting(false)   end
    if smokeEmitter then smokeEmitter:SetEmitting(false) end
    if fireEmitY    then fireEmitY:SetEmitting(false)    end
    if fireEmitO    then fireEmitO:SetEmitting(false)    end
    if fireEmitR    then fireEmitR:SetEmitting(false)    end
end

return M
