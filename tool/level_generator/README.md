# Block Order 2048 — Level Generator & Solver CLI

Tool chạy bằng **Dart thuần** (không cần Python hay chạy app Flutter) giúp:
1. **Sinh số lượng level tùy ý** theo nhịp độ khó sawtooth 10 màn (`easy` / `normal` / `hard` / `super_hard`) hoặc cố định theo từng combo mechanic (`Ice`, `Dud`, `Arrows`, `Pinned`, tổ hợp 2–3–4 mechanic).
2. **Kiểm chứng 100% có đường thắng** bằng **A\* Raycast Solver** khớp hoàn toàn luật va chạm/merge/mở băng của `BlockOrderGame` trong `lib/game/block_order_game.dart`.
3. **Lọc chất lượng tự động:** Loại bỏ màn lỗi số học 2048, deadlock băng/ghim, màn quá dễ (ít bước trượt), hoặc trùng `content_hash` với campaign hiện tại.
4. **Kiến trúc mở (`MechanicMutator`):** Dễ cắm thêm mechanic mới (như `NumberGate`, `Crate`, `Chain`, `Bomb`) trong [generator.dart](generator.dart) mà không cần viết lại lõi sinh bàn cờ.

---

## Cấu trúc thư mục
- [models.dart](models.dart): Model bàn cờ/khối, xuất JSON chuẩn format `assets/levels/all_121_levels.json`, và in bản đồ ASCII.
- [solver.dart](solver.dart): Kiểm tra tĩnh (parity, ice DAG, pinned pair) + A\* Raycast Solver khớp luật game.
- [generator.dart](generator.dart): Tạo 5 kiểu địa hình tường, 4 bộ hình polyomino, cây số 2048 tách cặp có khoảng cách, pipeline `MechanicMutator`, và cân chỉnh timer tự động.
- [generate_levels.dart](generate_levels.dart): CLI entrypoint.

---

## Cách sử dụng nhanh

### 1. Sinh thử ra file riêng + xem bản đồ ASCII
```powershell
dart run tool/level_generator/generate_levels.dart --count 10 --preview
```
File mặc định xuất ra: `assets/levels/generated_levels.json`.

### 2. Sinh số lượng tùy ý (ví dụ 178 màn từ Lv 123 → 300) và nối thẳng vào campaign
```powershell
dart run tool/level_generator/generate_levels.dart --count 178 --seed 2026 --append
```
> Khi dùng `--append`, tool tự động tạo bản sao lưu `assets/levels/all_121_levels.json.bak` trước khi ghi đè.

### 3. Sinh theo độ khó / tổ hợp mechanic cụ thể
```powershell
# 5 màn Super Hard đủ cả 4 mechanic, JSON format đẹp để review
dart run tool/level_generator/generate_levels.dart --count 5 --difficulty super_hard --mechanics all4 --pretty -o assets/levels/boss_pack.json

# 20 màn chỉ mix Ice + Dud
dart run tool/level_generator/generate_levels.dart --count 20 --difficulty hard --mechanics ice+dud
```

Các giá trị hợp lệ:
- `--difficulty`: `auto` (nhịp sawtooth 10 màn), `easy`, `normal`, `hard`, `super_hard`
- `--mechanics`: `auto`, `none`, `dud`, `ice`, `arrows`, `pinned`, `dud+arrows`, `ice+dud`, `dud+pinned`, `ice+arrows`, `ice+dud+arrows`, `ice+dud+pinned`, `dud+pinned+arrows`, `all4`

### 4. Kiểm tra solvability (Verify Mode) cho bất kỳ file level nào
```powershell
# Kiểm tra toàn bộ file vừa sinh (kèm in các bước giải)
dart run tool/level_generator/generate_levels.dart --verify assets/levels/generated_levels.json --show-steps

# Kiểm tra lại toàn bộ campaign gốc
dart run tool/level_generator/generate_levels.dart --verify assets/levels/all_121_levels.json
```

---

## Mở rộng thêm mechanic mới sau này
1. Thêm trường mới vào `GenPiece` hoặc `GenLevel` trong [models.dart](models.dart) (`toShapeJson` / `toLayoutJson`).
2. Tạo một class mới kế thừa `MechanicMutator` trong [generator.dart](generator.dart) và thêm vào danh sách `mutators` của `LevelGenerator`.
3. Cập nhật luật tương ứng trong `LevelSolver.solve()` ở [solver.dart](solver.dart) để đảm bảo mọi màn sinh ra vẫn được chứng minh 100% giải được.
