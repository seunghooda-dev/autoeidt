import 'dart:convert';
import 'dart:io' as io;

import '../models/job_models.dart';

class ProjectRecoverySnapshot {
  const ProjectRecoverySnapshot({
    required this.project,
    required this.savedAt,
    this.id = 'latest',
    this.label = 'Auto Save',
    this.isManual = false,
  });

  final ProjectState project;
  final DateTime savedAt;
  final String id;
  final String label;
  final bool isManual;
}

class ProjectRecoveryService {
  ProjectRecoveryService({io.Directory? directory, DateTime Function()? clock})
    : _directory = directory ?? _defaultDirectory(),
      _clock = clock ?? DateTime.now;

  final io.Directory _directory;
  final DateTime Function() _clock;
  int _versionSequence = 0;

  io.File get _snapshotFile => io.File(
    '${_directory.path}${io.Platform.pathSeparator}autoedit_recovery.json',
  );
  io.Directory get _versionsDirectory => io.Directory(
    '${_directory.path}${io.Platform.pathSeparator}recovery_versions',
  );
  io.File get _sessionFile => io.File(
    '${_directory.path}${io.Platform.pathSeparator}session_state.json',
  );

  static io.Directory _defaultDirectory() {
    final environment = io.Platform.environment;
    final base =
        environment['LOCALAPPDATA'] ??
        environment['APPDATA'] ??
        io.Directory.systemTemp.path;
    return io.Directory('$base${io.Platform.pathSeparator}AutoEdit');
  }

  Future<ProjectRecoverySnapshot> saveProject(
    ProjectState project, {
    String? label,
    bool manual = false,
  }) async {
    await _directory.create(recursive: true);
    final savedAt = _clock().toUtc();
    final id =
        '${savedAt.microsecondsSinceEpoch}_'
        '${DateTime.now().microsecondsSinceEpoch}_${_versionSequence++}';
    final resolvedLabel = label?.trim().isNotEmpty == true
        ? label!.trim()
        : manual
        ? 'Manual Snapshot'
        : 'Auto Save';
    final payload = {
      'version': 2,
      'id': id,
      'label': resolvedLabel,
      'is_manual': manual,
      'saved_at': savedAt.toIso8601String(),
      'project': project.toJson(),
    };
    await _writeAtomic(_snapshotFile, payload);
    await _versionsDirectory.create(recursive: true);
    await _writeAtomic(
      io.File('${_versionsDirectory.path}${io.Platform.pathSeparator}$id.json'),
      payload,
    );
    await _pruneVersions();
    return ProjectRecoverySnapshot(
      project: project,
      savedAt: savedAt,
      id: id,
      label: resolvedLabel,
      isManual: manual,
    );
  }

  Future<ProjectRecoverySnapshot?> readSnapshot() async {
    final file = _snapshotFile;
    if (!await file.exists()) {
      return null;
    }

    return _readFile(file);
  }

  Future<bool?> beginSession() async {
    bool? previousSessionWasClean;
    if (await _sessionFile.exists()) {
      try {
        final raw = jsonDecode(await _sessionFile.readAsString());
        if (raw is Map) {
          previousSessionWasClean = raw['clean_exit'] as bool?;
        }
      } catch (_) {
        previousSessionWasClean = false;
      }
    }
    await _writeSessionState(cleanExit: false);
    return previousSessionWasClean;
  }

  Future<void> markSessionClean() => _writeSessionState(cleanExit: true);

  void markSessionCleanSync() {
    _directory.createSync(recursive: true);
    final temporary = io.File('${_sessionFile.path}.${io.pid}.tmp');
    temporary.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'clean_exit': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    if (_sessionFile.existsSync()) {
      _sessionFile.deleteSync();
    }
    temporary.renameSync(_sessionFile.path);
  }

  Future<List<ProjectRecoverySnapshot>> listVersions() async {
    if (!await _versionsDirectory.exists()) {
      return const [];
    }
    final versions = <ProjectRecoverySnapshot>[];
    await for (final entity in _versionsDirectory.list()) {
      if (entity is! io.File || !entity.path.endsWith('.json')) {
        continue;
      }
      try {
        final snapshot = await _readFile(entity);
        if (snapshot != null) {
          versions.add(snapshot);
        }
      } catch (_) {
        // Ignore one corrupt version while keeping the remaining history.
      }
    }
    versions.sort((a, b) {
      final savedAtComparison = b.savedAt.compareTo(a.savedAt);
      return savedAtComparison != 0 ? savedAtComparison : b.id.compareTo(a.id);
    });
    return versions;
  }

  Future<ProjectRecoverySnapshot?> readVersion(String id) async {
    if (!_isValidVersionId(id)) {
      return null;
    }
    return _readFile(
      io.File('${_versionsDirectory.path}${io.Platform.pathSeparator}$id.json'),
    );
  }

  Future<void> deleteVersion(String id) async {
    if (!_isValidVersionId(id)) {
      return;
    }
    final file = io.File(
      '${_versionsDirectory.path}${io.Platform.pathSeparator}$id.json',
    );
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<bool> hasSnapshot() async => _snapshotFile.exists();

  Future<void> clearSnapshot() async {
    if (await _snapshotFile.exists()) {
      await _snapshotFile.delete();
    }
    if (await _versionsDirectory.exists()) {
      await _versionsDirectory.delete(recursive: true);
    }
  }

  Future<ProjectRecoverySnapshot?> _readFile(io.File file) async {
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
      id: raw['id']?.toString() ?? file.uri.pathSegments.last.split('.').first,
      label: raw['label']?.toString() ?? 'Auto Save',
      isManual: raw['is_manual'] as bool? ?? false,
    );
  }

  Future<void> _writeAtomic(io.File file, Map<String, dynamic> payload) async {
    final tempFile = io.File(
      '${file.path}.${io.pid}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tempFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
  }

  Future<void> _writeSessionState({required bool cleanExit}) async {
    await _directory.create(recursive: true);
    await _writeAtomic(_sessionFile, {
      'version': 1,
      'clean_exit': cleanExit,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _pruneVersions({int keepPerType = 20}) async {
    final files = await _versionsDirectory
        .list()
        .where((entity) => entity is io.File && entity.path.endsWith('.json'))
        .cast<io.File>()
        .toList();

    final automatic = <({io.File file, ProjectRecoverySnapshot snapshot})>[];
    final manual = <({io.File file, ProjectRecoverySnapshot snapshot})>[];
    for (final file in files) {
      try {
        final snapshot = await _readFile(file);
        if (snapshot == null) {
          continue;
        }
        (snapshot.isManual ? manual : automatic).add((
          file: file,
          snapshot: snapshot,
        ));
      } catch (_) {
        // Corrupt entries are ignored here and skipped by listVersions().
      }
    }

    int newestFirst(
      ({io.File file, ProjectRecoverySnapshot snapshot}) a,
      ({io.File file, ProjectRecoverySnapshot snapshot}) b,
    ) {
      final savedAtComparison = b.snapshot.savedAt.compareTo(
        a.snapshot.savedAt,
      );
      return savedAtComparison != 0
          ? savedAtComparison
          : b.snapshot.id.compareTo(a.snapshot.id);
    }

    automatic.sort(newestFirst);
    manual.sort(newestFirst);
    for (final entry in [
      ...automatic.skip(keepPerType),
      ...manual.skip(keepPerType),
    ]) {
      await entry.file.delete();
    }
  }

  bool _isValidVersionId(String id) =>
      RegExp(r'^\d+_\d+(?:_\d+)?$').hasMatch(id);
}
