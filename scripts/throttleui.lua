-- ============================================================
--  throttleui.lua  —  底部仪表盘 UI（油门 + 耐久度）
--  两条进度条并排显示在屏幕底部中央
-- ============================================================
local C = require "config"
local S = require "state"
local U = require "utils"

local M = {}

-- ── 布局常量 ─────────────────────────────────────────────────
local PANEL_W  = 320   -- 整体面板宽
local PANEL_H  = 90    -- 整体面板高
local BAR_W    = 220   -- 进度条槽宽
local BAR_H    = 16    -- 进度条槽高
local LABEL_X  = 10    -- 标签左边距
local BAR_X    = 62    -- 进度条槽左边距
local PCT_X    = -8    -- 百分比文字右边距

local ROW1_Y   = -26   -- 第一行（油门）相对面板中心的 Y 偏移
local ROW2_Y   =  10   -- 第二行（耐久）相对面板中心的 Y 偏移

-- ── 节点引用 ─────────────────────────────────────────────────
local panelNode   = nil
local thFill      = nil   -- 油门填充条
local thPct       = nil   -- 油门百分比文字
local durFill     = nil   -- 耐久填充条
local durPct      = nil   -- 耐久百分比文字

-- ─────────────────────────────────────────────────────────────
--  颜色函数
-- ─────────────────────────────────────────────────────────────
-- 油门：蓝→绿→橙→红
local function ThrottleColor(t)
    if t < 0.33 then
        local k = t / 0.33
        return Color(0.1, 0.45 + 0.35 * k, 0.9 - 0.6 * k, 1.0)
    elseif t < 0.66 then
        local k = (t - 0.33) / 0.33
        return Color(0.8 * k, 0.8 - 0.3 * k, 0.3 - 0.3 * k, 1.0)
    else
        local k = (t - 0.66) / 0.34
        return Color(0.8 + 0.2 * k, 0.5 - 0.5 * k, 0.0, 1.0)
    end
end

-- 耐久：绿→黄→红（低血量高亮）
local function DurabilityColor(d)
    if d > 0.6 then
        local k = (d - 0.6) / 0.4
        return Color(1.0 - k, 0.85, 0.1, 1.0)          -- 黄→绿
    elseif d > 0.3 then
        local k = (d - 0.3) / 0.3
        return Color(1.0, 0.85 * k, 0.0, 1.0)           -- 橙→黄
    else
        local k = d / 0.3
        return Color(1.0, 0.25 * k, 0.0, 1.0)           -- 深红→橙红
    end
end

-- ─────────────────────────────────────────────────────────────
--  辅助：创建一行仪表（标签 + 槽 + 填充 + 数值）
--  返回 fillNode, pctText
-- ─────────────────────────────────────────────────────────────
local function MakeRow(parent, labelStr, offsetY, initColor)
    -- 标签
    local lbl = parent:CreateChild("Text")
    lbl:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 13)
    lbl:SetColor(Color(0.85, 0.85, 0.85, 1.0))
    lbl:SetText(labelStr)
    lbl:SetAlignment(HA_LEFT, VA_CENTER)
    lbl:SetPosition(IntVector2(LABEL_X, offsetY))

    -- 槽背景
    local barBg = parent:CreateChild("BorderImage")
    barBg:SetAlignment(HA_LEFT, VA_CENTER)
    barBg:SetSize(IntVector2(BAR_W, BAR_H))
    barBg:SetPosition(IntVector2(BAR_X, offsetY))
    barBg:SetColor(Color(0.12, 0.12, 0.12, 0.9))

    -- 填充条
    local fill = barBg:CreateChild("BorderImage")
    fill:SetAlignment(HA_LEFT, VA_CENTER)
    fill:SetSize(IntVector2(BAR_W - 4, BAR_H - 4))
    fill:SetPosition(IntVector2(2, 0))
    fill:SetColor(initColor)

    -- 数值文字
    local pct = parent:CreateChild("Text")
    pct:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 12)
    pct:SetColor(Color(1.0, 1.0, 1.0, 0.9))
    pct:SetText("100%")
    pct:SetAlignment(HA_RIGHT, VA_CENTER)
    pct:SetPosition(IntVector2(PCT_X, offsetY))

    return fill, pct
end

-- ─────────────────────────────────────────────────────────────
--  初始化
-- ─────────────────────────────────────────────────────────────
function M.Init()
    local root = ui:GetRoot()

    -- 面板背景
    panelNode = root:CreateChild("BorderImage")
    panelNode:SetAlignment(HA_CENTER, VA_BOTTOM)
    panelNode:SetSize(IntVector2(PANEL_W, PANEL_H))
    panelNode:SetPosition(IntVector2(0, -18))
    panelNode:SetColor(Color(0.0, 0.0, 0.0, 0.55))
    panelNode:SetPriority(100)

    -- 油门行
    thFill, thPct = MakeRow(panelNode, "油门", ROW1_Y, Color(0.2, 0.7, 0.3, 1.0))

    -- 耐久行
    durFill, durPct = MakeRow(panelNode, "耐久", ROW2_Y, Color(0.2, 0.85, 0.2, 1.0))

    U.LogInfo("[ThrottleUI] 初始化完毕（油门 + 耐久并排）")
end

-- ─────────────────────────────────────────────────────────────
--  每帧更新
-- ─────────────────────────────────────────────────────────────
function M.Update()
    if not thFill then return end

    -- ── 油门 ────────────────────────────────────────────────
    local t  = math.max(0, math.min(1, S.throttle))
    local tw = math.floor(t * (BAR_W - 4))
    thFill:SetSize(IntVector2(math.max(0, tw), BAR_H - 4))
    thFill:SetColor(ThrottleColor(t))
    thPct:SetText(string.format("%d%%", math.floor(t * 100 + 0.5)))

    -- ── 耐久 ────────────────────────────────────────────────
    local d  = math.max(0, math.min(1, S.durability))
    local dw = math.floor(d * (BAR_W - 4))
    durFill:SetSize(IntVector2(math.max(0, dw), BAR_H - 4))
    durFill:SetColor(DurabilityColor(d))
    durPct:SetText(string.format("%d%%", math.floor(d * 100 + 0.5)))

    -- 低血量时面板边框红色闪烁提示
    if d <= 0.25 then
        local flash = 0.5 + 0.5 * math.sin(time:GetElapsedTime() * 8.0)
        panelNode:SetColor(Color(0.35 * flash, 0.0, 0.0, 0.70))
    else
        panelNode:SetColor(Color(0.0, 0.0, 0.0, 0.55))
    end
end

function M.SetVisible(v)
    if panelNode then panelNode:SetVisible(v) end
end

return M
