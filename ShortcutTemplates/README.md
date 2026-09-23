# 官方快捷指令模板

这两个模板是给 iOS 15 用户准备的稳定入口，不依赖“添加操作”搜索页是否正确展示参数行。

## 1. 图片直传版

文件：
- `ShortcutTemplates/xiaoxi-auto-bill-official.shortcut`

结构：
1. `截屏`
2. `小西记账自动记账`

用途：
- 最接近阿柴记账那种“两块结构”
- 第二步直接接收第一步截图输出

适用场景：
- 你的系统能正常把图片参数传给 `AutoBillLegacyIntent`

## 2. 文字兜底版

文件：
- `ShortcutTemplates/xiaoxi-auto-bill-text-fallback.shortcut`

结构：
1. `截屏`
2. `从图像中提取文本`
3. `小西记账自动记账`

用途：
- 当 iOS 15 不稳定传图片时，先走系统文字提取，再把文字传给 App

适用场景：
- 图片参数动作在编辑器里始终显示成单块
- 运行时日志里 `image=false`

## 推荐顺序

1. 先试图片直传版
2. 如果真机日志仍然是 `image=false`，改用文字兜底版

## 校验命令

```bash
python3 scripts/validate_shortcuts.py --profile auto-bill ShortcutTemplates/xiaoxi-auto-bill-official.shortcut
python3 scripts/validate_shortcuts.py --profile auto-bill ShortcutTemplates/xiaoxi-auto-bill-text-fallback.shortcut
```
