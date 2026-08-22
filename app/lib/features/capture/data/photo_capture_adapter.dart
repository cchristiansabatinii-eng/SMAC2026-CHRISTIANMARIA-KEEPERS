// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:path/path.dart' as p;

typedef PickImage = Future<XFile?> Function({
  required ImageSource source,
  required bool requestFullMetadata,
});
typedef RetrieveLostData = Future<LostDataResponse> Function();

abstract interface class PhotoCaptureAdapter {
  Future<String?> pick(PhotoSource source);
  Future<String?> recoverLostPhoto();
}

final class ImagePickerPhotoCaptureAdapter implements PhotoCaptureAdapter {
  ImagePickerPhotoCaptureAdapter({
    ImagePicker? picker,
    Directory? captureTemporaryDirectory,
    Future<Directory> Function()? temporaryDirectory,
    required String Function() idFactory,
    PickImage? pickImage,
    RetrieveLostData? retrieveLostData,
  }) : _picker = picker ?? ImagePicker(),
       _directory = captureTemporaryDirectory,
       _temporaryDirectory = temporaryDirectory,
       _idFactory = idFactory,
       _pickImage = pickImage,
       _retrieveLostData = retrieveLostData;

  final ImagePicker _picker;
  final Directory? _directory;
  final Future<Directory> Function()? _temporaryDirectory;
  final String Function() _idFactory;
  final PickImage? _pickImage;
  final RetrieveLostData? _retrieveLostData;

  @override
  Future<String?> pick(PhotoSource source) async {
    try {
      final image = await (_pickImage ?? _picker.pickImage)(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        requestFullMetadata: false,
      );
      return image == null
          ? null
          : await _own(
              image,
              deleteSourceAfterCopy: source == PhotoSource.camera,
            );
    } on PlatformException catch (error) {
      throw CapturePermissionException(source.permissionSource, error);
    }
  }

  @override
  Future<String?> recoverLostPhoto() async {
    final response = await (_retrieveLostData ?? _picker.retrieveLostData)();
    if (response.exception != null) throw response.exception!;
    final files = response.files;
    return files == null || files.isEmpty ? null : _own(files.first);
  }

  Future<String> _own(XFile image, {bool deleteSourceAfterCopy = false}) async {
    final root = _directory ?? await _temporaryDirectory!();
    final directory = Directory(p.join(root.path, 'keepers-capture'));
    await directory.create(recursive: true);
    final rawExtension = p.extension(image.path).toLowerCase();
    final extension = RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(rawExtension)
        ? rawExtension
        : '.jpg';
    final destination = p.join(directory.path, '${_idFactory()}$extension');
    final sourceFile = File(image.path);
    final destinationFile = File(destination);
    final pathsMatch = p.equals(
      sourceFile.absolute.path,
      destinationFile.absolute.path,
    );
    try {
      await sourceFile.copy(destination);
    } catch (_) {
      if (!pathsMatch) await _bestEffortDelete(destinationFile);
      rethrow;
    }
    if (deleteSourceAfterCopy && !pathsMatch) {
      await _bestEffortDelete(sourceFile);
    }
    return destination;
  }

  Future<void> _bestEffortDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // The owned copy remains usable if temporary-file cleanup is denied.
    }
  }
}
