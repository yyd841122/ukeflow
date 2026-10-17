#!/usr/bin/env python3
"""审计消化票收口检查:findings 无 open 行;票面 WP 行的发现编号并集覆盖 findings 全集。

用法: check-digest.py <findings.md> <ticket.md>
退出码: 0 = 通过;1 = 有缺口;2 = 用法错误。

规则:发现编号的**权威记录是票面的 WP 行**(`- **WP-…**…发现 <编号列表>…`),
评论里提及不算覆盖——并包/补修要改 WP 行本身。编号支持单点与 a-b 区间。
(工单 30 教训:WP 清单总和 48 ≠ findings 51,「全覆盖」声明靠评审子代理才纠出。)
"""
import re
import sys


def finding_ids(text):
    """findings 表的编号全集(行首 `| N |`)。"""
    return {int(x) for x in re.findall(r'^\| (\d+) \|', text, re.M)}


def open_rows(text):
    """仍为 open 的 findings 行。"""
    return [
        ln for ln in text.splitlines()
        if ln.lstrip().startswith('|') and '| open |' in ln
    ]


def expand(spec):
    """编号列表展开:逗号/顿号分隔,支持 a-b 区间。"""
    ids = set()
    for part in re.split(r'[,，、]+', spec.strip()):
        part = part.strip()
        m = re.fullmatch(r'(\d+)\s*[-–]\s*(\d+)', part)
        if m:
            a, b = int(m.group(1)), int(m.group(2))
            ids.update(range(a, b + 1))
        elif part.isdigit():
            ids.add(int(part))
    return ids


def ticket_covered_ids(text):
    """票面 WP 行声明的发现编号并集(只认 `- **WP…**…发现 <列表>` 行)。"""
    covered = set()
    for line in text.splitlines():
        if not re.match(r'\s*[-*]\s*\*\*WP', line):
            continue
        m = re.search(r'发现[：:\s]*([\d，,\s\-–]+)', line)
        if m:
            covered |= expand(m.group(1))
    return covered


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    with open(sys.argv[1], encoding='utf-8') as f:
        findings = f.read()
    with open(sys.argv[2], encoding='utf-8') as f:
        ticket = f.read()

    problems = []
    opens = open_rows(findings)
    if opens:
        problems.append(f'findings 仍有 {len(opens)} 行 open:')
        problems += [f'  {ln[:100]}' for ln in opens]

    all_ids = finding_ids(findings)
    covered = ticket_covered_ids(ticket)
    missing = sorted(all_ids - covered)
    ghost = sorted(covered - all_ids)
    if missing:
        problems.append(f'票面 WP 行未覆盖的 findings 编号: {missing}')
    if ghost:
        problems.append(f'WP 行引用但 findings 表不存在的编号: {ghost}')

    if problems:
        print('审计消化账目缺口:')
        print('\n'.join(problems))
        return 1
    print(f'账目核对通过:{len(all_ids)} 条发现,WP 行全覆盖,无 open 行。')
    return 0


if __name__ == '__main__':
    sys.exit(main())
