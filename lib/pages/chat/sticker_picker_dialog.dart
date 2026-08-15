// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/recent_stickers_store.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../widgets/avatar.dart';

class StickerPickerDialog extends StatefulWidget {
  final Room room;
  final void Function(ImagePackImageContent) onSelected;

  const StickerPickerDialog({
    required this.onSelected,
    required this.room,
    super.key,
  });

  @override
  StickerPickerDialogState createState() => StickerPickerDialogState();
}

class StickerPickerDialogState extends State<StickerPickerDialog> {
  String? searchFilter;

  late final AutoScrollController _scrollController;
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _scrollViewKey = GlobalKey();
  int? _activePackIndex;
  bool _activePackUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = AutoScrollController(axis: Axis.vertical);
    _scrollController.addListener(_scheduleActivePackUpdate);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scheduleActivePackUpdate);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _selectSticker(ImagePackImageContent image, String fallbackBody) {
    final imageCopy = ImagePackImageContent.fromJson(image.toJson().copy());
    imageCopy.body ??= fallbackBody;
    widget.onSelected(imageCopy);
  }

  void _scheduleActivePackUpdate() {
    if (_activePackUpdateScheduled || !mounted) return;
    _activePackUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activePackUpdateScheduled = false;
      if (mounted) _updateActivePackFromViewport();
    });
  }

  void _updateActivePackFromViewport() {
    final viewportContext = _scrollViewKey.currentContext;
    final viewportRenderObject = viewportContext?.findRenderObject();
    if (viewportRenderObject is! RenderBox ||
        !viewportRenderObject.attached ||
        _scrollController.tagMap.isEmpty) {
      return;
    }

    final viewportTop = viewportRenderObject.localToGlobal(Offset.zero).dy + 8;
    int? closestAtOrAbove;
    var closestAtOrAboveTop = double.negativeInfinity;
    int? closestBelow;
    var closestBelowTop = double.infinity;

    for (final entry in _scrollController.tagMap.entries) {
      final renderObject = entry.value.context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final top = renderObject.localToGlobal(Offset.zero).dy;
      if (top <= viewportTop && top > closestAtOrAboveTop) {
        closestAtOrAbove = entry.key;
        closestAtOrAboveTop = top;
      } else if (top > viewportTop && top < closestBelowTop) {
        closestBelow = entry.key;
        closestBelowTop = top;
      }
    }

    final nextActivePackIndex =
        closestAtOrAbove ?? (closestBelow == null ? null : -1);
    if (nextActivePackIndex != null &&
        nextActivePackIndex != _activePackIndex) {
      setState(() => _activePackIndex = nextActivePackIndex);
    }
  }

  Future<void> _clearSearchBeforeNavigation() async {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
    setState(() => searchFilter = null);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _scrollToRecents() async {
    await _clearSearchBeforeNavigation();
    if (!_scrollController.hasClients) return;
    setState(() => _activePackIndex = -1);
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _scrollToPack(int index) async {
    await _clearSearchBeforeNavigation();
    if (!_scrollController.hasClients) return;
    setState(() => _activePackIndex = index);
    await _scrollController.scrollToIndex(
      index,
      preferPosition: AutoScrollPosition.begin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final stickerPacks = widget.room.getImagePacks(ImagePackUsage.sticker);
    final packSlugs = stickerPacks.keys.toList();
    final currentStickersByUrl = <String, _StickerEntry>{};

    for (final pack in stickerPacks.values) {
      for (final entry in pack.images.entries) {
        currentStickersByUrl.putIfAbsent(
          entry.value.url.toString(),
          () => _StickerEntry(key: entry.key, image: entry.value),
        );
      }
    }

    final recentStickerUrls = RecentStickersStore.read(
      Matrix.of(context).store,
      widget.room.client.userID,
    );
    final recentStickers = recentStickerUrls
        .map((url) => currentStickersByUrl[url])
        .whereType<_StickerEntry>()
        .toList(growable: false);

    return Material(
      color: theme.colorScheme.onInverseSurface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                key: _scrollViewKey,
                controller: _scrollController,
                slivers: <Widget>[
                  if (recentStickers.isNotEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 88,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          scrollDirection: Axis.horizontal,
                          itemCount: recentStickers.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final recentSticker = recentStickers[index];
                            return SizedBox(
                              width: 72,
                              child: Tooltip(
                                message:
                                    recentSticker.image.body ??
                                    recentSticker.key,
                                child: InkWell(
                                  radius: AppConfig.borderRadius,
                                  key: ValueKey(
                                    'recent_${recentSticker.image.url}',
                                  ),
                                  onTap: () => _selectSticker(
                                    recentSticker.image,
                                    recentSticker.key,
                                  ),
                                  child: AbsorbPointer(
                                    absorbing: true,
                                    child: MxcImage(
                                      uri: recentSticker.image.url,
                                      fit: BoxFit.contain,
                                      width: 72,
                                      height: 72,
                                      animated: true,
                                      isThumbnail: false,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  SliverAppBar(
                    floating: true,
                    primary: false,
                    toolbarHeight: 72,
                    scrolledUnderElevation: 0,
                    backgroundColor: Colors.transparent,
                    automaticallyImplyLeading: false,
                    title: TextField(
                      controller: _searchController,
                      autofocus: false,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: theme.colorScheme.secondaryContainer,
                        border: OutlineInputBorder(
                          borderSide: BorderSide.none,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        contentPadding: EdgeInsets.zero,
                        hintText: L10n.of(context).search,
                        hintStyle: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.normal,
                        ),
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                        prefixIcon: const Icon(Icons.search_outlined),
                      ),
                      onChanged: (s) => setState(() => searchFilter = s),
                    ),
                  ),
                  if (packSlugs.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisSize: .min,
                          children: [
                            Text(L10n.of(context).noEmotesFound),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => UrlLauncher(
                                context,
                                AppConfig.howDoIGetStickersTutorial,
                              ).launchUrl(),
                              icon: const Icon(Icons.explore_outlined),
                              label: Text(L10n.of(context).discover),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverList.builder(
                      itemCount: packSlugs.length,
                      itemBuilder: (BuildContext context, int packIndex) {
                        final pack = stickerPacks[packSlugs[packIndex]]!;
                        final filteredImagePackImageEntried = pack
                            .images
                            .entries
                            .toList();
                        if (searchFilter?.isNotEmpty ?? false) {
                          filteredImagePackImageEntried.removeWhere(
                            (e) =>
                                !(e.key.toLowerCase().contains(
                                      searchFilter!.toLowerCase(),
                                    ) ||
                                    (e.value.body?.toLowerCase().contains(
                                          searchFilter!.toLowerCase(),
                                        ) ??
                                        false)),
                          );
                        }
                        final imageKeys = filteredImagePackImageEntried
                            .map((e) => e.key)
                            .toList();
                        final packName =
                            pack.pack.displayName ?? packSlugs[packIndex];

                        return AutoScrollTag(
                          key: ValueKey(
                            'sticker_pack_${packSlugs[packIndex]}_$packIndex',
                          ),
                          controller: _scrollController,
                          index: packIndex,
                          child: imageKeys.isEmpty
                              ? const SizedBox.shrink()
                              : Column(
                                  children: <Widget>[
                                    if (packIndex != 0)
                                      const SizedBox(height: 20),
                                    if (packName != 'user')
                                      ListTile(
                                        leading: Avatar(
                                          mxContent: pack.pack.avatarUrl,
                                          name: packName,
                                          client: widget.room.client,
                                        ),
                                        title: Text(packName),
                                      ),
                                    const SizedBox(height: 6),
                                    GridView.builder(
                                      padding: EdgeInsets.zero,
                                      itemCount: imageKeys.length,
                                      gridDelegate:
                                          const SliverGridDelegateWithMaxCrossAxisExtent(
                                            maxCrossAxisExtent: 84,
                                            mainAxisSpacing: 8.0,
                                            crossAxisSpacing: 8.0,
                                          ),
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemBuilder:
                                          (
                                            BuildContext context,
                                            int imageIndex,
                                          ) {
                                            final image = pack
                                                .images[imageKeys[imageIndex]]!;
                                            return Tooltip(
                                              message:
                                                  image.body ??
                                                  imageKeys[imageIndex],
                                              child: InkWell(
                                                radius: AppConfig.borderRadius,
                                                key: ValueKey(
                                                  image.url.toString(),
                                                ),
                                                onTap: () => _selectSticker(
                                                  image,
                                                  imageKeys[imageIndex],
                                                ),
                                                child: AbsorbPointer(
                                                  absorbing: true,
                                                  child: MxcImage(
                                                    uri: image.url,
                                                    fit: BoxFit.contain,
                                                    width: 128,
                                                    height: 128,
                                                    animated: true,
                                                    isThumbnail: false,
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                    ),
                                  ],
                                ),
                        );
                      },
                    ),
                ],
              ),
            ),
            if (packSlugs.isNotEmpty)
              _StickerPackNavigationBar(
                room: widget.room,
                stickerPacks: stickerPacks,
                packSlugs: packSlugs,
                activePackIndex: _activePackIndex,
                hasRecents: recentStickers.isNotEmpty,
                onScrollToRecents: _scrollToRecents,
                onScrollToPack: _scrollToPack,
              ),
          ],
        ),
      ),
    );
  }
}

class _StickerEntry {
  final String key;
  final ImagePackImageContent image;

  const _StickerEntry({required this.key, required this.image});
}

class _StickerPackNavigationBar extends StatelessWidget {
  final Room room;
  final Map<String, ImagePackContent> stickerPacks;
  final List<String> packSlugs;
  final int? activePackIndex;
  final bool hasRecents;
  final VoidCallback onScrollToRecents;
  final ValueChanged<int> onScrollToPack;

  const _StickerPackNavigationBar({
    required this.room,
    required this.stickerPacks,
    required this.packSlugs,
    required this.activePackIndex,
    required this.hasRecents,
    required this.onScrollToRecents,
    required this.onScrollToPack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedPackIndex =
        activePackIndex ?? (hasRecents ? -1 : (packSlugs.isEmpty ? -1 : 0));

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        scrollDirection: Axis.horizontal,
        itemCount: packSlugs.length + 1,
        itemBuilder: (context, navigationIndex) {
          if (navigationIndex == 0) {
            final selected = selectedPackIndex == -1;
            return _StickerPackNavigationButton(
              selected: selected,
              onTap: onScrollToRecents,
              child: Icon(
                Icons.history,
                color: selected
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            );
          }

          final packIndex = navigationIndex - 1;
          final slug = packSlugs[packIndex];
          final pack = stickerPacks[slug]!;
          final packName = pack.pack.displayName ?? slug;
          final firstSticker = pack.images.isEmpty
              ? null
              : pack.images.values.first;
          final selected = selectedPackIndex == packIndex;

          final Widget packIcon;
          if (pack.pack.avatarUrl != null) {
            packIcon = Avatar(
              mxContent: pack.pack.avatarUrl,
              name: packName,
              client: room.client,
              size: 40,
            );
          } else if (firstSticker != null) {
            packIcon = ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: MxcImage(
                uri: firstSticker.url,
                fit: BoxFit.contain,
                width: 40,
                height: 40,
                animated: false,
                isThumbnail: true,
              ),
            );
          } else {
            packIcon = Avatar(name: packName, client: room.client, size: 40);
          }

          return Tooltip(
            message: packName,
            child: _StickerPackNavigationButton(
              selected: selected,
              onTap: () => onScrollToPack(packIndex),
              child: packIcon,
            ),
          );
        },
      ),
    );
  }
}

class _StickerPackNavigationButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _StickerPackNavigationButton({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 50,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: selected
                ? Border.all(color: theme.colorScheme.primary, width: 2)
                : null,
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}