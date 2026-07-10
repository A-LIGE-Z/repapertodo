String? normalizeExternalUriTarget(
  String value, {
  bool allowBareWww = false,
}) {
  var trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (hasRawExternalUriControlCharacter(value)) {
    return null;
  }
  if (allowBareWww && trimmed.toLowerCase().startsWith('www.')) {
    trimmed = 'https://$trimmed';
  }
  if (hasUnsafeExternalUriCharacter(trimmed) ||
      hasMalformedExternalUriPercentEscape(trimmed) ||
      hasEncodedUnsafeExternalUriCharacter(trimmed) ||
      !isAllowedExternalUriTarget(trimmed)) {
    return null;
  }
  return trimmed;
}

bool isAllowedExternalUriTarget(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) {
    return false;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') {
    return uri.host.trim().isNotEmpty &&
        uri.userInfo.isEmpty &&
        !hasEncodedExternalUriAuthoritySeparator(value);
  }
  if (scheme == 'mailto') {
    return uri.authority.isEmpty && uri.path.trim().isNotEmpty;
  }
  return false;
}

bool hasEncodedExternalUriAuthoritySeparator(String value) {
  final uri = Uri.tryParse(value);
  final scheme = uri?.scheme.toLowerCase();
  if (uri == null || (scheme != 'http' && scheme != 'https')) {
    return false;
  }
  final authority = uri.authority.toLowerCase();
  for (final encodedSeparator in const [
    '%23',
    '%2f',
    '%3a',
    '%3f',
    '%40',
    '%5b',
    '%5c',
    '%5d',
  ]) {
    if (authority.contains(encodedSeparator)) {
      return true;
    }
  }
  return false;
}

bool hasMalformedExternalUriPercentEscape(String value) {
  for (var index = 0; index < value.length; index += 1) {
    if (value.codeUnitAt(index) != 0x25) {
      continue;
    }
    if (index + 2 >= value.length ||
        !_isHexDigit(value.codeUnitAt(index + 1)) ||
        !_isHexDigit(value.codeUnitAt(index + 2))) {
      return true;
    }
    index += 2;
  }
  return false;
}

bool hasUnsafeExternalUriCharacter(String value) {
  return value.runes.any(
    (rune) => rune <= 0x20 || (rune >= 0x7F && rune <= 0x9F),
  );
}

bool hasRawExternalUriControlCharacter(String value) {
  return value.runes.any(_isControlRune);
}

bool hasEncodedUnsafeExternalUriCharacter(String value) {
  try {
    return Uri.decodeFull(value).runes.any(_isControlRune);
  } on FormatException {
    // Malformed escapes should still reject obvious percent-encoded controls.
  }
  for (final match in RegExp(r'%([0-9a-fA-F]{2})').allMatches(value)) {
    final unit = int.parse(match.group(1)!, radix: 16);
    if (unit < 0x20 || (unit >= 0x7F && unit <= 0x9F)) {
      return true;
    }
  }
  return false;
}

bool _isControlRune(int rune) {
  return rune < 0x20 || (rune >= 0x7F && rune <= 0x9F);
}

bool _isHexDigit(int codeUnit) {
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x46) ||
      (codeUnit >= 0x61 && codeUnit <= 0x66);
}
