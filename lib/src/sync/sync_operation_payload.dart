import 'package:collection/collection.dart';

import '../core/model/json_helpers.dart';
import '../core/model/paper_constants.dart';
import '../core/model/paper_data.dart';
import '../core/model/paper_item.dart';
import '../core/model/paper_titles.dart';
import '../core/model/todo_paste.dart';
import '../core/model/todo_due_date.dart';
import '../core/state/papertodo_legacy_migration.dart';
import 'sync_device_id.dart';
import 'sync_operation.dart';
import 'sync_text_limits.dart';

bool isSyncOperationPayloadWellFormed(SyncOperation operation) {
  final payload = operation.payload;
  switch (operation.kind) {
    case SyncOperationKind.stateSnapshot:
      return _isSafeSnapshotPathPayload(_payloadValue(payload, 'snapshotPath'));
    case SyncOperationKind.upsertPaper:
      final paperJson = _jsonMapOrNull(_payloadValue(payload, 'paper'));
      if (paperJson == null) {
        return false;
      }
      if (!_hasSafePaperPayloadShape(paperJson)) {
        return false;
      }
      return _hasSafePaperPayloadIds(_migratePaperPayload(paperJson));
    case SyncOperationKind.deletePaper:
      return _payloadStringId(payload, 'paperId').isNotEmpty;
    case SyncOperationKind.upsertTodoItem:
      final itemJson = _jsonMapOrNull(_payloadValue(payload, 'item'));
      if (itemJson == null) {
        return false;
      }
      return _payloadStringId(payload, 'paperId').isNotEmpty &&
          _hasSafeTodoItemPayloadShape(itemJson) &&
          _hasSafeTodoItemPayloadIds(_migrateTodoItemPayload(itemJson));
    case SyncOperationKind.deleteTodoItem:
      return _payloadStringId(payload, 'paperId').isNotEmpty &&
          _payloadStringId(payload, 'itemId').isNotEmpty;
    case SyncOperationKind.updateNoteContent:
      return _payloadStringId(payload, 'paperId').isNotEmpty &&
          _payloadMarkdownTextFieldIsSafe(payload, 'content');
    case SyncOperationKind.updateSettings:
      final settings = _jsonMapOrNull(_payloadValue(payload, 'settings'));
      return settings != null &&
          (settings.isEmpty ||
              _hasApplicableSettingsPayload(settings) ||
              _hasLocalOnlyCapsuleSettingsPayload(settings));
  }
}

bool areSyncOperationsEquivalent(SyncOperation left, SyncOperation right) {
  final leftDeviceId = normalizeSyncDeviceId(left.deviceId, fallback: '');
  final rightDeviceId = normalizeSyncDeviceId(right.deviceId, fallback: '');
  final leftPayload = canonicalSyncOperationPayload(left);
  final rightPayload = canonicalSyncOperationPayload(right);
  return leftDeviceId.isNotEmpty &&
      leftDeviceId == rightDeviceId &&
      left.sequence == right.sequence &&
      left.kind == right.kind &&
      left.createdAtUtc.toUtc().isAtSameMomentAs(right.createdAtUtc.toUtc()) &&
      leftPayload != null &&
      rightPayload != null &&
      const DeepCollectionEquality().equals(leftPayload, rightPayload);
}

JsonMap? canonicalSyncOperationPayload(SyncOperation operation) {
  final payload = operation.payload;
  switch (operation.kind) {
    case SyncOperationKind.stateSnapshot:
      final snapshotPath = _payloadValue(payload, 'snapshotPath');
      final canonicalPath = _canonicalSnapshotPathPayload(snapshotPath);
      return canonicalPath == null ? null : {'snapshotPath': canonicalPath};
    case SyncOperationKind.upsertPaper:
      final paperJson = _jsonMapOrNull(_payloadValue(payload, 'paper'));
      if (paperJson == null) {
        return null;
      }
      if (!_hasSafePaperPayloadShape(paperJson)) {
        return null;
      }
      if (!_hasSafePaperPayloadIds(_migratePaperPayload(paperJson))) {
        return null;
      }
      final paper = _canonicalPaperPayload(paperJson);
      return _payloadStringId(paper, 'id').isNotEmpty ? {'paper': paper} : null;
    case SyncOperationKind.deletePaper:
      final paperId = _payloadStringId(payload, 'paperId');
      return paperId.isNotEmpty ? {'paperId': paperId} : null;
    case SyncOperationKind.upsertTodoItem:
      final itemJson = _jsonMapOrNull(_payloadValue(payload, 'item'));
      if (itemJson == null) {
        return null;
      }
      final paperId = _payloadStringId(payload, 'paperId');
      if (!_hasSafeTodoItemPayloadShape(itemJson) ||
          !_hasSafeTodoItemPayloadIds(_migrateTodoItemPayload(itemJson))) {
        return null;
      }
      final item = _canonicalTodoItemPayload(itemJson);
      final itemId = _payloadStringId(item, 'id');
      return paperId.isNotEmpty && itemId.isNotEmpty
          ? {'paperId': paperId, 'item': item}
          : null;
    case SyncOperationKind.deleteTodoItem:
      final paperId = _payloadStringId(payload, 'paperId');
      final itemId = _payloadStringId(payload, 'itemId');
      return paperId.isNotEmpty && itemId.isNotEmpty
          ? {'paperId': paperId, 'itemId': itemId}
          : null;
    case SyncOperationKind.updateNoteContent:
      final paperId = _payloadStringId(payload, 'paperId');
      final content = _payloadValue(payload, 'content');
      return paperId.isNotEmpty &&
              _payloadMarkdownTextFieldIsSafe(payload, 'content') &&
              content is String
          ? {'paperId': paperId, 'content': content}
          : null;
    case SyncOperationKind.updateSettings:
      final settings = _jsonMapOrNull(_payloadValue(payload, 'settings'));
      if (settings == null) {
        return null;
      }
      final safeSettings = canonicalSyncOperationSettingsPayload(settings);
      return settings.isEmpty ||
              safeSettings.isNotEmpty ||
              _hasLocalOnlyCapsuleSettingsPayload(settings)
          ? {'settings': safeSettings}
          : null;
  }
}

JsonMap canonicalSyncOperationPaperPayload(JsonMap paperJson) {
  return _canonicalPaperPayload(paperJson);
}

JsonMap canonicalSyncOperationTodoItemPayload(JsonMap itemJson) {
  return _canonicalTodoItemPayload(itemJson);
}

JsonMap applicableSyncOperationSettingsPayload(JsonMap settings) {
  final migratedSettings = migrateLegacyPaperTodoJson(settings);
  return {
    for (final entry in migratedSettings.entries)
      if (_syncOperationAppPreferenceKeys.contains(entry.key))
        entry.key: entry.value,
  };
}

JsonMap canonicalSyncOperationSettingsPayload(JsonMap settings) {
  final safeSettings = applicableSyncOperationSettingsPayload(settings);
  final canonical = <String, Object?>{};
  for (final entry in safeSettings.entries) {
    if (entry.key == 'showTopBarNewPaperButtons') {
      continue;
    }
    final value = _canonicalSettingValue(entry.key, entry.value);
    if (!identical(value, _invalidSettingValue)) {
      canonical[entry.key] = value;
    }
  }

  final retiredTopBarButtons = safeSettings['showTopBarNewPaperButtons'];
  if (retiredTopBarButtons is bool) {
    canonical
      ..remove('showTopBarNewTodoButton')
      ..remove('showTopBarNewNoteButton')
      ..['showTopBarNewTodoButton'] = retiredTopBarButtons
      ..['showTopBarNewNoteButton'] = retiredTopBarButtons;
  }

  _canonicalizeSettingDependencies(canonical);
  return canonical;
}

void _canonicalizeSettingDependencies(JsonMap canonical) {
  if (canonical['useCapsuleMode'] == false) {
    canonical['useDeepCapsuleMode'] = false;
    canonical['useCapsuleCollapseAll'] = false;
    canonical['hideDeepCapsulesWhenCovered'] = false;
    canonical['hideDeepCapsulesWhenFullscreen'] = false;
  }
  if (canonical['useDeepCapsuleMode'] == false) {
    canonical['useCapsuleCollapseAll'] = false;
    canonical['hideDeepCapsulesWhenCovered'] = false;
    canonical['hideDeepCapsulesWhenFullscreen'] = false;
  }
  if (canonical['useCapsuleCollapseAll'] == false) {
    canonical
      ..['capsuleCollapseAllActive'] = false
      ..['capsuleCollapseAllActiveQueues'] = <String, bool>{};
  }
  if (canonical['useCapsuleMode'] == false ||
      canonical['useDeepCapsuleMode'] == false ||
      canonical['useCapsuleCollapseAll'] == false) {
    canonical
      ..['deepCapsuleStartTopMargin'] = 48.0
      ..['deepCapsuleQueueStartTopMargins'] = <String, double>{};
  }
  final activeQueues = canonical['capsuleCollapseAllActiveQueues'];
  if (canonical['useCapsuleCollapseAll'] == true &&
      activeQueues is Map &&
      activeQueues.isNotEmpty) {
    canonical['capsuleCollapseAllActive'] = true;
  }
}

Object? _canonicalSettingValue(String key, Object? value) {
  if (_syncOperationBooleanPreferenceKeys.contains(key)) {
    return _boolSettingValueOrNull(value) ?? _invalidSettingValue;
  }
  if (_syncOperationIntegerPreferenceKeys.contains(key)) {
    final intValue = _intSettingValueOrNull(value);
    if (intValue == null || intValue <= 0) {
      return _invalidSettingValue;
    }
    return switch (key) {
      'todoReminderIntervalValue' => _normalizePositiveIntRange(
          intValue,
          1,
          240,
        ),
      'todoReminderBubbleDurationSeconds' => _normalizePositiveIntRange(
          intValue,
          1,
          600,
        ),
      'maxTitleLength' => PaperTitles.normalizeMaxTitleLength(intValue),
      _ => intValue,
    };
  }
  if (_syncOperationDoublePreferenceKeys.contains(key)) {
    final doubleValue = _doubleSettingValueOrNull(value);
    if (doubleValue == null) {
      return _invalidSettingValue;
    }
    return switch (key) {
      'zoom' => _normalizeZoomSetting(doubleValue),
      'todoLineSpacing' || 'noteLineSpacing' => _normalizeLineSpacingSetting(
          doubleValue,
        ),
      'deepCapsuleStartTopMargin' => doubleValue.clamp(8, 10000).toDouble(),
      _ => doubleValue,
    };
  }
  if (_syncOperationStringPreferenceKeys.contains(key)) {
    return _canonicalStringSettingValue(key, value);
  }
  if (key == 'capsuleCollapseAllActiveQueues') {
    return _canonicalBooleanQueueMapSetting(value);
  }
  if (key == 'deepCapsuleQueueStartTopMargins') {
    return _canonicalDoubleQueueMapSetting(value);
  }
  return value;
}

Object? _canonicalStringSettingValue(String key, Object? value) {
  if (value is! String) {
    return _invalidSettingValue;
  }
  return switch (key) {
    'theme' => _canonicalThemeSettingValue(value),
    'colorScheme' => _canonicalEnumSettingValue(
        value,
        const {
          ColorSchemes.warm,
          ColorSchemes.ink,
          ColorSchemes.forest,
          ColorSchemes.rose,
        },
        ColorSchemes.normalize,
      ),
    'customThemeColorHex' => _canonicalColorHexSettingValue(value),
    'markdownRenderMode' => _canonicalEnumSettingValue(
        value,
        const {
          MarkdownRenderModes.off,
          MarkdownRenderModes.basic,
          MarkdownRenderModes.enhanced,
        },
        MarkdownRenderModes.normalize,
      ),
    'todoVisualSize' => _canonicalEnumSettingValue(
        value,
        const {
          TodoVisualSizes.small,
          TodoVisualSizes.medium,
          TodoVisualSizes.large,
          TodoVisualSizes.extraLarge,
        },
        TodoVisualSizes.normalize,
      ),
    'uiFontPreset' => _canonicalEnumSettingValue(
        value,
        const {
          UiFontPresets.defaultPreset,
          UiFontPresets.yaHei,
          UiFontPresets.dengXian,
          UiFontPresets.serif,
          UiFontPresets.mono,
          UiFontPresets.custom,
        },
        UiFontPresets.normalize,
      ),
    'systemFontFamilyName' => _normalizeSystemFontFamilyNameSetting(value),
    'externalMarkdownExtension' => _canonicalMarkdownExtensionSettingValue(
        value,
      ),
    'todoDueYearDisplayMode' => _canonicalEnumSettingValue(
        value,
        const {
          TodoDueYearDisplayModes.none,
          TodoDueYearDisplayModes.short,
          TodoDueYearDisplayModes.full,
        },
        TodoDueYearDisplayModes.normalize,
      ),
    'todoReminderIntervalUnit' => _canonicalEnumSettingValue(
        value,
        const {
          TodoReminderIntervalUnits.minutes,
          TodoReminderIntervalUnits.hours,
        },
        TodoReminderIntervalUnits.normalize,
      ),
    'todoReminderScope' => _canonicalEnumSettingValue(
        value,
        const {
          TodoReminderScopes.all,
          TodoReminderScopes.nearest,
        },
        TodoReminderScopes.normalize,
      ),
    'pinnedTodoHotKey' || 'pinnedNoteHotKey' => _normalizeHotKeySetting(value),
    'fullscreenTopmostMode' => _canonicalEnumSettingValue(
        value,
        const {
          FullscreenTopmostModes.avoid,
          FullscreenTopmostModes.stayOnTop,
        },
        FullscreenTopmostModes.normalize,
      ),
    'deepCapsuleSide' => _canonicalEnumSettingValue(
        value,
        const {
          DeepCapsuleSides.left,
          DeepCapsuleSides.right,
        },
        DeepCapsuleSides.normalize,
      ),
    'deepCapsuleMonitorDeviceName' =>
      _canonicalMonitorDeviceNameSettingValue(value),
    _ => value,
  };
}

Object _canonicalMonitorDeviceNameSettingValue(String value) {
  if (_hasControlCharacter(value)) {
    return _invalidSettingValue;
  }
  return value.trim();
}

Object _canonicalThemeSettingValue(String value) {
  final normalized = value.trim().toLowerCase();
  if (const {'light', 'dark', 'system'}.contains(normalized)) {
    return normalized;
  }
  return _invalidSettingValue;
}

Object _canonicalEnumSettingValue(
  String value,
  Set<String> allowedValues,
  String Function(String? value) normalize,
) {
  final normalizedInput = value.trim().toLowerCase();
  final allowedInputs = {
    for (final allowedValue in allowedValues) allowedValue.toLowerCase(),
  };
  if (!allowedInputs.contains(normalizedInput)) {
    return _invalidSettingValue;
  }
  return normalize(value);
}

Object _canonicalColorHexSettingValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final withoutPrefix =
      trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(withoutPrefix)) {
    return _invalidSettingValue;
  }
  return '#${withoutPrefix.toUpperCase()}';
}

Object _canonicalMarkdownExtensionSettingValue(String value) {
  var normalized = value.trim();
  if (normalized.isEmpty) {
    return '.md';
  }
  if (normalized.startsWith('*.')) {
    normalized = normalized.substring(1);
  }
  if (!normalized.startsWith('.')) {
    normalized = '.$normalized';
  }
  if (normalized.length < 2 ||
      normalized.length > 120 ||
      normalized.endsWith('.') ||
      normalized.endsWith(' ') ||
      _hasInvalidFileNameCharacter(normalized)) {
    return _invalidSettingValue;
  }
  return normalized.toLowerCase();
}

String _normalizeSystemFontFamilyNameSetting(String value) {
  final cleaned = StringBuffer();
  for (final rune in value.runes) {
    if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      continue;
    }
    cleaned.writeCharCode(rune);
  }
  final text = cleaned.toString().trim();
  return text.length > 128 ? text.substring(0, 128) : text;
}

String _normalizeHotKeySetting(String value) {
  final cleaned = StringBuffer();
  for (final unit in value.codeUnits) {
    if (unit <= 0x1F || (unit >= 0x7F && unit <= 0x9F)) {
      continue;
    }
    cleaned.writeCharCode(unit);
  }
  final text = cleaned.toString().trim();
  return text.length > 64 ? text.substring(0, 64) : text;
}

Object _canonicalBooleanQueueMapSetting(Object? value) {
  final source = _jsonMapOrNull(value);
  if (source == null) {
    return _invalidSettingValue;
  }
  if (source.isEmpty) {
    return <String, bool>{};
  }
  var sawValidEntry = false;
  final canonical = <String, bool>{};
  for (final entry in source.entries) {
    final queueKey = _canonicalQueueKeyOrNull(entry.key);
    final active = _boolSettingValueOrNull(entry.value);
    if (queueKey == null || active == null) {
      continue;
    }
    sawValidEntry = true;
    if (!canonical.containsKey(queueKey) || entry.key == queueKey) {
      canonical[queueKey] = active;
    }
  }
  for (final entry in [...canonical.entries]) {
    if (!entry.value) {
      canonical.remove(entry.key);
    }
  }
  return sawValidEntry ? canonical : _invalidSettingValue;
}

Object _canonicalDoubleQueueMapSetting(Object? value) {
  final source = _jsonMapOrNull(value);
  if (source == null) {
    return _invalidSettingValue;
  }
  if (source.isEmpty) {
    return <String, double>{};
  }
  var sawValidEntry = false;
  final canonical = <String, double>{};
  for (final entry in source.entries) {
    final queueKey = _canonicalQueueKeyOrNull(entry.key);
    final margin = _doubleSettingValueOrNull(entry.value);
    if (queueKey == null || margin == null) {
      continue;
    }
    sawValidEntry = true;
    if (!canonical.containsKey(queueKey) || entry.key == queueKey) {
      canonical[queueKey] = margin.clamp(8, 10000).toDouble();
    }
  }
  return sawValidEntry ? canonical : _invalidSettingValue;
}

String? _canonicalQueueKeyOrNull(String key) {
  final value = key.trim();
  if (_hasControlCharacter(value)) {
    return null;
  }
  final separator = value.lastIndexOf('|');
  if (separator < 0) {
    final side = _canonicalDeepCapsuleSideOrNull(value);
    return side == null ? null : '|$side';
  }
  final monitor = value.substring(0, separator).trim();
  final side = _canonicalDeepCapsuleSideOrNull(
    value.substring(separator + 1),
  );
  return side == null ? null : '$monitor|$side';
}

String? _canonicalDeepCapsuleSideOrNull(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    DeepCapsuleSides.left => DeepCapsuleSides.left,
    DeepCapsuleSides.right => DeepCapsuleSides.right,
    _ => null,
  };
}

bool? _boolSettingValueOrNull(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return switch (value.trim().toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }
  return null;
}

int? _intSettingValueOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    return RegExp(r'^\d+$').hasMatch(value) ? int.tryParse(value) : null;
  }
  return null;
}

double? _doubleSettingValueOrNull(Object? value) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  if (value is String) {
    if (!_unsignedDecimalSettingStringPattern.hasMatch(value)) {
      return null;
    }
    final parsed = double.tryParse(value);
    if (parsed != null && parsed.isFinite) {
      return parsed;
    }
  }
  return null;
}

final _unsignedDecimalSettingStringPattern = RegExp(r'^(?:\d+|\d+\.\d+)$');

int _normalizePositiveIntRange(int value, int min, int max) {
  return value.clamp(min, max).toInt();
}

Object _normalizeZoomSetting(double value) {
  if (value <= 0) {
    return _invalidSettingValue;
  }
  return value.clamp(0.5, 1.5).toDouble();
}

Object _normalizeLineSpacingSetting(double value) {
  if (value <= 0) {
    return _invalidSettingValue;
  }
  final rounded = (value * 100).roundToDouble() / 100;
  return rounded.clamp(0.8, 5.0).toDouble();
}

JsonMap? _jsonMapOrNull(Object? value) {
  return jsonMapOrNull(value);
}

Object? _payloadValue(JsonMap payload, String key) {
  if (payload.containsKey(key)) {
    return payload[key];
  }
  final normalizedKey = key.toLowerCase();
  for (final entry in payload.entries) {
    if (entry.key.toLowerCase() == normalizedKey) {
      return entry.value;
    }
  }
  return null;
}

bool _payloadContainsKey(JsonMap payload, String key) {
  if (payload.containsKey(key)) {
    return true;
  }
  final normalizedKey = key.toLowerCase();
  for (final entry in payload.entries) {
    if (entry.key.toLowerCase() == normalizedKey) {
      return true;
    }
  }
  return false;
}

String _payloadStringId(JsonMap payload, String key) {
  final rawValue = stringValue(_payloadValue(payload, key), '');
  if (_hasControlCharacter(rawValue)) {
    return '';
  }
  final value = rawValue.trim();
  if (value.isEmpty) {
    return '';
  }
  return value;
}

bool _isSafeSnapshotPathPayload(Object? value) {
  return _canonicalSnapshotPathPayload(value) != null;
}

String? _canonicalSnapshotPathPayload(Object? value) {
  if (value is! String || value.isEmpty || value != value.trim()) {
    return null;
  }
  if (value.contains('\\')) {
    return null;
  }
  late final String decoded;
  try {
    decoded = Uri.decodeComponent(value);
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
  if (decoded.startsWith('/') || (Uri.tryParse(decoded)?.hasScheme ?? false)) {
    return null;
  }
  final segments = <String>[];
  final rawSegments = value.split('/');
  for (var index = 0; index < rawSegments.length; index += 1) {
    final rawSegment = rawSegments[index];
    if (rawSegment.isEmpty) {
      return null;
    }
    late final String segment;
    try {
      segment = Uri.decodeComponent(rawSegment);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    if (_hasControlCharacter(segment) ||
        segment.contains('/') ||
        segment.contains('\\')) {
      return null;
    }
    final trimmed = segment.trim();
    if (segment != trimmed ||
        (rawSegment.isNotEmpty && trimmed.isEmpty) ||
        trimmed == '.' ||
        trimmed == '..') {
      return null;
    }
    segments.add(segment);
  }
  return segments.isEmpty ? null : segments.join('/');
}

bool _hasControlCharacter(String value) {
  return value.runes
      .any((rune) => rune < 0x20 || (rune >= 0x7F && rune <= 0x9F));
}

bool _hasSafePaperPayloadIds(JsonMap paper) {
  if (_payloadStringId(paper, 'id').isEmpty) {
    return false;
  }
  final items = _jsonMapListPayloadOrNull(paper, 'items');
  if (items == null) {
    return false;
  }
  final itemIds = <String>{};
  for (final item in items) {
    if (!_hasSafeTodoItemPayloadShape(item)) {
      return false;
    }
    if (!_hasSafeTodoItemPayloadIds(item)) {
      return false;
    }
    if (!itemIds.add(_payloadStringId(item, 'id'))) {
      return false;
    }
  }
  final elements = _jsonMapListPayloadOrNull(paper, 'noteCanvasElements');
  if (elements == null) {
    return false;
  }
  final elementIds = <String>{};
  for (final element in elements) {
    if (!_hasSafeNoteCanvasElementPayloadShape(element)) {
      return false;
    }
    final elementId = _payloadStringId(element, 'id');
    if (elementId.isEmpty || !elementIds.add(elementId)) {
      return false;
    }
  }
  return true;
}

bool _hasSafePaperPayloadShape(JsonMap paper) {
  if (!_hasSafePaperTopLevelPayloadShape(paper)) {
    return false;
  }
  final items = _jsonMapListPayloadOrNull(paper, 'items');
  final elements = _jsonMapListPayloadOrNull(paper, 'noteCanvasElements');
  if (items == null || elements == null) {
    return false;
  }
  final normalizedType =
      (_payloadValue(paper, 'type') as String).trim().toLowerCase();
  if (normalizedType == PaperTypes.todo && elements.isNotEmpty) {
    return false;
  }
  if (normalizedType == PaperTypes.note && items.isNotEmpty) {
    return false;
  }
  return true;
}

bool _hasSafePaperTopLevelPayloadShape(JsonMap paper) {
  final type = _payloadValue(paper, 'type');
  if (!_payloadContainsKey(paper, 'type') || type is! String) {
    return false;
  }
  final normalizedType = type.trim().toLowerCase();
  if (normalizedType != PaperTypes.todo && normalizedType != PaperTypes.note) {
    return false;
  }
  if (!_payloadPaperTitleFieldIsSafe(paper, 'title')) {
    return false;
  }
  if (!_payloadMarkdownTextFieldIsSafe(paper, 'content')) {
    return false;
  }
  if (normalizedType == PaperTypes.todo) {
    final content = _payloadValue(paper, 'content');
    if (content is String && content.isNotEmpty) {
      return false;
    }
  }
  if (!_payloadPaperCapsuleSideFieldIsSafe(paper, 'capsuleSide')) {
    return false;
  }
  if (!_payloadMonitorNameFieldIsSafe(paper, 'capsuleMonitorDeviceName')) {
    return false;
  }
  for (final key in const ['x', 'y']) {
    final value = _payloadValue(paper, key);
    if (_payloadContainsKey(paper, key) && (value is! num || !value.isFinite)) {
      return false;
    }
  }
  if (!_payloadPaperDimensionFieldIsSafe(
    paper,
    'width',
    PaperLayoutDefaults.minWidth,
  )) {
    return false;
  }
  if (!_payloadPaperDimensionFieldIsSafe(
    paper,
    'height',
    PaperLayoutDefaults.minHeight,
  )) {
    return false;
  }
  if (!_payloadPositiveNumberFieldIsSafe(paper, 'textZoom')) {
    return false;
  }
  for (final key in const [
    'isVisible',
    'alwaysOnTop',
    'isCollapsed',
    'isPinnedToDesktop',
  ]) {
    if (_payloadContainsKey(paper, key) && _payloadValue(paper, key) is! bool) {
      return false;
    }
  }
  return true;
}

bool _payloadPaperTitleFieldIsSafe(JsonMap payload, String key) {
  if (!_payloadContainsKey(payload, key)) {
    return true;
  }
  final value = _payloadValue(payload, key);
  if (value is! String) {
    return false;
  }
  return value ==
      PaperTitles.cleanCustomTitle(
        value,
        maxLength: PaperTitles.maxTitleLength,
      );
}

bool _payloadPaperCapsuleSideFieldIsSafe(JsonMap payload, String key) {
  if (!_payloadContainsKey(payload, key)) {
    return true;
  }
  final value = _payloadValue(payload, key);
  if (value is! String || _hasControlCharacter(value)) {
    return false;
  }
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == DeepCapsuleSides.left ||
      normalized == DeepCapsuleSides.right;
}

bool _payloadMonitorNameFieldIsSafe(JsonMap payload, String key) {
  if (!_payloadContainsKey(payload, key)) {
    return true;
  }
  final value = _payloadValue(payload, key);
  return value is String && !_hasControlCharacter(value);
}

bool _payloadPaperDimensionFieldIsSafe(
  JsonMap payload,
  String key,
  double minimumValue,
) {
  if (!_payloadContainsKey(payload, key)) {
    return true;
  }
  final value = _payloadValue(payload, key);
  return value is num && value.isFinite && value >= minimumValue;
}

bool _payloadPositiveNumberFieldIsSafe(JsonMap payload, String key) {
  if (!_payloadContainsKey(payload, key)) {
    return true;
  }
  final value = _payloadValue(payload, key);
  return value is num && value.isFinite && value > 0;
}

List<JsonMap>? _jsonMapListPayloadOrNull(JsonMap payload, String key) {
  if (!_payloadContainsKey(payload, key)) {
    return const <JsonMap>[];
  }
  final value = _payloadValue(payload, key);
  if (value is! List) {
    return null;
  }
  final values = <JsonMap>[];
  for (final item in value) {
    final map = _jsonMapOrNull(item);
    if (map == null) {
      return null;
    }
    values.add(map);
  }
  return values;
}

bool _hasSafeTodoItemPayloadIds(JsonMap item) {
  return _payloadStringId(item, 'id').isNotEmpty &&
      _optionalPayloadIdIsSafe(item, 'linkedNoteId');
}

bool _hasSafeTodoItemPayloadShape(JsonMap item) {
  if (!_payloadTodoTextFieldIsSafe(item, 'text')) {
    return false;
  }
  if (!_payloadStringFieldIsSafe(item, 'linkedNoteId')) {
    return false;
  }
  for (final key in const [
    'order',
  ]) {
    if (!_payloadIntFieldIsSafe(item, key)) {
      return false;
    }
  }
  if (!_payloadPositiveIntFieldIsSafe(item, 'todoColumnCount')) {
    return false;
  }
  if (!_payloadBoolFieldIsSafe(item, 'done')) {
    return false;
  }
  if (!_payloadTodoDueAtLocalFieldIsSafe(item, 'dueAtLocal')) {
    return false;
  }
  if (!_payloadTodoReminderFieldsAreSafe(item)) {
    return false;
  }
  return _payloadTodoColumnListsAreSafe(item);
}

bool _payloadTodoColumnListsAreSafe(JsonMap item) {
  final hasColumnCount = _payloadContainsKey(item, 'todoColumnCount');
  final columnCount = _payloadValue(item, 'todoColumnCount');
  final hasExtraColumns = _payloadContainsKey(item, 'todoExtraColumns');
  final hasColumnWidths = _payloadContainsKey(item, 'todoColumnWidths');

  final extraColumns = _payloadValue(item, 'todoExtraColumns');
  if (hasExtraColumns) {
    if (extraColumns is! List ||
        extraColumns.any((value) =>
            value is! String || value.length > TodoPasteItems.maxLineLength)) {
      return false;
    }
  }
  final columnWidths = _payloadValue(item, 'todoColumnWidths');
  if (hasColumnWidths) {
    if (columnWidths is! List ||
        columnWidths
            .any((value) => value is! num || !value.isFinite || value < 0)) {
      return false;
    }
  }

  if (!hasExtraColumns && !hasColumnWidths) {
    return true;
  }
  if (!hasColumnCount || columnCount is! int || columnCount <= 0) {
    return false;
  }
  if (extraColumns is List && extraColumns.length > columnCount - 1) {
    return false;
  }
  if (columnWidths is List && columnWidths.length > columnCount) {
    return false;
  }
  return true;
}

bool _payloadTodoDueAtLocalFieldIsSafe(JsonMap payload, String key) {
  if (!_payloadContainsKey(payload, key)) {
    return true;
  }
  final value = _payloadValue(payload, key);
  if (value is! String || value.trim().isEmpty) {
    return false;
  }
  if (_hasControlCharacter(value)) {
    return false;
  }
  return parsePaperTodoDueAtLocal(value) != null;
}

bool _payloadTodoReminderFieldsAreSafe(JsonMap item) {
  final hasValue = _payloadContainsKey(item, 'reminderIntervalValue');
  final hasUnit = _payloadContainsKey(item, 'reminderIntervalUnit');
  if (hasValue) {
    final value = _payloadValue(item, 'reminderIntervalValue');
    if (value is! int || value <= 0) {
      return false;
    }
  }
  if (!hasUnit) {
    return true;
  }
  if (!hasValue) {
    return false;
  }
  final unit = _payloadValue(item, 'reminderIntervalUnit');
  if (unit is! String || unit.isEmpty || unit != unit.trim()) {
    return false;
  }
  if (_hasControlCharacter(unit)) {
    return false;
  }
  final normalizedUnit = unit.toLowerCase();
  return normalizedUnit == TodoReminderIntervalUnits.minutes ||
      normalizedUnit == TodoReminderIntervalUnits.hours;
}

bool _payloadStringFieldIsSafe(JsonMap payload, String key) {
  return !_payloadContainsKey(payload, key) ||
      _payloadValue(payload, key) is String;
}

bool _payloadMarkdownTextFieldIsSafe(JsonMap payload, String key) {
  if (!_payloadContainsKey(payload, key)) {
    return true;
  }
  final value = _payloadValue(payload, key);
  return value is String &&
      value.length <= SyncTextLimits.maxMarkdownTextLength;
}

bool _payloadTodoTextFieldIsSafe(JsonMap payload, String key) {
  if (!_payloadContainsKey(payload, key)) {
    return true;
  }
  final value = _payloadValue(payload, key);
  return value is String && value.length <= TodoPasteItems.maxLineLength;
}

bool _payloadIntFieldIsSafe(JsonMap payload, String key) {
  return !_payloadContainsKey(payload, key) ||
      _payloadValue(payload, key) is int;
}

bool _payloadPositiveIntFieldIsSafe(JsonMap payload, String key) {
  if (!_payloadContainsKey(payload, key)) {
    return true;
  }
  final value = _payloadValue(payload, key);
  return value is int && value > 0;
}

bool _payloadBoolFieldIsSafe(JsonMap payload, String key) {
  return !_payloadContainsKey(payload, key) ||
      _payloadValue(payload, key) is bool;
}

bool _hasSafeNoteCanvasElementPayloadShape(JsonMap element) {
  if (!_payloadNoteCanvasElementTypeFieldIsSafe(element, 'type')) {
    return false;
  }
  if (!_payloadMarkdownTextFieldIsSafe(element, 'text')) {
    return false;
  }
  for (final key in const ['x', 'y']) {
    if (!_payloadNumberFieldInRangeIsSafe(
      element,
      key,
      NoteCanvasElementLimits.minCoordinate,
      NoteCanvasElementLimits.maxCoordinate,
    )) {
      return false;
    }
  }
  if (!_payloadNumberFieldInRangeIsSafe(
    element,
    'width',
    NoteCanvasElementLimits.minWidth,
    NoteCanvasElementLimits.maxWidth,
  )) {
    return false;
  }
  if (!_payloadNumberFieldInRangeIsSafe(
    element,
    'height',
    NoteCanvasElementLimits.minHeight,
    NoteCanvasElementLimits.maxHeight,
  )) {
    return false;
  }
  if (_payloadContainsKey(element, 'zIndex')) {
    final zIndex = _payloadValue(element, 'zIndex');
    if (zIndex is! int || zIndex < 0) {
      return false;
    }
  }
  return true;
}

bool _payloadNoteCanvasElementTypeFieldIsSafe(JsonMap payload, String key) {
  if (!_payloadContainsKey(payload, key)) {
    return true;
  }
  final value = _payloadValue(payload, key);
  if (value is! String || value.isEmpty || value != value.trim()) {
    return false;
  }
  if (_hasControlCharacter(value)) {
    return false;
  }
  return _supportedNoteCanvasElementTypePayloadValues.contains(
    value.toLowerCase(),
  );
}

const _supportedNoteCanvasElementTypePayloadValues = {
  NoteCanvasElementTypes.code,
  'text',
  'sticky',
};

bool _payloadNumberFieldInRangeIsSafe(
  JsonMap payload,
  String key,
  double min,
  double max,
) {
  if (!_payloadContainsKey(payload, key)) {
    return true;
  }
  final value = _payloadValue(payload, key);
  return value is num && value.isFinite && value >= min && value <= max;
}

bool _optionalPayloadIdIsSafe(JsonMap payload, String key) {
  final value = _payloadValue(payload, key);
  if (value == null || value is! String) {
    return true;
  }
  if (_hasControlCharacter(value)) {
    return false;
  }
  return value.trim().isNotEmpty;
}

bool _hasInvalidFileNameCharacter(String value) {
  const invalid = {'<', '>', ':', '"', '/', '\\', '|', '?', '*'};
  return value.runes.any((rune) {
    if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      return true;
    }
    return invalid.contains(String.fromCharCode(rune));
  });
}

JsonMap _migratePaperPayload(JsonMap paperJson) {
  final migrated = migrateLegacyPaperTodoJson({
    'papers': [paperJson],
  });
  final papers = jsonMapList(migrated['papers']);
  return papers.isEmpty ? paperJson : papers.first;
}

JsonMap _migrateTodoItemPayload(JsonMap itemJson) {
  final migrated = migrateLegacyPaperTodoJson({
    'papers': [
      {
        'items': [itemJson],
      },
    ],
  });
  final papers = jsonMapList(migrated['papers']);
  if (papers.isEmpty) {
    return itemJson;
  }
  final items = jsonMapList(papers.first['items']);
  return items.isEmpty ? itemJson : items.first;
}

bool _hasApplicableSettingsPayload(JsonMap settings) {
  return canonicalSyncOperationSettingsPayload(settings).isNotEmpty;
}

bool _hasLocalOnlyCapsuleSettingsPayload(JsonMap settings) {
  return settings.isNotEmpty &&
      settings.keys.every(
        (key) => _localOnlyCapsuleSettingKeyNames.contains(
          key.trim().toLowerCase(),
        ),
      );
}

JsonMap _canonicalPaperPayload(JsonMap paperJson) {
  final paper = _migratePaperPayload(paperJson);
  if (_canNormalizePaperPayloadDeterministically(paper)) {
    return _withoutLocalCapsulePaperState(PaperData.fromJson(paper).toJson());
  }
  final canonical = Map<String, Object?>.from(paper);
  canonical['id'] = _payloadStringId(canonical, 'id');
  canonical['items'] = [
    for (final item in jsonMapList(canonical['items']))
      _canonicalTodoItemPayload(item),
  ];
  canonical['noteCanvasElements'] = [
    for (final element in jsonMapList(canonical['noteCanvasElements']))
      _canonicalIdPayload(element),
  ];
  return _withoutLocalCapsulePaperState(canonical);
}

JsonMap _withoutLocalCapsulePaperState(JsonMap paper) {
  return Map<String, Object?>.from(paper)
    ..remove('isCollapsed')
    ..remove('capsuleSide')
    ..remove('capsuleMonitorDeviceName');
}

JsonMap _canonicalTodoItemPayload(JsonMap itemJson) {
  final item = _migrateTodoItemPayload(itemJson);
  if (_payloadStringId(item, 'id').isNotEmpty) {
    return PaperItem.fromJson(item).toJson();
  }
  return _canonicalIdPayload(item);
}

JsonMap _canonicalIdPayload(JsonMap source) {
  final canonical = Map<String, Object?>.from(source);
  final id = _payloadStringId(canonical, 'id');
  if (id.isNotEmpty) {
    canonical['id'] = id;
  }
  return canonical;
}

bool _canNormalizePaperPayloadDeterministically(JsonMap paper) {
  if (_payloadStringId(paper, 'id').isEmpty) {
    return false;
  }
  return _hasStableUniqueIds(jsonMapList(paper['items'])) &&
      _hasStableUniqueIds(jsonMapList(paper['noteCanvasElements']));
}

bool _hasStableUniqueIds(List<JsonMap> values) {
  final ids = <String>{};
  for (final value in values) {
    final id = _payloadStringId(value, 'id');
    if (id.isEmpty || !ids.add(id)) {
      return false;
    }
  }
  return true;
}

const _syncOperationAppPreferenceKeys = {
  'theme',
  'colorScheme',
  'customThemeColorHex',
  'markdownRenderMode',
  'todoVisualSize',
  'uiFontPreset',
  'systemFontFamilyName',
  'externalMarkdownExtension',
  'zoom',
  'showTopBarNewTodoButton',
  'showTopBarNewNoteButton',
  'showTopBarNewPaperButtons',
  'showTopBarExternalOpenButton',
  'hidePapersFromWindowSwitcher',
  'enableTodoNoteLinks',
  'showTodoDueRelativeTime',
  'todoDueYearDisplayMode',
  'todoLineSpacing',
  'noteLineSpacing',
  'useTodoReminderInterval',
  'todoReminderIntervalValue',
  'todoReminderIntervalUnit',
  'todoReminderScope',
  'todoReminderBubbleDurationSeconds',
  'showLinkedNoteName',
  'allowLongLinkedNoteTitles',
  'hideLinkedNotesFromCapsules',
  'runLinkedScriptCapsulesOnClick',
  'maxTitleLength',
  'enableAnimations',
  'enableToolTips',
  'pinnedTodoHotKey',
  'pinnedNoteHotKey',
  'fullscreenTopmostMode',
  'usePersistentPowerShellProcess',
  'preferPowerShell7',
  'hideScriptRunWindow',
};

const _localOnlyCapsuleSettingKeys = {
  'useCapsuleMode',
  'useDeepCapsuleMode',
  'useCapsuleCollapseAll',
  'capsuleCollapseAllActive',
  'capsuleCollapseAllActiveQueues',
  'showDeepCapsuleWhileExpanded',
  'collapseExpandedDeepCapsuleOnClick',
  'hideDeepCapsulesWhenCovered',
  'hideDeepCapsulesWhenFullscreen',
  'deepCapsuleStartTopMargin',
  'deepCapsuleQueueStartTopMargins',
  'deepCapsuleSide',
  'deepCapsuleMonitorDeviceName',
};

final _localOnlyCapsuleSettingKeyNames = {
  for (final key in _localOnlyCapsuleSettingKeys) key.toLowerCase(),
};

final _invalidSettingValue = Object();

const _syncOperationBooleanPreferenceKeys = {
  'showTopBarNewTodoButton',
  'showTopBarNewNoteButton',
  'showTopBarExternalOpenButton',
  'hidePapersFromWindowSwitcher',
  'enableTodoNoteLinks',
  'showTodoDueRelativeTime',
  'useTodoReminderInterval',
  'showLinkedNoteName',
  'allowLongLinkedNoteTitles',
  'hideLinkedNotesFromCapsules',
  'runLinkedScriptCapsulesOnClick',
  'enableAnimations',
  'enableToolTips',
  'usePersistentPowerShellProcess',
  'preferPowerShell7',
  'hideScriptRunWindow',
};

const _syncOperationIntegerPreferenceKeys = {
  'todoReminderIntervalValue',
  'todoReminderBubbleDurationSeconds',
  'maxTitleLength',
};

const _syncOperationDoublePreferenceKeys = {
  'zoom',
  'todoLineSpacing',
  'noteLineSpacing',
  'deepCapsuleStartTopMargin',
};

const _syncOperationStringPreferenceKeys = {
  'theme',
  'colorScheme',
  'customThemeColorHex',
  'markdownRenderMode',
  'todoVisualSize',
  'uiFontPreset',
  'systemFontFamilyName',
  'externalMarkdownExtension',
  'todoDueYearDisplayMode',
  'todoReminderIntervalUnit',
  'todoReminderScope',
  'pinnedTodoHotKey',
  'pinnedNoteHotKey',
  'fullscreenTopmostMode',
  'deepCapsuleSide',
  'deepCapsuleMonitorDeviceName',
};
