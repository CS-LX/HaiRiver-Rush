-- ============================================================
--  ui.lua  —  HUD、游戏结束界面
-- ============================================================
local S = require "state"
local U = require "utils"

local M = {}

function M.Init()
    S.uiRoot = ui:GetRoot()
    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")

    S.scoreText = S.uiRoot:CreateChild("Text")
    S.scoreText:SetFont(font, 28)
    S.scoreText:SetColor(Color(1.0, 1.0, 1.0))          -- 纯白，最大可读性
    S.scoreText:SetAlignment(HA_LEFT, VA_TOP)
    S.scoreText:SetPosition(IntVector2(20, 20))
    S.scoreText:SetText("得分: 0")

    S.coinText = S.uiRoot:CreateChild("Text")
    S.coinText:SetFont(font, 24)
    S.coinText:SetColor(Color(1.0, 0.88, 0.0))          -- 鲜亮金色
    S.coinText:SetAlignment(HA_LEFT, VA_TOP)
    S.coinText:SetPosition(IntVector2(20, 58))
    S.coinText:SetText("金币: 0")

    S.speedText = S.uiRoot:CreateChild("Text")
    S.speedText:SetFont(font, 22)
    S.speedText:SetColor(Color(0.4, 1.0, 1.0))          -- 亮青色，醒目
    S.speedText:SetAlignment(HA_RIGHT, VA_TOP)
    S.speedText:SetPosition(IntVector2(-20, 20))
    S.speedText:SetText("0 km/h")

    S.hintText = S.uiRoot:CreateChild("Text")
    S.hintText:SetFont(font, 18)
    S.hintText:SetColor(Color(1.0, 1.0, 0.5, 1.0))      -- 明黄，底部提示
    S.hintText:SetAlignment(HA_CENTER, VA_BOTTOM)
    S.hintText:SetPosition(IntVector2(0, -28))
    S.hintText:SetText("A/D 转向  ·  W 加速  ·  S 刹车")

    U.LogInfo("[UI] HUD 初始化完毕")
end

function M.Update(dt)
    if S.scoreText then S.scoreText:SetText("得分: " .. S.score) end
    if S.coinText  then S.coinText:SetText("金币: " .. S.coinCount) end
    if S.speedText then S.speedText:SetText(math.floor(S.speed * 3.6) .. " km/h") end

    if S.hintTimer > 0 then
        S.hintTimer = S.hintTimer - dt
        if S.hintText then
            S.hintText:SetOpacity(math.max(0, math.min(1, S.hintTimer)))
        end
    end
end

function M.ShowGameOver()
    S.gameOverRoot = S.uiRoot:CreateChild("BorderImage")
    S.gameOverRoot:SetAlignment(HA_CENTER, VA_CENTER)
    S.gameOverRoot:SetSize(IntVector2(440, 320))
    S.gameOverRoot:SetColor(Color(0.02, 0.08, 0.20, 0.90))

    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")

    local title = S.gameOverRoot:CreateChild("Text")
    title:SetFont(font, 44)
    title:SetColor(Color(1.0, 0.28, 0.18))
    title:SetAlignment(HA_CENTER, VA_TOP)
    title:SetPosition(IntVector2(0, 28))
    title:SetText("游戏结束")

    local info1 = S.gameOverRoot:CreateChild("Text")
    info1:SetFont(font, 26)
    info1:SetColor(Color(1, 1, 1))
    info1:SetAlignment(HA_CENTER, VA_TOP)
    info1:SetPosition(IntVector2(0, 96))
    info1:SetText("得分: " .. S.score .. "   金币: " .. S.coinCount)

    local info2 = S.gameOverRoot:CreateChild("Text")
    info2:SetFont(font, 20)
    info2:SetColor(Color(0.65, 0.88, 1.0))
    info2:SetAlignment(HA_CENTER, VA_TOP)
    info2:SetPosition(IntVector2(0, 148))
    info2:SetText(string.format("行驶距离: %.0f 米", S.distanceMeter))

    local restart = S.gameOverRoot:CreateChild("Text")
    restart:SetFont(font, 22)
    restart:SetColor(Color(0.25, 1.0, 0.55))
    restart:SetAlignment(HA_CENTER, VA_TOP)
    restart:SetPosition(IntVector2(0, 220))
    restart:SetText("[ 点击 / 按任意键 重新开始 ]")
end

function M.HideGameOver()
    if S.gameOverRoot then
        S.gameOverRoot:Remove()
        S.gameOverRoot = nil
    end
end

function M.ResetHint()
    S.hintTimer = 6.0
end

return M
