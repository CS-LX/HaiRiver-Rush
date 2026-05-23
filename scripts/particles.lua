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
--  材质：实体无光照（NoTextureUnlit）
--  原因：PBRNoTextureAlpha 在透明 pass 渲染，SingleLayerWater 写深度缓冲
--        导致粒子后方有水时变黑。改用不透明 pass 渲染完全绕开该问题。
--  淡出效果改用 SetSizeAdd 让粒子缩小消失，不依赖 alpha。
-- ─────────────────────────────────────────────────────────────
local function MakeWaterMat()
    local mat = Material.new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))
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
