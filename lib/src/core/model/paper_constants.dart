abstract final class PaperTypes {
  static const todo = 'todo';
  static const note = 'note';

  static String normalize(String? value) {
    return _normalizedValue(value) == note ? note : todo;
  }
}

abstract final class MarkdownRenderModes {
  static const off = 'off';
  static const basic = 'basic';
  static const enhanced = 'enhanced';

  static String normalize(String? value) {
    return switch (_normalizedValue(value)) {
      off => off,
      basic => basic,
      enhanced => enhanced,
      _ => enhanced,
    };
  }
}

abstract final class TodoVisualSizes {
  static const small = 'small';
  static const medium = 'medium';
  static const large = 'large';
  static const extraLarge = 'extraLarge';

  static String normalize(String? value) {
    return switch (_normalizedValue(value)) {
      small => small,
      large => large,
      'extralarge' => extraLarge,
      _ => medium,
    };
  }
}

abstract final class TodoColumnLimits {
  static const minCount = 1;
  static const maxCount = 4;
  static const minWidth = 0.2;
  static const maxWidth = 10000.0;
}

abstract final class UiFontPresets {
  static const defaultPreset = 'default';
  static const yaHei = 'yahei';
  static const dengXian = 'dengxian';
  static const serif = 'serif';
  static const mono = 'mono';
  static const custom = 'custom';

  static String normalize(String? value) {
    return switch (_normalizedValue(value)) {
      yaHei => yaHei,
      dengXian => dengXian,
      serif => serif,
      mono => mono,
      custom => custom,
      _ => defaultPreset,
    };
  }
}

abstract final class ColorSchemes {
  static const warm = 'warm';
  static const ink = 'ink';
  static const forest = 'forest';
  static const rose = 'rose';

  static String normalize(String? value) {
    return switch (_normalizedValue(value)) {
      warm => warm,
      ink => ink,
      forest => forest,
      rose => rose,
      _ => warm,
    };
  }
}

abstract final class DeepCapsuleSides {
  static const left = 'left';
  static const right = 'right';

  static String normalize(String? value) {
    return _normalizedValue(value) == left ? left : right;
  }
}

abstract final class FullscreenTopmostModes {
  static const avoid = 'avoid';
  static const stayOnTop = 'stayOnTop';

  static String normalize(String? value) {
    return _normalizedValue(value) == 'stayontop' ? stayOnTop : avoid;
  }
}

abstract final class TodoReminderIntervalUnits {
  static const minutes = 'minutes';
  static const hours = 'hours';

  static String normalize(String? value) {
    return _normalizedValue(value) == hours ? hours : minutes;
  }
}

abstract final class TodoReminderScopes {
  static const nearest = 'nearest';
  static const all = 'all';

  static String normalize(String? value) {
    return _normalizedValue(value) == nearest ? nearest : all;
  }
}

abstract final class TodoDueYearDisplayModes {
  static const none = 'none';
  static const short = 'short';
  static const full = 'full';

  static String normalize(String? value) {
    return switch (_normalizedValue(value)) {
      short => short,
      full => full,
      _ => none,
    };
  }
}

abstract final class NoteCanvasElementTypes {
  static const code = 'code';
  static const text = 'text';

  static String normalize(String? value) {
    return _normalizedValue(value) == text ? text : code;
  }
}

String _normalizedValue(String? value) {
  return value?.trim().toLowerCase() ?? '';
}

abstract final class PaperLayoutDefaults {
  static const minWidth = 220.0;
  static const minHeight = 160.0;
  static const capsuleWidth = 92.0;
  static const capsuleHeight = 46.0;
  static const deepCapsuleExpandedEdgeInset = 36.0;
  static const deepCapsuleEdgeMargin = 8.0;
  static const deepCapsuleTopMargin = 8.0;
  static const deepCapsuleStartTopMargin = 48.0;
  static const deepCapsuleGap = 4.0;
  static const newPaperBaseLeft = 140.0;
  static const newPaperBaseTop = 140.0;
  static const newPaperCascadeOffset = 24.0;
  static const newPaperSourceOffset = 30.0;
  static const newPaperCollisionNudge = 30.0;
  static const newPaperCollisionThreshold = 5.0;
  static const newPaperWorkAreaMargin = 8.0;
  static const newPaperWorkAreaResizeInset = 80.0;
  static const todoDefaultWidth = 280.0;
  static const todoDefaultHeight = 340.0;
  static const noteDefaultWidth = 320.0;
  static const noteDefaultHeight = 360.0;
}

abstract final class PaperLimits {
  static const maxPapers = 100;
}
