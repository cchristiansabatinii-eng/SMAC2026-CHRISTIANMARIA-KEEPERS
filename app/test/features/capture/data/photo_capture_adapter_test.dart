import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:keepers/features/capture/data/photo_capture_adapter.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('photo-adapter-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test('maps camera and library and disables full metadata', () async {
    final source = File('${root.path}/source.jpg')..writeAsBytesSync([1, 2]);
    final sourcePath = source.path;
    final calls = <(ImageSource, bool)>[];
    final adapter = ImagePickerPhotoCaptureAdapter(
      captureTemporaryDirectory: root,
      idFactory: () => 'photo-1',
      pickImage: ({required source, required requestFullMetadata}) async {
        calls.add((source, requestFullMetadata));
        return XFile(sourcePath);
      },
    );

    final cameraPath = await adapter.pick(PhotoSource.camera);
    final libraryPath = await adapter.pick(PhotoSource.library);
    expect(calls, [(ImageSource.camera, false), (ImageSource.gallery, false)]);
    expect(File(cameraPath!).readAsBytesSync(), [1, 2]);
    expect(File(libraryPath!).readAsBytesSync(), [1, 2]);
    expect(cameraPath, contains('keepers-capture'));
  });

  test('returns null on cancellation', () async {
    final adapter = ImagePickerPhotoCaptureAdapter(
      captureTemporaryDirectory: root,
      idFactory: () => 'photo-1',
      pickImage: ({required source, required requestFullMetadata}) async =>
          null,
    );
    expect(await adapter.pick(PhotoSource.library), isNull);
  });

  test('maps platform permission failures to the selected source', () async {
    final adapter = ImagePickerPhotoCaptureAdapter(
      captureTemporaryDirectory: root,
      idFactory: () => 'photo-1',
      pickImage: ({required source, required requestFullMetadata}) async {
        throw PlatformException(code: 'camera_access_denied');
      },
    );
    await expectLater(
      adapter.pick(PhotoSource.camera),
      throwsA(
        isA<CapturePermissionException>().having(
          (e) => e.source,
          'source',
          CapturePermissionSource.camera,
        ),
      ),
    );
  });

  test('recovers first lost photo and surfaces lost-data error', () async {
    final source = File('${root.path}/lost.jpg')..writeAsBytesSync([4]);
    final adapter = ImagePickerPhotoCaptureAdapter(
      captureTemporaryDirectory: root,
      idFactory: () => 'lost-1',
      retrieveLostData: () async =>
          LostDataResponse(files: [XFile(source.path)]),
    );
    expect(await adapter.recoverLostPhoto(), contains('lost-1.jpg'));

    final failed = ImagePickerPhotoCaptureAdapter(
      captureTemporaryDirectory: root,
      idFactory: () => 'lost-2',
      retrieveLostData: () async =>
          LostDataResponse(exception: PlatformException(code: 'lost')),
    );
    await expectLater(
      failed.recoverLostPhoto(),
      throwsA(isA<PlatformException>()),
    );
  });
}
