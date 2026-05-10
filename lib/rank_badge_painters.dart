import 'dart:math' as math;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Rank Badge Painters — Category-Specific Icon System
//  ─────────────────────────────────────────────────────────────────────────
//  Each endeavour uses a distinct icon drawn on a circular halo background.
//    gym       →  dumbbell
//    academic  →  open book
//    running   →  running shoe
//    luminary  →  paintbrush
//
//  Six rank tiers receive progressively richer visual treatments:
//    0 Bronze    bare gradient fill, subtle glow
//    1 Silver    shine sweep lines
//    2 Gold      sparkles at badge corners
//    3 Platinum  diagonal icy gleam, soft outer ring
//    4 Diamond   multi-sparkle cluster, bright outer ring
//    5 Enlightened  radiant rays + 6-point star burst + prismatic border
//
//  Canvas virtual grid: 96 × 96.  Scale factor s = size.width / 96.
// ═══════════════════════════════════════════════════════════════════════════

// ─── Color scheme per rank tier ─────────────────────────────────────────────
class _Scheme {
  final Color primary;    // dominant fill / top gradient stop
  final Color secondary;  // shadow / bottom gradient stop
  final Color highlight;  // bright reflection
  final Color border;     // outline / edge
  final Color glow;       // bloom / sparkle color

  const _Scheme(
      this.primary, this.secondary, this.highlight, this.border, this.glow);
}

const List<_Scheme> _kSchemes = [
  _Scheme(Color(0xFFCD7F32), Color(0xFF5C2E0E), Color(0xFFFFCB7A), Color(0xFF8B5020), Color(0xFFCD7F32)), // 0 Bronze
  _Scheme(Color(0xFFDCDCDC), Color(0xFF747474), Color(0xFFFFFFFF), Color(0xFF9E9E9E), Color(0xFFC0C0C0)), // 1 Silver
  _Scheme(Color(0xFFFFDD44), Color(0xFFAA7700), Color(0xFFFFF8CC), Color(0xFFBB8800), Color(0xFFFFD700)), // 2 Gold
  _Scheme(Color(0xFFBEE9FF), Color(0xFF46A8D8), Color(0xFFFFFFFF), Color(0xFF70C4EE), Color(0xFFB0E0FF)), // 3 Platinum
  _Scheme(Color(0xFF70EEFF), Color(0xFF0080C8), Color(0xFFFFFFFF), Color(0xFF00BFFF), Color(0xFF00E5FF)), // 4 Diamond
  _Scheme(Color(0xFFEE44FF), Color(0xFF6600CC), Color(0xFFFFFFFF), Color(0xFFCC00FF), Color(0xFFE040FB)), // 5 Enlightened
];

// ─── Shared paint helpers ────────────────────────────────────────────────────

Paint _stroke(Color c, double w,
    [StrokeCap cap = StrokeCap.round, StrokeJoin join = StrokeJoin.round]) =>
    Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = cap
      ..strokeJoin = join;

Paint _fill(Color c) => Paint()..color = c;

// ─── Circular halo background ───────────────────────────────────────────────

void _drawBg(Canvas canvas, Size size, Color accent, _Scheme sc) {
  final s = size.width / 96;
  final center = Offset(48 * s, 48 * s);
  final r = 44 * s;

  // Outer accent halo
  canvas.drawCircle(
    center, r,
    Paint()
      ..shader = RadialGradient(
        colors: [accent.withAlpha(80), accent.withAlpha(10)],
      ).createShader(Rect.fromCircle(center: center, radius: r)),
  );

  // Rank-colored inner ring
  canvas.drawCircle(
    center, r,
    Paint()
      ..color = sc.glow.withAlpha(60)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * s,
  );

  // Accent border
  canvas.drawCircle(
    center, r,
    Paint()
      ..color = accent.withAlpha(70)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8 * s,
  );
}

// ─── Rank-tier overlay effects ───────────────────────────────────────────────

void _drawSparkle(Canvas canvas, double s, double cx, double cy,
    double sz, Color c, {double sw = 1.0}) {
  final p = _stroke(c, sw * s)..strokeCap = StrokeCap.round;
  canvas.drawLine(Offset((cx - sz) * s, cy * s), Offset((cx + sz) * s, cy * s), p);
  canvas.drawLine(Offset(cx * s, (cy - sz) * s), Offset(cx * s, (cy + sz) * s), p);
  canvas.drawCircle(Offset(cx * s, cy * s), 0.8 * s, _fill(c));
}

void _draw6Star(Canvas canvas, double s, double cx, double cy,
    double r, Color c) {
  final path = Path();
  final inner = r * 0.42;
  for (int i = 0; i < 12; i++) {
    final a = -math.pi / 2 + i * (math.pi / 6);
    final rad = i.isEven ? r : inner;
    final x = (cx + rad * math.cos(a)) * s;
    final y = (cy + rad * math.sin(a)) * s;
    i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
  }
  path.close();
  canvas.drawPath(path, _fill(c));
}

void _applyRankFx(Canvas canvas, double s, int rankIndex, _Scheme sc) {
  final center = Offset(48 * s, 48 * s);
  switch (rankIndex) {
    case 0: // Bronze — subtle glow only (handled in bg)
      break;

    case 1: // Silver — horizontal shine sweep
      for (final y in [32.0, 40.0, 62.0, 70.0]) {
        canvas.drawLine(
          Offset(8 * s, y * s), Offset(88 * s, y * s),
          _stroke(Colors.white.withAlpha(22), 1.2 * s, StrokeCap.butt),
        );
      }
      break;

    case 2: // Gold — 4 sparkles at N/E/S/W of badge
      _drawSparkle(canvas, s, 48, 5, 3, const Color(0xFFFFF0AA), sw: 1.3);
      _drawSparkle(canvas, s, 91, 48, 2.5, const Color(0xFFFFF0AA));
      _drawSparkle(canvas, s, 48, 91, 2.5, const Color(0xFFFFF0AA));
      _drawSparkle(canvas, s, 5, 48, 3, const Color(0xFFFFF0AA), sw: 1.3);
      break;

    case 3: // Platinum — diagonal icy gleam + faint outer ring
      canvas.drawCircle(
        center, 43 * s,
        Paint()
          ..color = const Color(0xFFB0E0FF).withAlpha(45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 * s
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.drawLine(
        Offset(18 * s, 10 * s), Offset(88 * s, 80 * s),
        _stroke(Colors.white.withAlpha(55), 1.4 * s, StrokeCap.round),
      );
      canvas.drawLine(
        Offset(10 * s, 22 * s), Offset(74 * s, 86 * s),
        _stroke(Colors.white.withAlpha(30), 1.0 * s, StrokeCap.round),
      );
      break;

    case 4: // Diamond — outer glow ring + 8 sparkles
      canvas.drawCircle(
        center, 43 * s,
        Paint()
          ..color = const Color(0xFF00E5FF).withAlpha(55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * s
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      const dspots = [
        [48.0, 4.0], [87.0, 22.0], [92.0, 48.0], [87.0, 74.0],
        [48.0, 92.0], [9.0, 74.0], [4.0, 48.0], [9.0, 22.0],
      ];
      for (final p in dspots) {
        _drawSparkle(canvas, s, p[0], p[1], 2.4, Colors.white, sw: 1.1);
      }
      break;

    case 5: // Enlightened — radiant rays + 6-point star + ring pair
      // Rays from center outward
      const rayCount = 16;
      for (int i = 0; i < rayCount; i++) {
        final angle = (math.pi * 2 / rayCount) * i;
        final innerR = 18.0 * s;
        final outerR = 44.0 * s;
        final c1 = i.isEven ? const Color(0xFFE040FB) : const Color(0xFF40C4FF);
        canvas.drawLine(
          Offset(center.dx + innerR * math.cos(angle),
              center.dy + innerR * math.sin(angle)),
          Offset(center.dx + outerR * math.cos(angle),
              center.dy + outerR * math.sin(angle)),
          _stroke(c1.withAlpha(80), 1.6 * s),
        );
      }
      // Dual halo rings
      canvas.drawCircle(center, 43 * s,
          Paint()
            ..color = const Color(0xFFE040FB).withAlpha(55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8 * s);
      canvas.drawCircle(center, 38 * s,
          Paint()
            ..color = const Color(0xFF40C4FF).withAlpha(45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 * s);
      // Bright 6-point star
      _draw6Star(canvas, s, 48, 48, 7, Colors.white.withAlpha(220));
      canvas.drawCircle(center, 2.0 * s, _fill(Colors.white));
      // Scattered sparkle dots
      const eSp = [
        [28.0, 16.0], [70.0, 18.0], [84.0, 34.0], [82.0, 64.0],
        [66.0, 84.0], [30.0, 84.0], [12.0, 62.0], [14.0, 32.0],
      ];
      for (final p in eSp) {
        canvas.drawCircle(Offset(p[0] * s, p[1] * s), 1.2 * s,
            _fill(Colors.white.withAlpha(220)));
        canvas.drawCircle(Offset(p[0] * s, p[1] * s), 2.4 * s,
            Paint()
              ..color = Colors.white.withAlpha(55)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
      }
      break;
  }
}

// ─── Gradient fill helper ────────────────────────────────────────────────────

Paint _gradFill(Rect r, _Scheme sc,
    {Alignment begin = Alignment.topCenter,
    Alignment end = Alignment.bottomCenter}) {
  return Paint()
    ..shader = LinearGradient(
      begin: begin,
      end: end,
      colors: [sc.primary, sc.secondary],
    ).createShader(r);
}

Paint _glowPaint(_Scheme sc, double blur) =>
    Paint()
      ..color = sc.glow.withAlpha(65)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

// ═══════════════════════════════════════════════════════════════════════════
//  PUBLIC FACTORY
// ═══════════════════════════════════════════════════════════════════════════

CustomPainter getRankBadgePainter(
  String endeavour,
  int rankIndex,
  Color accent,
) {
  final i = rankIndex.clamp(0, 5);
  switch (endeavour.toLowerCase()) {
    case 'gym':
      return _DumbbellPainter(accent: accent, rankIndex: i);
    case 'academic':
      return _BookPainter(accent: accent, rankIndex: i);
    case 'running':
      return _ShoePainter(accent: accent, rankIndex: i);
    case 'luminary':
    default:
      return _BrushPainter(accent: accent, rankIndex: i);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  GYM — DUMBBELL
//  Two weight plates + collars + bar, all drawn as RRects.
//  Grip lines on the bar, highlight on the upper half of the plates.
// ═══════════════════════════════════════════════════════════════════════════

class _DumbbellPainter extends CustomPainter {
  final Color accent;
  final int rankIndex;
  const _DumbbellPainter({required this.accent, required this.rankIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    final sc = _kSchemes[rankIndex];
    _drawBg(canvas, size, accent, sc);

    // ── Geometry ──────────────────────────────────────────────────────────
    final barRect   = RRect.fromRectAndRadius(Rect.fromLTRB(32*s, 43*s, 64*s, 53*s), Radius.circular(5*s));
    final lCollar   = RRect.fromRectAndRadius(Rect.fromLTRB(22*s, 39*s, 32*s, 57*s), Radius.circular(3*s));
    final rCollar   = RRect.fromRectAndRadius(Rect.fromLTRB(64*s, 39*s, 74*s, 57*s), Radius.circular(3*s));
    final lPlate    = RRect.fromRectAndRadius(Rect.fromLTRB(10*s, 28*s, 22*s, 68*s), Radius.circular(5*s));
    final rPlate    = RRect.fromRectAndRadius(Rect.fromLTRB(74*s, 28*s, 86*s, 68*s), Radius.circular(5*s));
    final allParts  = [lPlate, rPlate, lCollar, rCollar, barRect];
    final gradRect  = Rect.fromLTRB(10*s, 28*s, 86*s, 68*s);

    // ── Glow ──────────────────────────────────────────────────────────────
    for (final rr in [lPlate, rPlate]) {
      canvas.drawRRect(rr, _glowPaint(sc, 5 * s));
    }

    // ── Fill ──────────────────────────────────────────────────────────────
    final grad = _gradFill(gradRect, sc);
    for (final rr in allParts) { canvas.drawRRect(rr, grad); }

    // ── Highlight — upper half of plates ──────────────────────────────────
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, 96 * s, 48 * s));
    for (final rr in [lPlate, rPlate]) {
      canvas.drawRRect(rr, _fill(sc.highlight.withAlpha(70)));
    }
    canvas.restore();

    // ── Grip lines on bar ─────────────────────────────────────────────────
    canvas.save();
    canvas.clipRRect(barRect);
    final grip = _stroke(sc.border.withAlpha(100), 0.9 * s, StrokeCap.butt);
    for (double x = 36.0; x <= 60.0; x += 4) {
      canvas.drawLine(Offset(x * s, 43 * s), Offset(x * s, 53 * s), grip);
    }
    canvas.restore();

    // ── Collar divider lines ──────────────────────────────────────────────
    for (final rr in [lCollar, rCollar]) {
      canvas.drawLine(
        Offset(rr.left + rr.width / 2, rr.top + 2 * s),
        Offset(rr.left + rr.width / 2, rr.bottom - 2 * s),
        _stroke(sc.border.withAlpha(80), 0.8 * s),
      );
    }

    // ── Borders ───────────────────────────────────────────────────────────
    final b = _stroke(sc.border, 1.6 * s);
    for (final rr in allParts) { canvas.drawRRect(rr, b); }

    _applyRankFx(canvas, s, rankIndex, sc);
  }

  @override
  bool shouldRepaint(covariant _DumbbellPainter old) =>
      old.rankIndex != rankIndex || old.accent != accent;
}

// ═══════════════════════════════════════════════════════════════════════════
//  ACADEMIC — OPEN BOOK
//  Two pages splaying outward from a center spine, with page-text lines
//  and an arc for the top binding.
// ═══════════════════════════════════════════════════════════════════════════

class _BookPainter extends CustomPainter {
  final Color accent;
  final int rankIndex;
  const _BookPainter({required this.accent, required this.rankIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    final sc = _kSchemes[rankIndex];
    _drawBg(canvas, size, accent, sc);

    final fullRect = Rect.fromLTRB(12*s, 18*s, 84*s, 78*s);

    // ── Page paths ────────────────────────────────────────────────────────
    final leftPage = Path()
      ..moveTo(48*s, 20*s)
      ..lineTo(13*s, 27*s)
      ..lineTo(13*s, 77*s)
      ..lineTo(48*s, 72*s)
      ..close();

    final rightPage = Path()
      ..moveTo(48*s, 20*s)
      ..lineTo(83*s, 27*s)
      ..lineTo(83*s, 77*s)
      ..lineTo(48*s, 72*s)
      ..close();

    // ── Glow ──────────────────────────────────────────────────────────────
    canvas.drawPath(leftPage,  _glowPaint(sc, 5 * s));
    canvas.drawPath(rightPage, _glowPaint(sc, 5 * s));

    // ── Page fill — left page slightly lighter for depth ──────────────────
    final leftColor  = Color.lerp(sc.primary, Colors.white, 0.18)!;
    final rightColor = sc.primary;

    canvas.drawPath(leftPage,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [leftColor, sc.secondary],
          ).createShader(fullRect));

    canvas.drawPath(rightPage,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [rightColor, sc.secondary],
          ).createShader(fullRect));

    // ── Page-text lines ───────────────────────────────────────────────────
    final lineP = _stroke(sc.secondary.withAlpha(90), 0.9 * s, StrokeCap.butt);
    for (double y = 33.0; y <= 66.0; y += 9) {
      final t = (y - 20) / 57;  // 0→1 top→bottom (pages converge toward spine)
      // Left page: lines converge slightly toward spine as y increases
      canvas.drawLine(
        Offset((17 + t * 2) * s, y * s),
        Offset((44 - t * 2) * s, y * s),
        lineP,
      );
      // Right page
      canvas.drawLine(
        Offset((52 + t * 2) * s, y * s),
        Offset((79 - t * 2) * s, y * s),
        lineP,
      );
    }

    // ── Center spine ──────────────────────────────────────────────────────
    canvas.drawLine(
      Offset(48 * s, 20 * s), Offset(48 * s, 72 * s),
      _stroke(sc.border, 2.2 * s),
    );

    // ── Top binding arc ───────────────────────────────────────────────────
    canvas.drawArc(
      Rect.fromLTRB(43 * s, 14 * s, 53 * s, 26 * s),
      math.pi, math.pi, false,
      _stroke(sc.border, 2.2 * s),
    );

    // ── Borders ───────────────────────────────────────────────────────────
    final b = _stroke(sc.border, 1.5 * s);
    canvas.drawPath(leftPage,  b);
    canvas.drawPath(rightPage, b);

    // ── Highlight on upper-left corner ────────────────────────────────────
    canvas.save();
    canvas.clipPath(leftPage);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(26 * s, 30 * s), width: 12 * s, height: 5 * s),
      _fill(sc.highlight.withAlpha(90)),
    );
    canvas.restore();

    _applyRankFx(canvas, s, rankIndex, sc);
  }

  @override
  bool shouldRepaint(covariant _BookPainter old) =>
      old.rankIndex != rankIndex || old.accent != accent;
}

// ═══════════════════════════════════════════════════════════════════════════
//  RUNNING — SHOE
//  Side-profile sneaker facing right.  Upper body + thick sole + lace area.
// ═══════════════════════════════════════════════════════════════════════════

class _ShoePainter extends CustomPainter {
  final Color accent;
  final int rankIndex;
  const _ShoePainter({required this.accent, required this.rankIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    final sc = _kSchemes[rankIndex];
    _drawBg(canvas, size, accent, sc);

    // ── Shoe paths ────────────────────────────────────────────────────────
    // Upper body (heel left, toe right)
    final upper = Path()
      ..moveTo(14*s, 68*s)          // heel base
      ..lineTo(14*s, 54*s)          // heel back wall
      ..quadraticBezierTo(14*s, 40*s, 24*s, 34*s)  // heel curve
      ..lineTo(36*s, 28*s)          // ankle slope
      ..lineTo(54*s, 24*s)          // tongue peak
      ..quadraticBezierTo(72*s, 24*s, 80*s, 40*s)  // toe box forward curve
      ..quadraticBezierTo(86*s, 54*s, 86*s, 68*s)  // toe front wall
      ..close();

    // Sole (thick base)
    final sole = Path()
      ..moveTo(12*s, 68*s)
      ..lineTo(86*s, 68*s)
      ..quadraticBezierTo(90*s, 68*s, 90*s, 73*s)
      ..quadraticBezierTo(90*s, 78*s, 86*s, 78*s)
      ..lineTo(14*s, 78*s)
      ..quadraticBezierTo(10*s, 78*s, 10*s, 73*s)
      ..quadraticBezierTo(10*s, 68*s, 12*s, 68*s)
      ..close();

    // Lace panel (trapezoid on upper)
    final lacePanel = Path()
      ..moveTo(36*s, 28*s)
      ..lineTo(54*s, 24*s)
      ..lineTo(70*s, 34*s)
      ..lineTo(54*s, 42*s)
      ..close();

    final upperRect = Rect.fromLTRB(14*s, 24*s, 86*s, 68*s);
    final soleRect  = Rect.fromLTRB(10*s, 68*s, 90*s, 78*s);

    // ── Glow ──────────────────────────────────────────────────────────────
    canvas.drawPath(upper, _glowPaint(sc, 5 * s));

    // ── Upper fill ────────────────────────────────────────────────────────
    canvas.drawPath(upper, _gradFill(upperRect, sc));

    // ── Sole fill (darker) ────────────────────────────────────────────────
    canvas.drawPath(
      sole,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [sc.secondary, Color.lerp(sc.secondary, Colors.black, 0.35)!],
        ).createShader(soleRect),
    );

    // ── Lace panel overlay ────────────────────────────────────────────────
    canvas.save();
    canvas.clipPath(upper);
    canvas.drawPath(lacePanel,
        _fill(Color.lerp(sc.primary, Colors.white, 0.20)!.withAlpha(180)));
    // Lace lines
    final laceStroke = _stroke(sc.highlight.withAlpha(160), 1.2 * s);
    for (final pair in [
      [38.0, 33.0, 58.0, 32.0],
      [40.0, 38.0, 60.0, 37.5],
      [42.0, 43.5, 62.0, 43.5],
    ]) {
      canvas.drawLine(
          Offset(pair[0] * s, pair[1] * s),
          Offset(pair[2] * s, pair[3] * s),
          laceStroke);
    }
    canvas.restore();

    // ── Sole mid-stripe ───────────────────────────────────────────────────
    canvas.save();
    canvas.clipPath(sole);
    canvas.drawLine(
      Offset(12 * s, 71 * s), Offset(88 * s, 71 * s),
      _stroke(sc.highlight.withAlpha(55), 1.0 * s, StrokeCap.butt),
    );
    canvas.restore();

    // ── Borders ───────────────────────────────────────────────────────────
    final b = _stroke(sc.border, 1.6 * s);
    canvas.drawPath(upper, b);
    canvas.drawPath(sole,  b);

    // ── Heel tab (small rectangle at top of heel) ─────────────────────────
    final heelTab = RRect.fromRectAndRadius(
        Rect.fromLTRB(11*s, 50*s, 16*s, 58*s), Radius.circular(2*s));
    canvas.drawRRect(heelTab, _fill(sc.primary));
    canvas.drawRRect(heelTab, _stroke(sc.border, 1.2 * s));

    _applyRankFx(canvas, s, rankIndex, sc);
  }

  @override
  bool shouldRepaint(covariant _ShoePainter old) =>
      old.rankIndex != rankIndex || old.accent != accent;
}

// ═══════════════════════════════════════════════════════════════════════════
//  LUMINARY — PAINTBRUSH
//  Diagonal brush: handle top-right → bristle tip bottom-left (~45°).
//  Handle (wood) → ferrule (metal band) → tapered bristles → paint dot.
// ═══════════════════════════════════════════════════════════════════════════

class _BrushPainter extends CustomPainter {
  final Color accent;
  final int rankIndex;
  const _BrushPainter({required this.accent, required this.rankIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    final sc = _kSchemes[rankIndex];
    _drawBg(canvas, size, accent, sc);

    // ── Geometry ──────────────────────────────────────────────────────────
    // Brush axis runs from (74,18) top-right to (22,70) bottom-left at ~45°.
    // Perpendicular (1,1)/√2 · offset gives width.
    // All coordinates in virtual-grid units (×s for canvas).

    // Handle (wood): center (74,18)→(52,40), width 8 → perp ±4*(1/√2)≈±2.83≈±3
    final handle = Path()
      ..moveTo(77*s, 15*s)   // back-right
      ..lineTo(71*s, 21*s)   // back-left
      ..lineTo(49*s, 43*s)   // front-left
      ..lineTo(55*s, 37*s)   // front-right
      ..close();

    // Ferrule (metal band): center (52,40)→(44,48), width 9 → perp ±4.5*(1/√2)≈±3.2≈±3
    final ferrule = Path()
      ..moveTo(55*s, 37*s)   // back-right (same as handle front-right)
      ..lineTo(49*s, 43*s)   // back-left
      ..lineTo(41*s, 51*s)   // front-left
      ..lineTo(47*s, 45*s)   // front-right
      ..close();

    // Bristles (triangle): base (47,45)→(41,51), tip (22,70)
    final bristles = Path()
      ..moveTo(47*s, 45*s)
      ..lineTo(41*s, 51*s)
      ..lineTo(22*s, 70*s)
      ..close();

    final handleRect  = Rect.fromLTRB(49*s, 15*s, 77*s, 43*s);
    final bristleRect = Rect.fromLTRB(22*s, 45*s, 47*s, 70*s);

    // ── Glow ──────────────────────────────────────────────────────────────
    canvas.drawPath(bristles, _glowPaint(sc, 6 * s));

    // ── Handle fill (wood grain gradient) ─────────────────────────────────
    canvas.drawPath(
      handle,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [sc.primary, sc.secondary],
        ).createShader(handleRect),
    );

    // Wood grain: 2 subtle lines along the handle axis
    canvas.save();
    canvas.clipPath(handle);
    final grain = _stroke(sc.border.withAlpha(60), 0.7 * s, StrokeCap.butt);
    canvas.drawLine(Offset(74*s, 19*s), Offset(52*s, 41*s), grain);
    canvas.drawLine(Offset(76*s, 17*s), Offset(54*s, 39*s), grain);
    canvas.restore();

    // ── Ferrule fill (metallic, always silver-ish but tinted with rank) ───
    final ferruleColor = Color.lerp(const Color(0xFFCCCCCC), sc.primary, 0.35)!;
    canvas.drawPath(ferrule, _fill(ferruleColor));
    // Highlight edge on ferrule
    canvas.save();
    canvas.clipPath(ferrule);
    canvas.drawLine(
      Offset(54*s, 38*s), Offset(46*s, 46*s),
      _stroke(Colors.white.withAlpha(130), 1.0 * s),
    );
    canvas.restore();
    canvas.drawPath(ferrule, _stroke(sc.border, 1.4 * s));

    // ── Bristles fill ─────────────────────────────────────────────────────
    canvas.drawPath(
      bristles,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [sc.primary.withAlpha(220), sc.secondary],
        ).createShader(bristleRect),
    );
    // Fine bristle lines (3 parallel lines converging to tip)
    canvas.save();
    canvas.clipPath(bristles);
    final bLine = _stroke(sc.highlight.withAlpha(80), 0.7 * s);
    canvas.drawLine(Offset(46*s, 46*s), Offset(23*s, 69*s), bLine);
    canvas.drawLine(Offset(44*s, 48*s), Offset(22*s, 71*s), bLine);
    canvas.restore();

    // ── Handle border ─────────────────────────────────────────────────────
    canvas.drawPath(handle,   _stroke(sc.border, 1.5 * s));
    canvas.drawPath(bristles, _stroke(sc.border, 1.4 * s));

    // ── Paint blob at tip ─────────────────────────────────────────────────
    final tipCenter = Offset(22 * s, 70 * s);
    canvas.drawCircle(tipCenter, 5.5 * s,
        Paint()
          ..color = sc.glow.withAlpha(80)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * s));
    canvas.drawCircle(tipCenter, 4.0 * s, _fill(sc.primary));
    canvas.drawCircle(tipCenter, 4.0 * s, _stroke(sc.border, 1.2 * s));
    // Highlight on paint blob
    canvas.drawCircle(Offset(20 * s, 68 * s), 1.5 * s,
        _fill(sc.highlight.withAlpha(200)));

    _applyRankFx(canvas, s, rankIndex, sc);
  }

  @override
  bool shouldRepaint(covariant _BrushPainter old) =>
      old.rankIndex != rankIndex || old.accent != accent;
}
