# 流水谱跟练(flowing-score)

一手数据流水谱:《天空之城》端到端已落地(2026-11-08/09,方向见
`docs/adr/0012`,参照实现 codex `E:\codexProjects\musicScore` 只读)。

## 已落地(回归闸守护)

- 一手数据转换器 `lib/core/score/reference_score.dart`(守门断言全保留);
  真值回归闸 `test/reference_score_test.dart`(51/317/557/152.8536585s);
- 时间映射 `FlowingLayout`(全曲匀速等宽零留白) + 排版层
  `FlowingEngraving`(字形一次算清)+ 哑渲染器(光晕打洞,排版/绘制分离);
- 示范声调度 `FlowingNoteScheduler`(playScheduled 绝对时刻,延音不重拨);
- 跟练控制器 `FlowingPracticeController`(play/pause/seek/曲末);
- 页面 `flowing_score_page.dart`(固定红线/当弹红/休止/和弦图/段落名/曲头标记);
- 慢放三档 0.5/0.75/1.0(票01,2026-11-10):速度只缩时间轴,排版几何
  不动;播放中即切、位置连续;0.5 倍整曲真机零漂移。

## 未落地(工单)

- AB 选段循环、数四下、琴声/节拍器分开开关、按法提示(当前+下一步)、
  练习记录——练琴功能余五件;
- 在线获取链路并入(ADR-0012;运输形态待定,见工单);
- 换歌体检流程(守门已就绪,缺流程页与元数据接入)。

## 已搁置(重启须单独决策)

- PDF 识谱线、矢量谱页线(ADR-0012;样本/校对台资产保留)。
