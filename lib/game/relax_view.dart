import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'relax_engine.dart';

/// Soft, pastel vector art for the relaxing toys.
Paint _p(int c) => Paint()..color = Color(c);

Paint _stroke(int c, double w) => Paint()
  ..color = Color(c)
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round;

const _pastel = [0xFFFFADAD, 0xFFFFD6A5, 0xFFFDFFB6, 0xFFCAFFBF, 0xFF9BF6FF, 0xFFA0C4FF, 0xFFBDB2FF, 0xFFFFC6FF];
const _sandCols = [0xFFE76F51, 0xFFF4A261, 0xFFE9C46A, 0xFF2A9D8F, 0xFF264653, 0xFF8338EC];

void _bg(Canvas c, int top, int bottom) {
  c.drawRect(
    const Rect.fromLTWH(0, 0, kWorldW, kWorldH),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(top), Color(bottom)],
      ).createShader(const Rect.fromLTWH(0, 0, kWorldW, kWorldH)),
  );
}

void _timer(Canvas c, RelaxSim s) {
  if (s.meta.zen) return;
  final f = (s.timeLeft / s.timeTotal).clamp(0.0, 1.0);
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(100, 190, 800, 22), const Radius.circular(11)), _p(0x33000000));
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(100, 190, 800 * f, 22), const Radius.circular(11)),
    _p(s.freeze > 0 ? 0xFF9BF6FF : (f > 0.3 ? 0xFF95D5B2 : 0xFFFFADAD)),
  );
}

void _flash(Canvas c, RelaxSim s) {
  if (s.flashTicks <= 0) return;
  paintText(c, s.flash, const Offset(500, 120), 76, Colors.white.withValues(alpha: (s.flashTicks / 60).clamp(0.0, 1.0)));
}

void paintRelax(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as RelaxSim;
  switch (s) {
    case AntistressSim a:
      _anti(c, a, t);
    case PopItSim q:
      _popit(c, q, t);
    case SandSim q:
      _sand(c, q);
    case CleanSim q:
      _clean(c, q, t);
    case ZenSim q:
      _zen(c, q, t);
    default:
      break;
  }
  _timer(c, s);
  _flash(c, s);
}

// antistress ------------------------------------------------------------------
void _anti(Canvas c, AntistressSim s, double t) {
  _bg(c, 0xFFCDB4DB, 0xFFA2D2FF);
  switch (s.toy) {
    case kToyWrap:
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(110, 240, 780, 1120), const Radius.circular(30)), _p(0x55FFFFFF));
      for (final b in s.bubbles) {
        final o = Offset(b[0], b[1]);
        if (b[2] == 0) {
          c.drawCircle(o.translate(4, 6), 44, _p(0x22000000));
          c.drawCircle(o, 44, _p(0xCCFFFFFF));
          c.drawCircle(o.translate(-14, -14), 12, _p(0xFFFFFFFF));
        } else {
          c.drawCircle(o, 44, _stroke(0x88FFFFFF, 4));
          c.drawLine(o.translate(-20, -10), o.translate(18, 12), _stroke(0x88FFFFFF, 3));
        }
      }
    case kToySpinner:
      const o = Offset(500, 800);
      c.save();
      c.translate(o.dx, o.dy);
      c.rotate(s.angle);
      for (var k = 0; k < 3; k++) {
        final a = k * 2 * math.pi / 3;
        final e = Offset(math.cos(a) * 220, math.sin(a) * 220);
        c.drawLine(Offset.zero, e, _stroke(0xFF6A4C93, 110));
        c.drawCircle(e, 90, _p(_pastel[k * 2]));
        c.drawCircle(e, 50, _p(0xFFFFFFFF));
      }
      c.drawCircle(Offset.zero, 80, _p(0xFF6A4C93));
      c.drawCircle(Offset.zero, 40, _p(0xFFFFD6A5));
      c.restore();
      paintText(c, '${s.spins.floor()} / ${s.spinTarget}', const Offset(500, 1300), 64, Colors.white);
    case kToySwitch:
      paintText(c, s.neighbourMode ? '✦ + ✦' : '✦', const Offset(500, 330), 50, Colors.white70);
      for (var k = 0; k < s.lights.length; k++) {
        final (x, y) = s.switchPos(k);
        // target light (small) and the switch
        c.drawCircle(Offset(x, y - 62), 14, _p(s.target[k] ? 0xFFFFD166 : 0x55000000));
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y + 10), width: 110, height: 120), const Radius.circular(24));
        c.drawRRect(r, _p(s.lights[k] ? 0xFFFFD166 : 0xFF495057));
        c.drawRRect(r, _stroke(s.lights[k] == s.target[k] ? 0xFF52B788 : 0x55FFFFFF, 5));
        c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y + (s.lights[k] ? -10 : 30)), width: 50, height: 50), const Radius.circular(12)),
          _p(0xFFFFFFFF),
        );
      }
    default:
      final o = Offset(s.slimeX + s.stretchX * 0.5, s.slimeY + s.stretchY * 0.5);
      final w = 360 + s.stretchX.abs() * 0.8 - s.stretchY.abs() * 0.3, h = 300 + s.stretchY.abs() * 0.8 - s.stretchX.abs() * 0.3;
      final wob = math.sin(t * 6) * 8;
      c.drawOval(Rect.fromCenter(center: o.translate(0, 30), width: w + 20, height: h * 0.4), _p(0x22000000));
      c.drawOval(Rect.fromCenter(center: o, width: w + wob, height: h - wob), _p(0xFF80FFDB));
      c.drawOval(Rect.fromCenter(center: o.translate(-w * 0.2, -h * 0.2), width: w * 0.25, height: h * 0.15), _p(0x88FFFFFF));
      for (var k = 0; k < 7; k++) {
        c.drawCircle(o.translate(math.cos(k * 1.7) * w * 0.3, math.sin(k * 2.3) * h * 0.3), 10, _p(_pastel[k % 8]));
      }
      paintText(c, '${s.squishes} / ${s.squishTarget}', const Offset(500, 1300), 64, Colors.white);
  }
}

// pop it --------------------------------------------------------------------------
void _popit(Canvas c, PopItSim s, double t) {
  _bg(c, 0xFFFFF1E6, 0xFFFDE2E4);
  for (final b in s.bubbles) {
    final col = Color(_pastel[b.row % _pastel.length]);
    final o = Offset(b.x, b.y);
    // silicone base around each bubble
    c.drawCircle(o, 42, Paint()..color = Color.lerp(col, Colors.black, 0.08)!);
    if (b.hp > 0) {
      c.drawCircle(o.translate(3, 5), 32, _p(0x33000000));
      c.drawCircle(o, 32, Paint()..color = col);
      c.drawCircle(o.translate(-10, -10), 9, _p(0xAAFFFFFF));
      if (b.hp == 2) c.drawCircle(o, 22, _stroke(0x66FFFFFF, 4));
      if (b.star) paintText(c, '★', o, 30, Colors.white);
      if (b.order > 0) paintText(c, '${b.order}', o, 30, b.order == s.nextOrder ? Colors.black : Colors.black45);
    } else {
      c.drawCircle(o, 30, Paint()..color = Color.lerp(col, Colors.black, 0.25)!);
      c.drawCircle(o.translate(6, 6), 16, Paint()..color = Color.lerp(col, Colors.black, 0.35)!);
    }
  }
  if (s.combo > 4) paintText(c, 'x${s.combo}', const Offset(880, 1400), 50, Colors.black54);
}

// sand art ------------------------------------------------------------------------
void _sand(Canvas c, SandSim s) {
  _bg(c, 0xFFFFF8E7, 0xFFFFE8D6);
  const frame = Rect.fromLTRB(kSandL - 14, kSandBottom - kSandRows * kSandCell - 14, kSandL + kSandCols * kSandCell + 14, kSandBottom + 14);
  c.drawRRect(RRect.fromRectAndRadius(frame, const Radius.circular(18)), _p(0xFF8D6E63));
  c.drawRect(const Rect.fromLTRB(kSandL, kSandBottom - kSandRows * kSandCell, kSandL + kSandCols * kSandCell, kSandBottom), _p(0xFFFFFFFF));
  // target ghost
  for (var x = 0; x < kSandCols; x++) {
    final tg = s.target[x];
    for (var k = 0; k < tg.length; k++) {
      c.drawRect(
        Rect.fromLTWH(kSandL + x * kSandCell, kSandBottom - (k + 1) * kSandCell, kSandCell, kSandCell),
        Paint()..color = Color(_sandCols[tg[k] % _sandCols.length]).withValues(alpha: 0.18),
      );
    }
    final col = s.cols[x];
    for (var k = 0; k < col.length; k++) {
      final ok = k < tg.length && tg[k] == col[k];
      c.drawRect(
        Rect.fromLTWH(kSandL + x * kSandCell, kSandBottom - (k + 1) * kSandCell, kSandCell + 0.5, kSandCell + 0.5),
        Paint()..color = Color(_sandCols[col[k] % _sandCols.length]).withValues(alpha: ok ? 1 : 0.8),
      );
    }
    // target outline height
    final th = tg.length * kSandCell;
    c.drawLine(Offset(kSandL + x * kSandCell, kSandBottom - th), Offset(kSandL + (x + 1) * kSandCell, kSandBottom - th), _stroke(0x66000000, 2));
  }
  // palette
  for (var k = 0; k < s.colors; k++) {
    final (x, y) = s.swatch(k);
    c.drawCircle(Offset(x, y), k == s.color ? 58 : 46, _p(k == s.color ? 0xFF000000 : 0x33000000));
    c.drawCircle(Offset(x, y), 44, _p(_sandCols[k % _sandCols.length]));
  }
  paintText(c, '${(s.lastSim * 100).clamp(0, 100).round()}% / ${(s.threshold * 100).round()}%', const Offset(500, 270), 46, Colors.black54);
}

// cleaning ------------------------------------------------------------------------
void _clean(Canvas c, CleanSim s, double t) {
  _bg(c, 0xFFE0FBFC, 0xFFC2DFE3);
  const objCol = [0xFFF8F9FA, 0xFFBDE0FE, 0xFFE63946, 0xFFFFFFFF, 0xFFFFB4A2];
  const dirtCol = [0x00000000, 0xFF9C6644, 0xFF7F5539, 0xFF582F0E];
  for (var k = 0; k < s.dirt.length; k++) {
    final v = s.dirt[k];
    if (v < 0) continue;
    final r = Rect.fromLTWH(kCleanL + (k % kCleanW) * kCleanCell, kCleanT + (k ~/ kCleanW) * kCleanCell, kCleanCell + 0.6, kCleanCell + 0.6);
    c.drawRect(r, _p(objCol[s.object]));
    if (v > 0) c.drawRect(r, Paint()..color = Color(dirtCol[v]).withValues(alpha: 0.55 + v * 0.13));
  }
  // sparkles on clean areas
  for (var n = 0; n < 12; n++) {
    final k = (n * 977 + (t * 2).floor() * 131) % s.dirt.length;
    if (s.dirt[k] != 0) continue;
    final o = Offset(kCleanL + (k % kCleanW + 0.5) * kCleanCell, kCleanT + (k ~/ kCleanW + 0.5) * kCleanCell);
    c.drawLine(o.translate(-10, 0), o.translate(10, 0), _stroke(0xCCFFFFFF, 3));
    c.drawLine(o.translate(0, -10), o.translate(0, 10), _stroke(0xCCFFFFFF, 3));
  }
  if (s.wasDown) {
    final o = Offset(s.lastX, s.lastY);
    c.drawCircle(o, s.radius, _stroke(0x66FFFFFF, 4));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 110, height: 70), const Radius.circular(16)), _p(0xFFFFD166));
    for (var b = 0; b < 4; b++) {
      c.drawCircle(o.translate(math.cos(t * 5 + b) * 60, math.sin(t * 4 + b) * 40 - 40), 10, _p(0xAAFFFFFF));
    }
  }
  paintText(c, '${(s.cleanRatio * 100).round()}%', const Offset(500, 1440), 60, Colors.black54);
}

// zen garden ----------------------------------------------------------------------
void _zen(Canvas c, ZenSim s, double t) {
  _bg(c, 0xFFB7E4C7, 0xFF74C69D);
  c.drawRect(const Rect.fromLTWH(kZenL - 16, kZenT - 16, kZenW * kZenCell + 32, kZenH * kZenCell + 32), _p(0xFF6B4226));
  for (var k = 0; k < s.cells.length; k++) {
    final x = kZenL + (k % kZenW) * kZenCell, y = kZenT + (k ~/ kZenW) * kZenCell;
    final v = s.cells[k];
    c.drawRect(Rect.fromLTWH(x, y, kZenCell + 0.5, kZenCell + 0.5), _p(v == 3 ? 0xFFE9DCC9 : 0xFFF1E3C6));
    if (v == 1) {
      for (var l = 8.0; l < kZenCell; l += 11) {
        c.drawLine(Offset(x, y + l), Offset(x + kZenCell, y + l), _stroke(0x55A68A64, 2));
      }
    } else if (v == 2) {
      for (var l = 8.0; l < kZenCell; l += 11) {
        c.drawLine(Offset(x + l, y), Offset(x + l, y + kZenCell), _stroke(0x55A68A64, 2));
      }
    }
  }
  // rocks drawn as rounded stones over their cells
  for (var k = 0; k < s.cells.length; k++) {
    if (s.cells[k] != 3) continue;
    final o = Offset(kZenL + (k % kZenW + 0.5) * kZenCell, kZenT + (k ~/ kZenW + 0.5) * kZenCell);
    c.drawCircle(o, kZenCell * 0.62, _p(0xFF6C757D));
  }
  for (final sp in s.spots) {
    final o = Offset(sp[0], sp[1]);
    if (sp[2] == 0) {
      c.drawCircle(o, 42 + math.sin(t * 3) * 4, _stroke(0xAAFFFFFF, 5));
    } else {
      c.drawOval(Rect.fromCenter(center: o.translate(4, 8), width: 90, height: 50), _p(0x33000000));
      c.drawOval(Rect.fromCenter(center: o, width: 86, height: 60), _p(0xFF495057));
      c.drawOval(Rect.fromCenter(center: o.translate(-12, -10), width: 26, height: 14), _p(0x55FFFFFF));
    }
  }
  for (final l in s.leaves) {
    c.save();
    c.translate(l.x, l.y);
    c.rotate(math.sin(t * 2 + l.phase) * 0.8);
    c.drawOval(const Rect.fromLTWH(-28, -14, 56, 28), _p(0xFFE76F51));
    c.drawLine(const Offset(-24, 0), const Offset(24, 0), _stroke(0xFF9D0208, 2));
    c.restore();
  }
  paintText(c, '🍂 ${s.leafCaught}/${s.leafGoal}   ⬤ ${s.spots.where((x) => x[2] == 1).length}/${s.spots.length}   ≋ ${(s.rakeRatio * 100).round()}%',
      const Offset(500, 1380), 40, Colors.white);
}

Sfx? relaxSound(ArcadeSim sim) => switch ((sim as RelaxSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.place,
      3 => Sfx.combo,
      4 => Sfx.error,
      5 => Sfx.clear,
      _ => null,
    };
