abstract final class PaperTypes {
  static const todo = 'todo';
  static const note = 'note';

  static String normalize(String? value) {
    return value == note ? note : todo;
  }
}

abstract final class MarkdownRenderModes {
  static const off = 'off';
  static const basic = 'basic';
  static const enhanced = 'enhanced';

  static String normalize(String? value) {
    return value == off || value == basic || value == enhanced
        ? value!
        : enhanced;
  }
}

abstract final class TodoVisualSizes {
  static const small = 'small';
  static const medium = 'medium';
  static const large = 'large';
  static const extraLarge = 'extraLarge';

  static String normalize(String? value) {
    return value == small || value == large || value == extraLarge
        ? value!
        : medium;
  }
}

abstract final class UiFontPresets {
  static const defaultPreset = 'default';
  static const serif = 'serif';
  static const mono = 'mono';
  static const custom = 'custom';

  static String normalize(String? value) {
    return value == serif || value == mono || value == custom
        ? value!
        : defaultPreset;
  }
}

abstract final class ColorSchemes {
  static const warm = 'warm';
  static const ink = 'ink';
  static const forest = 'forest';
  static const rose = 'rose';

  static String normalize(String? value) {
    return value == warm || value == ink || value == forest || value == rose
        ? value!
        : warm;
  }
}

abstract final class DeepCapsuleSides {
  static const left = 'left';
  static const right = 'right';

  static String normalize(String? value) {
    return value == left ? left : right;
  }
}

abstract final class FullscreenTopmostModes {
  static const avoid = 'avoid';
  static const stayOnTop = 'stayOnTop';

  static String normalize(String? value) {
    return value == stayOnTop ? stayOnTop : avoid;
  }
}

abstract final class TodoReminderIntervalUnits {
  static const minutes = 'minutes';
  static const hours = 'hours';

  static String normalize(String? value) {
    return value == hours ? hours : minutes;
  }
}

abstract final class TodoReminderScopes {
  static const nearest = 'nearest';
  static const all = 'all';

  static String normalize(String? value) {
    return value == nearest ? nearest : all;
  }
}

abstract final class TodoDueYearDisplayModes {
  static const none = 'none';
  static const short = 'short';
  static const full = 'full';

  static String normalize(String? value) {
    return value == short || value == full ? value! : none;
  }
}

abstract final class NoteCanvasElementTypes {
  static const code = 'code';
  static const text = 'text';

  static String normalize(String? value) {
    return value == text ? text : code;
  }
}

abstract final class PaperLayoutDefaults {
  static const minWidth = 220.0;
  static const minHeight = 160.0;
  static const todoDefaultWidth = 280.0;
  static const todoDefaultHeight = 340.0;
  static const noteDefaultWidth = 320.0;
  static const noteDefaultHeight = 360.0;
}
