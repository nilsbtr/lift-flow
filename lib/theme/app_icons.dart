import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// An icon in `assets/icons/`, drawn on a 14×14 grid.
@immutable
class AppIconData {
  const AppIconData(this.name);

  final String name;

  String get asset => 'assets/icons/$name.svg';
}

/// Streamline Flex free icons (CC BY 4.0, streamlinehq.com): line by default,
/// solid for active states. plus, minus, close, chevron_right, arrow_left,
/// more, drag, play_solid, dumbbell(_solid) and trash are custom, drawn to
/// match, since the free set lacks them.
abstract final class AppIcons {
  static const plus = AppIconData('plus');
  static const minus = AppIconData('minus');
  static const close = AppIconData('close');
  static const chevronRight = AppIconData('chevron_right');
  static const arrowLeft = AppIconData('arrow_left');
  static const more = AppIconData('more');
  static const drag = AppIconData('drag');
  static const playSolid = AppIconData('play_solid');
  static const stopSolid = AppIconData('stop_solid');
  static const dumbbell = AppIconData('dumbbell');
  static const dumbbellSolid = AppIconData('dumbbell_solid');
  static const trash = AppIconData('trash');
  static const box = AppIconData('box');
  static const check = AppIconData('check');
  static const checkSolid = AppIconData('check_solid');
  static const home = AppIconData('home');
  static const homeSolid = AppIconData('home_solid');
  static const settings = AppIconData('settings');
  static const settingsSolid = AppIconData('settings_solid');
  static const history = AppIconData('history');
  static const historySolid = AppIconData('history_solid');
  static const progress = AppIconData('progress');
  static const progressSolid = AppIconData('progress_solid');
  static const search = AppIconData('search');
  static const calendar = AppIconData('calendar');
  static const list = AppIconData('list');
  static const trophySolid = AppIconData('trophy_solid');
  static const timer = AppIconData('timer');
  static const edit = AppIconData('edit');
  static const notepad = AppIconData('notepad');
  static const note = AppIconData('note');
  static const warning = AppIconData('warning');
  static const info = AppIconData('info');
  static const lock = AppIconData('lock');
  static const exportFile = AppIconData('export_file');
  static const importFile = AppIconData('import_file');
  static const openExternal = AppIconData('open_external');
  static const addExercise = AppIconData('add_exercise');

  static final _pictures = <String, PictureInfo>{};

  /// Decodes every icon up front so [AppIcon] paints on its first frame.
  static Future<void> precache() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets().where(
      (a) => a.startsWith('assets/icons/'),
    );
    await Future.wait([
      for (final asset in assets)
        vg.loadPicture(AssetBytesLoader(asset), null).then((p) {
          _pictures[asset] = p;
        }),
    ]);
  }
}

/// Drop-in replacement for [Icon] that renders an [AppIconData].
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size, this.color});

  final AppIconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    var color = this.color ?? theme.color ?? const Color(0xFF000000);
    final opacity = theme.opacity;
    if (opacity != null && opacity < 1) {
      color = color.withValues(alpha: color.a * opacity);
    }
    final picture = AppIcons._pictures[icon.asset];
    // Center keeps the glyph at [size] when a parent forces larger constraints,
    // matching [Icon].
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: CustomPaint(
            size: Size.square(size),
            painter: picture == null ? null : _IconPainter(picture, color),
          ),
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.info, this.color);

  final PictureInfo info;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..saveLayer(
        Offset.zero & size,
        Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
      )
      ..scale(size.width / info.size.width)
      ..drawPicture(info.picture)
      ..restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.info != info || old.color != color;
}
