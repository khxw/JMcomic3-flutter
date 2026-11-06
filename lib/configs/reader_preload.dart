import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _propertyName = 'reader_preload_pages';
const _forwardOnlyPropertyName = 'reader_preload_forward_only';
const List<int> readerPreloadPageOptions = [0, 1, 2, 4, 6];
int _readerPreloadPages = 2;
bool _readerPreloadForwardOnly = false;

int get currentReaderPreloadPages => _readerPreloadPages;
bool get currentReaderPreloadForwardOnly => _readerPreloadForwardOnly;

Future<void> initReaderPreload() async {
  final values = await Future.wait([
    methods.loadProperty(_propertyName),
    methods.loadProperty(_forwardOnlyPropertyName),
  ]);
  _readerPreloadPages = parseReaderPreloadPages(values[0]);
  _readerPreloadForwardOnly = parseReaderPreloadForwardOnly(values[1]);
}

int parseReaderPreloadPages(String raw) {
  final value = int.tryParse(raw.trim());
  return value != null && readerPreloadPageOptions.contains(value) ? value : 2;
}

bool parseReaderPreloadForwardOnly(String raw) {
  final value = raw.trim().toLowerCase();
  return value == '1' || value == 'true' || value == 'forward';
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

String readerPreloadModeName(BuildContext context, bool forwardOnly) {
  return forwardOnly
      ? context.l10n.tr('仅向后预加载', en: 'Forward only')
      : context.l10n.tr('前后双向', en: 'Both directions');
}

Future<void> chooseReaderPreloadMode(BuildContext context) async {
  final selected = await chooseMapDialog<bool>(
    context,
    title: context.l10n.tr('选择预加载方向', en: 'Choose preload direction'),
    values: {
      context.l10n.tr('前后双向', en: 'Both directions'): false,
      context.l10n.tr('仅向后预加载', en: 'Forward only'): true,
    },
  );
  if (selected == null) return;
  await methods.saveProperty(_forwardOnlyPropertyName, '$selected');
  _readerPreloadForwardOnly = selected;
}

List<int> readerPreloadIndices({
  required int current,
  required int total,
  required int pages,
  required bool paired,
  bool forwardOnly = false,
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
    if (!forwardOnly) {
      final backward = current - distance * step;
      if (backward >= 0 && backward < total && seen.add(backward)) {
        indices.add(backward);
      }
    }
  }
  return List<int>.unmodifiable(indices);
}
