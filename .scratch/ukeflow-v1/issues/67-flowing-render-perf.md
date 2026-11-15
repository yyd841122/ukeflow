# 67: 流水谱渲染性能——每帧整页重建与文本画笔生命周期

**What to build**(票65 F22/F23,审计源报告 .cc-suite/audits/):
1. 播放中每帧 setState 重建整页:传输控件/按法卡/总结行/painter 委托
   随帧重建,按法 painter 每帧新建并 layout 文本画笔。拆分:画布重绘
   与控件重建分离(播放位驱动画布,状态变化才重建控件)。
2. TextPainter 生命周期:页级 _textCache 清空与页 dispose 不 dispose
   画笔;按法 painter 临时文本画笔用后即弃无复用。显式 dispose + 按
   事件身份缓存。

**Blocked by:** None

**Status:** ready-for-agent

## Comments

- 2026-11-15: 建票(审计 D6 三条 Medium)。画像缓存机制已部分存在
  (_textCache),本票是补全不是重做。
