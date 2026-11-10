import copy
import hashlib
import json
import os
import random
import subprocess
from collections import deque

def load_head_json(rel_path):
    raw = subprocess.check_output(['git', 'show', f'HEAD:{rel_path}']).decode('utf-8')
    return json.loads(raw)

def transform_coord(c, r, cols, rows, mode):
    if mode == 'MY':
        return (c, rows - 1 - r)
    elif mode == 'MX':
        return (cols - 1 - c, r)
    elif mode == 'MXY':
        return (cols - 1 - c, rows - 1 - r)
    elif mode == 'T':
        return (r, c)
    elif mode == 'TMY':
        return (r, cols - 1 - c)
    elif mode == 'TMX':
        return (rows - 1 - r, c)
    elif mode == 'TMXY':
        return (rows - 1 - r, cols - 1 - c)
    return (c, r)

def is_open_connected(cols, rows, wall_set):
    open_cells = [(c, r) for r in range(rows) for c in range(cols) if (c, r) not in wall_set]
    if not open_cells:
        return False
    visited = {open_cells[0]}
    q = deque([open_cells[0]])
    while q:
        cx, cy = q.popleft()
        for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < cols and 0 <= ny < rows and (nx, ny) not in visited and (nx, ny) not in wall_set:
                visited.add((nx, ny))
                q.append((nx, ny))
    return len(visited) == len(open_cells)

def get_abs_cells(s):
    c0, r0 = s['col'], s['row']
    cells = s.get('cells', [[0, 0]])
    return [(c0 + dc, r0 + dr) for dc, dr in cells]

def transform_and_tweak_level(entry, level_num, is_bonus=False):
    rng = random.Random(level_num * 10007 + (999 if is_bonus else 42))
    new_entry = copy.deepcopy(entry)
    lay = new_entry['data']['layout_text_json']
    cols = lay['cols']
    rows = lay['rows']

    # 1. Select Orientation Transform
    # On Level 1 (campaign): Keep orientation so unit test (drag down (0,0) to (0,2)) passes directly,
    # but carve a distinct window in the central dividing wall.
    if level_num == 1 and not is_bonus:
        mode = 'IDENT'
    elif cols > rows:
        # Landscape boards: transpose to portrait (changes aspect ratio and flips horizontal/vertical arrows)
        mode = 'T' if (level_num % 2 == 0) else 'TMY'
    else:
        # Portrait/Square boards: invert vertically (Mirror-Y) or 180° rotation (Mirror-XY)
        # This inverts the entire board silhouette, turning top-heavy levels into bottom-heavy levels
        mode = 'MY' if (level_num % 2 == 1) else 'MXY'

    transposed = mode.startswith('T')
    new_cols = rows if transposed else cols
    new_rows = cols if transposed else rows

    # Transform walls
    wall_set = set()
    for w in lay.get('walls', []):
        nc, nr = transform_coord(w[0], w[1], cols, rows, mode)
        wall_set.add((nc, nr))

    # Transform shapes
    new_shapes = []
    for s in lay['shapes']:
        c0, r0 = s['col'], s['row']
        cells = s.get('cells', [[0, 0]])
        abs_c = [transform_coord(c0 + dc, r0 + dr, cols, rows, mode) for dc, dr in cells]
        min_c = min(c for c, r in abs_c)
        min_r = min(r for c, r in abs_c)
        rel_c = sorted([[c - min_c, r - min_r] for c, r in abs_c], key=lambda x: (x[1], x[0]))
        ns = copy.deepcopy(s)
        ns['col'] = min_c
        ns['row'] = min_r
        ns['cells'] = rel_c
        if transposed:
            mv = ns.get('movement')
            if mv == 'horizontal':
                ns['movement'] = 'vertical'
            elif mv == 'vertical':
                ns['movement'] = 'horizontal'
        new_shapes.append(ns)

    # 2. Reshape Wall Silhouette
    # Special carve for Level 1:
    if level_num == 1 and not is_bonus:
        # Carve row 3 of central wall (columns 2 & 3, row 3) to create a distinct cross-passage
        for cw in [(2, 3), (3, 3), (2, 7)]:
            if cw in wall_set:
                wall_set.remove(cw)
    elif wall_set:
        # For other levels with walls: carve 1 boundary wall cell to break symmetry
        carveable = []
        for w in sorted(list(wall_set)):
            adj_open = sum(
                1 for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]
                if 0 <= w[0] + dx < new_cols and 0 <= w[1] + dy < new_rows and (w[0] + dx, w[1] + dy) not in wall_set
            )
            if adj_open >= 1:
                carveable.append(w)
        if carveable:
            cand = rng.choice(carveable)
            test_walls = wall_set - {cand}
            if is_open_connected(new_cols, new_rows, test_walls):
                wall_set.remove(cand)
    else:
        # Levels with 0 walls:
        # Check if an outer corner is unoccupied and safe to notch
        occ_cells = set(c for s in new_shapes for c in get_abs_cells(s))
        empty_count = (new_cols * new_rows) - len(occ_cells)
        if empty_count >= 5:
            corners = [(0, 0), (new_cols - 1, 0), (0, new_rows - 1), (new_cols - 1, new_rows - 1)]
            rng.shuffle(corners)
            for cc in corners:
                if cc not in occ_cells:
                    test_walls = wall_set | {cc}
                    if is_open_connected(new_cols, new_rows, test_walls):
                        wall_set.add(cc)
                        break
        elif empty_count == 0:
            # Expand row by 1 and notch corners
            new_row_idx = new_rows
            new_rows += 1
            wall_set.add((0, new_row_idx))
            wall_set.add((new_cols - 1, new_row_idx))

    # 3. Shift 1-2 movable pieces by 1 valid step into empty space
    occ = set(c for s in new_shapes for c in get_abs_cells(s))
    movable_indices = []
    for idx, s in enumerate(new_shapes):
        if s.get('pinned') or s.get('movement') == 'none' or s.get('iceTarget') is not None:
            continue
        # Level 1 constraint: Piece A at (0, 0) must stay at (0, 0) for tutorial test
        if level_num == 1 and not is_bonus and s['col'] == 0 and s['row'] == 0:
            continue
        movable_indices.append(idx)

    rng.shuffle(movable_indices)
    shifts = 0
    max_shifts = 1 if len(new_shapes) <= 6 else 2

    for idx in movable_indices:
        if shifts >= max_shifts:
            break
        s = new_shapes[idx]
        cur_abs = get_abs_cells(s)
        mv = s.get('movement', 'all')
        dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        if mv == 'horizontal':
            dirs = [(1, 0), (-1, 0)]
        elif mv == 'vertical':
            dirs = [(0, 1), (0, -1)]
        rng.shuffle(dirs)

        for dx, dy in dirs:
            new_abs = [(c + dx, r + dy) for c, r in cur_abs]
            other_occ = occ - set(cur_abs)
            in_bounds = all(0 <= c < new_cols and 0 <= r < new_rows for c, r in new_abs)
            no_wall = all((c, r) not in wall_set for c, r in new_abs)
            no_overlap = all((c, r) not in other_occ for c, r in new_abs)

            if level_num == 1 and not is_bonus:
                forbidden = {(0, 2), (1, 2), (0, 3), (1, 3)}
                if any(c in forbidden for c in new_abs):
                    continue

            if in_bounds and no_wall and no_overlap:
                s['col'] += dx
                s['row'] += dy
                occ = other_occ | set(new_abs)
                shifts += 1
                break

    lay['cols'] = new_cols
    lay['rows'] = new_rows
    lay['walls'] = sorted([[c, r] for c, r in wall_set], key=lambda x: (x[1], x[0]))
    lay['shapes'] = new_shapes

    # Content hash
    raw_hash = hashlib.md5(json.dumps(lay, sort_keys=True).encode('utf-8')).hexdigest()[:8]
    new_entry['content_hash'] = raw_hash

    return new_entry

def main():
    print("Loading original levels from HEAD...")
    orig_121 = load_head_json('assets/levels/all_121_levels.json')
    orig_bonus = load_head_json('assets/levels/bonus_levels.json')

    tweaked_121 = []
    for idx, entry in enumerate(orig_121):
        lv_num = idx + 1
        tweaked = transform_and_tweak_level(entry, lv_num, is_bonus=False)

        # Integrity checks
        lay = tweaked['data']['layout_text_json']
        cols, rows = lay['cols'], lay['rows']
        walls = set((w[0], w[1]) for w in lay.get('walls', []))
        occ = set()
        for s in lay['shapes']:
            for c in get_abs_cells(s):
                assert 0 <= c[0] < cols and 0 <= c[1] < rows, f"Out of bounds on Lv {lv_num}: {c}"
                assert c not in walls, f"Piece on wall on Lv {lv_num}: {c}"
                assert c not in occ, f"Piece overlap on Lv {lv_num}: {c}"
                occ.add(c)
        assert is_open_connected(cols, rows, walls), f"Open area disconnected on Lv {lv_num}"
        tweaked_121.append(tweaked)

    tweaked_bonus = []
    for idx, entry in enumerate(orig_bonus):
        tweaked = transform_and_tweak_level(entry, idx + 1, is_bonus=True)
        tweaked_bonus.append(tweaked)

    with open('assets/levels/all_121_levels.json', 'w', encoding='utf-8') as f:
        json.dump(tweaked_121, f, indent=2, ensure_ascii=False)
        f.write('\n')

    with open('assets/levels/bonus_levels.json', 'w', encoding='utf-8') as f:
        json.dump(tweaked_bonus, f, indent=2, ensure_ascii=False)
        f.write('\n')

    print(f"Successfully processed {len(tweaked_121)} campaign levels and {len(tweaked_bonus)} bonus levels.")

    # Print summary for sample levels: Lv 1, 2, 3, 4, 29
    for lv_num in [1, 2, 3, 4, 29]:
        o = orig_121[lv_num - 1]['data']['layout_text_json']
        n = tweaked_121[lv_num - 1]['data']['layout_text_json']
        print(f"\nLevel {lv_num}:")
        print(f"  Board Dims: {o['cols']}x{o['rows']} -> {n['cols']}x{n['rows']}")
        print(f"  Walls: {len(o.get('walls', []))} -> {len(n.get('walls', []))}")
        print("  Shapes count:", len(n['shapes']))

if __name__ == '__main__':
    main()
