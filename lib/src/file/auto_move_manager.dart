import 'dart:io';

import 'package:dtorrent_task_v2/src/file/download_file.dart';
import 'package:logging/logging.dart';

typedef AutoMoveFileAction = Future<bool> Function(
  String torrentFilePath,
  String newAbsolutePath,
);

class AutoMoveRule {
  final Set<String> extensions;
  final String destinationDirectory;

  const AutoMoveRule({
    required this.extensions,
    required this.destinationDirectory,
  });

  bool matches(String fileName) {
    final ext = _extensionOf(fileName);
    return extensions.contains(ext);
  }

  static String _extensionOf(String fileName) {
    final idx = fileName.lastIndexOf('.');
    if (idx < 0 || idx == fileName.length - 1) return '';
    return fileName.substring(idx + 1).toLowerCase();
  }
}

class AutoMoveConfig {
  final String? defaultDestinationDirectory;
  final bool allowExternalDisks;
  final List<AutoMoveRule> rules;

  const AutoMoveConfig({
    this.defaultDestinationDirectory,
    this.allowExternalDisks = true,
    this.rules = const <AutoMoveRule>[],
  });
}

class AutoMoveResult {
  final bool success;
  final String fromPath;
  final String toPath;
  final String? error;

  const AutoMoveResult({
    required this.success,
    required this.fromPath,
    required this.toPath,
    this.error,
  });
}

class AutoMoveManager {
  final AutoMoveFileAction _moveAction;
  final Logger _log;
  AutoMoveConfig _config;

  AutoMoveManager({
    required AutoMoveFileAction moveAction,
    AutoMoveConfig config = const AutoMoveConfig(),
    Logger? logger,
  })  : _moveAction = moveAction,
        _config = config,
        _log = logger ?? Logger('AutoMoveManager');

  AutoMoveConfig get config => _config;

  void updateConfig(AutoMoveConfig config) {
    _config = config;
  }

  Future<AutoMoveResult?> moveCompletedFile(DownloadFile file) async {
    if (file.isVirtualFile) return null;

    final targetDirectory = _resolveTargetDirectory(file);
    if (targetDirectory == null || targetDirectory.isEmpty) {
      return null;
    }

    final destinationPath = _joinPath(targetDirectory, file.originalFileName);

    if (!_config.allowExternalDisks && _isExternalDiskPath(destinationPath)) {
      return AutoMoveResult(
        success: false,
        fromPath: file.filePath,
        toPath: destinationPath,
        error: 'External disk destinations are disabled',
      );
    }

    try {
      final ok = await _moveAction(file.torrentFilePath, destinationPath);
      if (!ok) {
        return AutoMoveResult(
          success: false,
          fromPath: file.filePath,
          toPath: destinationPath,
          error: 'Move action returned false',
        );
      }
      _log.info('Auto-moved ${file.torrentFilePath} to $destinationPath');
      return AutoMoveResult(
        success: true,
        fromPath: file.filePath,
        toPath: destinationPath,
      );
    } catch (e) {
      _log.warning('Failed to auto-move ${file.torrentFilePath}', e);
      return AutoMoveResult(
        success: false,
        fromPath: file.filePath,
        toPath: destinationPath,
        error: e.toString(),
      );
    }
  }

  String? _resolveTargetDirectory(DownloadFile file) {
    for (final rule in _config.rules) {
      if (rule.matches(file.originalFileName)) {
        return rule.destinationDirectory;
      }
    }
    return _config.defaultDestinationDirectory;
  }

  static bool _isExternalDiskPath(String path) {
    if (Platform.isMacOS) {
      return path.startsWith('/Volumes/');
    }
    if (Platform.isLinux) {
      return path.startsWith('/media/') || path.startsWith('/mnt/');
    }
    if (Platform.isWindows) {
      final normalized = path.replaceAll('\\', '/').toUpperCase();
      return normalized.startsWith('E:/') ||
          normalized.startsWith('F:/') ||
          normalized.startsWith('G:/');
    }
    return false;
  }

  static String _joinPath(String directory, String fileName) {
    if (directory.endsWith(Platform.pathSeparator)) {
      return '$directory$fileName';
    }
    return '$directory${Platform.pathSeparator}$fileName';
  }
}
