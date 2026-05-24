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
                    color = { 0.78, 0.72, 0.60 }, roughness = 0.84, metallic = 0.0,
                },
                {   -- 主体（奶白石材）
                    yBottom = 0.11, yTop = 0.76,
                    xScale = 1.00, zScale = 1.00,
                    color = { 0.93, 0.89, 0.78 }, roughness = 0.72, metallic = 0.0,
                },
                {   -- 主檐线脚（挑出）
                    yBottom = 0.74, yTop = 0.83,
                    xScale = 1.12, zScale = 1.12,
                    color = { 0.83, 0.77, 0.65 }, roughness = 0.75, metallic = 0.0,
                },
                {   -- 法式孟莎屋顶（深石板灰）
                    yBottom = 0.81, yTop = 1.00,
                    xScale = 1.16, zScale = 1.16,
                    color = { 0.17, 0.15, 0.13 }, roughness = 0.88, metallic = 0.03,
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
                    color = { 0.60, 0.55, 0.44 }, roughness = 0.84, metallic = 0.0,
                },

                -- ── 主体立面（砂黄石材）────────────────────────
                {   model = "Box",
                    yBottom = 0.08, yTop = 0.70,
                    xScale = 1.00, zScale = 1.00,
                    color = { 0.84, 0.77, 0.60 }, roughness = 0.72, metallic = 0.0,
                },

                -- ── 中层腰线──────────────────────────────────
                {   model = "Box",
                    yBottom = 0.38, yTop = 0.44,
                    xScale = 1.04, zScale = 1.04,
                    color = { 0.72, 0.66, 0.52 }, roughness = 0.78, metallic = 0.0,
                },

                -- ── 主檐口────────────────────────────────────
                {   model = "Box",
                    yBottom = 0.65, yTop = 0.73,
                    xScale = 1.06, zScale = 1.06,
                    color = { 0.68, 0.62, 0.50 }, roughness = 0.80, metallic = 0.0,
                },

                -- ── 红色坡屋顶：左翼（offsetZ=-13m）────────────
                {   model = "Box",
                    yBottom = 0.70, yTop = 0.90,
                    xScale = 0.96, zScale = 0.46,
                    offsetZ = -13.0,
                    color = { 0.62, 0.14, 0.08 }, roughness = 0.70, metallic = 0.0,
                },
                -- ── 红色坡屋顶：右翼（offsetZ=+13m）────────────
                {   model = "Box",
                    yBottom = 0.70, yTop = 0.90,
                    xScale = 0.96, zScale = 0.46,
                    offsetZ = 13.0,
                    color = { 0.62, 0.14, 0.08 }, roughness = 0.70, metallic = 0.0,
                },
                -- ── 红色坡屋顶：中央（略高）──────────────────
                {   model = "Box",
                    yBottom = 0.70, yTop = 0.94,
                    xScale = 0.94, zScale = 0.34,
                    offsetZ = 0.0,
                    color = { 0.60, 0.13, 0.08 }, roughness = 0.68, metallic = 0.0,
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
                    color = { 0.80, 0.73, 0.58 }, roughness = 0.74, metallic = 0.0,
                },
                -- ── 中央大半球（直径 8m）──────────────────────
                {   model = "Hemisphere",
                    yBottom = 0.98, yTop = 1.36,
                    absSize = 8.0,
                    offsetZ = 0.0,
                    color = { 0.58, 0.12, 0.07 }, roughness = 0.60, metallic = 0.05,
                },

                -- ── 左侧穹顶鼓座（直径 5m，offsetZ=-12m）───────
                {   model = "Cylinder",
                    yBottom = 0.88, yTop = 0.97,
                    absSize = 5.0,
                    offsetZ = -12.0,
                    color = { 0.78, 0.71, 0.57 }, roughness = 0.76, metallic = 0.0,
                },
                -- ── 左侧小半球（直径 5m）──────────────────────
                {   model = "Hemisphere",
                    yBottom = 0.96, yTop = 1.19,
                    absSize = 5.0,
                    offsetZ = -12.0,
                    color = { 0.56, 0.11, 0.07 }, roughness = 0.62, metallic = 0.05,
                },

                -- ── 右侧穹顶鼓座（直径 5m，offsetZ=+12m）───────
                {   model = "Cylinder",
                    yBottom = 0.88, yTop = 0.97,
                    absSize = 5.0,
                    offsetZ = 12.0,
                    color = { 0.78, 0.71, 0.57 }, roughness = 0.76, metallic = 0.0,
                },
                -- ── 右侧小半球（直径 5m）──────────────────────
                {   model = "Hemisphere",
                    yBottom = 0.96, yTop = 1.19,
                    absSize = 5.0,
                    offsetZ = 12.0,
                    color = { 0.56, 0.11, 0.07 }, roughness = 0.62, metallic = 0.05,
                },
            },
        },

    },
}
