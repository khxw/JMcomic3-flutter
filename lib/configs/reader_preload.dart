import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _propertyName = 'reader_preload_pages';
const List<int> readerPreloadPageOptions = [0, 1, 2, 4, 6];
int _readerPreloadPages = 2;

int get currentReaderPreloadPages => _readerPreloadPages;

Future<void> initReaderPreload() async {
  _readerPreloadPages = parseReaderPreloadPages(
    await methods.loadProperty(_propertyName),
  );
}

int parseReaderPreloadPages(String raw) {
  final value = int.tryParse(raw.trim());
  return value != null && readerPreloadPageOptions.contains(value) ? value : 2;
}

String readerPreloadPagesName(BuildContext context, int pages) {
  if (pages == 0) {
    return context.l10n.tr('关闭', en: 'Off');
  }
  return context.l10n.tr(
    '前后 $pages 页',
    en: '$pages page(s) each side',
  );
}

Future<void> chooseReaderPreloadPages(BuildContext context) async {
  final values = {
    for (final pages in readerPreloadPageOptions)
      readerPreloadPagesName(context, pages): pages,
  };
  final selected = await chooseMapDialog<int>(
    context,
    title: context.l10n.tr('选择预加载页数', en: 'Choose preload distance'),
    values: values,
  );
  if (selected == null) return;
  await methods.saveProperty(_propertyName, '$selected');
  _readerPreloadPages = selected;
}

List<int> readerPreloadIndices({
  required int current,
  required int total,
  required int pages,
  required bool paired,
}) {
  if (pages <= 0 || total <= 0) return const [];
  final step = paired ? 2 : 1;
  final indices = <int>[];
  final seen = <int>{};
  for (var distance = 1; distance <= pages; distance++) {
    final forward = current + distance * step;
    if (forward >= 0 && forward < total && seen.add(forward)) {
      indices.add(forward);
    }
    final backward = current - distance * step;
    if (backward >= 0 && backward < total && seen.add(backward)) {
      indices.add(backward);
    }
  }
  return List<int>.unmodifiable(indices);
}
