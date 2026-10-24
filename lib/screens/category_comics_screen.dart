import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/screens/components/comic_pager.dart';

import 'components/browser_bottom_sheet.dart';

class CategoryComicsScreen extends StatelessWidget {
  final Categories category;
  final SortBy sortBy;

  const CategoryComicsScreen({
    required this.category,
    this.sortBy = sortByNew,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(category.name),
        actions: const [BrowserBottomSheetAction()],
      ),
      body: ComicPager(
        key: ValueKey('category:${category.slug}:${sortBy.value}'),
        onPage: (page) async {
          final response = await methods.comics(category.slug, sortBy, page);
          return InnerComicPage(
            total: response.total,
            list: response.content,
          );
        },
      ),
    );
  }
}
