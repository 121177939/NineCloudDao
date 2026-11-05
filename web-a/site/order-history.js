/** Supabase history view: hide duplicate parent cards when an executable child exists. */
export const parentType = selection => ({arrange:'排列五',seven:'七星彩',both:'排列五＋七星彩'}[selection]||'未知彩种');
export const parentState = state => ({finished:'已完成',cancelled:'已取消 · 未执行',reviewed_closed:'人工核实后关闭'}[state]||'状态未知');
export function historyOnlyParents(orders, tasks) {
  const childIds=new Set((Array.isArray(tasks)?tasks:[]).map(x=>x?.id).filter(Boolean));
  return (Array.isArray(orders)?orders:[]).filter(order=>
    ['finished','cancelled','reviewed_closed'].includes(order.state) &&
    !childIds.has(order.id) && !(order.second_task_id && childIds.has(order.second_task_id)));
}
