import 'package:flutter_test/flutter_test.dart';
import 'package:game_095_zen_garden/core/arcade.dart';
import 'package:game_095_zen_garden/core/level_plan.dart';
import 'package:game_095_zen_garden/game/relax_engine.dart';
import 'package:game_095_zen_garden/game/rules.dart';

void main() {
  final rules = ZenGardenRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  RelaxSim fresh([int n = 1]) => RelaxSim(rules.build(planner.spec(n)).puzzle);

  test('running out of time costs a life and restarts the task', () {
    final s = fresh(2);
    s.timeLeft = 1;
    s.tick(ArcadeInput.idle);
    s.tick(ArcadeInput.idle);
    expect(s.lives, 2);
    expect(s.timeLeft, greaterThan(60));
  });

  test('time freeze keeps every touch (no skipped ticks)', () {
    final s = fresh(3);
    expect(s.useSlow(), isTrue);
    final t0 = s.timeLeft;
    for (var i = 0; i < 30; i++) {
      s.tick(ArcadeInput.idle);
    }
    expect(s.timeLeft, t0);
  });

  test('autopilot finishes the first ten levels without losing a life', () {
    for (var n = 1; n <= 10; n++) {
      final s = fresh(n);
      expect(runBot(s, rules.bot, 60 * 60 * 6).won, isTrue, reason: 'level $n');
      expect(s.lives, 3, reason: 'level $n');
    }
  });

  test('zen: dragging rakes the sand around rocks', () {
    final s = fresh() as ZenSim;
    s.tick(const ArcadeInput(down: true, x: 120, y: 270));
    for (var i = 1; i <= 30; i++) {
      s.tick(ArcadeInput(down: true, x: 120 + i * 25.0, y: 270));
    }
    expect(s.raked, greaterThan(15));
  });
}
