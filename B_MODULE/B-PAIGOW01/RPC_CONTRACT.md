# B-PAIGOW01 RPC契约

## 已在候选SQL提供

- `get_paigow_lobby_bpaigow01()`：四房、角色资源、现有赌场资金。
- `create_paigow_room_bpaigow01(...)`：创建天地玄黄房。
- `join_paigow_room_bpaigow01(...)`：选座或观战。
- `leave_paigow_room_bpaigow01(...)`。
- `get_paigow_room_state_bpaigow01(...)`。
- `set_paigow_ready_bpaigow01(...)`。
- `paigow_take_player_fee_bpaigow01(...)`：仅服务端内部调用，精确累计2.5%。
- `paigow_settle_laohe_one_bpaigow01(...)`：仅服务端内部调用，100∶100接入现有赌场资金。

## A线正式接入必须补齐并原子化

- `start_paigow_round_bpaigow01(room_id, request_id)`：服务端安全洗牌、私牌遮罩、阶段截止时间。
- `choose_paigow_rob_bpaigow01(room_id, rob, request_id)`：10秒抢庄。
- `choose_paigow_multiplier_bpaigow01(room_id, multiplier, request_id)`：10/50/100与超时10倍。
- `arrange_paigow_big_bpaigow01(room_id, head_indices, request_id)`：30秒、弱头强尾校验。
- `advance_paigow_round_bpaigow01(room_id)`：按服务器时间推进开头、10秒、开尾。
- `settle_paigow_round_bpaigow01(room_id, request_id)`：整桌一次事务结算，失败全回滚。

所有RPC必须使用 `casino_secure_random_int_v1`，客户端不得获得其他玩家私牌、牌堆顺序或随机种子。
