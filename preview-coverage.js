// Web A phase seven: audit-only UI grouping, never alters Kotlin/JS parse / wire amounts.
// A single original phrase may be deliberately split into several execution rows
// (e.g. 0336各88组 -> 0336-50 + 0336-38). Preserve all slices in filtered views.
export function expandLinkedReviewRows(rows, isVisible) {
  const input = Array.isArray(rows) ? rows : [];
  const selected = new Set(input.filter(isVisible).map(row => String(row.number)));
  return input.filter(row => selected.has(String(row.number)));
}
export function describeSplitExecutions(rows) {
  const groups = new Map();
  for (const row of Array.isArray(rows) ? rows : []) {
    const number = String(row.number || '');
    if (!number) continue;
    if (!groups.has(number)) groups.set(number, []);
    groups.get(number).push(row);
  }
  const output=[];
  for (const [number, matches] of groups) {
    // Never claim two actions came from the same source, unless the audit
    // mapper failed to independently locate at least one action.
    if (matches.length < 2 || matches.every(x => x.matched)) continue;
    const parts=matches.map(x=>x.amountText||'金额未知');
    output.push(`${number} 的 ${matches.length} 条执行项：${parts.join(' + ')}。这是原识别引擎的拆单/重复结果，请对照完整原文，勿只核对其中一项。`);
  }
  return output;
}
