import 'dart:math' as math;
import 'dart:ui';
import '../models/level_models.dart';
import '../models/unity_curve.dart';

class _DirEdge {
  final int x0, y0, x1, y1;
  const _DirEdge(this.x0, this.y0, this.x1, this.y1);

  int get dx => x1 - x0;
  int get dy => y1 - y0;
}

class PinnedScrewAnchor {
  final Offset restPos;
  final Offset outwardSign;
  final double baseScale;

  const PinnedScrewAnchor({
    required this.restPos,
    required this.outwardSign,
    required this.baseScale,
  });

  Offset positionWithPinPush(double pinPushPx) => Offset(
        restPos.dx + outwardSign.dx * pinPushPx,
        restPos.dy + outwardSign.dy * pinPushPx,
      );
}

enum NumberLabelLayoutMode {
  full,
  compactCentre,
  compactBetweenSideArrows,
  betweenArrows,
  betweenPins,
}

class MovementArrowLayout {
  final bool isHorizontal;
  final bool isCompact;
  final bool isCombined;
  final Offset negRestPos;
  final Offset posRestPos;
  final double arrowScale;
  final double negativeCellLimit;
  final double positiveCellLimit;

  const MovementArrowLayout({
    required this.isHorizontal,
    required this.isCompact,
    required this.isCombined,
    required this.negRestPos,
    required this.posRestPos,
    required this.arrowScale,
    required this.negativeCellLimit,
    required this.positiveCellLimit,
  });

  bool get hasArrowGap => !isCompact && !isCombined;
}

class PolyominoPathBuilder {
  /// Builds a closed, smoothly rounded [Path] (with both outer convex corners
  /// and inner concave L-fillets) for any set of grid cells [cells].
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

  /// Exact match of `PieceBlockBuilder.BuildStationaryAnchors` + `StationaryBlocksParts`:
  /// Places corner screw pins ONLY on outer convex 90° corners (`!hasVertical && !hasHorizontal`):
  /// - `1x1` piece: `scale = 0.65`, offset `(±0.30, ±0.30) * cellSize` from cell center.
  /// - Multi-cell piece: `scale = 1.0`, offset `(±0.23979275, ±0.237994) * cellSize` from cell center.
  static List<PinnedScrewAnchor> computePinnedScrewAnchors({
    required Set<GridCell> cells,
    required double cellSize,
  }) {
    if (cells.isEmpty) return const [];
    final isSingle = cells.length == 1;
    final baseScale = isSingle ? UnityComponentVisualConfig.singleBlockScale : 1.0;
    final dx = cellSize *
        (isSingle
            ? UnityComponentVisualConfig.singleBlockCornerOffset
            : UnityComponentVisualConfig.multiBlockCornerOffsetX);
    final dy = cellSize *
        (isSingle
            ? UnityComponentVisualConfig.singleBlockCornerOffset
            : UnityComponentVisualConfig.multiBlockCornerOffsetY);

    final anchors = <PinnedScrewAnchor>[];
    for (final (c, r) in cells) {
      final noLeft = !cells.contains((c - 1, r));
      final noRight = !cells.contains((c + 1, r));
      final noTop = !cells.contains((c, r - 1));
      final noBottom = !cells.contains((c, r + 1));

      final cx = (c + 0.5) * cellSize;
      final cy = (r + 0.5) * cellSize;

      if (noLeft && noTop) {
        anchors.add(
          PinnedScrewAnchor(
            restPos: Offset(cx - dx, cy - dy),
            outwardSign: const Offset(-1.0, -1.0),
            baseScale: baseScale,
          ),
        );
      }
      if (noRight && noTop) {
        anchors.add(
          PinnedScrewAnchor(
            restPos: Offset(cx + dx, cy - dy),
            outwardSign: const Offset(1.0, -1.0),
            baseScale: baseScale,
          ),
        );
      }
      if (noLeft && noBottom) {
        anchors.add(
          PinnedScrewAnchor(
            restPos: Offset(cx - dx, cy + dy),
            outwardSign: const Offset(-1.0, 1.0),
            baseScale: baseScale,
          ),
        );
      }
      if (noRight && noBottom) {
        anchors.add(
          PinnedScrewAnchor(
            restPos: Offset(cx + dx, cy + dy),
            outwardSign: const Offset(1.0, 1.0),
            baseScale: baseScale,
          ),
        );
      }
    }
    return anchors;
  }

  static List<Offset> computePinnedScrewOffsets({
    required Set<GridCell> cells,
    required double cellSize,
  }) {
    return computePinnedScrewAnchors(cells: cells, cellSize: cellSize)
        .map((a) => a.restPos)
        .toList();
  }

  /// Exact match of `MovementComponentPresenter.ResolvePositions` & `ResolveAxis`:
  /// Computes directional arrow positions, compact/normal scaling, seam placement on `2x2` squares,
  /// and combined-arrow detection on staircase polyominoes.
  static MovementArrowLayout? resolveMovementArrows({
    required PieceModel model,
    required double cellSize,
  }) {
    final isHoriz = model.movement == MovementConstraint.horizontalOnly;
    final isVert = model.movement == MovementConstraint.verticalOnly;
    if (!isHoriz && !isVert) return null;

    final cells = model.localCells.toSet();
    if (cells.isEmpty) return null;

    final (spanCx, spanCy) = model.spanCenterInCells();
    final centerAcross = isHoriz ? spanCy : spanCx;

    int alongOf(GridCell cell) => isHoriz ? cell.$1 : cell.$2;
    int acrossOf(GridCell cell) => isHoriz ? cell.$2 : cell.$1;

    // 1. RoomiestLines: group cells by Across line (row for H, col for V) & keep lines with max count
    final countsByLine = <int, int>{};
    for (final cell in cells) {
      final line = acrossOf(cell);
      countsByLine[line] = (countsByLine[line] ?? 0) + 1;
    }
    int maxCount = 0;
    for (final cnt in countsByLine.values) {
      if (cnt > maxCount) maxCount = cnt;
    }
    final roomiest = <int>{
      for (final e in countsByLine.entries)
        if (e.value == maxCount) e.key,
    };

    // 2. NearestLineDistance to spanCenter
    double nearestDist = double.infinity;
    for (final line in roomiest) {
      final d = ((line + 0.5) - centerAcross).abs();
      if (d < nearestDist) nearestDist = d;
    }
    final nearestLines = <int>[
      for (final line in roomiest)
        if ((((line + 0.5) - centerAcross).abs() - nearestDist).abs() <= 1e-4)
          line,
    ]..sort();

    int extremeOnLine(int line, {required bool towardsPositive}) {
      int? best;
      for (final cell in cells) {
        if (acrossOf(cell) != line) continue;
        final a = alongOf(cell);
        if (best == null || (towardsPositive ? a > best : a < best)) {
          best = a;
        }
      }
      return best ?? 0;
    }

    (int extremeAlong, int extremeLine, bool decided) findExtreme({
      required bool towardsPositive,
    }) {
      int? bestAlong;
      final winningLines = <int>[];
      for (final line in nearestLines) {
        final ext = extremeOnLine(line, towardsPositive: towardsPositive);
        if (bestAlong == null ||
            (towardsPositive ? ext > bestAlong : ext < bestAlong)) {
          bestAlong = ext;
          winningLines
            ..clear()
            ..add(line);
        } else if (ext == bestAlong) {
          winningLines.add(line);
        }
      }
      return (
        bestAlong ?? 0,
        winningLines.isNotEmpty ? winningLines.first : 0,
        winningLines.length == 1,
      );
    }

    // 3. FindExtreme for negative & positive ends + cross-end tie-breaking
    var (negAlong, negLine, negDecided) = findExtreme(towardsPositive: false);
    var (posAlong, posLine, posDecided) = findExtreme(towardsPositive: true);

    if (negDecided && !posDecided) {
      posLine = negLine;
      posAlong = extremeOnLine(negLine, towardsPositive: true);
      posDecided = true;
    } else if (posDecided && !negDecided) {
      negLine = posLine;
      negAlong = extremeOnLine(posLine, towardsPositive: false);
      negDecided = true;
    }

    // 4. UndecidedAcross: places arrows right on the seam `(minLine + 1.0) * cellSize` for `2x2`!
    double undecidedAcrossPx() {
      if (nearestLines.isEmpty) return centerAcross * cellSize;
      final minLine = nearestLines.first;
      final maxLine = nearestLines.last;
      if (maxLine - minLine == 1) {
        return (minLine + 1.0) * cellSize;
      }
      return (minLine + 0.5) * cellSize;
    }

    final sharedUndecided =
        (!negDecided || !posDecided) ? undecidedAcrossPx() : 0.0;
    final negAcrossPx =
        negDecided ? (negLine + 0.5) * cellSize : sharedUndecided;
    final posAcrossPx =
        posDecided ? (posLine + 0.5) * cellSize : sharedUndecided;

    final negAlongPx = (negAlong + 0.5) * cellSize;
    final posAlongPx = (posAlong + 0.5) * cellSize;

    final baseNegPos = isHoriz
        ? Offset(negAlongPx, negAcrossPx)
        : Offset(negAcrossPx, negAlongPx);
    final basePosPos = isHoriz
        ? Offset(posAlongPx, posAcrossPx)
        : Offset(posAcrossPx, posAlongPx);

    final isCompact =
        (isHoriz && model.widthCols == 1) || (isVert && model.heightRows == 1);
    if (isCompact) {
      final compactOffset = isHoriz
          ? Offset(UnityComponentVisualConfig.compactSideOffset * cellSize, 0.0)
          : Offset(
              0.0,
              UnityComponentVisualConfig.compactVerticalOffset * cellSize,
            );
      return MovementArrowLayout(
        isHorizontal: isHoriz,
        isCompact: true,
        isCombined: false,
        negRestPos: baseNegPos - compactOffset,
        posRestPos: basePosPos + compactOffset,
        arrowScale: UnityComponentVisualConfig.compactArrowScale,
        negativeCellLimit: negAlongPx - 0.5 * cellSize,
        positiveCellLimit: posAlongPx + 0.5 * cellSize,
      );
    }

    final isCombined =
        (negAlong == posAlong) && (negAcrossPx - posAcrossPx).abs() <= 1e-4;
    return MovementArrowLayout(
      isHorizontal: isHoriz,
      isCompact: false,
      isCombined: isCombined,
      negRestPos: baseNegPos,
      posRestPos: basePosPos,
      arrowScale: 1.0,
      negativeCellLimit: negAlongPx - 0.5 * cellSize,
      positiveCellLimit: posAlongPx + 0.5 * cellSize,
    );
  }
}

