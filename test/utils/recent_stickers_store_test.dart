// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/recent_stickers_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecentStickersStore', () {
    test('uses a separate key for each Matrix user', () {
      expect(
        RecentStickersStore.keyForUser('@alice:example.org'),
        'chat.fluffy.recent_stickers.@alice:example.org',
      );
      expect(RecentStickersStore.keyForUser(null), isNull);
      expect(RecentStickersStore.keyForUser(''), isNull);
    });

    test('keeps most recently used stickers first without duplicates', () {
      var recent = RecentStickersStore.update(
        const [],
        Uri.parse('mxc://example.org/a'),
      );
      recent = RecentStickersStore.update(
        recent,
        Uri.parse('mxc://example.org/b'),
      );
      recent = RecentStickersStore.update(
        recent,
        Uri.parse('mxc://example.org/a'),
      );

      expect(recent, const ['mxc://example.org/a', 'mxc://example.org/b']);
    });

    test('normalizes invalid and duplicate stored entries', () {
      final recent = RecentStickersStore.update(const [
        'not-an-mxc',
        'mxc://example.org/a',
        'mxc://example.org/a',
        'mxc://example.org/b',
      ], Uri.parse('mxc://example.org/c'));

      expect(recent, const [
        'mxc://example.org/c',
        'mxc://example.org/a',
        'mxc://example.org/b',
      ]);
    });

    test('caps recent history at the configured limit', () {
      final current = List.generate(
        RecentStickersStore.maxItems,
        (index) => 'mxc://example.org/$index',
      );

      final recent = RecentStickersStore.update(
        current,
        Uri.parse('mxc://example.org/new'),
      );

      expect(recent.length, RecentStickersStore.maxItems);
      expect(recent.first, 'mxc://example.org/new');
      expect(recent.last, 'mxc://example.org/28');
    });
  });
}
