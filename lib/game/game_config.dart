import 'package:flutter/material.dart';

import '../app/arcade_stage.dart';
import '../app/game_api.dart';
import '../core/game_rules.dart';
import 'relax_engine.dart';
import 'relax_view.dart';
import 'rules.dart';

final gameConfig = GameConfig(
  gameId: 'game-095-zen-garden',
  title: const ['Zen Bahçesi', 'Zen Garden', 'Zen-Garten', 'Jardín Zen', 'Jardin Zen'],
  tagline: const ['Kumu tırmıkla, taşları yerleştir, huzuru bul.', 'Rake the sand, place the stones, find your calm.', 'Sand harken, Steine legen.', 'Rastrilla y coloca piedras.', 'Ratissez et posez les pierres.'],
  seedColor: const Color(0xFF74C69D),
  icon: Icons.self_improvement,
  rules: ZenGardenRules(),
  buildPlay: (ctx) => ArcadeStage(
    ctx: ctx,
    create: () => RelaxSim((ctx.generated as GeneratedLevel<RelaxLevel>).puzzle),
    paint: paintRelax,
    sound: relaxSound,
    boosterIcon: Icons.air,
    boosterLabel: (l) => l == 'tr' ? 'Esinti' : 'Breeze',
    howTo: const ['Dokun ve sürükle. Süre çubuğu bitmeden görevi tamamla; Zen modunda süre yok. "Yavaş çekim" düğmesi süreyi 10 sn dondurur.', 'Tap and drag. Finish the task before the bar runs out; Zen mode has no timer. The slow-motion button freezes the timer for 10 s.', 'Tippen und ziehen. Zen-Modus ohne Zeit.', 'Toca y arrastra. El modo Zen no tiene tiempo.', 'Touchez et glissez. Le mode Zen est sans chrono.'],
  ),
  tutorial: const [
    TutorialStep(Icons.gesture, ['Sürükle: kumu tırmıkla.', 'Drag to rake.', 'Ziehen zum Harken.', 'Arrastra para rastrillar.', 'Glissez pour ratisser.']),
    TutorialStep(Icons.radio_button_unchecked, ['Parlayan halkalara dokun: taş koy.', 'Tap glowing rings to place stones.', 'Ringe antippen.', 'Toca los anillos.', 'Touchez les anneaux.']),
    TutorialStep(Icons.eco, ['Düşen yaprakları dokunarak topla.', 'Tap falling leaves.', 'Blätter antippen.', 'Toca las hojas.', 'Touchez les feuilles.']),
  ],
);
