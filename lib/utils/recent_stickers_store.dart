// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentStickersStore {
  static const maxItems = 30;
  static const _keyPrefix = 'chat.fluffy.recent_stickers.';

  static String? keyForUser(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    return '$_keyPrefix$userId';
  }

  static List<String> read(SharedPreferences store, String? userId) {
    final key = keyForUser(userId);
    if (key == null) return const [];

    try {
      final stored = store.getStringList(key);
      if (stored == null) return const [];
      return _normalize(stored);
    } catch (error, stackTrace) {
      Logs().w(
        'Unable to read recent stickers from local storage',
        error,
        stackTrace,
      );
      return const [];
    }
  }

  static Future<void> add(
    SharedPreferences store,
    String? userId,
    Uri stickerUrl,
  ) async {
    final key = keyForUser(userId);
    if (key == null || !_isMxc(stickerUrl.toString())) return;

    try {
      final updated = update(read(store, userId), stickerUrl);
      await store.setStringList(key, updated);
    } catch (error, stackTrace) {
      Logs().w(
        'Unable to persist recent sticker',
        error,
        stackTrace,
      );
    }
  }

  static List<String> update(List<String> current, Uri stickerUrl) {
    final stickerUrlString = stickerUrl.toString();
    final updated = _normalize(current)
        .where((item) => item != stickerUrlString)
        .toList();

    if (_isMxc(stickerUrlString)) {
      updated.insert(0, stickerUrlString);
    }

    return updated.take(maxItems).toList(growable: false);
  }

  static List<String> _normalize(Iterable<String> stored) {
    final normalized = <String>[];
    final seen = <String>{};

    for (final item in stored) {
      if (!_isMxc(item) || !seen.add(item)) continue;
      normalized.add(item);
      if (normalized.length == maxItems) break;
    }

    return normalized;
  }

  static bool _isMxc(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'mxc' &&
        uri.host.isNotEmpty &&
        uri.pathSegments.isNotEmpty;
  }
}
