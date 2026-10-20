/** History presentation helpers aligned with Android A's showHistoryDetail().
 * Read-only presentation only: these helpers never mutate cloud task state.
 */
const text = value => typeof value === 'string' ? value : '';

function decodeScreenshotMode(command) {
  if (!command.startsWith('M1|')) return { mixed: false, mode: null, scatterOnly: false, hasScatter: false };
  const modeMatch = command.match(/(?:^|\|)R=([0-4])(?:\||$)/);
  const tIndex = command.indexOf('|T=');
  const suitePayload = tIndex >= 0 ? command.slice(tIndex + 3).split('|', 1)[0].trim() : '';
  const scatterMatch = command.match(/^M1\|S=(.*?)\|T=/s);
  const scatterCommand = scatterMatch?.[1] ?? '';
  return {
    mixed: true,
    mode: modeMatch ? Number(modeMatch[1]) : null,
    scatterOnly: suitePayload === '',
    hasScatter: scatterCommand.trim() !== ''
  };
}

/** Match Android A's result_path/scatter_path/suite_path selection rules. */
export function planHistoryArtifacts(record, stopRows = []) {
  const command = text(record?.command);
  const mode = decodeScreenshotMode(command);
  const resultPath = text(record?.result_path);
  const storedScatterPath = text(record?.scatter_path);
  const storedSuitePath = text(record?.suite_path);
  let scatterPath = '';

  if (mode.mixed && mode.scatterOnly) {
    // Pure scatter with an explicit M1 wrapper (e.g. conversion odds) still uses result_path.
    scatterPath = resultPath;
  } else if (mode.mixed) {
    scatterPath = storedScatterPath || ([0, 4].includes(mode.mode) ? resultPath : '');
  } else {
    // Legacy Android tasks use result_path as the original receipt route.
    scatterPath = resultPath;
  }

  let scatterTitle = '散码小票';
  if (mode.mixed && mode.mode === 0) scatterTitle = '散码 + 套码合并小票';
  if (mode.mixed && mode.mode === 4) {
    scatterTitle = mode.hasScatter ? '散码主页统一截图（散码+套码）' : '散码主页统一截图（套码）';
  }
  const suiteTitle = mode.mixed && mode.mode === 3 ? '套码下注页截图' : '套码成功日志摘录';
  const planned = [];
  const seenPaths = new Set();
  const add = (path, title, kind) => {
    if (!path || seenPaths.has(path)) return;
    seenPaths.add(path);
    planned.push({ path, title, kind });
  };

  add(scatterPath, scatterTitle, 'scatter');
  add(mode.mixed ? storedSuitePath : '', suiteTitle, 'suite');
  for (const stop of Array.isArray(stopRows) ? stopRows : []) {
    const path = text(stop?.screenshot_path);
    const title = text(stop?.phase) === 'reviewed'
      ? '人工核实记录 · 已结案截图'
      : '执行中终止 · 终止前原始截图';
    add(path, title, 'stop');
  }
  return planned;
}

export function historyCardPresentation(status, message = '') {
  switch (text(status)) {
    case 'finished':
      return { label: '已完成', tone: 'success', summary: '核验完成，可到历史查看截图' };
    case 'cancelled':
      return { label: '已取消', tone: 'danger', summary: '任务已取消，点击查看历史记录' };
    case 'failed':
      return { label: '失败', tone: 'danger', summary: text(message).trim().slice(0, 120) || '任务失败，点击查看原因与回图' };
    case 'needs_review':
      return { label: '待核实', tone: 'warning', summary: '结果需要人工核对；禁止自动重发' };
    case 'partial':
      return { label: '部分完成', tone: 'warning', summary: '部分结果需要人工核对，点击查看详情' };
    case 'executing':
    case 'preparing':
    case 'confirmed':
      return { label: '执行中', tone: 'warning', summary: '点击查看任务进度、截图与核验记录' };
    case 'queued':
      return { label: '等待上一账号', tone: 'warning', summary: '任务仍在排队，点击查看任务详情' };
    case 'pending':
    case 'awaiting_confirm':
      return { label: '等待执行', tone: 'warning', summary: '点击查看任务详情与当前状态' };
    default:
      return { label: text(status) || '状态未知', tone: 'neutral', summary: '点击查看任务详情、截图与核验记录' };
  }
}

export function historyDetailStatus(status) {
  const map = {
    finished: '成功', failed: '失败', cancelled: '已取消', needs_review: '待人工核实',
    partial: '部分完成', executing: '执行中', preparing: '准备中', queued: '等待上一账号',
    pending: '等待执行', awaiting_confirm: '等待确认', confirmed: '已确认'
  };
  return map[text(status)] || text(status) || '未知';
}
