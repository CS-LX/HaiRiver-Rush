-- ============================================================
--  throttleui.lua  —  底部油门仪表盘 UI
--  显示当前油门开度（0~1），颜色随开度变化：蓝→绿→橙→红
-- ============================================================
local S = require "state"
local U = require "utils"

local M = {}

-- UI 节点引用
local contNode  = nil   -- 外层容器
local fillNode  = nil   -- 填充条
local pctText   = nil   -- 百分比文字

local CONT_W = 300
local CONT_H = 44
local BAR_W  = 210
local BAR_H  = 18

-- 根据油门值 t (0~1) 计算颜色：蓝→绿→橙→红
local function ThrottleColor(t)
    if t < 0.33 then
        local k = t / 0.33
        return Color(0.1 + 0.0*k, 0.45 + 0.35*k, 0.9 - 0.6*k, 1.0)  -- 蓝→绿
    elseif t < 0.66 then
        local k = (t - 0.33) / 0.33
        return Color(0.8*k, 0.8 - 0.3*k, 0.3 - 0.3*k, 1.0)           -- 绿→橙
    else
        local k = (t - 0.66) / 0.34
        return Color(0.8 + 0.2*k, 0.5 - 0.5*k, 0.0, 1.0)             -- 橙→红
    end
end

function M.Init()
    local root = ui:GetRoot()

    -- ── 外层容器（圆角矩形背景）───────────────────────────
    contNode = root:CreateChild("BorderImage")
    contNode:SetAlignment(HA_CENTER, VA_BOTTOM)
    contNode:SetSize(IntVector2(CONT_W, CONT_H))
    contNode:SetPosition(IntVector2(0, -68))
    contNode:SetColor(Color(0.0, 0.0, 0.0, 0.55))
    contNode:SetPriority(100)

    -- ── "油门" 标签（左侧）────────────────────────────────
    local label = contNode:CreateChild("Text")
    label:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 13)
    label:SetColor(Color(0.85, 0.85, 0.85, 1.0))
    label:SetText("油门")
    label:SetAlignment(HA_LEFT, VA_CENTER)
    label:SetPosition(IntVector2(10, 0))

    -- ── 填充条背景（深色槽）───────────────────────────────
    local barBg = contNode:CreateChild("BorderImage")
    barBg:SetAlignment(HA_LEFT, VA_CENTER)
    barBg:SetSize(IntVector2(BAR_W, BAR_H))
    barBg:SetPosition(IntVector2(48, 0))
    barBg:SetColor(Color(0.15, 0.15, 0.15, 0.9))

    -- ── 填充条（宽度随油门变化）───────────────────────────
    fillNode = barBg:CreateChild("BorderImage")
    fillNode:SetAlignment(HA_LEFT, VA_CENTER)
    fillNode:SetSize(IntVector2(0, BAR_H - 4))
    fillNode:SetPosition(IntVector2(2, 0))
    fillNode:SetColor(Color(0.2, 0.7, 0.3, 1.0))

    -- ── 百分比文字（右侧）────────────────────────────────
    pctText = contNode:CreateChild("Text")
    pctText:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 12)
    pctText:SetColor(Color(1.0, 1.0, 1.0, 0.9))
    pctText:SetText("25%")
    pctText:SetAlignment(HA_RIGHT, VA_CENTER)
    pctText:SetPosition(IntVector2(-8, 0))

    U.LogInfo("[ThrottleUI] 初始化完毕")
end

function M.Update()
    if not fillNode then return end
    local t = math.max(0, math.min(1, S.throttle))

    -- 填充条宽度
    local w = math.floor(t * (BAR_W - 4))
    fillNode:SetSize(IntVector2(w, BAR_H - 4))

    -- 填充条颜色
    fillNode:SetColor(ThrottleColor(t))

    -- 百分比文字
    pctText:SetText(string.format("%d%%", math.floor(t * 100 + 0.5)))
end

function M.SetVisible(v)
    if contNode then contNode:SetVisible(v) end
end

return M
