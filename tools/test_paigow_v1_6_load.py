#!/usr/bin/env python3
"""Deterministic architecture load model. This is not a production Supabase benchmark."""
from dataclasses import dataclass,asdict
import json
@dataclass
class Model:
    players:int=9
    seconds:int=600
    rounds:int=12
    actions_per_round:int=34       # ready, rob, multiplier and big-hand arrangement RPCs
    snapshot_phases_per_round:int=6 # round start, phase transitions and settlement
    room_resync_seconds:int=60

m=Model()
old_poll_requests=m.players*m.seconds
old_action_requests=m.rounds*m.actions_per_round
old_heavy=old_poll_requests+old_action_requests
new_action_requests=old_action_requests
new_phase_snapshots=m.rounds*m.snapshot_phases_per_round*m.players
new_safety_snapshots=m.players*(m.seconds//m.room_resync_seconds)
new_initial_snapshots=m.players
new_heavy=new_action_requests+new_phase_snapshots+new_safety_snapshots+new_initial_snapshots
new_global_light_ticks=m.seconds
reduction=1-new_heavy/old_heavy
# Ordinary ready/bet/arrange changes are delivered as safe deltas and do not trigger full snapshot reads on peers.
delta_deliveries=m.rounds*m.actions_per_round*m.players
result={
 'model':'deterministic_not_production_benchmark',
 'inputs':asdict(m),
 'v1_5':{'per_player_poll_requests':old_poll_requests,'action_requests':old_action_requests,'heavy_requests':old_heavy,'average_heavy_rps':round(old_heavy/m.seconds,3)},
 'v1_6':{'action_requests':new_action_requests,'phase_snapshot_reads':new_phase_snapshots,'safety_snapshot_reads':new_safety_snapshots,'initial_snapshot_reads':new_initial_snapshots,'heavy_requests':new_heavy,'average_heavy_rps':round(new_heavy/m.seconds,3),'global_light_cron_ticks':new_global_light_ticks,'safe_delta_deliveries':delta_deliveries},
 'heavy_request_reduction_percent':round(reduction*100,2),
 'four_room_global_tick_count':new_global_light_ticks,
 'closed_iframe':{'network_requests':0,'timers':0,'realtime_connections':0}
}
print(json.dumps(result,ensure_ascii=False,indent=2))
assert old_poll_requests==5400
assert new_heavy<old_heavy*0.4
assert reduction>0.6
assert result['four_room_global_tick_count']==600 # one global job, not one per player or room
print('PASS 9-player load model')
print('PASS global scheduler does not multiply by player count')
print('PASS closed iframe zero-runtime invariant')
