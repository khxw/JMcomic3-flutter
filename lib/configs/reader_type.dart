import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/enum_property.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

enum ReaderType {
  webtoon,
  // Legacy values remain parseable so older local/WebDAV snapshots can be
  // migrated without losing the user's other reader preferences.
  gallery,
  webToonFreeZoom,
  twoPageGallery,
}

const selectableReaderTypes = [
  ReaderType.webtoon,
  ReaderType.webToonFreeZoom,
];

const _propertyName = "readerType";
late ReaderType _readerType;

Future initReaderType() async {
  _readerType = _fromString(await methods.loadProperty(_propertyName));
}

ReaderType _fromString(String valueForm) {
  final parsed = parseEnumPropertyValue(
    valueForm,
    ReaderType.values,
    ReaderType.webtoon,
  );
  return selectableReaderTypes.contains(parsed) ? parsed : ReaderType.webtoon;
}

ReaderType get currentReaderType => _readerType;

String readerTypeName(ReaderType type, BuildContext context) {
  switch (type) {
    case ReaderType.webtoon:
      return context.l10n.tr("无限瀑布流", en: "Infinite webtoon");
    case ReaderType.gallery:
      return context.l10n.tr("相册", en: "Gallery");
    case ReaderType.webToonFreeZoom:
      return context.l10n.tr(
        "自由缩放瀑布流",
        en: "Zoomable webtoon",
      );
    case ReaderType.twoPageGallery:
      return context.l10n.tr("双页相册", en: "Two-page gallery");
  }
}

Future chooseReaderType(BuildContext context) async {
  final Map<String, ReaderType> map = {};
  for (final element in selectableReaderTypes) {
    map[readerTypeName(element, context)] = element;
  }
  final newReaderType = await chooseMapDialog(
    context,
    title: context.l10n.tr("请选择阅读器类型", en: "Choose reader type"),
    values: map,
  );
  if (newReaderType != null) {
    await methods.saveProperty(_propertyName, "$newReaderType");
    _readerType = newReaderType;
  }
}
