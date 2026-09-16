import 'package:flutter_test/flutter_test.dart';
import 'package:fluttergirdi/services/shelf_state_cache.dart';

void main() {
  test('Raf önbelleği yalnızca gerçek değişikliklerde dinleyiciyi uyarır', () {
    final cache = ShelfStateCache.instance;
    const uid = 'movie_detail_cache_test_user';
    cache.updateAll(uid, const {});

    var notifications = 0;
    void listener() => notifications++;
    cache.addListener(listener);
    addTearDown(() => cache.removeListener(listener));

    cache.optimisticAdd(uid, 'watchedKeys', '550');
    cache.optimisticAdd(uid, 'watchedKeys', '550');
    expect(cache.get(uid, 'watchedKeys'), contains('550'));
    expect(notifications, 1);

    cache.optimisticRemove(uid, 'watchedKeys', '550');
    cache.optimisticRemove(uid, 'watchedKeys', '550');
    expect(cache.get(uid, 'watchedKeys'), isNot(contains('550')));
    expect(notifications, 2);
  });
}
