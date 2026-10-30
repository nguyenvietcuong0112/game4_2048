import 'dart:math' as math;
import 'dart:ui';
import '../models/level_models.dart';

class _DirEdge {
  final int x0, y0, x1, y1;
  const _DirEdge(this.x0, this.y0, this.x1, this.y1);

  int get dx => x1 - x0;
  int get dy => y1 - y0;
}

class PolyominoPathBuilder {
  /// Builds a closed, smoothly rounded [Path] (with both outer convex corners
  /// and inner concave L-fillets) for any set of grid cells [cells].
  ///
  /// - [cellSize]: pixel size of one grid square.
  /// - [inset]: positive values shrink the shape inward (creating clean gaps between
  ///   adjacent blocks); negative values expand outward (e.g. for the board tray).
  /// - [cornerRadius]: fillet radius for convex corners.
  /// - [concaveRadius]: optional separate radius for inner concave corners
  ///   (defaults to `cornerRadius * 0.65`).
  static Path buildRoundedPath({
    required Set<GridCell> cells,
    required double cellSize,
    double inset = 0.0,
    required double cornerRadius,
    double? concaveRadius,
  }) {
    final path = Path();
    if (cells.isEmpty) return path;

    final double innerR = concaveRadius ?? (cornerRadius * 0.65);

    // 1. Collect directed unit boundary edges (clockwise around filled cells in screen coords)
    final edgesByStart = <(int, int), List<_DirEdge>>{};
    void addEdge(int x0, int y0, int x1, int y1) {
      edgesByStart.putIfAbsent((x0, y0), () => []).add(_DirEdge(x0, y0, x1, y1));
    }

    for (final (c, r) in cells) {
      // Top edge (East)
      if (!cells.contains((c, r - 1))) addEdge(c, r, c + 1, r);
      // Right edge (South)
      if (!cells.contains((c + 1, r))) addEdge(c + 1, r, c + 1, r + 1);
      // Bottom edge (West)
      if (!cells.contains((c, r + 1))) addEdge(c + 1, r + 1, c, r + 1);
      // Left edge (North)
      if (!cells.contains((c - 1, r))) addEdge(c, r + 1, c, r);
    }

    // 2. Chain directed edges into closed simple loops (preferring right turns at saddle points)
    final loops = <List<(int, int)>>[];
    while (edgesByStart.isNotEmpty) {
      final startKey = edgesByStart.keys.first;
      final startList = edgesByStart[startKey]!;
      _DirEdge current = startList.removeLast();
      if (startList.isEmpty) edgesByStart.remove(startKey);

      final rawPts = <(int, int)>[(current.x0, current.y0)];
      final rawDirs = <(int, int)>[(current.dx, current.dy)];

      while (true) {
        final nextVertex = (current.x1, current.y1);
        if (nextVertex == rawPts.first) break;

        final candidates = edgesByStart[nextVertex];
        if (candidates == null || candidates.isEmpty) break;

        final (pdx, pdy) = (current.dx, current.dy);
        // Right turn = (-pdy, pdx), Straight = (pdx, pdy), Left turn = (pdy, -pdx)
        final rightDir = (-pdy, pdx);
        final straightDir = (pdx, pdy);

        int chosenIdx = 0;
        for (int i = 0; i < candidates.length; i++) {
          final d = (candidates[i].dx, candidates[i].dy);
          if (d == rightDir) {
            chosenIdx = i;
            break;
          } else if (d == straightDir) {
            chosenIdx = i;
          }
        }

        final nextEdge = candidates.removeAt(chosenIdx);
        if (candidates.isEmpty) edgesByStart.remove(nextVertex);

        rawPts.add(nextVertex);
        rawDirs.add((nextEdge.dx, nextEdge.dy));
        current = nextEdge;
      }

      if (rawPts.length < 4) continue;

      // Merge collinear consecutive edges so only true 90-degree corners remain
      final corners = <(int, int)>[];
      final nRaw = rawPts.length;
      for (int i = 0; i < nRaw; i++) {
        final prevDir = rawDirs[(i - 1 + nRaw) % nRaw];
        final curDir = rawDirs[i];
        if (prevDir != curDir) {
          corners.add(rawPts[i]);
        }
      }
      if (corners.length >= 4) {
        loops.add(corners);
      }
    }

    // 3. Offset each loop along inward edge normals and round all corners
    for (final corners in loops) {
      final m = corners.length;
      final shifted = <Offset>[];

      for (int i = 0; i < m; i++) {
        final prev = corners[(i - 1 + m) % m];
        final curr = corners[i];
        final next = corners[(i + 1) % m];

        final dx0 = (curr.$1 - prev.$1).sign.toDouble();
        final dy0 = (curr.$2 - prev.$2).sign.toDouble();
        final dx1 = (next.$1 - curr.$1).sign.toDouble();
        final dy1 = (next.$2 - curr.$2).sign.toDouble();

        // Inward unit normals for clockwise exterior loop: n = (-dy, dx)
        final n0x = -dy0;
        final n0y = dx0;
        final n1x = -dy1;
        final n1y = dx1;

        final sx = curr.$1 * cellSize + inset * (n0x + n1x);
        final sy = curr.$2 * cellSize + inset * (n0y + n1y);
        shifted.add(Offset(sx, sy));
      }

      // Build rounded path for this loop
      Offset? firstArcEnd;
      Offset? firstArcStart;

      for (int i = 0; i < m; i++) {
        final pPrev = shifted[(i - 1 + m) % m];
        final pCurr = shifted[i];
        final pNext = shifted[(i + 1) % m];

        final vIn = pCurr - pPrev;
        final vOut = pNext - pCurr;
        final lenIn = vIn.distance;
        final lenOut = vOut.distance;
        if (lenIn < 1e-4 || lenOut < 1e-4) continue;

        final uIn = vIn / lenIn;
        final uOut = vOut / lenOut;
        final cross = uIn.dx * uOut.dy - uIn.dy * uOut.dx;
        final isRightTurn = cross > 0;

        final targetR = isRightTurn ? cornerRadius : innerR;
        final rEff = math.min(targetR, math.min(lenIn, lenOut) * 0.48);

        final arcStart = pCurr - uIn * rEff;
        final arcEnd = pCurr + uOut * rEff;

        if (firstArcStart == null) {
          firstArcStart = arcStart;
          firstArcEnd = arcEnd;
          path.moveTo(arcStart.dx, arcStart.dy);
        } else {
          path.lineTo(arcStart.dx, arcStart.dy);
        }

        if (rEff > 0.25) {
          path.arcToPoint(
            arcEnd,
            radius: Radius.circular(rEff),
            clockwise: isRightTurn,
          );
        } else {
          path.lineTo(arcEnd.dx, arcEnd.dy);
        }
      }

      if (firstArcStart != null && firstArcEnd != null) {
        path.lineTo(firstArcStart.dx, firstArcStart.dy);
        path.close();
      }
    }

    return path;
  }

  /// Computes crisp screw positions near the outer convex corners of a stationary/pinned piece,
  /// matching `StationaryBlocksParts.json` (`_cornerOffset: ~0.24`, `_singleBlockCornerOffset: 0.30`).
  static List<Offset> computePinnedScrewOffsets({
    required Set<GridCell> cells,
    required double cellSize,
  }) {
    if (cells.isEmpty) return const [];
    final isSingle = cells.length == 1;
    final margin = cellSize * (isSingle ? 0.26 : 0.24);
    final screws = <Offset>[];

    for (final (c, r) in cells) {
      final noLeft = !cells.contains((c - 1, r));
      final noRight = !cells.contains((c + 1, r));
      final noTop = !cells.contains((c, r - 1));
      final noBottom = !cells.contains((c, r + 1));

      final x0 = c * cellSize;
      final y0 = r * cellSize;

      if (noLeft && noTop) screws.add(Offset(x0 + margin, y0 + margin));
      if (noRight && noTop) screws.add(Offset(x0 + cellSize - margin, y0 + margin));
      if (noLeft && noBottom) screws.add(Offset(x0 + margin, y0 + cellSize - margin));
      if (noRight && noBottom) {
        screws.add(Offset(x0 + cellSize - margin, y0 + cellSize - margin));
      }
    }
    return screws;
  }
}
