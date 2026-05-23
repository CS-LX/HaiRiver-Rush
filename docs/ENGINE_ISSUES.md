# UrhoX 引擎问题归纳

记录 HaiRiver Rush 开发过程中遇到的引擎层面问题，供后续开发参考。

---

## 目录

1. [透明物体被水面波纹扭曲](#1-透明物体被水面波纹扭曲)
2. [透明粒子在水面背景下变黑](#2-透明粒子在水面背景下变黑)

---

## 1. 透明物体被水面波纹扭曲

**发现版本**：开发早期  
**严重程度**：视觉缺陷（不影响逻辑）

### 现象

使用 `PBRNoTextureAlpha` 技术的半透明对象（如烟雾粒子）放置在水面上方时，会被 `SingleLayerWater` 的水波纹折射效果扭曲变形，看起来像被水面"吸附"或产生波纹状变形。

![示意](../assets/image/engine_issue_water_distortion.png)

### 原因分析

`SingleLayerWater.xml` 材质在渲染时会对屏幕上方区域进行折射采样（Refraction Pass），所有位于水面上方但处于透明渲染通道的物体都会被一并采样扭曲。

### 目前状态

**无完美解法**。以下是已验证的规避方案：

| 方案 | 效果 | 代价 |
|------|------|------|
| 改用 `NoTextureUnlit`（不透明） | 完全规避扭曲 | 失去透明效果 |
| 将透明物体抬高远离水面 | 减轻但不消除 | 位置受限 |
| 接受该 Bug | 仅影响贴近水面时 | — |

### 当前处理方式

水花粒子使用 `NoTextureUnlit`（不透明）规避渲染冲突；  
烟雾粒子使用 `PBRNoTextureAlpha`（半透明），位于船身上方约 1m 处，受波纹扭曲轻微但可接受。

---

## 2. 透明粒子在水面背景下变黑

**发现版本**：粒子特效开发阶段  
**严重程度**：严重视觉缺陷

### 现象

使用 `PBRNoTextureAlpha` 技术的粒子，只要屏幕空间中粒子背后有水面，粒子就会完全变黑，即使粒子在世界空间中位于水面以上也不例外。

### 原因分析

渲染通道顺序问题：`SingleLayerWater` 在自己的 Pass 中写入深度缓冲，`PBRNoTextureAlpha` 属于透明 Pass，渲染时读取深度值判断遮挡关系，导致水面"遮住"了背后的透明粒子，呈现为黑色。

本质是**屏幕空间深度冲突**，与世界空间的实际高度无关。

### 解决方案

改用 `Techniques/NoTextureUnlit.xml`（不透明，在几何 Pass 渲染），完全绕开深度冲突：

```lua
local mat = Material.new()
mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, 1.0)))
-- 注意：alpha 值无效，用 SetSizeAdd 负值让粒子缩小消失代替淡出
```

**粒子淡出替代方案**（因为不透明材质无法靠 alpha 淡出）：

```lua
-- 粒子尺寸随时间缩小至消失
fx:SetSizeAdd(-maxSize * 1.2)
```

### 影响范围

所有使用 `PBRNoTextureAlpha` 的粒子效果，且游戏场景中存在 `SingleLayerWater` 时均会触发。

---

*最后更新：2026-05-24*
