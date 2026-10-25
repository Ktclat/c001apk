import 'dart:io';

import 'package:c001apk_flutter/logic/model/check_update/datum.dart' as update;
import 'package:c001apk_flutter/logic/model/fav_history/fav_history.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart' as feed;
import 'package:c001apk_flutter/logic/model/feed/entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

// Encode a synthetic legacy record through Hive itself, then reopen it with the
// production adapter. This guards the actual on-disk codec, not a source string.
class _LegacyFavourite {
  const _LegacyFavourite(this.time);
  final num? time;
}

class _LegacyFavouriteAdapter extends TypeAdapter<_LegacyFavourite> {
  @override
  int get typeId => 0;

  @override
  _LegacyFavourite read(BinaryReader reader) =>
      throw UnsupportedError('Write-only legacy fixture');

  @override
  void write(BinaryWriter writer, _LegacyFavourite item) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write('synthetic-feed')
      ..writeByte(7)
      ..write(item.time);
  }
}

void main() {
  test('production Hive adapter reads legacy double and nullable timestamps',
      () async {
    final directory = await Directory.systemTemp.createTemp('legacy-codec-');
    addTearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });
    Hive.init(directory.path);
    Hive.registerAdapter(_LegacyFavouriteAdapter(), override: true);
    final oldBox = await Hive.openBox<_LegacyFavourite>('legacy_favourites');
    await oldBox.put('double', const _LegacyFavourite(1700000000.75));
    await oldBox.put('integer', const _LegacyFavourite(1700000001));
    await oldBox.put('null', const _LegacyFavourite(null));
    await oldBox.close();

    Hive.registerAdapter(FavHistoryItemAdapter(), override: true);
    final reopened = await Hive.openBox<FavHistoryItem>('legacy_favourites');
    expect(reopened.get('double')!.id, 'synthetic-feed');
    expect(reopened.get('double')!.time, 1700000000);
    expect(reopened.get('integer')!.time, 1700000001);
    expect(reopened.get('null')!.time, isNull);
  });

  test('production entity decoder preserves non-string title conversion', () {
    expect(Entity.fromJson({'title': 123}).title, '123');
    expect(Entity.fromJson({'title': true}).title, 'true');
    expect(Entity.fromJson({'title': null}).title, isNull);
  });

  test('feed codec preserves existing asymmetric isTop input and output keys',
      () {
    final item = feed.Datum.fromJson({'isTop': 2.9, 'is_top': 9});
    expect(item.isTop, 2);
    expect(feed.Datum.fromJson({'is_top': 9}).isTop, isNull);
    expect(item.toJson()['is_top'], 2);
    expect(item.toJson().containsKey('isTop'), isFalse);
  });

  test('feed codec preserves existing location and follow serialization keys',
      () {
    final item = feed.Datum.fromJson({
      'ip_location': 'synthetic-location',
      'follow_num': 7,
    });
    expect(item.ipLocation, 'synthetic-location');
    expect(item.followNum, 7);
    final encoded = item.toJson();
    expect(encoded['ipLocation'], 'synthetic-location');
    expect(encoded['followNum'], 7);
    expect(encoded.containsKey('ip_location'), isFalse);
    expect(encoded.containsKey('follow_num'), isFalse);
  });

  test('update codec still reads but does not emit lastupdate', () {
    final item = update.Datum.fromJson({'lastupdate': 1700000000.75});
    expect(item.lastupdate, 1700000000);
    expect(item.toJson().containsKey('lastupdate'), isFalse);
  });
}
