import 'package:flutter/material.dart';

import '../models/biti_collection.dart';
import '../models/creature_growth.dart';
import 'home_screen.dart';

String _formatCriticalDuration(Duration d) {
  final int minutes = d.inMinutes;
  if (minutes >= 60 && minutes % 60 == 0) {
    final int h = minutes ~/ 60;
    return '$h heure${h > 1 ? 's' : ''}';
  }
  return '$minutes minute${minutes > 1 ? 's' : ''}';
}

/// Durée « jauge critique » avant mort — alignée sur [HomeScreen.bitiDeathAfterCriticalLowStreak].
const Duration _criticalLowStreakDeath = Duration(hours: 2);

class _Slide {
  const _Slide({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;
}

/// Carrousel d’introduction après la création du premier Biti.
class GameOnboardingCarouselScreen extends StatefulWidget {
  const GameOnboardingCarouselScreen({super.key, required this.collection});

  final BitiCollection collection;

  @override
  State<GameOnboardingCarouselScreen> createState() =>
      _GameOnboardingCarouselScreenState();
}

class _GameOnboardingCarouselScreenState
    extends State<GameOnboardingCarouselScreen> {
  late final PageController _pageController;
  late final List<_Slide> _slides;
  int _index = 0;

  static const Color _bg = Color(0xFF0B0E14);
  static const Color _fg = Color(0xFFE8ECF2);
  static const Color _muted = Color(0xFFB8C0CC);

  List<_Slide> _buildSlides() => <_Slide>[
    const _Slide(
      icon: Icons.monitor_heart_outlined,
      title: 'Les jauges',
      body:
          'Biti a faim, de l’énergie et une humeur. La faim baisse toutes les '
          'quelques secondes ; l’énergie et l’humeur baissent beaucoup plus '
          'lentement (environ 12 h pour vider toute la jauge si tu ne fais rien). '
          'Sous les jauges, une zone d’état résume son ressenti (calme, fatigué, etc.).',
    ),
    const _Slide(
      icon: Icons.touch_app_rounded,
      title: 'La barre du bas',
      body:
          'Jouer : consomme de l’énergie mais remonte l’humeur ; secouer le téléphone '
          'lance aussi une partie.\n\n'
          'Dormir : berce doucement le téléphone de gauche à droite (gyroscope). '
          'Quand le rythme est bon, l’énergie remonte ; la zone d’état indique si tu '
          'vas trop lent, trop vite ou si c’est parfait.\n\n'
          'Caresse : touche l’icône main, puis glisse sur la zone d’état : vibrations '
          'et petit gain d’humeur.\n\n'
          'Paramètres : aide détaillée et transfert Bluetooth vers un autre téléphone.',
    ),
    const _Slide(
      icon: Icons.grid_on_rounded,
      title: 'Terrain et nourriture',
      body:
          'Pince avec deux doigts pour zoomer (jusqu’à ×4), glisse pour te déplacer '
          'quand tu es zoomé.\n\n'
          'Les points verts sont de la nourriture : appuie dessus pour la récolter '
          '(un peu de faim en plus et de l’XP).',
    ),
    _Slide(
      icon: Icons.trending_up_rounded,
      title: 'Niveaux et XP',
      body:
          'Biti gagne ${CreatureGrowth.xpPerSecondWhenAlive} XP par seconde tant qu’il '
          'est vivant. Il existe ${CreatureGrowth.maxGrowthLevel} niveaux : par exemple '
          'le niveau 2 à partir de ${CreatureGrowth.xpLevelStarts[1]} XP cumulée, le '
          'niveau 6 à partir de ${CreatureGrowth.xpLevelStarts[5]} XP, et le dernier '
          'niveau à partir de '
          '${CreatureGrowth.xpLevelStarts[CreatureGrowth.maxGrowthLevel - 1]} XP. '
          'La jauge verte « LVL » montre la progression vers le niveau suivant : '
          'sprite et terrain grandissent avec les niveaux.',
    ),
    const _Slide(
      icon: Icons.vibration_rounded,
      title: 'Vibrations',
      body:
          'Les vibrations suivent un rythme type « pouls » : plus l’énergie est basse, '
          'plus le rythme ralentit.',
    ),
    _Slide(
      icon: Icons.warning_amber_rounded,
      title: 'Attention au danger',
      body:
          'Si la faim, l’énergie ou l’humeur reste trop basse (sous le seuil critique) '
          'sans remonter pendant au moins '
          '${_formatCriticalDuration(_criticalLowStreakDeath)}, '
          'Biti meurt. Il n’y a pas de bouton pour recommencer : pour une nouvelle '
          'partie, ferme complètement l’application puis rouvre-la.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _slides = _buildSlides();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => HomeScreen(initialCollection: widget.collection),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<_Slide> slides = _slides;
    final bool isLast = _index >= slides.length - 1;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF12161F),
        foregroundColor: _fg,
        title: const Text('Comment jouer'),
        actions: <Widget>[
          TextButton(
            onPressed: _goHome,
            child: Text(
              'Passer',
              style: TextStyle(color: _fg.withValues(alpha: 0.85)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: slides.length,
                onPageChanged: (int i) => setState(() => _index = i),
                itemBuilder: (BuildContext context, int i) {
                  final _Slide s = slides[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const SizedBox(height: 8),
                        Icon(
                          s.icon,
                          size: 56,
                          color: _fg.withValues(alpha: 0.92),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: _fg,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          s.body,
                          textAlign: TextAlign.left,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: _muted, height: 1.45),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(slides.length, (int i) {
                  final bool on = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: on ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: on ? _fg : _fg.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: <Widget>[
                  if (_index > 0)
                    TextButton(
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      child: Text(
                        'Précédent',
                        style: TextStyle(color: _fg.withValues(alpha: 0.9)),
                      ),
                    )
                  else
                    const SizedBox(width: 88),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      if (isLast) {
                        _goHome();
                      } else {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                    child: Text(isLast ? 'Commencer' : 'Suivant'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
