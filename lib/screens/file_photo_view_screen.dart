import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:photo_view/photo_view.dart';

import 'components/right_click_pop.dart';

// 预览图片
class FilePhotoViewScreen extends StatelessWidget {
  final String filePath;

  const FilePhotoViewScreen(this.filePath, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) => Scaffold(
        body: Stack(
          children: [
            GestureDetector(
              onLongPress: Platform.isAndroid || Platform.isIOS
                  ? () async {
                      final saveToGallery = context.l10n.tr(
                        '保存图片到相册',
                        en: 'Save image to gallery',
                      );
                      final choose = await chooseListDialog(
                        context,
                        title: context.l10n.choose,
                        values: [saveToGallery],
                      );
                      if (choose == saveToGallery) {
                        saveImageFileToGallery(context, filePath);
                      }
                    }
                  : null,
              child: PhotoView(
                imageProvider: FileImage(File(filePath)),
              ),
            ),
            InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                margin: const EdgeInsets.only(top: 80),
                padding: const EdgeInsets.only(left: 4, right: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.75),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Icon(Icons.keyboard_backspace, color: Colors.white),
              ),
            ),
          ],
        ),
      );
}
