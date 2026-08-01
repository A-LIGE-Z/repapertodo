import 'package:collection/collection.dart';
import '../core/model/json_helpers.dart';

/// Field-level 3-way conflict merging engine for RePaperTodo.
///
/// Merges concurrent modifications from local and remote devices against a shared
/// base state, avoiding whole-object last-writer-wins overwrites.
class FieldLevelConflictMerger {
  const FieldLevelConflictMerger();

  /// Performs a field-level 3-way merge on two JSON object representations of a paper
  /// or todo item.
  JsonMap mergeFields({
    required JsonMap base,
    required JsonMap local,
    required JsonMap remote,
  }) {
    final merged = JsonMap.from(base);

    final allKeys = <String>{
      ...base.keys,
      ...local.keys,
      ...remote.keys,
    };

    for (final key in allKeys) {
      final baseVal = base[key];
      final localVal = local[key];
      final remoteVal = remote[key];

      final localChanged = !_isEqual(baseVal, localVal);
      final remoteChanged = !_isEqual(baseVal, remoteVal);

      if (localChanged && !remoteChanged) {
        // Only local modified this field -> preserve local
        if (localVal != null) {
          merged[key] = localVal;
        } else {
          merged.remove(key);
        }
      } else if (!localChanged && remoteChanged) {
        // Only remote modified this field -> accept remote
        if (remoteVal != null) {
          merged[key] = remoteVal;
        } else {
          merged.remove(key);
        }
      } else if (localChanged && remoteChanged) {
        if (_isEqual(localVal, remoteVal)) {
          // Both made identical changes -> apply change
          if (localVal != null) {
            merged[key] = localVal;
          } else {
            merged.remove(key);
          }
        } else {
          // Conflicting edits on the same field -> resolve deterministically
          merged[key] = _resolveFieldConflict(key, baseVal, localVal, remoteVal);
        }
      }
    }

    return merged;
  }

  dynamic _resolveFieldConflict(
    String key,
    dynamic baseVal,
    dynamic localVal,
    dynamic remoteVal,
  ) {
    // For lists or arrays (e.g. todo items), merge union preserving order
    if (localVal is List && remoteVal is List) {
      final mergedList = List<dynamic>.from(localVal);
      
      // If they are lists of maps with 'id' fields (like todo items), we can merge them more intelligently
      final isObjectList = localVal.isNotEmpty && localVal.first is Map && (localVal.first as Map).containsKey('id') ||
                           remoteVal.isNotEmpty && remoteVal.first is Map && (remoteVal.first as Map).containsKey('id');
                           
      if (isObjectList) {
        final baseList = baseVal is List ? baseVal : [];
        final newMergedList = <dynamic>[];
        
        for (final remoteItem in remoteVal) {
          if (remoteItem is! Map || !remoteItem.containsKey('id')) {
             if (!newMergedList.any((e) => _isEqual(e, remoteItem))) newMergedList.add(remoteItem);
             continue;
          }
          final id = remoteItem['id'];
          final localIndex = localVal.indexWhere((e) => e is Map && e['id'] == id);
          
          if (localIndex >= 0) {
            final localItem = localVal[localIndex];
            final baseItem = baseList.firstWhere((e) => e is Map && e['id'] == id, orElse: () => <String, dynamic>{});
            if (localItem is Map && baseItem is Map) {
              newMergedList.add(mergeFields(
                base: Map<String, dynamic>.from(baseItem),
                local: Map<String, dynamic>.from(localItem),
                remote: Map<String, dynamic>.from(remoteItem),
              ));
            } else {
              newMergedList.add(remoteItem);
            }
          } else {
            final existedInBase = baseList.any((e) => e is Map && e['id'] == id);
            if (!existedInBase) {
              newMergedList.add(remoteItem);
            }
          }
        }
        
        for (final localItem in localVal) {
          if (localItem is! Map || !localItem.containsKey('id')) continue;
          final id = localItem['id'];
          if (!newMergedList.any((e) => e is Map && e['id'] == id)) {
             final existedInRemote = remoteVal.any((e) => e is Map && e['id'] == id);
             if (!existedInRemote) {
                final existedInBase = baseList.any((e) => e is Map && e['id'] == id);
                if (!existedInBase) {
                   newMergedList.add(localItem);
                } else {
                   final baseItem = baseList.firstWhere((e) => e is Map && e['id'] == id, orElse: () => <String, dynamic>{});
                   if (baseItem is Map && !_isEqual(baseItem, localItem)) {
                      newMergedList.add(localItem);
                   }
                }
             }
          }
        }
        return newMergedList;
      } else {
        for (final item in remoteVal) {
          if (!mergedList.any((e) => _isEqual(e, item))) {
            mergedList.add(item);
          }
        }
      }
      return mergedList;
    }

    // For string fields (e.g. title/content), concatenate if distinct or choose non-empty
    if (localVal is String && remoteVal is String) {
      if (localVal.isEmpty) return remoteVal;
      if (remoteVal.isEmpty) return localVal;
      return '$localVal / $remoteVal';
    }

    // Fallback to local value
    return localVal ?? remoteVal;
  }

  bool _isEqual(dynamic a, dynamic b) {
    return const DeepCollectionEquality().equals(a, b);
  }
}
