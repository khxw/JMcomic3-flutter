import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/components/images.dart';

const _methodsChannel = MethodChannel('methods');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late File fixture;
  late Uint8List fixtureBytes;

  setUpAll(() async {
    directory = Directory('build/jm-page-image-layout');
    await directory.create(recursive: true);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 64, 128),
      Paint()..color = Colors.blue,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(64, 128);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    fixtureBytes = bytes!.buffer.asUint8List();
    fixture = File('${directory.path}/page.png');
    await fixture.writeAsBytes(fixtureBytes);
    image.dispose();
    picture.dispose();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methodsChannel, null);
    imageCache.clear();
    imageCache.clearLiveImages();
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!await directory.exists()) return;
      try {
        await directory.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });

  testWidgets('page image paints before the true-size lookup completes',
      (tester) async {
    final sizeGate = Completer<void>();
    var sizeLookupFinished = false;
    Size? reportedSize;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_methodsChannel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      if (request['method'] != 'image_size') {
        throw StateError('Unexpected method: ${request['method']}');
      }
      await sizeGate.future;
      sizeLookupFinished = true;
      return jsonEncode({
        'error_message': '',
        'response_data': jsonEncode({'w': 64, 'h': 128}),
      });
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 640,
            child: JMPageImage(
              1,
              'page.png',
              localPath: fixture.path,
              imageProvider: MemoryImage(fixtureBytes),
              width: 320,
              height: 640,
              onTrueSize: (size) => reportedSize = size,
            ),
          ),
        ),
      ),
    );

    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(sizeLookupFinished, isFalse);
    expect(reportedSize, isNull);

    sizeGate.complete();
    for (var attempt = 0; attempt < 20 && reportedSize == null; attempt++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }

    expect(sizeLookupFinished, isTrue);
    expect(reportedSize, const Size(64, 128));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  });
}
