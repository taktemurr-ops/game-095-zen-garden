import 'dart:math' as math;

import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// Calm, tactile games on the shared arcade framework: stress-relief toys,
/// pop-it boards, sand art, ASMR cleaning and a zen garden.
///
/// A level is a sequence of short *rounds* (tasks). Rounds have a generous
/// timer (none in Zen); running out of time costs a life and restarts the
/// same round. Layouts are pure functions of (seed, round, difficulty).
enum RelaxKind { antistress, popit, sand, cleaning, zen }

class RelaxLevel {
  final ArcadeMeta meta;
  final RelaxKind kind;
  final int difficulty;
  final int rounds; // 0 = unlimited (endless / time attack / zen)
  final int theme;
  const RelaxLevel(this.meta, this.kind, this.difficulty, this.rounds, this.theme);
}

RelaxLevel generateRelax(RelaxKind kind, LevelSpec spec) {
  final m = ArcadeMeta.of(spec);
  final d = spec.difficulty.clamp(1, 10);
  var rounds = switch (kind) {
    RelaxKind.antistress => d >= 5 ? 4 : 3,
    RelaxKind.popit => d >= 7 ? 2 : 1,
    _ => 1,
  };
  if (!m.goal) rounds = 0;
  return RelaxLevel(m, kind, d, rounds, spec.theme % 4);
}

double _dist2(double ax, double ay, double bx, double by) => (ax - bx) * (ax - bx) + (ay - by) * (ay - by);

abstract class RelaxSim extends ArcadeSim {
  final RelaxLevel level;
  int round = 0;
  int timeLeft = 0, timeTotal = 1;
  int freeze = 0;
  int lastEvent = 0; // 1 touch, 2 good, 3 great, 4 bad, 5 round done
  String flash = '';
  int flashTicks = 0;
  // pointer tracking
  bool wasDown = false;
  double lastX = -1, lastY = -1;
  int bestCombo = 0;

  /// Autopilot scratch (never read by the game rules).
  final List<ArcadeInput> botQueue = [];
  int botCursor = 0;

  factory RelaxSim(RelaxLevel l) => switch (l.kind) {
        RelaxKind.antistress => AntistressSim(l),
        RelaxKind.popit => PopItSim(l),
        RelaxKind.sand => SandSim(l),
        RelaxKind.cleaning => CleanSim(l),
        RelaxKind.zen => ZenSim(l),
      };

  RelaxSim.base(this.level) : super(level.meta, lives: 3) {
    _start();
  }

  int get rd => (level.difficulty + (level.rounds == 0 ? round ~/ 2 : 0)).clamp(1, 10);
  int get roundSeed => mixSeed([meta.seed, 7331, round]);

  void _start() {
    botCursor = 0;
    botQueue.clear();
    setupRound();
    timeTotal = roundSeconds() * kTicksPerSecond;
    timeLeft = timeTotal;
  }

  void setupRound();

  /// Seconds available for the running round.
  int roundSeconds();

  double get roundProgress;

  void step(ArcadeInput i);

  bool get roundComplete;

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (flashTicks > 0) flashTicks--;
    if (freeze > 0) {
      freeze--;
    } else if (!meta.zen) {
      timeLeft--;
    }
    step(input);
    wasDown = input.down && input.hasPointer;
    if (input.hasPointer) {
      lastX = input.x;
      lastY = input.y;
    }
    if (over) return;
    if (roundComplete) {
      score += 200 + (timeLeft * 100 ~/ math.max(1, timeTotal)) * 3;
      round++;
      lastEvent = 5;
      say(_cheer());
      if (level.rounds > 0 && round >= level.rounds) {
        win();
        return;
      }
      _start();
    } else if (timeLeft <= 0 && !meta.zen) {
      lastEvent = 4;
      shield = 0;
      hit();
    }
  }

  String _cheer() => const ['NICE!', 'GREAT!', 'SO CALM!', 'PERFECT!'][round % 4];

  void say(String s) {
    flash = s;
    flashTicks = 60;
  }

  @override
  void onLifeLost() => _start();

  /// Slow motion is replaced by a calm "time freeze" so no touch is lost.
  @override
  bool useSlow() {
    if (over || freeze > 0) return false;
    freeze = 600;
    return true;
  }

  @override
  double get progress =>
      level.rounds > 0 ? ((round + roundProgress.clamp(0.0, 1.0)) / level.rounds).clamp(0.0, 1.0) : 0;

  @override
  String get goalText {
    final pct = (roundProgress.clamp(0.0, 1.0) * 100).round();
    final r = level.rounds > 0 ? '${round + 1}/${level.rounds} • ' : '${round + 1} • ';
    return '$r$pct%';
  }

  @override
  int get stars => won ? math.min(lifeStars(this, 3), timeLeft > timeTotal ~/ 3 ? 3 : 2) : 0;
}

// ---------------------------------------------------------------------------
// 091 Antistress: a rotating set of fidget toys.

const kToyWrap = 0, kToySpinner = 1, kToySwitch = 2, kToySlime = 3;

class AntistressSim extends RelaxSim {
  int toy = 0;
  // bubble wrap
  final List<List<double>> bubbles = []; // x, y, popped(0/1)
  int popped = 0;
  // spinner
  double angle = 0, omega = 0, spins = 0;
  int spinTarget = 20;
  // switches
  List<bool> lights = [], target = [];
  List<int> solution = [];
  bool neighbourMode = false;
  int cols = 3;
  // slime
  double slimeX = 500, slimeY = 800, stretchX = 0, stretchY = 0;
  bool grabbed = false;
  int squishes = 0, squishTarget = 8;
  int totalPops = 0, totalSpins = 0, totalSquish = 0, toysDone = 0;
  AntistressSim(super.l) : super.base();

  @override
  void setupRound() {
    final r = SeededRandom(roundSeed);
    final d = rd;
    toy = (round + (meta.seed % 4)) % 4;
    bubbles.clear();
    popped = 0;
    if (toy == kToyWrap) {
      final c = 5 + (d >= 5 ? 1 : 0), rw = 6 + d ~/ 2;
      for (var j = 0; j < rw; j++) {
        for (var i = 0; i < c; i++) {
          bubbles.add([180 + i * (640 / (c - 1)) + (j.isOdd ? 30 : 0), 300 + j * (1000 / math.max(1, rw - 1)), 0]);
        }
      }
    } else if (toy == kToySpinner) {
      angle = 0;
      omega = 0;
      spins = 0;
      spinTarget = 15 + d * 3;
    } else if (toy == kToySwitch) {
      cols = d >= 6 ? 4 : 3;
      final rows = d >= 3 ? 4 : 3;
      final n = cols * rows;
      neighbourMode = d >= 5;
      target = List.generate(n, (_) => r.chance(0.5));
      lights = List.of(target);
      solution = [];
      final presses = 3 + d ~/ 2;
      for (var k = 0; k < presses; k++) {
        final p = r.nextInt(n);
        if (solution.contains(p)) continue;
        solution.add(p);
        _press(p);
      }
      if (solution.isEmpty) {
        solution.add(0);
        _press(0);
      }
    } else {
      slimeX = 500;
      slimeY = 820;
      stretchX = stretchY = 0;
      grabbed = false;
      squishes = 0;
      squishTarget = 6 + d;
    }
  }

  int get rows => lights.length ~/ cols;

  void _press(int p) {
    lights[p] = !lights[p];
    if (!neighbourMode) return;
    final x = p % cols, y = p ~/ cols;
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= cols || ny >= rows) continue;
      lights[ny * cols + nx] = !lights[ny * cols + nx];
    }
  }

  (double, double) switchPos(int p) {
    final x = p % cols, y = p ~/ cols;
    final w = 600 / cols;
    return (200 + w * (x + 0.5), 520 + y * 190.0);
  }

  @override
  int roundSeconds() => switch (toy) {
        kToyWrap => 40 + bubbles.length ~/ 2,
        kToySpinner => 45,
        kToySwitch => 50,
        _ => 50,
      };

  @override
  void step(ArcadeInput i) {
    switch (toy) {
      case kToyWrap:
        if (i.down && i.hasPointer) {
          for (final b in bubbles) {
            if (b[2] == 0 && _dist2(b[0], b[1], i.x, i.y) < 50 * 50) {
              b[2] = 1;
              popped++;
              totalPops++;
              score += 10;
              lastEvent = 2;
            }
          }
        }
      case kToySpinner:
        if (i.down && i.hasPointer && wasDown) {
          // tangential finger speed around the hub spins it
          final rx = lastX - 500, ry = lastY - 800;
          final mx = i.x - lastX, my = i.y - lastY;
          final rl = math.max(60.0, math.sqrt(rx * rx + ry * ry));
          omega += (rx * my - ry * mx) / (rl * rl) * 0.8;
        }
        if (i.swipe == 1 || i.swipe == 3) omega += 0.18 * (i.swipe == 1 ? 1 : -1);
        omega = clampD(omega, -0.9, 0.9) * 0.994;
        angle += omega;
        final before = spins.floor();
        spins += omega.abs() / (2 * math.pi);
        if (spins.floor() > before) {
          totalSpins++;
          score += 5;
          lastEvent = 2;
        }
      case kToySwitch:
        if (i.tap && i.hasPointer) {
          for (var p = 0; p < lights.length; p++) {
            final (x, y) = switchPos(p);
            if ((i.x - x).abs() < 70 && (i.y - y).abs() < 80) {
              _press(p);
              lastEvent = 1;
              break;
            }
          }
        }
      default:
        if (i.down && i.hasPointer) {
          if (!grabbed && _dist2(i.x, i.y, slimeX, slimeY) < 230 * 230) grabbed = true;
          if (grabbed) {
            stretchX = clampD(i.x - slimeX, -320, 320);
            stretchY = clampD(i.y - slimeY, -420, 420);
          }
        } else {
          if (grabbed && math.sqrt(stretchX * stretchX + stretchY * stretchY) > 150) {
            squishes++;
            totalSquish++;
            score += 15;
            lastEvent = 3;
          }
          grabbed = false;
          stretchX *= 0.8;
          stretchY *= 0.8;
        }
    }
  }

  @override
  bool get roundComplete {
    final ok = switch (toy) {
      kToyWrap => popped >= bubbles.length,
      kToySpinner => spins >= spinTarget,
      kToySwitch => _matches(),
      _ => squishes >= squishTarget,
    };
    if (ok) toysDone++;
    return ok;
  }

  bool _matches() {
    for (var k = 0; k < lights.length; k++) {
      if (lights[k] != target[k]) return false;
    }
    return true;
  }

  @override
  double get roundProgress => switch (toy) {
        kToyWrap => bubbles.isEmpty ? 1 : popped / bubbles.length,
        kToySpinner => spins / spinTarget,
        kToySwitch => lights.isEmpty ? 1 : List.generate(lights.length, (k) => lights[k] == target[k] ? 1 : 0).fold<int>(0, (a, b) => a + b) / lights.length,
        _ => squishes / squishTarget,
      };

  @override
  bool useBooster() {
    // Helping hand: completes a chunk of the current toy.
    if (over) return false;
    switch (toy) {
      case kToyWrap:
        var k = 0;
        for (final b in bubbles) {
          if (b[2] == 0 && k < 10) {
            b[2] = 1;
            popped++;
            k++;
          }
        }
      case kToySpinner:
        omega = 0.9;
      case kToySwitch:
        lights = List.of(target);
      default:
        squishes = math.min(squishTarget, squishes + 3);
    }
    return true;
  }

  @override
  Map<String, int> get stats => {
        'bubbles_popped': totalPops,
        'spins': totalSpins,
        'squishes': totalSquish,
        'toys_finished': toysDone,
      };
}

// ---------------------------------------------------------------------------
// 092 Pop It: shaped silicone boards.

class PopBubble {
  final double x, y;
  final int row;
  int hp; // 1 normal, 2 double
  final int order; // 0 = free, n = must follow sequence
  final bool star; // pops neighbours
  PopBubble(this.x, this.y, this.row, this.hp, this.order, this.star);
}

class PopItSim extends RelaxSim {
  final List<PopBubble> bubbles = [];
  int shape = 0, nextOrder = 1, maxOrder = 0;
  int popCount = 0, boardsDone = 0, starPops = 0, combo = 0, comboTicks = 0;
  final Set<int> touched = {};
  PopItSim(super.l) : super.base();

  static bool inShape(int shape, double u, double v) {
    // u, v in -1..1
    switch (shape) {
      case 0:
        return u * u + v * v <= 1;
      case 1: // heart
        final x = u * 1.2, y = -v * 1.25 + 0.25;
        final a = x * x + y * y - 1;
        return a * a * a - x * x * y * y * y <= 0;
      case 2: // star-ish
        final r = math.sqrt(u * u + v * v);
        final t = math.atan2(v, u);
        return r <= 0.62 + 0.38 * math.cos(5 * t).abs();
      case 3: // hexagon
        return u.abs() <= 0.95 && (u.abs() * 0.5 + v.abs() * 0.866) <= 0.9;
      default:
        return u.abs() <= 0.95 && v.abs() <= 0.95;
    }
  }

  @override
  void setupRound() {
    final r = SeededRandom(roundSeed);
    final d = rd;
    shape = r.nextInt(5);
    bubbles.clear();
    touched.clear();
    nextOrder = 1;
    const sp = 78.0;
    final rows = 11;
    final cols = 10;
    final orderCount = d >= 5 ? 3 + d ~/ 2 : 0;
    final cand = <(double, double, int)>[];
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final x = 500 + (i - (cols - 1) / 2) * sp + (j.isOdd ? sp / 2 : 0) - sp / 4;
        final y = 820 + (j - (rows - 1) / 2) * sp * 0.9;
        if (inShape(shape, (x - 500) / 400, (y - 820) / 430)) cand.add((x, y, j));
      }
    }
    final orderIdx = <int>{};
    while (orderIdx.length < math.min(orderCount, cand.length)) {
      orderIdx.add(r.nextInt(cand.length));
    }
    var o = 0;
    for (var k = 0; k < cand.length; k++) {
      final (x, y, j) = cand[k];
      final dbl = d >= 3 && r.chance(0.08 + d * 0.02);
      final star = d >= 2 && r.chance(0.04);
      bubbles.add(PopBubble(x, y, j, dbl ? 2 : 1, orderIdx.contains(k) ? ++o : 0, star && !orderIdx.contains(k)));
    }
    maxOrder = o;
  }

  @override
  int roundSeconds() => 25 + bubbles.length ~/ 2 + maxOrder * 2;

  int get left => bubbles.where((b) => b.hp > 0).length;

  void _pop(PopBubble b) {
    if (b.hp <= 0) return;
    if (b.order > 0 && b.order != nextOrder) {
      // wrong order: shake and lose some time
      timeLeft -= 120;
      lastEvent = 4;
      say('${nextOrder}!');
      return;
    }
    b.hp--;
    if (b.hp > 0) {
      lastEvent = 1;
      return;
    }
    if (b.order > 0) nextOrder++;
    popCount++;
    combo++;
    comboTicks = 30;
    bestCombo = math.max(bestCombo, combo);
    score += 10 + math.min(combo, 20);
    lastEvent = 2;
    if (b.star) {
      starPops++;
      lastEvent = 3;
      for (final o in bubbles) {
        if (o.hp > 0 && o.order == 0 && _dist2(o.x, o.y, b.x, b.y) < 170 * 170) {
          o.hp = 0;
          popCount++;
          score += 10;
        }
      }
    }
  }

  @override
  void step(ArcadeInput i) {
    if (comboTicks > 0) {
      comboTicks--;
    } else {
      combo = 0;
    }
    if (!(i.down && i.hasPointer)) {
      touched.clear();
      return;
    }
    if (i.tap) touched.clear();
    for (var k = 0; k < bubbles.length; k++) {
      final b = bubbles[k];
      if (b.hp > 0 && !touched.contains(k) && _dist2(b.x, b.y, i.x, i.y) < 36 * 36) {
        touched.add(k); // one press per touch; lift to press a double bubble again
        _pop(b);
      }
    }
  }

  @override
  bool get roundComplete {
    final done = left == 0;
    if (done) boardsDone++;
    return done;
  }

  @override
  double get roundProgress => bubbles.isEmpty ? 1 : 1 - left / bubbles.length;

  @override
  bool useBooster() {
    // Pop wave: clears a free row.
    if (over) return false;
    final rowsLeft = bubbles.where((b) => b.hp > 0 && b.order == 0).map((b) => b.row).toSet().toList()..sort();
    if (rowsLeft.isEmpty) return false;
    for (final b in bubbles) {
      if (b.row == rowsLeft.first && b.order == 0 && b.hp > 0) {
        b.hp = 0;
        popCount++;
      }
    }
    return true;
  }

  @override
  Map<String, int> get stats => {
        'bubbles_popped': popCount,
        'boards_cleared': boardsDone,
        'star_pops': starPops,
        'best_combo': bestCombo,
      };
}

// ---------------------------------------------------------------------------
// 093 Sand Art: pour coloured sand to match the layered picture.

const int kSandCols = 35, kSandRows = 50;
const double kSandL = 150, kSandCell = 20, kSandBottom = 1340;

class SandSim extends RelaxSim {
  int colors = 3;
  int color = 0;
  final List<List<int>> cols = List.generate(kSandCols, (_) => <int>[]);
  final List<List<int>> target = List.generate(kSandCols, (_) => <int>[]);
  int pourTick = 0;
  double threshold = 0.7;
  int grains = 0, artsDone = 0, perfect = 0;
  double lastSim = 0;
  SandSim(super.l) : super.base();

  @override
  void setupRound() {
    final r = SeededRandom(roundSeed);
    final d = rd;
    colors = (3 + d ~/ 3).clamp(3, 6);
    color = 0;
    threshold = 0.66 + d * 0.022;
    for (final c in cols) {
      c.clear();
    }
    // layered bands: each band thickness varies smoothly along x
    final ph = List.generate(colors, (_) => r.nextDouble() * 6.28);
    final fr = List.generate(colors, (_) => 0.12 + r.nextDouble() * 0.25);
    final base = List.generate(colors, (_) => 3.0 + r.nextDouble() * 4);
    final order = List.generate(colors, (k) => k)..shuffle(math.Random(roundSeed));
    final bandCount = colors + (d >= 6 ? 2 : 0);
    for (var x = 0; x < kSandCols; x++) {
      final t = target[x]..clear();
      for (var b = 0; b < bandCount; b++) {
        final c = order[b % colors];
        final h = (base[c] + 2.6 * math.sin(x * fr[c] + ph[c] + b)).round().clamp(1, 9);
        for (var k = 0; k < h && t.length < kSandRows - 4; k++) {
          t.add(c);
        }
      }
    }
  }

  @override
  int roundSeconds() => 70 + colors * 12;

  int targetCells() => target.fold(0, (a, t) => a + t.length);

  double similarity() {
    var ok = 0, over = 0;
    for (var x = 0; x < kSandCols; x++) {
      final c = cols[x], t = target[x];
      for (var k = 0; k < c.length; k++) {
        if (k < t.length) {
          if (c[k] == t[k]) ok++;
        } else {
          over++;
        }
      }
    }
    return (ok - over * 0.5) / math.max(1, targetCells());
  }

  int columnAt(double x) => ((x - kSandL) / kSandCell).floor();

  (double, double) swatch(int c) => (200 + c * (600 / math.max(1, colors - 1)), 1470);

  void _settle(int x) {
    // avalanche: a grain slides to a lower neighbour when the slope is steep
    var cx = x;
    for (var guard = 0; guard < 40; guard++) {
      final h = cols[cx].length;
      final l = cx > 0 ? cols[cx - 1].length : 1 << 20;
      final rr = cx < kSandCols - 1 ? cols[cx + 1].length : 1 << 20;
      final lower = l <= rr ? cx - 1 : cx + 1;
      final lh = math.min(l, rr);
      if (h - lh <= 2) return;
      cols[lower].add(cols[cx].removeLast());
      cx = lower;
    }
  }

  @override
  void step(ArcadeInput i) {
    if (i.tap && i.hasPointer && i.y > 1400) {
      for (var c = 0; c < colors; c++) {
        final (sx, sy) = swatch(c);
        if ((i.x - sx).abs() < 60 && (i.y - sy).abs() < 70) {
          color = c;
          lastEvent = 1;
        }
      }
      return;
    }
    if (i.dirX != 0 && i.tap) color = (color + (i.dirX > 0 ? 1 : colors - 1)) % colors;
    if (i.down && i.hasPointer && i.y < 1400) {
      final x = columnAt(i.x);
      if (x < 0 || x >= kSandCols) return;
      pourTick++;
      if (pourTick % 3 == 0 && cols[x].length < kSandRows) {
        cols[x].add(color);
        grains++;
        _settle(x);
        if (grains % 10 == 0) score += 5;
        lastEvent = grains % 6 == 0 ? 1 : 0;
      }
    }
    lastSim = similarity();
  }

  @override
  bool get roundComplete {
    if (lastSim >= threshold) {
      artsDone++;
      if (lastSim >= 0.92) perfect++;
      score += (lastSim * 300).round();
      return true;
    }
    return false;
  }

  @override
  double get roundProgress => lastSim / threshold;

  @override
  bool useBooster() {
    // Smooth: removes the top grain from every overfilled column.
    if (over) return false;
    for (var x = 0; x < kSandCols; x++) {
      while (cols[x].length > target[x].length) {
        cols[x].removeLast();
      }
      if (cols[x].isNotEmpty && cols[x].length <= target[x].length && cols[x].last != target[x][cols[x].length - 1]) {
        cols[x].removeLast();
      }
    }
    lastSim = similarity();
    return true;
  }

  @override
  Map<String, int> get stats => {
        'grains_poured': grains,
        'artworks': artsDone,
        'perfect_art': perfect,
      };
}

// ---------------------------------------------------------------------------
// 094 ASMR Cleaning: scrub the dirt off everyday objects.

const int kCleanW = 32, kCleanH = 44;
const double kCleanL = 100, kCleanT = 250, kCleanCell = 25;

class CleanSim extends RelaxSim {
  int object = 0;
  final List<int> dirt = List.filled(kCleanW * kCleanH, -1); // -1 outside, 0 clean, 1..3 layers
  final List<double> wear = List.filled(kCleanW * kCleanH, 0);
  int dirtTotal = 0, dirtLeft = 0;
  int cleaned = 0, objectsDone = 0, sparkles = 0;
  double radius = 70;
  CleanSim(super.l) : super.base();

  static bool inObject(int obj, double u, double v) {
    switch (obj) {
      case 0: // plate
        return u * u + v * v <= 0.9;
      case 1: // window
        return u.abs() <= 0.9 && v.abs() <= 0.92;
      case 2: // car
        final body = u.abs() <= 0.95 && v >= -0.05 && v <= 0.45;
        final cabin = u.abs() <= 0.55 && v >= -0.45 && v < -0.05;
        final wheel1 = (u + 0.55) * (u + 0.55) + (v - 0.5) * (v - 0.5) <= 0.06;
        final wheel2 = (u - 0.55) * (u - 0.55) + (v - 0.5) * (v - 0.5) <= 0.06;
        return body || cabin || wheel1 || wheel2;
      case 3: // sneaker
        final sole = u.abs() <= 0.95 && v >= 0.15 && v <= 0.4;
        final upper = (u + 0.1) * (u + 0.1) / 0.6 + (v - 0.05) * (v - 0.05) / 0.12 <= 1;
        return sole || upper;
      default: // vase
        final w = 0.35 + 0.35 * math.sin((v + 1) / 2 * math.pi * 1.1);
        return v.abs() <= 0.95 && u.abs() <= w;
    }
  }

  @override
  void setupRound() {
    final r = SeededRandom(roundSeed);
    final d = rd;
    object = r.nextInt(5);
    radius = 74 - d * 2.0;
    dirtTotal = 0;
    // blotches of dirt
    final blobs = List.generate(6 + d, (_) => [r.nextDouble() * 2 - 1, r.nextDouble() * 2 - 1, 0.25 + r.nextDouble() * 0.35, 1 + r.nextInt(math.min(3, 1 + d ~/ 3)).toDouble()]);
    for (var j = 0; j < kCleanH; j++) {
      for (var i = 0; i < kCleanW; i++) {
        final u = (i + 0.5) / kCleanW * 2 - 1, v = (j + 0.5) / kCleanH * 2 - 1;
        final k = j * kCleanW + i;
        wear[k] = 0;
        if (!inObject(object, u, v)) {
          dirt[k] = -1;
          continue;
        }
        var lvl = 1;
        for (final b in blobs) {
          if ((u - b[0]) * (u - b[0]) + (v - b[1]) * (v - b[1]) < b[2] * b[2]) lvl = math.max(lvl, b[3].toInt());
        }
        dirt[k] = lvl;
        dirtTotal += lvl;
      }
    }
    dirtLeft = dirtTotal;
  }

  @override
  int roundSeconds() => 30 + dirtTotal ~/ 22;

  @override
  void step(ArcadeInput i) {
    if (!(i.down && i.hasPointer)) return;
    // scrub along the finger path
    final steps = wasDown ? math.max(1, (math.sqrt(_dist2(lastX, lastY, i.x, i.y)) / 20).ceil()) : 1;
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      final px = wasDown ? lastX + (i.x - lastX) * t : i.x, py = wasDown ? lastY + (i.y - lastY) * t : i.y;
      _scrub(px, py, 1 / steps);
    }
  }

  void _scrub(double px, double py, double amount) {
    final i0 = ((px - radius - kCleanL) / kCleanCell).floor().clamp(0, kCleanW - 1);
    final i1 = ((px + radius - kCleanL) / kCleanCell).floor().clamp(0, kCleanW - 1);
    final j0 = ((py - radius - kCleanT) / kCleanCell).floor().clamp(0, kCleanH - 1);
    final j1 = ((py + radius - kCleanT) / kCleanCell).floor().clamp(0, kCleanH - 1);
    for (var j = j0; j <= j1; j++) {
      for (var i = i0; i <= i1; i++) {
        final k = j * kCleanW + i;
        if (dirt[k] <= 0) continue;
        final cx = kCleanL + (i + 0.5) * kCleanCell, cy = kCleanT + (j + 0.5) * kCleanCell;
        if (_dist2(cx, cy, px, py) > radius * radius) continue;
        wear[k] += 0.35 * amount;
        if (wear[k] >= 1) {
          wear[k] = 0;
          dirt[k]--;
          dirtLeft--;
          cleaned++;
          if (cleaned % 25 == 0) score += 5;
          if (dirt[k] == 0) {
            lastEvent = cleaned % 3 == 0 ? 1 : lastEvent;
          }
        }
      }
    }
  }

  double get cleanRatio => dirtTotal == 0 ? 1 : 1 - dirtLeft / dirtTotal;

  @override
  bool get roundComplete {
    if (cleanRatio >= 0.97) {
      objectsDone++;
      sparkles++;
      return true;
    }
    return false;
  }

  @override
  double get roundProgress => cleanRatio / 0.97;

  @override
  bool useBooster() {
    // Pressure washer: wipes a third of the remaining dirt.
    if (over) return false;
    var k = 0;
    for (var c = 0; c < dirt.length; c++) {
      if (dirt[c] > 0 && k.isEven) {
        dirtLeft -= dirt[c];
        cleaned += dirt[c];
        dirt[c] = 0;
      }
      if (dirt[c] >= 0) k++;
    }
    return true;
  }

  @override
  Map<String, int> get stats => {
        'dirt_cleaned': cleaned,
        'objects_cleaned': objectsDone,
        'sparkles': sparkles,
      };
}

// ---------------------------------------------------------------------------
// 095 Zen Garden: rake the sand, place the stones, catch falling leaves.

const int kZenW = 20, kZenH = 26;
const double kZenL = 100, kZenT = 250, kZenCell = 40;

class Leaf {
  double x, y, vx;
  final double phase;
  Leaf(this.x, this.y, this.vx, this.phase);
}

class ZenSim extends RelaxSim {
  final List<int> cells = List.filled(kZenW * kZenH, 0); // 0 sand, 1 raked-h, 2 raked-v, 3 rock
  int sandCells = 0, raked = 0;
  double rakeGoal = 0.8;
  final List<List<double>> spots = []; // x, y, placed
  final List<Leaf> leaves = [];
  int leafGoal = 5, leafCaught = 0, leafTimer = 0;
  int totalRaked = 0, stonesPlaced = 0, leavesTotal = 0, gardens = 0;
  ZenSim(super.l) : super.base();

  @override
  void setupRound() {
    final r = SeededRandom(roundSeed);
    final d = rd;
    for (var k = 0; k < cells.length; k++) {
      cells[k] = 0;
    }
    // rocks
    final rocks = 2 + d ~/ 2;
    for (var n = 0; n < rocks; n++) {
      final cx = 2 + r.nextInt(kZenW - 4), cy = 2 + r.nextInt(kZenH - 4), rr = 1 + r.nextInt(2);
      for (var j = cy - rr; j <= cy + rr; j++) {
        for (var i = cx - rr; i <= cx + rr; i++) {
          if ((i - cx) * (i - cx) + (j - cy) * (j - cy) <= rr * rr) cells[j * kZenW + i] = 3;
        }
      }
    }
    sandCells = cells.where((c) => c == 0).length;
    raked = 0;
    rakeGoal = 0.7 + d * 0.02;
    spots.clear();
    final nSpots = 1 + d ~/ 3;
    var guard = 0;
    while (spots.length < nSpots && guard++ < 200) {
      final i = 1 + r.nextInt(kZenW - 2), j = 1 + r.nextInt(kZenH - 2);
      if (cells[j * kZenW + i] == 3) continue;
      final x = kZenL + (i + 0.5) * kZenCell, y = kZenT + (j + 0.5) * kZenCell;
      if (spots.any((s) => _dist2(s[0], s[1], x, y) < 200 * 200)) continue;
      spots.add([x, y, 0]);
    }
    leaves.clear();
    leafGoal = 3 + d ~/ 2;
    leafCaught = 0;
    leafTimer = 30;
  }

  @override
  int roundSeconds() => 75 + rd * 3;

  void _rakeAt(double x, double y, int dir) {
    final i = ((x - kZenL) / kZenCell).floor(), j = ((y - kZenT) / kZenCell).floor();
    for (var dj = -1; dj <= 1; dj++) {
      for (var di = -1; di <= 1; di++) {
        final ii = i + di, jj = j + dj;
        if (ii < 0 || jj < 0 || ii >= kZenW || jj >= kZenH) continue;
        if (di.abs() + dj.abs() > 1) continue;
        final k = jj * kZenW + ii;
        if (cells[k] == 3) continue;
        if (cells[k] == 0) {
          raked++;
          totalRaked++;
          if (raked % 20 == 0) score += 5;
        }
        cells[k] = dir;
      }
    }
  }

  @override
  void step(ArcadeInput i) {
    // leaves drift down
    leafTimer--;
    if (leafTimer <= 0 && leaves.length < 3 && leafCaught + leaves.length < leafGoal + 2) {
      final r = SeededRandom(mixSeed([roundSeed, ticks, 55]));
      leaves.add(Leaf(150 + r.nextDouble() * 700, 200, (r.nextDouble() - 0.5) * 2, r.nextDouble() * 6));
      leafTimer = 90 + r.nextInt(80);
    }
    for (final l in leaves) {
      l.y += 2.2;
      l.x += l.vx + math.sin(ticks * 0.05 + l.phase) * 1.5;
    }
    leaves.removeWhere((l) => l.y > 1420);
    if (i.tap && i.hasPointer) {
      for (final l in leaves) {
        if (_dist2(l.x, l.y, i.x, i.y) < 70 * 70) {
          leaves.remove(l);
          leafCaught++;
          leavesTotal++;
          score += 20;
          lastEvent = 2;
          return;
        }
      }
      for (final s in spots) {
        if (s[2] == 0 && _dist2(s[0], s[1], i.x, i.y) < 60 * 60) {
          s[2] = 1;
          stonesPlaced++;
          score += 30;
          lastEvent = 3;
          return;
        }
      }
    }
    if (i.down && i.hasPointer && wasDown) {
      final dx = i.x - lastX, dy = i.y - lastY;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len > 1) {
        final dir = dx.abs() >= dy.abs() ? 1 : 2;
        final n = (len / 15).ceil();
        for (var s = 1; s <= n; s++) {
          _rakeAt(lastX + dx * s / n, lastY + dy * s / n, dir);
        }
      }
    }
  }

  double get rakeRatio => raked / math.max(1, sandCells);

  @override
  bool get roundComplete {
    final ok = rakeRatio >= rakeGoal && spots.every((s) => s[2] == 1) && leafCaught >= leafGoal;
    if (ok) gardens++;
    return ok;
  }

  @override
  double get roundProgress {
    final a = (rakeRatio / rakeGoal).clamp(0.0, 1.0);
    final b = spots.isEmpty ? 1.0 : spots.where((s) => s[2] == 1).length / spots.length;
    final c = (leafCaught / leafGoal).clamp(0.0, 1.0);
    return (a * 2 + b + c) / 4;
  }

  @override
  bool useBooster() {
    // Gentle breeze: brings every leaf and settles all stones.
    if (over) return false;
    leafCaught = math.max(leafCaught, leafGoal);
    for (final s in spots) {
      s[2] = 1;
    }
    leaves.clear();
    return true;
  }

  @override
  Map<String, int> get stats => {
        'sand_raked': totalRaked,
        'stones_placed': stonesPlaced,
        'leaves_caught': leavesTotal,
        'gardens': gardens,
      };
}

// ---------------------------------------------------------------------------
// Autopilot (validation + demo).

ArcadeInput relaxBot(ArcadeSim sim) {
  final s = sim as RelaxSim;
  switch (s) {
    case AntistressSim a:
      return _antiBot(a);
    case PopItSim p:
      return _popBot(p);
    case SandSim q:
      return _sandBot(q);
    case CleanSim c:
      return _cleanBot(c);
    case ZenSim z:
      return _zenBot(z);
    default:
      return ArcadeInput.idle;
  }
}

ArcadeInput _antiBot(AntistressSim s) {
  switch (s.toy) {
    case kToyWrap:
      for (final b in s.bubbles) {
        if (b[2] == 0) return ArcadeInput(down: true, x: b[0].roundToDouble(), y: b[1].roundToDouble());
      }
      return ArcadeInput.idle;
    case kToySpinner:
      // circle around the hub
      final a = s.ticks * 0.35;
      return ArcadeInput(down: true, x: (500 + math.cos(a) * 220).roundToDouble(), y: (800 + math.sin(a) * 220).roundToDouble());
    case kToySwitch:
      if (s.wasDown) return ArcadeInput.idle;
      // presses that still differ: apply the generating set, then fix leftovers
      for (var p = 0; p < s.lights.length; p++) {
        if (!s.neighbourMode && s.lights[p] != s.target[p]) {
          final (x, y) = s.switchPos(p);
          return ArcadeInput(down: true, tap: true, x: x.roundToDouble(), y: y.roundToDouble());
        }
      }
      if (s.neighbourMode && s.botCursor < s.solution.length) {
        final (x, y) = s.switchPos(s.solution[s.botCursor++]);
        return ArcadeInput(down: true, tap: true, x: x.roundToDouble(), y: y.roundToDouble());
      }
      return ArcadeInput.idle;
    default:
      final phase = s.ticks % 40;
      if (phase < 25) return ArcadeInput(down: true, x: 500, y: (820 + phase * 12.0).roundToDouble());
      return const ArcadeInput(x: 500, y: 1100);
  }
}

ArcadeInput _popBot(PopItSim s) {
  if (s.wasDown) return const ArcadeInput(x: 0, y: 0);
  PopBubble? pick;
  for (final b in s.bubbles) {
    if (b.hp <= 0) continue;
    if (b.order > 0 && b.order != s.nextOrder) continue;
    if (b.order == s.nextOrder) {
      pick = b;
      break;
    }
    pick ??= b;
  }
  if (pick == null) return ArcadeInput.idle;
  return ArcadeInput(down: true, tap: true, x: pick.x.roundToDouble(), y: pick.y.roundToDouble());
}

ArcadeInput _sandBot(SandSim s) {
  // most under-filled column relative to its target
  var best = -1, bestGap = 0;
  for (var x = 0; x < kSandCols; x++) {
    final gap = s.target[x].length - s.cols[x].length;
    if (gap > bestGap || (gap == bestGap && best >= 0 && x.isEven && gap > 0)) {
      bestGap = gap;
      best = x;
    }
  }
  if (best < 0) return ArcadeInput.idle;
  final need = s.target[best][s.cols[best].length];
  if (need != s.color) {
    if (s.wasDown) return const ArcadeInput(x: 0, y: 0);
    final (sx, sy) = s.swatch(need);
    return ArcadeInput(down: true, tap: true, x: sx.roundToDouble(), y: sy.roundToDouble());
  }
  return ArcadeInput(down: true, x: (kSandL + (best + 0.5) * kSandCell).roundToDouble(), y: 900);
}

ArcadeInput _cleanBot(CleanSim s) {
  // move toward the nearest dirty cell from the last finger position
  final px = s.lastX < 0 ? 500.0 : s.lastX, py = s.lastY < 0 ? 800.0 : s.lastY;
  var best = -1;
  var bd = 1e18;
  for (var k = 0; k < s.dirt.length; k++) {
    if (s.dirt[k] <= 0) continue;
    final x = kCleanL + (k % kCleanW + 0.5) * kCleanCell, y = kCleanT + (k ~/ kCleanW + 0.5) * kCleanCell;
    final d = _dist2(x, y, px, py);
    if (d < bd) {
      bd = d;
      best = k;
    }
  }
  if (best < 0) return ArcadeInput.idle;
  final tx = kCleanL + (best % kCleanW + 0.5) * kCleanCell, ty = kCleanT + (best ~/ kCleanW + 0.5) * kCleanCell;
  final dist = math.sqrt(bd);
  const step = 30.0;
  final nx = dist <= step ? tx : px + (tx - px) / dist * step;
  final ny = dist <= step ? ty : py + (ty - py) / dist * step;
  // small circular wiggle so the sponge rubs
  final w = math.sin(s.ticks * 0.9) * 8;
  return ArcadeInput(down: true, x: (nx + w).roundToDouble(), y: (ny - w).roundToDouble());
}

ArcadeInput _zenBot(ZenSim s) {
  if (!s.wasDown) {
    for (final l in s.leaves) {
      if (l.y > 260) return ArcadeInput(down: true, tap: true, x: l.x.roundToDouble(), y: (l.y + 2.2).roundToDouble());
    }
    for (final sp in s.spots) {
      if (sp[2] == 0) return ArcadeInput(down: true, tap: true, x: sp[0].roundToDouble(), y: sp[1].roundToDouble());
    }
  }
  // leaves are worth a release
  if (s.wasDown && s.leaves.any((l) => l.y > 260) && s.ticks % 20 == 0) return const ArcadeInput(x: 0, y: 0);
  // rake toward the nearest sand cell
  final px = s.lastX < 0 ? 500.0 : s.lastX, py = s.lastY < 0 ? 800.0 : s.lastY;
  var best = -1;
  var bd = 1e18;
  for (var k = 0; k < s.cells.length; k++) {
    if (s.cells[k] != 0) continue;
    final x = kZenL + (k % kZenW + 0.5) * kZenCell, y = kZenT + (k ~/ kZenW + 0.5) * kZenCell;
    final d = _dist2(x, y, px, py);
    if (d < bd) {
      bd = d;
      best = k;
    }
  }
  if (best < 0) return ArcadeInput.idle;
  final tx = kZenL + (best % kZenW + 0.5) * kZenCell, ty = kZenT + (best ~/ kZenW + 0.5) * kZenCell;
  final dist = math.sqrt(bd);
  const step = 28.0;
  final nx = dist <= step ? tx : px + (tx - px) / dist * step;
  final ny = dist <= step ? ty : py + (ty - py) / dist * step;
  return ArcadeInput(down: true, x: nx.roundToDouble(), y: ny.roundToDouble());
}
