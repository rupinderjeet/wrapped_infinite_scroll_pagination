import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:infinite_scroll_pagination/src/core/paging_controller.dart';
import 'package:infinite_scroll_pagination/src/model/paging_state.dart';
import 'package:infinite_scroll_pagination/src/model/paging_status.dart';
import 'package:infinite_scroll_pagination/src/ui/default_indicators/first_page_error_indicator.dart';
import 'package:infinite_scroll_pagination/src/ui/default_indicators/first_page_progress_indicator.dart';
import 'package:infinite_scroll_pagination/src/ui/default_indicators/new_page_error_indicator.dart';
import 'package:infinite_scroll_pagination/src/ui/default_indicators/new_page_progress_indicator.dart';
import 'package:infinite_scroll_pagination/src/ui/default_indicators/no_items_found_indicator.dart';
import 'package:infinite_scroll_pagination/src/utils/listenable_listener.dart';
import 'package:sliver_tools/sliver_tools.dart';

typedef CompletedListingBuilder = Widget Function(
  BuildContext context,
  IndexedWidgetBuilder itemWidgetBuilder,
  int itemCount,
  WidgetBuilder? noMoreItemsIndicatorBuilder,
);

typedef ErrorListingBuilder = Widget Function(
  BuildContext context,
  IndexedWidgetBuilder itemWidgetBuilder,
  int itemCount,
  WidgetBuilder newPageErrorIndicatorBuilder,
);

typedef LoadingListingBuilder = Widget Function(
  BuildContext context,
  IndexedWidgetBuilder itemWidgetBuilder,
  int itemCount,
  WidgetBuilder newPageProgressIndicatorBuilder,
);

/// Facilitates creating infinitely scrolled paged layouts.
///
/// Combines a [PagingController] with a
/// [PagedChildBuilderDelegate] and calls the supplied
/// [loadingListingBuilder], [errorListingBuilder] or
/// [completedListingBuilder] for filling in the gaps.
///
/// For ordinary cases, this widget shouldn't be used directly. Instead, take a
/// look at [PagedSliverList], [PagedSliverGrid], [PagedStaggeredSliverGrid],
/// [PagedListView], [PagedGridView], [PagedStaggeredGridView], or
/// [PagedPageView].
class PagedLayoutBuilder<PageKeyType, ItemType> extends StatefulWidget {
  const PagedLayoutBuilder({
    required this.pagingController,
    required this.builderDelegate,
    required this.loadingListingBuilder,
    required this.errorListingBuilder,
    required this.completedListingBuilder,
    this.shrinkWrapFirstPageIndicators = false,
    this.isSliver = true,
    Key? key,
  }) : super(key: key);

  /// The controller for paged listings.
  ///
  /// Informs the current state of the pagination and requests new items from
  /// its listeners.
  final PagingController<PageKeyType, ItemType> pagingController;

  /// The delegate for building the UI pieces of scrolling paged listings.
  final PagedChildBuilderDelegate<ItemType> builderDelegate;

  /// The builder for an in-progress listing.
  final LoadingListingBuilder loadingListingBuilder;

  /// The builder for an in-progress listing with a failed request.
  final ErrorListingBuilder errorListingBuilder;

  /// The builder for a completed listing.
  final CompletedListingBuilder completedListingBuilder;

  /// Whether the extent of the first page indicators should be determined by
  /// the contents being viewed.
  ///
  /// If the paged sliver builder does not shrink wrap, then the first page
  /// indicators will expand to the maximum allowed size. If the paged sliver
  /// builder has unbounded constraints, then [shrinkWrapFirstPageIndicators]
  /// must be true.
  ///
  /// Defaults to false.
  final bool shrinkWrapFirstPageIndicators;

  /// Whether the builder is used in a sliver.
  ///
  /// This is useful for usages of the builder with widgets that
  /// are not slivers.
  /// If true, [PagedChildBuilderDelegate.animateTransitions] is ignored.
  ///
  /// Defaults to true.
  final bool isSliver;

  @override
  _PagedLayoutBuilderState<PageKeyType, ItemType> createState() =>
      _PagedLayoutBuilderState<PageKeyType, ItemType>();
}

class _PagedLayoutBuilderState<PageKeyType, ItemType>
    extends State<PagedLayoutBuilder<PageKeyType, ItemType>> {
  PagingController<PageKeyType, ItemType> get _pagingController =>
      widget.pagingController;

  PagedChildBuilderDelegate<ItemType> get _builderDelegate =>
      widget.builderDelegate;

  bool get _shrinkWrapFirstPageIndicators =>
      widget.shrinkWrapFirstPageIndicators;

  bool get _isSliver => widget.isSliver;

  WidgetBuilder get _firstPageErrorIndicatorBuilder =>
      _builderDelegate.firstPageErrorIndicatorBuilder ??
      (_) => FirstPageErrorIndicator(
            onTryAgain: _pagingController.retryLastFailedRequest,
          );

  WidgetBuilder get _newPageErrorIndicatorBuilder =>
      _builderDelegate.newPageErrorIndicatorBuilder ??
      (_) => NewPageErrorIndicator(
            onTap: _pagingController.retryLastFailedRequest,
          );

  WidgetBuilder get _firstPageProgressIndicatorBuilder =>
      _builderDelegate.firstPageProgressIndicatorBuilder ??
      (_) => FirstPageProgressIndicator();

  WidgetBuilder get _newPageProgressIndicatorBuilder =>
      _builderDelegate.newPageProgressIndicatorBuilder ??
      (_) => const NewPageProgressIndicator();

  WidgetBuilder get _noItemsFoundIndicatorBuilder =>
      _builderDelegate.noItemsFoundIndicatorBuilder ??
      (_) => NoItemsFoundIndicator();

  WidgetBuilder? get _noMoreItemsIndicatorBuilder =>
      _builderDelegate.noMoreItemsIndicatorBuilder;

  int get _invisibleItemsThreshold =>
      _pagingController.invisibleItemsThreshold ?? 3;

  int get _itemCount => _pagingController.itemCount;

  bool get _hasNextPage => _pagingController.hasNextPage;

  PageKeyType? get _nextKey => _pagingController.nextPageKey;

  /// Avoids duplicate requests on rebuilds.
  bool _hasRequestedNextPage = false;

  @override
  Widget build(BuildContext context) => ListenableListener(
        listenable: _pagingController,
        listener: () {
          final status = _pagingController.value.status;

          if (status == PagingStatus.loadingFirstPage) {
            _pagingController.notifyPageRequestListeners(
              _pagingController.firstPageKey,
            );
          }

          if (status == PagingStatus.ongoing) {
            _hasRequestedNextPage = false;
          }
        },
        child: ValueListenableBuilder<PagingState<PageKeyType, ItemType>>(
          valueListenable: _pagingController,
          builder: (context, pagingState, _) {
            Widget child;
            final itemList = _pagingController.itemList;
            switch (pagingState.status) {
              case PagingStatus.ongoing:
                child = widget.loadingListingBuilder(
                  context,
                  // We must create this closure to close over the [itemList]
                  // value. That way, we are safe if [itemList] value changes
                  // while Flutter rebuilds the widget (due to animations, for
                  // example.)
                  (context, index) => _buildListItemWidget(
                    context,
                    index,
                    itemList!,
                  ),
                  _itemCount,
                  _newPageProgressIndicatorBuilder,
                );
                break;
              case PagingStatus.completed:
                child = widget.completedListingBuilder(
                  context,
                  (context, index) => _buildListItemWidget(
                    context,
                    index,
                    itemList!,
                  ),
                  _itemCount,
                  _noMoreItemsIndicatorBuilder,
                );
                break;
              case PagingStatus.loadingFirstPage:
                child = _FirstPageStatusIndicatorBuilder(
                  builder: _firstPageProgressIndicatorBuilder,
                  shrinkWrap: _shrinkWrapFirstPageIndicators,
                  isSliver: _isSliver,
                );
                break;
              case PagingStatus.subsequentPageError:
                child = widget.errorListingBuilder(
                  context,
                  (context, index) => _buildListItemWidget(
                    context,
                    index,
                    itemList!,
                  ),
                  _itemCount,
                  (context) => _newPageErrorIndicatorBuilder(context),
                );
                break;
              case PagingStatus.noItemsFound:
                child = _FirstPageStatusIndicatorBuilder(
                  builder: _noItemsFoundIndicatorBuilder,
                  shrinkWrap: _shrinkWrapFirstPageIndicators,
                  isSliver: _isSliver,
                );
                break;
              default:
                child = _FirstPageStatusIndicatorBuilder(
                  builder: _firstPageErrorIndicatorBuilder,
                  shrinkWrap: _shrinkWrapFirstPageIndicators,
                  isSliver: _isSliver,
                );
            }

            if (_isSliver && _builderDelegate.animateTransitions) {
              return SliverAnimatedSwitcher(
                duration: _builderDelegate.transitionDuration,
                child: KeyedSubtree(
                  // The `ObjectKey` makes it possible to differentiate
                  // transitions between same Widget types, e.g., ongoing to
                  // completed.
                  key: ObjectKey(pagingState),
                  child: child,
                ),
              );
            } else {
              return child;
            }
          },
        ),
      );

  /// Connects the [_pagingController] with the [_builderDelegate] in order to
  /// create a list item widget and request more items if needed.
  Widget _buildListItemWidget(
    BuildContext context,
    int index,
    List<ItemType> itemList,
  ) {
    if (!_hasRequestedNextPage) {
      final newPageRequestTriggerIndex =
          max(0, _itemCount - _invisibleItemsThreshold);

      final isBuildingTriggerIndexItem = index == newPageRequestTriggerIndex;

      if (_hasNextPage && isBuildingTriggerIndexItem) {
        // Schedules the request for the end of this frame.
        WidgetsBinding.instance?.addPostFrameCallback((_) {
          _pagingController.notifyPageRequestListeners(_nextKey!);
        });
        _hasRequestedNextPage = true;
      }
    }

    final item = itemList[index];
    return _builderDelegate.itemBuilder(context, item, index);
  }
}

extension on PagingController {
  /// The loaded items count.
  int get itemCount => itemList?.length ?? 0;

  /// Tells whether there's a next page to request.
  bool get hasNextPage => nextPageKey != null;
}

class _FirstPageStatusIndicatorBuilder extends StatelessWidget {
  const _FirstPageStatusIndicatorBuilder({
    required this.builder,
    this.shrinkWrap = false,
    this.isSliver = false,
    Key? key,
  }) : super(key: key);

  final WidgetBuilder builder;
  final bool shrinkWrap;
  final bool isSliver;

  @override
  Widget build(BuildContext context) {
    if (isSliver) {
      if (shrinkWrap) {
        return SliverToBoxAdapter(
          child: builder(context),
        );
      } else {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: builder(context),
        );
      }
    } else {
      return Center(
        child: builder(context),
      );
    }
  }
}