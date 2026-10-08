# 采用 chord_pro 解析器，并自建谱面校验层

采用 chord_pro 0.8.0（MIT、纯 Dart、ChordPro 6、零依赖）。Spike C 实证其三个语义，直接影响 UkeFlow 的对策：(1) Chord.root 只含根音字母，quality 分离存储；(2) {transpose: n} 指令不改动 token 流，移调必须显式调 song.transposed(n)——UkeFlow 统一走显式移调；(3) 解析器极其宽容（未知指令静默、未闭合段落静默、几乎不产生 error 诊断）。因此谱面语法校验（段落闭合、和弦名合法性）是 UkeFlow 自己的责任，不指望解析器报错；导入路径的曲谱必须过自建校验后才能入库。
