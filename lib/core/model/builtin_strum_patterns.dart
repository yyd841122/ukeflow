import 'strum_pattern.dart';

/// 内置节奏型集合（spec「节奏与速度约定」：4/4，下、下上、上下上等组合）。
/// 由易到难排列，首个为默认选中。
///
/// 槽位记法（每小节 8 槽）：拍 n 落槽 2(n-1)，半拍落槽 2(n-1)+1。
/// 「下 下上 上下上」即经典岛国节奏型：手全程连续摆动，
/// 拍 3 的下扫刻意空过（槽 4 空拍），故全部动作与摆动方向天然一致。
const builtinStrumPatterns = <StrumPattern>[
  StrumPattern(
    id: 'all-down',
    name: '下 下 下 下',
    slots: [
      StrumDirection.down, // 拍 1
      null,
      StrumDirection.down, // 拍 2
      null,
      StrumDirection.down, // 拍 3
      null,
      StrumDirection.down, // 拍 4
      null,
    ],
  ),
  StrumPattern(
    id: 'eighth-du',
    name: '下上 下上 下上 下上',
    slots: [
      StrumDirection.down, // 拍 1
      StrumDirection.up, // 1 &
      StrumDirection.down, // 拍 2
      StrumDirection.up, // 2 &
      StrumDirection.down, // 拍 3
      StrumDirection.up, // 3 &
      StrumDirection.down, // 拍 4
      StrumDirection.up, // 4 &
    ],
  ),
  StrumPattern(
    id: 'd-du-d-du',
    name: '下 下上 下 下上',
    slots: [
      StrumDirection.down, // 拍 1
      null,
      StrumDirection.down, // 拍 2
      StrumDirection.up, // 2 &
      StrumDirection.down, // 拍 3
      null,
      StrumDirection.down, // 拍 4
      StrumDirection.up, // 4 &
    ],
  ),
  StrumPattern(
    id: 'island',
    name: '下 下上 上下上',
    slots: [
      StrumDirection.down, // 拍 1
      null,
      StrumDirection.down, // 拍 2
      StrumDirection.up, // 2 &
      null, // 拍 3 空过（手照摆不触弦）
      StrumDirection.up, // 3 &
      StrumDirection.down, // 拍 4
      StrumDirection.up, // 4 &
    ],
  ),
];
