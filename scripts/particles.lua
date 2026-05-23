-- ============================================================
--  particles.lua  —  快艇粒子特效
--    · 螺旋桨打水水花（船尾，随油门开度增减发射率）
--    · 漂移水花（左/右舷，侧倾超过阈值时触发）
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

-- 漂移判断阈值（度），与 boat.lua 中 tiltTarget=20° 对应
local DRIFT_TILT_THR = 7.0

-- ─────────────────────────────────────────────────────────────
--  材质：透明无光照，适合水花/水雾粒子
-- ─────────────────────────────────────────────────────────────
local function MakeWaterMat()
    local mat = Material.new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 0.85)))
    mat:SetShaderParameter("Roughness",    Variant(0.9))
    mat:SetShaderParameter("Metallic",     Variant(0.0))
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
    fx:SetSizeAdd(-minSz * 1.2)    -- 粒子随时间缩小消失
    fx:SetSizeMul(1.0)
    if gravity then
        fx:SetConstantForce(gravity)
    end
    -- 颜色帧：白色不透明 → 淡蓝透明
    fx:SetNumColorFrames(2)
    fx:SetColorFrame(0, ColorFrame(Color(1.00, 1.00, 1.00, 0.90), 0.0))
    fx:SetColorFrame(1, ColorFrame(Color(0.85, 0.92, 1.00, 0.00), 1.0))
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
        -- 强力向上 + 向后扇形：确保粒子飞出水面后才落下
        Vector3(-0.45, 0.55, -0.90),
        Vector3( 0.45, 1.20, -0.15),
        3.0, 7.0,       -- 更高速度，高速行驶时粒子飞得更远更显眼
        0.60, 1.40,     -- 更长寿命
        0.08, 0.22,     -- 更大粒子，高速下更易看清
        Vector3(0, -5.5, 0)
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
        Vector3(-1.0, 0.50, -0.35),   -- 向左外侧+偏上飞溅
        Vector3(-0.2, 1.20,  0.20),
        2.5, 6.0,
        0.40, 0.90,
        0.07, 0.20,
        Vector3(0, -6.0, 0)
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
        Vector3(0.2, 0.50, -0.35),    -- 向右外侧+偏上飞溅
        Vector3(1.0, 1.20,  0.20),
        2.5, 6.0,
        0.40, 0.90,
        0.07, 0.20,
        Vector3(0, -6.0, 0)
    )
    driftEmitR = driftRNode:CreateComponent("ParticleEmitter")
    driftEmitR.effect = fxR
    driftEmitR:SetEmitting(false)

    log:Write(LOG_INFO, "[Particles] 粒子系统初始化完成")
end

-- ─────────────────────────────────────────────────────────────
--  每帧更新
-- ─────────────────────────────────────────────────────────────
function M.Update(dt)
    -- ── 螺旋桨水花：油门 > 0.05 时喷，发射率随油门线性增减 ──
    local throttleOn = S.throttle > 0.05
    if propEmitter then
        if propEmitter:IsEmitting() ~= throttleOn then
            propEmitter:SetEmitting(throttleOn)
        end
        if throttleOn and propEffect then
            -- 动态调整发射率：低速少水花，高速强喷射
            local rate = 15.0 + S.throttle * 45.0
            propEffect:SetMinEmissionRate(rate * 0.55)
            propEffect:SetMaxEmissionRate(rate)
        end
    end

    -- ── 漂移水花：根据侧倾方向决定哪侧飞溅 ─────────────────
    -- boatTiltZ > 0 → 向左转，左舷吃水（LeftSplash）
    -- boatTiltZ < 0 → 向右转，右舷吃水（RightSplash）
    local tilt  = S.boatTiltZ
    local wantL = tilt >  DRIFT_TILT_THR
    local wantR = tilt < -DRIFT_TILT_THR

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
end

-- ─────────────────────────────────────────────────────────────
--  重置（游戏重开时停止所有发射）
-- ─────────────────────────────────────────────────────────────
function M.Reset()
    if propEmitter  then propEmitter:SetEmitting(false)  end
    if driftEmitL   then driftEmitL:SetEmitting(false)   end
    if driftEmitR   then driftEmitR:SetEmitting(false)   end
end

return M
