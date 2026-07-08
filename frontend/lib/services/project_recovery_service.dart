import 'dart:convert';
import 'dart:io' as io;

import '../models/job_models.dart';

class ProjectRecoverySnapshot {
  const ProjectRecoverySnapshot({required this.project, required this.savedAt});

  final ProjectState project;
  final DateTime savedAt;
}

class ProjectRecoveryService {
  ProjectRecoveryService({io.Directory? directory, DateTime Function()? clock})
    : _directory = directory ?? _defaultDirectory(),
      _clock = clock ?? DateTime.now;

  final io.Directory _directory;
  final DateTime Function() _clock;

  io.File get _snapshotFile => io.File(
    '${_directory.path}${io.Platform.pathSeparator}autoedit_recovery.json',
  );

  static io.Directory _defaultDirectory() {
    final environment = io.Platform.environment;
    final base =
        environment['LOCALAPPDATA'] ??
        environment['APPDATA'] ??
        io.Directory.systemTemp.path;
    return io.Directory('$base${io.Platform.pathSeparator}AutoEdit');
  }

  Future<ProjectRecoverySnapshot> saveProject(ProjectState project) async {
    await _directory.create(recursive: true);
    final savedAt = _clock().toUtc();
    final payload = {
      'version': 1,
      'saved_at': savedAt.toIso8601String(),
      'project': project.toJson(),
    };
    final tempFile = io.File(
      '${_snapshotFile.path}.${io.pid}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tempFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    if (await _snapshotFile.exists()) {
      await _snapshotFile.delete();
    }
    await tempFile.rename(_snapshotFile.path);
    return ProjectRecoverySnapshot(project: project, savedAt: savedAt);
  }

  Future<ProjectRecoverySnapshot?> readSnapshot() async {
    final file = _snapshotFile;
    if (!await file.exists()) {
      return null;
    }

    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map<String, dynamic>) {
      return null;
    }

    final projectJson = raw['project'] is Map
        ? Map<String, dynamic>.from(raw['project'] as Map)
        : raw;
    final savedAt = DateTime.tryParse(raw['saved_at']?.toString() ?? '');
    return ProjectRecoverySnapshot(
      project: ProjectState.fromJson(projectJson),
      savedAt: savedAt ?? await file.lastModified(),
    );
  }

  Future<bool> hasSnapshot() async => _snapshotFile.exists();

  Future<void> clearSnapshot() async {
    if (await _snapshotFile.exists()) {
      await _snapshotFile.delete();
    }
  }
}
