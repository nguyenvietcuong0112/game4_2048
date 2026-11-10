import json
import subprocess
import sys
import time
from collections import Counter
import heapq

def resolve_movement(m1, m2):
    h = (m1 in ('free', 'horizontal')) or (m2 in ('free', 'horizontal'))
    v = (m1 in ('free', 'vertical')) or (m2 in ('free', 'vertical'))
    if h and v:
        return 'free'
    if h:
        return 'horizontal'
    if v:
        return 'vertical'
    return 'pinned'

class Piece:
    __slots__ = ('id', 'key', 'col', 'row', 'cells', 'number', 'ice_target', 'movement')
    def __init__(self, pid, key, col, row, cells, number, ice_target, movement):
        self.id = pid
        self.key = key
        self.col = col
        self.row = row
        self.cells = cells
        self.number = number
        self.ice_target = ice_target
        self.movement = movement

    @property
    def is_dud(self):
        return self.number is None

    @property
    def is_frozen(self):
        return self.ice_target is not None

    @property
    def can_move(self):
        return not self.is_frozen and self.movement != 'pinned'

    @property
    def can_merge(self):
        return not self.is_dud and not self.is_frozen

    def world_cells(self, c=None, r=None):
        if c is None: c = self.col
        if r is None: r = self.row
        return [(c + dc, r + dr) for dc, dr in self.cells]

    def to_state_tuple(self):
        return (self.col, self.row, self.cells, self.number, self.ice_target, self.movement)

def parse_level(layout_json):
    cols = layout_json['cols']
    rows = layout_json['rows']
    walls = set((w[0], w[1]) for w in layout_json.get('walls', []))
    pieces = []
    pid = 1
    for s in layout_json['shapes']:
        raw_cells = s.get('cells', [[0, 0]])
        min_c = min(c[0] for c in raw_cells)
        min_r = min(c[1] for c in raw_cells)
        norm_cells = tuple(sorted((c[0] - min_c, c[1] - min_r) for c in raw_cells))
        col = s['col'] + min_c
        row = s['row'] + min_r
        num = s.get('number')
        ice = s.get('iceTarget')
        if s.get('pinned') or s.get('movement') == 'none':
            mv = 'pinned'
        elif s.get('movement') == 'horizontal':
            mv = 'horizontal'
        elif s.get('movement') == 'vertical':
            mv = 'vertical'
        else:
            mv = 'free'
        pieces.append(Piece(pid, s.get('key', f'P{pid}'), col, row, norm_cells, num, ice, mv))
        pid += 1
    return cols, rows, walls, pieces

def get_allowed_dirs(movement):
    if movement == 'horizontal':
        return ((1, 0), (-1, 0))
    elif movement == 'vertical':
        return ((0, 1), (0, -1))
    elif movement == 'free':
        return ((1, 0), (-1, 0), (0, 1), (0, -1))
    return ()

def check_multiset_parity(pieces):
    nums = [p.number for p in pieces if p.number is not None]
    c = Counter(nums)
    while len(c) > 1 or (len(c) == 1 and list(c.values())[0] > 1):
        m = min(c.keys())
        cnt = c[m]
        if cnt % 2 != 0:
            return False, f"Lỗi số học: số nhỏ nhất {m} có số lượng lẻ ({cnt}), không bao giờ ghép hết được!"
        del c[m]
        c[m * 2] += cnt // 2
    return True, "OK"

def check_ice_deadlock(pieces):
    unfrozen_nums = [p.number for p in pieces if p.number is not None and not p.is_frozen]
    frozen = [(p.number, p.ice_target) for p in pieces if p.is_frozen]
    if not frozen:
        return True, "Không có khối băng"

    avail = Counter(unfrozen_nums)
    unlocked_any = True
    unlocked_targets = set()
    while unlocked_any:
        unlocked_any = False
        produced_numbers = set()
        c = Counter(avail)
        changed = True
        while changed:
            changed = False
            for k in list(c.keys()):
                if c[k] >= 2:
                    produced_numbers.add(k * 2)
                    c[k * 2] = c.get(k * 2, 0) + c[k] // 2
                    c[k] = c[k] % 2
                    changed = True

        new_frozen = []
        for num, target in frozen:
            if target in produced_numbers or target in unlocked_targets:
                unlocked_any = True
                unlocked_targets.add(target)
                if num:
                    avail[num] += 1
            else:
                new_frozen.append((num, target))
        frozen = new_frozen

    if frozen:
        targets = [t for _, t in frozen]
        return False, f"Deadlock băng: không thể tạo ra số để mở khóa băng các mục tiêu {targets}"
    return True, "OK"

def check_pinned_pairs(pieces):
    # Two pinned pieces with number X can only be unpinned if the rest of the board can produce another X!
    pinned_by_num = {}
    for p in pieces:
        if p.number is not None and p.movement == 'pinned':
            pinned_by_num.setdefault(p.number, []).append(p)
    
    for num, plist in pinned_by_num.items():
        if len(plist) >= 2:
            # Sum of all other numbers <= num on the board
            other_sum = sum(p.number for p in pieces if p.number is not None and p.number <= num and p not in plist)
            if other_sum < num:
                return False, f"Deadlock ghim (Pinned): Cả 2 khối số {num} đều bị ghim và phần còn lại của bàn cờ không đủ số để tạo thêm số {num} để gỡ ghim!"
    return True, "OK"

def check_zero_moves_deadlock(cols, rows, walls, pieces):
    occ = {}
    for p in pieces:
        for wc in p.world_cells():
            occ[wc] = p
    
    for p in pieces:
        if not p.can_move:
            continue
        cur_cells = set(p.world_cells())
        for dx, dy in get_allowed_dirs(p.movement):
            target_wc = [(c + dx, r + dy) for c, r in cur_cells]
            if any(c < 0 or c >= cols or r < 0 or r >= rows or (c, r) in walls for c, r in target_wc):
                continue
            overlapping = set(occ[c] for c in target_wc if c in occ and occ[c].id != p.id)
            if len(overlapping) == 0:
                return True, "OK"
            elif len(overlapping) == 1:
                other = list(overlapping)[0]
                if p.can_merge and other.can_merge and p.number == other.number:
                    return True, "OK"
            
    return False, "Bị kẹt cứng ngay từ đầu: 100% không có bất kỳ khối nào có thể di chuyển hay hợp nhất!"

def compute_heuristic(pieces):
    by_num = {}
    numbered_count = 0
    for p in pieces:
        if p.number is not None:
            numbered_count += 1
            by_num.setdefault(p.number, []).append(p)
    dist_sum = 0
    for num, plist in by_num.items():
        if len(plist) >= 2:
            min_d = 999
            for i in range(len(plist)):
                pi = plist[i]
                for j in range(i + 1, len(plist)):
                    pj = plist[j]
                    d = abs(pi.col - pj.col) + abs(pi.row - pj.row)
                    if d < min_d: min_d = d
            dist_sum += min_d
    return numbered_count * 200 + dist_sum

def canonical_state(pieces):
    return tuple(sorted(p.to_state_tuple() for p in pieces))

def solve_with_raycast(cols, rows, walls, initial_pieces, max_visited=60000, timeout_sec=3.5):
    start_time = time.time()
    start_canon = canonical_state(initial_pieces)
    visited = {start_canon}
    heap = []
    state_counter = 0
    h_init = compute_heuristic(initial_pieces)
    heapq.heappush(heap, (h_init, 0, state_counter, initial_pieces, []))

    while heap:
        if len(visited) > max_visited:
            return None, "SEARCH_LIMIT", 0, None
        if time.time() - start_time > timeout_sec:
            return None, "TIMEOUT", 0, None

        h_val, moves, _, cur_pieces, history = heapq.heappop(heap)
        num_left = sum(1 for p in cur_pieces if not p.is_dud)
        if num_left <= 1:
            return True, "SOLVED", moves, history

        occ = {}
        for p in cur_pieces:
            for wc in p.world_cells():
                occ[wc] = p

        for i, p in enumerate(cur_pieces):
            if not p.can_move:
                continue
            cur_cells = set(p.world_cells())
            
            for dx, dy in get_allowed_dirs(p.movement):
                step = 1
                while True:
                    target_wc = [(c + step * dx, r + step * dy) for c, r in cur_cells]
                    if any(c < 0 or c >= cols or r < 0 or r >= rows or (c, r) in walls for c, r in target_wc):
                        break

                    overlapping = set(occ[c] for c in target_wc if c in occ and occ[c].id != p.id)

                    if len(overlapping) == 0:
                        # Slide move
                        new_pieces = []
                        for idx, op in enumerate(cur_pieces):
                            if idx == i:
                                new_pieces.append(Piece(op.id, op.key, op.col + step * dx, op.row + step * dy, op.cells, op.number, op.ice_target, op.movement))
                            else:
                                new_pieces.append(Piece(op.id, op.key, op.col, op.row, op.cells, op.number, op.ice_target, op.movement))
                        c_state = canonical_state(new_pieces)
                        if c_state not in visited:
                            visited.add(c_state)
                            state_counter += 1
                            h_new = compute_heuristic(new_pieces) + (moves + 1)
                            heapq.heappush(heap, (h_new, moves + 1, state_counter, new_pieces, history + [f"Slide {p.key} to ({p.col+step*dx},{p.row+step*dy})"]))
                        step += 1

                    elif len(overlapping) == 1:
                        target_p = list(overlapping)[0]
                        if p.can_merge and target_p.can_merge and p.number == target_p.number:
                            new_number = p.number * 2
                            combined_mv = resolve_movement(p.movement, target_p.movement)
                            if target_p.movement == 'pinned' and len(target_p.cells) < len(p.cells):
                                survivor_id, survivor_key = p.id, p.key
                                survivor_col = p.col + step * dx
                                survivor_row = p.row + step * dy
                                survivor_cells = p.cells
                            else:
                                survivor_id, survivor_key = target_p.id, target_p.key
                                survivor_col = target_p.col
                                survivor_row = target_p.row
                                survivor_cells = target_p.cells

                            new_pieces = []
                            for op in cur_pieces:
                                if op.id == p.id or op.id == target_p.id:
                                    continue
                                ice = op.ice_target
                                if ice == new_number:
                                    ice = None
                                new_pieces.append(Piece(op.id, op.key, op.col, op.row, op.cells, op.number, ice, op.movement))

                            new_pieces.append(Piece(survivor_id, survivor_key, survivor_col, survivor_row, survivor_cells, new_number, None, combined_mv))
                            c_state = canonical_state(new_pieces)
                            if c_state not in visited:
                                visited.add(c_state)
                                state_counter += 1
                                # Major bonus for merges
                                h_new = compute_heuristic(new_pieces) + (moves + 1) - 150
                                heapq.heappush(heap, (h_new, moves + 1, state_counter, new_pieces, history + [f"Merge {p.key}({p.number}) + {target_p.key}({target_p.number}) -> {new_number}"]))
                        break
                    else:
                        break

    return False, "DEADLOCK: Không còn bất kỳ đường di chuyển/hợp nhất nào hợp lệ để thắng (Exhausted all reachable states)", 0, None

def analyze_all_levels(file_path):
    with open(file_path, 'r') as f:
        levels = json.load(f)

    print(f"================================================================================")
    print(f"BẮT ĐẦU PHÂN TÍCH TOÀN BỘ {len(levels)} LEVEL TRONG '{file_path}'")
    print(f"================================================================================\n")

    stuck_levels = []
    solved_levels = []
    timeout_levels = []

    start_all = time.time()
    for idx, lvl in enumerate(levels):
        num = lvl.get('number', idx + 1)
        lay = lvl['data']['layout_text_json']
        cols, rows, walls, pieces = parse_level(lay)

        # 1. Multiset parity check
        ok, reason = check_multiset_parity(pieces)
        if not ok:
            stuck_levels.append((num, reason, "Multiset Parity Error"))
            print(f"❌ Level {num:3d}: NGHẼN! ({reason})")
            continue

        # 2. Ice deadlock check
        ok, reason = check_ice_deadlock(pieces)
        if not ok:
            stuck_levels.append((num, reason, "Ice Deadlock"))
            print(f"❌ Level {num:3d}: NGHẼN! ({reason})")
            continue

        # 3. Pinned pair deadlock
        ok, reason = check_pinned_pairs(pieces)
        if not ok:
            stuck_levels.append((num, reason, "Pinned Pair Deadlock"))
            print(f"❌ Level {num:3d}: NGHẼN! ({reason})")
            continue

        # 4. Zero moves deadlock
        ok, reason = check_zero_moves_deadlock(cols, rows, walls, pieces)
        if not ok:
            stuck_levels.append((num, reason, "Zero Moves Jam"))
            print(f"❌ Level {num:3d}: NGHẼN! ({reason})")
            continue

        # 5. Full Raycast A* Graph Search
        t0 = time.time()
        res, reason, moves, _ = solve_with_raycast(cols, rows, walls, pieces, max_visited=60000, timeout_sec=3.0)
        dt = time.time() - t0
        if res is True:
            solved_levels.append((num, moves, dt))
            print(f"✅ Level {num:3d}: THÔNG SUỐT (Thắng trong {moves:2d} bước, {dt:.2f}s)")
        elif res is False:
            stuck_levels.append((num, reason, "Graph Deadlock"))
            print(f"❌ Level {num:3d}: NGHẼN! ({reason}) [{dt:.2f}s]")
        else:
            timeout_levels.append((num, reason, dt))
            print(f"⚠️ Level {num:3d}: CẦN KIỂM TRA THÊM ({reason}, {dt:.2f}s)")

    total_time = time.time() - start_all
    print(f"\n================================================================================")
    print(f"KẾT QUẢ TỔNG HỢP ({total_time:.1f}s):")
    print(f"  - Tổng số level: {len(levels)}")
    print(f"  - Level THÔNG SUỐT (Đã chứng minh 100% có đường thắng): {len(solved_levels)}")
    print(f"  - Level BỊ NGHẼN (Đã chứng minh 100% DEADLOCK / UNWINNABLE): {len(stuck_levels)}")
    print(f"  - Level Search Limit (Cần thêm bước tìm kiếm): {len(timeout_levels)}")
    print(f"================================================================================")
    if stuck_levels:
        print("\nDANH SÁCH CHI TIẾT CÁC LEVEL BỊ NGHẼN:")
        for num, reason, cat in stuck_levels:
            print(f"  * Level {num:3d} [{cat}]: {reason}")
    print(f"================================================================================")

    return stuck_levels, solved_levels, timeout_levels

if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'assets/levels/all_121_levels.json'
    analyze_all_levels(path)
