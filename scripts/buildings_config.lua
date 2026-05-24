-- ============================================================
--  buildings_config.lua  —  建筑类型配置
--
--  相当于 assets/buildings.json 的 Lua 版本，数据完全等价。
--  在此文件中新增建筑类型时，请同步更新 assets/buildings.json（注释版）。
--
--  每个建筑类型字段说明：
--    tier      "short"（近岸矮楼）| "tall"（远岸高层）
--    spanZ     沿赛道方向宽度（m）
--    spanX     垂直赛道方向深度（m）
--    heightMin / heightMax  随机高度范围（m）
--    parts[]:  构件数组
--      yBottom / yTop    该构件在建筑高度中的比例区间 [0, 1]
--      xScale / zScale   构件相对 spanX / spanZ 的缩放（>1 即挑出、挑檐）
--      color             { r, g, b }  PBR 基色，范围 [0, 1]
--      roughness         粗糙度 [0, 1]
--      metallic          金属度 [0, 1]
-- ============================================================

return {
    types = {

        -- ────────────────────────────────────────────────────
        --  玻璃幕墙写字楼（高层）
        -- ────────────────────────────────────────────────────
        glass_tower = {
            tier      = "tall",
            spanZ     = 20,
            spanX     = 20,
            heightMin = 50,
            heightMax = 88,
            parts = {
                {   -- 混凝土基座（略宽于主体，裙楼效果）
                    yBottom = 0.00, yTop = 0.06,
                    xScale  = 1.08, zScale = 1.08,
                    color   = { 0.50, 0.47, 0.43 },
                    roughness = 0.80, metallic = 0.0,
                },
                {   -- 玻璃幕墙主体（蓝灰反射玻璃）
                    yBottom = 0.00, yTop = 0.88,
                    xScale  = 1.00, zScale = 1.00,
                    color   = { 0.30, 0.50, 0.70 },
                    roughness = 0.08, metallic = 0.88,
                },
                {   -- 顶冠（深色玻璃收头，略内缩）
                    yBottom = 0.88, yTop = 1.00,
                    xScale  = 0.80, zScale = 0.80,
                    color   = { 0.15, 0.25, 0.42 },
                    roughness = 0.05, metallic = 0.95,
                },
            },
        },

        -- ────────────────────────────────────────────────────
        --  欧式风格小楼（近岸矮楼）
        -- ────────────────────────────────────────────────────
        european_house = {
            tier      = "short",
            spanZ     = 16,
            spanX     = 12,
            heightMin = 12,
            heightMax = 22,
            parts = {
                {   -- 欧式楼体（奶油色石材）
                    yBottom = 0.00, yTop = 0.82,
                    xScale  = 1.00, zScale = 1.00,
                    color   = { 0.88, 0.80, 0.64 },
                    roughness = 0.75, metallic = 0.0,
                },
                {   -- 挑檐线脚（略宽，颜色略深）
                    yBottom = 0.80, yTop = 0.90,
                    xScale  = 1.08, zScale = 1.08,
                    color   = { 0.78, 0.70, 0.56 },
                    roughness = 0.78, metallic = 0.0,
                },
                {   -- 深色坡屋顶（向外出挑）
                    yBottom = 0.88, yTop = 1.00,
                    xScale  = 1.14, zScale = 1.14,
                    color   = { 0.24, 0.20, 0.16 },
                    roughness = 0.85, metallic = 0.0,
                },
            },
        },

    },
}
