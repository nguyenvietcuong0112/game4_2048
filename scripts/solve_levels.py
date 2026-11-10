import copy
import json
import os
import sys
import time
import heapq
from collections import Counter

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
    __slots__ = ('id', 'col', 'row', 'cells', 'number', 'ice_target', 'movement')
    def __init__(self, pid, col, row, cells, number, ice_target, movement):
        self.id = pid
        self.col = col
        self.row = row
        self.cells = cells  # tuple of (dc, dr)
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
        pieces.append(Piece(pid, col, row, norm_cells, num, ice, mv))
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

def solve_level(cols, rows, walls, initial_pieces, max_visited=35000, timeout_sec=5.0):
    start_time = time.time()
    
    # 1. Quick static multiset check
    nums = [p.number for p in initial_pieces if p.number is not None]
    c = Counter(nums)
    while len(c) > 1 or (len(c) == 1 and list(c.values())[0] > 1):
        m = min(c.keys())
        cnt = c[m]
        if cnt % 2 != 0:
            return False, f"Impossible multiset: odd count {cnt} of min value {m}", 0, None
        del c[m]
        c[m * 2] += cnt // 2

    # 2. Check if already won
    numbered_init = sum(1 for p in initial_pieces if not p.is_dud)
    if numbered_init <= 1:
        return True, "Already won", 0, []

    start_canon = canonical_state(initial_pieces)
    visited = {start_canon}
    
    # Priority Queue: (h_score, moves_cost, tie_breaker, pieces, history)
    heap = []
    state_counter = 0
    h_init = compute_heuristic(initial_pieces)
    heapq.heappush(heap, (h_init, 0, state_counter, initial_pieces, []))

    while heap:
        if len(visited) > max_visited:
            return None, f"Exceeded max visited states ({max_visited})", 0, None
        if time.time() - start_time > timeout_sec:
            return None, f"Timed out ({timeout_sec}s)", 0, None

        h_val, moves, _, cur_pieces, history = heapq.heappop(heap)

        num_left = sum(1 for p in cur_pieces if not p.is_dud)
        if num_left <= 1:
            return True, "Solvable", moves, history

        # Fast occupancy map: dict (c, r) -> piece
        occ = {}
        for p in cur_pieces:
            for wc in p.world_cells():
                occ[wc] = p

        # Separate potential merges from slides to prioritize merges!
        for i, p in enumerate(cur_pieces):
            if not p.can_move:
                continue

            cur_cells = set(p.world_cells())
            for dx, dy in get_allowed_dirs(p.movement):
                target_wc = [(c + dx, r + dy) for c, r in cur_cells]

                # Check bounds & walls
                if any(c < 0 or c >= cols or r < 0 or r >= rows or (c, r) in walls for c, r in target_wc):
                    continue

                # Check overlapping other pieces
                overlapping = set()
                for c in target_wc:
                    if c in occ:
                        other = occ[c]
                        if other.id != p.id:
                            overlapping.add(other)

                if len(overlapping) == 0:
                    # Slide move
                    new_pieces = []
                    for idx, op in enumerate(cur_pieces):
                        if idx == i:
                            new_pieces.append(Piece(op.id, op.col + dx, op.row + dy, op.cells, op.number, op.ice_target, op.movement))
                        else:
                            new_pieces.append(Piece(op.id, op.col, op.row, op.cells, op.number, op.ice_target, op.movement))
                    c_state = canonical_state(new_pieces)
                    if c_state not in visited:
                        visited.add(c_state)
                        state_counter += 1
                        h_new = compute_heuristic(new_pieces) + (moves + 1)
                        move_desc = f"Slide P{p.id}({p.number}) to ({p.col+dx},{p.row+dy})"
                        heapq.heappush(heap, (h_new, moves + 1, state_counter, new_pieces, history + [move_desc]))

                elif len(overlapping) == 1:
                    # Merge move
                    target_p = list(overlapping)[0]
                    if p.can_merge and target_p.can_merge and p.number == target_p.number:
                        new_number = p.number * 2
                        combined_mv = resolve_movement(p.movement, target_p.movement)

                        if target_p.movement == 'pinned' and len(target_p.cells) < len(p.cells):
                            survivor_id = p.id
                            survivor_col = p.col + dx
                            survivor_row = p.row + dy
                            survivor_cells = p.cells
                        else:
                            survivor_id = target_p.id
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
                            new_pieces.append(Piece(op.id, op.col, op.row, op.cells, op.number, ice, op.movement))

                        new_pieces.append(Piece(survivor_id, survivor_col, survivor_row, survivor_cells, new_number, None, combined_mv))
                        c_state = canonical_state(new_pieces)
                        if c_state not in visited:
                            visited.add(c_state)
                            state_counter += 1
                            # Huge bonus for merges: subtract 150 from heuristic so merges are explored first!
                            h_new = compute_heuristic(new_pieces) + (moves + 1) - 150
                            merge_desc = f"Merge P{p.id}({p.number}) + P{target_p.id}({target_p.number}) -> {new_number}"
                            heapq.heappush(heap, (h_new, moves + 1, state_counter, new_pieces, history + [merge_desc]))

    return False, "Exhausted all reachable states without winning (Deadlock / Unwinnable)", 0, None
