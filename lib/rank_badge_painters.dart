import 'dart:math' as math;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Rank Badge Painters — Unified Tier-Based Icon System
//  ─────────────────────────────────────────────────────────────────────────
//  All endeavours share one icon set tied to the rank tier:
//    0 Bronze      → heraldic shield
//    1 Silver      → shield with upward chevron
//    2 Gold        → shield with 5-point star
//    3 Platinum    → pointy-top hexagonal crystal badge
//    4 Diamond     → faceted rhombus gem
//    5 Enlightened → royal crown with crown jewels
//
//  Canvas virtual grid: 96 × 96.  Scale factor s = size.width / 96.
// ═══════════════════════════════════════════════════════════════════════════

class _Scheme {
  final Color primary;
  final Color secondary;
  final Color highlight;
  final Color border;
  final Color glow;
  const _Scheme(this.primary, this.secondary, this.highlight, this.border, this.glow);
}

const List<_Scheme> _kSchemes = [
  _Scheme(Color(0xFFCD7F32), Color(0xFF5C2E0E), Color(0xFFFFCB7A), Color(0xFF8B5020), Color(0xFFCD7F32)), // 0 Bronze
  _Scheme(Color(0xFFDCDCDC), Color(0xFF747474), Color(0xFFFFFFFF), Color(0xFF9E9E9E), Color(0xFFC0C0C0)), // 1 Silver
  _Scheme(Color(0xFFFFDD44), Color(0xFFAA7700), Color(0xFFFFF8CC), Color(0xFFBB8800), Color(0xFFFFD700)), // 2 Gold
  _Scheme(Color(0xFFBEE9FF), Color(0xFF46A8D8), Color(0xFFFFFFFF), Color(0xFF70C4EE), Color(0xFFB0E0FF)), // 3 Platinum
  _Scheme(Color(0xFF70EEFF), Color(0xFF0080C8), Color(0xFFFFFFFF), Color(0xFF00BFFF), Color(0xFF00E5FF)), // 4 Diamond
  _Scheme(Color(0xFFEE44FF), Color(0xFF6600CC), Color(0xFFFFFFFF), Color(0xFFCC00FF), Color(0xFFE040FB)), // 5 Enlightened
];

// ─── Paint helpers ───────────────────────────────────────────────────────────

Paint _stroke(Color c, double w,
    [StrokeCap cap = StrokeCap.round, StrokeJoin join = StrokeJoin.round]) =>
    Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = cap
      ..strokeJoin = join;

Paint _fill(Color c) => Paint()..color = c;

Paint _gradFill(Rect r, _Scheme sc,
    {Alignment begin = Alignment.topCenter,
    Alignment end = Alignment.bottomCenter}) =>
    Paint()
      ..shader = LinearGradient(
        begin: begin,
        end: end,
        colors: [sc.primary, sc.secondary],
      ).createShader(r);

Paint _glowPaint(_Scheme sc, double blur) =>
    Paint()
      ..color = sc.glow.withAlpha(65)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

// ─── Circular halo background ─────────────────────────────────────────────

void _drawBg(Canvas canvas, Size size, Color accent, _Scheme sc) {
  final s = size.width / 96;
  final center = Offset(48 * s, 48 * s);
  final r = 44 * s;
  canvas.drawCircle(
    center, r,
    Paint()
      ..shader = RadialGradient(
        colors: [accent.withAlpha(80), accent.withAlpha(10)],
      ).createShader(Rect.fromCircle(center: center, radius: r)),
  );
  canvas.drawCircle(
    center, r,
    Paint()
      ..color = sc.glow.withAlpha(60)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * s,
  );
  canvas.drawCircle(
    center, r,
    Paint()
      ..color = accent.withAlpha(70)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8 * s,
  );
}

// ─── Sparkle + star helpers ───────────────────────────────────────────────

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

// ─── Rank-tier overlay effects ────────────────────────────────────────────

void _applyRankFx(Canvas canvas, double s, int rankIndex, _Scheme sc) {
  final center = Offset(48 * s, 48 * s);
  switch (rankIndex) {
    case 0: // Bronze — bare, no overlay
      break;

    case 1: // Silver — horizontal shine sweep
      for (final y in [32.0, 40.0, 62.0, 70.0]) {
        canvas.drawLine(
          Offset(8 * s, y * s), Offset(88 * s, y * s),
          _stroke(Colors.white.withAlpha(22), 1.2 * s, StrokeCap.butt),
        );
      }
      break;

    case 2: // Gold — 4 sparkles at compass points
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
      canvas.drawLine(Offset(18 * s, 10 * s), Offset(88 * s, 80 * s),
          _stroke(Colors.white.withAlpha(55), 1.4 * s, StrokeCap.round));
      canvas.drawLine(Offset(10 * s, 22 * s), Offset(74 * s, 86 * s),
          _stroke(Colors.white.withAlpha(30), 1.0 * s, StrokeCap.round));
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

    case 5: // Enlightened — radiant rays + dual rings + 6-point star
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
      _draw6Star(canvas, s, 48, 48, 7, Colors.white.withAlpha(220));
      canvas.drawCircle(center, 2.0 * s, _fill(Colors.white));
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

// ─── Shape path helpers ───────────────────────────────────────────────────

// Classic heraldic shield
Path _shieldPath(double s) => Path()
  ..moveTo(20 * s, 18 * s)
  ..lineTo(76 * s, 18 * s)
  ..lineTo(76 * s, 56 * s)
  ..quadraticBezierTo(76 * s, 78 * s, 48 * s, 84 * s)
  ..quadraticBezierTo(20 * s, 78 * s, 20 * s, 56 * s)
  ..close();

// Pointy-top regular hexagon
Path _hexPath(double s, double cx, double cy, double r) {
  final path = Path();
  for (int i = 0; i < 6; i++) {
    final a = -math.pi / 2 + i * math.pi / 3;
    final x = (cx + r * math.cos(a)) * s;
    final y = (cy + r * math.sin(a)) * s;
    i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
  }
  path.close();
  return path;
}

// 5-point star
Path _star5Path(double s, double cx, double cy, double outerR, double innerR) {
  final path = Path();
  for (int i = 0; i < 10; i++) {
    final a = -math.pi / 2 + i * math.pi / 5;
    final r = i.isEven ? outerR : innerR;
    final x = (cx + r * math.cos(a)) * s;
    final y = (cy + r * math.sin(a)) * s;
    i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
  }
  path.close();
  return path;
}

// ─── Per-rank draw functions ──────────────────────────────────────────────

// Bronze — clean shield with field division line
void _paintBronze(Canvas canvas, double s, _Scheme sc) {
  final shield = _shieldPath(s);
  final bounds = Rect.fromLTRB(20 * s, 18 * s, 76 * s, 84 * s);

  canvas.drawPath(shield, _glowPaint(sc, 5 * s));
  canvas.drawPath(shield, _gradFill(bounds, sc));

  canvas.save();
  canvas.clipPath(shield);
  canvas.drawRect(
    Rect.fromLTRB(0, 0, 96 * s, 48 * s),
    _fill(sc.highlight.withAlpha(45)),
  );
  // Horizontal field division
  canvas.drawLine(
    Offset(22 * s, 50 * s), Offset(74 * s, 50 * s),
    _stroke(sc.border.withAlpha(140), 1.4 * s, StrokeCap.butt),
  );
  canvas.restore();

  canvas.drawPath(shield, _stroke(sc.border, 2.2 * s));
}

// Silver — shield with bold upward chevron
void _paintSilver(Canvas canvas, double s, _Scheme sc) {
  final shield = _shieldPath(s);
  final bounds = Rect.fromLTRB(20 * s, 18 * s, 76 * s, 84 * s);

  canvas.drawPath(shield, _glowPaint(sc, 5 * s));
  canvas.drawPath(shield, _gradFill(bounds, sc));

  canvas.save();
  canvas.clipPath(shield);
  canvas.drawRect(
    Rect.fromLTRB(0, 0, 96 * s, 48 * s),
    _fill(sc.highlight.withAlpha(50)),
  );
  final chevron = Path()
    ..moveTo(26 * s, 66 * s)
    ..lineTo(48 * s, 48 * s)
    ..lineTo(70 * s, 66 * s);
  canvas.drawPath(chevron, _stroke(sc.highlight, 5.0 * s));
  canvas.drawPath(chevron, _stroke(sc.border.withAlpha(140), 1.8 * s));
  canvas.restore();

  canvas.drawPath(shield, _stroke(sc.border, 2.2 * s));
}

// Gold — shield with 5-point star
void _paintGold(Canvas canvas, double s, _Scheme sc) {
  final shield = _shieldPath(s);
  final bounds = Rect.fromLTRB(20 * s, 18 * s, 76 * s, 84 * s);

  canvas.drawPath(shield, _glowPaint(sc, 6 * s));
  canvas.drawPath(shield, _gradFill(bounds, sc));

  canvas.save();
  canvas.clipPath(shield);
  canvas.drawRect(
    Rect.fromLTRB(0, 0, 96 * s, 48 * s),
    _fill(sc.highlight.withAlpha(55)),
  );
  final star = _star5Path(s, 48, 52, 18, 8);
  final starBounds = Rect.fromCenter(
      center: Offset(48 * s, 52 * s), width: 36 * s, height: 36 * s);
  canvas.drawPath(
    star,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [sc.highlight, sc.primary],
      ).createShader(starBounds),
  );
  canvas.drawPath(star, _stroke(sc.border, 1.4 * s));
  canvas.restore();

  canvas.drawPath(shield, _stroke(sc.border, 2.2 * s));
}

// Platinum — pointy-top hexagon with inner crystal ring and spokes
void _paintPlatinum(Canvas canvas, double s, _Scheme sc) {
  final hex = _hexPath(s, 48, 48, 31);
  final bounds = Rect.fromLTRB(17 * s, 17 * s, 79 * s, 79 * s);

  canvas.drawPath(hex, _glowPaint(sc, 6 * s));
  canvas.drawPath(hex, _gradFill(bounds, sc));

  canvas.save();
  canvas.clipPath(hex);
  canvas.drawRect(
    Rect.fromLTRB(0, 0, 96 * s, 48 * s),
    _fill(sc.highlight.withAlpha(60)),
  );
  canvas.restore();

  // Inner hexagon ring
  canvas.drawPath(
    _hexPath(s, 48, 48, 19),
    _stroke(sc.highlight.withAlpha(200), 1.6 * s),
  );

  // 6 spokes from center to inner hex vertices
  final spokeP = _stroke(sc.highlight.withAlpha(120), 0.9 * s);
  for (int i = 0; i < 6; i++) {
    final a = -math.pi / 2 + i * math.pi / 3;
    canvas.drawLine(
      Offset(48 * s, 48 * s),
      Offset((48 + 19 * math.cos(a)) * s, (48 + 19 * math.sin(a)) * s),
      spokeP,
    );
  }

  // Center dot
  canvas.drawCircle(Offset(48 * s, 48 * s), 3.0 * s, _fill(sc.highlight));
  canvas.drawPath(hex, _stroke(sc.border, 2.2 * s));
}

// Diamond — faceted rhombus gem with girdle and inner facets
void _paintDiamond(Canvas canvas, double s, _Scheme sc) {
  final gem = Path()
    ..moveTo(48 * s, 14 * s)
    ..lineTo(82 * s, 48 * s)
    ..lineTo(48 * s, 82 * s)
    ..lineTo(14 * s, 48 * s)
    ..close();

  canvas.drawPath(gem, _glowPaint(sc, 7 * s));

  // Upper half: highlight → primary
  final upper = Path()
    ..moveTo(48 * s, 14 * s)
    ..lineTo(82 * s, 48 * s)
    ..lineTo(14 * s, 48 * s)
    ..close();
  canvas.drawPath(
    upper,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [sc.highlight.withAlpha(240), sc.primary],
      ).createShader(Rect.fromLTRB(14 * s, 14 * s, 82 * s, 48 * s)),
  );

  // Lower half: primary → secondary
  final lower = Path()
    ..moveTo(14 * s, 48 * s)
    ..lineTo(82 * s, 48 * s)
    ..lineTo(48 * s, 82 * s)
    ..close();
  canvas.drawPath(
    lower,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [sc.primary, sc.secondary],
      ).createShader(Rect.fromLTRB(14 * s, 48 * s, 82 * s, 82 * s)),
  );

  // Facet lines
  final facetP = _stroke(sc.highlight.withAlpha(170), 1.1 * s);

  // Inner diamond (girdle facet)
  final innerGem = Path()
    ..moveTo(48 * s, 28 * s)
    ..lineTo(68 * s, 48 * s)
    ..lineTo(48 * s, 68 * s)
    ..lineTo(28 * s, 48 * s)
    ..close();
  canvas.drawPath(innerGem, _stroke(sc.highlight.withAlpha(160), 1.0 * s));

  // Upper facet lines from top to inner-left and inner-right
  canvas.drawLine(Offset(48 * s, 14 * s), Offset(28 * s, 48 * s), facetP);
  canvas.drawLine(Offset(48 * s, 14 * s), Offset(68 * s, 48 * s), facetP);
  // Lower facet lines from bottom to inner-left and inner-right
  canvas.drawLine(Offset(48 * s, 82 * s), Offset(28 * s, 48 * s), facetP);
  canvas.drawLine(Offset(48 * s, 82 * s), Offset(68 * s, 48 * s), facetP);

  // Horizontal girdle
  canvas.drawLine(
    Offset(14 * s, 48 * s), Offset(82 * s, 48 * s),
    _stroke(sc.highlight.withAlpha(210), 1.3 * s),
  );

  canvas.drawPath(gem, _stroke(sc.border, 2.2 * s));
}

// Enlightened — 3-peak royal crown with crown jewels
void _paintEnlightened(Canvas canvas, double s, _Scheme sc) {
  final crown = Path()
    ..moveTo(12 * s, 74 * s)
    ..lineTo(12 * s, 52 * s)
    ..lineTo(28 * s, 34 * s)
    ..lineTo(38 * s, 48 * s)
    ..lineTo(48 * s, 18 * s)
    ..lineTo(58 * s, 48 * s)
    ..lineTo(68 * s, 34 * s)
    ..lineTo(84 * s, 52 * s)
    ..lineTo(84 * s, 74 * s)
    ..close();

  final bounds = Rect.fromLTRB(12 * s, 18 * s, 84 * s, 74 * s);

  canvas.drawPath(crown, _glowPaint(sc, 6 * s));
  canvas.drawPath(crown, _gradFill(bounds, sc));

  canvas.save();
  canvas.clipPath(crown);

  // Base band (darker strip at bottom of crown)
  canvas.drawRect(
    Rect.fromLTRB(12 * s, 62 * s, 84 * s, 74 * s),
    _fill(sc.secondary.withAlpha(180)),
  );
  canvas.drawLine(
    Offset(12 * s, 62 * s), Offset(84 * s, 62 * s),
    _stroke(sc.border.withAlpha(130), 1.0 * s, StrokeCap.butt),
  );

  // Upper highlight on peaks
  canvas.drawRect(
    Rect.fromLTRB(0, 0, 96 * s, 46 * s),
    _fill(sc.highlight.withAlpha(55)),
  );
  canvas.restore();

  // Crown jewels at the 3 peaks
  for (final coords in [
    [28.0, 32.0],
    [48.0, 16.0],
    [68.0, 32.0],
  ]) {
    final gx = coords[0];
    final gy = coords[1];
    canvas.drawCircle(Offset(gx * s, gy * s), 5.5 * s, _glowPaint(sc, 4 * s));
    canvas.drawCircle(Offset(gx * s, gy * s), 4.5 * s, _fill(sc.highlight));
    canvas.drawCircle(Offset(gx * s, gy * s), 4.5 * s, _stroke(sc.border, 1.2 * s));
    canvas.drawCircle(
      Offset((gx - 1.5) * s, (gy - 1.5) * s), 1.5 * s,
      _fill(Colors.white.withAlpha(230)),
    );
  }

  canvas.drawPath(crown, _stroke(sc.border, 2.2 * s));

  // Re-draw band line on top of crown border for crispness
  canvas.save();
  canvas.clipPath(crown);
  canvas.drawLine(
    Offset(12 * s, 62 * s), Offset(84 * s, 62 * s),
    _stroke(sc.border, 1.0 * s, StrokeCap.butt),
  );
  canvas.restore();
}

// ═══════════════════════════════════════════════════════════════════════════
//  PUBLIC FACTORY
//  endeavour param kept for API compatibility — all endeavours now share
//  the same tier-based icons.
// ═══════════════════════════════════════════════════════════════════════════

CustomPainter getRankBadgePainter(
  String endeavour,
  int rankIndex,
  Color accent,
) =>
    _RankPainter(accent: accent, rankIndex: rankIndex.clamp(0, 5));

class _RankPainter extends CustomPainter {
  final Color accent;
  final int rankIndex;
  const _RankPainter({required this.accent, required this.rankIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    final sc = _kSchemes[rankIndex];
    _drawBg(canvas, size, accent, sc);
    switch (rankIndex) {
      case 0:
        _paintBronze(canvas, s, sc);
        break;
      case 1:
        _paintSilver(canvas, s, sc);
        break;
      case 2:
        _paintGold(canvas, s, sc);
        break;
      case 3:
        _paintPlatinum(canvas, s, sc);
        break;
      case 4:
        _paintDiamond(canvas, s, sc);
        break;
      case 5:
        _paintEnlightened(canvas, s, sc);
        break;
    }
    _applyRankFx(canvas, s, rankIndex, sc);
  }

  @override
  bool shouldRepaint(covariant _RankPainter old) =>
      old.rankIndex != rankIndex || old.accent != accent;
}
