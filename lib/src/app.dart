import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import 'app_controller.dart';
import 'core/model/app_state.dart';
import 'core/model/external_uri_targets.dart';
import 'core/model/markdown_formatting.dart';
import 'core/model/markdown_inline_html.dart';
import 'core/model/markdown_link_targets.dart';
import 'core/model/markdown_links.dart';
import 'core/model/markdown_list_continuation.dart';
import 'core/model/markdown_paste.dart';
import 'core/model/note_canvas_element.dart';
import 'core/model/paper_constants.dart';
import 'core/model/paper_data.dart';
import 'core/model/paper_item.dart';
import 'core/model/paper_titles.dart';
import 'core/model/sync_settings.dart';
import 'core/model/todo_paste.dart';
import 'core/model/todo_due_date.dart';
import 'core/script/script_capsule.dart';
import 'core/storage/state_store.dart';
import 'core/startup/startup_command.dart';
import 'platform/platform_services.dart';
import 'sync/android_background_sync.dart';
import 'sync/app_sync_service.dart';
import 'sync/webdav/webdav_client.dart';
import 'sync/webdav/webdav_payload_codec.dart';
import 'sync/webdav/webdav_state_sync_service.dart';
import 'ui/papertodo_strings.dart';
import 'ui/runtime_custom_font.dart';
import 'ui/sync_settings_dialog.dart';

const _externalMarkdownExportRetention = Duration(days: 7);
const _maxExternalMarkdownPaperIdFileNameLength = 96;
const _maxTodoReminderDetailLines = 4;
const _todoReminderLeadTime = Duration(minutes: 10);
const _todoReminderGraceTime = Duration(minutes: 2);
const _windowsPaperTransparencyKey = Color(0xFF010203);
const _yaHeiFontFamily = 'Microsoft YaHei UI';
const _yaHeiFontFamilyFallback = [
  'Microsoft YaHei',
  'Segoe UI',
  'Microsoft JhengHei UI',
  'Microsoft JhengHei',
  'Yu Gothic UI',
  'Malgun Gothic',
  'Meiryo',
  'Segoe UI Symbol',
  'Segoe UI Emoji',
];
const _dengXianFontFamily = 'DengXian';
const _dengXianFontFamilyFallback = [
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'Segoe UI',
  'Microsoft JhengHei UI',
  'Microsoft JhengHei',
  'Yu Gothic UI',
  'Malgun Gothic',
  'Meiryo',
  'Segoe UI Symbol',
  'Segoe UI Emoji',
];
final _paperTodoMarkdownBuilders = <String, MarkdownElementBuilder>{
  'u': _UnderlineMarkdownElementBuilder(),
};

typedef AndroidBackgroundSyncConfigurator = Future<void> Function({
  required SyncSettings sync,
  required String stateFilePath,
});

typedef PaperWindowActionSender = Future<void> Function(
  String kind, {
  String value,
});

typedef PaperWindowReminderPresenter = Future<void> Function(
  Map<String, Object?> reminder,
);

String _syncUserConfigurationJson(SyncSettings settings) {
  return jsonEncode(<String, Object?>{
    'enabled': settings.enabled,
    'provider': settings.provider,
    'webDav': settings.webDav.toJson(),
  });
}

String _syncTargetConfigurationJson(SyncSettings settings) {
  final webDav = settings.webDav;
  return jsonEncode(<String, Object?>{
    'provider': settings.provider,
    'endpoint': webDav.endpoint,
    'username': webDav.username,
    'password': webDav.password,
    'encryptionPassphrase': webDav.encryptionPassphrase,
    'rootPath': webDav.rootPath,
  });
}

void _copySyncRuntimeMetadata({
  required SyncSettings source,
  required SyncSettings target,
  required bool preserveOperationProgress,
  required bool preservePendingOperationBatch,
}) {
  final decoded =
      jsonDecode(jsonEncode(source.toJson())) as Map<String, dynamic>;
  final runtimeCopy = SyncSettings.fromJson(decoded);
  target
    ..operationDeviceSequences = preserveOperationProgress
        ? runtimeCopy.operationDeviceSequences
        : <String, int>{}
    ..pendingOperationBatch =
        preservePendingOperationBatch ? runtimeCopy.pendingOperationBatch : null
    ..deletedPaperTombstones = runtimeCopy.deletedPaperTombstones
    ..deletedTodoItemTombstones = runtimeCopy.deletedTodoItemTombstones
    ..extra = runtimeCopy.extra;
  target.webDav.extra = runtimeCopy.webDav.extra;
}

final _paperTodoMarkdownExtensionSet = md.ExtensionSet(
  md.ExtensionSet.commonMark.blockSyntaxes,
  <md.InlineSyntax>[
    ...md.ExtensionSet.commonMark.inlineSyntaxes,
    md.StrikethroughSyntax(),
  ],
);

class _UnderlineMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final baseStyle = parentStyle ?? DefaultTextStyle.of(context).style;
    return SelectableText.rich(
      TextSpan(
        text: element.textContent,
        style: baseStyle.merge(preferredStyle).merge(
              const TextStyle(decoration: TextDecoration.underline),
            ),
      ),
    );
  }
}

class RePaperTodoApp extends StatefulWidget {
  const RePaperTodoApp({
    required this.controller,
    required this.store,
    this.syncService,
    this.configureAndroidBackgroundSync =
        configureRePaperTodoAndroidBackgroundSync,
    this.customFontLoader,
    this.initialSurfacePaperId,
    this.paperWindowMode = false,
    this.coordinatorWindowMode = false,
    this.paperWindowActionSender,
    this.paperWindowDragStarter,
    this.paperWindowCapsuleHoverChanged,
    this.paperWindowResizeStarter,
    this.paperWindowReminderPresenter,
    super.key,
  });

  final RePaperTodoController controller;
  final StateStore store;
  final AppSyncService? syncService;
  final AndroidBackgroundSyncConfigurator configureAndroidBackgroundSync;
  final PaperTodoRuntimeCustomFontLoader? customFontLoader;
  final String? initialSurfacePaperId;
  final bool paperWindowMode;
  final bool coordinatorWindowMode;
  final PaperWindowActionSender? paperWindowActionSender;
  final Future<void> Function()? paperWindowDragStarter;
  final Future<void> Function(bool hovered)? paperWindowCapsuleHoverChanged;
  final Future<void> Function(String direction)? paperWindowResizeStarter;
  final PaperWindowReminderPresenter? paperWindowReminderPresenter;

  @override
  State<RePaperTodoApp> createState() => _RePaperTodoAppState();
}

class _RePaperTodoAppState extends State<RePaperTodoApp> {
  String? _runtimeCustomFontFamily;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRuntimeCustomFont());
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: PaperTodoStrings.resolve(
        PaperTodoStrings.resolveLocale(
          WidgetsBinding.instance.platformDispatcher.locale,
          PaperTodoStrings.supportedLocales,
        ),
      ).get(PaperTodoStringKeys.appTitle),
      supportedLocales: PaperTodoStrings.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      localeResolutionCallback: (locale, supportedLocales) {
        return PaperTodoStrings.resolveLocale(locale, supportedLocales);
      },
      theme: _appTheme(Brightness.light, state),
      darkTheme: _appTheme(Brightness.dark, state),
      themeMode: _themeMode(state.theme),
      builder: (context, child) {
        final locale = Localizations.maybeLocaleOf(context) ??
            PaperTodoStrings.resolveLocale(
              WidgetsBinding.instance.platformDispatcher.locale,
              PaperTodoStrings.supportedLocales,
            );
        return PaperTodoStringsScope(
          strings: PaperTodoStrings.resolve(locale),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: PaperBoardScreen(
        controller: widget.controller,
        store: widget.store,
        syncService: widget.syncService ?? AppSyncService(),
        configureAndroidBackgroundSync: widget.configureAndroidBackgroundSync,
        onAppThemeChanged: () => setState(() {}),
        initialSurfacePaperId: widget.initialSurfacePaperId,
        paperWindowMode: widget.paperWindowMode,
        coordinatorWindowMode: widget.coordinatorWindowMode,
        paperWindowActionSender: widget.paperWindowActionSender,
        paperWindowDragStarter: widget.paperWindowDragStarter,
        paperWindowCapsuleHoverChanged: widget.paperWindowCapsuleHoverChanged,
        paperWindowResizeStarter: widget.paperWindowResizeStarter,
        paperWindowReminderPresenter: widget.paperWindowReminderPresenter,
      ),
    );
  }

  Future<void> _loadRuntimeCustomFont() async {
    final family =
        await (widget.customFontLoader ?? PaperTodoRuntimeCustomFontLoader())
            .load();
    if (!mounted ||
        family == null ||
        family.trim().isEmpty ||
        family == _runtimeCustomFontFamily) {
      return;
    }
    setState(() => _runtimeCustomFontFamily = family);
  }

  ThemeData _appTheme(Brightness brightness, AppState state) {
    final colors = _paperColorScheme(brightness, state);
    final base = ThemeData(
      colorScheme: colors,
      useMaterial3: true,
      scaffoldBackgroundColor: colors.surface,
      canvasColor: colors.surface,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.standard,
    );
    final fontFamily = _fontFamily(state);
    final fontFamilyFallback = _fontFamilyFallback(state);
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSizeFactor: state.zoom,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSizeFactor: state.zoom,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          maximumSize: const Size(40, 40),
          padding: const EdgeInsets.all(6),
          foregroundColor: colors.onSurfaceVariant,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: colors.outline, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colors.primary
              : Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(colors.onPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: colors.shadow.withValues(alpha: 0.22),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        textStyle: base.textTheme.bodyMedium?.copyWith(
          color: colors.onSurface,
          fontSize: 13,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(10),
          shadowColor: WidgetStatePropertyAll(
            colors.shadow.withValues(alpha: 0.22),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              side: BorderSide(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 4),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant.withValues(alpha: 0.7),
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.onSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: colors.surface, fontSize: 12),
        waitDuration: const Duration(milliseconds: 450),
      ),
    );
  }

  ColorScheme _paperColorScheme(Brightness brightness, AppState state) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorSchemes.normalize(state.colorScheme);
    final palettes = <String,
        ({
      Color lightPaper,
      Color lightBorder,
      Color lightText,
      Color lightWeak,
      Color lightActive,
      Color darkPaper,
      Color darkBorder,
      Color darkText,
      Color darkWeak,
      Color darkActive
    })>{
      ColorSchemes.warm: (
        lightPaper: const Color(0xFFFFF9EA),
        lightBorder: const Color(0xFFE0CEA7),
        lightText: const Color(0xFF33291E),
        lightWeak: const Color(0xFF8A7A63),
        lightActive: const Color(0xFF8C7350),
        darkPaper: const Color(0xFF211F1C),
        darkBorder: const Color(0xFF4C453D),
        darkText: const Color(0xFFE7E0D4),
        darkWeak: const Color(0xFF92897B),
        darkActive: const Color(0xFFA88E6A),
      ),
      ColorSchemes.ink: (
        lightPaper: const Color(0xFFF6F7F9),
        lightBorder: const Color(0xFFD0D6DE),
        lightText: const Color(0xFF262C36),
        lightWeak: const Color(0xFF767E8A),
        lightActive: const Color(0xFF5A6C86),
        darkPaper: const Color(0xFF1A1C20),
        darkBorder: const Color(0xFF3C424C),
        darkText: const Color(0xFFDEE3EA),
        darkWeak: const Color(0xFF8A929E),
        darkActive: const Color(0xFF849CBC),
      ),
      ColorSchemes.forest: (
        lightPaper: const Color(0xFFF3F8F1),
        lightBorder: const Color(0xFFC8DAC6),
        lightText: const Color(0xFF26322A),
        lightWeak: const Color(0xFF6E8070),
        lightActive: const Color(0xFF588260),
        darkPaper: const Color(0xFF1A1E1B),
        darkBorder: const Color(0xFF3A463C),
        darkText: const Color(0xFFDCE4DC),
        darkWeak: const Color(0xFF869488),
        darkActive: const Color(0xFF7CA886),
      ),
      ColorSchemes.rose: (
        lightPaper: const Color(0xFFFDF5F6),
        lightBorder: const Color(0xFFE4CDD2),
        lightText: const Color(0xFF36262A),
        lightWeak: const Color(0xFF8C7278),
        lightActive: const Color(0xFF9E6876),
        darkPaper: const Color(0xFF211C1E),
        darkBorder: const Color(0xFF4E4044),
        darkText: const Color(0xFFE8DCDF),
        darkWeak: const Color(0xFF988489),
        darkActive: const Color(0xFFBE8694),
      ),
    }[scheme]!;
    final surface = dark ? palettes.darkPaper : palettes.lightPaper;
    final border = dark ? palettes.darkBorder : palettes.lightBorder;
    final text = dark ? palettes.darkText : palettes.lightText;
    final weak = dark ? palettes.darkWeak : palettes.lightWeak;
    final customThemeColor = _customThemeColor(state.customThemeColorHex);
    final active = customThemeColor == null
        ? (dark ? palettes.darkActive : palettes.lightActive)
        : ColorScheme.fromSeed(
            seedColor: customThemeColor,
            brightness: brightness,
          ).primary;
    return ColorScheme.fromSeed(
      seedColor: active,
      brightness: brightness,
    ).copyWith(
      primary: active,
      onPrimary: dark ? const Color(0xFF211F1C) : Colors.white,
      surface: surface,
      surfaceContainerLowest: surface,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surface,
      surfaceContainerHighest: surface,
      onSurface: text,
      onSurfaceVariant: weak,
      outline: border,
      outlineVariant: border,
      primaryContainer: dark
          ? border
          : Color.alphaBlend(active.withValues(alpha: 0.12), surface),
      onPrimaryContainer: text,
      secondary: active,
      onSecondary: dark ? const Color(0xFF211F1C) : Colors.white,
    );
  }

  ThemeMode _themeMode(String theme) {
    return switch (theme.trim().toLowerCase()) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Color? _customThemeColor(String value) {
    final match = RegExp(r'^#?([0-9A-Fa-f]{6})$').firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    return Color(int.parse('FF${match.group(1)!}', radix: 16));
  }

  String? _fontFamily(AppState state) {
    return resolveAppFontFamily(
      state,
      runtimeCustomFontFamily: _runtimeCustomFontFamily,
    );
  }

  List<String>? _fontFamilyFallback(AppState state) {
    return resolveAppFontFamilyFallback(
      state,
      runtimeCustomFontFamily: _runtimeCustomFontFamily,
    );
  }
}

String? resolveAppFontFamily(
  AppState state, {
  String? runtimeCustomFontFamily,
}) {
  final systemFontFamilyName = normalizeSystemFontFamilyName(
    state.systemFontFamilyName,
  );
  if (systemFontFamilyName.isNotEmpty) {
    return systemFontFamilyName;
  }
  final runtimeFamily = runtimeCustomFontFamily?.trim();
  if (runtimeFamily != null && runtimeFamily.isNotEmpty) {
    return runtimeFamily;
  }
  return switch (UiFontPresets.normalize(state.uiFontPreset)) {
    UiFontPresets.yaHei => _yaHeiFontFamily,
    UiFontPresets.dengXian => _dengXianFontFamily,
    UiFontPresets.serif => 'serif',
    UiFontPresets.mono => 'monospace',
    _ => null,
  };
}

List<String>? resolveAppFontFamilyFallback(
  AppState state, {
  String? runtimeCustomFontFamily,
}) {
  if (normalizeSystemFontFamilyName(state.systemFontFamilyName).isNotEmpty) {
    return null;
  }
  final runtimeFamily = runtimeCustomFontFamily?.trim();
  if (runtimeFamily != null && runtimeFamily.isNotEmpty) {
    return null;
  }
  return switch (UiFontPresets.normalize(state.uiFontPreset)) {
    UiFontPresets.yaHei => _yaHeiFontFamilyFallback,
    UiFontPresets.dengXian => _dengXianFontFamilyFallback,
    _ => null,
  };
}

String _shortenTitle(String title, int maxLength) {
  return PaperTitles.shorten(title, maxLength);
}

bool _sameStringSet(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

String? _tooltipLabel(bool enabled, String label) => enabled ? label : null;

Widget _conditionalTooltip({
  required bool enabled,
  required String message,
  required Widget child,
}) {
  return enabled ? Tooltip(message: message, child: child) : child;
}

String _readableFailureMessage(Object error, {PaperTodoStrings? strings}) {
  return switch (error) {
    WebDavException(
      :final message,
      :final responseBody,
    ) =>
      _webDavFailureMessage(message, responseBody),
    WebDavPayloadDecryptionException(:final message) => message,
    PlatformException(
      :final code,
      :final message,
      :final details,
    ) =>
      _platformFailureMessage(
        code: code,
        message: message,
        details: details,
        strings: strings,
      ),
    FileSystemException(:final message, :final path) =>
      path == null ? message : '$message: $path',
    StateStoreException(:final message) => message,
    FormatException(:final message) => message,
    TimeoutException(:final message) => message ?? 'The operation timed out.',
    StateError(:final message) => message,
    _ => error.toString(),
  };
}

String _webDavFailureMessage(String message, String responseBody) {
  final cleanBody = _cleanWebDavResponseBodyForDisplay(responseBody);
  if (cleanBody.isEmpty ||
      cleanBody == message ||
      message.contains(cleanBody) ||
      cleanBody.contains(message)) {
    return message;
  }
  return '$message Provider details: $cleanBody';
}

String _cleanWebDavResponseBodyForDisplay(String responseBody) {
  const maxLength = 240;
  final normalized = responseBody
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength - 3).trimRight()}...';
}

String _platformFailureMessage({
  required String code,
  required String? message,
  required Object? details,
  required PaperTodoStrings? strings,
}) {
  final readableMessage = message?.trim();
  final platformMessageKey = _platformFailureMessageKey(code);
  if (strings != null &&
      platformMessageKey != null &&
      (readableMessage == null ||
          readableMessage.isEmpty ||
          _isGenericPlatformFailureMessage(code, readableMessage))) {
    return strings.get(platformMessageKey);
  }
  if (readableMessage != null && readableMessage.isNotEmpty) {
    return readableMessage;
  }
  final readableDetails = details?.toString().trim();
  if (readableDetails != null && readableDetails.isNotEmpty) {
    return readableDetails;
  }
  return code;
}

String? _platformFailureMessageKey(String code) {
  return switch (code) {
    'invalid_uri' => PaperTodoStringKeys.platformInvalidUri,
    'invalid_path' => PaperTodoStringKeys.platformInvalidPath,
    'file_not_found' => PaperTodoStringKeys.platformFileNotFound,
    'file_provider_failed' => PaperTodoStringKeys.platformFileShareFailed,
    'open_external_file_failed' =>
      PaperTodoStringKeys.platformOpenExternalFileFailed,
    'open_uri_failed' => PaperTodoStringKeys.platformOpenUriFailed,
    _ => null,
  };
}

bool _isGenericPlatformFailureMessage(String code, String message) {
  return switch (code) {
    'invalid_uri' => const {
        'The URI is empty.',
        'The URI contains unsupported characters.',
        'The URI is not valid.',
        'The URI must include a scheme.',
        'The URI contains malformed escapes.',
        'The URI contains encoded unsupported characters.',
        'The URI scheme is not supported.',
        'The URI is not valid UTF-8.',
      }.contains(message),
    'invalid_path' => const {
        'The file path is empty.',
        'The file path contains unsupported characters.',
        'The file path must be absolute.',
        'The file path is not valid.',
        'The file is outside the configured RePaperTodo share directories.',
        'The external file path is empty.',
        'The external file path contains unsupported characters.',
      }.contains(message),
    'file_not_found' => message == 'The file does not exist.',
    'file_provider_failed' =>
      message == 'The file is outside the configured share paths.',
    'open_external_file_failed' => const {
        'The external file cannot be shared securely.',
        'Unable to open the external file.',
      }.contains(message),
    'open_uri_failed' => const {
        'Unable to open the URI.',
        'The URI cannot be opened securely.',
      }.contains(message),
    _ => false,
  };
}

String? _normalizeExternalUri(String value) {
  return normalizeExternalUriTarget(value, allowBareWww: true);
}

String? _normalizeMarkdownLocalPath(String value) {
  return normalizeMarkdownLocalPathTarget(value);
}

String _markdownEditorActionLabel(
  PaperTodoStrings strings,
  String externalMarkdownExtension,
) {
  return strings.format(
    PaperTodoStringKeys.actionOpenMarkdownInDefaultEditor,
    [_normalizedExternalMarkdownExtensionForDisplay(externalMarkdownExtension)],
  );
}

String _externalMarkdownButtonLabel(String externalMarkdownExtension) {
  var extension = _normalizedExternalMarkdownExtensionForDisplay(
    externalMarkdownExtension,
  ).substring(1);
  if (extension.trim().isEmpty) {
    extension = 'md';
  }
  return extension.length > 2
      ? extension.substring(0, 2).toUpperCase()
      : extension.toUpperCase();
}

String _normalizedExternalMarkdownExtensionForDisplay(String value) {
  var extension = value.trim();
  if (extension.isEmpty) {
    return '.md';
  }
  if (extension.startsWith('*.')) {
    extension = extension.substring(1);
  }
  if (!extension.startsWith('.')) {
    extension = '.$extension';
  }
  if (extension.length < 2 ||
      extension.length > 120 ||
      extension.endsWith('.') ||
      extension.endsWith(' ') ||
      _hasInvalidExternalMarkdownExtensionCharacter(extension)) {
    return '.md';
  }
  return extension.toLowerCase();
}

bool _hasInvalidExternalMarkdownExtensionCharacter(String value) {
  const invalidCharacters = {'<', '>', ':', '"', '/', '\\', '|', '?', '*'};
  return value.runes.any((rune) {
    if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      return true;
    }
    return invalidCharacters.contains(String.fromCharCode(rune));
  });
}

class _CompactAppBarActions {
  const _CompactAppBarActions._();

  static const openMarkdown = 'open-markdown';
  static const newTodo = 'new-todo';
  static const newNote = 'new-note';
  static const toggleCollapseAll = 'toggle-collapse-all';
  static const recoverySnapshots = 'recovery-snapshots';
  static const showHidden = 'show-hidden';
  static const settings = 'settings';
}

class PaperBoardScreen extends StatefulWidget {
  const PaperBoardScreen({
    required this.controller,
    required this.store,
    required this.syncService,
    required this.configureAndroidBackgroundSync,
    this.onAppThemeChanged,
    this.initialSurfacePaperId,
    this.paperWindowMode = false,
    this.coordinatorWindowMode = false,
    this.paperWindowActionSender,
    this.paperWindowDragStarter,
    this.paperWindowCapsuleHoverChanged,
    this.paperWindowResizeStarter,
    this.paperWindowReminderPresenter,
    super.key,
  });

  final RePaperTodoController controller;
  final StateStore store;
  final AppSyncService syncService;
  final AndroidBackgroundSyncConfigurator configureAndroidBackgroundSync;
  final VoidCallback? onAppThemeChanged;
  final String? initialSurfacePaperId;
  final bool paperWindowMode;
  final bool coordinatorWindowMode;
  final PaperWindowActionSender? paperWindowActionSender;
  final Future<void> Function()? paperWindowDragStarter;
  final Future<void> Function(bool hovered)? paperWindowCapsuleHoverChanged;
  final Future<void> Function(String direction)? paperWindowResizeStarter;
  final PaperWindowReminderPresenter? paperWindowReminderPresenter;

  @override
  State<PaperBoardScreen> createState() => _PaperBoardScreenState();
}

class _PaperBoardScreenState extends State<PaperBoardScreen>
    with WidgetsBindingObserver {
  bool _isSyncing = false;
  bool _isSettingsOpen = false;
  bool _deferredSettingsSync = false;
  bool _queuedSilentSync = false;
  Future<void> _saveQueue = Future<void>.value();
  Future<void>? _activeSyncFuture;
  Future<void>? _exitCommandFuture;
  StreamSubscription<PaperData>? _surfaceUpdateSubscription;
  StreamSubscription<PaperData>? _paperEditSubscription;
  StreamSubscription<PaperWindowActionRequest>? _paperActionSubscription;
  StreamSubscription<CapsuleDropRequest>? _capsuleDropSubscription;
  StreamSubscription<String>? _paperOpenSubscription;
  StreamSubscription<String>? _paperDeleteSubscription;
  StreamSubscription<void>? _coordinatorCloseSubscription;
  StreamSubscription<StartupCommand>? _startupCommandSubscription;
  Timer? _autoSyncTimer;
  Timer? _settingsDeferredAutoSyncTimer;
  Timer? _localEditSyncDebounce;
  Timer? _surfaceSaveDebounce;
  Timer? _titleSurfaceDebounce;
  Timer? _todoReminderTimer;
  Timer? _todoReminderSnackBarDismissTimer;
  DateTime? _todoReminderSnackBarDismissStartedAt;
  Duration _todoReminderSnackBarRemaining = Duration.zero;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
      _todoReminderSnackBarController;
  int _localEditSyncGeneration = 0;
  AppState? _pendingLocalEditBaseState;
  AppState? _pendingLocalEditLatestState;
  int? _pendingLocalEditGeneration;
  String? _surfacePaperId;
  String? _lastTrayMenuLanguageCode;
  TrayMenuLabels? _cachedTrayMenuLabels;
  final Map<String, bool> _surfaceVisibilityByPaperId = <String, bool>{};
  final Map<String, DateTime> _lastTodoReminderAt = <String, DateTime>{};
  final Set<String> _activeTodoReminderItemIds = <String>{};
  final Set<String> _activeTodoReminderKeys = <String>{};

  RePaperTodoController get controller => widget.controller;
  PaperTodoStrings get strings => PaperTodoStringsScope.of(context);

  @override
  void initState() {
    super.initState();
    _surfacePaperId = widget.initialSurfacePaperId;
    WidgetsBinding.instance.addObserver(this);
    _surfaceUpdateSubscription =
        controller.paperSurfaceUpdates.listen(_handleSurfaceUpdate);
    _paperEditSubscription = controller.paperEdits.listen(_handlePaperEdit);
    _paperActionSubscription =
        controller.paperWindowActionRequests.listen(_handlePaperWindowAction);
    _capsuleDropSubscription =
        controller.capsuleDrops.listen(_handleCapsuleDrop);
    _paperOpenSubscription = controller.paperOpenRequests.listen((paperId) {
      unawaited(_handlePaperOpenRequest(paperId));
    });
    _paperDeleteSubscription = controller.paperDeleteRequests.listen((paperId) {
      unawaited(_handlePaperDeleteRequest(paperId));
    });
    _coordinatorCloseSubscription =
        controller.coordinatorCloseRequests.listen((_) {
      if (_isSettingsOpen && mounted) {
        unawaited(Navigator.of(context, rootNavigator: true).maybePop());
      }
    });
    _startupCommandSubscription = controller.startupCommands.listen((command) {
      unawaited(_handleStartupCommand(command));
    });
    final pendingStartupCommand = controller.takePendingUiStartupCommand();
    if (pendingStartupCommand != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_handleStartupCommand(pendingStartupCommand));
      });
    }
    _refreshSurfaceVisibilitySnapshot();
    _restartAutoSyncTimer();
    if (!widget.coordinatorWindowMode) {
      _restartTodoReminderTimer();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentStrings = strings;
    if (_lastTrayMenuLanguageCode == currentStrings.languageCode) {
      return;
    }
    _lastTrayMenuLanguageCode = currentStrings.languageCode;
    _cachedTrayMenuLabels = _trayMenuLabelsFor(currentStrings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_rebuildTrayMenu());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _settingsDeferredAutoSyncTimer?.cancel();
    _localEditSyncDebounce?.cancel();
    _surfaceSaveDebounce?.cancel();
    _titleSurfaceDebounce?.cancel();
    _todoReminderTimer?.cancel();
    _cancelTodoReminderSnackBarDismissTimer();
    unawaited(_surfaceUpdateSubscription?.cancel());
    unawaited(_paperEditSubscription?.cancel());
    unawaited(_paperActionSubscription?.cancel());
    unawaited(_capsuleDropSubscription?.cancel());
    unawaited(_paperOpenSubscription?.cancel());
    unawaited(_paperDeleteSubscription?.cancel());
    unawaited(_coordinatorCloseSubscription?.cancel());
    unawaited(_startupCommandSubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_syncSilentlyIfConfigured());
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final boardCanvasColor = Color.alphaBlend(
      Colors.black.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.30 : 0.07,
      ),
      colorScheme.surface,
    );
    final enableToolTips = controller.state.enableToolTips;
    final linkedNoteIds = _linkedNoteIds();
    final visiblePapers = controller.state.papers.where((paper) {
      if (!paper.isVisible) {
        return false;
      }
      return !(controller.state.hideLinkedNotesFromCapsules &&
          paper.isNote &&
          linkedNoteIds.contains(paper.id));
    }).toList();
    final hiddenPapers =
        controller.state.papers.where((paper) => !paper.isVisible).toList();
    final notePapers =
        controller.state.papers.where((paper) => paper.isNote).toList();
    final surfacePaper = _surfacePaper();
    if (widget.coordinatorWindowMode) {
      return Scaffold(
        key: const ValueKey('windows-settings-window-surface'),
        backgroundColor: colorScheme.surface,
        body: const SizedBox.expand(),
      );
    }
    if (widget.paperWindowMode) {
      if (surfacePaper == null) {
        return const SizedBox.shrink();
      }
      if (_isCollapseAllMasterPaper(surfacePaper)) {
        return _paperWindowMasterCapsule(surfacePaper);
      }
      if (surfacePaper.isCollapsed) {
        return _paperWindowCapsule(surfacePaper);
      }
      return Scaffold(
        backgroundColor: _windowsPaperTransparencyKey,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              key: ValueKey('${surfacePaper.id}-paper-window-chrome-margin'),
              padding: const EdgeInsets.all(8),
              child: _paperPreview(surfacePaper, notePapers),
            ),
            if (!surfacePaper.isPinnedToDesktop) ..._paperWindowResizeHandles(),
          ],
        ),
      );
    }
    final useCompactAppBar = MediaQuery.sizeOf(context).shortestSide < 600;
    return PopScope<Object?>(
      canPop: surfacePaper == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || surfacePaper == null) {
          return;
        }
        setState(() => _surfacePaperId = null);
      },
      child: Scaffold(
        backgroundColor: boardCanvasColor,
        appBar: AppBar(
          toolbarHeight: useCompactAppBar ? 52 : null,
          scrolledUnderElevation: 0,
          backgroundColor: boardCanvasColor,
          surfaceTintColor: Colors.transparent,
          leading: surfacePaper == null
              ? null
              : IconButton(
                  tooltip: _tooltipLabel(
                    enableToolTips,
                    strings.get(PaperTodoStringKeys.actionBackToBoard),
                  ),
                  onPressed: () => setState(() => _surfacePaperId = null),
                  style: useCompactAppBar
                      ? IconButton.styleFrom(
                          minimumSize: const Size.square(48),
                          maximumSize: const Size.square(48),
                        )
                      : null,
                  icon: const Icon(Icons.arrow_back),
                ),
          title: Text(
            surfacePaper == null
                ? strings.get(PaperTodoStringKeys.appTitle)
                : _displayTitle(surfacePaper),
            style: useCompactAppBar
                ? Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    )
                : null,
          ),
          actions: _appBarActions(
            surfacePaper: surfacePaper,
            hiddenPapers: hiddenPapers,
            enableToolTips: enableToolTips,
            compact: useCompactAppBar,
          ),
        ),
        body: ColoredBox(
          color: boardCanvasColor,
          child: surfacePaper == null
              ? ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    useCompactAppBar ? 12 : 16,
                    useCompactAppBar ? 8 : 16,
                    useCompactAppBar ? 12 : 16,
                    16,
                  ),
                  itemCount: visiblePapers.length,
                  separatorBuilder: (context, index) =>
                      SizedBox(height: useCompactAppBar ? 8 : 12),
                  itemBuilder: (context, index) {
                    return _paperPreview(visiblePapers[index], notePapers);
                  },
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    useCompactAppBar ? 12 : 16,
                    useCompactAppBar ? 8 : 16,
                    useCompactAppBar ? 12 : 16,
                    16,
                  ),
                  children: [
                    _paperPreview(surfacePaper, notePapers),
                  ],
                ),
        ),
      ),
    );
  }

  bool _isCollapseAllMasterPaper(PaperData paper) {
    if (!controller.state.useCapsuleMode ||
        !controller.state.useCapsuleCollapseAll ||
        !controller.state.isCapsuleCollapseAllActiveFor(paper)) {
      return false;
    }
    final queueKey = controller.state.capsuleQueueKeyFor(paper);
    final linkedNoteIds = _linkedNoteIds();
    for (final candidate in controller.state.papers) {
      if (!candidate.isVisible ||
          (controller.state.enableTodoNoteLinks &&
              controller.state.hideLinkedNotesFromCapsules &&
              candidate.isNote &&
              linkedNoteIds.contains(candidate.id)) ||
          !controller.state.isCapsuleCollapseAllActiveFor(candidate) ||
          controller.state.capsuleQueueKeyFor(candidate) != queueKey) {
        continue;
      }
      return candidate.id == paper.id;
    }
    return false;
  }

  Widget _paperWindowMasterCapsule(PaperData paper) {
    final colors = Theme.of(context).colorScheme;
    final collapseAllActive =
        controller.state.isCapsuleCollapseAllActiveFor(paper);
    Future<void> toggle() async {
      final sender = widget.paperWindowActionSender;
      if (sender != null) {
        await sender(PaperWindowActionKinds.toggleCollapseAll);
        return;
      }
      await _toggleCollapseAll(paper);
    }

    return Scaffold(
      backgroundColor: _windowsPaperTransparencyKey,
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: MouseRegion(
          onEnter: widget.paperWindowCapsuleHoverChanged == null
              ? null
              : (_) => unawaited(
                    widget.paperWindowCapsuleHoverChanged!(true),
                  ),
          onExit: widget.paperWindowCapsuleHoverChanged == null
              ? null
              : (_) => unawaited(
                    widget.paperWindowCapsuleHoverChanged!(false),
                  ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('${paper.id}-paper-window-master-capsule'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => unawaited(toggle()),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: 0.18),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: Row(
                    children: [
                      Listener(
                        key: ValueKey('${paper.id}-master-capsule-drag-handle'),
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: widget.paperWindowDragStarter == null
                            ? null
                            : (_) => unawaited(
                                  widget.paperWindowDragStarter!(),
                                ),
                        child: SizedBox(
                          width: 26,
                          height: double.infinity,
                          child: Icon(
                            collapseAllActive
                                ? Icons.unfold_more_outlined
                                : Icons.unfold_less_outlined,
                            size: 14,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          strings.get(
                            collapseAllActive
                                ? PaperTodoStringKeys.actionExpandAll
                                : PaperTodoStringKeys.actionCollapseAll,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _paperWindowCapsule(PaperData paper) {
    final colorScheme = Theme.of(context).colorScheme;
    final capsuleCloseWidth = controller.state.useDeepCapsuleMode ? 30.0 : 21.0;
    final scriptCapsuleSpec =
        paper.isNote ? ScriptCapsuleSpec.tryParse(paper.content) : null;
    void expandForEditing() {
      final sender = widget.paperWindowActionSender;
      if (sender != null) {
        unawaited(sender(PaperWindowActionKinds.expandPaper));
        return;
      }
      setState(() => paper.isCollapsed = false);
      unawaited(_saveState());
      unawaited(controller.updatePaperSurface(paper));
    }

    return Scaffold(
      backgroundColor: _windowsPaperTransparencyKey,
      body: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: MouseRegion(
                onEnter: widget.paperWindowCapsuleHoverChanged == null
                    ? null
                    : (_) => unawaited(
                          widget.paperWindowCapsuleHoverChanged!(true),
                        ),
                onExit: widget.paperWindowCapsuleHoverChanged == null
                    ? null
                    : (_) => unawaited(
                          widget.paperWindowCapsuleHoverChanged!(false),
                        ),
                child: Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      border: Border.all(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.shadow.withValues(alpha: 0.18),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            key: ValueKey('${paper.id}-paper-window-capsule'),
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(12),
                            ),
                            onTap: scriptCapsuleSpec == null
                                ? expandForEditing
                                : () => unawaited(
                                      _runPaperWindowScriptCapsule(
                                        scriptCapsuleSpec,
                                      ),
                                    ),
                            onSecondaryTap: scriptCapsuleSpec == null
                                ? null
                                : expandForEditing,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Row(
                                children: [
                                  Listener(
                                    key: ValueKey(
                                        '${paper.id}-capsule-drag-handle'),
                                    behavior: HitTestBehavior.opaque,
                                    onPointerDown: widget
                                                .paperWindowDragStarter ==
                                            null
                                        ? null
                                        : (_) => unawaited(
                                              widget.paperWindowDragStarter!(),
                                            ),
                                    child: SizedBox(
                                      width: 26,
                                      height: double.infinity,
                                      child: Icon(
                                        paper.isTodo
                                            ? Icons.check_outlined
                                            : scriptCapsuleSpec != null
                                                ? Icons.bolt_outlined
                                                : Icons.edit_outlined,
                                        size: 13,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _displayTitle(paper),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontSize: 11,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: capsuleCloseWidth,
                          child: InkWell(
                            key: ValueKey(
                                '${paper.id}-paper-window-capsule-close'),
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(12),
                            ),
                            onTap: () => unawaited(_hidePaper(paper)),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runPaperWindowScriptCapsule(ScriptCapsuleSpec spec) async {
    final actionSender = widget.paperWindowActionSender;
    if (actionSender != null) {
      await actionSender(PaperWindowActionKinds.runScriptCapsule);
      return;
    }
    await _runScriptCapsule(spec);
  }

  List<Widget> _paperWindowResizeHandles() {
    final resizeStarter = widget.paperWindowResizeStarter;
    if (resizeStarter == null) {
      return const [];
    }

    Widget handle({
      required String direction,
      required MouseCursor cursor,
      double? left,
      double? top,
      double? right,
      double? bottom,
      double? width,
      double? height,
    }) {
      return Positioned(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        width: width,
        height: height,
        child: Semantics(
          label: strings.get(PaperTodoStringKeys.actionResizePaperWindow),
          child: MouseRegion(
            cursor: cursor,
            child: Listener(
              key: ValueKey('paper-window-resize-$direction'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => unawaited(resizeStarter(direction)),
            ),
          ),
        ),
      );
    }

    // The visible paper starts 8 px inside the transparent window chrome.
    // A 12/18 px native-like hit zone covers both the outer HWND edge and the
    // visible paper border without stealing ordinary content interaction.
    const edge = 12.0;
    const corner = 18.0;
    return [
      handle(
        direction: 'left',
        cursor: SystemMouseCursors.resizeLeftRight,
        left: 0,
        top: corner,
        bottom: corner,
        width: edge,
      ),
      handle(
        direction: 'right',
        cursor: SystemMouseCursors.resizeLeftRight,
        right: 0,
        top: corner,
        bottom: corner,
        width: edge,
      ),
      handle(
        direction: 'top',
        cursor: SystemMouseCursors.resizeUpDown,
        left: corner,
        top: 0,
        right: corner,
        height: edge,
      ),
      handle(
        direction: 'bottom',
        cursor: SystemMouseCursors.resizeUpDown,
        left: corner,
        right: corner,
        bottom: 0,
        height: edge,
      ),
      handle(
        direction: 'topLeft',
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        left: 0,
        top: 0,
        width: corner,
        height: corner,
      ),
      handle(
        direction: 'topRight',
        cursor: SystemMouseCursors.resizeUpRightDownLeft,
        top: 0,
        right: 0,
        width: corner,
        height: corner,
      ),
      handle(
        direction: 'bottomLeft',
        cursor: SystemMouseCursors.resizeUpRightDownLeft,
        left: 0,
        bottom: 0,
        width: corner,
        height: corner,
      ),
      handle(
        direction: 'bottomRight',
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        right: 0,
        bottom: 0,
        width: corner,
        height: corner,
      ),
    ];
  }

  List<Widget> _appBarActions({
    required PaperData? surfacePaper,
    required List<PaperData> hiddenPapers,
    required bool enableToolTips,
    required bool compact,
  }) {
    final currentSurfacePaper = surfacePaper;
    final collapseAllActive = _collapseAllActiveFor(surfacePaper);
    final canOpenSurfaceMarkdown = currentSurfacePaper != null &&
        currentSurfacePaper.isNote &&
        controller.state.showTopBarExternalOpenButton;
    final openMarkdownEditorLabel = _markdownEditorActionLabel(
      strings,
      controller.state.externalMarkdownExtension,
    );
    final externalMarkdownButtonLabel = _externalMarkdownButtonLabel(
      controller.state.externalMarkdownExtension,
    );
    final syncButton = IconButton(
      tooltip: _tooltipLabel(
        enableToolTips,
        strings.get(PaperTodoStringKeys.actionSyncNow),
      ),
      onPressed: _isSyncing ? null : () => _syncNow(),
      style: compact
          ? IconButton.styleFrom(
              minimumSize: const Size.square(48),
              maximumSize: const Size.square(48),
              padding: EdgeInsets.zero,
            )
          : null,
      icon: _isSyncing
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync_outlined),
    );
    if (compact) {
      return [
        syncButton,
        SizedBox.square(
          key: const ValueKey('compact-app-bar-actions'),
          dimension: 48,
          child: PopupMenuButton<String>(
            tooltip: _tooltipLabel(
              enableToolTips,
              strings.get(PaperTodoStringKeys.actionMore),
            ),
            icon: const Icon(Icons.more_vert),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(48),
              maximumSize: const Size.square(48),
            ),
            padding: EdgeInsets.zero,
            onSelected: (value) =>
                _handleCompactAppBarAction(value, surfacePaper),
            itemBuilder: (context) => [
              if (canOpenSurfaceMarkdown)
                _compactMenuItem(
                  value: _CompactAppBarActions.openMarkdown,
                  icon: Icons.file_open_outlined,
                  label: openMarkdownEditorLabel,
                ),
              if (controller.state.showTopBarNewTodoButton)
                _compactMenuItem(
                  value: _CompactAppBarActions.newTodo,
                  icon: Icons.add_task,
                  label: strings.get(PaperTodoStringKeys.actionNewTodo),
                ),
              if (controller.state.showTopBarNewNoteButton)
                _compactMenuItem(
                  value: _CompactAppBarActions.newNote,
                  icon: Icons.note_add_outlined,
                  label: strings.get(PaperTodoStringKeys.actionNewNote),
                ),
              if (controller.state.useCapsuleMode &&
                  controller.state.useCapsuleCollapseAll)
                _compactMenuItem(
                  value: _CompactAppBarActions.toggleCollapseAll,
                  icon:
                      collapseAllActive ? Icons.unfold_more : Icons.unfold_less,
                  label: collapseAllActive
                      ? strings.get(PaperTodoStringKeys.actionExpandAll)
                      : strings.get(PaperTodoStringKeys.actionCollapseAll),
                ),
              _compactMenuItem(
                value: _CompactAppBarActions.recoverySnapshots,
                icon: Icons.restore_outlined,
                label: strings.get(PaperTodoStringKeys.actionRecoverySnapshots),
                enabled: !_isSyncing,
              ),
              _compactMenuItem(
                value: _CompactAppBarActions.showHidden,
                icon: Icons.visibility_outlined,
                label: strings.get(PaperTodoStringKeys.actionShowHidden),
                enabled: hiddenPapers.isNotEmpty,
              ),
              _compactMenuItem(
                value: _CompactAppBarActions.settings,
                icon: Icons.settings_outlined,
                label: strings.get(PaperTodoStringKeys.actionSettings),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      if (canOpenSurfaceMarkdown)
        IconButton(
          tooltip: _tooltipLabel(
            enableToolTips,
            openMarkdownEditorLabel,
          ),
          onPressed: () =>
              unawaited(_openNoteMarkdownExternally(currentSurfacePaper)),
          icon: Text(
            externalMarkdownButtonLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
          ),
        ),
      if (controller.state.showTopBarNewTodoButton)
        IconButton(
          tooltip: _tooltipLabel(
            enableToolTips,
            strings.get(PaperTodoStringKeys.actionNewTodoPaper),
          ),
          onPressed: () =>
              _createPaper(PaperTypes.todo, sourcePaper: surfacePaper),
          icon: const Icon(Icons.add_task),
        ),
      if (controller.state.showTopBarNewNoteButton)
        IconButton(
          tooltip: _tooltipLabel(
            enableToolTips,
            strings.get(PaperTodoStringKeys.actionNewNotePaper),
          ),
          onPressed: () =>
              _createPaper(PaperTypes.note, sourcePaper: surfacePaper),
          icon: const Icon(Icons.note_add_outlined),
        ),
      if (controller.state.useCapsuleMode &&
          controller.state.useCapsuleCollapseAll)
        IconButton(
          tooltip: _tooltipLabel(
            enableToolTips,
            collapseAllActive
                ? strings.get(PaperTodoStringKeys.actionExpandAllPapers)
                : strings.get(PaperTodoStringKeys.actionCollapseAllPapers),
          ),
          onPressed: () => _toggleCollapseAll(surfacePaper),
          icon: Icon(collapseAllActive ? Icons.unfold_more : Icons.unfold_less),
        ),
      syncButton,
      IconButton(
        tooltip: _tooltipLabel(
          enableToolTips,
          strings.get(PaperTodoStringKeys.actionRecoverySnapshots),
        ),
        onPressed: _isSyncing ? null : _openRecoverySnapshots,
        icon: const Icon(Icons.restore_outlined),
      ),
      IconButton(
        tooltip: _tooltipLabel(
          enableToolTips,
          strings.get(PaperTodoStringKeys.actionShowHiddenPapers),
        ),
        onPressed: hiddenPapers.isEmpty ? null : _showHiddenPapers,
        icon: const Icon(Icons.visibility_outlined),
      ),
      IconButton(
        tooltip: _tooltipLabel(
          enableToolTips,
          strings.get(PaperTodoStringKeys.actionSettings),
        ),
        onPressed: _openSettings,
        icon: const Icon(Icons.settings_outlined),
      ),
    ];
  }

  PopupMenuItem<String> _compactMenuItem({
    required String value,
    required IconData icon,
    required String label,
    bool enabled = true,
  }) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      height: _paperTodoPopupMenuHeight(),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }

  void _handleCompactAppBarAction(String value, PaperData? surfacePaper) {
    switch (value) {
      case _CompactAppBarActions.openMarkdown:
        if (surfacePaper != null && surfacePaper.isNote) {
          unawaited(_openNoteMarkdownExternally(surfacePaper));
        }
      case _CompactAppBarActions.newTodo:
        unawaited(_createPaper(PaperTypes.todo, sourcePaper: surfacePaper));
      case _CompactAppBarActions.newNote:
        unawaited(_createPaper(PaperTypes.note, sourcePaper: surfacePaper));
      case _CompactAppBarActions.toggleCollapseAll:
        unawaited(_toggleCollapseAll(surfacePaper));
      case _CompactAppBarActions.recoverySnapshots:
        unawaited(_openRecoverySnapshots());
      case _CompactAppBarActions.showHidden:
        unawaited(_showHiddenPapers());
      case _CompactAppBarActions.settings:
        unawaited(_openSettings());
    }
  }

  Set<String> _linkedNoteIds() {
    final linkedNoteIds = <String>{};
    for (final paper in controller.state.papers) {
      if (!paper.isTodo) {
        continue;
      }
      for (final item in paper.items) {
        final linkedNoteId = item.linkedNoteId;
        if (linkedNoteId != null) {
          linkedNoteIds.add(linkedNoteId);
        }
      }
    }
    return linkedNoteIds;
  }

  PaperData? _surfacePaper() {
    final surfacePaperId =
        widget.paperWindowMode ? widget.initialSurfacePaperId : _surfacePaperId;
    if (surfacePaperId == null) {
      return null;
    }
    for (final paper in controller.state.papers) {
      if (paper.id == surfacePaperId && paper.isVisible) {
        return paper;
      }
    }
    return null;
  }

  void _reconcileSurfacePaperAfterReplacement() {
    final surfacePaperId = _surfacePaperId;
    if (surfacePaperId == null) {
      return;
    }
    final surfacePaperStillVisible = controller.state.papers.any(
      (paper) => paper.id == surfacePaperId && paper.isVisible,
    );
    if (!surfacePaperStillVisible) {
      _surfacePaperId = null;
    }
  }

  PaperPreview _paperPreview(PaperData paper, List<PaperData> notePapers) {
    final actionSender = widget.paperWindowActionSender;
    return PaperPreview(
      paper: paper,
      notePapers: notePapers,
      titleText: controller.paperTitleText(paper),
      enableTodoNoteLinks: controller.state.enableTodoNoteLinks,
      showLinkedNoteName: controller.state.showLinkedNoteName,
      allowLongLinkedNoteTitles: controller.state.allowLongLinkedNoteTitles,
      runLinkedScriptCapsulesOnClick:
          controller.state.runLinkedScriptCapsulesOnClick,
      maxTitleLength: controller.state.maxTitleLength,
      showTopBarNewTodoButton: controller.state.showTopBarNewTodoButton,
      showTopBarNewNoteButton: controller.state.showTopBarNewNoteButton,
      showTopBarExternalOpenButton:
          controller.state.showTopBarExternalOpenButton,
      useCapsuleMode: controller.state.useCapsuleMode,
      onWindowDragStart: widget.paperWindowDragStarter,
      enableToolTips: controller.state.enableToolTips,
      enableAnimations: controller.state.enableAnimations,
      markdownRenderMode: controller.state.markdownRenderMode,
      externalMarkdownExtension: controller.state.externalMarkdownExtension,
      todoVisualSize: controller.state.todoVisualSize,
      todoLineSpacing: controller.state.todoLineSpacing,
      showTodoDueRelativeTime: controller.state.showTodoDueRelativeTime,
      todoDueYearDisplayMode: controller.state.todoDueYearDisplayMode,
      defaultTodoReminderIntervalValue:
          controller.state.todoReminderIntervalValue,
      defaultTodoReminderIntervalUnit:
          controller.state.todoReminderIntervalUnit,
      collapseAllActive: controller.state.useCapsuleMode &&
          controller.state.useCapsuleCollapseAll &&
          controller.state.isCapsuleCollapseAllActiveFor(paper),
      noteLineSpacing: controller.state.noteLineSpacing,
      onChanged: _refreshAndSaveState,
      onTitleChanged: _updatePaperTitle,
      onCreatePaper: actionSender == null
          ? _createPaper
          : (type, {sourcePaper}) => actionSender(
                type == PaperTypes.note
                    ? PaperWindowActionKinds.createNote
                    : PaperWindowActionKinds.createTodo,
              ),
      onOpen: actionSender == null
          ? _openPaper
          : (target) => actionSender(
                PaperWindowActionKinds.openPaper,
                value: target.id,
              ),
      onOpenLinkedNote: actionSender == null
          ? _openLinkedNote
          : (note, anchorPaper) => actionSender(
                PaperWindowActionKinds.openPaper,
                value: note.id,
              ),
      onRunScriptCapsule: actionSender == null
          ? _runScriptCapsule
          : (_) => actionSender(PaperWindowActionKinds.runScriptCapsule),
      onOpenExternalMarkdown: actionSender == null
          ? _openNoteMarkdownExternally
          : (_) => actionSender(PaperWindowActionKinds.openExternalMarkdown),
      onOpenUri: actionSender == null
          ? _openUri
          : (uri) => actionSender(
                PaperWindowActionKinds.openUri,
                value: uri,
              ),
      onHide: _hidePaper,
      onDelete: (paper) => _deletePaper(paper),
      onTodoItemDeleted: _markTodoItemDeleted,
      onTodoItemRestored: _clearTodoItemDeleted,
      onTodoReminderReset: _resetTodoReminder,
      onSetAlwaysOnTop: _setPaperAlwaysOnTop,
      onSetPinnedToDesktop: _setPaperPinnedToDesktop,
      onSurfaceChanged: _updatePaperSurface,
      onCaptureBounds: _capturePaperBounds,
      standaloneSurface: widget.paperWindowMode,
    );
  }

  Future<void> _createPaper(String type, {PaperData? sourcePaper}) async {
    PaperData? paper;
    setState(() {
      paper = controller.tryCreatePaper(type, sourcePaper: sourcePaper);
    });
    final createdPaper = paper;
    if (createdPaper == null) {
      _showPaperLimitSnackBar();
      return;
    }
    await controller.showPaper(createdPaper);
    await _saveState();
  }

  void _showPaperLimitSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.get(PaperTodoStringKeys.paperLimitReached),
        ),
      ),
    );
  }

  bool _collapseAllActiveFor(PaperData? surfacePaper) {
    if (!controller.state.useCapsuleMode ||
        !controller.state.useCapsuleCollapseAll) {
      return false;
    }
    return surfacePaper == null
        ? controller.state.capsuleCollapseAllActive
        : controller.state.isCapsuleCollapseAllActiveFor(surfacePaper);
  }

  Future<void> _toggleCollapseAll([PaperData? paper]) async {
    setState(() {
      controller.state.toggleCapsuleCollapseAllFor(paper);
    });
    await controller.refreshPaperSurfaces();
    await _saveState();
  }

  Future<void> _saveState({
    bool scheduleLocalEditSync = true,
    bool rebuildTrayMenu = true,
    bool preserveExistingPendingOperationBatch = true,
  }) async {
    AppState? beforeState;
    final saveLocalEditSyncGeneration = _localEditSyncGeneration;
    _saveQueue = _saveQueue.catchError((_) {}).then((_) async {
      try {
        final loadedState = await widget.store.load();
        beforeState = _stateSnapshot(loadedState);
      } catch (_) {
        beforeState = null;
      }
      final localBeforeState = beforeState;
      if (localBeforeState != null) {
        final existingBatch = localBeforeState.sync.pendingOperationBatch;
        controller.state.sync.pendingOperationBatch =
            preserveExistingPendingOperationBatch
                ? existingBatch?.copy()
                : null;
        if (scheduleLocalEditSync && !_isSettingsOpen && _canRunAutoSync()) {
          try {
            final preparedState =
                await widget.syncService.preparePendingLocalOperationBatch(
              beforeState: localBeforeState,
              afterState: controller.state,
              store: widget.store,
            );
            controller.state.sync.pendingOperationBatch =
                preparedState.sync.pendingOperationBatch?.copy();
          } catch (_) {
            controller.state.sync.pendingOperationBatch =
                preserveExistingPendingOperationBatch
                    ? existingBatch?.copy()
                    : null;
          }
        }
      }
      await widget.store.save(controller.state);
      if (rebuildTrayMenu) {
        await _rebuildTrayMenu();
      }
      _refreshSurfaceVisibilitySnapshot();
    });
    await _saveQueue;
    final localBeforeState = beforeState;
    if (scheduleLocalEditSync &&
        localBeforeState != null &&
        saveLocalEditSyncGeneration == _localEditSyncGeneration &&
        !_isSettingsOpen) {
      _scheduleLocalEditSync(
        beforeState: localBeforeState,
        afterState: _stateSnapshot(controller.state),
      );
    }
  }

  Future<void> _refreshAndSaveState() async {
    if (mounted) {
      setState(() {});
    }
    await _saveState();
  }

  Future<void> _updatePaperTitle(PaperData paper) async {
    if (mounted) {
      setState(() {});
    }
    _titleSurfaceDebounce?.cancel();
    _titleSurfaceDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(controller.updatePaperSurface(paper));
    });
    await _saveState();
  }

  Future<void> _deletePaper(PaperData paper, {bool confirm = true}) async {
    if (confirm) {
      final confirmed = await _confirmDeletePaper(paper);
      if (!confirmed) {
        return;
      }
    }
    final removedIndex = controller.state.papers.indexWhere(
      (candidate) => candidate.id == paper.id,
    );
    if (removedIndex < 0) {
      return;
    }
    final removedPaper = PaperData.fromJson(paper.toJson());
    final detachedLinks = <_LinkedNoteRestore>[];
    PaperData? defaultPaper;
    if (removedPaper.isTodo) {
      _clearTodoReminderStateForItems(
        removedPaper.items,
        hideActiveSnackBar: true,
      );
    }
    setState(() {
      controller.state.sync
          .markPaperDeleted(removedPaper.id, DateTime.now().toUtc());
      controller.state.papers.removeAt(removedIndex);
      if (_surfacePaperId == removedPaper.id) {
        _surfacePaperId = null;
      }
      if (removedPaper.isNote) {
        for (final todoPaper in controller.state.papers) {
          if (!todoPaper.isTodo) {
            continue;
          }
          for (final item in todoPaper.items) {
            if (item.linkedNoteId == removedPaper.id) {
              detachedLinks.add(
                _LinkedNoteRestore(
                  paperId: todoPaper.id,
                  itemId: item.id,
                  noteId: removedPaper.id,
                ),
              );
              item.linkedNoteId = null;
            }
          }
        }
      }
      if (controller.state.papers.isEmpty) {
        defaultPaper = controller.tryCreatePaper(PaperTypes.todo);
      }
    });
    await controller.hidePaper(paper);
    final createdDefaultPaper = defaultPaper;
    if (createdDefaultPaper != null) {
      await controller.showPaper(createdDefaultPaper);
    }
    unawaited(_saveState());
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.format(
            PaperTodoStringKeys.paperDeleted,
            [_displayTitle(removedPaper)],
          ),
        ),
        action: SnackBarAction(
          label: strings.get(PaperTodoStringKeys.actionUndo),
          onPressed: () => unawaited(
            _undoDeletePaper(
              restoredPaper: removedPaper,
              targetIndex: removedIndex,
              detachedLinks: detachedLinks,
              fallbackPaperIdToRemove: createdDefaultPaper?.id,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _undoDeletePaper({
    required PaperData restoredPaper,
    required int targetIndex,
    required List<_LinkedNoteRestore> detachedLinks,
    String? fallbackPaperIdToRemove,
  }) async {
    if (controller.state.papers.any((paper) => paper.id == restoredPaper.id)) {
      return;
    }
    PaperData? fallbackPaperToHide;
    final fallbackDeletedAtUtc = DateTime.now().toUtc();
    setState(() {
      final fallbackPaperId = fallbackPaperIdToRemove;
      if (fallbackPaperId != null) {
        final fallbackIndex = controller.state.papers.indexWhere(
          (paper) => paper.id == fallbackPaperId,
        );
        if (fallbackIndex >= 0) {
          final fallbackPaper = controller.state.papers[fallbackIndex];
          if (_isTemporaryDefaultTodoPaper(fallbackPaper)) {
            fallbackPaperToHide = fallbackPaper;
            controller.state.papers.removeAt(fallbackIndex);
            controller.state.sync.markPaperDeleted(
              fallbackPaper.id,
              fallbackDeletedAtUtc,
            );
            _surfaceVisibilityByPaperId.remove(fallbackPaper.id);
            if (_surfacePaperId == fallbackPaper.id) {
              _surfacePaperId = null;
            }
          }
        }
      }
      final insertIndex = targetIndex
          .clamp(
            0,
            controller.state.papers.length,
          )
          .toInt();
      controller.state.sync.clearPaperDeleted(restoredPaper.id);
      controller.state.papers.insert(insertIndex, restoredPaper);
      for (final link in detachedLinks) {
        _restoreLinkedNote(link);
      }
    });
    final removedFallbackPaper = fallbackPaperToHide;
    if (removedFallbackPaper != null && removedFallbackPaper.isVisible) {
      await controller.hidePaper(removedFallbackPaper);
    }
    if (restoredPaper.isVisible) {
      await controller.showPaper(restoredPaper);
    }
    await _saveState();
  }

  bool _isTemporaryDefaultTodoPaper(PaperData paper) {
    if (!paper.isTodo ||
        paper.alwaysOnTop ||
        paper.isCollapsed ||
        paper.isPinnedToDesktop ||
        (paper.textZoom - 1).abs() > 0.001 ||
        paper.content.isNotEmpty ||
        paper.noteCanvasElements.isNotEmpty ||
        paper.extra.isNotEmpty ||
        paper.items.length != 1) {
      return false;
    }
    final title = PaperTitles.cleanCustomTitle(paper.title);
    if (!title.startsWith('Todo')) {
      return false;
    }
    final number = int.tryParse(title.substring('Todo'.length));
    return number != null &&
        number > 0 &&
        _isTemporaryDefaultTodoItem(paper.items.single);
  }

  bool _isTemporaryDefaultTodoItem(PaperItem item) {
    return item.text.isEmpty &&
        !item.done &&
        item.order == 0 &&
        item.todoColumnCount == 1 &&
        item.todoExtraColumns.every((value) => value.isEmpty) &&
        item.todoColumnWidths.every((width) => (width - 1).abs() <= 0.001) &&
        item.linkedNoteId == null &&
        item.dueAtLocal == null &&
        item.reminderIntervalValue == null &&
        item.reminderIntervalUnit == null &&
        item.extra.isEmpty;
  }

  void _markTodoItemDeleted(PaperData paper, PaperItem item) {
    _resetTodoReminder(item);
    controller.state.sync.markTodoItemDeleted(
      paper.id,
      item.id,
      DateTime.now().toUtc(),
    );
  }

  void _resetTodoReminder(PaperItem item) {
    _clearTodoReminderStateForItems([item], hideActiveSnackBar: true);
  }

  void _clearTodoItemDeleted(PaperData paper, PaperItem item) {
    controller.state.sync.clearTodoItemDeleted(paper.id, item.id);
  }

  Future<void> _setPaperAlwaysOnTop(PaperData paper, bool enabled) async {
    setState(() => controller.setPaperAlwaysOnTop(paper, enabled));
    await controller.updatePaperSurface(paper);
    await _saveState();
  }

  Future<void> _setPaperPinnedToDesktop(PaperData paper, bool pinned) async {
    setState(() => controller.setPaperPinnedToDesktop(paper, pinned));
    await controller.updatePaperSurface(paper);
    await _saveState();
  }

  Future<void> _hidePaper(PaperData paper) async {
    final hideFuture = controller.hidePaper(paper);
    setState(() {
      if (_surfacePaperId == paper.id) {
        _surfacePaperId = null;
      }
    });
    await hideFuture;
    await _saveState();
  }

  Future<void> _openPaper(PaperData paper) async {
    setState(() {
      paper.isVisible = true;
      _surfacePaperId = paper.id;
    });
    await controller.showPaper(paper);
    await _saveState();
  }

  Future<void> _openLinkedNote(PaperData note, PaperData anchorPaper) async {
    setState(() {
      note.isVisible = true;
      note.isCollapsed = false;
      _surfacePaperId = note.id;
    });
    await controller.openLinkedNote(note, anchorPaper: anchorPaper);
    await _saveState();
  }

  Future<void> _openNoteMarkdownExternally(PaperData paper) async {
    if (!paper.isNote) {
      return;
    }
    try {
      final file = await _writeExternalMarkdownFile(paper);
      await controller.openExternalFile(file.path);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.format(PaperTodoStringKeys.openedMarkdownFile, [file.path]),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.format(
              PaperTodoStringKeys.externalMarkdownOpenFailed,
              [_readableFailureMessage(error, strings: strings)],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _runScriptCapsule(ScriptCapsuleSpec spec) async {
    try {
      await controller.runScriptCapsule(spec);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.format(
              PaperTodoStringKeys.scriptCapsuleFailed,
              [_readableFailureMessage(error, strings: strings)],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openUri(String uri) async {
    final localPath = _normalizeMarkdownLocalPath(uri);
    if (localPath != null) {
      try {
        await controller.openExternalFile(localPath);
      } catch (error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.format(
                PaperTodoStringKeys.openLinkFailed,
                [_readableFailureMessage(error, strings: strings)],
              ),
            ),
          ),
        );
      }
      return;
    }

    final normalizedUri = _normalizeExternalUri(uri);
    if (normalizedUri == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.get(PaperTodoStringKeys.openLinkUnsupported),
          ),
        ),
      );
      return;
    }
    try {
      await controller.openUri(normalizedUri);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.format(
              PaperTodoStringKeys.openLinkFailed,
              [_readableFailureMessage(error, strings: strings)],
            ),
          ),
        ),
      );
    }
  }

  Future<File> _writeExternalMarkdownFile(PaperData paper) async {
    final documentsPath = await controller.documentsDirectoryPath();
    final directory = Directory(
      p.join(documentsPath, 'RePaperTodo', 'exports'),
    );
    directory.createSync(recursive: true);
    _cleanupOldExternalMarkdownExports(directory);
    final safePaperId = _safeFilename(paper.id);
    final paperId = safePaperId.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toRadixString(16)
        : safePaperId;
    final file = File(
      p.join(
        directory.path,
        'paper-$paperId${controller.state.externalMarkdownExtension}',
      ),
    );
    file.writeAsStringSync(paper.content, flush: true);
    return file;
  }

  void _cleanupOldExternalMarkdownExports(Directory directory) {
    final cutoff = DateTime.now().subtract(_externalMarkdownExportRetention);
    try {
      for (final entity in directory.listSync(followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        if (!p.basename(entity.path).startsWith('paper-')) {
          continue;
        }
        if (entity.lastModifiedSync().isBefore(cutoff)) {
          entity.deleteSync();
        }
      }
    } catch (_) {
      // Export cleanup is opportunistic; opening the current note should win.
    }
  }

  String _safeFilename(String value) {
    final safe =
        value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F\x7F-\x9F]'), '_').trim();
    if (safe.length <= _maxExternalMarkdownPaperIdFileNameLength) {
      return safe;
    }
    return '${safe.substring(0, 72)}_${safe.substring(safe.length - 23)}';
  }

  Future<void> _showHiddenPapers() async {
    final hiddenPapers =
        controller.state.papers.where((paper) => !paper.isVisible).toList();
    setState(() {
      for (final paper in hiddenPapers) {
        paper.isVisible = true;
      }
    });
    for (final paper in hiddenPapers) {
      await controller.showPaper(paper);
    }
    await _saveState();
  }

  Future<void> _handlePaperOpenRequest(String paperId) async {
    if (_exitCommandFuture != null) {
      return;
    }
    final paperIndex = controller.state.papers.indexWhere(
      (paper) => paper.id == paperId,
    );
    if (paperIndex < 0) {
      return;
    }
    final paper = controller.state.papers[paperIndex];
    if (paper.isVisible) {
      await _hidePaper(paper);
    } else {
      await _openPaper(paper);
    }
  }

  Future<void> _handlePaperDeleteRequest(String paperId) async {
    if (_exitCommandFuture != null) {
      return;
    }
    final paperIndex = controller.state.papers.indexWhere(
      (paper) => paper.id == paperId,
    );
    if (paperIndex < 0) {
      return;
    }
    await _deletePaper(controller.state.papers[paperIndex], confirm: false);
  }

  Future<void> _handleStartupCommand(StartupCommand command) async {
    if (command.kind == StartupCommandKind.none) {
      return;
    }
    if (command.kind == StartupCommandKind.exit) {
      _exitCommandFuture ??= _runExitStartupCommand(command);
      await _exitCommandFuture;
      if (mounted) {
        setState(() {});
      }
      return;
    }
    if (_exitCommandFuture != null) {
      return;
    }
    if (command.kind == StartupCommandKind.settings) {
      await _openSettings();
      return;
    }
    await controller.executeStartupCommand(command);
    if (mounted) {
      setState(() {
        _refreshSurfaceVisibilitySnapshot();
      });
    }
    await _rebuildTrayMenu();
    await _saveState();
  }

  Future<void> _runExitStartupCommand(StartupCommand command) async {
    await _saveAndSyncBeforeExit();
    await controller.executeStartupCommand(command);
  }

  Future<void> _saveAndSyncBeforeExit() async {
    _surfaceSaveDebounce?.cancel();
    _surfaceSaveDebounce = null;
    await _saveState();
    _localEditSyncDebounce?.cancel();
    _localEditSyncDebounce = null;
    if (_isSyncing) {
      await _activeSyncFuture;
    }
    await _uploadLocalEditsThenSync();
  }

  void _handleSurfaceUpdate(PaperData paper) {
    if (!mounted) {
      return;
    }
    if (_exitCommandFuture != null && !paper.isVisible) {
      return;
    }
    final paperIndex = controller.state.papers.indexWhere(
      (candidate) => candidate.id == paper.id,
    );
    if (paperIndex < 0) {
      _surfaceVisibilityByPaperId.remove(paper.id);
      return;
    }
    final statePaper = controller.state.papers[paperIndex];
    final visibilityChanged = _rememberSurfaceVisibility(paper);
    setState(() => _applyPlatformSurfaceUpdate(statePaper, paper));
    if (visibilityChanged) {
      unawaited(_rebuildTrayMenu());
    }
    _surfaceSaveDebounce?.cancel();
    _surfaceSaveDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_saveState(rebuildTrayMenu: false));
    });
  }

  void _handlePaperEdit(PaperData paper) {
    if (!mounted || _exitCommandFuture != null) {
      return;
    }
    final paperIndex = controller.state.papers.indexWhere(
      (candidate) => candidate.id == paper.id,
    );
    if (paperIndex < 0) {
      return;
    }
    final wasVisible = controller.state.papers[paperIndex].isVisible;
    final changedPaper = PaperData.fromJson(paper.toJson());
    setState(() => controller.state.papers[paperIndex] = changedPaper);
    if (wasVisible && !changedPaper.isVisible) {
      unawaited(controller.hidePaper(changedPaper));
    } else if (!wasVisible && changedPaper.isVisible) {
      unawaited(controller.showPaper(changedPaper));
    } else {
      unawaited(controller.updatePaperSurface(changedPaper));
    }
    unawaited(_rebuildTrayMenu());
    unawaited(_saveState(rebuildTrayMenu: false));
  }

  void _handlePaperWindowAction(PaperWindowActionRequest request) {
    if (!mounted || _exitCommandFuture != null) {
      return;
    }
    Timer.run(() => _dispatchPaperWindowAction(request));
  }

  void _dispatchPaperWindowAction(PaperWindowActionRequest request) {
    if (!mounted || _exitCommandFuture != null) {
      return;
    }
    final paper = controller.state.papers
        .where((candidate) => candidate.id == request.paperId)
        .firstOrNull;
    if (paper == null) {
      return;
    }
    switch (request.kind) {
      case PaperWindowActionKinds.openPaper:
        final target = controller.state.papers
            .where((candidate) => candidate.id == request.value)
            .firstOrNull;
        if (target != null) {
          unawaited(_openPaper(target));
        }
      case PaperWindowActionKinds.createTodo:
        unawaited(_createPaper(PaperTypes.todo, sourcePaper: paper));
      case PaperWindowActionKinds.createNote:
        unawaited(_createPaper(PaperTypes.note, sourcePaper: paper));
      case PaperWindowActionKinds.openExternalMarkdown:
        if (paper.isNote) {
          unawaited(_openNoteMarkdownExternally(paper));
        }
      case PaperWindowActionKinds.runScriptCapsule:
        final spec =
            paper.isNote ? ScriptCapsuleSpec.tryParse(paper.content) : null;
        if (spec != null) {
          unawaited(_runScriptCapsule(spec));
        }
      case PaperWindowActionKinds.openUri:
        unawaited(_openUri(request.value));
      case PaperWindowActionKinds.openReminderPaper:
        unawaited(_openTodoReminderPaper(paper));
      case PaperWindowActionKinds.toggleCollapseAll:
        unawaited(_toggleCollapseAll(paper));
      case PaperWindowActionKinds.collapsePaper:
        if (!paper.isCollapsed) {
          setState(() {
            paper.isCollapsed = true;
            controller.state.normalize();
          });
          unawaited(controller.refreshPaperSurfaces());
          unawaited(_saveState());
        }
      case PaperWindowActionKinds.expandPaper:
        if (paper.isCollapsed) {
          setState(() {
            paper.isCollapsed = false;
            controller.state.normalize();
          });
          unawaited(controller.refreshPaperSurfaces());
          unawaited(_saveState());
        }
    }
  }

  void _handleCapsuleDrop(CapsuleDropRequest request) {
    if (!mounted || _exitCommandFuture != null) {
      return;
    }
    final paper = controller.state.papers
        .where((candidate) => candidate.id == request.paperId)
        .firstOrNull;
    if (paper == null ||
        !request.dropTop.isFinite ||
        !request.workAreaTop.isFinite) {
      return;
    }
    setState(() {
      if (request.isMasterCapsule) {
        final queueKey = controller.state.capsuleQueueKeyFor(paper);
        controller.state.deepCapsuleQueueStartTopMargins[queueKey] =
            (request.dropTop - request.workAreaTop)
                .clamp(8.0, 10000.0)
                .toDouble();
      } else {
        paper
          ..capsuleMonitorDeviceName = request.monitorDeviceName.trim()
          ..capsuleSide = DeepCapsuleSides.normalize(request.side);
        _reorderPaperInCapsuleQueue(
          paper,
          dropTop: request.dropTop,
          workAreaTop: request.workAreaTop,
        );
      }
      controller.state.normalize();
    });
    unawaited(controller.refreshPaperSurfaces());
    unawaited(_saveState());
  }

  void _reorderPaperInCapsuleQueue(
    PaperData paper, {
    required double dropTop,
    required double workAreaTop,
  }) {
    final state = controller.state;
    final queueKey = state.capsuleQueueKeyFor(paper);
    final startTop = state.deepCapsuleQueueStartTopMargins[queueKey] ??
        state.deepCapsuleStartTopMargin;
    const slotHeight = 50.0;
    final masterOffset = state.useCapsuleCollapseAll ? 1 : 0;
    final desiredIndex =
        (((dropTop - workAreaTop - startTop) / slotHeight).round() -
                masterOffset)
            .clamp(0, state.papers.length)
            .toInt();
    final oldIndex = state.papers.indexOf(paper);
    if (oldIndex < 0) {
      return;
    }
    state.papers.removeAt(oldIndex);
    final queuePeers = state.papers
        .where((candidate) =>
            _paperOccupiesDeepCapsuleQueue(candidate) &&
            state.capsuleQueueKeyFor(candidate) == queueKey)
        .toList();
    if (queuePeers.isEmpty) {
      state.papers.insert(oldIndex.clamp(0, state.papers.length), paper);
      return;
    }
    final queueIndex = desiredIndex.clamp(0, queuePeers.length).toInt();
    final insertionIndex = queueIndex >= queuePeers.length
        ? state.papers.indexOf(queuePeers.last) + 1
        : state.papers.indexOf(queuePeers[queueIndex]);
    state.papers.insert(insertionIndex.clamp(0, state.papers.length), paper);
  }

  bool _paperOccupiesDeepCapsuleQueue(PaperData paper) {
    final state = controller.state;
    if (!paper.isVisible ||
        !state.useCapsuleMode ||
        !state.useDeepCapsuleMode) {
      return false;
    }
    if (state.enableTodoNoteLinks &&
        state.hideLinkedNotesFromCapsules &&
        paper.isNote &&
        state.papers
            .where((candidate) => candidate.isTodo)
            .expand((candidate) => candidate.items)
            .any((item) => item.linkedNoteId == paper.id)) {
      return false;
    }
    return paper.isCollapsed ||
        paper.isPinnedToDesktop ||
        state.showDeepCapsuleWhileExpanded;
  }

  void _applyPlatformSurfaceUpdate(PaperData target, PaperData source) {
    target
      ..x = _platformSurfaceCoordinate(source.x, fallback: target.x)
      ..y = _platformSurfaceCoordinate(source.y, fallback: target.y)
      ..width = _platformSurfaceDimension(
        source.width,
        fallback: target.width,
        min: PaperLayoutDefaults.minWidth,
      )
      ..height = _platformSurfaceDimension(
        source.height,
        fallback: target.height,
        min: PaperLayoutDefaults.minHeight,
      )
      ..isVisible = source.isVisible;
  }

  double _platformSurfaceCoordinate(double value, {required double fallback}) {
    if (value.isFinite) {
      return value;
    }
    return fallback.isFinite ? fallback : 120;
  }

  double _platformSurfaceDimension(
    double value, {
    required double fallback,
    required double min,
  }) {
    if (value.isFinite && value >= min) {
      return value;
    }
    if (fallback.isFinite && fallback >= min) {
      return fallback;
    }
    return min;
  }

  bool _rememberSurfaceVisibility(PaperData paper) {
    final previous = _surfaceVisibilityByPaperId[paper.id];
    _surfaceVisibilityByPaperId[paper.id] = paper.isVisible;
    return previous != null && previous != paper.isVisible;
  }

  void _refreshSurfaceVisibilitySnapshot() {
    _surfaceVisibilityByPaperId
      ..clear()
      ..addEntries(
        controller.state.papers.map(
          (paper) => MapEntry(paper.id, paper.isVisible),
        ),
      );
  }

  Future<void> _rebuildTrayMenu() async {
    final labels = _cachedTrayMenuLabels ?? _trayMenuLabelsFor(strings);
    await controller.rebuildTrayMenu(labels: labels);
  }

  TrayMenuLabels _trayMenuLabelsFor(PaperTodoStrings strings) {
    return TrayMenuLabels(
      newTodo: strings.get(PaperTodoStringKeys.trayNewTodo),
      newNote: strings.get(PaperTodoStringKeys.trayNewNote),
      settings: strings.get(PaperTodoStringKeys.traySettings),
      showAll: strings.get(PaperTodoStringKeys.trayShowAll),
      hideAll: strings.get(PaperTodoStringKeys.trayHideAll),
      toggleAll: strings.get(PaperTodoStringKeys.trayToggleAll),
      papers: strings.get(PaperTodoStringKeys.trayPapers),
      deletePaper: strings.get(PaperTodoStringKeys.trayDeletePaper),
      deleteConfirmTitle:
          strings.get(PaperTodoStringKeys.trayDeleteConfirmTitle),
      deleteConfirmMessage:
          strings.get(PaperTodoStringKeys.trayDeleteConfirmMessage),
      inlineConfirmDelete:
          strings.get(PaperTodoStringKeys.trayInlineConfirmDelete),
      inlineConfirmAction:
          strings.get(PaperTodoStringKeys.trayInlineConfirmAction),
      cancel: strings.get(PaperTodoStringKeys.actionCancel),
      exit: strings.get(PaperTodoStringKeys.trayExit),
      todoPaper: strings.get(PaperTodoStringKeys.trayTodoPaper),
      notePaper: strings.get(PaperTodoStringKeys.trayNotePaper),
      scriptPaper: strings.get(PaperTodoStringKeys.trayScriptPaper),
      hidden: strings.get(PaperTodoStringKeys.trayHidden),
      collapsed: strings.get(PaperTodoStringKeys.trayCollapsed),
      desktop: strings.get(PaperTodoStringKeys.trayDesktop),
      topmost: strings.get(PaperTodoStringKeys.trayTopmost),
    );
  }

  Future<void> _replaceStateAndApplyPlatform(
    AppState state, {
    bool invalidatePendingLocalEdits = false,
  }) async {
    final previousReminderCadence = _todoReminderCadence(controller.state);
    if (invalidatePendingLocalEdits) {
      _invalidatePendingLocalEditSyncForStateReplacement();
    }
    setState(() {
      controller.replaceState(state);
      _reconcileSurfacePaperAfterReplacement();
      _refreshSurfaceVisibilitySnapshot();
    });
    if (previousReminderCadence != _todoReminderCadence(controller.state)) {
      _lastTodoReminderAt.clear();
    }
    _reconcileTodoReminderStateAfterReplacement();
    await controller.applyCurrentStateToPlatform();
  }

  Future<void> _updatePaperSurface(PaperData paper) async {
    setState(() {});
    await controller.updatePaperSurface(paper);
  }

  Future<void> _capturePaperBounds(PaperData paper) async {
    await controller.capturePaperSurfaceBounds(paper);
    setState(() {});
    await _saveState();
  }

  Future<void> _syncNow({bool showMessage = true}) {
    if (_isSyncing) {
      return Future<void>.value();
    }
    if (!mounted) {
      return Future<void>.value();
    }
    final syncFuture = _runSyncNow(showMessage: showMessage);
    _activeSyncFuture = syncFuture;
    return syncFuture.whenComplete(() {
      if (identical(_activeSyncFuture, syncFuture)) {
        _activeSyncFuture = null;
      }
    });
  }

  Future<void> _runSyncNow({required bool showMessage}) async {
    setState(() => _isSyncing = true);
    _localEditSyncDebounce?.cancel();
    _localEditSyncDebounce = null;
    try {
      if (_canRunAutoSync()) {
        final uploadedPendingEdits = await _uploadPendingLocalEdits(
          reportFailures: showMessage,
        );
        if (!uploadedPendingEdits) {
          return;
        }
      } else {
        _pendingLocalEditBaseState = null;
        _pendingLocalEditLatestState = null;
      }

      if (!mounted) {
        return;
      }
      final result = await widget.syncService.syncAndMergeNow(
        localState: controller.state,
        store: widget.store,
      );
      if (!mounted) {
        return;
      }
      await _replaceStateAndApplyPlatform(result.state);
      _restartAutoSyncTimer();
      if (showMessage && mounted) {
        _showSyncSnackBar(
          message: _syncRunMessage(result),
          status: result.syncResult.status,
        );
      }
    } catch (error) {
      if (!mounted || !showMessage) {
        return;
      }
      _showSyncFailureSnackBar(error);
    } finally {
      final shouldRunQueuedSilentSync =
          _queuedSilentSync && mounted && _canRunAutoSync();
      _queuedSilentSync = false;
      if (mounted) {
        setState(() => _isSyncing = false);
      }
      if (shouldRunQueuedSilentSync) {
        unawaited(_syncSilentlyIfConfigured());
      }
    }
  }

  Future<void> _openRecoverySnapshots() async {
    final sync = controller.state.sync;
    if (!sync.enabled) {
      _showSyncSnackBar(
        message: _syncMessage(
          const AppSyncResult(status: AppSyncStatus.disabled),
        ),
        status: AppSyncStatus.disabled,
      );
      return;
    }
    if (sync.provider != SyncProviderIds.webDav ||
        !sync.webDav.isSecurelyConfigured) {
      _showSyncSnackBar(
        message: _syncMessage(
          const AppSyncResult(status: AppSyncStatus.configurationMissing),
        ),
        status: AppSyncStatus.configurationMissing,
      );
      return;
    }
    final snapshot = await showDialog<WebDavSnapshotRecord>(
      context: context,
      builder: (context) {
        return _RecoverySnapshotsDialog(
          loadSnapshots: () => widget.syncService.listRecoverySnapshots(
            localState: controller.state,
            store: widget.store,
          ),
          onOpenSettings: () {
            Navigator.of(context).pop();
            if (mounted) {
              unawaited(_openSettings());
            }
          },
        );
      },
    );
    if (!mounted || snapshot == null) {
      return;
    }
    final confirmed = await _confirmRestoreSnapshot(snapshot);
    if (!mounted || !confirmed) {
      return;
    }
    await _restoreRecoverySnapshot(snapshot);
  }

  Future<bool> _confirmRestoreSnapshot(WebDavSnapshotRecord snapshot) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            final strings = PaperTodoStringsScope.of(context);
            return AlertDialog(
              title: Text(
                strings.get(PaperTodoStringKeys.dialogRestoreSnapshot),
              ),
              content: Text(_snapshotSummary(snapshot)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(strings.get(PaperTodoStringKeys.actionCancel)),
                ),
                FilledButton.icon(
                  key: const ValueKey('confirm-restore-snapshot'),
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.restore_outlined),
                  label: Text(strings.get(PaperTodoStringKeys.actionRestore)),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _restoreRecoverySnapshot(WebDavSnapshotRecord snapshot) async {
    setState(() => _isSyncing = true);
    try {
      final result = await widget.syncService.restoreRecoverySnapshot(
        localState: controller.state,
        store: widget.store,
        snapshotPath: snapshot.path,
      );
      if (!mounted) {
        return;
      }
      if (result.state != null) {
        await _replaceStateAndApplyPlatform(
          result.state!,
          invalidatePendingLocalEdits: true,
        );
      }
      if (!mounted) {
        return;
      }
      _showSyncSnackBar(
        message: _syncMessage(result),
        status: result.status,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showRestoreFailureSnackBar(snapshot, error);
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _openSettings() async {
    final hadPendingLocalEditSync = _pendingLocalEditBaseState != null &&
        _pendingLocalEditLatestState != null;
    _localEditSyncDebounce?.cancel();
    _localEditSyncDebounce = null;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    _startSettingsDeferredAutoSyncTimer();
    final previousSyncJson = _syncUserConfigurationJson(controller.state.sync);
    final previousSyncTargetJson =
        _syncTargetConfigurationJson(controller.state.sync);
    final previousSyncEnabled = controller.state.sync.enabled;
    _isSettingsOpen = true;
    final previousUsePersistentPowerShellProcess =
        controller.state.usePersistentPowerShellProcess;
    final previousPreferPowerShell7 = controller.state.preferPowerShell7;
    final previousHideScriptRunWindow = controller.state.hideScriptRunWindow;
    final previousUseTodoReminderInterval =
        controller.state.useTodoReminderInterval;
    final previousTodoReminderIntervalValue =
        controller.state.todoReminderIntervalValue;
    final previousTodoReminderIntervalUnit =
        controller.state.todoReminderIntervalUnit;
    final previousCapsuleSettings = (
      useCapsuleMode: controller.state.useCapsuleMode,
      useDeepCapsuleMode: controller.state.useDeepCapsuleMode,
      useCapsuleCollapseAll: controller.state.useCapsuleCollapseAll,
      capsuleCollapseAllActive: controller.state.capsuleCollapseAllActive,
      deepCapsuleSide: controller.state.deepCapsuleSide,
      deepCapsuleStartTopMargin: controller.state.deepCapsuleStartTopMargin,
      deepCapsuleMonitorDeviceName:
          controller.state.deepCapsuleMonitorDeviceName,
      showDeepCapsuleWhileExpanded:
          controller.state.showDeepCapsuleWhileExpanded,
      collapseExpandedDeepCapsuleOnClick:
          controller.state.collapseExpandedDeepCapsuleOnClick,
      hideDeepCapsulesWhenCovered: controller.state.hideDeepCapsulesWhenCovered,
      hideDeepCapsulesWhenFullscreen:
          controller.state.hideDeepCapsulesWhenFullscreen,
    );
    final result = await showSyncSettingsDialog(
      context: context,
      initialSettings: controller.state.sync,
      initialTheme: controller.state.theme,
      initialColorScheme: controller.state.colorScheme,
      initialCustomThemeColorHex: controller.state.customThemeColorHex,
      initialMarkdownRenderMode: controller.state.markdownRenderMode,
      initialTodoVisualSize: controller.state.todoVisualSize,
      initialUiFontPreset: controller.state.uiFontPreset,
      initialSystemFontFamilyName: controller.state.systemFontFamilyName,
      initialExternalMarkdownExtension:
          controller.state.externalMarkdownExtension,
      initialZoom: controller.state.zoom,
      initialMaxTitleLength: controller.state.maxTitleLength,
      initialEnableToolTips: controller.state.enableToolTips,
      initialEnableAnimations: controller.state.enableAnimations,
      initialTodoLineSpacing: controller.state.todoLineSpacing,
      initialNoteLineSpacing: controller.state.noteLineSpacing,
      initialShowTodoDueRelativeTime: controller.state.showTodoDueRelativeTime,
      initialTodoDueYearDisplayMode: controller.state.todoDueYearDisplayMode,
      initialUseTodoReminderInterval: controller.state.useTodoReminderInterval,
      initialTodoReminderIntervalValue:
          controller.state.todoReminderIntervalValue,
      initialTodoReminderIntervalUnit:
          controller.state.todoReminderIntervalUnit,
      initialTodoReminderScope: controller.state.todoReminderScope,
      initialTodoReminderBubbleDurationSeconds:
          controller.state.todoReminderBubbleDurationSeconds,
      initialShowTopBarNewTodoButton: controller.state.showTopBarNewTodoButton,
      initialShowTopBarNewNoteButton: controller.state.showTopBarNewNoteButton,
      initialShowTopBarExternalOpenButton:
          controller.state.showTopBarExternalOpenButton,
      initialUseCapsuleMode: controller.state.useCapsuleMode,
      initialUseDeepCapsuleMode: controller.state.useDeepCapsuleMode,
      initialUseCapsuleCollapseAll: controller.state.useCapsuleCollapseAll,
      initialCapsuleCollapseAllActive:
          controller.state.capsuleCollapseAllActive,
      initialDeepCapsuleSide: controller.state.deepCapsuleSide,
      initialDeepCapsuleStartTopMargin:
          controller.state.deepCapsuleStartTopMargin,
      initialDeepCapsuleMonitorDeviceName:
          controller.state.deepCapsuleMonitorDeviceName,
      initialShowDeepCapsuleWhileExpanded:
          controller.state.showDeepCapsuleWhileExpanded,
      initialCollapseExpandedDeepCapsuleOnClick:
          controller.state.collapseExpandedDeepCapsuleOnClick,
      initialHideDeepCapsulesWhenCovered:
          controller.state.hideDeepCapsulesWhenCovered,
      initialHideDeepCapsulesWhenFullscreen:
          controller.state.hideDeepCapsulesWhenFullscreen,
      initialStartAtLogin: controller.state.startAtLogin,
      supportsStartAtLogin: controller.supportsStartupAtLogin,
      supportsHideFromWindowSwitcher:
          controller.supportsWindowSwitcherVisibility,
      supportsFullscreenTopmostMode: controller.supportsFullscreenTopmostMode,
      supportsGlobalHotkeys: controller.supportsGlobalHotkeys,
      supportsScriptCapsules: controller.supportsScriptCapsules,
      initialHideFromWindowSwitcher:
          controller.state.hidePapersFromWindowSwitcher,
      initialFullscreenTopmostMode: controller.state.fullscreenTopmostMode,
      initialPinnedTodoHotKey: controller.state.pinnedTodoHotKey,
      initialPinnedNoteHotKey: controller.state.pinnedNoteHotKey,
      initialRunLinkedScriptCapsulesOnClick:
          controller.state.runLinkedScriptCapsulesOnClick,
      initialUsePersistentPowerShellProcess:
          controller.state.usePersistentPowerShellProcess,
      initialPreferPowerShell7: controller.state.preferPowerShell7,
      initialHideScriptRunWindow: controller.state.hideScriptRunWindow,
      initialEnableTodoNoteLinks: controller.state.enableTodoNoteLinks,
      initialShowLinkedNoteName: controller.state.showLinkedNoteName,
      initialAllowLongLinkedNoteTitles:
          controller.state.allowLongLinkedNoteTitles,
      initialHideLinkedNotesFromCapsules:
          controller.state.hideLinkedNotesFromCapsules,
      initialDataDirectoryPath: p.dirname(widget.store.filePath),
      supportsDataDirectorySelection: controller.supportsDataDirectorySelection,
      selectDataDirectory: controller.chooseDataDirectory,
      loadInstalledFontFamilies: controller.installedFontFamilies,
    );
    try {
      await controller.hideCoordinatorWindow();
    } catch (_) {
      // The settings result is still valid if the native coordinator was
      // already hidden or is being torn down.
    }
    if (result == null) {
      _isSettingsOpen = false;
      _settingsDeferredAutoSyncTimer?.cancel();
      _settingsDeferredAutoSyncTimer = null;
      if (mounted) {
        _restartAutoSyncTimer();
      }
      if (hadPendingLocalEditSync) {
        _reschedulePendingLocalEditSync();
      }
      _runDeferredSettingsSyncIfNeeded();
      return;
    }
    final syncTargetChanged =
        _syncTargetConfigurationJson(result.sync) != previousSyncTargetJson;
    final syncEnabledChanged = result.sync.enabled != previousSyncEnabled;
    final preservePendingOperationBatch =
        !syncTargetChanged && !syncEnabledChanged;
    _copySyncRuntimeMetadata(
      source: controller.state.sync,
      target: result.sync,
      preserveOperationProgress: !syncTargetChanged,
      preservePendingOperationBatch: preservePendingOperationBatch,
    );
    final syncSettingsChanged =
        _syncUserConfigurationJson(result.sync) != previousSyncJson;
    if (syncSettingsChanged) {
      _localEditSyncGeneration += 1;
      _clearPendingLocalEditSync();
    }
    final reminderCadenceChanged = result.useTodoReminderInterval !=
            previousUseTodoReminderInterval ||
        result.todoReminderIntervalValue != previousTodoReminderIntervalValue ||
        result.todoReminderIntervalUnit != previousTodoReminderIntervalUnit;
    final capsuleSettingsChanged = previousCapsuleSettings !=
        (
          useCapsuleMode: result.useCapsuleMode,
          useDeepCapsuleMode: result.useDeepCapsuleMode,
          useCapsuleCollapseAll: result.useCapsuleCollapseAll,
          capsuleCollapseAllActive: result.capsuleCollapseAllActive,
          deepCapsuleSide: result.deepCapsuleSide,
          deepCapsuleStartTopMargin: result.deepCapsuleStartTopMargin,
          deepCapsuleMonitorDeviceName: result.deepCapsuleMonitorDeviceName,
          showDeepCapsuleWhileExpanded: result.showDeepCapsuleWhileExpanded,
          collapseExpandedDeepCapsuleOnClick:
              result.collapseExpandedDeepCapsuleOnClick,
          hideDeepCapsulesWhenCovered: result.hideDeepCapsulesWhenCovered,
          hideDeepCapsulesWhenFullscreen: result.hideDeepCapsulesWhenFullscreen,
        );
    if (reminderCadenceChanged) {
      _lastTodoReminderAt.clear();
    }
    setState(() {
      controller.state.sync = result.sync;
      controller.state.theme = result.theme;
      controller.state.colorScheme = result.colorScheme;
      controller.state.customThemeColorHex = result.customThemeColorHex;
      controller.state.markdownRenderMode = result.markdownRenderMode;
      controller.state.todoVisualSize = result.todoVisualSize;
      controller.state.uiFontPreset = result.uiFontPreset;
      controller.state.systemFontFamilyName = result.systemFontFamilyName;
      controller.state.externalMarkdownExtension =
          result.externalMarkdownExtension;
      controller.state.zoom = result.zoom;
      controller.state.maxTitleLength = result.maxTitleLength;
      controller.state.enableToolTips = result.enableToolTips;
      controller.state.enableAnimations = result.enableAnimations;
      controller.state.todoLineSpacing = result.todoLineSpacing;
      controller.state.noteLineSpacing = result.noteLineSpacing;
      controller.state.showTodoDueRelativeTime = result.showTodoDueRelativeTime;
      controller.state.todoDueYearDisplayMode = result.todoDueYearDisplayMode;
      controller.state.useTodoReminderInterval = result.useTodoReminderInterval;
      controller.state.todoReminderIntervalValue =
          result.todoReminderIntervalValue;
      controller.state.todoReminderIntervalUnit =
          result.todoReminderIntervalUnit;
      controller.state.todoReminderScope = result.todoReminderScope;
      controller.state.todoReminderBubbleDurationSeconds =
          result.todoReminderBubbleDurationSeconds;
      controller.state.showTopBarNewTodoButton = result.showTopBarNewTodoButton;
      controller.state.showTopBarNewNoteButton = result.showTopBarNewNoteButton;
      controller.state.showTopBarExternalOpenButton =
          result.showTopBarExternalOpenButton;
      controller.applyCapsuleSettings(
        useCapsuleMode: result.useCapsuleMode,
        useDeepCapsuleMode: result.useDeepCapsuleMode,
        useCapsuleCollapseAll: result.useCapsuleCollapseAll,
        capsuleCollapseAllActive: result.capsuleCollapseAllActive,
        deepCapsuleSide: result.deepCapsuleSide,
        deepCapsuleStartTopMargin: result.deepCapsuleStartTopMargin,
        deepCapsuleMonitorDeviceName: result.deepCapsuleMonitorDeviceName,
        showDeepCapsuleWhileExpanded: result.showDeepCapsuleWhileExpanded,
        collapseExpandedDeepCapsuleOnClick:
            result.collapseExpandedDeepCapsuleOnClick,
        hideDeepCapsulesWhenCovered: result.hideDeepCapsulesWhenCovered,
        hideDeepCapsulesWhenFullscreen: result.hideDeepCapsulesWhenFullscreen,
      );
      controller.state.startAtLogin = result.startAtLogin;
      controller.state.hidePapersFromWindowSwitcher =
          result.hideFromWindowSwitcher;
      controller.state.fullscreenTopmostMode = result.fullscreenTopmostMode;
      controller.state.pinnedTodoHotKey = result.pinnedTodoHotKey;
      controller.state.pinnedNoteHotKey = result.pinnedNoteHotKey;
      controller.state.runLinkedScriptCapsulesOnClick =
          result.runLinkedScriptCapsulesOnClick;
      controller.state.usePersistentPowerShellProcess =
          result.usePersistentPowerShellProcess;
      controller.state.preferPowerShell7 = result.preferPowerShell7;
      controller.state.hideScriptRunWindow = result.hideScriptRunWindow;
      controller.state.enableTodoNoteLinks = result.enableTodoNoteLinks;
      controller.state.showLinkedNoteName = result.showLinkedNoteName;
      controller.state.allowLongLinkedNoteTitles =
          result.allowLongLinkedNoteTitles;
      controller.state.hideLinkedNotesFromCapsules =
          result.hideLinkedNotesFromCapsules;
    });
    final platformSettingErrors = <String>[];
    Future<void> applyPlatformSetting(
      String labelKey,
      Future<void> Function() action,
    ) async {
      try {
        await action();
      } catch (error) {
        platformSettingErrors.add(
          '${strings.get(labelKey)}: '
          '${_readableFailureMessage(error, strings: strings)}',
        );
      }
    }

    if (controller.supportsDataDirectorySelection) {
      final previousFilePath = widget.store.filePath;
      final previousDirectory = p.dirname(previousFilePath);
      final selectedDirectory = result.dataDirectoryPath.trim();
      if (selectedDirectory.isNotEmpty &&
          p.normalize(selectedDirectory).toLowerCase() !=
              p.normalize(previousDirectory).toLowerCase()) {
        await applyPlatformSetting(
          PaperTodoStringKeys.dataDirectory,
          () async {
            final nextFilePath = p.join(selectedDirectory, 'data.json');
            await widget.store.relocate(nextFilePath, controller.state);
            try {
              await controller.commitDataDirectory(selectedDirectory);
            } catch (_) {
              await widget.store.relocate(previousFilePath, controller.state);
              rethrow;
            }
          },
        );
      }
    }

    if (controller.supportsStartupAtLogin) {
      await applyPlatformSetting(
        PaperTodoStringKeys.platformSettingStartupAtLogin,
        () => controller.setStartupAtLogin(result.startAtLogin),
      );
    }
    await applyPlatformSetting(
      PaperTodoStringKeys.platformSettingWindowSwitcherVisibility,
      () => controller.setHideFromWindowSwitcher(result.hideFromWindowSwitcher),
    );
    await applyPlatformSetting(
      PaperTodoStringKeys.platformSettingFullscreenTopmostMode,
      () => controller.setFullscreenTopmostMode(result.fullscreenTopmostMode),
    );
    await applyPlatformSetting(
      PaperTodoStringKeys.platformSettingGlobalHotkeys,
      controller.registerGlobalHotkeys,
    );
    if (_shouldStopPersistentScriptCapsules(
      previousUsePersistentPowerShellProcess,
      previousPreferPowerShell7,
      previousHideScriptRunWindow,
      result,
    )) {
      await applyPlatformSetting(
        PaperTodoStringKeys.platformSettingScriptCapsuleProcess,
        controller.stopPersistentScriptCapsules,
      );
    }
    if (_shouldPreparePersistentScriptCapsules(
      previousUsePersistentPowerShellProcess,
      previousPreferPowerShell7,
      previousHideScriptRunWindow,
      result,
    )) {
      await applyPlatformSetting(
        PaperTodoStringKeys.platformSettingScriptCapsuleProcess,
        controller.preparePersistentScriptCapsules,
      );
    }
    if (capsuleSettingsChanged) {
      await applyPlatformSetting(
        PaperTodoStringKeys.platformSettingPaperSurfaces,
        controller.applyCurrentStateToPlatform,
      );
    }
    if (platformSettingErrors.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.format(
              PaperTodoStringKeys.platformSettingsFailed,
              [platformSettingErrors.join('; ')],
            ),
          ),
        ),
      );
    }
    widget.onAppThemeChanged?.call();
    if (syncSettingsChanged || !_canRunAutoSync()) {
      _clearPendingLocalEditSync();
    } else if (hadPendingLocalEditSync) {
      _reschedulePendingLocalEditSync();
    }
    if (!widget.coordinatorWindowMode) {
      _restartTodoReminderTimer();
    }
    try {
      await _saveState(
        scheduleLocalEditSync: false,
        preserveExistingPendingOperationBatch: preservePendingOperationBatch,
      );
      await _configureAndroidBackgroundSyncAfterSettingsSave();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.format(
                PaperTodoStringKeys.settingsSaveFailed,
                [_readableFailureMessage(error, strings: strings)],
              ),
            ),
          ),
        );
      }
    } finally {
      _isSettingsOpen = false;
      _settingsDeferredAutoSyncTimer?.cancel();
      _settingsDeferredAutoSyncTimer = null;
      if (mounted) {
        _restartAutoSyncTimer();
      }
      if (syncSettingsChanged) {
        _deferredSettingsSync = false;
      } else {
        _runDeferredSettingsSyncIfNeeded();
      }
    }
  }

  Future<void> _configureAndroidBackgroundSyncAfterSettingsSave() async {
    try {
      await widget.configureAndroidBackgroundSync(
        sync: controller.state.sync,
        stateFilePath: widget.store.filePath,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.format(
              PaperTodoStringKeys.platformSettingsFailed,
              [
                'WebDAV sync: '
                    '${_readableFailureMessage(error, strings: strings)}',
              ],
            ),
          ),
        ),
      );
    }
  }

  void _showSyncSnackBar({
    required String message,
    required AppSyncStatus status,
  }) {
    final action = switch (status) {
      AppSyncStatus.disabled ||
      AppSyncStatus.configurationMissing ||
      AppSyncStatus.payloadUnreadable =>
        SnackBarAction(
          label: strings.get(PaperTodoStringKeys.actionSettings),
          onPressed: () {
            if (mounted) {
              unawaited(_openSettings());
            }
          },
        ),
      AppSyncStatus.conflict => SnackBarAction(
          label: strings.get(PaperTodoStringKeys.actionRecovery),
          onPressed: () {
            if (mounted) {
              unawaited(_openRecoverySnapshots());
            }
          },
        ),
      _ => null,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
      ),
    );
  }

  void _showSyncFailureSnackBar(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.format(
            PaperTodoStringKeys.syncFailed,
            [_readableFailureMessage(error, strings: strings)],
          ),
        ),
        action: SnackBarAction(
          label: strings.get(PaperTodoStringKeys.actionRetry),
          onPressed: () {
            if (mounted) {
              unawaited(_syncNow());
            }
          },
        ),
      ),
    );
  }

  void _showRestoreFailureSnackBar(
    WebDavSnapshotRecord snapshot,
    Object error,
  ) {
    final strings = this.strings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.format(
            PaperTodoStringKeys.syncRestoreSnapshotFailed,
            [_readableFailureMessage(error, strings: strings)],
          ),
        ),
        action: SnackBarAction(
          label: strings.get(PaperTodoStringKeys.actionRetry),
          onPressed: () {
            if (mounted) {
              unawaited(_restoreRecoverySnapshot(snapshot));
            }
          },
        ),
      ),
    );
  }

  bool _shouldStopPersistentScriptCapsules(
    bool previousUsePersistentPowerShellProcess,
    bool previousPreferPowerShell7,
    bool previousHideScriptRunWindow,
    SyncSettingsDialogResult result,
  ) {
    if (!previousUsePersistentPowerShellProcess) {
      return false;
    }
    return !result.usePersistentPowerShellProcess ||
        previousPreferPowerShell7 != result.preferPowerShell7 ||
        previousHideScriptRunWindow != result.hideScriptRunWindow;
  }

  bool _shouldPreparePersistentScriptCapsules(
    bool previousUsePersistentPowerShellProcess,
    bool previousPreferPowerShell7,
    bool previousHideScriptRunWindow,
    SyncSettingsDialogResult result,
  ) {
    if (!result.usePersistentPowerShellProcess) {
      return false;
    }
    return !previousUsePersistentPowerShellProcess ||
        previousPreferPowerShell7 != result.preferPowerShell7 ||
        previousHideScriptRunWindow != result.hideScriptRunWindow;
  }

  String _syncMessage(AppSyncResult result) {
    if (result.message.isNotEmpty) {
      return _localizedSyncResultMessage(result);
    }
    return switch (result.status) {
      AppSyncStatus.disabled => strings.get(PaperTodoStringKeys.syncDisabled),
      AppSyncStatus.configurationMissing =>
        strings.get(PaperTodoStringKeys.syncCompleteConfiguration),
      AppSyncStatus.uploaded => strings.get(PaperTodoStringKeys.syncUploaded),
      AppSyncStatus.downloaded =>
        strings.get(PaperTodoStringKeys.syncDownloaded),
      AppSyncStatus.conflict => strings.get(PaperTodoStringKeys.syncConflict),
      AppSyncStatus.payloadUnreadable =>
        strings.get(PaperTodoStringKeys.syncPayloadUnreadable),
    };
  }

  String _localizedSyncResultMessage(AppSyncResult result) {
    final message = result.message;
    return switch (message) {
      'Sync is disabled.' => strings.get(PaperTodoStringKeys.syncDisabled),
      'Complete WebDAV sync settings and encryption passphrase first.' =>
        strings.get(PaperTodoStringKeys.syncCompleteConfiguration),
      'Local data uploaded.' => strings.get(PaperTodoStringKeys.syncUploaded),
      'Remote data downloaded.' =>
        strings.get(PaperTodoStringKeys.syncDownloaded),
      'Remote data downloaded from legacy plain WebDAV data and migrated to encrypted payloads.' =>
        strings.get(PaperTodoStringKeys.syncDownloadedLegacyPlainMigrated),
      'Remote data downloaded from legacy plain WebDAV data. Automatic encryption migration could not complete; sync again to retry.' =>
        strings.get(PaperTodoStringKeys.syncDownloadedLegacyPlainRetry),
      'Remote data downloaded from legacy plain WebDAV data. The next successful upload will write encrypted payloads.' =>
        strings.get(PaperTodoStringKeys.syncDownloadedLegacyPlainNextUpload),
      'Remote snapshot is empty.' =>
        strings.get(PaperTodoStringKeys.syncRemoteSnapshotEmpty),
      'Snapshot restored.' =>
        strings.get(PaperTodoStringKeys.syncSnapshotRestored),
      'Snapshot restored from legacy plain WebDAV data. The next successful upload will write encrypted payloads.' =>
        strings.get(
          PaperTodoStringKeys.syncSnapshotRestoredLegacyPlainNextUpload,
        ),
      'Remote data changed during sync. Pull again before upload.' =>
        strings.get(PaperTodoStringKeys.syncConflict),
      _
          when message.startsWith(
            'Remote data changed during sync. Local snapshot preserved at ',
          ) =>
        strings.format(
          PaperTodoStringKeys.syncConflictSnapshotPreserved,
          [result.snapshotPath],
        ),
      _ => message,
    };
  }

  String _syncRunMessage(AppSyncRunResult result) {
    final baseMessage = _syncMessage(result.syncResult);
    final appliedCount = result.operationAppliedCount;
    final parts = <String>[baseMessage];
    if (appliedCount > 0) {
      final changeLabel = strings.get(
        appliedCount == 1
            ? PaperTodoStringKeys.syncRemoteChange
            : PaperTodoStringKeys.syncRemoteChanges,
      );
      parts.add(
        strings.format(
          PaperTodoStringKeys.syncMergedRemoteChanges,
          [appliedCount, changeLabel],
        ),
      );
    }
    final mergeResult = result.operationMergeResult;
    if (mergeResult != null && mergeResult.legacyPlainOperationLogCount > 0) {
      final total = mergeResult.legacyPlainOperationLogCount;
      final migrated = mergeResult.legacyPlainOperationLogMigratedCount;
      final logLabel = strings.get(
        total == 1
            ? PaperTodoStringKeys.syncOperationLog
            : PaperTodoStringKeys.syncOperationLogs,
      );
      if (migrated == total) {
        parts.add(
          strings.format(
            PaperTodoStringKeys.syncMigratedLegacyOperationLogs,
            [total, logLabel],
          ),
        );
      } else if (migrated > 0) {
        parts.add(
          strings.format(
            PaperTodoStringKeys.syncMigratedLegacyOperationLogsPartial,
            [migrated, total, logLabel],
          ),
        );
      } else {
        parts.add(
          strings.format(
            PaperTodoStringKeys.syncFoundLegacyOperationLogs,
            [total, logLabel],
          ),
        );
      }
    }
    return parts.join(' ');
  }

  void _restartAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    if (!_canRunAutoSync()) {
      return;
    }
    final interval = Duration(
      minutes: controller.state.sync.webDav.autoSyncIntervalMinutes,
    );
    _autoSyncTimer = Timer.periodic(interval, (_) {
      unawaited(_syncSilentlyIfConfigured());
    });
  }

  void _startSettingsDeferredAutoSyncTimer() {
    _settingsDeferredAutoSyncTimer?.cancel();
    _settingsDeferredAutoSyncTimer = null;
    if (!_canRunAutoSync()) {
      return;
    }
    final interval = Duration(
      minutes: controller.state.sync.webDav.autoSyncIntervalMinutes,
    );
    _settingsDeferredAutoSyncTimer = Timer(interval, () {
      _settingsDeferredAutoSyncTimer = null;
      if (_isSettingsOpen) {
        _deferredSettingsSync = true;
      }
    });
  }

  Future<void> _syncSilentlyIfConfigured() async {
    if (_isSettingsOpen) {
      _deferredSettingsSync = true;
      return;
    }
    if (!_canRunAutoSync()) {
      _queuedSilentSync = false;
      return;
    }
    if (_isSyncing) {
      _queuedSilentSync = true;
      return;
    }
    await _syncNow(showMessage: false);
  }

  void _runDeferredSettingsSyncIfNeeded() {
    if (!_deferredSettingsSync) {
      return;
    }
    _deferredSettingsSync = false;
    if (mounted) {
      unawaited(_syncSilentlyIfConfigured());
    }
  }

  void _scheduleLocalEditSync({
    required AppState beforeState,
    required AppState afterState,
  }) {
    _localEditSyncDebounce?.cancel();
    _localEditSyncDebounce = null;
    if (!_canRunAutoSync()) {
      _clearPendingLocalEditSync();
      return;
    }
    _pendingLocalEditBaseState ??= beforeState;
    _pendingLocalEditLatestState = afterState;
    _pendingLocalEditGeneration = _localEditSyncGeneration;
    _localEditSyncDebounce = Timer(const Duration(seconds: 5), () {
      _localEditSyncDebounce = null;
      unawaited(_uploadLocalEditsThenSync());
    });
  }

  Future<void> _uploadLocalEditsThenSync() async {
    if (!_canRunAutoSync()) {
      _clearPendingLocalEditSync();
      return;
    }
    if (_isSyncing) {
      _reschedulePendingLocalEditSync();
      return;
    }
    final uploadedPendingEdits = await _uploadPendingLocalEdits();
    if (!uploadedPendingEdits) {
      return;
    }
    await _syncSilentlyIfConfigured();
  }

  Future<bool> _uploadPendingLocalEdits({bool reportFailures = false}) async {
    final beforeState = _pendingLocalEditBaseState;
    final afterState = _pendingLocalEditLatestState;
    final generation = _pendingLocalEditGeneration;
    _pendingLocalEditBaseState = null;
    _pendingLocalEditLatestState = null;
    _pendingLocalEditGeneration = null;
    if (beforeState == null || afterState == null) {
      return true;
    }
    if (generation != _localEditSyncGeneration) {
      return true;
    }
    if (afterState.sync.pendingOperationBatch != null) {
      return true;
    }
    try {
      final uploadResult = await widget.syncService.uploadLocalOperations(
        beforeState: beforeState,
        afterState: afterState,
        store: widget.store,
      );
      if (!mounted) {
        return false;
      }
      if (uploadResult.uploadedCount > 0 || uploadResult.stateChanged) {
        await _replaceStateAndApplyPlatform(uploadResult.state);
      }
      return true;
    } catch (error) {
      _pendingLocalEditBaseState = beforeState;
      _pendingLocalEditLatestState = afterState;
      _pendingLocalEditGeneration = generation;
      if (reportFailures) {
        rethrow;
      }
      return false;
    }
  }

  void _reschedulePendingLocalEditSync() {
    if (_pendingLocalEditBaseState == null ||
        _pendingLocalEditLatestState == null ||
        _localEditSyncDebounce != null) {
      return;
    }
    _localEditSyncDebounce = Timer(const Duration(seconds: 1), () {
      _localEditSyncDebounce = null;
      unawaited(_uploadLocalEditsThenSync());
    });
  }

  void _clearPendingLocalEditSync() {
    _localEditSyncDebounce?.cancel();
    _localEditSyncDebounce = null;
    _pendingLocalEditBaseState = null;
    _pendingLocalEditLatestState = null;
    _pendingLocalEditGeneration = null;
  }

  void _invalidatePendingLocalEditSyncForStateReplacement() {
    _localEditSyncGeneration += 1;
    _clearPendingLocalEditSync();
  }

  AppState _stateSnapshot(AppState state) {
    return AppState.fromJson(state.toJson());
  }

  bool _canRunAutoSync() {
    final settings = controller.state.sync;
    return settings.enabled &&
        settings.provider == SyncProviderIds.webDav &&
        settings.webDav.isSecurelyConfigured;
  }

  Future<bool> _confirmDeletePaper(PaperData paper) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            final strings = PaperTodoStringsScope.of(context);
            return AlertDialog(
              title: Text(strings.get(PaperTodoStringKeys.dialogDeletePaper)),
              content: Text(_displayTitle(paper)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(strings.get(PaperTodoStringKeys.actionCancel)),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(strings.get(PaperTodoStringKeys.actionDelete)),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  String _displayTitle(PaperData paper) {
    final title = controller.paperTitleText(paper);
    return _shortenTitle(
      title,
      controller.state.maxTitleLength,
    );
  }

  void _restoreLinkedNote(_LinkedNoteRestore link) {
    for (final paper in controller.state.papers) {
      if (paper.id != link.paperId) {
        continue;
      }
      for (final item in paper.items) {
        if (item.id == link.itemId) {
          item.linkedNoteId = link.noteId;
          return;
        }
      }
    }
  }

  void _restartTodoReminderTimer() {
    _todoReminderTimer?.cancel();
    _todoReminderTimer = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkTodoReminders();
      }
    });
    _todoReminderTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkTodoReminders(),
    );
  }

  void _checkTodoReminders() {
    if (!mounted) {
      return;
    }
    final now = DateTime.now();
    final candidates = _reminderCandidates(now);
    final shouldRefreshRelativeDueLabels =
        controller.state.showTodoDueRelativeTime && candidates.isNotEmpty;
    final readyCandidates = candidates
        .where((candidate) => _shouldShowReminder(candidate, now))
        .toList();
    if (readyCandidates.isNotEmpty) {
      if (controller.state.todoReminderScope == TodoReminderScopes.nearest &&
          readyCandidates.length > 1) {
        readyCandidates.sort((a, b) {
          final distance = _distanceFromNow(a, now).compareTo(
            _distanceFromNow(b, now),
          );
          return distance == 0 ? a.dueAt.compareTo(b.dueAt) : distance;
        });
        readyCandidates.removeRange(1, readyCandidates.length);
      }
      for (final candidate in readyCandidates) {
        _lastTodoReminderAt[candidate.key] = now;
      }
      _showTodoReminder(readyCandidates);
    }
    if (shouldRefreshRelativeDueLabels) {
      setState(() {});
    }
  }

  List<_TodoReminderCandidate> _reminderCandidates(DateTime now) {
    final candidates = <_TodoReminderCandidate>[];
    for (final paper in controller.state.papers) {
      if (widget.paperWindowMode && paper.id != widget.initialSurfacePaperId) {
        continue;
      }
      if (!paper.isTodo) {
        continue;
      }
      for (final item in paper.items) {
        if (item.done) {
          continue;
        }
        final dueAt = parsePaperTodoDueAtLocal(item.dueAtLocal);
        if (dueAt == null) {
          continue;
        }
        candidates.add(_TodoReminderCandidate(paper, item, dueAt));
      }
    }
    candidates.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return candidates;
  }

  bool _shouldShowReminder(_TodoReminderCandidate candidate, DateTime now) {
    final lastReminderAt = _lastTodoReminderAt[candidate.key];
    if (controller.state.useTodoReminderInterval) {
      final interval = _reminderInterval(candidate.item);
      if (!_isReminderInActiveWindow(candidate, now)) {
        return false;
      }
      return lastReminderAt == null ||
          now.difference(lastReminderAt) >= interval;
    }
    if (!_isReminderInActiveWindow(candidate, now)) {
      return false;
    }
    return lastReminderAt == null;
  }

  bool _isReminderInActiveWindow(
    _TodoReminderCandidate candidate,
    DateTime now,
  ) {
    if (controller.state.useTodoReminderInterval) {
      return !candidate.dueAt
          .isAfter(now.add(_reminderInterval(candidate.item)));
    }
    return !now.isBefore(candidate.dueAt.subtract(_todoReminderLeadTime)) &&
        !now.isAfter(candidate.dueAt.add(_todoReminderGraceTime));
  }

  Duration _distanceFromNow(_TodoReminderCandidate candidate, DateTime now) {
    final difference = candidate.dueAt.difference(now);
    return difference.isNegative
        ? Duration(microseconds: -difference.inMicroseconds)
        : difference;
  }

  Duration _reminderInterval(PaperItem item) {
    final value = (item.reminderIntervalValue ??
            controller.state.todoReminderIntervalValue)
        .clamp(1, 240)
        .toInt();
    final unit = TodoReminderIntervalUnits.normalize(
      item.reminderIntervalUnit ?? controller.state.todoReminderIntervalUnit,
    );
    return unit == TodoReminderIntervalUnits.hours
        ? Duration(hours: value)
        : Duration(minutes: value);
  }

  void _showTodoReminder(List<_TodoReminderCandidate> candidates) {
    _cancelTodoReminderSnackBarDismissTimer();
    _todoReminderSnackBarController = null;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final reminderItemIds = candidates
        .map((candidate) => candidate.item.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final reminderKeys = candidates.map((candidate) => candidate.key).toSet();
    _activeTodoReminderItemIds
      ..clear()
      ..addAll(reminderItemIds);
    _activeTodoReminderKeys
      ..clear()
      ..addAll(reminderKeys);
    final first = candidates.first;
    final message = candidates.length == 1
        ? strings.format(
            PaperTodoStringKeys.todoReminderSingle,
            [
              _displayTitle(first.paper),
              _displayReminderItemText(first.paper, first.item),
            ],
          )
        : strings.format(
            PaperTodoStringKeys.todoReminderMultiple,
            [candidates.length],
          );
    final reminderNow = DateTime.now();
    final details = candidates
        .take(_maxTodoReminderDetailLines)
        .map(
          (candidate) => _formatTodoReminderDetail(
            candidate,
            reminderNow,
            includeItemText: candidates.length > 1,
          ),
        )
        .toList();
    final reminderDuration = Duration(
      seconds: controller.state.todoReminderBubbleDurationSeconds,
    );
    final nativePresenter = widget.paperWindowReminderPresenter;
    if (widget.paperWindowMode && nativePresenter != null) {
      final colorScheme = Theme.of(context).colorScheme;
      unawaited(nativePresenter(<String, Object?>{
        'visible': true,
        'title': message,
        'message': details.join('\n'),
        'durationSeconds': reminderDuration.inSeconds,
        'backgroundColor': colorScheme.surface.toARGB32(),
        'borderColor': colorScheme.outlineVariant.toARGB32(),
        'accentColor': colorScheme.primary.toARGB32(),
        'textColor': colorScheme.onSurface.toARGB32(),
        'weakTextColor': colorScheme.onSurfaceVariant.toARGB32(),
      }));
      return;
    }
    final snackBarController = messenger.showSnackBar(
      SnackBar(
        content: MouseRegion(
          onEnter: (_) => _pauseTodoReminderSnackBarDismissTimer(),
          onExit: (_) => _resumeTodoReminderSnackBarDismissTimer(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              for (final detail in details) ...[
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: DefaultTextStyle.of(context).style.copyWith(
                        fontSize: 12,
                        height: 1.2,
                      ),
                ),
              ],
            ],
          ),
        ),
        duration: const Duration(days: 1),
        action: SnackBarAction(
          label: strings.get(PaperTodoStringKeys.actionOpen),
          onPressed: () => unawaited(_openTodoReminderPaper(first.paper)),
        ),
      ),
    );
    _todoReminderSnackBarController = snackBarController;
    _startTodoReminderSnackBarDismissTimer(
      reminderDuration,
      snackBarController,
    );
    unawaited(snackBarController.closed.then((_) {
      if (identical(_todoReminderSnackBarController, snackBarController)) {
        _cancelTodoReminderSnackBarDismissTimer();
        _todoReminderSnackBarController = null;
      }
      if (_sameStringSet(_activeTodoReminderKeys, reminderKeys)) {
        _activeTodoReminderItemIds.clear();
        _activeTodoReminderKeys.clear();
      }
    }));
  }

  void _startTodoReminderSnackBarDismissTimer(
    Duration duration,
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller,
  ) {
    _todoReminderSnackBarDismissTimer?.cancel();
    _todoReminderSnackBarRemaining = duration;
    if (duration <= Duration.zero) {
      controller.close();
      return;
    }
    _todoReminderSnackBarDismissStartedAt = DateTime.now();
    _todoReminderSnackBarDismissTimer = Timer(duration, () {
      if (identical(_todoReminderSnackBarController, controller)) {
        controller.close();
      }
    });
  }

  void _pauseTodoReminderSnackBarDismissTimer() {
    final timer = _todoReminderSnackBarDismissTimer;
    final startedAt = _todoReminderSnackBarDismissStartedAt;
    if (timer == null || !timer.isActive || startedAt == null) {
      return;
    }
    final remaining =
        _todoReminderSnackBarRemaining - DateTime.now().difference(startedAt);
    _todoReminderSnackBarRemaining =
        remaining > Duration.zero ? remaining : Duration.zero;
    timer.cancel();
    _todoReminderSnackBarDismissTimer = null;
    _todoReminderSnackBarDismissStartedAt = null;
  }

  void _resumeTodoReminderSnackBarDismissTimer() {
    final controller = _todoReminderSnackBarController;
    if (controller == null || _todoReminderSnackBarDismissTimer != null) {
      return;
    }
    final remaining = _todoReminderSnackBarRemaining;
    if (remaining <= Duration.zero) {
      controller.close();
      return;
    }
    _startTodoReminderSnackBarDismissTimer(remaining, controller);
  }

  void _cancelTodoReminderSnackBarDismissTimer() {
    _todoReminderSnackBarDismissTimer?.cancel();
    _todoReminderSnackBarDismissTimer = null;
    _todoReminderSnackBarDismissStartedAt = null;
    _todoReminderSnackBarRemaining = Duration.zero;
  }

  void _hideCurrentTodoReminderSnackBar() {
    _cancelTodoReminderSnackBarDismissTimer();
    _todoReminderSnackBarController = null;
    final nativePresenter = widget.paperWindowReminderPresenter;
    if (widget.paperWindowMode && nativePresenter != null) {
      unawaited(nativePresenter(const <String, Object?>{'visible': false}));
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  Future<void> _openTodoReminderPaper(PaperData paper) async {
    final wasCollapseAllActive =
        controller.state.isCapsuleCollapseAllActiveFor(paper);
    setState(() {
      paper
        ..isVisible = true
        ..isCollapsed = false;
      if (wasCollapseAllActive) {
        controller.state.setCapsuleCollapseAllActiveFor(paper, false);
      }
      _surfacePaperId = paper.id;
    });
    await controller.openReminderPaper(paper);
    if (wasCollapseAllActive) {
      await controller.refreshPaperSurfaces();
    }
    await _saveState();
  }

  void _reconcileTodoReminderStateAfterReplacement() {
    final now = DateTime.now();
    final candidateKeys = <String>{};
    final candidateItemIds = <String>{};
    final activeWindowCandidateKeys = <String>{};
    for (final candidate in _reminderCandidates(now)) {
      candidateKeys.add(candidate.key);
      if (_isReminderInActiveWindow(candidate, now)) {
        activeWindowCandidateKeys.add(candidate.key);
      }
      final itemId = candidate.item.id.trim();
      if (itemId.isNotEmpty) {
        candidateItemIds.add(itemId);
      }
    }
    _lastTodoReminderAt.removeWhere((key, _) => !candidateKeys.contains(key));
    final activeReminderStillExists =
        _activeTodoReminderKeys.every(activeWindowCandidateKeys.contains) &&
            _activeTodoReminderItemIds.every(candidateItemIds.contains);
    if (_activeTodoReminderKeys.isNotEmpty && !activeReminderStillExists) {
      _hideCurrentTodoReminderSnackBar();
      _activeTodoReminderItemIds.clear();
      _activeTodoReminderKeys.clear();
    }
  }

  ({bool useInterval, int value, String unit}) _todoReminderCadence(
    AppState state,
  ) {
    return (
      useInterval: state.useTodoReminderInterval,
      value: state.todoReminderIntervalValue,
      unit: TodoReminderIntervalUnits.normalize(state.todoReminderIntervalUnit),
    );
  }

  void _clearTodoReminderStateForItems(
    Iterable<PaperItem> items, {
    required bool hideActiveSnackBar,
  }) {
    final itemIds = items
        .map((item) => item.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (itemIds.isEmpty) {
      return;
    }
    _lastTodoReminderAt.removeWhere((key, _) {
      return itemIds.any((itemId) => key.startsWith('$itemId|'));
    });
    if (hideActiveSnackBar &&
        _activeTodoReminderItemIds.any(itemIds.contains)) {
      _hideCurrentTodoReminderSnackBar();
      _activeTodoReminderItemIds.clear();
      _activeTodoReminderKeys.clear();
      return;
    }
    _activeTodoReminderItemIds.removeWhere(itemIds.contains);
    _activeTodoReminderKeys.removeWhere((key) {
      return itemIds.any((itemId) => key.startsWith('$itemId|'));
    });
  }

  String _displayReminderItemText(PaperData paper, PaperItem item) {
    var text = item.text.trim();
    if (text.isEmpty) {
      text = controller.paperTitleText(paper);
    }
    if (text.length > 80) {
      return '${text.substring(0, 80)}...';
    }
    return text;
  }

  String _formatTodoReminderDetail(
    _TodoReminderCandidate candidate,
    DateTime now, {
    required bool includeItemText,
  }) {
    final dueAt = candidate.dueAt.toLocal();
    final dueText = '${dueAt.year.toString().padLeft(4, '0')}-'
        '${dueAt.month.toString().padLeft(2, '0')}-'
        '${dueAt.day.toString().padLeft(2, '0')} '
        '${dueAt.hour.toString().padLeft(2, '0')}:'
        '${dueAt.minute.toString().padLeft(2, '0')}:'
        '${dueAt.second.toString().padLeft(2, '0')}';
    final relativeText = _formatTodoReminderRelativeTime(dueAt, now);
    final dueDetail = strings.format(
      PaperTodoStringKeys.dueLabel,
      ['$dueText ($relativeText)'],
    );
    if (!includeItemText) {
      return dueDetail;
    }
    return '${_displayReminderItemText(candidate.paper, candidate.item)} - '
        '$dueDetail';
  }

  String _formatTodoReminderRelativeTime(DateTime dueAt, DateTime now) {
    final difference = dueAt.difference(now);
    final absoluteDifference = difference.isNegative
        ? Duration(microseconds: -difference.inMicroseconds)
        : difference;
    final countdown = _formatTodoReminderCountdown(absoluteDifference);
    final key = difference.isNegative
        ? PaperTodoStringKeys.relativeDueOverdue
        : PaperTodoStringKeys.relativeDueFuture;
    return strings.format(key, [countdown]);
  }

  String _formatTodoReminderCountdown(Duration span) {
    var totalSeconds =
        (span.inMicroseconds / Duration.microsecondsPerSecond).ceil();
    if (totalSeconds < 0) {
      totalSeconds = 0;
    }
    final days = totalSeconds ~/ 86400;
    totalSeconds %= 86400;
    final hours = totalSeconds ~/ 3600;
    totalSeconds %= 3600;
    final minutes = totalSeconds ~/ Duration.secondsPerMinute;
    final seconds = totalSeconds % Duration.secondsPerMinute;

    if (days > 0) {
      return '${days}d${hours}h${minutes}m${seconds}s';
    }
    if (hours > 0) {
      return '${hours}h${minutes}m${seconds}s';
    }
    if (minutes > 0) {
      return '${minutes}m${seconds}s';
    }
    return '${seconds}s';
  }
}

class _TodoReminderCandidate {
  const _TodoReminderCandidate(this.paper, this.item, this.dueAt);

  final PaperData paper;
  final PaperItem item;
  final DateTime dueAt;

  String get key => '${item.id}|${item.dueAtLocal ?? ''}';
}

class _ReminderIntervalSelection {
  const _ReminderIntervalSelection.set(this.value, this.unit) : clear = false;

  const _ReminderIntervalSelection.clear()
      : value = null,
        unit = null,
        clear = true;

  final int? value;
  final String? unit;
  final bool clear;
}

class _ReminderIntervalDialog extends StatefulWidget {
  const _ReminderIntervalDialog({
    required this.initialValue,
    required this.initialUnit,
  });

  final int? initialValue;
  final String? initialUnit;

  @override
  State<_ReminderIntervalDialog> createState() =>
      _ReminderIntervalDialogState();
}

class _ReminderIntervalDialogState extends State<_ReminderIntervalDialog> {
  late final TextEditingController _intervalController;
  late final FocusNode _intervalFocusNode;
  late String _unit;

  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController(
      text: (widget.initialValue ?? 10).clamp(1, 240).toString(),
    );
    _intervalFocusNode = FocusNode(debugLabel: 'todo-reminder-interval');
    _unit = TodoReminderIntervalUnits.normalize(widget.initialUnit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _intervalFocusNode.requestFocus();
      _intervalController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _intervalController.text.length,
      );
    });
  }

  @override
  void dispose() {
    _intervalFocusNode.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = PaperTodoStringsScope.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _handleDialogKeyEvent,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): _save,
          const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        },
        child: AlertDialog(
          title: Text(strings.get(PaperTodoStringKeys.reminderInterval)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _intervalController,
                  focusNode: _intervalFocusNode,
                  autofocus: true,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: strings.get(PaperTodoStringKeys.interval),
                    prefixIcon: const Icon(Icons.notifications_active_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: TodoReminderIntervalUnits.minutes,
                      icon: const Icon(Icons.timer_outlined),
                      label: Text(strings.get(PaperTodoStringKeys.minutes)),
                    ),
                    ButtonSegment(
                      value: TodoReminderIntervalUnits.hours,
                      icon: const Icon(Icons.schedule_outlined),
                      label: Text(strings.get(PaperTodoStringKeys.hours)),
                    ),
                  ],
                  selected: {_unit},
                  onSelectionChanged: (selection) {
                    setState(() => _unit = selection.single);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _clear,
              child: Text(strings.get(PaperTodoStringKeys.actionClear)),
            ),
            TextButton(
              onPressed: _cancel,
              child: Text(strings.get(PaperTodoStringKeys.actionCancel)),
            ),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(strings.get(PaperTodoStringKeys.actionSave)),
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleDialogKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _save();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _clear() {
    Navigator.of(context).pop(
      const _ReminderIntervalSelection.clear(),
    );
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  void _save() {
    final parsedValue = int.tryParse(_intervalController.text.trim());
    final fallbackValue = (widget.initialValue ?? 10).clamp(1, 240).toInt();
    final rawValue = parsedValue ?? fallbackValue;
    final value = (rawValue <= 0 ? 1 : rawValue).clamp(1, 240).toInt();
    Navigator.of(context).pop(
      _ReminderIntervalSelection.set(value, _unit),
    );
  }
}

class _LinkedNoteRestore {
  const _LinkedNoteRestore({
    required this.paperId,
    required this.itemId,
    required this.noteId,
  });

  final String paperId;
  final String itemId;
  final String noteId;
}

class _RecoverySnapshotsDialog extends StatefulWidget {
  const _RecoverySnapshotsDialog({
    required this.loadSnapshots,
    required this.onOpenSettings,
  });

  final Future<List<WebDavSnapshotRecord>> Function() loadSnapshots;
  final VoidCallback onOpenSettings;

  @override
  State<_RecoverySnapshotsDialog> createState() =>
      _RecoverySnapshotsDialogState();
}

class _RecoverySnapshotsDialogState extends State<_RecoverySnapshotsDialog> {
  late Future<List<WebDavSnapshotRecord>> _snapshotsFuture;

  @override
  void initState() {
    super.initState();
    _snapshotsFuture = widget.loadSnapshots();
  }

  void _retry() {
    setState(() {
      _snapshotsFuture = widget.loadSnapshots();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = PaperTodoStringsScope.of(context);
    return AlertDialog(
      title: Text(strings.get(PaperTodoStringKeys.actionRecoverySnapshots)),
      content: SizedBox(
        width: 520,
        child: FutureBuilder<List<WebDavSnapshotRecord>>(
          future: _snapshotsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 132,
                  maxHeight: 240,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          strings.format(
                            PaperTodoStringKeys.recoverySnapshotLoadFailed,
                            [
                              _readableFailureMessage(
                                snapshot.error!,
                                strings: strings,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          key: const ValueKey('settings-recovery-snapshots'),
                          onPressed: widget.onOpenSettings,
                          icon: const Icon(Icons.settings_outlined),
                          label: Text(
                            strings.get(PaperTodoStringKeys.actionSettings),
                          ),
                        ),
                        FilledButton.icon(
                          key: const ValueKey('retry-recovery-snapshots'),
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh_outlined),
                          label: Text(
                            strings.get(PaperTodoStringKeys.actionRetry),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }
            final snapshots = snapshot.data ?? const <WebDavSnapshotRecord>[];
            if (snapshots.isEmpty) {
              return SizedBox(
                height: 96,
                child: Center(
                  child: Text(
                    strings.get(PaperTodoStringKeys.recoverySnapshotsEmpty),
                  ),
                ),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: snapshots.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final record = snapshots[index];
                  return _RecoverySnapshotListItem(
                    record: record,
                    onRestore: () => Navigator.of(context).pop(record),
                    strings: strings,
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.get(PaperTodoStringKeys.actionClose)),
        ),
      ],
    );
  }
}

class _RecoverySnapshotListItem extends StatelessWidget {
  const _RecoverySnapshotListItem({
    required this.record,
    required this.onRestore,
    required this.strings,
  });

  final WebDavSnapshotRecord record;
  final VoidCallback onRestore;
  final PaperTodoStrings strings;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.history_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _snapshotSummary(record),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.path,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _snapshotSizeLabel(strings, record),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: ValueKey('restore-snapshot-${record.path}'),
              onPressed: onRestore,
              icon: const Icon(Icons.restore_outlined),
              label: Text(strings.get(PaperTodoStringKeys.actionRestore)),
            ),
          ],
        ),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history_outlined),
      title: Text(_snapshotSummary(record)),
      subtitle: Text(
        '${record.path}\n${_snapshotSizeLabel(strings, record)}',
      ),
      isThreeLine: true,
      trailing: FilledButton.icon(
        key: ValueKey('restore-snapshot-${record.path}'),
        onPressed: onRestore,
        icon: const Icon(Icons.restore_outlined),
        label: Text(strings.get(PaperTodoStringKeys.actionRestore)),
      ),
    );
  }
}

String _snapshotSummary(WebDavSnapshotRecord snapshot) {
  return '${_formatSnapshotTime(snapshot.updatedAtUtc)} - ${snapshot.deviceId}';
}

String _snapshotSizeLabel(
  PaperTodoStrings strings,
  WebDavSnapshotRecord snapshot,
) {
  final parts = <String>[];
  final contentLength = snapshot.contentLength;
  if (contentLength != null) {
    parts.add(_formatByteCount(contentLength));
  }
  final lastModified = snapshot.lastModifiedUtc;
  if (lastModified != null) {
    parts.add(
      strings.format(
        PaperTodoStringKeys.recoverySnapshotModified,
        [_formatSnapshotTime(lastModified)],
      ),
    );
  }
  return parts.isEmpty
      ? strings.get(PaperTodoStringKeys.recoverySnapshotFallback)
      : parts.join(' - ');
}

String _formatSnapshotTime(DateTime value) {
  final utc = value.toUtc();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)} UTC';
}

String _formatByteCount(int value) {
  if (value < 1024) {
    return '$value B';
  }
  final kib = value / 1024;
  if (kib < 1024) {
    return '${kib.toStringAsFixed(kib < 10 ? 1 : 0)} KiB';
  }
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib < 10 ? 1 : 0)} MiB';
}

PopupMenuItem<String> _paperTodoMenuHeader(String label) {
  return PopupMenuItem<String>(
    enabled: false,
    height: 32,
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

double _paperTodoPopupMenuHeight() {
  return defaultTargetPlatform == TargetPlatform.windows ? 36 : 48;
}

class PaperPreview extends StatelessWidget {
  const PaperPreview({
    required this.paper,
    required this.notePapers,
    required this.titleText,
    required this.enableTodoNoteLinks,
    required this.showLinkedNoteName,
    required this.allowLongLinkedNoteTitles,
    required this.runLinkedScriptCapsulesOnClick,
    required this.maxTitleLength,
    required this.showTopBarNewTodoButton,
    required this.showTopBarNewNoteButton,
    required this.showTopBarExternalOpenButton,
    required this.useCapsuleMode,
    this.onWindowDragStart,
    required this.enableToolTips,
    required this.enableAnimations,
    required this.markdownRenderMode,
    required this.externalMarkdownExtension,
    required this.todoVisualSize,
    required this.todoLineSpacing,
    required this.showTodoDueRelativeTime,
    required this.todoDueYearDisplayMode,
    required this.defaultTodoReminderIntervalValue,
    required this.defaultTodoReminderIntervalUnit,
    required this.collapseAllActive,
    required this.noteLineSpacing,
    required this.onChanged,
    required this.onTitleChanged,
    required this.onCreatePaper,
    required this.onOpen,
    required this.onOpenLinkedNote,
    required this.onRunScriptCapsule,
    required this.onOpenExternalMarkdown,
    required this.onOpenUri,
    required this.onHide,
    required this.onDelete,
    required this.onTodoItemDeleted,
    required this.onTodoItemRestored,
    required this.onTodoReminderReset,
    required this.onSetAlwaysOnTop,
    required this.onSetPinnedToDesktop,
    required this.onSurfaceChanged,
    required this.onCaptureBounds,
    this.standaloneSurface = false,
    super.key,
  });

  static const _compactPaperActionOpenSurface = 'open-surface';
  static const _compactPaperActionOpenMarkdown = 'open-markdown';
  static const _compactPaperActionNewTodo = 'new-todo';
  static const _compactPaperActionNewNote = 'new-note';
  static const _compactPaperActionClearDone = 'clear-done';
  static const _compactPaperActionAddCanvasBlock = 'add-canvas-block';
  static const _compactPaperActionToggleAlwaysOnTop = 'toggle-always-on-top';
  static const _compactPaperActionTogglePinned = 'toggle-pinned';
  static const _compactPaperActionToggleCollapsed = 'toggle-collapsed';
  static const _compactPaperActionCaptureBounds = 'capture-bounds';
  static const _compactPaperActionHide = 'hide';
  static const _compactPaperActionDelete = 'delete';
  static const _compactPaperZoomActionPrefix = 'zoom:';

  final PaperData paper;
  final List<PaperData> notePapers;
  final String titleText;
  final bool enableTodoNoteLinks;
  final bool showLinkedNoteName;
  final bool allowLongLinkedNoteTitles;
  final bool runLinkedScriptCapsulesOnClick;
  final int maxTitleLength;
  final bool showTopBarNewTodoButton;
  final bool showTopBarNewNoteButton;
  final bool showTopBarExternalOpenButton;
  final bool useCapsuleMode;
  final Future<void> Function()? onWindowDragStart;
  final bool enableToolTips;
  final bool enableAnimations;
  final String markdownRenderMode;
  final String externalMarkdownExtension;
  final String todoVisualSize;
  final double todoLineSpacing;
  final bool showTodoDueRelativeTime;
  final String todoDueYearDisplayMode;
  final int defaultTodoReminderIntervalValue;
  final String defaultTodoReminderIntervalUnit;
  final bool collapseAllActive;
  final double noteLineSpacing;
  final Future<void> Function() onChanged;
  final Future<void> Function(PaperData paper) onTitleChanged;
  final Future<void> Function(String type, {PaperData? sourcePaper})
      onCreatePaper;
  final Future<void> Function(PaperData paper) onOpen;
  final Future<void> Function(PaperData paper, PaperData anchorPaper)
      onOpenLinkedNote;
  final Future<void> Function(ScriptCapsuleSpec spec) onRunScriptCapsule;
  final Future<void> Function(PaperData paper) onOpenExternalMarkdown;
  final Future<void> Function(String uri) onOpenUri;
  final Future<void> Function(PaperData paper) onHide;
  final Future<void> Function(PaperData paper) onDelete;
  final void Function(PaperData paper, PaperItem item) onTodoItemDeleted;
  final void Function(PaperData paper, PaperItem item) onTodoItemRestored;
  final void Function(PaperItem item) onTodoReminderReset;
  final Future<void> Function(PaperData paper, bool enabled) onSetAlwaysOnTop;
  final Future<void> Function(PaperData paper, bool pinned)
      onSetPinnedToDesktop;
  final Future<void> Function(PaperData paper) onSurfaceChanged;
  final Future<void> Function(PaperData paper) onCaptureBounds;
  final bool standaloneSurface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final mobileBoard =
        !standaloneSurface && MediaQuery.sizeOf(context).shortestSide < 600;
    final titleBarTintAlpha = isDark ? 18 / 255 : 12 / 255;
    final titleBarDividerAlpha = isDark ? 34 / 255 : 28 / 255;
    final isCollapsed = collapseAllActive || paper.isCollapsed;
    final scriptCapsuleSpec =
        paper.isNote ? ScriptCapsuleSpec.tryParse(paper.content) : null;
    final textZoom = paper.textZoom.clamp(0.5, 1.5).toDouble();
    final desktopInteractionLocked =
        paper.isPinnedToDesktop && !paper.isCollapsed;
    return Semantics(
      label: '$titleText ${paper.type} paper',
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: DecoratedBox(
          key: ValueKey('${paper.id}-paper-surface'),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            border: Border.all(
              color: colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(
              standaloneSurface
                  ? 18
                  : mobileBoard
                      ? 18
                      : 12,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(
                  alpha: isDark ? 0.34 : 0.18,
                ),
                blurRadius: standaloneSurface || mobileBoard ? 22 : 16,
                offset: standaloneSurface ? Offset.zero : const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: standaloneSurface
                  ? CrossAxisAlignment.stretch
                  : mobileBoard
                      ? CrossAxisAlignment.stretch
                      : CrossAxisAlignment.start,
              children: [
                Container(
                  key: ValueKey('${paper.id}-paper-header'),
                  height: standaloneSurface
                      ? 31
                      : mobileBoard
                          ? 56
                          : null,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(
                      alpha: standaloneSurface
                          ? titleBarTintAlpha
                          : mobileBoard
                              ? (isDark ? 18 / 255 : 12 / 255)
                              : 0.035,
                    ),
                    borderRadius: standaloneSurface
                        ? const BorderRadius.vertical(top: Radius.circular(17))
                        : mobileBoard
                            ? const BorderRadius.vertical(
                                top: Radius.circular(15),
                              )
                            : null,
                    border: Border(
                      bottom: BorderSide(
                        color: standaloneSurface
                            ? colorScheme.primary.withValues(
                                alpha: titleBarDividerAlpha,
                              )
                            : mobileBoard
                                ? colorScheme.primary.withValues(
                                    alpha: isDark ? 34 / 255 : 28 / 255,
                                  )
                                : colorScheme.outlineVariant
                                    .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    standaloneSurface
                        ? 6
                        : mobileBoard
                            ? 8
                            : 10,
                    standaloneSurface
                        ? 3
                        : mobileBoard
                            ? 4
                            : 5,
                    standaloneSurface
                        ? 8
                        : mobileBoard
                            ? 4
                            : 7,
                    standaloneSurface
                        ? 2
                        : mobileBoard
                            ? 3
                            : 5,
                  ),
                  child: Semantics(
                    label: standaloneSurface
                        ? PaperTodoStringsScope.of(context)
                            .get(PaperTodoStringKeys.actionMovePaperWindow)
                        : null,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanStart: standaloneSurface &&
                              !desktopInteractionLocked &&
                              onWindowDragStart != null
                          ? (_) => unawaited(onWindowDragStart!())
                          : null,
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (event) =>
                            _handlePaperContextMenuPointerDown(context, event),
                        child: Row(
                          children: [
                            if (standaloneSurface)
                              _standalonePaperTypeButton(
                                context,
                                scriptCapsuleSpec: scriptCapsuleSpec,
                              )
                            else
                              SizedBox.square(
                                dimension: mobileBoard ? 40 : 24,
                                child: Icon(
                                  paper.isTodo
                                      ? (paper.items.isNotEmpty &&
                                              paper.items
                                                  .every((item) => item.done)
                                          ? Icons.check_box
                                          : Icons.check_box_outline_blank)
                                      : scriptCapsuleSpec != null
                                          ? Icons.bolt_outlined
                                          : Icons.edit_outlined,
                                  size: mobileBoard ? 20 : 17,
                                  color: colorScheme.primary,
                                ),
                              ),
                            if (!standaloneSurface &&
                                paper.isNote &&
                                enableTodoNoteLinks) ...[
                              const SizedBox(width: 2),
                              _noteLinkDragHandle(context),
                            ],
                            SizedBox(width: standaloneSurface ? 1 : 5),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth: standaloneSurface ? 30 : 0,
                                    maxWidth: standaloneSurface
                                        ? 86
                                        : double.infinity,
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: standaloneSurface
                                          ? Border(
                                              bottom: BorderSide(
                                                color: colorScheme
                                                    .outlineVariant
                                                    .withValues(alpha: 0.38),
                                              ),
                                            )
                                          : null,
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: standaloneSurface ? 4 : 0,
                                      ),
                                      child: _PaperTitleEditor(
                                        paper: paper,
                                        titleText: titleText,
                                        textZoom: textZoom,
                                        enabled: !desktopInteractionLocked &&
                                            !isCollapsed,
                                        fieldEnabled: !desktopInteractionLocked,
                                        enableToolTips: enableToolTips,
                                        compact: standaloneSurface,
                                        onTitleChanged: onTitleChanged,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (standaloneSurface) ...[
                              ..._standalonePaperHeaderActions(
                                context: context,
                                isCollapsed: isCollapsed,
                                desktopInteractionLocked:
                                    desktopInteractionLocked,
                              ),
                            ] else if (mobileBoard) ...[
                              ..._paperHeaderActions(
                                context: context,
                                isCollapsed: isCollapsed,
                                desktopInteractionLocked:
                                    desktopInteractionLocked,
                                textZoom: textZoom,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (!standaloneSurface && !mobileBoard) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 2,
                        runSpacing: 2,
                        children: _paperHeaderActions(
                          context: context,
                          isCollapsed: isCollapsed,
                          desktopInteractionLocked: desktopInteractionLocked,
                          textZoom: textZoom,
                        ),
                      ),
                    ),
                  ),
                ],
                if (standaloneSurface)
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                          child: SizedBox(
                            width: math.max(0, constraints.maxWidth - 12),
                            child: AbsorbPointer(
                              absorbing: desktopInteractionLocked,
                              child: _animatedPaperBody(
                                isCollapsed,
                                scriptCapsuleSpec,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  )
                else
                  Padding(
                    padding: mobileBoard
                        ? const EdgeInsets.fromLTRB(8, 4, 8, 8)
                        : const EdgeInsets.fromLTRB(7, 3, 7, 7),
                    child: AbsorbPointer(
                      absorbing: desktopInteractionLocked,
                      child: _animatedPaperBody(isCollapsed, scriptCapsuleSpec),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _noteLinkDragHandle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = PaperTodoStringsScope.of(context);
    final dragLabel =
        strings.get(PaperTodoStringKeys.actionDragToLinkNoteToTodo);
    final handle = Semantics(
      label: dragLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: SizedBox.square(
          key: ValueKey('${paper.id}-note-link-drag-handle'),
          dimension: standaloneSurface ? 28 : 48,
          child: Icon(
            Icons.link_outlined,
            size: 16,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
    return Draggable<String>(
      data: paper.id,
      feedback: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            border: Border.all(color: colorScheme.primary),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.16),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.link_outlined,
                  size: 16,
                  color: colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  strings.format(
                    PaperTodoStringKeys.actionLinkPaper,
                    [_displayPaperTitle()],
                  ),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: handle),
      child: _conditionalTooltip(
        enabled: enableToolTips,
        message: dragLabel,
        child: handle,
      ),
    );
  }

  Widget _animatedPaperBody(
    bool isCollapsed,
    ScriptCapsuleSpec? scriptCapsuleSpec,
  ) {
    final body = isCollapsed
        ? scriptCapsuleSpec == null
            ? const SizedBox.shrink(key: ValueKey('collapsed'))
            : _collapsedScriptCapsule(scriptCapsuleSpec)
        : Column(
            key: const ValueKey('expanded'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: standaloneSurface && paper.isNote ? 0 : 3),
              if (paper.isTodo)
                _TodoEditor(
                  paper: paper,
                  notePapers: notePapers,
                  enableTodoNoteLinks: enableTodoNoteLinks,
                  showLinkedNoteName: showLinkedNoteName,
                  allowLongLinkedNoteTitles: allowLongLinkedNoteTitles,
                  runLinkedScriptCapsulesOnClick:
                      runLinkedScriptCapsulesOnClick,
                  maxTitleLength: maxTitleLength,
                  enableToolTips: enableToolTips,
                  visualSize: todoVisualSize,
                  lineSpacing: todoLineSpacing,
                  textZoom: paper.textZoom,
                  showDueRelativeTime: showTodoDueRelativeTime,
                  dueYearDisplayMode: todoDueYearDisplayMode,
                  defaultReminderIntervalValue:
                      defaultTodoReminderIntervalValue,
                  defaultReminderIntervalUnit: defaultTodoReminderIntervalUnit,
                  onOpenLinkedNote: onOpenLinkedNote,
                  onRunScriptCapsule: onRunScriptCapsule,
                  onChanged: onChanged,
                  onItemDeleted: onTodoItemDeleted,
                  onItemRestored: onTodoItemRestored,
                  onReminderReset: onTodoReminderReset,
                  standaloneSurface: standaloneSurface,
                )
              else
                _NoteEditor(
                  paper: paper,
                  markdownRenderMode: markdownRenderMode,
                  lineSpacing: noteLineSpacing,
                  textZoom: paper.textZoom,
                  enableToolTips: enableToolTips,
                  onOpenUri: onOpenUri,
                  onChanged: onChanged,
                  onTextZoomChanged: _setTextZoom,
                  onShowPaperContextMenu: _showPaperContextMenu,
                ),
            ],
          );
    if (!enableAnimations) {
      return body;
    }
    return AnimatedSwitcher(
      key: ValueKey('${paper.id}-body-animation'),
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: animation,
          alignment: AlignmentDirectional.topStart,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      child: body,
    );
  }

  Widget _collapsedScriptCapsule(ScriptCapsuleSpec spec) {
    return Builder(
      key: ValueKey('${paper.id}-script-capsule'),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final strings = PaperTodoStringsScope.of(context);
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _conditionalTooltip(
            enabled: enableToolTips,
            message: strings.get(PaperTodoStringKeys.actionRunScriptCapsule),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(onRunScriptCapsule(spec)),
              onSecondaryTap: _openCollapsedScriptCapsuleForEditing,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.primary),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bolt_outlined,
                        size: 18,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          strings.format(
                            PaperTodoStringKeys.actionRunPaper,
                            [_displayPaperTitle()],
                          ),
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _paperHeaderActions({
    required BuildContext context,
    required bool isCollapsed,
    required bool desktopInteractionLocked,
    required double textZoom,
  }) {
    if (desktopInteractionLocked) {
      final strings = PaperTodoStringsScope.of(context);
      return [
        _standaloneHeaderButton(
          key: ValueKey('${paper.id}-desktop-pin'),
          tooltip: strings.get(PaperTodoStringKeys.actionUnpinFromDesktop),
          onPressed: _togglePinnedToDesktop,
          child: const Icon(Icons.push_pin, size: 15),
        ),
      ];
    }
    final strings = PaperTodoStringsScope.of(context);
    final hideThisPaperLabel =
        strings.get(PaperTodoStringKeys.actionHideThisPaper);
    final openMarkdownEditorLabel = _openMarkdownEditorLabel(strings);
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    if (compact) {
      return [
        SizedBox.square(
          dimension: 48,
          child: _collapseButton(context, isCollapsed),
        ),
        SizedBox.square(
          key: ValueKey('${paper.id}-paper-actions'),
          dimension: 48,
          child: PopupMenuButton<String>(
            tooltip: _tooltipLabel(
              enableToolTips,
              strings.get(PaperTodoStringKeys.actionPaperActions),
            ),
            icon: const Icon(Icons.more_vert),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(48),
              maximumSize: const Size.square(48),
            ),
            padding: EdgeInsets.zero,
            onSelected: _handleCompactPaperAction,
            itemBuilder: (context) => [
              _paperActionMenuItem(
                value: _compactPaperActionOpenSurface,
                icon: Icons.open_in_new,
                label: strings.get(PaperTodoStringKeys.actionOpenSurface),
              ),
              if (paper.isNote)
                _paperActionMenuItem(
                  value: _compactPaperActionOpenMarkdown,
                  icon: Icons.file_open_outlined,
                  label: openMarkdownEditorLabel,
                ),
              const PopupMenuDivider(),
              for (final option in _TextZoomOption.values)
                CheckedPopupMenuItem<String>(
                  value: '$_compactPaperZoomActionPrefix${option.value}',
                  checked: option.value == textZoom,
                  child: Text('${strings.get(PaperTodoStringKeys.zoom)} '
                      '${option.label}'),
                ),
              const PopupMenuDivider(),
              _paperActionMenuItem(
                value: _compactPaperActionToggleAlwaysOnTop,
                icon: paper.alwaysOnTop
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
                label: paper.alwaysOnTop
                    ? strings.get(PaperTodoStringKeys.actionDisableAlwaysOnTop)
                    : strings.get(PaperTodoStringKeys.actionKeepOnTop),
              ),
              _paperActionMenuItem(
                value: _compactPaperActionTogglePinned,
                icon: paper.isPinnedToDesktop
                    ? Icons.desktop_windows
                    : Icons.desktop_windows_outlined,
                label: paper.isPinnedToDesktop
                    ? strings.get(PaperTodoStringKeys.actionUnpinFromDesktop)
                    : strings.get(PaperTodoStringKeys.actionPinToDesktop),
              ),
              _paperActionMenuItem(
                value: _compactPaperActionCaptureBounds,
                icon: Icons.aspect_ratio_outlined,
                label: strings.get(PaperTodoStringKeys.actionSaveWindowBounds),
              ),
              const PopupMenuDivider(),
              _paperActionMenuItem(
                value: _compactPaperActionHide,
                icon: Icons.visibility_off_outlined,
                label: hideThisPaperLabel,
              ),
              _paperActionMenuItem(
                value: _compactPaperActionDelete,
                icon: Icons.delete_outline,
                label: strings.get(PaperTodoStringKeys.actionDeletePaper),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      IconButton(
        tooltip: _tooltipLabel(
          enableToolTips,
          strings.get(PaperTodoStringKeys.actionOpenPaperSurface),
        ),
        onPressed: () => unawaited(onOpen(paper)),
        icon: const Icon(Icons.open_in_new),
      ),
      if (paper.isNote)
        IconButton(
          tooltip: _tooltipLabel(
            enableToolTips,
            openMarkdownEditorLabel,
          ),
          onPressed: () => unawaited(onOpenExternalMarkdown(paper)),
          icon: const Icon(Icons.file_open_outlined),
        ),
      _collapseButton(context, isCollapsed),
      PopupMenuButton<double>(
        tooltip: _tooltipLabel(
          enableToolTips,
          strings.get(PaperTodoStringKeys.actionPaperTextZoom),
        ),
        icon: const Icon(Icons.text_fields),
        initialValue: textZoom,
        onSelected: (value) => _setTextZoom(value),
        itemBuilder: (context) {
          return [
            for (final option in _TextZoomOption.values)
              CheckedPopupMenuItem<double>(
                value: option.value,
                checked: option.value == textZoom,
                child: Text(option.label),
              ),
          ];
        },
      ),
      IconButton(
        tooltip: _tooltipLabel(
          enableToolTips,
          paper.alwaysOnTop
              ? strings.get(PaperTodoStringKeys.actionDisableAlwaysOnTop)
              : strings.get(PaperTodoStringKeys.actionKeepOnTop),
        ),
        onPressed: _toggleAlwaysOnTop,
        icon:
            Icon(paper.alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined),
      ),
      IconButton(
        tooltip: _tooltipLabel(
          enableToolTips,
          paper.isPinnedToDesktop
              ? strings.get(PaperTodoStringKeys.actionUnpinFromDesktop)
              : strings.get(PaperTodoStringKeys.actionPinToDesktop),
        ),
        onPressed: _togglePinnedToDesktop,
        icon: Icon(paper.isPinnedToDesktop
            ? Icons.desktop_windows
            : Icons.desktop_windows_outlined),
      ),
      IconButton(
        tooltip: _tooltipLabel(
          enableToolTips,
          strings.get(PaperTodoStringKeys.actionSaveWindowBounds),
        ),
        onPressed: () => unawaited(onCaptureBounds(paper)),
        icon: const Icon(Icons.aspect_ratio_outlined),
      ),
      IconButton(
        tooltip: _tooltipLabel(
          enableToolTips,
          hideThisPaperLabel,
        ),
        onPressed: () => unawaited(onHide(paper)),
        icon: const Icon(Icons.visibility_off_outlined),
      ),
      IconButton(
        tooltip: _tooltipLabel(
          enableToolTips,
          strings.get(PaperTodoStringKeys.actionDeletePaper),
        ),
        onPressed: () => unawaited(onDelete(paper)),
        icon: const Icon(Icons.delete_outline),
      ),
    ];
  }

  List<Widget> _standalonePaperHeaderActions({
    required BuildContext context,
    required bool isCollapsed,
    required bool desktopInteractionLocked,
  }) {
    if (desktopInteractionLocked) {
      return [_pinnedDesktopUnlockButton(context)];
    }
    final strings = PaperTodoStringsScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final hideOptionalCreationButtons = width < (paper.isNote ? 300 : 255);
    final actions = <Widget>[
      if (!hideOptionalCreationButtons && showTopBarNewTodoButton)
        _standaloneHeaderButton(
          key: ValueKey('${paper.id}-new-todo'),
          tooltip: strings.get(PaperTodoStringKeys.actionNewTodoPaper),
          onPressed: () => unawaited(
            onCreatePaper(PaperTypes.todo, sourcePaper: paper),
          ),
          child: const Text(
            '+✓',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
      if (!hideOptionalCreationButtons && showTopBarNewNoteButton)
        _standaloneHeaderButton(
          key: ValueKey('${paper.id}-new-note'),
          tooltip: strings.get(PaperTodoStringKeys.actionNewNotePaper),
          onPressed: () => unawaited(
            onCreatePaper(PaperTypes.note, sourcePaper: paper),
          ),
          child: const Text(
            '+✎',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
      if (paper.isNote && enableTodoNoteLinks)
        SizedBox(
          width: 24,
          height: 24,
          child: _noteLinkDragHandle(context),
        ),
      if (paper.isNote && showTopBarExternalOpenButton)
        _standaloneHeaderButton(
          key: ValueKey('${paper.id}-open-markdown'),
          tooltip: _openMarkdownEditorLabel(strings),
          onPressed: () => unawaited(onOpenExternalMarkdown(paper)),
          child: const Text(
            'MD',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500),
          ),
        ),
      _standaloneHeaderButton(
        key: ValueKey('${paper.id}-desktop-pin'),
        tooltip: paper.isPinnedToDesktop
            ? strings.get(PaperTodoStringKeys.actionUnpinFromDesktop)
            : strings.get(PaperTodoStringKeys.actionPinToDesktop),
        onPressed: _togglePinnedToDesktop,
        child: Icon(
          paper.isPinnedToDesktop ? Icons.push_pin : Icons.push_pin_outlined,
          size: 15,
        ),
      ),
      _standaloneHeaderButton(
        key: ValueKey('${paper.id}-close'),
        tooltip: useCapsuleMode
            ? strings.get(PaperTodoStringKeys.actionCollapsePaper)
            : strings.get(PaperTodoStringKeys.actionHideThisPaper),
        onPressed:
            useCapsuleMode ? _toggleCollapsed : () => unawaited(onHide(paper)),
        child: const Icon(Icons.remove, size: 16),
      ),
    ];
    return actions;
  }

  Widget _standalonePaperTypeButton(
    BuildContext context, {
    required ScriptCapsuleSpec? scriptCapsuleSpec,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = PaperTodoStringsScope.of(context);
    final active = paper.alwaysOnTop;
    return _standaloneHeaderButton(
      key: ValueKey('${paper.id}-topmost'),
      width: 23,
      tooltip: active
          ? strings.get(PaperTodoStringKeys.actionDisableAlwaysOnTop)
          : strings.get(PaperTodoStringKeys.actionKeepOnTop),
      onPressed: _desktopInteractionLocked ? null : _toggleAlwaysOnTop,
      child: Icon(
        paper.isTodo
            ? Icons.check_box
            : scriptCapsuleSpec != null
                ? Icons.bolt_outlined
                : Icons.edit_outlined,
        size: paper.isNote ? 15 : 14,
        color: active ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _standaloneHeaderButton({
    Key? key,
    required String tooltip,
    required VoidCallback? onPressed,
    required Widget child,
    double width = 28,
  }) {
    return SizedBox(
      key: key,
      width: width,
      height: 24,
      child: _conditionalTooltip(
        enabled: enableToolTips,
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          splashRadius: 14,
          iconSize: 16,
          icon: child,
        ),
      ),
    );
  }

  IconButton _pinnedDesktopUnlockButton(BuildContext context) {
    final strings = PaperTodoStringsScope.of(context);
    return IconButton(
      tooltip: _tooltipLabel(
        enableToolTips,
        strings.get(PaperTodoStringKeys.actionUnpinFromDesktop),
      ),
      onPressed: _togglePinnedToDesktop,
      icon: const Icon(Icons.desktop_windows),
    );
  }

  String _openMarkdownEditorLabel(PaperTodoStrings strings) {
    return _markdownEditorActionLabel(strings, externalMarkdownExtension);
  }

  IconButton _collapseButton(BuildContext context, bool isCollapsed) {
    final strings = PaperTodoStringsScope.of(context);
    final mobileBoard =
        !standaloneSurface && MediaQuery.sizeOf(context).shortestSide < 600;
    return IconButton(
      tooltip: _tooltipLabel(
        enableToolTips,
        collapseAllActive
            ? strings.get(PaperTodoStringKeys.collapseAllActive)
            : paper.isCollapsed
                ? strings.get(PaperTodoStringKeys.actionExpandPaper)
                : strings.get(PaperTodoStringKeys.actionCollapsePaper),
      ),
      onPressed: collapseAllActive ? null : _toggleCollapsed,
      style: mobileBoard
          ? IconButton.styleFrom(
              minimumSize: const Size.square(48),
              maximumSize: const Size.square(48),
              padding: EdgeInsets.zero,
            )
          : null,
      icon: Icon(isCollapsed ? Icons.expand_more : Icons.expand_less),
    );
  }

  void _handlePaperContextMenuPointerDown(
    BuildContext context,
    PointerDownEvent event,
  ) {
    if (_desktopInteractionLocked ||
        event.buttons & kSecondaryMouseButton == 0) {
      return;
    }
    unawaited(_showPaperContextMenu(context, event.position));
  }

  Future<void> _showPaperContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (overlay is! RenderBox) {
      return;
    }
    final selected = await showMenu<String>(
      context: context,
      requestFocus: false,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: _paperContextMenuItems(context),
    );
    if (!context.mounted || selected == null) {
      return;
    }
    _handleCompactPaperAction(selected);
  }

  List<PopupMenuEntry<String>> _paperContextMenuItems(BuildContext context) {
    final strings = PaperTodoStringsScope.of(context);
    final hideThisPaperLabel =
        strings.get(PaperTodoStringKeys.actionHideThisPaper);
    final openMarkdownEditorLabel = _openMarkdownEditorLabel(strings);
    final textZoom = paper.textZoom.clamp(0.5, 1.5).toDouble();
    if (_desktopInteractionLocked) {
      return [
        _paperTodoMenuHeader(
          strings.get(PaperTodoStringKeys.menuDesktopPin),
        ),
        _paperActionMenuItem(
          value: _compactPaperActionTogglePinned,
          icon: Icons.desktop_windows,
          label: strings.get(PaperTodoStringKeys.actionUnpinFromDesktop),
        ),
      ];
    }
    return [
      _paperTodoMenuHeader(strings.get(PaperTodoStringKeys.menuNew)),
      _paperActionMenuItem(
        value: _compactPaperActionNewTodo,
        icon: Icons.add_task,
        label: strings.get(PaperTodoStringKeys.actionNewTodoPaper),
      ),
      _paperActionMenuItem(
        value: _compactPaperActionNewNote,
        icon: Icons.note_add_outlined,
        label: strings.get(PaperTodoStringKeys.actionNewNotePaper),
      ),
      if (paper.isTodo) ...[
        const PopupMenuDivider(),
        _paperTodoMenuHeader(strings.get(PaperTodoStringKeys.menuTodo)),
        _paperActionMenuItem(
          value: _compactPaperActionClearDone,
          icon: Icons.delete_sweep_outlined,
          label: strings.get(PaperTodoStringKeys.actionClearCompleted),
          enabled: _hasDoneTodoItems,
        ),
      ],
      if (_canAddCanvasBlockFromPaperMenu) ...[
        const PopupMenuDivider(),
        _paperTodoMenuHeader(strings.get(PaperTodoStringKeys.menuCanvas)),
        _paperActionMenuItem(
          value: _compactPaperActionAddCanvasBlock,
          icon: Icons.add_box_outlined,
          label: strings.get(PaperTodoStringKeys.actionAddCanvasBlock),
        ),
      ],
      const PopupMenuDivider(),
      _paperTodoMenuHeader(_displayPaperTitle()),
      _paperActionMenuItem(
        value: _compactPaperActionOpenSurface,
        icon: Icons.open_in_new,
        label: strings.get(PaperTodoStringKeys.actionOpenSurface),
      ),
      if (paper.isNote)
        _paperActionMenuItem(
          value: _compactPaperActionOpenMarkdown,
          icon: Icons.file_open_outlined,
          label: openMarkdownEditorLabel,
        ),
      const PopupMenuDivider(),
      for (final option in _TextZoomOption.values)
        CheckedPopupMenuItem<String>(
          value: '$_compactPaperZoomActionPrefix${option.value}',
          checked: option.value == textZoom,
          child: Text('${strings.get(PaperTodoStringKeys.zoom)} '
              '${option.label}'),
        ),
      const PopupMenuDivider(),
      _paperTodoMenuHeader(strings.get(PaperTodoStringKeys.menuDesktopPin)),
      _paperActionMenuItem(
        value: _compactPaperActionToggleAlwaysOnTop,
        icon: paper.alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
        label: paper.alwaysOnTop
            ? strings.get(PaperTodoStringKeys.actionDisableAlwaysOnTop)
            : strings.get(PaperTodoStringKeys.actionKeepOnTop),
      ),
      _paperActionMenuItem(
        value: _compactPaperActionTogglePinned,
        icon: paper.isPinnedToDesktop
            ? Icons.desktop_windows
            : Icons.desktop_windows_outlined,
        label: paper.isPinnedToDesktop
            ? strings.get(PaperTodoStringKeys.actionUnpinFromDesktop)
            : strings.get(PaperTodoStringKeys.actionPinToDesktop),
      ),
      if (!collapseAllActive)
        _paperActionMenuItem(
          value: _compactPaperActionToggleCollapsed,
          icon: paper.isCollapsed ? Icons.expand_more : Icons.expand_less,
          label: paper.isCollapsed
              ? strings.get(PaperTodoStringKeys.actionRestoreWindow)
              : strings.get(PaperTodoStringKeys.actionCollapseToCapsule),
        ),
      _paperActionMenuItem(
        value: _compactPaperActionCaptureBounds,
        icon: Icons.aspect_ratio_outlined,
        label: strings.get(PaperTodoStringKeys.actionSaveWindowBounds),
      ),
      const PopupMenuDivider(),
      _paperActionMenuItem(
        value: _compactPaperActionHide,
        icon: Icons.visibility_off_outlined,
        label: hideThisPaperLabel,
      ),
      _paperActionMenuItem(
        value: _compactPaperActionDelete,
        icon: Icons.delete_outline,
        label: strings.get(PaperTodoStringKeys.actionDeletePaper),
      ),
    ];
  }

  PopupMenuItem<String> _paperActionMenuItem({
    required String value,
    required IconData icon,
    required String label,
    bool enabled = true,
  }) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      height: _paperTodoPopupMenuHeight(),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }

  void _handleCompactPaperAction(String value) {
    if (value.startsWith(_compactPaperZoomActionPrefix)) {
      _setTextZoom(
        double.parse(value.substring(_compactPaperZoomActionPrefix.length)),
      );
      return;
    }
    switch (value) {
      case _compactPaperActionNewTodo:
        unawaited(onCreatePaper(PaperTypes.todo, sourcePaper: paper));
      case _compactPaperActionNewNote:
        unawaited(onCreatePaper(PaperTypes.note, sourcePaper: paper));
      case _compactPaperActionClearDone:
        _clearDoneTodoItemsFromPaperMenu();
      case _compactPaperActionAddCanvasBlock:
        _addNoteCanvasBlockFromPaperMenu();
      case _compactPaperActionOpenSurface:
        unawaited(onOpen(paper));
      case _compactPaperActionOpenMarkdown:
        unawaited(onOpenExternalMarkdown(paper));
      case _compactPaperActionToggleAlwaysOnTop:
        _toggleAlwaysOnTop();
      case _compactPaperActionTogglePinned:
        _togglePinnedToDesktop();
      case _compactPaperActionToggleCollapsed:
        _toggleCollapsed();
      case _compactPaperActionCaptureBounds:
        unawaited(onCaptureBounds(paper));
      case _compactPaperActionHide:
        unawaited(onHide(paper));
      case _compactPaperActionDelete:
        unawaited(onDelete(paper));
    }
  }

  bool get _hasDoneTodoItems {
    return paper.items.any((item) => item.done);
  }

  bool get _canAddCanvasBlockFromPaperMenu {
    return paper.isNote &&
        !paper.isCollapsed &&
        !collapseAllActive &&
        !paper.isPinnedToDesktop;
  }

  void _clearDoneTodoItemsFromPaperMenu() {
    if (!paper.isTodo) {
      return;
    }
    final completedItems = paper.items.where((item) => item.done).toList();
    if (completedItems.isEmpty) {
      return;
    }
    final completedIds = completedItems.map((item) => item.id).toSet();
    paper.items = [
      for (final item in paper.items)
        if (!completedIds.contains(item.id)) item,
    ];
    if (paper.items.isEmpty) {
      paper.items.add(_newTodoItemFromPaperMenu());
    }
    paper.normalize();
    for (final item in completedItems) {
      onTodoItemDeleted(paper, item);
    }
    unawaited(onChanged());
  }

  PaperItem _newTodoItemFromPaperMenu() {
    return PaperItem(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
    );
  }

  void _addNoteCanvasBlockFromPaperMenu() {
    if (!_canAddCanvasBlockFromPaperMenu) {
      return;
    }
    final elements = paper.noteCanvasElements;
    const width = 230.0;
    const height = 116.0;
    final point = _nextNoteCanvasElementPointFromPaperMenu(
      width,
      height,
      elements.length,
    );
    elements.add(
      NoteCanvasElement(
        id: _newCanvasElementIdFromPaperMenu(),
        type: NoteCanvasElementTypes.code,
        text: 'Console.WriteLine("PaperTodo");',
        x: point.dx,
        y: point.dy,
        width: width,
        height: height,
        zIndex: _maxCanvasElementLayer(elements) + 10,
      ),
    );
    paper.normalize();
    unawaited(onChanged());
  }

  String _newCanvasElementIdFromPaperMenu() {
    final existingIds = paper.noteCanvasElements.map((element) => element.id);
    return _newUniqueChildId(existingIds);
  }

  Offset _nextNoteCanvasElementPointFromPaperMenu(
    double width,
    double height,
    int existingCount,
  ) {
    final layerWidth = math.max(220.0, paper.width - 40);
    final layerHeight = math.max(160.0, paper.height - 90);
    final offset = math.min(80.0, existingCount * 12.0);
    final x = math.max(
      10.0,
      math.min(layerWidth - width - 10.0, 28.0 + offset),
    );
    final y = math.max(
      10.0,
      math.min(layerHeight - height - 10.0, 28.0 + offset),
    );
    return Offset(x, y);
  }

  int _maxCanvasElementLayer(List<NoteCanvasElement> elements) {
    if (elements.isEmpty) {
      return 0;
    }
    return elements
        .map((element) => element.zIndex)
        .reduce((max, zIndex) => zIndex > max ? zIndex : max);
  }

  String _newUniqueChildId(Iterable<String> existingIds) {
    final usedIds = existingIds.toSet();
    var id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    var suffix = 1;
    while (usedIds.contains(id)) {
      id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-$suffix';
      suffix += 1;
    }
    return id;
  }

  void _toggleCollapsed() {
    if (paper.isPinnedToDesktop && paper.isCollapsed) {
      unawaited(onSetPinnedToDesktop(paper, false));
      return;
    }
    paper.isCollapsed = !paper.isCollapsed;
    unawaited(onChanged());
  }

  void _openCollapsedScriptCapsuleForEditing() {
    if (!paper.isCollapsed) {
      return;
    }
    paper.isCollapsed = false;
    unawaited(onChanged());
  }

  void _toggleAlwaysOnTop() {
    unawaited(onSetAlwaysOnTop(paper, !paper.alwaysOnTop));
  }

  void _togglePinnedToDesktop() {
    unawaited(onSetPinnedToDesktop(paper, !paper.isPinnedToDesktop));
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !paper.isNote ||
        !HardwareKeyboard.instance.isControlPressed ||
        _desktopInteractionLocked) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (event) => _setTextZoom(_textZoomAfterWheel(event as PointerScrollEvent)),
    );
  }

  bool get _desktopInteractionLocked =>
      paper.isPinnedToDesktop && !paper.isCollapsed;

  double _textZoomAfterWheel(PointerScrollEvent event) {
    final step = event.scrollDelta.dy < 0 ? 0.1 : -0.1;
    return ((paper.textZoom + step).clamp(0.5, 1.5) * 10).round() / 10;
  }

  void _setTextZoom(double value) {
    paper.textZoom = value.clamp(0.5, 1.5).toDouble();
    unawaited(onSurfaceChanged(paper));
    unawaited(onChanged());
  }

  String _displayPaperTitle() {
    return titleText;
  }
}

class _PaperTitleEditor extends StatefulWidget {
  const _PaperTitleEditor({
    required this.paper,
    required this.titleText,
    required this.textZoom,
    required this.enabled,
    required this.fieldEnabled,
    required this.enableToolTips,
    this.compact = false,
    required this.onTitleChanged,
  });

  final PaperData paper;
  final String titleText;
  final double textZoom;
  final bool enabled;
  final bool fieldEnabled;
  final bool enableToolTips;
  final bool compact;
  final Future<void> Function(PaperData paper) onTitleChanged;

  @override
  State<_PaperTitleEditor> createState() => _PaperTitleEditorState();
}

class _PaperTitleEditorState extends State<_PaperTitleEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isEditingTitle = false;
  String _titleBeforeEdit = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayTitle);
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _PaperTitleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paper.id != widget.paper.id) {
      _isEditingTitle = false;
      _titleBeforeEdit = '';
      _syncControllerToDisplayTitle();
      return;
    }
    if (!_isEditingTitle) {
      _syncControllerToDisplayTitle();
    } else if (!widget.enabled) {
      unawaited(_endTitleEdit(commit: true));
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = PaperTodoStringsScope.of(context);
    final editTitleLabel = strings.get(PaperTodoStringKeys.actionEditTitle);
    final field = SizedBox(
      height: widget.compact ? 24 : 28,
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: TextFormField(
          key: ValueKey('${widget.paper.id}-title'),
          controller: _controller,
          focusNode: _focusNode,
          inputFormatters: const [
            _PaperTitleTextInputFormatter(
              maxLength: PaperTitles.maxTitleLength,
            ),
          ],
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
            hintText: strings.get(PaperTodoStringKeys.untitledPaper),
            isDense: true,
          ),
          enabled: widget.fieldEnabled,
          readOnly: !_isEditingTitle,
          showCursor: _isEditingTitle,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          style: (widget.compact
                  ? theme.textTheme.labelMedium
                  : theme.textTheme.titleMedium)
              ?.apply(
                fontSizeFactor: widget.textZoom,
              )
              .copyWith(
                height: 1,
                fontSize: widget.compact ? 11 : null,
                fontWeight: widget.compact ? FontWeight.w600 : null,
              ),
          onTap: _beginTitleEdit,
          onChanged: _handleTitleChanged,
          onFieldSubmitted: (_) => unawaited(_endTitleEdit(commit: true)),
        ),
      ),
    );
    return Semantics(
      button: widget.enabled && !_isEditingTitle,
      textField: _isEditingTitle,
      label: editTitleLabel,
      child: _conditionalTooltip(
        enabled: widget.enableToolTips,
        message: editTitleLabel,
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.text
              : SystemMouseCursors.basic,
          child: field,
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_isEditingTitle) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(_endTitleEdit(commit: false));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      unawaited(_endTitleEdit(commit: true));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      if (!_isEditingTitle) {
        _beginTitleEdit();
      }
      return;
    }
    if (_isEditingTitle) {
      unawaited(_endTitleEdit(commit: true));
    }
  }

  void _beginTitleEdit() {
    if (!widget.enabled) {
      return;
    }
    if (_isEditingTitle) {
      _selectAll();
      return;
    }
    _titleBeforeEdit = widget.paper.title;
    final title = _displayTitle;
    setState(() {
      _isEditingTitle = true;
      _controller.value = TextEditingValue(
        text: title,
        selection: TextSelection(baseOffset: 0, extentOffset: title.length),
      );
    });
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isEditingTitle) {
        _selectAll();
      }
    });
  }

  void _selectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  void _handleTitleChanged(String value) {
    if (!_isEditingTitle) {
      return;
    }
    final cleaned = PaperTitles.cleanCustomTitle(value);
    if (widget.paper.title == cleaned) {
      return;
    }
    widget.paper.title = cleaned;
    unawaited(widget.onTitleChanged(widget.paper));
  }

  Future<void> _endTitleEdit({required bool commit}) async {
    if (!_isEditingTitle) {
      return;
    }
    final nextTitle = commit
        ? PaperTitles.cleanCustomTitle(_controller.text)
        : _titleBeforeEdit;
    final changed = widget.paper.title != nextTitle;
    setState(() {
      _isEditingTitle = false;
      widget.paper.title = nextTitle;
      _syncControllerToDisplayTitle();
    });
    _focusNode.unfocus();
    if (changed || !commit) {
      await widget.onTitleChanged(widget.paper);
    }
  }

  void _syncControllerToDisplayTitle() {
    final title = _displayTitle;
    if (_controller.text == title) {
      return;
    }
    _controller.value = TextEditingValue(
      text: title,
      selection: TextSelection.collapsed(offset: title.length),
    );
  }

  String get _displayTitle {
    final customTitle = PaperTitles.cleanCustomTitle(widget.paper.title);
    return customTitle.isEmpty ? widget.titleText : customTitle;
  }
}

class _TextZoomOption {
  const _TextZoomOption(this.value, this.label);

  final double value;
  final String label;

  static const values = [
    _TextZoomOption(0.75, '75%'),
    _TextZoomOption(1, '100%'),
    _TextZoomOption(1.25, '125%'),
    _TextZoomOption(1.5, '150%'),
  ];
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({
    required this.paper,
    required this.markdownRenderMode,
    required this.lineSpacing,
    required this.textZoom,
    required this.enableToolTips,
    required this.onOpenUri,
    required this.onChanged,
    required this.onTextZoomChanged,
    required this.onShowPaperContextMenu,
  });

  final PaperData paper;
  final String markdownRenderMode;
  final double lineSpacing;
  final double textZoom;
  final bool enableToolTips;
  final Future<void> Function(String uri) onOpenUri;
  final Future<void> Function() onChanged;
  final void Function(double value) onTextZoomChanged;
  final Future<void> Function(BuildContext context, Offset globalPosition)
      onShowPaperContextMenu;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  static const _viewEdit = 'edit';
  static const _viewPreview = 'preview';
  static const _viewSplit = 'split';
  static const _markdownActionStrikethrough = 'strikethrough';
  static const _markdownActionHeading = 'heading';
  static const _markdownActionQuote = 'quote';
  static const _markdownActionList = 'list';
  static const _markdownActionCodeBlock = 'code-block';
  static const _markdownActionBold = 'bold';
  static const _markdownActionItalic = 'italic';
  static const _markdownActionInsertLink = 'insert-link';
  static const _markdownActionCopy = 'copy';
  static const _markdownActionPaste = 'paste';
  static const _markdownActionSelectAll = 'select-all';

  late final TextEditingController _contentController;
  late final FocusNode _contentFocusNode;
  late String _view = _defaultView(widget.markdownRenderMode, widget.paper);
  bool _toolbarInteractionActive = false;
  bool _enteringEditorFromPreview = false;
  bool _previewLinkActivated = false;
  bool _previewPrimaryPointer = false;
  String? _selectedCanvasElementId;

  PaperTodoStrings get strings => PaperTodoStringsScope.of(context);

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.paper.content);
    _contentFocusNode = FocusNode();
    _contentFocusNode.addListener(_handleEditorFocusChange);
  }

  @override
  void didUpdateWidget(covariant _NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdownRenderMode != widget.markdownRenderMode) {
      _view = _defaultView(widget.markdownRenderMode, widget.paper);
    }
    if (oldWidget.paper.id != widget.paper.id ||
        widget.paper.content != _contentController.text) {
      final offset = _contentController.selection.baseOffset
          .clamp(0, widget.paper.content.length)
          .toInt();
      _contentController.value = TextEditingValue(
        text: widget.paper.content,
        selection: TextSelection.collapsed(offset: offset),
      );
    }
    if (_selectedCanvasElementId != null &&
        !widget.paper.noteCanvasElements.any(
          (element) => element.id == _selectedCanvasElementId,
        )) {
      _selectedCanvasElementId = null;
    }
  }

  @override
  void dispose() {
    _contentFocusNode.removeListener(_handleEditorFocusChange);
    _contentFocusNode.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = MarkdownRenderModes.normalize(widget.markdownRenderMode);
    if (mode == MarkdownRenderModes.off) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _noteCanvasToolbar(),
          _notePaperSurface(
            _editor(context, minLines: 4, maxLines: 12),
          ),
          if (widget.paper.noteCanvasElements.isNotEmpty) ...[
            const SizedBox(height: 8),
            _canvasPreview(),
          ],
          _noteStatusBar(context, _viewEdit),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _noteCanvasToolbar(),
        _notePaperSurface(
          _safeView(mode) == _viewPreview
              ? _preview(context)
              : _editor(context, minLines: 4, maxLines: 12),
        ),
        if (widget.paper.noteCanvasElements.isNotEmpty) ...[
          const SizedBox(height: 8),
          _canvasPreview(),
        ],
        _noteStatusBar(context, _safeView(mode)),
      ],
    );
  }

  Widget _noteCanvasToolbar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 31),
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 3),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.025),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;
          return Row(
            children: [
              _addCanvasButton(compact: compact),
              const Spacer(),
              Flexible(
                child: Text(
                  '${widget.paper.noteCanvasElements.length} elements',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _notePaperSurface(Widget child) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(1, 6, 1, 0),
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.035),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.75),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              left: 14,
              top: 14,
              bottom: 14,
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 5, 4),
              child: child,
            ),
          ],
        ),
      ),
    );
  }

  Widget _editor(
    BuildContext context, {
    required int minLines,
    required int maxLines,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _markdownToolbar(context),
        const SizedBox(height: 8),
        Focus(
          onKeyEvent: _handleMarkdownKeyEvent,
          child: Listener(
            onPointerDown: (event) =>
                _handleMarkdownEditorContextMenuPointerDown(context, event),
            child: TextFormField(
              key: ValueKey('${widget.paper.id}-content'),
              controller: _contentController,
              focusNode: _contentFocusNode,
              onTapAlwaysCalled: true,
              onTap: () => _handleEditorTap(context),
              minLines: minLines,
              maxLines: maxLines,
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: strings.get(PaperTodoStringKeys.noteEditorHint),
              ),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.apply(
                    fontSizeFactor: widget.textZoom,
                  )
                  .copyWith(height: widget.lineSpacing),
              inputFormatters: const [
                _MarkdownPasteTextInputFormatter(),
                _MarkdownListContinuationTextInputFormatter(),
              ],
              onChanged: _commitContent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _markdownToolbar(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    return Listener(
      onPointerDown: (_) => _beginToolbarInteraction(),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _formatButton(
            tooltip:
                strings.get(PaperTodoStringKeys.markdownActionBoldShortcut),
            icon: Icons.format_bold,
            onPressed: _formatBold,
          ),
          _formatButton(
            tooltip:
                strings.get(PaperTodoStringKeys.markdownActionItalicShortcut),
            icon: Icons.format_italic,
            onPressed: _formatItalic,
          ),
          if (!compact) ...[
            _formatButton(
              tooltip:
                  strings.get(PaperTodoStringKeys.markdownActionStrikethrough),
              icon: Icons.strikethrough_s,
              onPressed: _formatStrikethrough,
            ),
            _formatButton(
              tooltip: strings.get(PaperTodoStringKeys.markdownActionHeading),
              icon: Icons.title,
              onPressed: _formatHeading,
            ),
            _formatButton(
              tooltip: strings.get(PaperTodoStringKeys.markdownActionQuote),
              icon: Icons.format_quote,
              onPressed: _formatQuote,
            ),
            _formatButton(
              tooltip: strings.get(PaperTodoStringKeys.markdownActionList),
              icon: Icons.format_list_bulleted,
              onPressed: _formatList,
            ),
            _formatButton(
              tooltip: strings.get(PaperTodoStringKeys.markdownActionCodeBlock),
              icon: Icons.code,
              onPressed: _formatCodeBlock,
            ),
          ],
          _formatButton(
            tooltip: strings.get(
              PaperTodoStringKeys.markdownActionInsertLinkShortcut,
            ),
            icon: Icons.link,
            onPressed: _insertMarkdownLink,
          ),
          if (compact) _compactMarkdownActions(),
        ],
      ),
    );
  }

  Widget _formatButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton.outlined(
      tooltip: _tooltipLabel(widget.enableToolTips, tooltip),
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }

  Widget _compactMarkdownActions() {
    return PopupMenuButton<String>(
      key: const ValueKey('compact-markdown-toolbar-actions'),
      tooltip: _tooltipLabel(
        widget.enableToolTips,
        strings.get(PaperTodoStringKeys.markdownActionMore),
      ),
      icon: const Icon(Icons.more_vert),
      onOpened: _beginToolbarInteraction,
      onCanceled: _endToolbarInteraction,
      onSelected: (value) {
        _handleCompactMarkdownAction(value);
        _endToolbarInteraction();
      },
      itemBuilder: (context) => [
        _markdownMenuItem(
          value: _markdownActionStrikethrough,
          icon: Icons.strikethrough_s,
          label: strings.get(PaperTodoStringKeys.markdownActionStrikethrough),
        ),
        _markdownMenuItem(
          value: _markdownActionHeading,
          icon: Icons.title,
          label: strings.get(PaperTodoStringKeys.markdownActionHeading),
        ),
        _markdownMenuItem(
          value: _markdownActionQuote,
          icon: Icons.format_quote,
          label: strings.get(PaperTodoStringKeys.markdownActionQuote),
        ),
        _markdownMenuItem(
          value: _markdownActionList,
          icon: Icons.format_list_bulleted,
          label: strings.get(PaperTodoStringKeys.markdownActionList),
        ),
        _markdownMenuItem(
          value: _markdownActionCodeBlock,
          icon: Icons.code,
          label: strings.get(PaperTodoStringKeys.markdownActionCodeBlock),
        ),
      ],
    );
  }

  PopupMenuItem<String> _markdownMenuItem({
    required String value,
    required IconData icon,
    required String label,
    bool enabled = true,
  }) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      height: _paperTodoPopupMenuHeight(),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }

  void _handleMarkdownEditorContextMenuPointerDown(
    BuildContext context,
    PointerDownEvent event,
  ) {
    if (event.buttons & kSecondaryMouseButton == 0) {
      return;
    }
    unawaited(_showMarkdownEditorContextMenu(context, event.position));
  }

  Future<void> _showMarkdownEditorContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (overlay is! RenderBox) {
      return;
    }
    _beginToolbarInteraction();
    try {
      final selected = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
          Offset.zero & overlay.size,
        ),
        items: _markdownEditorContextMenuItems(),
      );
      if (!mounted || !context.mounted || selected == null) {
        return;
      }
      await _handleMarkdownEditorContextAction(selected);
    } finally {
      _endToolbarInteraction();
    }
  }

  List<PopupMenuEntry<String>> _markdownEditorContextMenuItems() {
    final hasSelection = _contentController.selection.isValid &&
        !_contentController.selection.isCollapsed;
    final hasText = _contentController.text.isNotEmpty;
    return [
      _paperTodoMenuHeader(strings.get(PaperTodoStringKeys.menuFormat)),
      _markdownMenuItem(
        value: _markdownActionBold,
        icon: Icons.format_bold,
        label: strings.get(PaperTodoStringKeys.markdownActionBold),
      ),
      _markdownMenuItem(
        value: _markdownActionItalic,
        icon: Icons.format_italic,
        label: strings.get(PaperTodoStringKeys.markdownActionItalic),
      ),
      _markdownMenuItem(
        value: _markdownActionStrikethrough,
        icon: Icons.strikethrough_s,
        label: strings.get(PaperTodoStringKeys.markdownActionStrikethrough),
      ),
      _markdownMenuItem(
        value: _markdownActionHeading,
        icon: Icons.title,
        label: strings.get(PaperTodoStringKeys.markdownActionHeading),
      ),
      _markdownMenuItem(
        value: _markdownActionQuote,
        icon: Icons.format_quote,
        label: strings.get(PaperTodoStringKeys.markdownActionQuote),
      ),
      _markdownMenuItem(
        value: _markdownActionList,
        icon: Icons.format_list_bulleted,
        label: strings.get(PaperTodoStringKeys.markdownActionList),
      ),
      _markdownMenuItem(
        value: _markdownActionCodeBlock,
        icon: Icons.code,
        label: strings.get(PaperTodoStringKeys.markdownActionCodeBlock),
      ),
      _markdownMenuItem(
        value: _markdownActionInsertLink,
        icon: Icons.link,
        label: strings.get(PaperTodoStringKeys.markdownActionInsertLink),
      ),
      const PopupMenuDivider(),
      _paperTodoMenuHeader(strings.get(PaperTodoStringKeys.menuText)),
      _markdownMenuItem(
        value: _markdownActionCopy,
        icon: Icons.content_copy_outlined,
        label: strings.get(PaperTodoStringKeys.actionCopy),
        enabled: hasSelection,
      ),
      _markdownMenuItem(
        value: _markdownActionPaste,
        icon: Icons.content_paste_outlined,
        label: strings.get(PaperTodoStringKeys.actionPaste),
      ),
      _markdownMenuItem(
        value: _markdownActionSelectAll,
        icon: Icons.select_all,
        label: strings.get(PaperTodoStringKeys.actionSelectAll),
        enabled: hasText,
      ),
    ];
  }

  void _formatBold() {
    _applyMarkdownFormat(
      (value) => MarkdownFormatting.wrapSelection(value, '**', '**'),
    );
  }

  void _formatItalic() {
    _applyMarkdownFormat(
      (value) => MarkdownFormatting.wrapSelection(value, '*', '*'),
    );
  }

  void _insertMarkdownLink() {
    _applyMarkdownFormat(MarkdownFormatting.insertMarkdownLink);
  }

  void _formatStrikethrough() {
    _applyMarkdownFormat(
      (value) => MarkdownFormatting.wrapSelection(value, '~~', '~~'),
    );
  }

  void _formatHeading() {
    _applyMarkdownFormat(
      (value) => MarkdownFormatting.insertLinePrefix(value, '# '),
    );
  }

  void _formatQuote() {
    _applyMarkdownFormat(
      (value) => MarkdownFormatting.insertLinePrefix(value, '> '),
    );
  }

  void _formatList() {
    _applyMarkdownFormat(
      (value) => MarkdownFormatting.insertLinePrefix(value, '- '),
    );
  }

  void _formatCodeBlock() {
    _applyMarkdownFormat(
      (value) => MarkdownFormatting.wrapSelection(
        value,
        '```\n',
        '\n```',
      ),
    );
  }

  void _handleCompactMarkdownAction(String value) {
    switch (value) {
      case _markdownActionStrikethrough:
        _formatStrikethrough();
      case _markdownActionHeading:
        _formatHeading();
      case _markdownActionQuote:
        _formatQuote();
      case _markdownActionList:
        _formatList();
      case _markdownActionCodeBlock:
        _formatCodeBlock();
    }
  }

  Future<void> _handleMarkdownEditorContextAction(String value) async {
    switch (value) {
      case _markdownActionBold:
        _formatBold();
      case _markdownActionItalic:
        _formatItalic();
      case _markdownActionInsertLink:
        _insertMarkdownLink();
      case _markdownActionCopy:
        await _copyMarkdownSelection();
      case _markdownActionPaste:
        await _pasteMarkdownClipboardText();
      case _markdownActionSelectAll:
        _selectAllMarkdownText();
      default:
        _handleCompactMarkdownAction(value);
    }
  }

  Future<void> _copyMarkdownSelection() async {
    final selection = _contentController.selection;
    if (!selection.isValid || selection.isCollapsed) {
      _contentFocusNode.requestFocus();
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: selection.textInside(_contentController.text)),
    );
    _contentFocusNode.requestFocus();
  }

  Future<void> _pasteMarkdownClipboardText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasteText = data?.text;
    if (pasteText == null || pasteText.isEmpty) {
      _contentFocusNode.requestFocus();
      return;
    }
    final oldValue = _contentController.value;
    final selection = oldValue.selection.isValid
        ? oldValue.selection
        : TextSelection.collapsed(offset: oldValue.text.length);
    final rawValue = TextEditingValue(
      text: '${selection.textBefore(oldValue.text)}'
          '$pasteText'
          '${selection.textAfter(oldValue.text)}',
      selection: TextSelection.collapsed(
        offset: selection.textBefore(oldValue.text).length + pasteText.length,
      ),
    );
    final formattedValue =
        MarkdownPasteText.formatEditUpdate(oldValue, rawValue);
    _contentController.value = formattedValue;
    _commitContent(formattedValue.text);
    _contentFocusNode.requestFocus();
  }

  void _selectAllMarkdownText() {
    _contentController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _contentController.text.length,
    );
    _contentFocusNode.requestFocus();
  }

  void _beginToolbarInteraction() {
    _toolbarInteractionActive = true;
  }

  void _endToolbarInteraction() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _toolbarInteractionActive = false;
      _handleEditorFocusChange();
    });
  }

  KeyEventResult _handleMarkdownKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _applyMarkdownFormat(
        (value) => MarkdownFormatting.handleTab(
          value,
          outdent: HardwareKeyboard.instance.isShiftPressed,
        ),
      );
      return KeyEventResult.handled;
    }
    if (!HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyB) {
      _formatBold();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyI) {
      _formatItalic();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyK) {
      _insertMarkdownLink();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleEditorTap(BuildContext context) {
    if (!HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final selection = _contentController.selection;
      if (!selection.isValid) {
        return;
      }
      final offset = selection.extentOffset;
      final href = MarkdownLinks.hrefAt(_contentController.text, offset);
      if (href == null) {
        return;
      }
      _openMarkdownLink(context, href);
    });
  }

  void _handleEditorFocusChange() {
    final mode = MarkdownRenderModes.normalize(widget.markdownRenderMode);
    if (_contentFocusNode.hasFocus ||
        _enteringEditorFromPreview ||
        _toolbarInteractionActive ||
        mode == MarkdownRenderModes.off ||
        _safeView(mode) != _viewEdit) {
      return;
    }
    setState(() => _view = _viewPreview);
  }

  void _applyMarkdownFormat(
    TextEditingValue Function(TextEditingValue value) format,
  ) {
    _contentController.value = format(_contentController.value);
    _commitContent(_contentController.text);
    _contentFocusNode.requestFocus();
  }

  void _commitContent(String value) {
    if (widget.paper.content == value) {
      return;
    }
    setState(() {
      widget.paper.content = value;
    });
    unawaited(widget.onChanged());
  }

  Widget _noteStatusBar(BuildContext context, String view) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        );
    return DecoratedBox(
      key: const ValueKey('note-status-bar'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  _noteViewLabel(view),
                  key: const ValueKey('note-status-mode'),
                  style: textStyle?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _noteStatsText(),
                key: const ValueKey('note-status-stats'),
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
            _noteZoomStatus(context, textStyle),
          ],
        ),
      ),
    );
  }

  Widget _noteZoomStatus(BuildContext context, TextStyle? textStyle) {
    final strings = PaperTodoStringsScope.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final canReset = (widget.textZoom - 1).abs() > 0.001;
    final zoomText = Text(
      '${(widget.textZoom * 100).round()}%',
      style: canReset
          ? textStyle?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            )
          : textStyle,
    );
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: zoomText,
    );
    return _conditionalTooltip(
      enabled: widget.enableToolTips,
      message: strings.get(PaperTodoStringKeys.actionResetTextZoom),
      child: MouseRegion(
        cursor: canReset ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          key: const ValueKey('note-status-zoom'),
          behavior: HitTestBehavior.opaque,
          onTap: canReset ? _resetTextZoom : null,
          child: content,
        ),
      ),
    );
  }

  void _resetTextZoom() {
    if ((widget.textZoom - 1).abs() <= 0.001) {
      return;
    }
    widget.onTextZoomChanged(1);
  }

  String _noteStatsText() {
    final characterCount = _countNoteTextCharacters(widget.paper.content);
    final lineCount = _countNoteLines(widget.paper.content);
    final elementCount = widget.paper.noteCanvasElements.length;
    return [
      '$characterCount ${characterCount == 1 ? 'char' : 'chars'}',
      '$lineCount ${lineCount == 1 ? 'line' : 'lines'}',
      '$elementCount ${elementCount == 1 ? 'element' : 'elements'}',
    ].join(' | ');
  }

  int _countNoteTextCharacters(String text) {
    return text.codeUnits.where(_isPaperTodoCountedNoteCharacter).length;
  }

  bool _isPaperTodoCountedNoteCharacter(int codeUnit) {
    if (codeUnit < 0x20 || (codeUnit >= 0x7F && codeUnit <= 0x9F)) {
      return false;
    }
    return String.fromCharCode(codeUnit).trim().isNotEmpty;
  }

  int _countNoteLines(String text) {
    if (text.isEmpty) {
      return 1;
    }
    return '\n'.allMatches(text).length + 1;
  }

  String _noteViewLabel(String view) {
    return switch (view) {
      _viewPreview => strings.get(PaperTodoStringKeys.noteViewPreview),
      _viewSplit => strings.get(PaperTodoStringKeys.noteViewSplit),
      _ => strings.get(PaperTodoStringKeys.noteViewEdit),
    };
  }

  Widget _preview(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _previewLinkActivated = false;
        _previewPrimaryPointer = event.buttons & kPrimaryMouseButton != 0;
        _handlePreviewContextMenuPointerDown(context, event);
      },
      onPointerUp: (event) {
        if (!_previewPrimaryPointer) {
          return;
        }
        _previewPrimaryPointer = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_previewLinkActivated) {
            _enterEditorFromPreview();
          }
        });
      },
      child: GestureDetector(
        key: ValueKey('${widget.paper.id}-preview'),
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: const BoxDecoration(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 112),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: MarkdownBody(
                data: widget.paper.content.trim().isEmpty
                    ? strings.get(PaperTodoStringKeys.noteEmptyPreview)
                    : widget.paper.content,
                inlineSyntaxes: paperTodoMarkdownInlineHtmlSyntaxes(),
                extensionSet: _paperTodoMarkdownExtensionSet,
                builders: _paperTodoMarkdownBuilders,
                imageBuilder: _paperTodoMarkdownImageBuilder,
                onTapLink: (text, href, title) {
                  _previewLinkActivated = true;
                  _openMarkdownLink(context, href);
                },
                styleSheet: _previewMarkdownStyleSheet(context),
                selectable: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handlePreviewContextMenuPointerDown(
    BuildContext context,
    PointerDownEvent event,
  ) {
    if (event.buttons & kSecondaryMouseButton == 0) {
      return;
    }
    unawaited(widget.onShowPaperContextMenu(context, event.position));
  }

  Widget _paperTodoMarkdownImageBuilder(
    Uri uri,
    String? title,
    String? alt,
  ) {
    return SelectableText('![${alt ?? ''}]($uri)');
  }

  MarkdownStyleSheet _previewMarkdownStyleSheet(BuildContext context) {
    final theme = Theme.of(context);
    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium
          ?.apply(
            fontSizeFactor: widget.textZoom,
          )
          .copyWith(height: widget.lineSpacing),
    );
    return styleSheet;
  }

  void _enterEditorFromPreview() {
    final mode = MarkdownRenderModes.normalize(widget.markdownRenderMode);
    if (mode == MarkdownRenderModes.off) {
      return;
    }
    _enteringEditorFromPreview = true;
    setState(() => _view = _viewEdit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _contentFocusNode.requestFocus();
      _enteringEditorFromPreview = false;
    });
  }

  void _openMarkdownLink(BuildContext context, String? href) {
    final uri = href?.trim();
    if (uri == null || uri.isEmpty) {
      return;
    }
    unawaited(
      widget.onOpenUri(uri).catchError((Object error) {
        if (!context.mounted) {
          return;
        }
        final strings = PaperTodoStringsScope.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.format(
                PaperTodoStringKeys.openLinkFailed,
                [_readableFailureMessage(error, strings: strings)],
              ),
            ),
          ),
        );
      }),
    );
  }

  String _safeView(String mode) {
    if (_view == _viewSplit && mode != MarkdownRenderModes.enhanced) {
      return _viewEdit;
    }
    return _view;
  }

  String _defaultView(String mode, PaperData paper) {
    if (ScriptCapsuleSpec.tryParse(paper.content) != null) {
      return _viewEdit;
    }
    return MarkdownRenderModes.normalize(mode) == MarkdownRenderModes.off
        ? _viewEdit
        : _viewPreview;
  }

  Widget _canvasPreview() {
    return _NoteCanvasPreview(
      elements: widget.paper.noteCanvasElements,
      selectedElementId: _selectedCanvasElementId,
      geometryGesturesEnabled: !widget.paper.isPinnedToDesktop,
      enableToolTips: widget.enableToolTips,
      textZoom: widget.textZoom,
      onChanged: widget.onChanged,
      onGeometryChanging: _refreshCanvasGeometry,
      onSelect: _selectCanvasElement,
      onEdit: _editCanvasElement,
      onDuplicate: _duplicateCanvasElement,
      onLayerAction: _applyCanvasLayerAction,
      onDelete: _deleteCanvasElement,
    );
  }

  void _refreshCanvasGeometry() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Widget _addCanvasButton({bool compact = false}) {
    final onPressed = widget.paper.isPinnedToDesktop
        ? null
        : () => _addCanvasElement(NoteCanvasElementTypes.code);
    if (compact) {
      return IconButton(
        tooltip: _tooltipLabel(
          widget.enableToolTips,
          strings.get(PaperTodoStringKeys.actionAddCanvasBlock),
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.code, size: 17),
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.code, size: 17),
      label: Text(strings.get(PaperTodoStringKeys.actionAddCanvasBlock)),
    );
  }

  void _addCanvasElement(String type) {
    if (widget.paper.isPinnedToDesktop) {
      return;
    }
    final elements = widget.paper.noteCanvasElements;
    final normalizedType = NoteCanvasElementTypes.normalize(type);
    final width = _defaultNoteCanvasElementWidth();
    final height = _defaultNoteCanvasElementHeight();
    final point = _nextNoteCanvasElementPoint(width, height, elements.length);
    final maxLayer = _maxCanvasElementLayer(elements);
    setState(() {
      final elementId = _newCanvasElementId();
      elements.add(
        NoteCanvasElement(
          id: elementId,
          type: normalizedType,
          text: _defaultNoteCanvasElementText(),
          x: point.dx,
          y: point.dy,
          width: width,
          height: height,
          zIndex: maxLayer + 10,
        ),
      );
      _selectedCanvasElementId = elementId;
    });
    unawaited(widget.onChanged());
  }

  void _selectCanvasElement(NoteCanvasElement element) {
    if (widget.paper.isPinnedToDesktop) {
      return;
    }
    if (_selectedCanvasElementId == element.id) {
      return;
    }
    setState(() => _selectedCanvasElementId = element.id);
  }

  void _duplicateCanvasElement(NoteCanvasElement element) {
    if (widget.paper.isPinnedToDesktop) {
      return;
    }
    final elements = widget.paper.noteCanvasElements;
    final maxLayer = _maxCanvasElementLayer(elements);
    final duplicate = element.copyWith(
      id: _newCanvasElementId(),
      x: element.x + 18,
      y: element.y + 18,
      zIndex: maxLayer + 10,
    )..normalize();
    setState(() {
      elements.add(duplicate);
      _selectedCanvasElementId = duplicate.id;
    });
    unawaited(widget.onChanged());
  }

  void _applyCanvasLayerAction(
    NoteCanvasElement element,
    _CanvasLayerAction action,
  ) {
    if (widget.paper.isPinnedToDesktop) {
      return;
    }
    final elements = widget.paper.noteCanvasElements;
    final orderedElements = [...elements]..sort((a, b) {
        final byLayer = a.zIndex.compareTo(b.zIndex);
        return byLayer != 0 ? byLayer : a.id.compareTo(b.id);
      });
    final elementIndex = orderedElements.indexWhere(
      (candidate) => candidate.id == element.id,
    );
    if (elementIndex < 0) {
      return;
    }
    final minLayer = _minCanvasElementLayer(elements);
    final maxLayer = _maxCanvasElementLayer(elements);
    var didChange = false;
    setState(() {
      switch (action) {
        case _CanvasLayerAction.bringForward:
          if (elementIndex < orderedElements.length - 1) {
            _renumberDuplicateCanvasLayers(orderedElements);
            final nextElement = orderedElements[elementIndex + 1];
            final currentLayer = element.zIndex;
            element.zIndex = nextElement.zIndex;
            nextElement.zIndex = currentLayer;
            didChange = true;
          }
          break;
        case _CanvasLayerAction.sendBackward:
          if (elementIndex > 0) {
            _renumberDuplicateCanvasLayers(orderedElements);
            final previousElement = orderedElements[elementIndex - 1];
            final currentLayer = element.zIndex;
            element.zIndex = previousElement.zIndex;
            previousElement.zIndex = currentLayer;
            didChange = true;
          }
          break;
        case _CanvasLayerAction.bringToFront:
          element.zIndex = maxLayer + 10;
          didChange = true;
          break;
        case _CanvasLayerAction.sendToBack:
          element.zIndex = minLayer - 10;
          didChange = true;
          break;
      }
      if (didChange) {
        _selectedCanvasElementId = element.id;
      }
    });
    if (didChange) {
      unawaited(widget.onChanged());
    }
  }

  void _deleteCanvasElement(NoteCanvasElement element) {
    if (widget.paper.isPinnedToDesktop) {
      return;
    }
    setState(() {
      widget.paper.noteCanvasElements.removeWhere(
        (candidate) => candidate.id == element.id,
      );
      if (_selectedCanvasElementId == element.id) {
        _selectedCanvasElementId = null;
      }
    });
    unawaited(widget.onChanged());
  }

  Future<void> _editCanvasElement(NoteCanvasElement element) async {
    if (widget.paper.isPinnedToDesktop) {
      return;
    }
    final result = await showDialog<_CanvasGeometry>(
      context: context,
      builder: (context) => _CanvasGeometryDialog(element: element),
    );
    if (result == null) {
      return;
    }
    setState(() {
      element
        ..type = result.type
        ..x = result.x
        ..y = result.y
        ..width = result.width
        ..height = result.height
        ..zIndex = result.zIndex;
      element.normalize();
    });
    await widget.onChanged();
  }

  String _newCanvasElementId() {
    final existingIds =
        widget.paper.noteCanvasElements.map((element) => element.id).toSet();
    var id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    var suffix = 1;
    while (existingIds.contains(id)) {
      id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-$suffix';
      suffix += 1;
    }
    return id;
  }

  Offset _nextNoteCanvasElementPoint(
    double width,
    double height,
    int existingCount,
  ) {
    final layerWidth = math.max(220.0, widget.paper.width - 40);
    final layerHeight = math.max(160.0, widget.paper.height - 90);
    final offset = math.min(80.0, existingCount * 12.0);
    final x = math.max(
      10.0,
      math.min(layerWidth - width - 10.0, 28.0 + offset),
    );
    final y = math.max(
      10.0,
      math.min(layerHeight - height - 10.0, 28.0 + offset),
    );
    return Offset(x, y);
  }

  int _maxCanvasElementLayer(List<NoteCanvasElement> elements) {
    if (elements.isEmpty) {
      return 0;
    }
    return elements
        .map((element) => element.zIndex)
        .reduce((max, zIndex) => zIndex > max ? zIndex : max);
  }

  int _minCanvasElementLayer(List<NoteCanvasElement> elements) {
    if (elements.isEmpty) {
      return 0;
    }
    return elements
        .map((element) => element.zIndex)
        .reduce((min, zIndex) => zIndex < min ? zIndex : min);
  }

  void _renumberDuplicateCanvasLayers(
    List<NoteCanvasElement> orderedElements,
  ) {
    final seenLayers = <int>{};
    var hasDuplicateLayer = false;
    for (final element in orderedElements) {
      if (!seenLayers.add(element.zIndex)) {
        hasDuplicateLayer = true;
        break;
      }
    }
    if (!hasDuplicateLayer || orderedElements.isEmpty) {
      return;
    }

    final firstLayer = orderedElements.first.zIndex;
    for (var index = 0; index < orderedElements.length; index += 1) {
      orderedElements[index].zIndex = firstLayer + index;
    }
  }

  double _defaultNoteCanvasElementWidth() {
    return 230;
  }

  double _defaultNoteCanvasElementHeight() {
    return 116;
  }

  String _defaultNoteCanvasElementText() {
    return 'Console.WriteLine("PaperTodo");';
  }
}

class _NoteCanvasPreview extends StatelessWidget {
  const _NoteCanvasPreview({
    required this.elements,
    required this.selectedElementId,
    required this.geometryGesturesEnabled,
    required this.enableToolTips,
    required this.textZoom,
    required this.onChanged,
    required this.onGeometryChanging,
    required this.onSelect,
    required this.onEdit,
    required this.onDuplicate,
    required this.onLayerAction,
    required this.onDelete,
  });

  final List<NoteCanvasElement> elements;
  final String? selectedElementId;
  final bool geometryGesturesEnabled;
  final bool enableToolTips;
  final double textZoom;
  final Future<void> Function() onChanged;
  final VoidCallback onGeometryChanging;
  final void Function(NoteCanvasElement element) onSelect;
  final Future<void> Function(NoteCanvasElement element) onEdit;
  final void Function(NoteCanvasElement element) onDuplicate;
  final void Function(NoteCanvasElement element, _CanvasLayerAction action)
      onLayerAction;
  final void Function(NoteCanvasElement element) onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = PaperTodoStringsScope.of(context);
    final sortedElements = [...elements]..sort((a, b) {
        final byLayer = a.zIndex.compareTo(b.zIndex);
        return byLayer != 0 ? byLayer : a.id.compareTo(b.id);
      });
    final contentWidth = _contentWidth(sortedElements);
    final contentHeight = _contentHeight(sortedElements);
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('note-canvas-preview'),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : contentWidth;
          final scale = (maxWidth / contentWidth).clamp(0.2, 1.0).toDouble();
          final visualHeight =
              (contentHeight * scale).clamp(120, 640).toDouble();
          final canvasWidth = maxWidth / scale;
          final canvasHeight = visualHeight / scale;
          return SizedBox(
            height: visualHeight,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: colorScheme.surfaceContainerLowest,
                  ),
                ),
                for (var index = 0; index < sortedElements.length; index++)
                  Positioned(
                    left: sortedElements[index].x * scale,
                    top: sortedElements[index].y * scale,
                    width: sortedElements[index].width * scale,
                    height: sortedElements[index].height * scale,
                    child: _NoteCanvasElementPreview(
                      key: ValueKey(
                        'note-canvas-element-${sortedElements[index].id}',
                      ),
                      element: sortedElements[index],
                      layerRank: index + 1,
                      layerCount: sortedElements.length,
                      isSelected: sortedElements[index].id == selectedElementId,
                      geometryGesturesEnabled: geometryGesturesEnabled,
                      enableToolTips: enableToolTips,
                      strings: strings,
                      scale: scale,
                      canvasWidth: canvasWidth,
                      canvasHeight: canvasHeight,
                      textZoom: textZoom,
                      onChanged: onChanged,
                      onGeometryChanging: onGeometryChanging,
                      onSelect: onSelect,
                      onEdit: onEdit,
                      onDuplicate: onDuplicate,
                      onLayerAction: onLayerAction,
                      onDelete: onDelete,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  double _contentWidth(List<NoteCanvasElement> elements) {
    return elements
        .map((element) => element.x + element.width)
        .fold<double>(320, (max, value) => value > max ? value : max);
  }

  double _contentHeight(List<NoteCanvasElement> elements) {
    return elements
        .map((element) => element.y + element.height)
        .fold<double>(160, (max, value) => value > max ? value : max);
  }
}

class _NoteCanvasElementPreview extends StatefulWidget {
  const _NoteCanvasElementPreview({
    required this.element,
    required this.layerRank,
    required this.layerCount,
    required this.isSelected,
    required this.geometryGesturesEnabled,
    required this.enableToolTips,
    required this.strings,
    required this.scale,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.textZoom,
    required this.onChanged,
    required this.onGeometryChanging,
    required this.onSelect,
    required this.onEdit,
    required this.onDuplicate,
    required this.onLayerAction,
    required this.onDelete,
    super.key,
  });

  final NoteCanvasElement element;
  final int layerRank;
  final int layerCount;
  final bool isSelected;
  final bool geometryGesturesEnabled;
  final bool enableToolTips;
  final PaperTodoStrings strings;
  final double scale;
  final double canvasWidth;
  final double canvasHeight;
  final double textZoom;
  final Future<void> Function() onChanged;
  final VoidCallback onGeometryChanging;
  final void Function(NoteCanvasElement element) onSelect;
  final Future<void> Function(NoteCanvasElement element) onEdit;
  final void Function(NoteCanvasElement element) onDuplicate;
  final void Function(NoteCanvasElement element, _CanvasLayerAction action)
      onLayerAction;
  final void Function(NoteCanvasElement element) onDelete;

  @override
  State<_NoteCanvasElementPreview> createState() =>
      _NoteCanvasElementPreviewState();
}

class _NoteCanvasElementPreviewState extends State<_NoteCanvasElementPreview> {
  static const _compactCanvasActionEdit = 'edit';
  static const _compactCanvasActionDuplicate = 'duplicate';
  static const _compactCanvasActionBringToFront = 'bring-to-front';
  static const _compactCanvasActionBringForward = 'bring-forward';
  static const _compactCanvasActionSendBackward = 'send-backward';
  static const _compactCanvasActionSendToBack = 'send-to-back';
  static const _compactCanvasActionDelete = 'delete';

  bool _geometryChanged = false;
  int? _geometryPointer;
  _CanvasGeometryDragMode? _geometryDragMode;
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.element.text);
  }

  @override
  void didUpdateWidget(covariant _NoteCanvasElementPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.element.id != widget.element.id ||
        widget.element.text != _textController.text) {
      final offset = _textController.selection.baseOffset
          .clamp(0, widget.element.text.length)
          .toInt();
      _textController.value = TextEditingValue(
        text: widget.element.text,
        selection: TextSelection.collapsed(offset: offset),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final element = widget.element;
    final isCode = element.type == NoteCanvasElementTypes.code;
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.apply(fontSizeFactor: widget.textZoom)
        .copyWith(fontFamily: isCode ? 'monospace' : null);
    final typeLabel = _noteCanvasElementTypeLabel(widget.strings, element.type);
    final layerLabel = _noteCanvasLayerLabel(
      widget.strings,
      widget.layerRank,
      widget.layerCount,
    );
    final showInlineActions = element.width * widget.scale >= 168;
    final compactContent = element.width * widget.scale < 120 ||
        element.height * widget.scale < 72;
    final elementPadding =
        compactContent ? 4.0 : (8 * widget.scale).clamp(4, 8).toDouble();
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleCanvasContextMenuPointerDown,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          border: Border.all(
            color: widget.isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
            width: widget.isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: widget.isSelected
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.18),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Padding(
              padding: EdgeInsets.all(elementPadding),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _conditionalTooltip(
                          enabled: widget.enableToolTips,
                          message: widget.strings
                              .get(PaperTodoStringKeys.canvasDragBlock),
                          child: MouseRegion(
                            cursor: widget.geometryGesturesEnabled
                                ? SystemMouseCursors.move
                                : SystemMouseCursors.basic,
                            child: Listener(
                              key: ValueKey(
                                'note-canvas-drag-handle-${element.id}',
                              ),
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: (event) => _beginGeometryGesture(
                                event,
                                _CanvasGeometryDragMode.move,
                              ),
                              onPointerMove: _updateGeometryGesture,
                              onPointerUp: _endGeometryGesture,
                              onPointerCancel: _endGeometryGesture,
                              child: compactContent
                                  ? Align(
                                      alignment: Alignment.centerLeft,
                                      child: Icon(
                                        Icons.open_with,
                                        size: (16 * widget.scale)
                                            .clamp(12, 16)
                                            .toDouble(),
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    )
                                  : Wrap(
                                      spacing: (6 * widget.scale)
                                          .clamp(3, 6)
                                          .toDouble(),
                                      runSpacing: (4 * widget.scale)
                                          .clamp(2, 4)
                                          .toDouble(),
                                      children: [
                                        _NoteCanvasElementBadge(
                                          label: typeLabel,
                                          scale: widget.scale,
                                          color: colorScheme.primaryContainer,
                                          foregroundColor:
                                              colorScheme.onPrimaryContainer,
                                        ),
                                        _NoteCanvasElementBadge(
                                          label: layerLabel,
                                          scale: widget.scale,
                                          color: colorScheme.secondaryContainer,
                                          foregroundColor:
                                              colorScheme.onSecondaryContainer,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                      if (showInlineActions) ...[
                        SizedBox.square(
                          dimension:
                              (28 * widget.scale).clamp(24, 28).toDouble(),
                          child: IconButton(
                            tooltip: _tooltipLabel(
                              widget.enableToolTips,
                              widget.strings
                                  .get(PaperTodoStringKeys.canvasEditGeometry),
                            ),
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              minimumSize: Size.zero,
                            ),
                            onPressed: widget.geometryGesturesEnabled
                                ? () {
                                    widget.onSelect(element);
                                    unawaited(widget.onEdit(element));
                                  }
                                : null,
                            iconSize:
                                (18 * widget.scale).clamp(16, 18).toDouble(),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.tune_outlined),
                          ),
                        ),
                        SizedBox.square(
                          dimension:
                              (28 * widget.scale).clamp(24, 28).toDouble(),
                          child: IconButton(
                            tooltip: _tooltipLabel(
                              widget.enableToolTips,
                              widget.strings.get(
                                PaperTodoStringKeys.canvasDuplicateBlock,
                              ),
                            ),
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              minimumSize: Size.zero,
                            ),
                            onPressed: widget.geometryGesturesEnabled
                                ? () {
                                    widget.onSelect(element);
                                    widget.onDuplicate(element);
                                  }
                                : null,
                            iconSize:
                                (18 * widget.scale).clamp(16, 18).toDouble(),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.content_copy_outlined),
                          ),
                        ),
                        SizedBox.square(
                          dimension:
                              (28 * widget.scale).clamp(24, 28).toDouble(),
                          child: PopupMenuButton<_CanvasLayerAction>(
                            key: ValueKey(
                              'note-canvas-layer-actions-${element.id}',
                            ),
                            enabled: widget.geometryGesturesEnabled,
                            tooltip: _tooltipLabel(
                              widget.enableToolTips,
                              widget.strings
                                  .get(PaperTodoStringKeys.canvasLayerActions),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.layers_outlined,
                                size: (18 * widget.scale)
                                    .clamp(16, 18)
                                    .toDouble(),
                              ),
                            ),
                            onSelected: (action) {
                              widget.onSelect(element);
                              widget.onLayerAction(element, action);
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: _CanvasLayerAction.bringToFront,
                                child: Text(
                                  widget.strings.get(
                                    PaperTodoStringKeys.canvasBringToFront,
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: _CanvasLayerAction.bringForward,
                                child: Text(
                                  widget.strings.get(
                                    PaperTodoStringKeys.canvasBringForward,
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: _CanvasLayerAction.sendBackward,
                                child: Text(
                                  widget.strings.get(
                                    PaperTodoStringKeys.canvasSendBackward,
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: _CanvasLayerAction.sendToBack,
                                child: Text(
                                  widget.strings.get(
                                    PaperTodoStringKeys.canvasSendToBack,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox.square(
                          dimension:
                              (28 * widget.scale).clamp(24, 28).toDouble(),
                          child: IconButton(
                            tooltip: _tooltipLabel(
                              widget.enableToolTips,
                              widget.strings
                                  .get(PaperTodoStringKeys.canvasDeleteBlock),
                            ),
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              minimumSize: Size.zero,
                            ),
                            onPressed: widget.geometryGesturesEnabled
                                ? () {
                                    widget.onSelect(element);
                                    widget.onDelete(element);
                                  }
                                : null,
                            iconSize:
                                (18 * widget.scale).clamp(16, 18).toDouble(),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.close_outlined),
                          ),
                        ),
                      ] else
                        SizedBox.square(
                          dimension:
                              (28 * widget.scale).clamp(24, 28).toDouble(),
                          child: PopupMenuButton<String>(
                            key: ValueKey(
                              'note-canvas-compact-actions-${element.id}',
                            ),
                            enabled: widget.geometryGesturesEnabled,
                            tooltip: _tooltipLabel(
                              widget.enableToolTips,
                              widget.strings
                                  .get(PaperTodoStringKeys.canvasBlockActions),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.more_vert,
                                size: (18 * widget.scale)
                                    .clamp(16, 18)
                                    .toDouble(),
                              ),
                            ),
                            onSelected: _handleCompactCanvasAction,
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: _compactCanvasActionEdit,
                                child: Text(
                                  widget.strings.get(
                                    PaperTodoStringKeys.canvasEditGeometry,
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: _compactCanvasActionDuplicate,
                                child: Text(
                                  widget.strings.get(
                                    PaperTodoStringKeys.canvasDuplicateBlock,
                                  ),
                                ),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: _compactCanvasActionBringToFront,
                                child: Text(
                                  widget.strings.get(
                                    PaperTodoStringKeys.canvasBringToFront,
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: _compactCanvasActionBringForward,
                                child: Text(
                                  widget.strings.get(
                                    PaperTodoStringKeys.canvasBringForward,
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: _compactCanvasActionSendBackward,
                                child: Text(
                                  widget.strings.get(
                                    PaperTodoStringKeys.canvasSendBackward,
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: _compactCanvasActionSendToBack,
                                child: Text(
                                  widget.strings.get(
                                    PaperTodoStringKeys.canvasSendToBack,
                                  ),
                                ),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: _compactCanvasActionDelete,
                                child: Text(
                                  widget.strings.get(
                                    PaperTodoStringKeys.actionDelete,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  Expanded(
                    child: compactContent
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.onSelect(element),
                            child: ClipRect(
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Text(
                                  element.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: style?.copyWith(
                                    color: colorScheme.onSurface,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Focus(
                            onKeyEvent: _handleCanvasTextKeyEvent,
                            child: TextFormField(
                              key: ValueKey(
                                'note-canvas-element-text-${element.id}',
                              ),
                              controller: _textController,
                              readOnly: !widget.geometryGesturesEnabled,
                              enableInteractiveSelection:
                                  widget.geometryGesturesEnabled,
                              expands: true,
                              maxLines: null,
                              minLines: null,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              style: style?.copyWith(
                                color: colorScheme.onSurface,
                                height: 1.35,
                              ),
                              onTap: () => widget.onSelect(element),
                              onChanged: _commitCanvasText,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 3,
              bottom: 3,
              child: _conditionalTooltip(
                enabled: widget.enableToolTips,
                message:
                    widget.strings.get(PaperTodoStringKeys.canvasResizeBlock),
                child: MouseRegion(
                  cursor: widget.geometryGesturesEnabled
                      ? SystemMouseCursors.resizeDownRight
                      : SystemMouseCursors.basic,
                  child: Listener(
                    key: ValueKey('note-canvas-resize-handle-${element.id}'),
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) => _beginGeometryGesture(
                      event,
                      _CanvasGeometryDragMode.resize,
                    ),
                    onPointerMove: _updateGeometryGesture,
                    onPointerUp: _endGeometryGesture,
                    onPointerCancel: _endGeometryGesture,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.32),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SizedBox.square(
                        dimension: (16 * widget.scale).clamp(14, 18).toDouble(),
                        child: Icon(
                          Icons.open_in_full,
                          size: (11 * widget.scale).clamp(9, 11).toDouble(),
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _beginGeometryGesture(
    PointerDownEvent event,
    _CanvasGeometryDragMode mode,
  ) {
    if (!widget.geometryGesturesEnabled) {
      return;
    }
    if (event.buttons & kPrimaryMouseButton == 0) {
      return;
    }
    if (_geometryPointer != null) {
      return;
    }
    _geometryPointer = event.pointer;
    _geometryDragMode = mode;
    _geometryChanged = false;
    widget.onSelect(widget.element);
  }

  void _handleCanvasContextMenuPointerDown(PointerDownEvent event) {
    if (!widget.geometryGesturesEnabled) {
      return;
    }
    if (event.buttons & kSecondaryMouseButton == 0) {
      return;
    }
    widget.onSelect(widget.element);
    unawaited(_showCanvasElementContextMenu(event.position));
  }

  Future<void> _showCanvasElementContextMenu(Offset globalPosition) async {
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (overlay is! RenderBox) {
      return;
    }
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: _canvasElementContextMenuItems(),
    );
    if (!mounted || selected == null) {
      return;
    }
    _handleCompactCanvasAction(selected);
  }

  List<PopupMenuEntry<String>> _canvasElementContextMenuItems() {
    return [
      PopupMenuItem<String>(
        enabled: false,
        child: Text(
          '${_noteCanvasElementTypeLabel(widget.strings, widget.element.type)}'
          ' · ${_noteCanvasLayerLabel(
            widget.strings,
            widget.layerRank,
            widget.layerCount,
          )}',
        ),
      ),
      const PopupMenuDivider(),
      _canvasElementContextMenuItem(
        value: _compactCanvasActionBringForward,
        label: widget.strings.get(PaperTodoStringKeys.canvasBringForward),
      ),
      _canvasElementContextMenuItem(
        value: _compactCanvasActionSendBackward,
        label: widget.strings.get(PaperTodoStringKeys.canvasSendBackward),
      ),
      _canvasElementContextMenuItem(
        value: _compactCanvasActionBringToFront,
        label: widget.strings.get(PaperTodoStringKeys.canvasBringToFront),
      ),
      _canvasElementContextMenuItem(
        value: _compactCanvasActionSendToBack,
        label: widget.strings.get(PaperTodoStringKeys.canvasSendToBack),
      ),
      _canvasElementContextMenuItem(
        value: _compactCanvasActionDuplicate,
        label: widget.strings.get(PaperTodoStringKeys.canvasDuplicateBlock),
      ),
      const PopupMenuDivider(),
      _canvasElementContextMenuItem(
        value: _compactCanvasActionDelete,
        label: widget.strings.get(PaperTodoStringKeys.actionDelete),
      ),
    ];
  }

  PopupMenuItem<String> _canvasElementContextMenuItem({
    required String value,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: _paperTodoPopupMenuHeight(),
      child: Text(label),
    );
  }

  void _handleCompactCanvasAction(String action) {
    final element = widget.element;
    widget.onSelect(element);
    switch (action) {
      case _compactCanvasActionEdit:
        unawaited(widget.onEdit(element));
      case _compactCanvasActionDuplicate:
        widget.onDuplicate(element);
      case _compactCanvasActionBringToFront:
        widget.onLayerAction(element, _CanvasLayerAction.bringToFront);
      case _compactCanvasActionBringForward:
        widget.onLayerAction(element, _CanvasLayerAction.bringForward);
      case _compactCanvasActionSendBackward:
        widget.onLayerAction(element, _CanvasLayerAction.sendBackward);
      case _compactCanvasActionSendToBack:
        widget.onLayerAction(element, _CanvasLayerAction.sendToBack);
      case _compactCanvasActionDelete:
        widget.onDelete(element);
    }
  }

  KeyEventResult _handleCanvasTextKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.tab ||
        !widget.geometryGesturesEnabled) {
      return KeyEventResult.ignored;
    }
    _textController.value = MarkdownFormatting.handleTab(
      _textController.value,
      outdent: HardwareKeyboard.instance.isShiftPressed,
    );
    _commitCanvasText(_textController.text);
    return KeyEventResult.handled;
  }

  void _commitCanvasText(String value) {
    if (!widget.geometryGesturesEnabled) {
      return;
    }
    if (widget.element.text == value) {
      return;
    }
    widget.element.text = value;
    unawaited(widget.onChanged());
  }

  void _updateGeometryGesture(PointerMoveEvent event) {
    if (!widget.geometryGesturesEnabled) {
      return;
    }
    if (event.pointer != _geometryPointer) {
      return;
    }
    switch (_geometryDragMode) {
      case _CanvasGeometryDragMode.move:
        _moveElement(event.delta);
      case _CanvasGeometryDragMode.resize:
        _resizeElement(event.delta);
      case null:
        break;
    }
  }

  void _moveElement(Offset delta) {
    final element = widget.element;
    final dx = delta.dx / widget.scale;
    final dy = delta.dy / widget.scale;
    final maxX = (widget.canvasWidth - element.width).clamp(0, double.infinity);
    final maxY =
        (widget.canvasHeight - element.height).clamp(0, double.infinity);
    element.x = _roundCanvasValue((element.x + dx).clamp(0, maxX).toDouble());
    element.y = _roundCanvasValue((element.y + dy).clamp(0, maxY).toDouble());
    _geometryChanged = true;
    widget.onGeometryChanging();
  }

  void _resizeElement(Offset delta) {
    final element = widget.element;
    final dx = delta.dx / widget.scale;
    final dy = delta.dy / widget.scale;
    final maxWidth =
        (widget.canvasWidth - element.x).clamp(72, double.infinity);
    final maxHeight =
        (widget.canvasHeight - element.y).clamp(48, double.infinity);
    element.width =
        _roundCanvasValue((element.width + dx).clamp(72, maxWidth).toDouble());
    element.height = _roundCanvasValue(
        (element.height + dy).clamp(48, maxHeight).toDouble());
    _geometryChanged = true;
    widget.onGeometryChanging();
  }

  void _endGeometryGesture(PointerEvent event) {
    if (event.pointer != _geometryPointer) {
      return;
    }
    _geometryPointer = null;
    _geometryDragMode = null;
    if (!_geometryChanged) {
      return;
    }
    _geometryChanged = false;
    unawaited(widget.onChanged());
  }

  double _roundCanvasValue(double value) => (value * 10).roundToDouble() / 10;
}

enum _CanvasGeometryDragMode {
  move,
  resize,
}

class _NoteCanvasElementBadge extends StatelessWidget {
  const _NoteCanvasElementBadge({
    required this.label,
    required this.scale,
    required this.color,
    required this.foregroundColor,
  });

  final String label;
  final double scale;
  final Color color;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: (6 * scale).clamp(4, 6).toDouble(),
          vertical: (3 * scale).clamp(2, 3).toDouble(),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
        ),
      ),
    );
  }
}

String _noteCanvasElementTypeLabel(PaperTodoStrings strings, String type) {
  return strings.get(PaperTodoStringKeys.canvasBlockTypeCode);
}

String _noteCanvasLayerLabel(
  PaperTodoStrings strings,
  int layerRank,
  int layerCount,
) {
  if (layerCount > 1 && layerRank == layerCount) {
    return strings.format(PaperTodoStringKeys.canvasTopLayer, [layerRank]);
  }
  return strings.format(PaperTodoStringKeys.canvasLayer, [layerRank]);
}

enum _CanvasLayerAction {
  bringForward,
  sendBackward,
  bringToFront,
  sendToBack,
}

class _CanvasGeometry {
  const _CanvasGeometry({
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.zIndex,
  });

  final String type;
  final double x;
  final double y;
  final double width;
  final double height;
  final int zIndex;
}

class _CanvasGeometryDialog extends StatefulWidget {
  const _CanvasGeometryDialog({
    required this.element,
  });

  final NoteCanvasElement element;

  @override
  State<_CanvasGeometryDialog> createState() => _CanvasGeometryDialogState();
}

class _CanvasGeometryDialogState extends State<_CanvasGeometryDialog> {
  late final TextEditingController _xController;
  late final TextEditingController _yController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _layerController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _xController = TextEditingController(text: _format(widget.element.x));
    _yController = TextEditingController(text: _format(widget.element.y));
    _widthController =
        TextEditingController(text: _format(widget.element.width));
    _heightController =
        TextEditingController(text: _format(widget.element.height));
    _layerController =
        TextEditingController(text: widget.element.zIndex.toString());
  }

  @override
  void dispose() {
    _xController.dispose();
    _yController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _layerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = PaperTodoStringsScope.of(context);
    return AlertDialog(
      title: Text(strings.get(PaperTodoStringKeys.canvasBlockGeometry)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_errorText case final errorText?) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  errorText,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(child: _numberField(_xController, 'X')),
                const SizedBox(width: 8),
                Expanded(child: _numberField(_yController, 'Y')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    _widthController,
                    strings.get(PaperTodoStringKeys.canvasFieldWidth),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numberField(
                    _heightController,
                    strings.get(PaperTodoStringKeys.canvasFieldHeight),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _numberField(
              _layerController,
              strings.get(PaperTodoStringKeys.canvasFieldLayer),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.get(PaperTodoStringKeys.actionCancel)),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check),
          label: Text(strings.get(PaperTodoStringKeys.actionSave)),
        ),
      ],
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        isDense: true,
      ),
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
    );
  }

  void _save() {
    final x = double.tryParse(_xController.text.trim());
    final y = double.tryParse(_yController.text.trim());
    final width = double.tryParse(_widthController.text.trim());
    final height = double.tryParse(_heightController.text.trim());
    final layer = int.tryParse(_layerController.text.trim());
    if (x == null ||
        y == null ||
        width == null ||
        height == null ||
        layer == null ||
        !x.isFinite ||
        !y.isFinite ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      final strings = PaperTodoStringsScope.of(context);
      setState(
        () => _errorText = strings.get(
          PaperTodoStringKeys.canvasEnterValidNumbers,
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      _CanvasGeometry(
        type: NoteCanvasElementTypes.code,
        x: x,
        y: y,
        width: width,
        height: height,
        zIndex: layer,
      ),
    );
  }

  String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}

class _TodoEditor extends StatefulWidget {
  const _TodoEditor({
    required this.paper,
    required this.notePapers,
    required this.enableTodoNoteLinks,
    required this.showLinkedNoteName,
    required this.allowLongLinkedNoteTitles,
    required this.runLinkedScriptCapsulesOnClick,
    required this.maxTitleLength,
    required this.enableToolTips,
    required this.visualSize,
    required this.lineSpacing,
    required this.textZoom,
    required this.showDueRelativeTime,
    required this.dueYearDisplayMode,
    required this.defaultReminderIntervalValue,
    required this.defaultReminderIntervalUnit,
    required this.onOpenLinkedNote,
    required this.onRunScriptCapsule,
    required this.onChanged,
    required this.onItemDeleted,
    required this.onItemRestored,
    required this.onReminderReset,
    this.standaloneSurface = false,
  });

  final PaperData paper;
  final List<PaperData> notePapers;
  final bool enableTodoNoteLinks;
  final bool showLinkedNoteName;
  final bool allowLongLinkedNoteTitles;
  final bool runLinkedScriptCapsulesOnClick;
  final int maxTitleLength;
  final bool enableToolTips;
  final String visualSize;
  final double lineSpacing;
  final double textZoom;
  final bool showDueRelativeTime;
  final String dueYearDisplayMode;
  final int defaultReminderIntervalValue;
  final String defaultReminderIntervalUnit;
  final Future<void> Function(PaperData paper, PaperData anchorPaper)
      onOpenLinkedNote;
  final Future<void> Function(ScriptCapsuleSpec spec) onRunScriptCapsule;
  final Future<void> Function() onChanged;
  final void Function(PaperData paper, PaperItem item) onItemDeleted;
  final void Function(PaperData paper, PaperItem item) onItemRestored;
  final void Function(PaperItem item) onReminderReset;
  final bool standaloneSurface;

  @override
  State<_TodoEditor> createState() => _TodoEditorState();
}

enum _TodoFocusPlacement { start, end }

class _TodoEditorState extends State<_TodoEditor> {
  static const _maxTodoUndoDepth = 100;
  static const _todoColumnSplitterWidth = 8.0;
  static const _minTodoColumnWidth = 0.2;
  static const _maxTodoColumnWidth = TodoColumnLimits.maxWidth;

  final _todoFocusNode = FocusNode(debugLabel: 'todo-editor');
  final _todoMainFieldFocusNodes = <String, FocusNode>{};
  final _todoExtraFieldFocusNodes = <String, FocusNode>{};
  final _todoColumnHitTestKeys = <String, GlobalKey>{};
  final _todoDropTargetKeys = <String, GlobalKey>{};
  final _undoStack = <List<Map<String, Object?>>>[];
  final _redoStack = <List<Map<String, Object?>>>[];
  final _focusedTodoTextUndoStack = <String>[];
  final _focusedTodoTextRedoStack = <String>[];
  var _textFieldRevision = 0;
  var _suppressTodoBackspaceUntilKeyUp = false;
  var _applyingTodoTextHistory = false;
  var _isDraggingTodoItem = false;
  String? _activeOriginalTodoItemId;
  int? _activeOriginalTodoColumnIndex;
  String? _activeOriginalTodoText;

  PaperTodoStrings get strings => PaperTodoStringsScope.of(context);

  @override
  void dispose() {
    _todoFocusNode.dispose();
    for (final focusNode in _todoMainFieldFocusNodes.values) {
      focusNode.dispose();
    }
    for (final focusNode in _todoExtraFieldFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualSpec = _TodoVisualSpec.from(widget.visualSize);
    final itemTextStyle = theme.textTheme.bodyMedium
        ?.apply(fontSizeFactor: visualSpec.textScale * widget.textZoom)
        .copyWith(
          height: widget.lineSpacing,
        );
    return Focus(
      focusNode: _todoFocusNode,
      autofocus: true,
      onKeyEvent: _handleTodoKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final useCompactItemActions =
              MediaQuery.sizeOf(context).shortestSide < 600 ||
                  availableWidth < 600;
          return Column(
            children: [
              for (var itemIndex = 0;
                  itemIndex < widget.paper.items.length;
                  itemIndex++)
                _todoReorderDropTarget(
                  item: widget.paper.items[itemIndex],
                  child: _todoRow(
                    context: context,
                    item: widget.paper.items[itemIndex],
                    itemTextStyle: itemTextStyle,
                    visualSpec: visualSpec,
                    compactActions: useCompactItemActions,
                  ),
                ),
              _todoDeleteDropTarget(context, visualSpec),
            ],
          );
        },
      ),
    );
  }

  Widget _todoReorderDropTarget({
    required PaperItem item,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final mobileBoard = !widget.standaloneSurface &&
        MediaQuery.sizeOf(context).shortestSide < 600;
    final dropTargetKey = _todoDropTargetKey(item);
    return DragTarget<PaperItem>(
      onWillAcceptWithDetails: (details) =>
          _canAcceptTodoItemDrop(details.data, item),
      onAcceptWithDetails: (details) => _reorderTodoItemToTarget(
        details.data,
        item,
        after: _dropAfterTodoTarget(item, details.offset),
      ),
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData
            .whereType<PaperItem>()
            .any((dragged) => _canAcceptTodoItemDrop(dragged, item));
        return DecoratedBox(
          key: dropTargetKey,
          decoration: BoxDecoration(
            color: highlighted
                ? colorScheme.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border.all(
              color: highlighted
                  ? colorScheme.primary
                  : mobileBoard
                      ? Colors.transparent
                      : colorScheme.primary.withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
                              ? 18 / 255
                              : 12 / 255,
                        ),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: child,
        );
      },
    );
  }

  GlobalKey _todoDropTargetKey(PaperItem item) {
    return _todoDropTargetKeys.putIfAbsent(
      item.id,
      () => GlobalKey(debugLabel: '${widget.paper.id}-${item.id}-drop-target'),
    );
  }

  bool _dropAfterTodoTarget(PaperItem target, Offset globalOffset) {
    final key = _todoDropTargetKeys[target.id];
    final renderObject = key?.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        renderObject.size.height <= 0) {
      return false;
    }
    final localOffset = renderObject.globalToLocal(globalOffset);
    return localOffset.dy >= renderObject.size.height / 2;
  }

  Widget _todoDeleteDropTarget(
    BuildContext context,
    _TodoVisualSpec visualSpec,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return DragTarget<PaperItem>(
      onWillAcceptWithDetails: (details) => _todoItemIndex(details.data) >= 0,
      onAcceptWithDetails: (details) {
        _setTodoItemDragging(false);
        _deleteItem(context, details.data);
      },
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData
            .whereType<PaperItem>()
            .any((item) => _todoItemIndex(item) >= 0);
        final visible = _isDraggingTodoItem || highlighted;
        final mobileBoard = !widget.standaloneSurface &&
            MediaQuery.sizeOf(context).shortestSide < 600;
        final targetHeight = widget.standaloneSurface
            ? visualSpec.controlExtent + 8
            : mobileBoard
                ? 53.0
                : math.max(48.0, visualSpec.controlExtent + 12);
        if (!visible) {
          return SizedBox(
            key: ValueKey('${widget.paper.id}-todo-delete-drop-target'),
            height: targetHeight,
            child: _todoFooterActions(visualSpec),
          );
        }
        return SizedBox(
          key: ValueKey('${widget.paper.id}-todo-delete-drop-target'),
          height: targetHeight,
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(
                alpha: highlighted ? 0.74 : 0.28,
              ),
              border: Border.all(
                color: colorScheme.error.withValues(
                  alpha: highlighted ? 0.92 : 0.32,
                ),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: visible
                ? ClipRect(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: visualSpec.iconSize,
                            color: colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            strings.get(PaperTodoStringKeys.actionDeleteItem),
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        );
      },
    );
  }

  Widget _todoFooterActions(_TodoVisualSpec visualSpec) {
    final colorScheme = Theme.of(context).colorScheme;
    if (widget.standaloneSurface) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final backgroundAlpha = isDark ? 18 / 255 : 12 / 255;
      const borderAlpha = 45 / 255;
      return Semantics(
        button: true,
        label: strings.get(PaperTodoStringKeys.actionAddItem),
        child: InkWell(
          onTap: _addItem,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.only(top: 6, bottom: 2),
            height: visualSpec.controlExtent,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: backgroundAlpha),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: borderAlpha),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.add,
              size: visualSpec.appendGlyphSize,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.42),
            ),
          ),
        ),
      );
    }
    final mobileBoard = MediaQuery.sizeOf(context).shortestSide < 600;
    if (mobileBoard) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                key: ValueKey('${widget.paper.id}-mobile-add-item'),
                height: 48,
                child: Semantics(
                  button: true,
                  label: strings.get(PaperTodoStringKeys.actionAddItem),
                  child: InkWell(
                    onTap: _addItem,
                    borderRadius: BorderRadius.circular(8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(
                          alpha: isDark ? 18 / 255 : 12 / 255,
                        ),
                        border: Border.all(
                          color:
                              colorScheme.primary.withValues(alpha: 45 / 255),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.add,
                          size: 20,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.54,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: _tooltipLabel(
                widget.enableToolTips,
                strings.get(PaperTodoStringKeys.actionUndoTodoChange),
              ),
              onPressed: _undoStack.isEmpty ? null : _undoTodoChange,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(48),
                maximumSize: const Size.square(48),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.72),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.undo, size: 18),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: _tooltipLabel(
                widget.enableToolTips,
                strings.get(PaperTodoStringKeys.actionRedoTodoChange),
              ),
              onPressed: _redoStack.isEmpty ? null : _redoTodoChange,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(48),
                maximumSize: const Size.square(48),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.72),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.redo, size: 18),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 5),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.035),
        border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: _addItem,
              icon: Icon(Icons.add, size: 17, color: colorScheme.primary),
              label: Text(strings.get(PaperTodoStringKeys.actionAddItem)),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurfaceVariant,
                alignment: Alignment.center,
                minimumSize: const Size.fromHeight(36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: _tooltipLabel(
              widget.enableToolTips,
              strings.get(PaperTodoStringKeys.actionUndoTodoChange),
            ),
            onPressed: _undoStack.isEmpty ? null : _undoTodoChange,
            icon: const Icon(Icons.undo, size: 17),
          ),
          IconButton(
            tooltip: _tooltipLabel(
              widget.enableToolTips,
              strings.get(PaperTodoStringKeys.actionRedoTodoChange),
            ),
            onPressed: _redoStack.isEmpty ? null : _redoTodoChange,
            icon: const Icon(Icons.redo, size: 17),
          ),
        ],
      ),
    );
  }

  Widget _todoRow({
    required BuildContext context,
    required PaperItem item,
    required TextStyle? itemTextStyle,
    required _TodoVisualSpec visualSpec,
    required bool compactActions,
  }) {
    final mobileBoard = !widget.standaloneSurface &&
        MediaQuery.sizeOf(context).shortestSide < 600;
    final leadingExtent = mobileBoard ? 48.0 : visualSpec.controlExtent;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: leadingExtent,
          child: Transform.scale(
            scale: visualSpec.checkboxScale,
            child: Checkbox(
              value: item.done,
              onChanged: (value) {
                _pushTodoUndoSnapshot();
                setState(() => item.done = value ?? false);
                unawaited(widget.onChanged());
              },
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _todoColumnFields(context, item, itemTextStyle, visualSpec),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ..._todoDueChips(context, item, visualSpec),
                  if (_formatReminderInterval(item)
                      case final reminderInterval?)
                    InputChip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      avatar: Icon(
                        Icons.notifications_active_outlined,
                        size: visualSpec.chipIconSize,
                      ),
                      labelStyle: _todoChipTextStyle(visualSpec),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      label: Text(reminderInterval),
                      onPressed: () =>
                          unawaited(_pickReminderInterval(context, item)),
                      onDeleted: () => _clearReminderInterval(item),
                      deleteIcon: Icon(
                        Icons.close_outlined,
                        size: visualSpec.chipIconSize,
                      ),
                      deleteButtonTooltipMessage: _tooltipLabel(
                        widget.enableToolTips,
                        strings.get(
                          PaperTodoStringKeys.actionClearReminderInterval,
                        ),
                      ),
                    ),
                  if (widget.enableTodoNoteLinks)
                    if (_linkedNoteFor(item) case final linkedNote?)
                      _linkedNoteChip(
                        linkedNote,
                        item,
                        visualSpec,
                      ),
                ],
              ),
            ],
          ),
        ),
        ..._todoItemActions(
          context: context,
          item: item,
          visualSpec: visualSpec,
          compact: compactActions,
        ),
      ],
    );
    final rowBody =
        widget.enableTodoNoteLinks ? _noteLinkDropTarget(item, row) : row;
    return Padding(
      key: ValueKey('${widget.paper.id}-${item.id}-row'),
      padding: EdgeInsets.only(bottom: visualSpec.itemGap),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) =>
            _handleTodoContextMenuPointerDown(context, item, event),
        child: rowBody,
      ),
    );
  }

  void _handleTodoContextMenuPointerDown(
    BuildContext context,
    PaperItem item,
    PointerDownEvent event,
  ) {
    if (event.buttons & kSecondaryMouseButton == 0) {
      return;
    }
    final columnIndex = _todoContextColumnIndexForPosition(
      item,
      event.position,
    );
    _focusTodoColumn(item, columnIndex);
    unawaited(
      _showTodoItemContextMenu(
        context,
        item,
        columnIndex,
        event.position,
      ),
    );
  }

  Future<void> _showTodoItemContextMenu(
    BuildContext context,
    PaperItem item,
    int columnIndex,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (overlay is! RenderBox) {
      return;
    }
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: _todoItemContextMenuItems(item, columnIndex),
    );
    if (!mounted || !context.mounted) {
      return;
    }
    _focusTodoColumn(item, columnIndex);
    if (selected == null) {
      return;
    }
    _handleCompactTodoAction(context: context, item: item, value: selected);
  }

  List<PopupMenuEntry<String>> _todoItemContextMenuItems(
    PaperItem item,
    int columnIndex,
  ) {
    final hasLinkedNote = item.linkedNoteId?.trim().isNotEmpty ?? false;
    final normalizedColumnIndex =
        columnIndex.clamp(0, math.max(0, item.todoColumnCount - 1)).toInt();
    return [
      _paperTodoMenuHeader(strings.get(PaperTodoStringKeys.menuTodoItem)),
      if (widget.enableTodoNoteLinks && hasLinkedNote) ...[
        if (_linkedNoteFor(item) case final PaperData linkedNote)
          _todoActionMenuItem(
            value: _compactTodoActionOpenLinkedNote,
            icon: Icons.open_in_new,
            label: widget.runLinkedScriptCapsulesOnClick &&
                    ScriptCapsuleSpec.tryParse(linkedNote.content) != null
                ? strings.get(PaperTodoStringKeys.actionEditLinkedScript)
                : strings.get(PaperTodoStringKeys.actionOpenLinkedNote),
          ),
        _todoActionMenuItem(
          value: _compactTodoActionUnlinkNote,
          icon: Icons.link_off_outlined,
          label: strings.get(PaperTodoStringKeys.actionUnlinkNote),
        ),
        const PopupMenuDivider(),
      ],
      _todoActionMenuItem(
        value: _compactTodoActionDueDate,
        icon: Icons.event_outlined,
        label: _hasDueDate(item)
            ? strings.get(PaperTodoStringKeys.actionChangeDueDate)
            : strings.get(PaperTodoStringKeys.actionSetDueDate),
      ),
      if (_hasDueDate(item))
        _todoActionMenuItem(
          value: _compactTodoActionClearDueDate,
          icon: Icons.event_busy_outlined,
          label: strings.get(PaperTodoStringKeys.actionClearDueDate),
        ),
      _todoActionMenuItem(
        value: _compactTodoActionReminder,
        icon: Icons.notifications_none_outlined,
        label: _hasReminderInterval(item)
            ? strings.get(PaperTodoStringKeys.actionChangeReminder)
            : strings.get(PaperTodoStringKeys.actionSetReminder),
      ),
      if (_hasReminderInterval(item))
        _todoActionMenuItem(
          value: _compactTodoActionClearReminder,
          icon: Icons.notifications_off_outlined,
          label: strings.get(PaperTodoStringKeys.actionClearReminder),
        ),
      if (widget.enableTodoNoteLinks &&
          widget.notePapers.isNotEmpty &&
          !hasLinkedNote) ...[
        const PopupMenuDivider(),
        for (final note in widget.notePapers)
          _todoActionMenuItem(
            value: '$_compactTodoLinkActionPrefix${note.id}',
            icon: Icons.notes_outlined,
            label: _displayPaperTitle(note),
          ),
      ],
      const PopupMenuDivider(),
      _todoActionMenuItem(
        value:
            '$_compactTodoColumnActionPrefix$_columnActionInsertBeforePrefix$normalizedColumnIndex',
        icon: Icons.add_box_outlined,
        label: strings.format(
          PaperTodoStringKeys.actionInsertBeforeColumn,
          [normalizedColumnIndex + 1],
        ),
        enabled: item.todoColumnCount < TodoColumnLimits.maxCount,
      ),
      _todoActionMenuItem(
        value:
            '$_compactTodoColumnActionPrefix$_columnActionDeletePrefix$normalizedColumnIndex',
        icon: Icons.delete_sweep_outlined,
        label: strings.format(
          PaperTodoStringKeys.actionDeleteColumn,
          [normalizedColumnIndex + 1],
        ),
        enabled: item.todoColumnCount > 1,
      ),
      _todoActionMenuItem(
        value: '$_compactTodoColumnActionPrefix$_columnActionAdd',
        icon: Icons.add,
        label: strings.get(PaperTodoStringKeys.actionAddColumn),
        enabled: item.todoColumnCount < TodoColumnLimits.maxCount,
      ),
      _todoActionMenuItem(
        value: '$_compactTodoColumnActionPrefix$_columnActionRemove',
        icon: Icons.remove,
        label: strings.get(PaperTodoStringKeys.actionRemoveLastColumn),
        enabled: item.todoColumnCount > 1,
      ),
      _todoActionMenuItem(
        value: '$_compactTodoColumnActionPrefix$_columnActionEqualWidths',
        icon: Icons.view_column_outlined,
        label: strings.get(PaperTodoStringKeys.actionEqualWidths),
        enabled: item.todoColumnCount > 1,
      ),
      _todoActionMenuItem(
        value: '$_compactTodoColumnActionPrefix$_columnActionWideFirst',
        icon: Icons.view_week_outlined,
        label: strings.get(PaperTodoStringKeys.actionWideFirstColumn),
        enabled: item.todoColumnCount > 1,
      ),
      const PopupMenuDivider(),
      _todoActionMenuItem(
        value: _compactTodoActionMoveUp,
        icon: Icons.keyboard_arrow_up,
        label: strings.get(PaperTodoStringKeys.actionMoveItemUp),
        enabled: _canMoveTodoItem(item, -1),
      ),
      _todoActionMenuItem(
        value: _compactTodoActionMoveDown,
        icon: Icons.keyboard_arrow_down,
        label: strings.get(PaperTodoStringKeys.actionMoveItemDown),
        enabled: _canMoveTodoItem(item, 1),
      ),
      const PopupMenuDivider(),
      _todoActionMenuItem(
        value: _compactTodoActionDelete,
        icon: Icons.delete_outline,
        label: strings.get(PaperTodoStringKeys.actionDeleteItem),
      ),
      _todoActionMenuItem(
        value: _compactTodoActionClearDone,
        icon: Icons.delete_sweep_outlined,
        label: strings.get(PaperTodoStringKeys.actionClearCompleted),
        enabled: _hasDoneTodoItems,
      ),
    ];
  }

  int _todoContextColumnIndexForPosition(
    PaperItem item,
    Offset globalPosition,
  ) {
    item.normalize();
    for (var columnIndex = 0;
        columnIndex < item.todoColumnCount;
        columnIndex++) {
      if (_globalPositionInsideKey(
        _todoColumnHitTestKey(item, columnIndex),
        globalPosition,
      )) {
        return columnIndex;
      }
    }
    return 0;
  }

  bool _globalPositionInsideKey(GlobalKey key, Offset globalPosition) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return false;
    }
    final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    return rect.contains(globalPosition);
  }

  List<Widget> _todoDueChips(
    BuildContext context,
    PaperItem item,
    _TodoVisualSpec visualSpec,
  ) {
    final dueAt = parsePaperTodoDueAtLocal(item.dueAtLocal);
    if (dueAt == null) {
      return const [];
    }

    final chipTextStyle = _todoChipTextStyle(visualSpec);
    final chips = <Widget>[];
    if (widget.showDueRelativeTime) {
      chips.add(
        Chip(
          key: ValueKey('${widget.paper.id}-${item.id}-due-relative'),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          avatar: Icon(
            Icons.schedule_outlined,
            size: visualSpec.chipIconSize,
          ),
          labelStyle: chipTextStyle,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          label: Text(
            strings.format(
              PaperTodoStringKeys.dueLabel,
              [_formatRelativeDueDate(dueAt)],
            ),
          ),
        ),
      );
    }

    chips.add(
      InputChip(
        key: ValueKey('${widget.paper.id}-${item.id}-due-absolute'),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        avatar: Icon(
          Icons.event_outlined,
          size: visualSpec.chipIconSize,
        ),
        labelStyle: chipTextStyle,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        label: Text(
          strings.format(
            PaperTodoStringKeys.dueLabel,
            [_formatAbsoluteDueDate(dueAt)],
          ),
        ),
        onPressed: () => unawaited(_pickDueDate(context, item)),
        onDeleted: () => _clearDueDate(item),
        deleteIcon: Icon(
          Icons.close_outlined,
          size: visualSpec.chipIconSize,
        ),
        deleteButtonTooltipMessage: _tooltipLabel(
          widget.enableToolTips,
          strings.get(PaperTodoStringKeys.actionClearDueDate),
        ),
      ),
    );

    return chips;
  }

  Widget _noteLinkDropTarget(PaperItem item, Widget row) {
    final colorScheme = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          _canAcceptNoteLinkDrop(details.data),
      onAcceptWithDetails: (details) => _linkNote(item, details.data),
      builder: (context, candidateData, rejectedData) {
        final highlighted =
            candidateData.whereType<String>().any(_canAcceptNoteLinkDrop);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: highlighted
                ? colorScheme.primaryContainer.withValues(alpha: 0.38)
                : Colors.transparent,
            border: Border.all(
              color: highlighted ? colorScheme.primary : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: row,
        );
      },
    );
  }

  bool _canAcceptNoteLinkDrop(String noteId) {
    return widget.enableTodoNoteLinks && _notePaperById(noteId) != null;
  }

  static const _columnActionAdd = 'add';
  static const _columnActionRemove = 'remove';
  static const _columnActionEqualWidths = 'equal-widths';
  static const _columnActionWideFirst = 'wide-first';
  static const _columnActionInsertBeforePrefix = 'insert-before:';
  static const _columnActionDeletePrefix = 'delete:';
  static const _compactTodoActionDueDate = 'due-date';
  static const _compactTodoActionClearDueDate = 'clear-due-date';
  static const _compactTodoActionReminder = 'reminder';
  static const _compactTodoActionClearReminder = 'clear-reminder';
  static const _compactTodoActionMoveUp = 'move-up';
  static const _compactTodoActionMoveDown = 'move-down';
  static const _compactTodoActionOpenLinkedNote = 'open-linked-note';
  static const _compactTodoActionUnlinkNote = 'unlink-note';
  static const _compactTodoActionDelete = 'delete';
  static const _compactTodoActionClearDone = 'clear-done';
  static const _compactTodoColumnActionPrefix = 'column:';
  static const _compactTodoLinkActionPrefix = 'link:';
  static const _todoLinkActionUnlink = 'todo-link:unlink';

  List<Widget> _todoItemActions({
    required BuildContext context,
    required PaperItem item,
    required _TodoVisualSpec visualSpec,
    required bool compact,
  }) {
    final hasLinkedNote = item.linkedNoteId?.trim().isNotEmpty ?? false;
    if (widget.standaloneSurface) {
      return [
        Draggable<PaperItem>(
          key: ValueKey('${widget.paper.id}-${item.id}-drag-handle'),
          data: item,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _todoDragFeedback(item, visualSpec),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: _standaloneTodoDragHandle(visualSpec),
          ),
          onDragStarted: () => _setTodoItemDragging(true),
          onDragCompleted: () => _setTodoItemDragging(false),
          onDraggableCanceled: (_, __) => _setTodoItemDragging(false),
          onDragEnd: (_) => _setTodoItemDragging(false),
          child: _standaloneTodoDragHandle(visualSpec),
        ),
      ];
    }
    if (compact) {
      final actionExtent =
          widget.standaloneSurface ? visualSpec.controlExtent : 48.0;
      return [
        SizedBox(
          key: ValueKey('${widget.paper.id}-${item.id}-actions'),
          width: actionExtent,
          height: actionExtent,
          child: PopupMenuButton<String>(
            tooltip: _tooltipLabel(
              widget.enableToolTips,
              strings.get(PaperTodoStringKeys.actionTodoItemActions),
            ),
            iconSize: visualSpec.iconSize,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _handleCompactTodoAction(
              context: context,
              item: item,
              value: value,
            ),
            itemBuilder: (context) => [
              _todoActionMenuItem(
                value: _compactTodoActionDueDate,
                icon: Icons.event_outlined,
                label: _hasDueDate(item)
                    ? strings.get(PaperTodoStringKeys.actionChangeDueDate)
                    : strings.get(PaperTodoStringKeys.actionSetDueDate),
              ),
              if (_hasDueDate(item))
                _todoActionMenuItem(
                  value: _compactTodoActionClearDueDate,
                  icon: Icons.event_busy_outlined,
                  label: strings.get(PaperTodoStringKeys.actionClearDueDate),
                ),
              _todoActionMenuItem(
                value: _compactTodoActionReminder,
                icon: Icons.notifications_none_outlined,
                label: _hasReminderInterval(item)
                    ? strings.get(PaperTodoStringKeys.actionChangeReminder)
                    : strings.get(PaperTodoStringKeys.actionSetReminder),
              ),
              if (_hasReminderInterval(item))
                _todoActionMenuItem(
                  value: _compactTodoActionClearReminder,
                  icon: Icons.notifications_off_outlined,
                  label: strings.get(PaperTodoStringKeys.actionClearReminder),
                ),
              if (widget.enableTodoNoteLinks && hasLinkedNote) ...[
                const PopupMenuDivider(),
                if (_linkedNoteFor(item) case final PaperData linkedNote)
                  _todoActionMenuItem(
                    value: _compactTodoActionOpenLinkedNote,
                    icon: Icons.open_in_new,
                    label: widget.runLinkedScriptCapsulesOnClick &&
                            ScriptCapsuleSpec.tryParse(linkedNote.content) !=
                                null
                        ? strings
                            .get(PaperTodoStringKeys.actionEditLinkedScript)
                        : strings.get(PaperTodoStringKeys.actionOpenLinkedNote),
                  ),
                _todoActionMenuItem(
                  value: _compactTodoActionUnlinkNote,
                  icon: Icons.link_off_outlined,
                  label: strings.get(PaperTodoStringKeys.actionUnlinkNote),
                ),
              ],
              if (widget.enableTodoNoteLinks &&
                  widget.notePapers.isNotEmpty &&
                  !hasLinkedNote) ...[
                const PopupMenuDivider(),
                for (final note in widget.notePapers)
                  _todoActionMenuItem(
                    value: '$_compactTodoLinkActionPrefix${note.id}',
                    icon: item.linkedNoteId == note.id
                        ? Icons.link_outlined
                        : Icons.notes_outlined,
                    label: _displayPaperTitle(note),
                  ),
              ],
              const PopupMenuDivider(),
              _todoActionMenuItem(
                value: _compactTodoActionDelete,
                icon: Icons.delete_outline,
                label: strings.get(PaperTodoStringKeys.actionDeleteItem),
              ),
              _todoActionMenuItem(
                value: _compactTodoActionClearDone,
                icon: Icons.delete_sweep_outlined,
                label: strings.get(PaperTodoStringKeys.actionClearCompleted),
                enabled: _hasDoneTodoItems,
              ),
              const PopupMenuDivider(),
              _todoActionMenuItem(
                value: _compactTodoActionMoveUp,
                icon: Icons.keyboard_arrow_up,
                label: strings.get(PaperTodoStringKeys.actionMoveItemUp),
                enabled: _canMoveTodoItem(item, -1),
              ),
              _todoActionMenuItem(
                value: _compactTodoActionMoveDown,
                icon: Icons.keyboard_arrow_down,
                label: strings.get(PaperTodoStringKeys.actionMoveItemDown),
                enabled: _canMoveTodoItem(item, 1),
              ),
              const PopupMenuDivider(),
              _todoActionMenuItem(
                value: '$_compactTodoColumnActionPrefix$_columnActionAdd',
                icon: Icons.add,
                label: strings.get(PaperTodoStringKeys.actionAddColumn),
                enabled: item.todoColumnCount < TodoColumnLimits.maxCount,
              ),
              _todoActionMenuItem(
                value: '$_compactTodoColumnActionPrefix$_columnActionRemove',
                icon: Icons.remove,
                label: strings.get(PaperTodoStringKeys.actionRemoveLastColumn),
                enabled: item.todoColumnCount > 1,
              ),
              for (var columnIndex = 0;
                  columnIndex < item.todoColumnCount;
                  columnIndex++)
                _todoActionMenuItem(
                  value:
                      '$_compactTodoColumnActionPrefix$_columnActionInsertBeforePrefix$columnIndex',
                  icon: Icons.add_box_outlined,
                  label: strings.format(
                    PaperTodoStringKeys.actionInsertBeforeColumn,
                    [columnIndex + 1],
                  ),
                  enabled: item.todoColumnCount < TodoColumnLimits.maxCount,
                ),
              for (var columnIndex = 0;
                  columnIndex < item.todoColumnCount;
                  columnIndex++)
                _todoActionMenuItem(
                  value:
                      '$_compactTodoColumnActionPrefix$_columnActionDeletePrefix$columnIndex',
                  icon: Icons.delete_sweep_outlined,
                  label: strings.format(
                    PaperTodoStringKeys.actionDeleteColumn,
                    [columnIndex + 1],
                  ),
                  enabled: item.todoColumnCount > 1,
                ),
              _todoActionMenuItem(
                value:
                    '$_compactTodoColumnActionPrefix$_columnActionEqualWidths',
                icon: Icons.view_column_outlined,
                label: strings.get(PaperTodoStringKeys.actionEqualWidths),
                enabled: item.todoColumnCount > 1,
              ),
              _todoActionMenuItem(
                value: '$_compactTodoColumnActionPrefix$_columnActionWideFirst',
                icon: Icons.view_week_outlined,
                label: strings.get(PaperTodoStringKeys.actionWideFirstColumn),
                enabled: item.todoColumnCount > 1,
              ),
              if (widget.enableTodoNoteLinks &&
                  widget.notePapers.isNotEmpty &&
                  hasLinkedNote) ...[
                const PopupMenuDivider(),
                for (final note in widget.notePapers)
                  _todoActionMenuItem(
                    value: '$_compactTodoLinkActionPrefix${note.id}',
                    icon: item.linkedNoteId == note.id
                        ? Icons.link_outlined
                        : Icons.notes_outlined,
                    label: _displayPaperTitle(note),
                  ),
              ],
            ],
          ),
        ),
      ];
    }
    return [
      Draggable<PaperItem>(
        key: ValueKey('${widget.paper.id}-${item.id}-drag-handle'),
        data: item,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _todoDragFeedback(item, visualSpec),
        childWhenDragging: Opacity(
          opacity: 0.35,
          child: _todoDragHandle(visualSpec),
        ),
        onDragStarted: () => _setTodoItemDragging(true),
        onDragCompleted: () => _setTodoItemDragging(false),
        onDraggableCanceled: (_, __) => _setTodoItemDragging(false),
        onDragEnd: (_) => _setTodoItemDragging(false),
        child: _maybeTooltip(
          enabled: widget.enableToolTips,
          message: strings.get(PaperTodoStringKeys.actionDragToReorder),
          child: _todoDragHandle(visualSpec),
        ),
      ),
      IconButton(
        tooltip: _tooltipLabel(
          widget.enableToolTips,
          strings.get(PaperTodoStringKeys.actionSetDueDate),
        ),
        onPressed: () => unawaited(_pickDueDate(context, item)),
        iconSize: visualSpec.iconSize,
        constraints: BoxConstraints.tightFor(
          width: visualSpec.controlExtent,
          height: visualSpec.controlExtent,
        ),
        icon: const Icon(Icons.event_outlined),
      ),
      IconButton(
        tooltip: _tooltipLabel(
          widget.enableToolTips,
          strings.get(PaperTodoStringKeys.actionSetReminderInterval),
        ),
        onPressed: () => unawaited(_pickReminderInterval(context, item)),
        iconSize: visualSpec.iconSize,
        constraints: BoxConstraints.tightFor(
          width: visualSpec.controlExtent,
          height: visualSpec.controlExtent,
        ),
        icon: const Icon(Icons.notifications_none_outlined),
      ),
      SizedBox(
        width: visualSpec.controlExtent,
        height: visualSpec.controlExtent,
        child: PopupMenuButton<String>(
          tooltip: _tooltipLabel(
            widget.enableToolTips,
            strings.get(PaperTodoStringKeys.actionTodoColumns),
          ),
          iconSize: visualSpec.iconSize,
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.table_chart_outlined),
          onSelected: (value) => _updateColumns(item, value),
          itemBuilder: (context) {
            return [
              PopupMenuItem(
                value: _columnActionAdd,
                enabled: item.todoColumnCount < TodoColumnLimits.maxCount,
                child: ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(strings.get(PaperTodoStringKeys.actionAddColumn)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _columnActionRemove,
                enabled: item.todoColumnCount > 1,
                child: ListTile(
                  leading: const Icon(Icons.remove),
                  title: Text(
                    strings.get(PaperTodoStringKeys.actionRemoveLastColumn),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              for (var columnIndex = 0;
                  columnIndex < item.todoColumnCount;
                  columnIndex++)
                PopupMenuItem(
                  value: '$_columnActionInsertBeforePrefix$columnIndex',
                  enabled: item.todoColumnCount < TodoColumnLimits.maxCount,
                  child: ListTile(
                    leading: const Icon(Icons.add_box_outlined),
                    title: Text(
                      strings.format(
                        PaperTodoStringKeys.actionInsertBeforeColumn,
                        [columnIndex + 1],
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              for (var columnIndex = 0;
                  columnIndex < item.todoColumnCount;
                  columnIndex++)
                PopupMenuItem(
                  value: '$_columnActionDeletePrefix$columnIndex',
                  enabled: item.todoColumnCount > 1,
                  child: ListTile(
                    leading: const Icon(Icons.delete_sweep_outlined),
                    title: Text(
                      strings.format(
                        PaperTodoStringKeys.actionDeleteColumn,
                        [columnIndex + 1],
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _columnActionEqualWidths,
                enabled: item.todoColumnCount > 1,
                child: ListTile(
                  leading: const Icon(Icons.view_column_outlined),
                  title:
                      Text(strings.get(PaperTodoStringKeys.actionEqualWidths)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _columnActionWideFirst,
                enabled: item.todoColumnCount > 1,
                child: ListTile(
                  leading: const Icon(Icons.view_week_outlined),
                  title: Text(
                    strings.get(PaperTodoStringKeys.actionWideFirstColumn),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ];
          },
        ),
      ),
      SizedBox(
        width: visualSpec.controlExtent,
        height: visualSpec.controlExtent,
        child: PopupMenuButton<String>(
          tooltip: _tooltipLabel(
            widget.enableToolTips,
            strings.get(PaperTodoStringKeys.actionLinkNote),
          ),
          enabled: widget.enableTodoNoteLinks &&
              (widget.notePapers.isNotEmpty ||
                  (item.linkedNoteId?.trim().isNotEmpty ?? false)),
          iconSize: visualSpec.iconSize,
          padding: EdgeInsets.zero,
          icon: Icon(item.linkedNoteId == null
              ? Icons.note_add_outlined
              : Icons.link_outlined),
          onSelected: (value) {
            if (value == _todoLinkActionUnlink) {
              _clearLinkedNote(item);
              return;
            }
            _linkNote(item, value);
          },
          itemBuilder: (context) {
            return [
              if (item.linkedNoteId?.trim().isNotEmpty ?? false) ...[
                _todoActionMenuItem(
                  value: _todoLinkActionUnlink,
                  icon: Icons.link_off_outlined,
                  label: strings.get(PaperTodoStringKeys.actionUnlinkNote),
                ),
                if (widget.notePapers.isNotEmpty) const PopupMenuDivider(),
              ],
              for (final note in widget.notePapers)
                _todoActionMenuItem(
                  value: note.id,
                  icon: item.linkedNoteId == note.id
                      ? Icons.link_outlined
                      : Icons.notes_outlined,
                  label: _displayPaperTitle(note),
                ),
            ];
          },
        ),
      ),
      IconButton(
        tooltip: _tooltipLabel(
          widget.enableToolTips,
          strings.get(PaperTodoStringKeys.actionMoveItemUp),
        ),
        onPressed:
            _canMoveTodoItem(item, -1) ? () => _moveTodoItem(item, -1) : null,
        iconSize: visualSpec.iconSize,
        constraints: BoxConstraints.tightFor(
          width: visualSpec.controlExtent,
          height: visualSpec.controlExtent,
        ),
        icon: const Icon(Icons.keyboard_arrow_up),
      ),
      IconButton(
        tooltip: _tooltipLabel(
          widget.enableToolTips,
          strings.get(PaperTodoStringKeys.actionMoveItemDown),
        ),
        onPressed:
            _canMoveTodoItem(item, 1) ? () => _moveTodoItem(item, 1) : null,
        iconSize: visualSpec.iconSize,
        constraints: BoxConstraints.tightFor(
          width: visualSpec.controlExtent,
          height: visualSpec.controlExtent,
        ),
        icon: const Icon(Icons.keyboard_arrow_down),
      ),
      IconButton(
        tooltip: _tooltipLabel(
          widget.enableToolTips,
          strings.get(PaperTodoStringKeys.actionDeleteItem),
        ),
        onPressed: () => _deleteItem(context, item),
        iconSize: visualSpec.iconSize,
        constraints: BoxConstraints.tightFor(
          width: visualSpec.controlExtent,
          height: visualSpec.controlExtent,
        ),
        icon: const Icon(Icons.delete_outline),
      ),
      IconButton(
        tooltip: _tooltipLabel(
          widget.enableToolTips,
          strings.get(PaperTodoStringKeys.actionClearCompletedItems),
        ),
        onPressed: _hasDoneTodoItems ? _clearDoneItems : null,
        iconSize: visualSpec.iconSize,
        constraints: BoxConstraints.tightFor(
          width: visualSpec.controlExtent,
          height: visualSpec.controlExtent,
        ),
        icon: const Icon(Icons.delete_sweep_outlined),
      ),
    ];
  }

  Widget _standaloneTodoDragHandle(_TodoVisualSpec visualSpec) {
    return _maybeTooltip(
      enabled: widget.enableToolTips,
      message: strings.get(PaperTodoStringKeys.actionDragToReorder),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: SizedBox(
          width: visualSpec.controlExtent,
          height: visualSpec.controlExtent,
          child: Icon(
            Icons.drag_handle,
            size: visualSpec.iconSize,
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withValues(alpha: 0.62),
          ),
        ),
      ),
    );
  }

  Widget _todoDragHandle(_TodoVisualSpec visualSpec) {
    return SizedBox(
      width: visualSpec.controlExtent,
      height: visualSpec.controlExtent,
      child: Icon(Icons.drag_handle, size: visualSpec.iconSize),
    );
  }

  Widget _todoDragFeedback(PaperItem item, _TodoVisualSpec visualSpec) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.drag_handle,
                  size: visualSpec.iconSize,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _displayItemText(item),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _todoActionMenuItem({
    required String value,
    required IconData icon,
    required String label,
    bool enabled = true,
  }) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      height: _paperTodoPopupMenuHeight(),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }

  Widget _maybeTooltip({
    required bool enabled,
    required String message,
    required Widget child,
  }) {
    if (!enabled) {
      return child;
    }
    return Tooltip(message: message, child: child);
  }

  void _handleCompactTodoAction({
    required BuildContext context,
    required PaperItem item,
    required String value,
  }) {
    if (value.startsWith(_compactTodoColumnActionPrefix)) {
      _updateColumns(
        item,
        value.substring(_compactTodoColumnActionPrefix.length),
      );
      return;
    }
    if (value.startsWith(_compactTodoLinkActionPrefix)) {
      _linkNote(item, value.substring(_compactTodoLinkActionPrefix.length));
      return;
    }
    switch (value) {
      case _compactTodoActionDueDate:
        unawaited(_pickDueDate(context, item));
      case _compactTodoActionClearDueDate:
        _clearDueDate(item);
      case _compactTodoActionReminder:
        unawaited(_pickReminderInterval(context, item));
      case _compactTodoActionClearReminder:
        _clearReminderInterval(item);
      case _compactTodoActionMoveUp:
        _moveTodoItem(item, -1);
      case _compactTodoActionMoveDown:
        _moveTodoItem(item, 1);
      case _compactTodoActionOpenLinkedNote:
        _openLinkedNote(item);
      case _compactTodoActionUnlinkNote:
        _clearLinkedNote(item);
      case _compactTodoActionDelete:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _deleteItem(context, item);
          }
        });
      case _compactTodoActionClearDone:
        _clearDoneItems();
    }
  }

  List<Map<String, Object?>> _snapshotTodoItems() {
    return [
      for (final item in widget.paper.items)
        Map<String, Object?>.from(item.toJson()),
    ];
  }

  void _pushTodoUndoSnapshot({bool commitFocusedText = true}) {
    if (commitFocusedText) {
      _commitFocusedTodoTextIfNeeded();
    }
    _undoStack.add(_snapshotTodoItems());
    if (_undoStack.length > _maxTodoUndoDepth) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  bool _commitFocusedTodoTextIfNeeded({bool clearRedo = false}) {
    final itemId = _activeOriginalTodoItemId;
    final originalText = _activeOriginalTodoText;
    if (itemId == null || originalText == null) {
      return false;
    }
    final item = _todoItemById(itemId);
    if (item == null) {
      _activeOriginalTodoItemId = null;
      _activeOriginalTodoColumnIndex = null;
      _activeOriginalTodoText = null;
      return false;
    }
    final columnIndex = _activeOriginalTodoColumnIndex;
    final currentText = _todoColumnText(item, columnIndex);
    if (currentText == null) {
      _activeOriginalTodoItemId = null;
      _activeOriginalTodoColumnIndex = null;
      _activeOriginalTodoText = null;
      return false;
    }
    if (currentText == originalText) {
      return false;
    }

    _setTodoColumnText(item, columnIndex, originalText);
    _undoStack.add(_snapshotTodoItems());
    if (_undoStack.length > _maxTodoUndoDepth) {
      _undoStack.removeAt(0);
    }
    _setTodoColumnText(item, columnIndex, currentText);
    _activeOriginalTodoText = currentText;
    if (clearRedo) {
      _redoStack.clear();
    }
    return true;
  }

  PaperItem? _todoItemById(String itemId) {
    for (final item in widget.paper.items) {
      if (item.id == itemId) {
        return item;
      }
    }
    return null;
  }

  void _markTodoTextEditCommitted(PaperItem item, {int? columnIndex}) {
    if (_activeOriginalTodoItemId == item.id &&
        _activeOriginalTodoColumnIndex == columnIndex) {
      _activeOriginalTodoText = _todoColumnText(item, columnIndex);
    }
  }

  void _restoreTodoSnapshot(List<Map<String, Object?>> snapshot) {
    final beforeItems = [...widget.paper.items];
    late final List<PaperItem> afterItems;
    setState(() {
      afterItems = [
        for (final itemJson in snapshot)
          PaperItem.fromJson(Map<String, Object?>.from(itemJson)),
      ];
      widget.paper.items = afterItems;
      widget.paper.normalize();
      _textFieldRevision++;
    });
    _clearActiveTodoTextTracking();
    _reconcileTodoItemTombstones(beforeItems, afterItems);
    _requestTodoFocus();
    unawaited(widget.onChanged());
  }

  void _clearActiveTodoTextTracking() {
    _activeOriginalTodoItemId = null;
    _activeOriginalTodoColumnIndex = null;
    _activeOriginalTodoText = null;
    _clearFocusedTodoTextHistory();
  }

  void _reconcileTodoItemTombstones(
    List<PaperItem> beforeItems,
    List<PaperItem> afterItems,
  ) {
    final beforeById = {
      for (final item in beforeItems)
        if (item.id.trim().isNotEmpty) item.id: item,
    };
    final afterById = {
      for (final item in afterItems)
        if (item.id.trim().isNotEmpty) item.id: item,
    };
    for (final entry in beforeById.entries) {
      if (!afterById.containsKey(entry.key)) {
        widget.onItemDeleted(widget.paper, entry.value);
      }
    }
    for (final entry in afterById.entries) {
      if (!beforeById.containsKey(entry.key)) {
        widget.onItemRestored(widget.paper, entry.value);
      }
    }
  }

  void _requestTodoFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _todoFocusNode.requestFocus();
      }
    });
  }

  FocusNode _mainTodoFieldFocusNode(PaperItem item) {
    final focusNode = _todoMainFieldFocusNodes.putIfAbsent(
      item.id,
      () {
        final node = FocusNode(debugLabel: 'todo-main-${item.id}');
        node.addListener(
          () => _handleMainTodoFieldFocusChange(item.id, node),
        );
        return node;
      },
    );
    focusNode.onKeyEvent =
        (node, event) => _handleTodoItemKeyEvent(node, item, event);
    return focusNode;
  }

  void _handleMainTodoFieldFocusChange(String itemId, FocusNode focusNode) {
    if (focusNode.hasFocus) {
      _activeOriginalTodoItemId = itemId;
      _activeOriginalTodoColumnIndex = null;
      _activeOriginalTodoText = _todoItemById(itemId)?.text ?? '';
      _clearFocusedTodoTextHistory();
      return;
    }
    if (_activeOriginalTodoItemId != itemId ||
        _activeOriginalTodoColumnIndex != null) {
      return;
    }
    final committed = _commitFocusedTodoTextIfNeeded(clearRedo: true);
    _clearFocusedTodoTextHistory();
    if (committed && mounted) {
      setState(() {});
    }
  }

  FocusNode _extraTodoFieldFocusNode(PaperItem item, int index) {
    final focusKey = '${item.id}:$index';
    final focusNode = _todoExtraFieldFocusNodes.putIfAbsent(
      focusKey,
      () {
        final node = FocusNode(debugLabel: 'todo-extra-$focusKey');
        node.addListener(
          () => _handleExtraTodoFieldFocusChange(item.id, index, node),
        );
        return node;
      },
    );
    focusNode.onKeyEvent =
        (node, event) => _handleTodoItemKeyEvent(node, item, event);
    return focusNode;
  }

  void _handleExtraTodoFieldFocusChange(
    String itemId,
    int columnIndex,
    FocusNode focusNode,
  ) {
    if (focusNode.hasFocus) {
      final item = _todoItemById(itemId);
      _activeOriginalTodoItemId = itemId;
      _activeOriginalTodoColumnIndex = columnIndex;
      _activeOriginalTodoText =
          item == null ? '' : _todoColumnText(item, columnIndex) ?? '';
      _clearFocusedTodoTextHistory();
      return;
    }
    if (_activeOriginalTodoItemId != itemId ||
        _activeOriginalTodoColumnIndex != columnIndex) {
      return;
    }
    final committed = _commitFocusedTodoTextIfNeeded(clearRedo: true);
    _clearFocusedTodoTextHistory();
    if (committed && mounted) {
      setState(() {});
    }
  }

  void _requestTodoItemFocus(
    String? itemId, {
    _TodoFocusPlacement placement = _TodoFocusPlacement.end,
  }) {
    if (itemId == null) {
      _requestTodoFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final focusNode = _todoMainFieldFocusNodes[itemId];
      if (focusNode == null) {
        _todoFocusNode.requestFocus();
        return;
      }
      focusNode.requestFocus();
      _placeTodoCaret(focusNode, placement);
    });
  }

  void _focusTodoColumn(PaperItem item, int columnIndex) {
    final normalizedColumnIndex =
        columnIndex.clamp(0, math.max(0, item.todoColumnCount - 1)).toInt();
    final focusNode = normalizedColumnIndex == 0
        ? _todoMainFieldFocusNodes[item.id]
        : _todoExtraFieldFocusNodes['${item.id}:${normalizedColumnIndex - 1}'];
    if (focusNode == null) {
      return;
    }
    focusNode.requestFocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
  }

  void _placeTodoCaret(FocusNode focusNode, _TodoFocusPlacement placement) {
    final editable = _editableTextStateFor(focusNode.context);
    if (editable == null) {
      return;
    }
    final value = editable.textEditingValue;
    final offset = switch (placement) {
      _TodoFocusPlacement.start => 0,
      _TodoFocusPlacement.end => value.text.length,
    };
    editable.userUpdateTextEditingValue(
      value.copyWith(selection: TextSelection.collapsed(offset: offset)),
      SelectionChangedCause.keyboard,
    );
  }

  EditableTextState? _editableTextStateFor(BuildContext? context) {
    if (context == null) {
      return null;
    }
    final ancestor = context.findAncestorStateOfType<EditableTextState>();
    if (ancestor != null) {
      return ancestor;
    }
    EditableTextState? descendant;
    void visit(Element element) {
      if (descendant != null) {
        return;
      }
      if (element is StatefulElement && element.state is EditableTextState) {
        descendant = element.state as EditableTextState;
        return;
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return descendant;
  }

  void _unfocusTodoItem(PaperItem item) {
    _todoMainFieldFocusNodes[item.id]?.unfocus();
    final extraKeyPrefix = '${item.id}:';
    for (final entry in _todoExtraFieldFocusNodes.entries) {
      if (entry.key.startsWith(extraKeyPrefix)) {
        entry.value.unfocus();
      }
    }
  }

  String? _currentFocusedTodoItemId() {
    for (final entry in _todoMainFieldFocusNodes.entries) {
      if (entry.value.hasFocus) {
        return entry.key;
      }
    }
    for (final entry in _todoExtraFieldFocusNodes.entries) {
      if (entry.value.hasFocus) {
        return entry.key.split(':').first;
      }
    }
    return null;
  }

  void _undoTodoChange() {
    if (_undoStack.isEmpty) {
      return;
    }
    _redoStack.add(_snapshotTodoItems());
    _restoreTodoSnapshot(_undoStack.removeLast());
  }

  void _redoTodoChange() {
    if (_redoStack.isEmpty) {
      return;
    }
    _undoStack.add(_snapshotTodoItems());
    _restoreTodoSnapshot(_redoStack.removeLast());
  }

  KeyEventResult _handleTodoKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }
    if (_shouldDeferToTodoTextUndo(event)) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      _undoTodoChange();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyY) {
      _redoTodoChange();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleTodoItemKeyEvent(
    FocusNode node,
    PaperItem item,
    KeyEvent event,
  ) {
    final textShortcutResult = _handleFocusedTodoTextShortcut(node, event);
    if (textShortcutResult != null) {
      return textShortcutResult;
    }
    if (_shouldDeferToTodoTextUndo(event)) {
      return KeyEventResult.ignored;
    }
    final editorShortcutResult = _handleTodoKeyEvent(node, event);
    if (editorShortcutResult == KeyEventResult.handled) {
      return editorShortcutResult;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        event is KeyUpEvent) {
      _suppressTodoBackspaceUntilKeyUp = false;
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter &&
        _noKeyboardModifiersPressed) {
      _insertItemAfter(item);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_suppressTodoBackspaceUntilKeyUp) {
        return KeyEventResult.handled;
      }
      if (_deleteBlankTodoItemFromKeyboard(item)) {
        _suppressTodoBackspaceUntilKeyUp = true;
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  bool _shouldDeferToTodoTextUndo(KeyEvent event) {
    if (event is! KeyDownEvent || !HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      return _focusedTodoTextUndoStack.isNotEmpty ||
          _focusedTodoTextHasUncommittedEdit;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyY) {
      return _focusedTodoTextRedoStack.isNotEmpty;
    }
    return false;
  }

  KeyEventResult? _handleFocusedTodoTextShortcut(
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent || !HardwareKeyboard.instance.isControlPressed) {
      return null;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (_focusedTodoTextUndoStack.isEmpty) {
        return null;
      }
      _applyFocusedTodoTextHistory(
        node,
        source: _focusedTodoTextUndoStack,
        target: _focusedTodoTextRedoStack,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyY) {
      if (_focusedTodoTextRedoStack.isEmpty) {
        return null;
      }
      _applyFocusedTodoTextHistory(
        node,
        source: _focusedTodoTextRedoStack,
        target: _focusedTodoTextUndoStack,
      );
      return KeyEventResult.handled;
    }
    return null;
  }

  void _applyFocusedTodoTextHistory(
    FocusNode node, {
    required List<String> source,
    required List<String> target,
  }) {
    final itemId = _activeOriginalTodoItemId;
    final columnIndex = _activeOriginalTodoColumnIndex;
    if (itemId == null || source.isEmpty) {
      return;
    }
    final item = _todoItemById(itemId);
    if (item == null || !_isTodoColumnFocused(itemId, columnIndex)) {
      return;
    }

    final currentText = _todoColumnText(item, columnIndex) ?? '';
    final nextText = source.removeLast();
    if (currentText != nextText) {
      target.add(currentText);
    }
    _applyingTodoTextHistory = true;
    try {
      setState(() => _setTodoColumnText(item, columnIndex, nextText));
      final editable = _editableTextStateFor(node.context);
      if (editable != null) {
        final previousValue = editable.textEditingValue;
        final offset = previousValue.selection.extentOffset
            .clamp(0, nextText.length)
            .toInt();
        editable.userUpdateTextEditingValue(
          previousValue.copyWith(
            text: nextText,
            selection: TextSelection.collapsed(offset: offset),
            composing: TextRange.empty,
          ),
          SelectionChangedCause.keyboard,
        );
      }
    } finally {
      _applyingTodoTextHistory = false;
    }
    unawaited(widget.onChanged());
  }

  bool get _focusedTodoTextHasUncommittedEdit {
    final itemId = _activeOriginalTodoItemId;
    final columnIndex = _activeOriginalTodoColumnIndex;
    final originalText = _activeOriginalTodoText;
    if (itemId == null || originalText == null) {
      return false;
    }
    if (!_isTodoColumnFocused(itemId, columnIndex)) {
      return false;
    }
    final item = _todoItemById(itemId);
    return item != null && _todoColumnText(item, columnIndex) != originalText;
  }

  bool _isTodoColumnFocused(String itemId, int? columnIndex) {
    if (columnIndex == null) {
      return _todoMainFieldFocusNodes[itemId]?.hasFocus == true;
    }
    return _todoExtraFieldFocusNodes['$itemId:$columnIndex']?.hasFocus == true;
  }

  GlobalKey _todoColumnHitTestKey(PaperItem item, int columnIndex) {
    return _todoColumnHitTestKeys.putIfAbsent(
      '${item.id}:$columnIndex',
      () => GlobalKey(debugLabel: 'todo-column-${item.id}-$columnIndex'),
    );
  }

  bool get _noKeyboardModifiersPressed {
    final keyboard = HardwareKeyboard.instance;
    return !keyboard.isControlPressed &&
        !keyboard.isShiftPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed;
  }

  Widget _todoItemKeyboardScope(PaperItem item, Widget child) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) => _handleTodoItemKeyEvent(node, item, event),
      child: child,
    );
  }

  Widget _todoColumnFields(
    BuildContext context,
    PaperItem item,
    TextStyle? itemTextStyle,
    _TodoVisualSpec visualSpec,
  ) {
    final fields = [
      _mainColumnField(context, item, itemTextStyle, visualSpec),
      for (var index = 0; index < item.todoExtraColumns.length; index++)
        _extraColumnField(context, item, index, itemTextStyle, visualSpec),
    ];
    if (item.todoColumnCount <= 1) {
      return fields.first;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 640) {
            return Column(
              children: [
                for (var index = 0; index < fields.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: index == fields.length - 1 ? 0 : 6,
                    ),
                    child: fields[index],
                  ),
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: _columnFlex(item, 0),
                  child: fields.first,
                ),
                for (var index = 1; index < fields.length; index++) ...[
                  _todoColumnSplitter(
                    context: context,
                    item: item,
                    leftColumnIndex: index - 1,
                    availableWidth: constraints.maxWidth,
                  ),
                  Expanded(
                    flex: _columnFlex(item, index),
                    child: fields[index],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _todoColumnSplitter({
    required BuildContext context,
    required PaperItem item,
    required int leftColumnIndex,
    required double availableWidth,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        key: ValueKey(
          '${widget.paper.id}-${item.id}-column-splitter-${leftColumnIndex + 1}',
        ),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => _resizeTodoColumnPair(
          item: item,
          leftColumnIndex: leftColumnIndex,
          delta: details.delta.dx,
          availableWidth: availableWidth,
        ),
        child: SizedBox(
          width: _todoColumnSplitterWidth,
          child: Center(
            child: FractionallySizedBox(
              heightFactor: 0.72,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(1),
                ),
                child: const SizedBox(width: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _resizeTodoColumnPair({
    required PaperItem item,
    required int leftColumnIndex,
    required double delta,
    required double availableWidth,
  }) {
    if (delta.abs() < 0.1) {
      return;
    }
    item.normalize();
    final count = item.todoColumnCount;
    if (leftColumnIndex < 0 || leftColumnIndex >= count - 1) {
      return;
    }
    final widths = _normalizedTodoColumnWidths(item);
    final totalUnits = widths.fold<double>(0, (total, width) => total + width);
    final columnPixels = math.max(
      1.0,
      availableWidth - ((count - 1) * _todoColumnSplitterWidth),
    );
    final unitsPerPixel = totalUnits / columnPixels;
    final requestedDelta = delta * unitsPerPixel;
    final minDelta = _minTodoColumnWidth - widths[leftColumnIndex];
    final maxDelta = widths[leftColumnIndex + 1] - _minTodoColumnWidth;
    final appliedDelta = requestedDelta.clamp(minDelta, maxDelta).toDouble();
    if (appliedDelta.abs() < 0.001) {
      return;
    }

    widths[leftColumnIndex] =
        _roundTodoColumnWidth(widths[leftColumnIndex] + appliedDelta);
    widths[leftColumnIndex + 1] =
        _roundTodoColumnWidth(widths[leftColumnIndex + 1] - appliedDelta);
    setState(() => item.todoColumnWidths = widths);
    unawaited(widget.onChanged());
  }

  List<double> _normalizedTodoColumnWidths(PaperItem item) {
    if (item.todoColumnWidths.length == item.todoColumnCount) {
      return [
        for (final width in item.todoColumnWidths)
          width.isFinite && width >= _minTodoColumnWidth
              ? width.clamp(_minTodoColumnWidth, _maxTodoColumnWidth).toDouble()
              : _minTodoColumnWidth,
      ];
    }
    return List.filled(item.todoColumnCount, 1);
  }

  double _roundTodoColumnWidth(double value) {
    return (value.clamp(_minTodoColumnWidth, _maxTodoColumnWidth) * 1000)
            .roundToDouble() /
        1000;
  }

  Widget _mainColumnField(
    BuildContext context,
    PaperItem item,
    TextStyle? itemTextStyle,
    _TodoVisualSpec visualSpec,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return KeyedSubtree(
      key: ValueKey('${widget.paper.id}-${item.id}-text'),
      child: KeyedSubtree(
        key: _todoColumnHitTestKey(item, 0),
        child: _todoItemKeyboardScope(
          item,
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: visualSpec.rowMinHeight),
            child: TextFormField(
              key: ValueKey(
                '${widget.paper.id}-${item.id}-text-field-$_textFieldRevision',
              ),
              focusNode: _mainTodoFieldFocusNode(item),
              initialValue: item.text,
              keyboardType: TextInputType.multiline,
              minLines: 1,
              maxLines: null,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                border: item.todoColumnCount > 1
                    ? const OutlineInputBorder()
                    : InputBorder.none,
                enabledBorder: item.todoColumnCount > 1
                    ? const OutlineInputBorder()
                    : InputBorder.none,
                focusedBorder: item.todoColumnCount > 1
                    ? OutlineInputBorder(
                        borderSide: BorderSide(color: colorScheme.primary),
                      )
                    : InputBorder.none,
                filled: false,
                labelText: item.todoColumnCount > 1
                    ? strings.format(PaperTodoStringKeys.columnLabel, [1])
                    : null,
                hintText: strings.get(PaperTodoStringKeys.todoNewItemHint),
                isDense: true,
                contentPadding: visualSpec.mainContentPadding,
              ),
              style: itemTextStyle?.copyWith(
                color: item.done ? colorScheme.outline : colorScheme.onSurface,
                decoration: item.done ? TextDecoration.lineThrough : null,
              ),
              inputFormatters: [
                _TodoPasteTextInputFormatter(
                  onPaste: (lines, replacementText, previousValue) =>
                      _handleMultiLinePaste(
                    item,
                    replacementText,
                    previousColumnText: previousValue,
                    parsedLines: lines,
                  ),
                ),
                LengthLimitingTextInputFormatter(TodoPasteItems.maxLineLength),
              ],
              onChanged: (value) {
                if (_handleMultiLinePaste(item, value)) {
                  return;
                }
                _recordTodoTextInput(item, null, value);
                unawaited(widget.onChanged());
              },
              onFieldSubmitted: (_) => _insertItemAfter(item),
            ),
          ),
        ),
      ),
    );
  }

  bool _handleMultiLinePaste(
    PaperItem item,
    String value, {
    int? extraColumnIndex,
    String? previousColumnText,
    List<String>? parsedLines,
  }) {
    if (parsedLines == null && !value.contains('\n') && !value.contains('\r')) {
      return false;
    }
    final lines = parsedLines ?? TodoPasteItems.parseLines(value);
    if (lines.length <= 1) {
      return false;
    }
    final replacementText = parsedLines == null ? lines.first : value;
    if (extraColumnIndex != null) {
      item.normalize();
      if (extraColumnIndex < 0 ||
          extraColumnIndex >= item.todoExtraColumns.length) {
        return false;
      }
    }
    final snapshotText = _todoPasteSnapshotText(
      item,
      extraColumnIndex,
      previousColumnText,
      replacementText,
    );
    final currentColumnText = _todoColumnText(item, extraColumnIndex);
    if (previousColumnText == null && snapshotText == currentColumnText) {
      _pushTodoUndoSnapshot();
    } else {
      _setTodoColumnText(item, extraColumnIndex, snapshotText);
      _pushTodoUndoSnapshot(commitFocusedText: false);
    }
    late final List<PaperItem> newItems;
    setState(() {
      _setTodoColumnText(item, extraColumnIndex, replacementText);
      newItems = _addItemsAfter(item, lines.skip(1));
      widget.paper.normalize();
      _textFieldRevision++;
    });
    _markTodoTextEditCommitted(item, columnIndex: extraColumnIndex);
    _requestTodoItemFocus(newItems.isEmpty ? item.id : newItems.last.id);
    unawaited(widget.onChanged());
    return true;
  }

  String _todoPasteSnapshotText(
    PaperItem item,
    int? columnIndex,
    String? previousColumnText,
    String firstPastedLine,
  ) {
    if (previousColumnText == firstPastedLine &&
        _activeOriginalTodoItemId == item.id &&
        _activeOriginalTodoColumnIndex == columnIndex &&
        _activeOriginalTodoText != null) {
      return _activeOriginalTodoText!;
    }
    final currentText = _todoColumnText(item, columnIndex);
    if (previousColumnText == null &&
        currentText == firstPastedLine &&
        _activeOriginalTodoItemId == item.id &&
        _activeOriginalTodoColumnIndex == columnIndex &&
        _activeOriginalTodoText != null) {
      return _activeOriginalTodoText!;
    }
    if (previousColumnText == null) {
      return currentText ?? '';
    }
    return previousColumnText;
  }

  Widget _extraColumnField(
    BuildContext context,
    PaperItem item,
    int index,
    TextStyle? itemTextStyle,
    _TodoVisualSpec visualSpec,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return KeyedSubtree(
      key: _todoColumnHitTestKey(item, index + 1),
      child: _todoItemKeyboardScope(
        item,
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: visualSpec.rowMinHeight),
          child: TextFormField(
            key: ValueKey(
              '${widget.paper.id}-${item.id}-column-${index + 2}',
            ),
            focusNode: _extraTodoFieldFocusNode(item, index),
            initialValue: item.todoExtraColumns[index],
            keyboardType: TextInputType.multiline,
            minLines: 1,
            maxLines: null,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: strings.format(
                PaperTodoStringKeys.columnLabel,
                [index + 2],
              ),
              isDense: true,
              contentPadding: visualSpec.extraContentPadding,
            ),
            style: itemTextStyle?.copyWith(
              color: item.done ? colorScheme.outline : colorScheme.onSurface,
              decoration: item.done ? TextDecoration.lineThrough : null,
            ),
            inputFormatters: [
              _TodoPasteTextInputFormatter(
                onPaste: (lines, replacementText, previousValue) =>
                    _handleMultiLinePaste(
                  item,
                  replacementText,
                  extraColumnIndex: index,
                  previousColumnText: previousValue,
                  parsedLines: lines,
                ),
              ),
              LengthLimitingTextInputFormatter(TodoPasteItems.maxLineLength),
            ],
            onChanged: (value) {
              if (_handleMultiLinePaste(item, value, extraColumnIndex: index)) {
                return;
              }
              _recordTodoTextInput(item, index, value);
              unawaited(widget.onChanged());
            },
            onFieldSubmitted: (_) => _insertItemAfter(item),
          ),
        ),
      ),
    );
  }

  void _setTodoColumnText(
    PaperItem item,
    int? extraColumnIndex,
    String value,
  ) {
    if (extraColumnIndex == null) {
      item.text = value;
      return;
    }
    item.todoExtraColumns[extraColumnIndex] = value;
  }

  void _recordTodoTextInput(
    PaperItem item,
    int? columnIndex,
    String value,
  ) {
    final previousText = _todoColumnText(item, columnIndex) ?? '';
    if (!_applyingTodoTextHistory &&
        _activeOriginalTodoItemId == item.id &&
        _activeOriginalTodoColumnIndex == columnIndex &&
        previousText != value) {
      _focusedTodoTextUndoStack.add(previousText);
      if (_focusedTodoTextUndoStack.length > _maxTodoUndoDepth) {
        _focusedTodoTextUndoStack.removeAt(0);
      }
      _focusedTodoTextRedoStack.clear();
    }
    _setTodoColumnText(item, columnIndex, value);
  }

  void _clearFocusedTodoTextHistory() {
    _focusedTodoTextUndoStack.clear();
    _focusedTodoTextRedoStack.clear();
  }

  String? _todoColumnText(PaperItem item, int? extraColumnIndex) {
    if (extraColumnIndex == null) {
      return item.text;
    }
    if (extraColumnIndex < 0 ||
        extraColumnIndex >= item.todoExtraColumns.length) {
      return null;
    }
    return item.todoExtraColumns[extraColumnIndex];
  }

  int _columnFlex(PaperItem item, int index) {
    if (item.todoColumnWidths.length != item.todoColumnCount) {
      return 1;
    }
    final width = item.todoColumnWidths[index];
    if (width <= 0 || !width.isFinite) {
      return 1;
    }
    final normalizedWidth =
        width.clamp(_minTodoColumnWidth, _maxTodoColumnWidth).toDouble();
    return (normalizedWidth * 100).round().clamp(1, 800).toInt();
  }

  void _updateColumns(PaperItem item, String action) {
    _pushTodoUndoSnapshot();
    setState(() {
      if (action == _columnActionAdd &&
          item.todoColumnCount < TodoColumnLimits.maxCount) {
        item.todoColumnCount += 1;
        if (item.todoColumnWidths.isNotEmpty) {
          item.todoColumnWidths = [
            ...item.todoColumnWidths.take(item.todoColumnCount - 1),
            1,
          ];
        }
      } else if (action == _columnActionRemove && item.todoColumnCount > 1) {
        item.todoColumnCount -= 1;
        if (item.todoColumnWidths.isNotEmpty) {
          item.todoColumnWidths =
              item.todoColumnWidths.take(item.todoColumnCount).toList();
        }
      } else if (action.startsWith(_columnActionInsertBeforePrefix)) {
        final columnIndex = int.tryParse(
          action.substring(_columnActionInsertBeforePrefix.length),
        );
        if (columnIndex != null) {
          _insertTodoColumnBefore(item, columnIndex);
        }
      } else if (action.startsWith(_columnActionDeletePrefix)) {
        final columnIndex = int.tryParse(
          action.substring(_columnActionDeletePrefix.length),
        );
        if (columnIndex != null) {
          _deleteTodoColumn(item, columnIndex);
        }
      } else if (action == _columnActionEqualWidths &&
          item.todoColumnCount > 1) {
        item.todoColumnWidths = List.filled(item.todoColumnCount, 1);
      } else if (action == _columnActionWideFirst && item.todoColumnCount > 1) {
        item.todoColumnWidths = [
          2,
          ...List.filled(item.todoColumnCount - 1, 1),
        ];
      }
      item.normalize();
    });
    _markTodoTextEditCommitted(item);
    unawaited(widget.onChanged());
  }

  bool _canMoveTodoItem(PaperItem item, int delta) {
    final index = _todoItemIndex(item);
    if (index < 0) {
      return false;
    }
    final targetIndex = index + delta;
    return targetIndex >= 0 && targetIndex < widget.paper.items.length;
  }

  int _todoItemIndex(PaperItem item) {
    return widget.paper.items.indexWhere(
      (candidate) => candidate.id == item.id,
    );
  }

  void _moveTodoItem(PaperItem item, int delta) {
    final index = _todoItemIndex(item);
    final targetIndex = index + delta;
    if (index < 0 ||
        targetIndex < 0 ||
        targetIndex >= widget.paper.items.length) {
      return;
    }

    _pushTodoUndoSnapshot();
    setState(() {
      final targetItem = widget.paper.items[targetIndex];
      widget.paper.items[targetIndex] = item;
      widget.paper.items[index] = targetItem;
      widget.paper.normalize();
    });
    _requestTodoItemFocus(item.id);
    unawaited(widget.onChanged());
  }

  bool _canAcceptTodoItemDrop(PaperItem dragged, PaperItem target) {
    return dragged.id != target.id &&
        _todoItemIndex(dragged) >= 0 &&
        _todoItemIndex(target) >= 0;
  }

  void _reorderTodoItemToTarget(
    PaperItem dragged,
    PaperItem target, {
    required bool after,
  }) {
    final oldIndex = _todoItemIndex(dragged);
    final targetIndex = _todoItemIndex(target);
    if (oldIndex < 0 ||
        targetIndex < 0 ||
        oldIndex >= widget.paper.items.length ||
        targetIndex >= widget.paper.items.length ||
        oldIndex == targetIndex) {
      return;
    }
    var insertIndex = targetIndex + (after ? 1 : 0);
    if (oldIndex < insertIndex) {
      insertIndex--;
    }
    if (insertIndex == oldIndex) {
      return;
    }

    _pushTodoUndoSnapshot();
    late final PaperItem movedItem;
    setState(() {
      movedItem = widget.paper.items.removeAt(oldIndex);
      widget.paper.items.insert(insertIndex, movedItem);
      widget.paper.normalize();
    });
    _requestTodoItemFocus(movedItem.id);
    unawaited(widget.onChanged());
  }

  void _setTodoItemDragging(bool value) {
    if (!mounted || _isDraggingTodoItem == value) {
      return;
    }
    setState(() => _isDraggingTodoItem = value);
  }

  void _insertTodoColumnBefore(PaperItem item, int columnIndex) {
    item.normalize();
    final count = item.todoColumnCount;
    if (count >= TodoColumnLimits.maxCount) {
      return;
    }

    final insertIndex = columnIndex.clamp(0, count).toInt();
    if (insertIndex == 0) {
      item.todoExtraColumns.insert(0, item.text);
      item.text = '';
    } else {
      item.todoExtraColumns.insert(insertIndex - 1, '');
    }
    item.todoColumnCount = count + 1;
    item.todoColumnWidths.insert(insertIndex, 1);
  }

  void _deleteTodoColumn(PaperItem item, int columnIndex) {
    item.normalize();
    final count = item.todoColumnCount;
    if (count <= TodoColumnLimits.minCount) {
      return;
    }

    final deleteIndex = columnIndex.clamp(0, count - 1).toInt();
    if (deleteIndex == 0) {
      if (item.todoExtraColumns.isEmpty) {
        item.text = '';
      } else {
        item.text = item.todoExtraColumns.first;
        item.todoExtraColumns.removeAt(0);
      }
    } else if (deleteIndex - 1 < item.todoExtraColumns.length) {
      item.todoExtraColumns.removeAt(deleteIndex - 1);
    }
    if (deleteIndex < item.todoColumnWidths.length) {
      item.todoColumnWidths.removeAt(deleteIndex);
    }
    item.todoColumnCount = count - 1;
  }

  void _addItem() {
    final lastItem =
        widget.paper.items.isEmpty ? null : widget.paper.items.last;
    _insertItemAfter(lastItem);
  }

  void _insertItemAfter(PaperItem? item, {String text = ''}) {
    _pushTodoUndoSnapshot();
    final insertIndex = item == null
        ? widget.paper.items.length
        : widget.paper.items.indexWhere(
              (candidate) => candidate.id == item.id,
            ) +
            1;
    final normalizedInsertIndex = insertIndex <= 0
        ? widget.paper.items.length
        : insertIndex.clamp(0, widget.paper.items.length).toInt();
    final newItem = _newTodoItem(text: text);
    setState(() {
      widget.paper.items.insert(normalizedInsertIndex, newItem);
      widget.paper.normalize();
    });
    _requestTodoItemFocus(newItem.id);
    unawaited(widget.onChanged());
  }

  List<PaperItem> _addItemsAfter(PaperItem item, Iterable<String> lines) {
    final insertIndex = widget.paper.items.indexWhere(
      (candidate) => candidate.id == item.id,
    );
    if (insertIndex < 0) {
      return const [];
    }
    final idSeed = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    var lineIndex = 0;
    final newItems = [
      for (final line in lines)
        PaperItem(
          id: '$idSeed-${lineIndex++}',
          text: line,
        ),
    ];
    widget.paper.items.insertAll(insertIndex + 1, newItems);
    return newItems;
  }

  PaperItem _newTodoItem({String text = ''}) {
    return PaperItem(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
      text: text,
    );
  }

  bool _deleteBlankTodoItemFromKeyboard(PaperItem item) {
    final removedIndex = widget.paper.items.indexWhere(
      (candidate) => candidate.id == item.id,
    );
    if (removedIndex < 0 ||
        widget.paper.items.length <= 1 ||
        !_allTodoTextColumnsBlank(item)) {
      return false;
    }

    final previousItem =
        removedIndex > 0 ? widget.paper.items[removedIndex - 1] : null;
    final nextItem = removedIndex + 1 < widget.paper.items.length
        ? widget.paper.items[removedIndex + 1]
        : null;
    final focusTargetId = previousItem?.id ?? nextItem?.id;

    _pushTodoUndoSnapshot();
    _unfocusTodoItem(item);
    setState(() {
      widget.paper.items.removeAt(removedIndex);
      if (widget.paper.items.isEmpty) {
        widget.paper.items.add(_newTodoItem());
      }
      widget.paper.normalize();
    });
    widget.onItemDeleted(widget.paper, item);
    _requestTodoItemFocus(
      focusTargetId ?? widget.paper.items.first.id,
      placement: previousItem == null
          ? _TodoFocusPlacement.start
          : _TodoFocusPlacement.end,
    );
    unawaited(widget.onChanged());
    return true;
  }

  bool _allTodoTextColumnsBlank(PaperItem item) {
    return item.text.trim().isEmpty &&
        item.todoExtraColumns.every((column) => column.trim().isEmpty);
  }

  bool _isBlankTodoItem(PaperItem item) {
    return _allTodoTextColumnsBlank(item) &&
        (item.dueAtLocal?.trim().isEmpty ?? true) &&
        item.reminderIntervalValue == null &&
        (item.linkedNoteId?.trim().isEmpty ?? true);
  }

  bool _hasDueDate(PaperItem item) {
    return item.dueAtLocal?.trim().isNotEmpty ?? false;
  }

  bool _hasReminderInterval(PaperItem item) {
    return item.reminderIntervalValue != null;
  }

  bool get _hasDoneTodoItems {
    return widget.paper.items.any((item) => item.done);
  }

  void _clearDoneItems() {
    final completedItems =
        widget.paper.items.where((item) => item.done).toList();
    if (completedItems.isEmpty) {
      return;
    }
    final focusedId = _currentFocusedTodoItemId();
    final completedIds = completedItems.map((item) => item.id).toSet();

    _pushTodoUndoSnapshot();
    for (final item in completedItems) {
      _unfocusTodoItem(item);
    }
    String? focusTargetId;
    setState(() {
      final remainingItems = widget.paper.items
          .where((item) => !completedIds.contains(item.id))
          .toList();
      if (remainingItems.isEmpty) {
        remainingItems.add(_newTodoItem());
      }
      widget.paper.items = remainingItems;
      widget.paper.normalize();
      if (widget.paper.items.any((item) => item.id == focusedId)) {
        focusTargetId = focusedId;
      } else {
        for (final item in widget.paper.items) {
          if (!_isBlankTodoItem(item)) {
            focusTargetId = item.id;
            break;
          }
        }
        focusTargetId ??=
            widget.paper.items.isEmpty ? null : widget.paper.items.first.id;
      }
    });
    for (final item in completedItems) {
      widget.onItemDeleted(widget.paper, item);
    }
    _requestTodoItemFocus(focusTargetId);
    unawaited(widget.onChanged());
  }

  void _deleteItem(BuildContext context, PaperItem item) {
    final removedIndex = widget.paper.items.indexWhere(
      (candidate) => candidate.id == item.id,
    );
    if (removedIndex < 0) {
      return;
    }
    final previousItem =
        removedIndex > 0 ? widget.paper.items[removedIndex - 1] : null;
    final nextItem = removedIndex + 1 < widget.paper.items.length
        ? widget.paper.items[removedIndex + 1]
        : null;
    var focusTargetId = previousItem?.id ?? nextItem?.id;
    String? fallbackItemId;

    _pushTodoUndoSnapshot();
    _unfocusTodoItem(item);
    setState(() {
      widget.paper.items.removeAt(removedIndex);
      if (widget.paper.items.isEmpty) {
        final replacement = _newTodoItem();
        widget.paper.items.add(replacement);
        focusTargetId = replacement.id;
        fallbackItemId = replacement.id;
      }
      widget.paper.normalize();
    });
    widget.onItemDeleted(widget.paper, item);
    _requestTodoItemFocus(focusTargetId);
    unawaited(widget.onChanged());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.format(
            PaperTodoStringKeys.todoItemDeleted,
            [_displayItemText(item)],
          ),
        ),
        action: SnackBarAction(
          label: strings.get(PaperTodoStringKeys.actionUndo),
          onPressed: () {
            setState(() {
              if (fallbackItemId != null) {
                widget.paper.items.removeWhere(
                  (candidate) => candidate.id == fallbackItemId,
                );
              }
              final targetIndex = removedIndex
                  .clamp(
                    0,
                    widget.paper.items.length,
                  )
                  .toInt();
              widget.paper.items.insert(targetIndex, item);
              widget.paper.normalize();
            });
            widget.onItemRestored(widget.paper, item);
            unawaited(widget.onChanged());
          },
        ),
      ),
    );
  }

  Future<void> _pickDueDate(BuildContext context, PaperItem item) async {
    final now = DateTime.now();
    final initialDate = parsePaperTodoDueAtLocal(item.dueAtLocal) ??
        now.add(const Duration(hours: 1));
    final result = await showDialog<_TodoDueSelection>(
      context: context,
      builder: (context) => _TodoDueSelectionDialog(initialDate: initialDate),
    );
    if (result == null) {
      return;
    }
    _pushTodoUndoSnapshot();
    setState(() {
      item.dueAtLocal = result.clear
          ? null
          : _formatDueAtLocalValue(result.dueAt ?? initialDate);
    });
    widget.onReminderReset(item);
    unawaited(widget.onChanged());
  }

  void _clearDueDate(PaperItem item) {
    if (!_hasDueDate(item)) {
      return;
    }
    _pushTodoUndoSnapshot();
    setState(() => item.dueAtLocal = null);
    widget.onReminderReset(item);
    unawaited(widget.onChanged());
  }

  Future<void> _pickReminderInterval(
    BuildContext context,
    PaperItem item,
  ) async {
    final result = await showDialog<_ReminderIntervalSelection>(
      context: context,
      builder: (context) => _ReminderIntervalDialog(
        initialValue:
            item.reminderIntervalValue ?? widget.defaultReminderIntervalValue,
        initialUnit:
            item.reminderIntervalUnit ?? widget.defaultReminderIntervalUnit,
      ),
    );
    if (result == null) {
      return;
    }
    _pushTodoUndoSnapshot();
    setState(() {
      if (result.clear) {
        item.reminderIntervalValue = null;
        item.reminderIntervalUnit = null;
      } else {
        item.reminderIntervalValue = result.value;
        item.reminderIntervalUnit = result.unit;
      }
    });
    widget.onReminderReset(item);
    unawaited(widget.onChanged());
  }

  void _clearReminderInterval(PaperItem item) {
    if (!_hasReminderInterval(item)) {
      return;
    }
    _pushTodoUndoSnapshot();
    setState(() {
      item.reminderIntervalValue = null;
      item.reminderIntervalUnit = null;
    });
    widget.onReminderReset(item);
    unawaited(widget.onChanged());
  }

  void _openLinkedNote(PaperItem item) {
    final noteId = item.linkedNoteId;
    if (noteId == null) {
      return;
    }
    final linkedNote = _notePaperById(noteId);
    if (linkedNote == null) {
      return;
    }
    unawaited(widget.onOpenLinkedNote(linkedNote, widget.paper));
  }

  void _linkNote(PaperItem item, String noteId) {
    if (!widget.enableTodoNoteLinks ||
        _notePaperById(noteId) == null ||
        item.linkedNoteId == noteId) {
      return;
    }
    final focusTargetId = _currentFocusedTodoItemId() ?? item.id;
    _pushTodoUndoSnapshot();
    setState(() => item.linkedNoteId = noteId);
    _requestTodoItemFocus(focusTargetId);
    unawaited(widget.onChanged());
  }

  void _clearLinkedNote(PaperItem item) {
    if (item.linkedNoteId == null || item.linkedNoteId!.trim().isEmpty) {
      return;
    }
    final focusTargetId = _currentFocusedTodoItemId() ?? item.id;
    _pushTodoUndoSnapshot();
    setState(() => item.linkedNoteId = null);
    _requestTodoItemFocus(focusTargetId);
    unawaited(widget.onChanged());
  }

  PaperData? _notePaperById(String noteId) {
    for (final note in widget.notePapers) {
      if (note.id == noteId) {
        return note;
      }
    }
    return null;
  }

  PaperData? _linkedNoteFor(PaperItem item) {
    final noteId = item.linkedNoteId;
    if (noteId == null) {
      return null;
    }
    return _notePaperById(noteId);
  }

  InputChip _linkedNoteChip(
    PaperData linkedNote,
    PaperItem item,
    _TodoVisualSpec visualSpec,
  ) {
    final scriptSpec = widget.runLinkedScriptCapsulesOnClick
        ? ScriptCapsuleSpec.tryParse(linkedNote.content)
        : null;
    final isScriptCapsule = scriptSpec != null;
    return InputChip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(
        isScriptCapsule ? Icons.bolt_outlined : Icons.notes_outlined,
        size: visualSpec.chipIconSize,
      ),
      labelStyle: _todoChipTextStyle(visualSpec),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      label: Text(
        isScriptCapsule
            ? _scriptChipLabel(linkedNote)
            : _noteChipLabel(linkedNote),
      ),
      tooltip: _tooltipLabel(
        widget.enableToolTips,
        isScriptCapsule
            ? strings.get(PaperTodoStringKeys.actionRunLinkedScriptCapsule)
            : strings.get(PaperTodoStringKeys.actionOpenLinkedNote),
      ),
      onPressed: () {
        if (scriptSpec != null) {
          unawaited(widget.onRunScriptCapsule(scriptSpec));
          return;
        }
        unawaited(widget.onOpenLinkedNote(linkedNote, widget.paper));
      },
      onDeleted: () => _clearLinkedNote(item),
      deleteIcon: Icon(Icons.close_outlined, size: visualSpec.chipIconSize),
      deleteButtonTooltipMessage: _tooltipLabel(
        widget.enableToolTips,
        strings.get(PaperTodoStringKeys.actionUnlinkNote),
      ),
    );
  }

  TextStyle? _todoChipTextStyle(_TodoVisualSpec visualSpec) {
    return Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: visualSpec.chipFontSize,
          fontWeight: FontWeight.w600,
        );
  }

  String _noteChipLabel(PaperData note) {
    if (!widget.showLinkedNoteName) {
      return strings.get(PaperTodoStringKeys.labelNote);
    }
    final title = widget.allowLongLinkedNoteTitles
        ? _displayPaperTitle(note)
        : _shortenTitle(_displayPaperTitle(note), widget.maxTitleLength);
    return strings.format(PaperTodoStringKeys.labelNoteTitle, [title]);
  }

  String _scriptChipLabel(PaperData note) {
    if (!widget.showLinkedNoteName) {
      return strings.get(PaperTodoStringKeys.labelScript);
    }
    final title = widget.allowLongLinkedNoteTitles
        ? _displayPaperTitle(note)
        : _shortenTitle(_displayPaperTitle(note), widget.maxTitleLength);
    return strings.format(PaperTodoStringKeys.actionRunPaper, [title]);
  }

  String _displayPaperTitle(PaperData paper) {
    final title = PaperTitles.cleanCustomTitle(paper.title);
    if (title.isNotEmpty) {
      return title;
    }
    return PaperTitles.defaultTitle(paper.type, _titleNumberForPaper(paper));
  }

  int _titleNumberForPaper(PaperData paper) {
    final normalizedType = PaperTypes.normalize(paper.type);
    var number = 1;
    for (final existing in widget.notePapers) {
      if (PaperTypes.normalize(existing.type) != normalizedType) {
        continue;
      }
      if (existing.id == paper.id) {
        return number;
      }
      number++;
    }
    return math.max(1, number);
  }

  String _displayItemText(PaperItem item) {
    final text = item.text.trim();
    return text.isEmpty
        ? strings.get(PaperTodoStringKeys.todoItemFallback)
        : text;
  }

  String _formatAbsoluteDueDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final time = _formatDueTime(date);
    final yearDisplayMode = TodoDueYearDisplayModes.normalize(
      widget.dueYearDisplayMode,
    );
    return switch (yearDisplayMode) {
      TodoDueYearDisplayModes.short =>
        '${(date.year % 100).toString().padLeft(2, '0')}-$month-$day $time',
      TodoDueYearDisplayModes.full => '${date.year}-$month-$day $time',
      _ => _formatCompactAbsoluteDueDate(date, time, month, day),
    };
  }

  String _formatCompactAbsoluteDueDate(
    DateTime date,
    String time,
    String month,
    String day,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(date.year, date.month, date.day);
    if (dueDay == today) {
      return time;
    }
    if (dueDay == today.add(const Duration(days: 1))) {
      return strings.format(PaperTodoStringKeys.dueTomorrow, [time]);
    }
    return '$month-$day $time';
  }

  String _formatDueTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDueAtLocalValue(DateTime date) {
    return formatPaperTodoDueAtLocal(date);
  }

  String? _formatReminderInterval(PaperItem item) {
    final value = item.reminderIntervalValue;
    if (value == null || value < 1) {
      return null;
    }
    final unit = TodoReminderIntervalUnits.normalize(item.reminderIntervalUnit);
    final key = unit == TodoReminderIntervalUnits.hours
        ? PaperTodoStringKeys.reminderEveryHours
        : PaperTodoStringKeys.reminderEveryMinutes;
    return strings.format(key, [value]);
  }

  String _formatRelativeDueDate(DateTime date) {
    final now = DateTime.now();
    final difference = date.difference(now);
    final isPast = difference.isNegative;
    final absoluteMicroseconds =
        isPast ? -difference.inMicroseconds : difference.inMicroseconds;
    final totalMinutes = (absoluteMicroseconds / Duration.microsecondsPerMinute)
        .ceil()
        .clamp(1, 1 << 31)
        .toInt();
    final days = totalMinutes ~/ (24 * 60);
    final hours = (totalMinutes % (24 * 60)) ~/ 60;
    final minutes = totalMinutes % 60;
    final parts = <String>[
      if (days > 0) '${days}d',
      if (hours > 0) '${hours}h',
      if (minutes > 0 || (days == 0 && hours == 0))
        '${minutes <= 0 ? 1 : minutes}m',
    ];
    final text = parts.join();
    if (isPast) {
      return strings.format(PaperTodoStringKeys.relativeDueOverdue, [text]);
    }
    return strings.format(PaperTodoStringKeys.relativeDueFuture, [text]);
  }
}

class _TodoDueSelection {
  const _TodoDueSelection.set(this.dueAt) : clear = false;

  const _TodoDueSelection.clear()
      : dueAt = null,
        clear = true;

  final DateTime? dueAt;
  final bool clear;
}

class _TodoDueSelectionDialog extends StatefulWidget {
  const _TodoDueSelectionDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_TodoDueSelectionDialog> createState() =>
      _TodoDueSelectionDialogState();
}

class _TodoDueSelectionDialogState extends State<_TodoDueSelectionDialog> {
  late DateTime _selectedDate;
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _hour = widget.initialDate.hour;
    _minute = widget.initialDate.minute;
  }

  @override
  Widget build(BuildContext context) {
    final strings = PaperTodoStringsScope.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _handleDialogKeyEvent,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): _save,
          const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        },
        child: AlertDialog(
          title: Text(strings.get(PaperTodoStringKeys.dialogDueDate)),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 330,
                    child: CalendarDatePicker(
                      initialDate: _selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      onDateChanged: (value) {
                        setState(() {
                          _selectedDate = DateTime(
                            value.year,
                            value.month,
                            value.day,
                          );
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: const ValueKey('todo-due-hour'),
                          initialValue: _hour,
                          decoration: InputDecoration(
                            labelText: strings.get(PaperTodoStringKeys.hour),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (var value = 0; value < 24; value++)
                              DropdownMenuItem(
                                value: value,
                                child: Text(value.toString().padLeft(2, '0')),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _hour = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: const ValueKey('todo-due-minute'),
                          initialValue: _minute,
                          decoration: InputDecoration(
                            labelText: strings.get(PaperTodoStringKeys.minute),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (var value = 0; value < 60; value++)
                              DropdownMenuItem(
                                value: value,
                                child: Text(value.toString().padLeft(2, '0')),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _minute = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _clear,
              child: Text(strings.get(PaperTodoStringKeys.actionClear)),
            ),
            TextButton(
              onPressed: _cancel,
              child: Text(strings.get(PaperTodoStringKeys.actionCancel)),
            ),
            FilledButton(
              onPressed: _save,
              child: Text(strings.get(PaperTodoStringKeys.actionSave)),
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleDialogKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _save();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _clear() {
    Navigator.of(context).pop(const _TodoDueSelection.clear());
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  void _save() {
    Navigator.of(context).pop(
      _TodoDueSelection.set(
        DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          _hour,
          _minute,
        ),
      ),
    );
  }
}

class _TodoPasteTextInputFormatter extends TextInputFormatter {
  const _TodoPasteTextInputFormatter({required this.onPaste});

  final void Function(
    List<String> lines,
    String replacementText,
    String previousText,
  ) onPaste;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final edit = _TodoTextEdit.betweenValues(oldValue, newValue);
    final inserted = newValue.text.substring(edit.start, edit.newEnd);
    if (!inserted.contains('\n') && !inserted.contains('\r')) {
      return newValue;
    }
    final lines = TodoPasteItems.parseLines(inserted);
    if (lines.length <= 1) {
      final replacement = lines.isEmpty ? '' : lines.single;
      final text = oldValue.text.replaceRange(
        edit.start,
        edit.oldEnd,
        replacement,
      );
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(
          offset: edit.start + replacement.length,
        ),
      );
    }
    final replacementText = oldValue.text.replaceRange(
      edit.start,
      edit.oldEnd,
      lines.first,
    );
    scheduleMicrotask(() => onPaste(lines, replacementText, oldValue.text));
    return oldValue;
  }
}

class _TodoTextEdit {
  const _TodoTextEdit({
    required this.start,
    required this.oldEnd,
    required this.newEnd,
  });

  factory _TodoTextEdit.betweenValues(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selection = oldValue.selection;
    if (selection.isValid) {
      final oldText = oldValue.text;
      final newText = newValue.text;
      final start = selection.start.clamp(0, oldText.length).toInt();
      final oldEnd = selection.end.clamp(start, oldText.length).toInt();
      final suffixLength = oldText.length - oldEnd;
      final newEnd = newText.length - suffixLength;
      if (newEnd >= start &&
          newText.startsWith(oldText.substring(0, start)) &&
          newText.endsWith(oldText.substring(oldEnd))) {
        return _TodoTextEdit(start: start, oldEnd: oldEnd, newEnd: newEnd);
      }
    }
    return _TodoTextEdit.between(oldValue.text, newValue.text);
  }

  factory _TodoTextEdit.between(String oldText, String newText) {
    var start = 0;
    while (start < oldText.length &&
        start < newText.length &&
        oldText[start] == newText[start]) {
      start++;
    }

    var oldEnd = oldText.length;
    var newEnd = newText.length;
    while (oldEnd > start &&
        newEnd > start &&
        oldText[oldEnd - 1] == newText[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }

    return _TodoTextEdit(start: start, oldEnd: oldEnd, newEnd: newEnd);
  }

  final int start;
  final int oldEnd;
  final int newEnd;
}

class _MarkdownPasteTextInputFormatter extends TextInputFormatter {
  const _MarkdownPasteTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return MarkdownPasteText.formatEditUpdate(oldValue, newValue);
  }
}

class _MarkdownListContinuationTextInputFormatter extends TextInputFormatter {
  const _MarkdownListContinuationTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return MarkdownListContinuation.formatEnter(oldValue, newValue);
  }
}

class _PaperTitleTextInputFormatter extends TextInputFormatter {
  const _PaperTitleTextInputFormatter({required this.maxLength});

  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = _cleanEditingTitle(newValue.text);
    if (cleaned == newValue.text) {
      return newValue;
    }

    final selection = newValue.selection;
    return newValue.copyWith(
      text: cleaned,
      selection: selection.copyWith(
        baseOffset: _cleanedOffset(newValue.text, selection.baseOffset),
        extentOffset: _cleanedOffset(newValue.text, selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }

  String _cleanEditingTitle(String value) {
    final withoutControls = value.runes
        .where((rune) => !_isControlRune(rune))
        .map(String.fromCharCode)
        .join();
    return PaperTitles.shorten(withoutControls, maxLength);
  }

  int _cleanedOffset(String text, int offset) {
    if (offset < 0) {
      return -1;
    }
    final safeOffset = offset.clamp(0, text.length).toInt();
    return _cleanEditingTitle(text.substring(0, safeOffset)).length;
  }

  bool _isControlRune(int rune) {
    return rune < 0x20 || (rune >= 0x7F && rune <= 0x9F);
  }
}

class _TodoVisualSpec {
  const _TodoVisualSpec({
    required this.textScale,
    required this.checkboxScale,
    required this.iconSize,
    required this.chipIconSize,
    required this.chipFontSize,
    required this.controlExtent,
    required this.itemGap,
    required this.rowMinHeight,
    required this.textVerticalPadding,
  });

  final double textScale;
  final double checkboxScale;
  final double iconSize;
  final double chipIconSize;
  final double chipFontSize;
  final double controlExtent;
  final double itemGap;
  final double rowMinHeight;
  final double textVerticalPadding;

  double get appendGlyphSize => switch (controlExtent) {
        28 => 13,
        30 => 14,
        32 => 15,
        36 => 16.5,
        _ => math.max(13, controlExtent - 16),
      };

  EdgeInsets get mainContentPadding =>
      EdgeInsets.symmetric(horizontal: 2, vertical: textVerticalPadding);

  EdgeInsets get extraContentPadding =>
      EdgeInsets.fromLTRB(8, textVerticalPadding, 4, textVerticalPadding);

  static _TodoVisualSpec from(String value) {
    return switch (TodoVisualSizes.normalize(value)) {
      TodoVisualSizes.small => const _TodoVisualSpec(
          textScale: 12 / 14,
          checkboxScale: 0.86,
          iconSize: 21,
          chipIconSize: 11.5,
          chipFontSize: 9.5,
          controlExtent: 28,
          itemGap: 4,
          rowMinHeight: 23,
          textVerticalPadding: 2.5,
        ),
      TodoVisualSizes.large => const _TodoVisualSpec(
          textScale: 1,
          checkboxScale: 1,
          iconSize: 24,
          chipIconSize: 13.5,
          chipFontSize: 11.5,
          controlExtent: 32,
          itemGap: 8,
          rowMinHeight: 26,
          textVerticalPadding: 3.5,
        ),
      TodoVisualSizes.extraLarge => const _TodoVisualSpec(
          textScale: 15.5 / 14,
          checkboxScale: 1.08,
          iconSize: 27,
          chipIconSize: 15,
          chipFontSize: 13,
          controlExtent: 36,
          itemGap: 10,
          rowMinHeight: 30,
          textVerticalPadding: 4.5,
        ),
      _ => const _TodoVisualSpec(
          textScale: 13 / 14,
          checkboxScale: 0.94,
          iconSize: 22,
          chipIconSize: 12.5,
          chipFontSize: 10.5,
          controlExtent: 30,
          itemGap: 6,
          rowMinHeight: 24,
          textVerticalPadding: 3,
        ),
    };
  }
}
