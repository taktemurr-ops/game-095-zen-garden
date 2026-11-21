import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import 'relax_engine.dart';

class ZenGardenRules extends ArcadeRules<RelaxLevel> {
  @override
  String get gameId => 'game-095-zen-garden';

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameStat> get gameStats => const [
        GameStat('gardens', 'Tamamlanan bahçe', 'Gardens finished', scale: 40),
        GameStat('sand_raked', 'Tırmıklanan kum', 'Sand raked', scale: 10000),
        GameStat('stones_placed', 'Yerleştirilen taş', 'Stones placed', scale: 100),
        GameStat('leaves_caught', 'Yakalanan yaprak', 'Leaves caught', scale: 200),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('gardens', 'gardens', [10, 20, 40]),
        MissionTemplate('sand_raked', 'sand_raked', [1250, 2500, 5000], coinReward: 80),
      ];

  @override
  RelaxLevel generate(LevelSpec spec) => generateRelax(RelaxKind.zen, spec);

  @override
  ArcadeMeta metaOf(RelaxLevel l) => l.meta;

  @override
  ArcadeSim createSim(RelaxLevel l) => RelaxSim(l);

  @override
  ArcadeInput bot(ArcadeSim sim) => relaxBot(sim);
}

ArcadeRules createRules() => ZenGardenRules();
