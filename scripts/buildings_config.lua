-- ============================================================
--  buildings_config.lua  —  建筑类型配置
--
--  参考：天津海河沿岸实景（米黄色古典高层 + 法式欧式矮楼 + 巴洛克宫殿）
--
--  间距设计（TILE_LEN = 10m，间隔由代码自动计算：ceil(spanZ/TILE_LEN) + GAP_TILES）：
--    european_house  spanZ=12m → interval=ceil(12/10)+1=3 tiles → 每 30m 一栋，18m 间隙
--    glass_tower     spanZ=16m → interval=ceil(16/10)+2=4 tiles → 每 40m 一栋，24m 间隙
--    baroque_palace  spanZ=40m → interval=ceil(40/10)+1=5 tiles → 每 50m 一次（地标）
--
--  字段说明：
--    tier      "short"（近岸矮楼）| "tall"（远岸高层）
--    spanZ     沿赛道方向宽度（m）
--    spanX     垂直赛道方向深度（m）
--    heightMin / heightMax  随机高度范围（m）
--    parts[]:
--      model     "Box"(默认) | "Sphere" | "Cylinder" | "Hemisphere"
--      yBottom / yTop    高度比例区间 [0,1]
--      xScale / zScale   构件缩放（>1 挑出）
--      offsetZ           沿赛道偏移（m），用于分段/侧翼
--      absSize           绝对直径（Hemisphere/Cylinder 用）
--      color / roughness / metallic
-- ============================================================

return {
    types = {

        -- ────────────────────────────────────────────────────
        --  古典米黄色高层（spanZ=16m，每 3 瓦片 1 栋 → 30m 间距）
        -- ────────────────────────────────────────────────────
        --  青绿幕墙细高楼（现代国际风格，偏绿色玻璃）
        -- ────────────────────────────────────────────────────
        teal_glass = {
            tier       = "tall",
            spanZ      = 14,
            spanX      = 14,
            heightMin  = 48,
            heightMax  = 80,
            curtainWall  = true,
            glassColor   = { 0.04, 0.30, 0.22 },  -- 固定青翠绿（匹配 teal 名称）
            glassRoughness = 0.05, glassMetallic = 0.76,
            winYStart   = 0.02,
            winYEnd     = 0.96,
            parts = {
                -- 主体下段（全幅）
                { model = "Box",
                  yBottom = 0.00, yTop = 0.62,
                  xScale = 1.00, zScale = 1.00,
                  color = { 0.18, 0.36, 0.40 }, roughness = 0.18, metallic = 0.30,
                },
                -- 腰带分段线（略挑出）
                { model = "Box",
                  yBottom = 0.60, yTop = 0.63,
                  xScale = 1.025, zScale = 1.025,
                  color = { 0.12, 0.20, 0.24 }, roughness = 0.75, metallic = 0.08,
                },
                -- 主体上段（内缩）
                { model = "Box",
                  yBottom = 0.62, yTop = 0.95,
                  xScale = 0.85, zScale = 0.85,
                  color = { 0.18, 0.36, 0.40 }, roughness = 0.18, metallic = 0.30,
                },
                -- 顶冠
                { model = "Box",
                  yBottom = 0.94, yTop = 1.00,
                  xScale = 0.42, zScale = 0.42,
                  color = { 0.14, 0.26, 0.30 }, roughness = 0.38, metallic = 0.42,
                },
            },
        },

        -- ────────────────────────────────────────────────────
        --  现代主义混凝土办公楼（浅灰，带逐窗网格）
        -- ────────────────────────────────────────────────────
        concrete_office = {
            tier       = "tall",
            spanZ      = 18,
            spanX      = 16,
            heightMin  = 38,
            heightMax  = 62,
            addWindows = true,
            winYStart  = 0.10,
            winYEnd    = 0.88,
            parts = {
                -- 深灰基座
                { model = "Box",
                  yBottom = 0.00, yTop = 0.09,
                  xScale = 1.045, zScale = 1.045,
                  color = { 0.50, 0.48, 0.45 }, roughness = 0.84, metallic = 0.0,
                },
                -- 浅灰混凝土主体
                { model = "Box",
                  yBottom = 0.08, yTop = 0.91,
                  xScale = 1.00, zScale = 1.00,
                  color = { 0.74, 0.72, 0.68 }, roughness = 0.78, metallic = 0.02,
                },
                -- 顶部腰线（挑出）
                { model = "Box",
                  yBottom = 0.89, yTop = 0.94,
                  xScale = 1.035, zScale = 1.035,
                  color = { 0.50, 0.48, 0.45 }, roughness = 0.82, metallic = 0.0,
                },
                -- 机械层顶箱
                { model = "Box",
                  yBottom = 0.93, yTop = 1.00,
                  xScale = 0.78, zScale = 0.78,
                  color = { 0.58, 0.56, 0.52 }, roughness = 0.80, metallic = 0.0,
                },
            },
        },

        -- ────────────────────────────────────────────────────
        --  乳白古典比例高层（象牙白石材，带窗格，细挑檐）
        -- ────────────────────────────────────────────────────
        ivory_classic = {
            tier       = "tall",
            spanZ      = 14,
            spanX      = 16,
            heightMin  = 46,
            heightMax  = 74,
            addWindows = true,
            winYStart  = 0.10,
            winYEnd    = 0.82,
            parts = {
                -- 石材基座（深暖米）
                { model = "Box",
                  yBottom = 0.00, yTop = 0.10,
                  xScale = 1.06, zScale = 1.06,
                  color = { 0.72, 0.66, 0.54 }, roughness = 0.84, metallic = 0.0,
                },
                -- 主体（象牙白）
                { model = "Box",
                  yBottom = 0.09, yTop = 0.83,
                  xScale = 1.00, zScale = 1.00,
                  color = { 0.95, 0.92, 0.84 }, roughness = 0.68, metallic = 0.0,
                },
                -- 主檐线脚（挑出）
                { model = "Box",
                  yBottom = 0.81, yTop = 0.88,
                  xScale = 1.08, zScale = 1.08,
                  color = { 0.82, 0.76, 0.64 }, roughness = 0.76, metallic = 0.0,
                },
                -- 顶部阁楼（收窄）
                { model = "Box",
                  yBottom = 0.87, yTop = 1.00,
                  xScale = 0.80, zScale = 0.80,
                  color = { 0.90, 0.86, 0.76 }, roughness = 0.70, metallic = 0.0,
                },
            },
        },

        -- ────────────────────────────────────────────────────
        --  深色台阶幕墙楼（暖碳灰，三段退台，铜色感）
        -- ────────────────────────────────────────────────────
        dark_step = {
            tier       = "tall",
            spanZ      = 16,
            spanX      = 18,
            heightMin  = 55,
            heightMax  = 85,
            curtainWall  = true,
            glassColor   = { 0.16, 0.06, 0.30 },  -- 固定深蓝紫（暗色退台风格）
            glassRoughness = 0.05, glassMetallic = 0.80,
            winYStart   = 0.01,
            winYEnd     = 0.97,
            parts = {
                -- 下段（全幅，深暖灰）
                { model = "Box",
                  yBottom = 0.00, yTop = 0.50,
                  xScale = 1.00, zScale = 1.00,
                  color = { 0.36, 0.32, 0.28 }, roughness = 0.30, metallic = 0.22,
                },
                -- 腰线
                { model = "Box",
                  yBottom = 0.48, yTop = 0.52,
                  xScale = 1.02, zScale = 1.02,
                  color = { 0.22, 0.20, 0.17 }, roughness = 0.72, metallic = 0.08,
                },
                -- 中段（内缩）
                { model = "Box",
                  yBottom = 0.50, yTop = 0.78,
                  xScale = 0.86, zScale = 0.86,
                  color = { 0.36, 0.32, 0.28 }, roughness = 0.30, metallic = 0.22,
                },
                -- 腰线 2
                { model = "Box",
                  yBottom = 0.76, yTop = 0.80,
                  xScale = 0.88, zScale = 0.88,
                  color = { 0.22, 0.20, 0.17 }, roughness = 0.72, metallic = 0.08,
                },
                -- 上段（再收缩）
                { model = "Box",
                  yBottom = 0.78, yTop = 0.97,
                  xScale = 0.68, zScale = 0.68,
                  color = { 0.36, 0.32, 0.28 }, roughness = 0.30, metallic = 0.22,
                },
                -- 顶冠
                { model = "Box",
                  yBottom = 0.96, yTop = 1.00,
                  xScale = 0.32, zScale = 0.32,
                  color = { 0.28, 0.24, 0.20 }, roughness = 0.45, metallic = 0.35,
                },
            },
        },

        -- ────────────────────────────────────────────────────
        glass_tower = {
            tier      = "tall",
            spanZ     = 16,
            spanX     = 20,
            heightMin = 55,
            heightMax = 95,
            parts = {
                {   -- 深色石材基座
                    yBottom = 0.00, yTop = 0.08,
                    xScale = 1.06, zScale = 1.06,
                    color = { 0.62, 0.57, 0.47 }, roughness = 0.82, metallic = 0.0,
                },
                {   -- 米黄石材主体
                    yBottom = 0.07, yTop = 0.88,
                    xScale = 1.00, zScale = 1.00,
                    color = { 0.87, 0.80, 0.64 }, roughness = 0.70, metallic = 0.02,
                },
                {   -- 顶部挑檐腰线
                    yBottom = 0.86, yTop = 0.92,
                    xScale = 1.04, zScale = 1.04,
                    color = { 0.72, 0.66, 0.54 }, roughness = 0.76, metallic = 0.0,
                },
                {   -- 顶冠（内缩收头）
                    yBottom = 0.91, yTop = 1.00,
                    xScale = 0.86, zScale = 0.86,
                    color = { 0.58, 0.53, 0.43 }, roughness = 0.80, metallic = 0.0,
                },
            },
        },

        -- ────────────────────────────────────────────────────
        --  法式欧式矮楼（spanZ=12m，每 2 瓦片 1 栋 → 20m 间距，8m 间隙）
        -- ────────────────────────────────────────────────────
        european_house = {
            tier       = "short",
            spanZ      = 12,
            spanX      = 12,
            heightMin  = 14,
            heightMax  = 26,
            addWindows = true,   -- 生成石框玻璃窗格
            winYStart  = 0.14,   -- 从基座顶部开始
            winYEnd    = 0.74,   -- 到主檐口底部结束
            parts = {
                {   -- 石材基座
                    yBottom = 0.00, yTop = 0.13,
                    xScale = 1.02, zScale = 1.02,
                    color = { 0.88, 0.80, 0.60 }, roughness = 0.82, metallic = 0.0,
                },
                {   -- 主体（明亮奶黄石材）
                    yBottom = 0.11, yTop = 0.76,
                    xScale = 1.00, zScale = 1.00,
                    color = { 0.98, 0.94, 0.72 }, roughness = 0.65, metallic = 0.0,
                },
                {   -- 主檐线脚（挑出）
                    yBottom = 0.74, yTop = 0.83,
                    xScale = 1.12, zScale = 1.12,
                    color = { 0.90, 0.82, 0.60 }, roughness = 0.72, metallic = 0.0,
                },
                {   -- 法式孟莎屋顶（铜绿蓝石板，典型法式风格）
                    yBottom = 0.81, yTop = 1.00,
                    xScale = 1.16, zScale = 1.16,
                    color = { 0.12, 0.38, 0.36 }, roughness = 0.72, metallic = 0.18,
                },
            },
        },

        -- ────────────────────────────────────────────────────
        --  巴洛克宫殿（地标性，每 25 块瓦片 1 次 = 约 250m）
        --
        --  spanZ=40m（原 52m 缩比 0.77），所有 offsetZ 同比缩放
        --  三段红色坡屋顶 + 中央大穹顶（直径 8m）+ 两侧小穹顶（直径 5m）
        -- ────────────────────────────────────────────────────
        baroque_palace = {
            tier       = "short",
            spanZ      = 40,
            spanX      = 20,
            heightMin  = 22,
            heightMax  = 22,
            addWindows = true,   -- 生成石框玻璃窗格
            winYStart  = 0.10,   -- 从基座顶部开始
            winYEnd    = 0.65,   -- 到主檐口底部结束
            parts = {

                -- ── 石材基座（深色，略宽）──────────────────────
                {   model = "Box",
                    yBottom = 0.00, yTop = 0.10,
                    xScale = 1.03, zScale = 1.03,
                    color = { 0.70, 0.62, 0.44 }, roughness = 0.82, metallic = 0.0,
                },

                -- ── 主体立面（暖金黄石材）──────────────────────
                {   model = "Box",
                    yBottom = 0.08, yTop = 0.70,
                    xScale = 1.00, zScale = 1.00,
                    color = { 0.96, 0.86, 0.52 }, roughness = 0.68, metallic = 0.0,
                },

                -- ── 中层腰线──────────────────────────────────
                {   model = "Box",
                    yBottom = 0.38, yTop = 0.44,
                    xScale = 1.04, zScale = 1.04,
                    color = { 0.82, 0.72, 0.42 }, roughness = 0.74, metallic = 0.0,
                },

                -- ── 主檐口────────────────────────────────────
                {   model = "Box",
                    yBottom = 0.65, yTop = 0.73,
                    xScale = 1.06, zScale = 1.06,
                    color = { 0.76, 0.68, 0.40 }, roughness = 0.76, metallic = 0.0,
                },

                -- ── 红色坡屋顶：左翼（offsetZ=-13m）────────────
                {   model = "Box",
                    yBottom = 0.70, yTop = 0.90,
                    xScale = 0.96, zScale = 0.46,
                    offsetZ = -13.0,
                    color = { 0.76, 0.12, 0.06 }, roughness = 0.65, metallic = 0.0,
                },
                -- ── 红色坡屋顶：右翼（offsetZ=+13m）────────────
                {   model = "Box",
                    yBottom = 0.70, yTop = 0.90,
                    xScale = 0.96, zScale = 0.46,
                    offsetZ = 13.0,
                    color = { 0.76, 0.12, 0.06 }, roughness = 0.65, metallic = 0.0,
                },
                -- ── 红色坡屋顶：中央（略高）──────────────────
                {   model = "Box",
                    yBottom = 0.70, yTop = 0.94,
                    xScale = 0.94, zScale = 0.34,
                    offsetZ = 0.0,
                    color = { 0.74, 0.11, 0.05 }, roughness = 0.62, metallic = 0.0,
                },

                -- ── 侧翼山墙线脚（左端）────────────────────────
                {   model = "Box",
                    yBottom = 0.88, yTop = 0.96,
                    xScale = 0.20, zScale = 0.04,
                    offsetZ = -17.0,
                    color = { 0.78, 0.71, 0.57 }, roughness = 0.76, metallic = 0.0,
                },
                -- ── 侧翼山墙线脚（右端）────────────────────────
                {   model = "Box",
                    yBottom = 0.88, yTop = 0.96,
                    xScale = 0.20, zScale = 0.04,
                    offsetZ = 17.0,
                    color = { 0.78, 0.71, 0.57 }, roughness = 0.76, metallic = 0.0,
                },

                -- ── 中央穹顶鼓座（Cylinder，直径 8m）──────────
                {   model = "Cylinder",
                    yBottom = 0.86, yTop = 0.99,
                    absSize = 8.0,
                    offsetZ = 0.0,
                    color = { 0.96, 0.90, 0.68 }, roughness = 0.68, metallic = 0.0,
                },
                -- ── 中央大半球（直径 8m，鲜红穹顶）──────────
                {   model = "Hemisphere",
                    yBottom = 0.98, yTop = 1.36,
                    absSize = 8.0,
                    offsetZ = 0.0,
                    color = { 0.78, 0.10, 0.05 }, roughness = 0.52, metallic = 0.06,
                },

                -- ── 左侧穹顶鼓座（直径 5m，offsetZ=-12m）───────
                {   model = "Cylinder",
                    yBottom = 0.88, yTop = 0.97,
                    absSize = 5.0,
                    offsetZ = -12.0,
                    color = { 0.96, 0.90, 0.68 }, roughness = 0.68, metallic = 0.0,
                },
                -- ── 左侧小半球（直径 5m）──────────────────────
                {   model = "Hemisphere",
                    yBottom = 0.96, yTop = 1.19,
                    absSize = 5.0,
                    offsetZ = -12.0,
                    color = { 0.76, 0.10, 0.05 }, roughness = 0.54, metallic = 0.06,
                },

                -- ── 右侧穹顶鼓座（直径 5m，offsetZ=+12m）───────
                {   model = "Cylinder",
                    yBottom = 0.88, yTop = 0.97,
                    absSize = 5.0,
                    offsetZ = 12.0,
                    color = { 0.96, 0.90, 0.68 }, roughness = 0.68, metallic = 0.0,
                },
                -- ── 右侧小半球（直径 5m）──────────────────────
                {   model = "Hemisphere",
                    yBottom = 0.96, yTop = 1.19,
                    absSize = 5.0,
                    offsetZ = 12.0,
                    color = { 0.76, 0.10, 0.05 }, roughness = 0.54, metallic = 0.06,
                },
            },
        },

        -- ────────────────────────────────────────────────────
        --  门形高层（海河地标，参考天津滨海金融区风格）
        --
        --  结构解构：
        --    spanZ=56m  沿赛道宽度（玩家从河岸侧看到的立面宽度）
        --    spanX=40m  垂直赛道深度
        --    height=52m 固定高度（约 13 层）
        --
        --  门洞几何：
        --    左柱  zScale=0.32 → 宽17.9m，中心 offsetZ=-19m → Z:-28~-10
        --    右柱  zScale=0.32 → 宽17.9m，中心 offsetZ=+19m → Z:+10~+28
        --    虚空  Z:-10 ~ +10 = 20m，Y: 28%~70% 高度
        --    顶梁  全宽，上部 30% 高度
        --
        --  窗格分区（winZGroups）：
        --    左柱面  Z:-26.5 ~ -11.5（含 1.5m 边距）
        --    右柱面  Z:+11.5 ~ +26.5
        --    虚空及顶梁中段无窗（避免悬空窗格）
        --
        --  材质：
        -- ────────────────────────────────────────────────────
        --  全玻璃幕墙超高层（天津周大福金融中心风格）
        --
        --  特征：深蓝反射玻璃全立面 + 三道机械层横带 + 顶部收分
        --  tier=tall，spanZ=22m，高度 90-115m
        --  幕墙分区：无 winZGroups（全宽单区），竖挺间距 2.4m
        -- ────────────────────────────────────────────────────
        ctf_tower = {
            tier       = "tall",
            spanZ      = 22,
            spanX      = 20,
            heightMin  = 90,
            heightMax  = 115,
            curtainWall  = true,
            glassColor   = { 0.04, 0.18, 0.42 },  -- 固定亮天蓝（超高层标志色）
            glassRoughness = 0.04, glassMetallic = 0.84,
            winYStart   = 0.01,
            winYEnd     = 0.98,
            parts = {
                -- ── 主体下段（0–40%，全幅）────────────────────
                { model = "Box",
                  yBottom = 0.00, yTop = 0.40,
                  xScale = 1.00, zScale = 1.00,
                  color = { 0.28, 0.34, 0.48 }, roughness = 0.20, metallic = 0.28,
                },
                -- ── 机械层带 1（约 25% 处，全幅略挑出）──────────
                { model = "Box",
                  yBottom = 0.23, yTop = 0.27,
                  xScale = 1.02, zScale = 1.02,
                  color = { 0.16, 0.18, 0.24 }, roughness = 0.78, metallic = 0.08,
                },
                -- ── 主体中段（38–65%，略收缩）────────────────────
                { model = "Box",
                  yBottom = 0.38, yTop = 0.65,
                  xScale = 0.94, zScale = 0.94,
                  color = { 0.28, 0.34, 0.48 }, roughness = 0.20, metallic = 0.28,
                },
                -- ── 机械层带 2（约 50% 处）───────────────────────
                { model = "Box",
                  yBottom = 0.48, yTop = 0.52,
                  xScale = 0.96, zScale = 0.96,
                  color = { 0.16, 0.18, 0.24 }, roughness = 0.78, metallic = 0.08,
                },
                -- ── 主体上段（63–85%，进一步收缩）───────────────
                { model = "Box",
                  yBottom = 0.63, yTop = 0.85,
                  xScale = 0.82, zScale = 0.82,
                  color = { 0.28, 0.34, 0.48 }, roughness = 0.20, metallic = 0.28,
                },
                -- ── 机械层带 3（约 67% 处）───────────────────────
                { model = "Box",
                  yBottom = 0.65, yTop = 0.68,
                  xScale = 0.84, zScale = 0.84,
                  color = { 0.16, 0.18, 0.24 }, roughness = 0.78, metallic = 0.08,
                },
                -- ── 顶部细杆段（83–97%）──────────────────────────
                { model = "Box",
                  yBottom = 0.83, yTop = 0.97,
                  xScale = 0.62, zScale = 0.62,
                  color = { 0.28, 0.34, 0.48 }, roughness = 0.20, metallic = 0.28,
                },
                -- ── 顶冠（尖顶天线底座）─────────────────────────
                { model = "Box",
                  yBottom = 0.96, yTop = 1.00,
                  xScale = 0.28, zScale = 0.28,
                  color = { 0.22, 0.26, 0.36 }, roughness = 0.40, metallic = 0.50,
                },
            },
        },

        --    石材  暖米黄 (0.79, 0.73, 0.60)  roughness=0.72
        --    玻璃入口亭  深蓝灰 (0.28, 0.38, 0.50)  metallic=0.65
        -- ────────────────────────────────────────────────────
        portal_tower = {
            tier       = "tall",
            spanZ      = 56,
            spanX      = 40,
            heightMin  = 52,
            heightMax  = 52,
            curtainWall  = true,  -- 使用幕墙系统（整面玻璃板 + 楼板带 + 竖挺）
            glassColor   = { 0.04, 0.07, 0.18 },  -- 固定深海蓝（门形地标标志色）
            glassRoughness = 0.04, glassMetallic = 0.82,
            winYStart  = 0.28,   -- 从基座顶（yTop=0.28）开始
            winYEnd    = 0.70,   -- 到顶桥底（yBottom=0.70）结束
            -- 幕墙分区：双柱 + 顶横梁（每组可独立指定 Y 范围）
            winZGroups = {
                -- 左柱：从基座顶到顶桥底
                { zMin = -26.5, zMax = -11.5, yFracStart = 0.28, yFracEnd = 0.70 },
                -- 右柱：从基座顶到顶桥底
                { zMin =  11.5, zMax =  26.5, yFracStart = 0.28, yFracEnd = 0.70 },
                -- 顶横梁（全宽）：顶桥底到顶冠底
                { zMin = -26.5, zMax =  26.5, yFracStart = 0.70, yFracEnd = 0.97 },
            },
            parts = {

                -- ── 基座（全宽，深米黄，下部约 3 层）────────────
                { model = "Box",
                  yBottom = 0.00, yTop = 0.28,
                  xScale = 1.00, zScale = 1.00,
                  color = { 0.68, 0.62, 0.50 }, roughness = 0.82, metallic = 0.0,
                },

                -- ── 基座顶线脚（全宽，略宽挑出）────────────────
                { model = "Box",
                  yBottom = 0.26, yTop = 0.30,
                  xScale = 1.02, zScale = 1.02,
                  color = { 0.58, 0.53, 0.42 }, roughness = 0.85, metallic = 0.0,
                },

                -- ── 左柱（砂黄石材主体）────────────────────────
                { model = "Box",
                  yBottom = 0.28, yTop = 1.00,
                  xScale = 1.00, zScale = 0.32,
                  offsetZ = -19.0,
                  color = { 0.79, 0.73, 0.60 }, roughness = 0.72, metallic = 0.0,
                },

                -- ── 右柱（镜像左柱）────────────────────────────
                { model = "Box",
                  yBottom = 0.28, yTop = 1.00,
                  xScale = 1.00, zScale = 0.32,
                  offsetZ = 19.0,
                  color = { 0.79, 0.73, 0.60 }, roughness = 0.72, metallic = 0.0,
                },

                -- ── 顶部横梁（全宽，连接双柱）──────────────────
                { model = "Box",
                  yBottom = 0.70, yTop = 1.00,
                  xScale = 1.00, zScale = 1.00,
                  color = { 0.79, 0.73, 0.60 }, roughness = 0.72, metallic = 0.0,
                },

                -- ── 顶冠线脚（全宽，微凸出）─────────────────────
                { model = "Box",
                  yBottom = 0.97, yTop = 1.00,
                  xScale = 1.015, zScale = 1.015,
                  color = { 0.58, 0.53, 0.42 }, roughness = 0.82, metallic = 0.0,
                },

                -- ── 玻璃入口大厅（中央底部，覆盖虚空宽度）────────
                { model = "Box",
                  yBottom = 0.01, yTop = 0.14,
                  xScale = 0.26, zScale = 0.34,
                  color = { 0.28, 0.38, 0.50 }, roughness = 0.10, metallic = 0.65,
                },
            },
        },

    },
}
