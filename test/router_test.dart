import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/router.dart';

void main() {
  test('exercise and workout pages nest in every tab, up to a limit', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final config = container.read(routerProvider).configuration;
    bool matches(String path) => !config.findMatch(Uri.parse(path)).isError;

    for (final tab in ['/gym', '/progress']) {
      expect(matches('$tab/exercise/1'), isTrue);
      expect(matches('$tab/exercise/1/workout/2'), isTrue);
      expect(matches('$tab/exercise/1/workout/2/edit'), isTrue);
      expect(matches('$tab/exercise/1/workout/2/exercise/3'), isTrue);
    }
    expect(matches('/history/5/exercise/1/workout/2/exercise/3'), isTrue);
    expect(matches('/progress/workout/5/exercise/1/workout/2'), isTrue);

    final deep = config.findMatch(
      Uri.parse('/gym/exercise/1/workout/2/exercise/3/workout/4/exercise/5'),
    );
    expect(deep.pathParameters, {
      'exerciseId': '1',
      'workoutId1': '2',
      'exerciseId1': '3',
      'workoutId2': '4',
      'exerciseId2': '5',
    });
    // The chain ends there.
    expect(
      matches(
        '/gym/exercise/1/workout/2/exercise/3/workout/4/exercise/5/workout/6',
      ),
      isFalse,
    );
  });
}
