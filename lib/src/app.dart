import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;

import 'app_controller.dart';
import 'core/logging/usage_log.dart';
import 'core/model/app_state.dart';
import 'core/model/external_uri_targets.dart';
import 'core/model/markdown_formatting.dart';
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
import 'core/model/webdav_presets.dart';
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
import 'ui/papertodo_markdown_source.dart';
import 'ui/papertodo_theme.dart';
import 'ui/papertodo_motion.dart';
import 'ui/runtime_custom_font.dart';
import 'ui/sync_settings_dialog.dart';

const _paperWindowMethodChannel = MethodChannel('repapertodo/paper_window');

const _externalMarkdownExportRetention = Duration(days: 7);
const _maxExternalMarkdownPaperIdFileNameLength = 96;
const _maxTodoReminderDetailLines = 4;
const _todoReminderLeadTime = Duration(minutes: 10);
const _todoReminderGraceTime = Duration(minutes: 2);
const _windowsPaperTransparencyKey = Color(0xFF010203);
const _paperWindowChromeMargin = 8.0;
const _dengXianFontFamily = 'DengXian';
const _dengXianFontFamilyFallback = [
  'Segoe UI',
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'Microsoft JhengHei UI',
  'Microsoft JhengHei',
  'Yu Gothic UI',
  'Malgun Gothic',
  'Meiryo',
  'Segoe UI Symbol',
  'Segoe UI Emoji',
];
// Flutter's DengXian shaping keeps fractional CJK advances that WPF's
// Display text mode rounds away. Preserve the source line box while matching
// the reference advance used by wrapped Todo text.
const _paperTodoDengXianAdvanceScale = 12.5 / 13;
const _defaultContentFontFamily = 'Microsoft YaHei UI';
const _defaultContentFontFamilyFallback = [
  'Segoe UI',
  'Microsoft YaHei',
  'Segoe UI Symbol',
  'Segoe UI Emoji',
];
const _paperTodoCodeFontFamily = 'Cascadia Mono';
const _paperTodoCodeFontFamilyFallback = [
  'Consolas',
  'Microsoft YaHei UI',
  'Segoe UI Symbol',
  'Segoe UI Emoji',
];

Color _paperTodoBlend(Color background, Color foreground, int alpha) {
  final clampedAlpha = alpha.clamp(0, 255);
  final inverse = 255 - clampedAlpha;
  int channel(double value) => value.round();
  int premultiply(int value, int opacity) => ((value * opacity) + 127) ~/ 255;
  int mix(int base, int overlay) =>
      premultiply(base, inverse) + premultiply(overlay, clampedAlpha);
  return Color.fromARGB(
    255,
    mix(channel(background.r * 255), channel(foreground.r * 255)),
    mix(channel(background.g * 255), channel(foreground.g * 255)),
    mix(channel(background.b * 255), channel(foreground.b * 255)),
  );
}

typedef AndroidBackgroundSyncConfigurator = Future<void> Function({
  required SyncSettings sync,
  required String stateFilePath,
});

typedef PaperWindowActionSender = Future<void> Function(String kind,
    {String value});

typedef PaperWindowReminderPresenter = Future<void> Function(
    Map<String, Object?> reminder);

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
        runtimeCustomFontFamily: _runtimeCustomFontFamily,
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
    final paperColors = PaperTodoThemeColors.resolve(
      brightness: brightness,
      colorScheme: state.colorScheme,
      customThemeColorHex: state.customThemeColorHex,
    );
    final colors = _paperColorScheme(brightness, paperColors);
    final typography = PaperTodoTypography(
      contentFontFamily: _contentFontFamily(state),
      contentFontFamilyFallback: _contentFontFamilyFallback(state),
    );
    final base = ThemeData(
      colorScheme: colors,
      extensions: [paperColors, typography],
      useMaterial3: true,
      scaffoldBackgroundColor: colors.surface,
      canvasColor: colors.surface,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.standard,
    );
    final fontFamily = _fontFamily(state);
    final fontFamilyFallback = _fontFamilyFallback(state);
    final hoverTint = paperColors.hover;
    return base.copyWith(
      hoverColor: hoverTint,
      focusColor: hoverTint,
      highlightColor: hoverTint,
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
          minimumSize: const Size(34, 34),
          maximumSize: const Size(42, 42),
          padding: const EdgeInsets.all(7),
          foregroundColor: colors.onSurfaceVariant,
          disabledForegroundColor: colors.onSurfaceVariant.withValues(
            alpha: 0.30,
          ),
          hoverColor: paperColors.tint.withValues(alpha: 0.075),
          highlightColor: paperColors.tint.withValues(alpha: 0.13),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        side: WidgetStateBorderSide.resolveWith((states) {
          final hovered = states.contains(WidgetState.hovered);
          final selected = states.contains(WidgetState.selected);
          return BorderSide(
            color: hovered && !selected
                ? paperColors.checkBoxHoverBorder
                : paperColors.checkBox,
            width: 1.5,
          );
        }),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        fillColor: WidgetStateProperty.resolveWith((states) {
          final hovered = states.contains(WidgetState.hovered);
          if (states.contains(WidgetState.selected)) {
            return hovered ? paperColors.checkBoxActiveHover : colors.primary;
          }
          return hovered
              ? paperColors.checkBoxUncheckedHover
              : Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(paperColors.paper),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paperColors.tint.withValues(alpha: 0.035),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: paperColors.tint.withValues(alpha: 0.055),
        selectedColor: paperColors.tint.withValues(alpha: 0.12),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.72)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        menuPadding: const EdgeInsets.all(4),
        textStyle: base.textTheme.bodyMedium?.copyWith(
          color: colors.onSurface,
          fontSize: 13,
          height: 1,
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => base.textTheme.bodyMedium
              ?.copyWith(color: colors.onSurface, fontSize: 13, height: 1)
              .copyWith(
                color: states.contains(WidgetState.disabled)
                    ? colors.onSurface.withValues(alpha: 0.72)
                    : colors.onSurface,
              ),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              side: BorderSide(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 4),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant.withValues(alpha: 0.38),
        thickness: 1,
        space: 1,
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(3),
        thickness: const WidgetStatePropertyAll(5),
        minThumbLength: 28,
        mainAxisMargin: 7,
        crossAxisMargin: 0,
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final active = states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged);
          return (active ? const Color(0xFF96784F) : const Color(0xFFB39B74))
              .withValues(
            alpha: states.contains(WidgetState.dragged)
                ? 0.64
                : states.contains(WidgetState.hovered)
                    ? 0.54
                    : 0.34,
          );
        }),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
        trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.onSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: colors.surface, fontSize: 12),
        waitDuration: const Duration(milliseconds: 450),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.surface,
        contentTextStyle: TextStyle(
          color: colors.onSurface,
          fontSize: 13,
          height: 1.25,
        ),
        actionTextColor: colors.primary,
        disabledActionTextColor: colors.onSurfaceVariant.withValues(
          alpha: 0.55,
        ),
        elevation: 8,
        insetPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
    );
  }

  ColorScheme _paperColorScheme(
    Brightness brightness,
    PaperTodoThemeColors palette,
  ) {
    return ColorScheme.fromSeed(
      seedColor: palette.active,
      brightness: brightness,
    ).copyWith(
      primary: palette.active,
      onPrimary: palette.paper,
      surface: palette.paper,
      surfaceContainerLowest: palette.paper,
      surfaceContainerLow: palette.paper,
      surfaceContainer: palette.paper,
      surfaceContainerHigh: palette.code,
      surfaceContainerHighest: palette.paper,
      onSurface: palette.text,
      onSurfaceVariant: palette.weakText,
      outline: palette.paperBorder,
      outlineVariant: palette.paperBorder,
      primaryContainer: Color.alphaBlend(
        palette.tint.withValues(alpha: palette.isDark ? 42 / 255 : 24 / 255),
        palette.paper,
      ),
      onPrimaryContainer: palette.text,
      secondary: palette.active,
      onSecondary: palette.paper,
      tertiary: palette.link,
      onTertiary: palette.paper,
      error: palette.danger,
      onError: palette.paper,
    );
  }

  ThemeMode _themeMode(String theme) {
    return switch (theme.trim().toLowerCase()) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
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

  String? _contentFontFamily(AppState state) {
    return resolveAppContentFontFamily(
      state,
      runtimeCustomFontFamily: _runtimeCustomFontFamily,
    );
  }

  List<String>? _contentFontFamilyFallback(AppState state) {
    return resolveAppContentFontFamilyFallback(
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
    UiFontPresets.yaHei => null,
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
    UiFontPresets.yaHei => null,
    UiFontPresets.dengXian => _dengXianFontFamilyFallback,
    _ => null,
  };
}

String resolveAppContentFontFamily(
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
    UiFontPresets.yaHei => _defaultContentFontFamily,
    UiFontPresets.dengXian => _dengXianFontFamily,
    UiFontPresets.serif => 'serif',
    UiFontPresets.mono => 'monospace',
    _ => _defaultContentFontFamily,
  };
}

String resolveWindowsNativeDialogFontFamily(
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
    UiFontPresets.yaHei => 'Microsoft YaHei UI',
    UiFontPresets.dengXian => _dengXianFontFamily,
    UiFontPresets.serif => 'Georgia',
    UiFontPresets.mono => 'Consolas',
    _ => '',
  };
}

List<String>? resolveAppContentFontFamilyFallback(
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
    UiFontPresets.yaHei => _defaultContentFontFamilyFallback,
    UiFontPresets.dengXian => _dengXianFontFamilyFallback,
    UiFontPresets.serif || UiFontPresets.mono => null,
    _ => _defaultContentFontFamilyFallback,
  };
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
    WebDavException(:final message, :final responseBody) =>
      _webDavFailureMessage(message, responseBody),
    WebDavPayloadDecryptionException(:final message) => message,
    PlatformException(:final code, :final message, :final details) =>
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
  return strings.format(PaperTodoStringKeys.actionOpenMarkdownInDefaultEditor, [
    _normalizedExternalMarkdownExtensionForDisplay(externalMarkdownExtension),
  ]);
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
    this.runtimeCustomFontFamily,
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
  final String? runtimeCustomFontFamily;
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
  Future<void> _capsuleToggleQueue = Future<void>.value();
  int _capsuleToggleGeneration = 0;
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
    _surfaceUpdateSubscription = controller.paperSurfaceUpdates.listen(
      _handleSurfaceUpdate,
    );
    _paperEditSubscription = controller.paperEdits.listen(_handlePaperEdit);
    _paperActionSubscription = controller.paperWindowActionRequests.listen(
      _handlePaperWindowAction,
    );
    _capsuleDropSubscription = controller.capsuleDrops.listen(
      _handleCapsuleDrop,
    );
    _paperOpenSubscription = controller.paperOpenRequests.listen((paperId) {
      unawaited(_handlePaperOpenRequest(paperId));
    });
    _paperDeleteSubscription = controller.paperDeleteRequests.listen((paperId) {
      unawaited(_handlePaperDeleteRequest(paperId));
    });
    _coordinatorCloseSubscription = controller.coordinatorCloseRequests.listen((
      _,
    ) {
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
        backgroundColor: _windowsPaperTransparencyKey,
        body: DecoratedBox(
          key: const ValueKey('windows-settings-paper-underlay'),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      );
    }
    if (widget.paperWindowMode) {
      if (surfacePaper == null) {
        return const SizedBox.shrink();
      }
      if (surfacePaper.isCollapsed) {
        return _paperWindowCapsule(surfacePaper);
      }
      return Scaffold(
        backgroundColor: _windowsPaperTransparencyKey,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              key: ValueKey('${surfacePaper.id}-paper-window-chrome-margin'),
              child: Padding(
                padding: const EdgeInsets.all(_paperWindowChromeMargin),
                child: _paperPreview(surfacePaper, notePapers),
              ),
            ),
            ..._paperWindowTransparencyGuards(),
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
                ? Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)
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
                  children: [_paperPreview(surfacePaper, notePapers)],
                ),
        ),
      ),
    );
  }

  // Legacy renderer retained only for storage/widget migration coverage. The
  // live master capsule is an independent native HWND and must never replace a
  // real paper engine's content.
  // ignore: unused_element
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

  // ignore: unused_element
  Widget _paperWindowMasterCapsule(PaperData paper) {
    final colors = Theme.of(context).colorScheme;
    final collapseAllActive = controller.state.isCapsuleCollapseAllActiveFor(
      paper,
    );
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
        padding: const EdgeInsets.all(_paperWindowChromeMargin),
        child: MouseRegion(
          onEnter: widget.paperWindowCapsuleHoverChanged == null
              ? null
              : (_) => unawaited(widget.paperWindowCapsuleHoverChanged!(true)),
          onExit: widget.paperWindowCapsuleHoverChanged == null
              ? null
              : (_) => unawaited(widget.paperWindowCapsuleHoverChanged!(false)),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('${paper.id}-paper-window-master-capsule'),
              borderRadius: BorderRadius.circular(999),
              onTap: () => unawaited(toggle()),
              child: DecoratedBox(
                key: ValueKey(
                  '${paper.id}-paper-window-master-capsule-surface',
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(999),
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
                            : (_) =>
                                unawaited(widget.paperWindowDragStarter!()),
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
    final paperColors = PaperTodoThemeColors.of(context);
    const capsuleCloseWidth = 21.0;
    final scriptCapsuleSpec =
        paper.isNote ? ScriptCapsuleSpec.tryParse(paper.content) : null;
    final capsuleIcon = scriptCapsuleSpec != null
        ? '\u26A1'
        : paper.isNote
            ? '\u270E'
            : '\u2713';
    final capsuleIconSize = scriptCapsuleSpec == null ? 13.0 : 15.0;
    const capsuleRadius = 12.0;
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
            left: _paperWindowChromeMargin,
            top: _paperWindowChromeMargin,
            right: _paperWindowChromeMargin,
            bottom: _paperWindowChromeMargin,
            child: MouseRegion(
              onEnter: widget.paperWindowCapsuleHoverChanged == null
                  ? null
                  : (_) =>
                      unawaited(widget.paperWindowCapsuleHoverChanged!(true)),
              onExit: widget.paperWindowCapsuleHoverChanged == null
                  ? null
                  : (_) => unawaited(
                        widget.paperWindowCapsuleHoverChanged!(false),
                      ),
              child: Material(
                color: Colors.transparent,
                child: DecoratedBox(
                  key: ValueKey('${paper.id}-paper-window-capsule-surface'),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border.all(color: colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(capsuleRadius),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.08),
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
                            left: Radius.circular(capsuleRadius),
                          ),
                          hoverColor: paperColors.hover,
                          highlightColor: paperColors.tint.withValues(
                            alpha: paperColors.isDark ? 58 / 255 : 42 / 255,
                          ),
                          splashColor: Colors.transparent,
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
                                Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    Transform.translate(
                                      offset: Offset(
                                        0,
                                        paper.isNote ? -1 : -1.25,
                                      ),
                                      child: Text(
                                        capsuleIcon,
                                        style: TextStyle(
                                          color: paperColors.brightWeakText,
                                          fontFamily: 'Segoe UI Symbol',
                                          fontFamilyFallback: const <String>[
                                            'Segoe UI Emoji',
                                          ],
                                          fontSize: capsuleIconSize,
                                          fontWeight: FontWeight.w600,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: -6,
                                      width: 26,
                                      top: -8,
                                      bottom: -8,
                                      child: Listener(
                                        key: ValueKey(
                                          '${paper.id}-capsule-drag-handle',
                                        ),
                                        behavior: HitTestBehavior.opaque,
                                        onPointerDown:
                                            widget.paperWindowDragStarter ==
                                                    null
                                                ? null
                                                : (_) => unawaited(
                                                      widget
                                                          .paperWindowDragStarter!(),
                                                    ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Transform.translate(
                                    offset: const Offset(-1, -1),
                                    child: Transform.scale(
                                      scaleX: paper.isNote ? 0.93 : 0.94,
                                      scaleY: 1,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        _displayTitle(paper),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                              fontSize: 11,
                                            ),
                                      ),
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
                            '${paper.id}-paper-window-capsule-close',
                          ),
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(capsuleRadius),
                          ),
                          hoverColor: paperColors.hover,
                          highlightColor: paperColors.tint.withValues(
                            alpha: paperColors.isDark ? 58 / 255 : 42 / 255,
                          ),
                          splashColor: Colors.transparent,
                          onTap: () => unawaited(_hidePaper(paper)),
                          child: Transform.translate(
                            offset: const Offset(-1, 0),
                            child: Text(
                              '\u00D7',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontFamily: 'Segoe UI Symbol',
                                fontFamilyFallback: const <String>[
                                  'Segoe UI Emoji',
                                ],
                                fontSize: 18,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
      Widget? child,
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
              child: child,
            ),
          ),
        ),
      );
    }

    // The paper itself now fills the HWND. Keep a narrow native-like hit zone
    // over its edge so resizing remains discoverable without a fake frame.
    const edge = 8.0;
    const corner = 16.0;
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
        child: CustomPaint(painter: const _PaperResizeGripPainter()),
      ),
    ];
  }

  List<Widget> _paperWindowTransparencyGuards() {
    const offset = _paperWindowChromeMargin - 1;
    const thickness = 1.0;
    return const [
      Positioned(
        left: offset,
        top: 0,
        bottom: 0,
        width: thickness,
        child: ColoredBox(
          key: ValueKey('paper-window-transparency-guard-left'),
          color: _windowsPaperTransparencyKey,
        ),
      ),
      Positioned(
        right: offset,
        top: 0,
        bottom: 0,
        width: thickness,
        child: ColoredBox(
          key: ValueKey('paper-window-transparency-guard-right'),
          color: _windowsPaperTransparencyKey,
        ),
      ),
      Positioned(
        left: 0,
        top: offset,
        right: 0,
        height: thickness,
        child: ColoredBox(
          key: ValueKey('paper-window-transparency-guard-top'),
          color: _windowsPaperTransparencyKey,
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: offset,
        height: thickness,
        child: ColoredBox(
          key: ValueKey('paper-window-transparency-guard-bottom'),
          color: _windowsPaperTransparencyKey,
        ),
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
              if (Platform.isWindows &&
                  controller.state.useCapsuleMode &&
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
          tooltip: _tooltipLabel(enableToolTips, openMarkdownEditorLabel),
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
      if (Platform.isWindows &&
          controller.state.useCapsuleMode &&
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
      padding: _paperTodoPopupMenuItemPadding,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
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
      moveCompletedTodosToBottom: controller.state.moveCompletedTodosToBottom,
      showTopBarNewTodoButton: controller.state.showTopBarNewTodoButton,
      showTopBarNewNoteButton: controller.state.showTopBarNewNoteButton,
      showTopBarExternalOpenButton:
          controller.state.showTopBarExternalOpenButton,
      useCapsuleMode: Platform.isWindows && controller.state.useCapsuleMode,
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
      nativeDialogFontFamily: resolveWindowsNativeDialogFontFamily(
        controller.state,
        runtimeCustomFontFamily: widget.runtimeCustomFontFamily,
      ),
      collapseAllActive: Platform.isWindows &&
          controller.state.useCapsuleMode &&
          controller.state.useCapsuleCollapseAll &&
          controller.state.isCapsuleCollapseAllActiveFor(paper),
      noteLineSpacing: controller.state.noteLineSpacing,
      syncing: _isSyncing,
      onSync: actionSender == null
          ? () => _syncNow()
          : () => actionSender(PaperWindowActionKinds.syncNow),
      onChanged: _refreshAndSaveState,
      onPersist: _saveState,
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
          : (note, anchorPaper) =>
              actionSender(PaperWindowActionKinds.openPaper, value: note.id),
      onRunScriptCapsule: actionSender == null
          ? _runScriptCapsule
          : (_) => actionSender(PaperWindowActionKinds.runScriptCapsule),
      onOpenExternalMarkdown: actionSender == null
          ? _openNoteMarkdownExternally
          : (_) => actionSender(PaperWindowActionKinds.openExternalMarkdown),
      onOpenUri: actionSender == null
          ? _openUri
          : (uri) => actionSender(PaperWindowActionKinds.openUri, value: uri),
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
      await _showPaperLimitDialog();
      return;
    }
    await controller.showPaper(createdPaper);
    await _saveState();
  }

  Future<void> _showPaperLimitDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final strings = PaperTodoStringsScope.of(context);
        final paperColors = PaperTodoThemeColors.of(context);
        return _PaperDialog(
          width: 340,
          height: 176,
          minWidth: 340,
          minHeight: 176,
          radius: 10,
          padding: const EdgeInsets.all(18),
          contentSpacing: 8,
          actionSpacing: 16,
          titleFontSize: 16,
          shadowKind: _PaperDialogShadowKind.compact,
          title: strings.get(PaperTodoStringKeys.paperLimitTitle),
          content: Text(
            strings.get(PaperTodoStringKeys.paperLimitMessage),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: paperColors.weakText,
                  fontSize: 13,
                  height: 20 / 13,
                ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                minimumSize: const Size(72, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                foregroundColor: paperColors.text,
                textStyle: const TextStyle(fontSize: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text(
                strings.get(PaperTodoStringKeys.dialogDueDateConfirm),
              ),
            ),
          ],
        );
      },
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

  Future<void> _toggleCollapseAll([PaperData? paper, String queueKey = '']) {
    final normalizedQueueKey = queueKey.trim();
    final requestedPaperId = paper?.id ?? '';
    if (!mounted) {
      return Future<void>.value();
    }

    // Commit the logical state at pointer-up time.  Only native reconciliation
    // is serialized; waiting for a prior HWND refresh before changing the
    // model makes a quick collapse/expand pair appear to lose the second
    // click.
    final targetPaper = requestedPaperId.isEmpty
        ? paper
        : controller.state.papers
            .where((candidate) => candidate.id == requestedPaperId)
            .firstOrNull;
    final beforeActive = targetPaper == null
        ? controller.state.capsuleCollapseAllActive
        : controller.state.isCapsuleCollapseAllActiveFor(targetPaper);
    var changed = false;
    setState(() {
      if (normalizedQueueKey.isNotEmpty) {
        changed = controller.state.toggleCapsuleCollapseAllQueue(
          normalizedQueueKey,
        );
      } else if (targetPaper != null || requestedPaperId.isEmpty) {
        final before = targetPaper == null
            ? controller.state.capsuleCollapseAllActive
            : controller.state.isCapsuleCollapseAllActiveFor(targetPaper);
        controller.state.toggleCapsuleCollapseAllFor(targetPaper);
        final after = targetPaper == null
            ? controller.state.capsuleCollapseAllActive
            : controller.state.isCapsuleCollapseAllActiveFor(targetPaper);
        changed = before != after;
      }
    });
    if (!changed) {
      return UsageLog.instance.record(
        'capsule',
        'master-toggle-ignored',
        details: {
          'queueKey': normalizedQueueKey,
          'paperId': requestedPaperId,
          'activeBefore': beforeActive,
          'reason': 'queue-not-live',
        },
      );
    }

    final activeAfter = targetPaper == null
        ? controller.state.capsuleCollapseAllActive
        : controller.state.isCapsuleCollapseAllActiveFor(targetPaper);
    final generation = ++_capsuleToggleGeneration;
    final snapshot = _stateSnapshot(controller.state);
    final queuePaperCount = normalizedQueueKey.isEmpty
        ? controller.state.papers.length
        : controller.state.papers
            .where(
              (candidate) =>
                  candidate.isVisible &&
                  controller.state.capsuleQueueKeyFor(candidate) ==
                      normalizedQueueKey,
            )
            .length;
    final operation = _capsuleToggleQueue.catchError((_) {}).then((_) async {
      if (!mounted) return;
      await UsageLog.instance.record(
        'capsule',
        'master-toggle',
        details: {
          'queueKey': normalizedQueueKey,
          'paperId': requestedPaperId,
          'activeBefore': beforeActive,
          'activeAfter': activeAfter,
          'generation': generation,
          'queuePaperCount': queuePaperCount,
        },
      );
      // A master capsule changes only the capsule queue. A full restore also
      // reapplies paper bounds, visibility and z-order, which makes otherwise
      // stationary cards flash when the queue is collapsed or expanded.
      await controller.refreshSurfaceRegistry(snapshot: snapshot);
      await _saveState();
      await UsageLog.instance.record(
        'capsule',
        'master-toggle-applied',
        details: {
          'queueKey': normalizedQueueKey,
          'paperId': requestedPaperId,
          'active': activeAfter,
          'generation': generation,
        },
      );
    });
    _capsuleToggleQueue = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }

  Future<void> _activatePaperFromCapsule(
    PaperData paper, {
    bool nativeActivated = false,
  }) async {
    final wasPinned = paper.isPinnedToDesktop;
    final wasCollapsed = paper.isCollapsed;
    setState(() {
      paper
        ..isVisible = true
        ..isCollapsed = false
        ..isPinnedToDesktop = false;
      controller.state.normalize();
      _surfacePaperId = paper.id;
    });
    await UsageLog.instance.record(
      'capsule',
      'paper-activate',
      details: {
        'paperId': paper.id,
        'wasPinnedToDesktop': wasPinned,
        'wasCollapsed': wasCollapsed,
        'nativeActivated': nativeActivated,
      },
    );
    if (nativeActivated && !wasCollapsed) {
      // The native proxy handled foreground activation synchronously while
      // Windows still associated it with the mouse click. Replaying show,
      // bounds and z-order from Dart would make the paper/capsule flash once.
      await controller.refreshSurfaceRegistry();
    } else {
      await controller.showPaper(paper);
    }
    await _saveState();
  }

  Future<void> _saveState({
    bool scheduleLocalEditSync = true,
    bool rebuildTrayMenu = true,
    bool preserveExistingPendingOperationBatch = true,
    AppState? usageBeforeState,
    String usageSource = 'state-save',
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
      final savedState = _stateSnapshot(controller.state);
      await widget.store.save(savedState);
      final usageBefore = usageBeforeState ?? beforeState;
      if (usageBefore != null) {
        await UsageLog.instance.recordStateChange(
          before: usageBefore,
          after: savedState,
          source: usageSource,
        );
      }
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
      controller.state.sync.markPaperDeleted(
        removedPaper.id,
        DateTime.now().toUtc(),
      );
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
          strings.format(PaperTodoStringKeys.paperDeleted, [
            _displayTitle(removedPaper),
          ]),
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
      final insertIndex =
          targetIndex.clamp(0, controller.state.papers.length).toInt();
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
    await UsageLog.instance.record(
      'paper',
      'desktop-pin-changed',
      details: {'paperId': paper.id, 'enabled': pinned},
    );
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
            strings.format(PaperTodoStringKeys.externalMarkdownOpenFailed, [
              _readableFailureMessage(error, strings: strings),
            ]),
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
            strings.format(PaperTodoStringKeys.scriptCapsuleFailed, [
              _readableFailureMessage(error, strings: strings),
            ]),
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
              strings.format(PaperTodoStringKeys.openLinkFailed, [
                _readableFailureMessage(error, strings: strings),
              ]),
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
          content: Text(strings.get(PaperTodoStringKeys.openLinkUnsupported)),
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
            strings.format(PaperTodoStringKeys.openLinkFailed, [
              _readableFailureMessage(error, strings: strings),
            ]),
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
    if (paper.isCollapsed &&
        controller.state.isCapsuleCollapseAllActiveFor(paper)) {
      await _activatePaperFromCapsule(paper);
      return;
    }
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
    await UsageLog.instance.record(
      'application',
      'startup-command',
      details: {'command': command.kind.name},
    );
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
    final previousPaper = controller.state.papers[paperIndex];
    final changedPaper = PaperData.fromJson(paper.toJson());
    final surfaceTopologyChanged =
        previousPaper.isVisible != changedPaper.isVisible ||
            previousPaper.isCollapsed != changedPaper.isCollapsed ||
            previousPaper.isPinnedToDesktop != changedPaper.isPinnedToDesktop ||
            previousPaper.capsuleSide != changedPaper.capsuleSide ||
            previousPaper.capsuleMonitorDeviceName !=
                changedPaper.capsuleMonitorDeviceName;
    setState(() => controller.state.papers[paperIndex] = changedPaper);
    if (surfaceTopologyChanged) {
      // A child engine reports collapse/expand through `paperChanged`. That
      // event changes the HWND shape and the native capsule queue, so a plain
      // content update is insufficient. Reconcile the complete registry
      // before showing or hiding the changed paper.
      unawaited(() async {
        await controller.refreshPaperSurfaces();
        if (changedPaper.isVisible) {
          // The registry pass has already applied the new HWND shape. Keep
          // the regular edit path as well so title/content and native state
          // remain synchronized for both the real host and test hosts.
          await controller.updatePaperSurface(changedPaper);
        } else {
          await controller.hidePaper(changedPaper);
        }
      }());
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
          unawaited(
            _activatePaperFromCapsule(
              target,
              nativeActivated: request.nativeActivated,
            ),
          );
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
        unawaited(
          UsageLog.instance.record(
            'capsule',
            'master-click-received',
            details: {
              'queueKey': request.value,
              'paperId': request.paperId,
              if (request.surfaceGeneration != null)
                'surfaceGeneration': request.surfaceGeneration,
            },
          ),
        );
        unawaited(_toggleCollapseAll(paper, request.value));
      case PaperWindowActionKinds.collapsePaper:
        // Native proxy HWNDs can deliver one click with their previous
        // collapseOnClick flag while a pin-state surface refresh is in flight.
        // Dart owns the authoritative paper state: a pinned paper must always
        // use its capsule as the escape route from desktop mode, never become
        // collapsed behind the desktop.
        if (paper.isPinnedToDesktop) {
          unawaited(
            UsageLog.instance.record(
              'capsule',
              'stale-collapse-rerouted',
              details: {'paperId': paper.id},
            ),
          );
          unawaited(_activatePaperFromCapsule(paper));
          break;
        }
        if (!paper.isCollapsed) {
          setState(() {
            paper.isCollapsed = true;
            controller.state.normalize();
          });
          unawaited(
            UsageLog.instance.record(
              'capsule',
              'paper-collapse',
              details: {
                'paperId': paper.id,
                'wasPinnedToDesktop': paper.isPinnedToDesktop,
              },
            ),
          );
          unawaited(controller.refreshPaperSurfaces());
          unawaited(_saveState());
        }
      case PaperWindowActionKinds.expandPaper:
        unawaited(_activatePaperFromCapsule(paper));
      case PaperWindowActionKinds.syncNow:
        unawaited(_syncNow());
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
    unawaited(
      UsageLog.instance.record(
        'capsule',
        'dropped',
        details: {
          'paperId': request.paperId,
          'isMasterCapsule': request.isMasterCapsule,
          'monitorDeviceName': request.monitorDeviceName,
          'side': request.side,
          'dropTop': request.dropTop.round(),
        },
      ),
    );
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
        .where(
          (candidate) =>
              _paperOccupiesDeepCapsuleQueue(candidate) &&
              state.capsuleQueueKeyFor(candidate) == queueKey,
        )
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
      deleteConfirmTitle: strings.get(
        PaperTodoStringKeys.trayDeleteConfirmTitle,
      ),
      deleteConfirmMessage: strings.get(
        PaperTodoStringKeys.trayDeleteConfirmMessage,
      ),
      inlineConfirmDelete: strings.get(
        PaperTodoStringKeys.trayInlineConfirmDelete,
      ),
      inlineConfirmAction: strings.get(
        PaperTodoStringKeys.trayInlineConfirmAction,
      ),
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
    await UsageLog.instance.record(
      'sync',
      'started',
      details: {
        'manual': showMessage,
        'provider': controller.state.sync.provider,
        'preset': controller.state.sync.webDav.presetId,
      },
    );
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
      await UsageLog.instance.record(
        'sync',
        'completed',
        details: {
          'manual': showMessage,
          'status': result.syncResult.status.name,
        },
      );
      _restartAutoSyncTimer();
      if (showMessage && mounted) {
        _showSyncSnackBar(
          message: _syncRunMessage(result),
          status: result.syncResult.status,
        );
      }
    } catch (error) {
      await UsageLog.instance.record(
        'sync',
        'failed',
        level: 'ERROR',
        details: {
          'manual': showMessage,
          'errorType': error.runtimeType.toString(),
          if (error is WebDavException) 'statusCode': error.statusCode,
        },
      );
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
            final paperColors = PaperTodoThemeColors.of(context);
            return _PaperDialog(
              width: 382,
              title: strings.get(PaperTodoStringKeys.dialogRestoreSnapshot),
              content: Text(
                _snapshotSummary(snapshot),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: paperColors.weakText,
                      fontSize: 13,
                      height: 20 / 13,
                    ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    fixedSize: const Size(72, 34),
                    minimumSize: const Size(72, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    foregroundColor: paperColors.text,
                    backgroundColor: paperColors.tint.withValues(
                      alpha: 28 / 255,
                    ),
                    textStyle: const TextStyle(fontSize: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(strings.get(PaperTodoStringKeys.actionCancel)),
                ),
                FilledButton(
                  key: const ValueKey('confirm-restore-snapshot'),
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    fixedSize: const Size(72, 34),
                    minimumSize: const Size(72, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    backgroundColor: paperColors.active,
                    foregroundColor: paperColors.paper,
                    textStyle: const TextStyle(fontSize: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(strings.get(PaperTodoStringKeys.actionRestore)),
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
      _showSyncSnackBar(message: _syncMessage(result), status: result.status);
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
    await controller.setCoordinatorBackgroundColor(
      Theme.of(context).colorScheme.surface.toARGB32(),
    );
    final stateBeforeSettings = _stateSnapshot(controller.state);
    final hadPendingLocalEditSync = _pendingLocalEditBaseState != null &&
        _pendingLocalEditLatestState != null;
    _localEditSyncDebounce?.cancel();
    _localEditSyncDebounce = null;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    _startSettingsDeferredAutoSyncTimer();
    final previousSyncJson = _syncUserConfigurationJson(controller.state.sync);
    final previousSyncTargetJson = _syncTargetConfigurationJson(
      controller.state.sync,
    );
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
      initialMoveCompletedTodosToBottom:
          controller.state.moveCompletedTodosToBottom,
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
      supportsCapsules: Platform.isWindows,
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
      pickCustomThemeColor: controller.supportsCustomColorPicker
          ? controller.chooseCustomColor
          : null,
      openAuthorLink: () => _openUri('https://github.com/snownico0722'),
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
      controller.state.moveCompletedTodosToBottom =
          result.moveCompletedTodosToBottom;
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
        await applyPlatformSetting(PaperTodoStringKeys.dataDirectory, () async {
          final nextFilePath = p.join(selectedDirectory, 'data.json');
          await widget.store.relocate(nextFilePath, controller.state);
          try {
            await controller.commitDataDirectory(selectedDirectory);
            await UsageLog.instance.configureForStateFile(nextFilePath);
          } catch (_) {
            await widget.store.relocate(previousFilePath, controller.state);
            rethrow;
          }
        });
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
            strings.format(PaperTodoStringKeys.platformSettingsFailed, [
              platformSettingErrors.join('; '),
            ]),
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
        usageBeforeState: stateBeforeSettings,
        usageSource: 'settings-save',
      );
      await _configureAndroidBackgroundSyncAfterSettingsSave();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.format(PaperTodoStringKeys.settingsSaveFailed, [
                _readableFailureMessage(error, strings: strings),
              ]),
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
            strings.format(PaperTodoStringKeys.platformSettingsFailed, [
              'WebDAV sync: '
                  '${_readableFailureMessage(error, strings: strings)}',
            ]),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), action: action));
  }

  void _showSyncFailureSnackBar(Object error) {
    final failureMessage = error is WebDavException &&
            error.statusCode == HttpStatus.unauthorized &&
            controller.state.sync.webDav.presetId == WebDavPresetIds.jianguoyun
        ? strings.get(PaperTodoStringKeys.jianguoyunAuthenticationFailed)
        : _readableFailureMessage(error, strings: strings);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.format(PaperTodoStringKeys.syncFailed, [failureMessage]),
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
          strings.format(PaperTodoStringKeys.syncRestoreSnapshotFailed, [
            _readableFailureMessage(error, strings: strings),
          ]),
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
      AppSyncStatus.configurationMissing => strings.get(
          PaperTodoStringKeys.syncCompleteConfiguration,
        ),
      AppSyncStatus.uploaded => strings.get(PaperTodoStringKeys.syncUploaded),
      AppSyncStatus.downloaded => strings.get(
          PaperTodoStringKeys.syncDownloaded,
        ),
      AppSyncStatus.conflict => strings.get(PaperTodoStringKeys.syncConflict),
      AppSyncStatus.payloadUnreadable => strings.get(
          PaperTodoStringKeys.syncPayloadUnreadable,
        ),
    };
  }

  String _localizedSyncResultMessage(AppSyncResult result) {
    final message = result.message;
    return switch (message) {
      'Sync is disabled.' => strings.get(PaperTodoStringKeys.syncDisabled),
      'Complete WebDAV sync settings and encryption passphrase first.' =>
        strings.get(PaperTodoStringKeys.syncCompleteConfiguration),
      'Local data uploaded.' => strings.get(PaperTodoStringKeys.syncUploaded),
      'Remote data downloaded.' => strings.get(
          PaperTodoStringKeys.syncDownloaded,
        ),
      'Remote data downloaded from legacy plain WebDAV data and migrated to encrypted payloads.' =>
        strings.get(PaperTodoStringKeys.syncDownloadedLegacyPlainMigrated),
      'Remote data downloaded from legacy plain WebDAV data. Automatic encryption migration could not complete; sync again to retry.' =>
        strings.get(PaperTodoStringKeys.syncDownloadedLegacyPlainRetry),
      'Remote data downloaded from legacy plain WebDAV data. The next successful upload will write encrypted payloads.' =>
        strings.get(PaperTodoStringKeys.syncDownloadedLegacyPlainNextUpload),
      'Remote snapshot is empty.' => strings.get(
          PaperTodoStringKeys.syncRemoteSnapshotEmpty,
        ),
      'Snapshot restored.' => strings.get(
          PaperTodoStringKeys.syncSnapshotRestored,
        ),
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
        strings.format(PaperTodoStringKeys.syncConflictSnapshotPreserved, [
          result.snapshotPath,
        ]),
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
        strings.format(PaperTodoStringKeys.syncMergedRemoteChanges, [
          appliedCount,
          changeLabel,
        ]),
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
          strings.format(PaperTodoStringKeys.syncMigratedLegacyOperationLogs, [
            total,
            logLabel,
          ]),
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
          strings.format(PaperTodoStringKeys.syncFoundLegacyOperationLogs, [
            total,
            logLabel,
          ]),
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
            final paperColors = PaperTodoThemeColors.of(context);
            return _PaperDialog(
              width: 300,
              height: 178,
              minWidth: 300,
              minHeight: 178,
              radius: 18,
              padding: const EdgeInsets.all(18),
              contentSpacing: 10,
              actionSpacing: 16,
              titleFontSize: 16,
              destructive: true,
              title: strings.get(PaperTodoStringKeys.dialogDeletePaper),
              content: Text(
                strings.get(PaperTodoStringKeys.dialogDeletePaperBody),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: paperColors.weakText,
                      fontSize: 13,
                      height: 20 / 13,
                    ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    fixedSize: const Size(72, 34),
                    minimumSize: const Size(72, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    backgroundColor: paperColors.danger,
                    foregroundColor: paperColors.paper,
                    textStyle: const TextStyle(fontSize: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(strings.get(PaperTodoStringKeys.actionDelete)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    fixedSize: const Size(72, 34),
                    minimumSize: const Size(72, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    foregroundColor: paperColors.text,
                    backgroundColor: paperColors.tint.withValues(
                      alpha: 28 / 255,
                    ),
                    textStyle: const TextStyle(fontSize: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(strings.get(PaperTodoStringKeys.actionCancel)),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  String _displayTitle(PaperData paper) {
    return PaperTitles.shorten(
      controller.paperTitleText(paper),
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
          final distance = _distanceFromNow(
            a,
            now,
          ).compareTo(_distanceFromNow(b, now));
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
      return !candidate.dueAt.isAfter(
        now.add(_reminderInterval(candidate.item)),
      );
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
    final reminderNow = DateTime.now();
    final singleCandidate = candidates.length == 1;
    final message = singleCandidate
        ? strings.get(PaperTodoStringKeys.todoReminderBubbleTitle)
        : strings.format(PaperTodoStringKeys.todoReminderMultiple, [
            candidates.length,
          ]);
    final details = singleCandidate
        ? <String>[_formatPaperTodoReminderBubbleMessage(first, reminderNow)]
        : candidates
            .take(_maxTodoReminderDetailLines)
            .map(
              (candidate) => _formatTodoReminderDetail(
                candidate,
                reminderNow,
                includeItemText: true,
              ),
            )
            .toList();
    final reminderDuration = Duration(
      seconds: controller.state.todoReminderBubbleDurationSeconds,
    );
    final nativePresenter = widget.paperWindowReminderPresenter;
    if (widget.paperWindowMode && nativePresenter != null) {
      final colorScheme = Theme.of(context).colorScheme;
      final paperColors = PaperTodoThemeColors.of(context);
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final reminderTint = paperColors.tint;
      unawaited(
        nativePresenter(<String, Object?>{
          'visible': true,
          'title': message,
          'message': details.join('\n'),
          'durationSeconds': reminderDuration.inSeconds,
          'backgroundColor': colorScheme.surface.toARGB32(),
          'borderColor': reminderTint.toARGB32(),
          'borderAlpha': 150,
          'iconBackgroundColor': Color.alphaBlend(
            reminderTint.withValues(alpha: (isDark ? 48 : 32) / 255),
            colorScheme.surface,
          ).toARGB32(),
          'accentColor': colorScheme.primary.toARGB32(),
          'textColor': colorScheme.onSurface.toARGB32(),
          'weakTextColor': colorScheme.onSurfaceVariant.toARGB32(),
        }),
      );
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
                  style: DefaultTextStyle.of(
                    context,
                  ).style.copyWith(fontSize: 12, height: 1.2),
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
    unawaited(
      snackBarController.closed.then((_) {
        if (identical(_todoReminderSnackBarController, snackBarController)) {
          _cancelTodoReminderSnackBarDismissTimer();
          _todoReminderSnackBarController = null;
        }
        if (_sameStringSet(_activeTodoReminderKeys, reminderKeys)) {
          _activeTodoReminderItemIds.clear();
          _activeTodoReminderKeys.clear();
        }
      }),
    );
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
    final wasCollapseAllActive = controller.state.isCapsuleCollapseAllActiveFor(
      paper,
    );
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

  String _formatPaperTodoReminderBubbleMessage(
    _TodoReminderCandidate candidate,
    DateTime now,
  ) {
    final dueAt = candidate.dueAt.toLocal();
    final dueText = '${dueAt.year.toString().padLeft(4, '0')}-'
        '${dueAt.month.toString().padLeft(2, '0')}-'
        '${dueAt.day.toString().padLeft(2, '0')} '
        '${dueAt.hour.toString().padLeft(2, '0')}:'
        '${dueAt.minute.toString().padLeft(2, '0')}:'
        '${dueAt.second.toString().padLeft(2, '0')}';
    final difference = dueAt.difference(now);
    final absoluteDifference = difference.isNegative
        ? Duration(microseconds: -difference.inMicroseconds)
        : difference;
    final countdown = _formatPaperTodoReminderBubbleCountdown(
      absoluteDifference,
    );
    final relativeText = strings.format(
      difference.isNegative
          ? PaperTodoStringKeys.todoReminderBubbleOverdue
          : PaperTodoStringKeys.todoReminderBubbleRemaining,
      [countdown],
    );
    return strings.format(PaperTodoStringKeys.todoReminderBubbleMessage, [
      dueText,
      relativeText,
      _displayReminderItemText(candidate.paper, candidate.item),
    ]);
  }

  String _formatPaperTodoReminderBubbleCountdown(Duration span) {
    var totalSeconds =
        (span.inMicroseconds / Duration.microsecondsPerSecond).ceil();
    if (totalSeconds < 0) {
      totalSeconds = 0;
    }
    final days = totalSeconds ~/ Duration.secondsPerDay;
    totalSeconds %= Duration.secondsPerDay;
    final hours = totalSeconds ~/ Duration.secondsPerHour;
    totalSeconds %= Duration.secondsPerHour;
    final minutes = totalSeconds ~/ Duration.secondsPerMinute;
    final seconds = totalSeconds % Duration.secondsPerMinute;

    String component(String key, int value) => strings.format(key, [value]);

    if (days > 0) {
      return '${component(PaperTodoStringKeys.todoReminderCountdownDay, days)}'
          '${component(PaperTodoStringKeys.todoReminderCountdownHour, hours)}'
          '${component(PaperTodoStringKeys.todoReminderCountdownMinute, minutes)}'
          '${component(PaperTodoStringKeys.todoReminderCountdownSecond, seconds)}';
    }
    if (hours > 0) {
      return '${component(PaperTodoStringKeys.todoReminderCountdownHour, hours)}'
          '${component(PaperTodoStringKeys.todoReminderCountdownMinute, minutes)}'
          '${component(PaperTodoStringKeys.todoReminderCountdownSecond, seconds)}';
    }
    if (minutes > 0) {
      return '${component(PaperTodoStringKeys.todoReminderCountdownMinute, minutes)}'
          '${component(PaperTodoStringKeys.todoReminderCountdownSecond, seconds)}';
    }
    return component(PaperTodoStringKeys.todoReminderCountdownSecond, seconds);
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
    final dueDetail = strings.format(PaperTodoStringKeys.dueLabel, [
      '$dueText ($relativeText)',
    ]);
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
    final paperColors = PaperTodoThemeColors.of(context);
    final inputFill = paperColors.tint.withValues(
      alpha: paperColors.isDark ? 22 / 255 : 12 / 255,
    );
    final inputBorder = BorderSide(
      color: paperColors.tint.withValues(alpha: 80 / 255),
    );
    InputDecoration inputDecoration() => InputDecoration(
          filled: true,
          fillColor: inputFill,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: inputBorder,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: inputBorder,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: paperColors.active, width: 1.5),
          ),
        );
    return Focus(
      autofocus: true,
      onKeyEvent: _handleDialogKeyEvent,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): _save,
          const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        },
        child: _PaperDialog(
          surfaceKey: const ValueKey('todo-reminder-dialog-surface'),
          width: 326,
          height: 216,
          radius: 12,
          padding: const EdgeInsets.all(16),
          contentSpacing: 8,
          actionSpacing: 16,
          actionsGap: 6,
          title: strings.get(PaperTodoStringKeys.reminderInterval),
          content: SizedBox(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.get(PaperTodoStringKeys.reminderIntervalMessage),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('todo-reminder-interval-value'),
                          controller: _intervalController,
                          focusNode: _intervalFocusNode,
                          autofocus: true,
                          textAlign: TextAlign.center,
                          textAlignVertical: TextAlignVertical.center,
                          style: const TextStyle(fontSize: 13, height: 1.15),
                          decoration: inputDecoration(),
                          keyboardType: TextInputType.number,
                          onSubmitted: (_) => _save(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 112,
                        child: _TodoDialogDropdown<String>(
                          dropdownKey: const ValueKey(
                            'todo-reminder-interval-unit',
                          ),
                          value: _unit,
                          items: [
                            DropdownMenuItem(
                              value: TodoReminderIntervalUnits.minutes,
                              child: Text(
                                strings.get(PaperTodoStringKeys.minutes),
                              ),
                            ),
                            DropdownMenuItem(
                              value: TodoReminderIntervalUnits.hours,
                              child: Text(
                                strings.get(PaperTodoStringKeys.hours),
                              ),
                            ),
                          ],
                          onChanged: (value) => setState(() => _unit = value),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _cancel,
              style: _todoDialogActionStyle(context),
              child: Text(strings.get(PaperTodoStringKeys.actionCancel)),
            ),
            TextButton(
              onPressed: _clear,
              style: _todoDialogActionStyle(context),
              child: Text(
                strings.get(PaperTodoStringKeys.reminderIntervalGlobal),
              ),
            ),
            FilledButton(
              onPressed: _save,
              style: _todoDialogActionStyle(context, primary: true),
              child: Text(
                strings.get(PaperTodoStringKeys.dialogDueDateConfirm),
              ),
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
    Navigator.of(context).pop(const _ReminderIntervalSelection.clear());
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  void _save() {
    final parsedValue = int.tryParse(_intervalController.text.trim());
    final fallbackValue = (widget.initialValue ?? 10).clamp(1, 240).toInt();
    final rawValue = parsedValue ?? fallbackValue;
    final value = (rawValue <= 0 ? 1 : rawValue).clamp(1, 240).toInt();
    Navigator.of(context).pop(_ReminderIntervalSelection.set(value, _unit));
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

enum _PaperDialogShadowKind { floating, compact }

class _PaperDialog extends StatelessWidget {
  const _PaperDialog({
    required this.title,
    required this.content,
    required this.actions,
    this.icon,
    this.destructive = false,
    this.width = 440,
    this.height,
    this.minWidth = 0,
    this.minHeight = 0,
    this.radius = 18,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
    this.contentSpacing = 14,
    this.actionSpacing = 16,
    this.actionsGap = 8,
    this.titleFontSize = 15,
    this.shadowKind = _PaperDialogShadowKind.floating,
    this.surfaceKey,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final IconData? icon;
  final bool destructive;
  final double width;
  final double? height;
  final double minWidth;
  final double minHeight;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double contentSpacing;
  final double actionSpacing;
  final double actionsGap;
  final double titleFontSize;
  final _PaperDialogShadowKind shadowKind;
  final Key? surfaceKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final accent = destructive ? colors.error : colors.primary;
    final compactShadow = shadowKind == _PaperDialogShadowKind.compact;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        key: surfaceKey,
        constraints: BoxConstraints(
          minWidth: minWidth,
          minHeight: minHeight,
          maxWidth: width,
          maxHeight: height ?? double.infinity,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: colors.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(
                  alpha: compactShadow ? 0.22 : (isDark ? 0.36 : 0.22),
                ),
                blurRadius: compactShadow ? 18 : (isDark ? 26 : 24),
                offset:
                    compactShadow ? const Offset(0, 2) : const Offset(1.4, 1.4),
              ),
            ],
          ),
          child: Padding(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (icon case final icon?) ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SizedBox.square(
                          dimension: 28,
                          child: Icon(icon, size: 17, color: accent),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: contentSpacing),
                if (height == null)
                  content
                else
                  Expanded(
                    child: Align(alignment: Alignment.topLeft, child: content),
                  ),
                SizedBox(height: actionSpacing),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: actionsGap,
                  runSpacing: actionsGap,
                  children: actions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

ButtonStyle _todoDialogActionStyle(
  BuildContext context, {
  bool primary = false,
}) {
  final colors = PaperTodoThemeColors.of(context);
  return TextButton.styleFrom(
    minimumSize: const Size(64, 26),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    backgroundColor: primary ? colors.active : colors.hover,
    foregroundColor: primary ? colors.paper : colors.text,
    textStyle: const TextStyle(fontSize: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
  );
}

class _TodoDialogDropdown<T> extends StatelessWidget {
  const _TodoDialogDropdown({
    required this.dropdownKey,
    required this.value,
    required this.items,
    required this.onChanged,
    this.menuMaxHeight = 220,
  });

  final Key dropdownKey;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;
  final double menuMaxHeight;

  @override
  Widget build(BuildContext context) {
    final colors = PaperTodoThemeColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.tint.withValues(
          alpha: colors.isDark ? 22 / 255 : 12 / 255,
        ),
        border: Border.all(color: colors.tint.withValues(alpha: 80 / 255)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            key: dropdownKey,
            value: value,
            isDense: true,
            isExpanded: true,
            menuMaxHeight: menuMaxHeight,
            borderRadius: BorderRadius.circular(8),
            dropdownColor: colors.paper,
            icon: Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: colors.weakText,
            ),
            style: TextStyle(color: colors.text, fontSize: 13, height: 1.15),
            items: items,
            onChanged: (next) {
              if (next != null) {
                onChanged(next);
              }
            },
          ),
        ),
      ),
    );
  }
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
    return _PaperDialog(
      width: 560,
      icon: Icons.history_outlined,
      title: strings.get(PaperTodoStringKeys.actionRecoverySnapshots),
      content: SizedBox(
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
            return DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.025),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: snapshots.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final record = snapshots[index];
                      return _RecoverySnapshotListItem(
                        record: record,
                        onRestore: () => Navigator.of(context).pop(record),
                        strings: strings,
                      );
                    },
                  ),
                ),
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
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.history_outlined,
            size: 19,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _snapshotSummary(record),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  record.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _snapshotSizeLabel(strings, record),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            key: ValueKey('restore-snapshot-${record.path}'),
            onPressed: onRestore,
            icon: const Icon(Icons.restore_outlined, size: 16),
            label: Text(strings.get(PaperTodoStringKeys.actionRestore)),
          ),
        ],
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
      strings.format(PaperTodoStringKeys.recoverySnapshotModified, [
        _formatSnapshotTime(lastModified),
      ]),
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

class _PaperTodoPopupMenuItem<T> extends PopupMenuItem<T> {
  const _PaperTodoPopupMenuItem({
    super.key,
    super.value,
    super.onTap,
    super.enabled,
    super.height,
    super.padding,
    super.textStyle,
    super.labelTextStyle,
    super.mouseCursor,
    required super.child,
  });

  @override
  PopupMenuItemState<T, _PaperTodoPopupMenuItem<T>> createState() =>
      _PaperTodoPopupMenuItemState<T>();
}

class _PaperTodoPopupMenuItemState<T>
    extends PopupMenuItemState<T, _PaperTodoPopupMenuItem<T>> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final menuTheme = PopupMenuTheme.of(context);
    final states = <WidgetState>{if (!widget.enabled) WidgetState.disabled};
    final style = theme.useMaterial3
        ? widget.labelTextStyle?.resolve(states) ??
            menuTheme.labelTextStyle?.resolve(states) ??
            theme.textTheme.labelLarge!
        : widget.textStyle ??
            menuTheme.textStyle ??
            theme.textTheme.titleMedium!;
    final padding = widget.padding ??
        EdgeInsets.symmetric(horizontal: theme.useMaterial3 ? 12 : 16);
    final item = DefaultTextStyle(
      style: style,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.height),
        child: Padding(
          padding: padding,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: buildChild(),
          ),
        ),
      ),
    );

    return MergeSemantics(
      child: buildSemantics(
        child: InkWell(
          onTap: widget.enabled ? handleTap : null,
          canRequestFocus: widget.enabled,
          mouseCursor:
              widget.mouseCursor ?? menuTheme.mouseCursor?.resolve(states),
          borderRadius: BorderRadius.circular(8),
          hoverColor: theme.hoverColor,
          focusColor: theme.focusColor,
          // The pointer remains hovered while pressed; a second tint would
          // darken PaperTodo's single IsHighlighted surface.
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          child: item,
        ),
      ),
    );
  }
}

class _PaperTodoPopupMenuHeaderLabel extends StatelessWidget {
  const _PaperTodoPopupMenuHeaderLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = PaperTodoThemeColors.of(context);
    return Text(
      label,
      style: TextStyle(
        color: colors.weakText.withValues(alpha: 0.72),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1,
      ),
    );
  }
}

PopupMenuItem<String> _paperTodoMenuHeader(String label) {
  return PopupMenuItem<String>(
    enabled: false,
    height: 28,
    padding: _paperTodoPopupMenuItemPadding,
    child: _PaperTodoPopupMenuHeaderLabel(label),
  );
}

const EdgeInsets _paperTodoPopupMenuItemPadding = EdgeInsets.fromLTRB(
  8,
  4,
  10,
  4,
);

const EdgeInsets _paperTodoStandalonePopupMenuItemPadding = EdgeInsets.fromLTRB(
  8,
  2,
  10,
  2,
);

BoxConstraints _paperTodoStandaloneMenuConstraints(
  BuildContext context,
  List<PopupMenuEntry<String>> entries,
) {
  final theme = Theme.of(context);
  final style = theme.popupMenuTheme.labelTextStyle?.resolve({}) ??
      theme.textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1) ??
      const TextStyle(fontSize: 13, height: 1);
  var widest = 0.0;
  for (final entry in entries) {
    if (entry is! PopupMenuItem<String>) {
      continue;
    }
    final child = entry.child;
    String? value;
    TextStyle? entryStyle;
    if (child is Text) {
      value = child.data;
      entryStyle = child.style;
    } else if (child is _PaperTodoPopupMenuHeaderLabel) {
      value = child.label;
      entryStyle = const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1,
      );
    } else {
      continue;
    }
    if (value == null || value.isEmpty) {
      continue;
    }
    final painter = TextPainter(
      text: TextSpan(text: value, style: entryStyle ?? style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    widest = math.max(widest, painter.width);
  }
  // PaperTodo's menu is content-sized: 4 px menu padding, 8/10 px item
  // padding, and a 1 px border on both sides.
  return BoxConstraints.tightFor(width: (widest + 28).ceilToDouble());
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
    required this.moveCompletedTodosToBottom,
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
    required this.nativeDialogFontFamily,
    required this.collapseAllActive,
    required this.noteLineSpacing,
    required this.syncing,
    required this.onSync,
    required this.onChanged,
    required this.onPersist,
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
  final bool moveCompletedTodosToBottom;
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
  final String nativeDialogFontFamily;
  final bool collapseAllActive;
  final double noteLineSpacing;
  final bool syncing;
  final Future<void> Function() onSync;
  final Future<void> Function() onChanged;
  final Future<void> Function() onPersist;
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
    final paperColors = PaperTodoThemeColors.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mobileBoard =
        !standaloneSurface && MediaQuery.sizeOf(context).shortestSide < 600;
    // The master capsule only retracts or expands the edge capsule queue. It
    // must never become paper state or change the paper body's visibility.
    final isCollapsed = Platform.isWindows && paper.isCollapsed;
    final scriptCapsuleSpec =
        paper.isNote ? ScriptCapsuleSpec.tryParse(paper.content) : null;
    final textZoom = paper.textZoom.clamp(0.5, 1.5).toDouble();
    final desktopInteractionLocked =
        Platform.isWindows && paper.isPinnedToDesktop && !paper.isCollapsed;
    return Semantics(
      label: '$titleText ${paper.type} paper',
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          clipBehavior: standaloneSurface ? Clip.hardEdge : Clip.none,
          child: DecoratedBox(
            key: ValueKey('${paper.id}-paper-surface'),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border.all(color: paperColors.paperBorder),
              borderRadius: BorderRadius.circular(18),
              boxShadow: standaloneSurface
                  ? const <BoxShadow>[]
                  : [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(
                          alpha: isDark ? 0.24 : 0.13,
                        ),
                        blurRadius: 16,
                        offset: const Offset(0, 5),
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
                      color: paperColors.tint.withValues(
                        alpha: isDark ? 18 / 255 : 12 / 255,
                      ),
                      borderRadius: standaloneSurface
                          ? const BorderRadius.vertical(
                              top: Radius.circular(17),
                            )
                          : mobileBoard
                              ? const BorderRadius.vertical(
                                  top: Radius.circular(17),
                                )
                              : null,
                      border: Border(
                        bottom: BorderSide(
                          color: Color.alphaBlend(
                            paperColors.tint.withValues(
                              alpha: isDark ? 34 / 255 : 28 / 255,
                            ),
                            paperColors.paper,
                          ),
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
                          ? 5
                          : mobileBoard
                              ? 4
                              : 5,
                      standaloneSurface
                          ? 8
                          : mobileBoard
                              ? 4
                              : 7,
                      standaloneSurface
                          ? 1
                          : mobileBoard
                              ? 3
                              : 5,
                    ),
                    child: Semantics(
                      label: standaloneSurface
                          ? PaperTodoStringsScope.of(
                              context,
                            ).get(PaperTodoStringKeys.actionMovePaperWindow)
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
                              _handlePaperContextMenuPointerDown(
                            context,
                            event,
                          ),
                          child: LayoutBuilder(
                            builder: (context, headerConstraints) {
                              return Row(
                                children: [
                                  if (standaloneSurface)
                                    _paperWindowLeadingAction(
                                      context,
                                      scriptCapsuleSpec: scriptCapsuleSpec,
                                    )
                                  else
                                    SizedBox.square(
                                      dimension: mobileBoard ? 40 : 24,
                                      child: Icon(
                                        paper.isTodo
                                            ? (paper.items.isNotEmpty &&
                                                    paper.items.every(
                                                      (item) => item.done,
                                                    )
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
                                  if (!standaloneSurface)
                                    const SizedBox(width: 5),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minWidth: standaloneSurface ? 38 : 0,
                                          maxWidth: standaloneSurface
                                              ? 86
                                              : double.infinity,
                                        ),
                                        child: _PaperTitleEditor(
                                          paper: paper,
                                          titleText: titleText,
                                          maxTitleLength: maxTitleLength,
                                          textZoom: textZoom,
                                          enabled: !desktopInteractionLocked &&
                                              !isCollapsed,
                                          fieldEnabled:
                                              !desktopInteractionLocked,
                                          enableToolTips: enableToolTips,
                                          compact: standaloneSurface,
                                          onTitleChanged: onTitleChanged,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (standaloneSurface) ...[
                                    ..._paperWindowHeaderActions(
                                      context: context,
                                      isCollapsed: isCollapsed,
                                      desktopInteractionLocked:
                                          desktopInteractionLocked,
                                      availableWidth:
                                          headerConstraints.maxWidth,
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
                              );
                            },
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
                  if (standaloneSurface && paper.isNote)
                    Expanded(
                      child: Padding(
                        key: ValueKey('${paper.id}-standalone-note-body'),
                        padding: const EdgeInsets.only(top: 2),
                        child: AbsorbPointer(
                          absorbing: desktopInteractionLocked,
                          child: _animatedPaperBody(
                            isCollapsed,
                            scriptCapsuleSpec,
                            fillAvailable: true,
                          ),
                        ),
                      ),
                    )
                  else if (standaloneSurface)
                    Expanded(
                      child: _PaperTodoScrollViewport(
                        key: ValueKey('${paper.id}-todo-scroll-viewport'),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return SizedBox(
                              width: math.max(0, constraints.maxWidth - 14),
                              child: AbsorbPointer(
                                absorbing: desktopInteractionLocked,
                                child: _animatedPaperBody(
                                  isCollapsed,
                                  scriptCapsuleSpec,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: mobileBoard
                          ? const EdgeInsets.fromLTRB(8, 4, 8, 8)
                          : const EdgeInsets.fromLTRB(7, 3, 7, 7),
                      child: AbsorbPointer(
                        absorbing: desktopInteractionLocked,
                        child: _animatedPaperBody(
                          isCollapsed,
                          scriptCapsuleSpec,
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
  }

  Widget _noteLinkDragHandle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = PaperTodoStringsScope.of(context);
    final dragLabel = strings.get(
      PaperTodoStringKeys.actionDragToLinkNoteToTodo,
    );
    final handle = Semantics(
      label: dragLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: SizedBox.square(
          key: ValueKey('${paper.id}-note-link-drag-handle'),
          dimension: standaloneSurface ? 24 : 48,
          child: standaloneSurface
              ? Text(
                  '\u2316',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Segoe UI Symbol',
                    fontFamilyFallback: const <String>['Segoe UI Emoji'],
                    fontSize: 13,
                    color: colorScheme.primary,
                    height: 1,
                  ),
                )
              : Icon(Icons.link_outlined, size: 16, color: colorScheme.primary),
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
                if (!standaloneSurface)
                  Icon(
                    Icons.link_outlined,
                    size: 16,
                    color: colorScheme.onPrimaryContainer,
                  )
                else
                  Text(
                    '\u2316',
                    style: TextStyle(
                      fontFamily: 'Segoe UI Symbol',
                      fontFamilyFallback: const <String>['Segoe UI Emoji'],
                      fontSize: 13,
                      color: colorScheme.onPrimaryContainer,
                      height: 1,
                    ),
                  ),
                const SizedBox(width: 6),
                Text(
                  strings.format(PaperTodoStringKeys.actionLinkPaper, [
                    _displayPaperTitle(),
                  ]),
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
    ScriptCapsuleSpec? scriptCapsuleSpec, {
    bool fillAvailable = false,
  }) {
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
                  moveCompletedTodosToBottom: moveCompletedTodosToBottom,
                  enableToolTips: enableToolTips,
                  enableAnimations: enableAnimations,
                  visualSize: todoVisualSize,
                  lineSpacing: todoLineSpacing,
                  textZoom: paper.textZoom,
                  showDueRelativeTime: showTodoDueRelativeTime,
                  dueYearDisplayMode: todoDueYearDisplayMode,
                  defaultReminderIntervalValue:
                      defaultTodoReminderIntervalValue,
                  defaultReminderIntervalUnit: defaultTodoReminderIntervalUnit,
                  nativeDialogFontFamily: nativeDialogFontFamily,
                  onOpenLinkedNote: onOpenLinkedNote,
                  onRunScriptCapsule: onRunScriptCapsule,
                  onChanged: onChanged,
                  onPersist: onPersist,
                  onItemDeleted: onTodoItemDeleted,
                  onItemRestored: onTodoItemRestored,
                  onReminderReset: onTodoReminderReset,
                  standaloneSurface: standaloneSurface,
                )
              else if (fillAvailable)
                Expanded(child: _noteEditor())
              else
                _noteEditor(),
            ],
          );
    // Native paper HWNDs animate their own geometry. Cross-fading the Flutter
    // subtree at the same time exposes a transient blank frame during resize,
    // pin and capsule transitions.
    if (!enableAnimations || standaloneSurface) {
      return body;
    }
    return AnimatedSwitcher(
      key: ValueKey('${paper.id}-body-animation'),
      duration: PaperTodoMotion.fadeOut,
      switchInCurve: PaperTodoMotion.enterCurve,
      switchOutCurve: PaperTodoMotion.exitCurve,
      transitionBuilder: (child, animation) {
        return ClipRect(
          child: SizeTransition(
            sizeFactor: animation,
            alignment: AlignmentDirectional.topStart,
            child: child,
          ),
        );
      },
      child: body,
    );
  }

  Widget _noteEditor() {
    return _NoteEditor(
      paper: paper,
      markdownRenderMode: markdownRenderMode,
      lineSpacing: noteLineSpacing,
      textZoom: paper.textZoom,
      enableToolTips: enableToolTips,
      onOpenUri: onOpenUri,
      onChanged: onChanged,
      onTextZoomChanged: _setTextZoom,
      onShowPaperContextMenu: _showPaperContextMenu,
      standaloneSurface: standaloneSurface,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
                          strings.format(PaperTodoStringKeys.actionRunPaper, [
                            _displayPaperTitle(),
                          ]),
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
    final hideThisPaperLabel = strings.get(
      PaperTodoStringKeys.actionHideThisPaper,
    );
    final openMarkdownEditorLabel = _openMarkdownEditorLabel(strings);
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    if (compact) {
      return [
        if (useCapsuleMode)
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
                  height: _paperTodoPopupMenuHeight(),
                  padding: _paperTodoPopupMenuItemPadding,
                  child: Text(
                    '${strings.get(PaperTodoStringKeys.zoom)} '
                    '${option.label}',
                  ),
                ),
              if (Platform.isWindows) ...[
                const PopupMenuDivider(),
                _paperActionMenuItem(
                  value: _compactPaperActionToggleAlwaysOnTop,
                  icon: paper.alwaysOnTop
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                  label: paper.alwaysOnTop
                      ? strings.get(
                          PaperTodoStringKeys.actionDisableAlwaysOnTop,
                        )
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
                  label: strings.get(
                    PaperTodoStringKeys.actionSaveWindowBounds,
                  ),
                ),
              ],
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
          tooltip: _tooltipLabel(enableToolTips, openMarkdownEditorLabel),
          onPressed: () => unawaited(onOpenExternalMarkdown(paper)),
          icon: const Icon(Icons.file_open_outlined),
        ),
      if (useCapsuleMode) _collapseButton(context, isCollapsed),
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
                height: _paperTodoPopupMenuHeight(),
                padding: _paperTodoPopupMenuItemPadding,
                child: Text(option.label),
              ),
          ];
        },
      ),
      if (Platform.isWindows)
        IconButton(
          tooltip: _tooltipLabel(
            enableToolTips,
            paper.alwaysOnTop
                ? strings.get(PaperTodoStringKeys.actionDisableAlwaysOnTop)
                : strings.get(PaperTodoStringKeys.actionKeepOnTop),
          ),
          onPressed: _toggleAlwaysOnTop,
          icon: Icon(
            paper.alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
          ),
        ),
      if (Platform.isWindows)
        IconButton(
          tooltip: _tooltipLabel(
            enableToolTips,
            paper.isPinnedToDesktop
                ? strings.get(PaperTodoStringKeys.actionUnpinFromDesktop)
                : strings.get(PaperTodoStringKeys.actionPinToDesktop),
          ),
          onPressed: _togglePinnedToDesktop,
          icon: Icon(
            paper.isPinnedToDesktop
                ? Icons.desktop_windows
                : Icons.desktop_windows_outlined,
          ),
        ),
      if (Platform.isWindows)
        IconButton(
          tooltip: _tooltipLabel(
            enableToolTips,
            strings.get(PaperTodoStringKeys.actionSaveWindowBounds),
          ),
          onPressed: () => unawaited(onCaptureBounds(paper)),
          icon: const Icon(Icons.aspect_ratio_outlined),
        ),
      IconButton(
        tooltip: _tooltipLabel(enableToolTips, hideThisPaperLabel),
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

  // Kept temporarily for state-file/widget compatibility while the new paper
  // chrome rolls out; no runtime path calls this legacy composition.
  // ignore: unused_element
  List<Widget> _standalonePaperHeaderActions({
    required BuildContext context,
    required bool isCollapsed,
    required bool desktopInteractionLocked,
  }) {
    if (desktopInteractionLocked) {
      return [_pinnedDesktopUnlockButton(context)];
    }
    final strings = PaperTodoStringsScope.of(context);
    final width = math.min(MediaQuery.sizeOf(context).width, paper.width);
    final showPrimaryActions = width >= 225;
    final showSecondaryActions = width >= 285;
    final showCreationActions = width >= (paper.isNote ? 390 : 340);
    final actions = <Widget>[
      if (showCreationActions && showTopBarNewTodoButton)
        _standaloneHeaderButton(
          key: ValueKey('${paper.id}-new-todo'),
          tooltip: strings.get(PaperTodoStringKeys.actionNewTodoPaper),
          onPressed: () =>
              unawaited(onCreatePaper(PaperTypes.todo, sourcePaper: paper)),
          child: const Text(
            '+✓',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
      if (showCreationActions && showTopBarNewNoteButton)
        _standaloneHeaderButton(
          key: ValueKey('${paper.id}-new-note'),
          tooltip: strings.get(PaperTodoStringKeys.actionNewNotePaper),
          onPressed: () =>
              unawaited(onCreatePaper(PaperTypes.note, sourcePaper: paper)),
          child: const Text(
            '+✎',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
      if (showSecondaryActions && paper.isNote && enableTodoNoteLinks)
        SizedBox(width: 24, height: 24, child: _noteLinkDragHandle(context)),
      if (showSecondaryActions && paper.isNote && showTopBarExternalOpenButton)
        _standaloneHeaderButton(
          key: ValueKey('${paper.id}-open-markdown'),
          tooltip: _openMarkdownEditorLabel(strings),
          onPressed: () => unawaited(onOpenExternalMarkdown(paper)),
          child: const Text(
            'MD',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w400,
              height: 1,
            ),
          ),
        ),
      if (showSecondaryActions)
        _standaloneHeaderButton(
          key: ValueKey('${paper.id}-sync-now'),
          tooltip: strings.get(PaperTodoStringKeys.actionSyncNow),
          onPressed: syncing ? null : () => unawaited(onSync()),
          child: syncing
              ? const SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              : const Icon(Icons.sync_outlined, size: 15),
        ),
      if (showPrimaryActions)
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

  List<Widget> _paperWindowHeaderActions({
    required BuildContext context,
    required bool isCollapsed,
    required bool desktopInteractionLocked,
    required double availableWidth,
  }) {
    final strings = PaperTodoStringsScope.of(context);
    if (desktopInteractionLocked) {
      return [
        _paperWindowHeaderButton(
          context,
          key: ValueKey('${paper.id}-desktop-pin'),
          tooltip: strings.get(PaperTodoStringKeys.actionUnpinFromDesktop),
          onPressed: _togglePinnedToDesktop,
          child: _paperTodoDesktopPinGlyph(pinned: true),
        ),
      ];
    }
    final width = availableWidth;
    final showBaseActions = width >= (paper.isNote ? 230 : 180);
    final showUtility = width >= 210;
    final showSync = width >= 400;
    return [
      if (showSync)
        _paperWindowHeaderButton(
          context,
          key: ValueKey('${paper.id}-sync-now'),
          tooltip: strings.get(PaperTodoStringKeys.actionSyncNow),
          onPressed: syncing ? null : () => unawaited(onSync()),
          child: syncing
              ? const SizedBox.square(
                  dimension: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              : const Icon(Icons.sync_rounded, size: 16),
        ),
      if (showUtility && paper.isNote && enableTodoNoteLinks)
        SizedBox(
          key: ValueKey('${paper.id}-note-link-drag-action'),
          width: 24,
          height: 24,
          child: _noteLinkDragHandle(context),
        ),
      if (showUtility && paper.isNote && showTopBarExternalOpenButton)
        _paperWindowHeaderButton(
          context,
          key: ValueKey('${paper.id}-open-markdown'),
          tooltip: _openMarkdownEditorLabel(strings),
          onPressed: () => unawaited(onOpenExternalMarkdown(paper)),
          child: const Text(
            'MD',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w400,
              height: 1,
            ),
          ),
        ),
      if (showBaseActions)
        _paperWindowHeaderButton(
          context,
          key: ValueKey('${paper.id}-desktop-pin'),
          tooltip: paper.isPinnedToDesktop
              ? strings.get(PaperTodoStringKeys.actionUnpinFromDesktop)
              : strings.get(PaperTodoStringKeys.actionPinToDesktop),
          onPressed: _togglePinnedToDesktop,
          child: _paperTodoDesktopPinGlyph(pinned: paper.isPinnedToDesktop),
        ),
      if (showBaseActions && showTopBarNewTodoButton)
        _paperWindowHeaderButton(
          context,
          key: ValueKey('${paper.id}-new-todo'),
          tooltip: strings.get(PaperTodoStringKeys.actionNewTodoPaper),
          onPressed: () =>
              unawaited(onCreatePaper(PaperTypes.todo, sourcePaper: paper)),
          child: Transform.translate(
            key: const ValueKey('paper-window-new-todo-glyph-metrics'),
            offset: const Offset(-1, 1),
            child: const Text(
              '\uFF0B\u2713',
              style: TextStyle(
                fontFamily: 'Segoe UI Symbol',
                fontFamilyFallback: <String>['Segoe UI Emoji'],
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
      if (showBaseActions && showTopBarNewNoteButton)
        _paperWindowHeaderButton(
          context,
          key: ValueKey('${paper.id}-new-note'),
          tooltip: strings.get(PaperTodoStringKeys.actionNewNotePaper),
          onPressed: () =>
              unawaited(onCreatePaper(PaperTypes.note, sourcePaper: paper)),
          child: Transform.translate(
            key: const ValueKey('paper-window-new-note-glyph-metrics'),
            offset: const Offset(-1, 1),
            child: const Text(
              '\uFF0B\u270E',
              style: TextStyle(
                fontFamily: 'Segoe UI Symbol',
                fontFamilyFallback: <String>['Segoe UI Emoji'],
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1,
                letterSpacing: -0.75,
              ),
            ),
          ),
        ),
      _paperWindowHeaderButton(
        context,
        key: ValueKey('${paper.id}-close'),
        tooltip: useCapsuleMode
            ? strings.get(PaperTodoStringKeys.actionCollapsePaper)
            : strings.get(PaperTodoStringKeys.actionHideThisPaper),
        onPressed:
            useCapsuleMode ? _toggleCollapsed : () => unawaited(onHide(paper)),
        child: Transform.translate(
          key: const ValueKey('paper-window-close-glyph-metrics'),
          offset: const Offset(-1, 1),
          child: Text(
            useCapsuleMode ? '\u2500' : '\u00D7',
            style: const TextStyle(
              fontFamily: 'Segoe UI Symbol',
              fontFamilyFallback: <String>['Segoe UI Emoji'],
              fontSize: 16,
              height: 1,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _paperTodoDesktopPinGlyph({required bool pinned, double size = 15}) {
    return Transform.translate(
      key: const ValueKey('paper-window-desktop-pin-glyph-metrics'),
      offset: const Offset(-2, 0),
      child: Opacity(
        key: const ValueKey('paper-window-desktop-pin-glyph-opacity'),
        opacity: pinned ? 1 : 0.72,
        child: Image.asset(
          pinned ? 'assets/icons/unpin.png' : 'assets/icons/pin.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
        ),
      ),
    );
  }

  Widget _paperWindowLeadingAction(
    BuildContext context, {
    required ScriptCapsuleSpec? scriptCapsuleSpec,
  }) {
    final strings = PaperTodoStringsScope.of(context);
    final paperColors = PaperTodoThemeColors.of(context);
    final active = paper.alwaysOnTop;
    return _paperWindowHeaderButton(
      context,
      key: ValueKey('${paper.id}-topmost'),
      width: 23,
      tooltip: active
          ? strings.get(PaperTodoStringKeys.actionDisableAlwaysOnTop)
          : strings.get(PaperTodoStringKeys.actionKeepOnTop),
      onPressed: _desktopInteractionLocked ? null : _toggleAlwaysOnTop,
      child: _PaperWindowTopmostGlyph(
        active: active,
        enabled: !_desktopInteractionLocked,
        glyph: paper.isTodo ? '\u2611' : '\u270E',
        size: paper.isNote ? 15 : 13,
        activeColor: paperColors.text,
        inactiveColor: paperColors.weakText,
      ),
    );
  }

  Widget _paperWindowHeaderButton(
    BuildContext context, {
    Key? key,
    double width = 28,
    double height = 24,
    required String tooltip,
    required VoidCallback? onPressed,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: SizedBox(
        key: key,
        width: width,
        height: height,
        child: _conditionalTooltip(
          enabled: enableToolTips,
          message: tooltip,
          child: _PaperWindowHeaderAction(onPressed: onPressed, child: child),
        ),
      ),
    );
  }

  // ignore: unused_element
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
        paper.isCollapsed
            ? strings.get(PaperTodoStringKeys.actionExpandPaper)
            : strings.get(PaperTodoStringKeys.actionCollapsePaper),
      ),
      onPressed: _toggleCollapsed,
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
    final entries = _paperContextMenuItems(context);
    final selected = await showMenu<String>(
      context: context,
      requestFocus: false,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy + 1, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: entries,
      constraints: standaloneSurface
          ? _paperTodoStandaloneMenuConstraints(context, entries)
          : null,
    );
    if (!context.mounted || selected == null) {
      return;
    }
    _handleCompactPaperAction(selected);
  }

  List<PopupMenuEntry<String>> _paperContextMenuItems(BuildContext context) {
    final strings = PaperTodoStringsScope.of(context);
    if (standaloneSurface) {
      return _standalonePaperContextMenuItems(strings);
    }
    final hideThisPaperLabel = strings.get(
      PaperTodoStringKeys.actionHideThisPaper,
    );
    final openMarkdownEditorLabel = _openMarkdownEditorLabel(strings);
    final textZoom = paper.textZoom.clamp(0.5, 1.5).toDouble();
    if (_desktopInteractionLocked) {
      return [
        _paperTodoMenuHeader(strings.get(PaperTodoStringKeys.menuDesktopPin)),
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
          height: _paperTodoPopupMenuHeight(),
          padding: _paperTodoPopupMenuItemPadding,
          child: Text(
            '${strings.get(PaperTodoStringKeys.zoom)} '
            '${option.label}',
          ),
        ),
      if (Platform.isWindows) ...[
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
      ],
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

  List<PopupMenuEntry<String>> _standalonePaperContextMenuItems(
    PaperTodoStrings strings,
  ) {
    final scriptCapsule =
        paper.isNote ? ScriptCapsuleSpec.tryParse(paper.content) : null;
    return [
      _paperTodoDesktopMenuHeader(strings.get(PaperTodoStringKeys.menuNew)),
      _paperTodoDesktopMenuItem(
        value: _compactPaperActionNewTodo,
        label: strings.get(PaperTodoStringKeys.actionNewTodoPaperCompact),
      ),
      _paperTodoDesktopMenuItem(
        value: _compactPaperActionNewNote,
        label: strings.get(PaperTodoStringKeys.actionNewNotePaperCompact),
      ),
      if (paper.isTodo) ...[
        const PopupMenuDivider(height: 7),
        _paperTodoDesktopMenuHeader(strings.get(PaperTodoStringKeys.menuTodo)),
        _paperTodoDesktopMenuItem(
          value: _compactPaperActionClearDone,
          label: strings.get(PaperTodoStringKeys.actionClearCompleted),
        ),
      ],
      if (_canAddCanvasBlockFromPaperMenu) ...[
        const PopupMenuDivider(height: 7),
        _paperTodoDesktopMenuHeader(
          strings.get(PaperTodoStringKeys.menuCanvas),
        ),
        _paperTodoDesktopMenuItem(
          value: _compactPaperActionAddCanvasBlock,
          label: strings.get(PaperTodoStringKeys.actionAddCodeBlock),
        ),
      ],
      const PopupMenuDivider(height: 7),
      _paperTodoDesktopMenuHeader(
        strings.get(PaperTodoStringKeys.menuDesktopPin),
      ),
      if (!paper.isCollapsed && !paper.isPinnedToDesktop)
        _paperTodoDesktopMenuItem(
          value: _compactPaperActionTogglePinned,
          label: strings.get(PaperTodoStringKeys.actionPinToDesktop),
        ),
      const PopupMenuDivider(height: 7),
      _paperTodoDesktopMenuHeader(_displayPaperTitle()),
      if (useCapsuleMode)
        _paperTodoDesktopMenuItem(
          value: _compactPaperActionToggleCollapsed,
          label: scriptCapsule != null && paper.isCollapsed
              ? strings.get(PaperTodoStringKeys.actionEditScriptCapsule)
              : paper.isCollapsed
                  ? strings.get(PaperTodoStringKeys.actionRestoreWindow)
                  : strings.get(PaperTodoStringKeys.actionCollapseToCapsule),
        ),
      _paperTodoDesktopMenuItem(
        value: _compactPaperActionHide,
        label: strings.get(PaperTodoStringKeys.actionHideCompact),
      ),
      _paperTodoDesktopMenuItem(
        value: _compactPaperActionDelete,
        label: strings.get(PaperTodoStringKeys.actionDelete),
      ),
    ];
  }

  PopupMenuItem<String> _paperTodoDesktopMenuHeader(String label) {
    return PopupMenuItem<String>(
      enabled: false,
      height: 17,
      padding: _paperTodoStandalonePopupMenuItemPadding,
      child: _PaperTodoPopupMenuHeaderLabel(label),
    );
  }

  PopupMenuItem<String> _paperTodoDesktopMenuItem({
    required String value,
    required String label,
  }) {
    return _PaperTodoPopupMenuItem<String>(
      value: value,
      height: 21,
      padding: _paperTodoStandalonePopupMenuItemPadding,
      child: Text(label),
    );
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
      padding: _paperTodoPopupMenuItemPadding,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
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

class _PaperWindowHeaderAction extends StatefulWidget {
  const _PaperWindowHeaderAction({
    required this.onPressed,
    required this.child,
  });

  final VoidCallback? onPressed;
  final Widget child;

  @override
  State<_PaperWindowHeaderAction> createState() =>
      _PaperWindowHeaderActionState();
}

class _PaperWindowHeaderActionState extends State<_PaperWindowHeaderAction> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant _PaperWindowHeaderAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null) {
      _hovered = false;
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final paperColors = PaperTodoThemeColors.of(context);
    final enabled = widget.onPressed != null;
    final disabledForeground = colors.onSurfaceVariant.withValues(alpha: 0.30);
    final foreground = enabled
        ? (_hovered || _pressed ? paperColors.text : paperColors.weakText)
        : disabledForeground;
    final baseStyle = IconButton.styleFrom(
      foregroundColor: foreground,
      disabledForegroundColor: disabledForeground,
      hoverColor: paperColors.hover,
      highlightColor: paperColors.hover,
      splashFactory: NoSplash.splashFactory,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    return MouseRegion(
      onEnter: enabled ? (_) => _setHovered(true) : null,
      onExit: enabled
          ? (_) {
              _setHovered(false);
              _clearPressed();
            }
          : null,
      child: Listener(
        onPointerDown: enabled
            ? (event) {
                if (event.buttons & kPrimaryMouseButton != 0 && !_pressed) {
                  setState(() => _pressed = true);
                }
              }
            : null,
        onPointerUp: enabled ? (_) => _clearPressed() : null,
        onPointerCancel: enabled ? (_) => _clearPressed() : null,
        child: Opacity(
          opacity: _pressed ? 0.7 : 1,
          child: ExcludeFocus(
            child: IconButton(
              onPressed: widget.onPressed,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              style: baseStyle.copyWith(
                foregroundColor: WidgetStateProperty.resolveWith<Color?>((
                  states,
                ) {
                  if (!enabled || states.contains(WidgetState.disabled)) {
                    return disabledForeground;
                  }
                  if (_hovered ||
                      _pressed ||
                      states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.pressed)) {
                    return paperColors.text;
                  }
                  return paperColors.weakText;
                }),
              ),
              icon: IconTheme.merge(
                data: IconThemeData(color: foreground),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: foreground),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (_hovered != value) {
      setState(() => _hovered = value);
    }
  }

  void _clearPressed() {
    if (_pressed) {
      setState(() => _pressed = false);
    }
  }
}

class _PaperWindowTopmostGlyph extends StatefulWidget {
  const _PaperWindowTopmostGlyph({
    required this.active,
    required this.enabled,
    required this.glyph,
    required this.size,
    required this.activeColor,
    required this.inactiveColor,
  });

  final bool active;
  final bool enabled;
  final String glyph;
  final double size;
  final Color activeColor;
  final Color inactiveColor;

  @override
  State<_PaperWindowTopmostGlyph> createState() =>
      _PaperWindowTopmostGlyphState();
}

class _PaperWindowTopmostGlyphState extends State<_PaperWindowTopmostGlyph> {
  bool _hovered = false;

  @override
  void didUpdateWidget(covariant _PaperWindowTopmostGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _hovered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _hovered = false) : null,
      child: Opacity(
        key: const ValueKey('paper-window-topmost-glyph-opacity'),
        opacity: widget.active || _hovered ? 1 : 0.58,
        child: Transform.translate(
          key: const ValueKey('paper-window-topmost-glyph-metrics'),
          offset: const Offset(1, 1),
          child: Text(
            widget.glyph,
            style: TextStyle(
              fontFamily: 'Segoe UI Symbol',
              fontFamilyFallback: const <String>['Segoe UI Emoji'],
              fontSize: widget.size,
              fontWeight: widget.active ? FontWeight.w600 : FontWeight.normal,
              color: widget.active ? widget.activeColor : widget.inactiveColor,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperTodoScrollViewport extends StatefulWidget {
  const _PaperTodoScrollViewport({required this.child, super.key});

  final Widget child;

  @override
  State<_PaperTodoScrollViewport> createState() =>
      _PaperTodoScrollViewportState();
}

class _PaperTodoScrollViewportState extends State<_PaperTodoScrollViewport> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      key: const ValueKey('todo-paper-scrollbar'),
      controller: _controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        key: const ValueKey('todo-paper-scroll'),
        controller: _controller,
        padding: const EdgeInsets.fromLTRB(7, 2, 7, 10),
        child: widget.child,
      ),
    );
  }
}

class _PaperTitleEditor extends StatefulWidget {
  const _PaperTitleEditor({
    required this.paper,
    required this.titleText,
    required this.maxTitleLength,
    required this.textZoom,
    required this.enabled,
    required this.fieldEnabled,
    required this.enableToolTips,
    this.compact = false,
    required this.onTitleChanged,
  });

  final PaperData paper;
  final String titleText;
  final int maxTitleLength;
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
  bool _isHovered = false;
  String _titleBeforeEdit = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _editableTitle);
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
    if (!widget.enabled) {
      _isHovered = false;
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
    final paperColors = PaperTodoThemeColors.of(context);
    final strings = PaperTodoStringsScope.of(context);
    final editTitleLabel = strings.get(PaperTodoStringKeys.actionEditTitle);
    final emphasized = _isEditingTitle || _isHovered;
    final dividerColor = paperColors.tint.withValues(
      alpha: paperColors.isDark ? 34 / 255 : 28 / 255,
    );
    final titleStyle = (widget.compact
            ? theme.textTheme.labelMedium
            : theme.textTheme.titleMedium)
        ?.apply(fontSizeFactor: widget.textZoom)
        .copyWith(
          height: 1,
          fontSize: widget.compact ? 11 : null,
          fontWeight: widget.compact ? FontWeight.w600 : null,
          letterSpacing: widget.compact ? -0.1 : null,
        );
    final field = AnimatedContainer(
      key: ValueKey('${widget.paper.id}-title-host'),
      // PaperTodo changes title hover/focus tint immediately; animated
      // interpolation here leaves a visible trail during desktop pointer
      // movement and is not part of the source interaction.
      duration: Duration.zero,
      height: widget.compact ? 24 : 28,
      padding: widget.compact
          ? const EdgeInsets.fromLTRB(4, 0, 5, 0)
          : const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: emphasized ? paperColors.hover : Colors.transparent,
        border: widget.compact
            ? Border(bottom: BorderSide(color: dividerColor))
            : Border.all(color: emphasized ? dividerColor : Colors.transparent),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: Transform.translate(
          key: ValueKey('${widget.paper.id}-title-wpf-metrics'),
          offset: widget.compact ? const Offset(1, 1) : Offset.zero,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned.fill(
                child: Visibility(
                  key: ValueKey('${widget.paper.id}-title-display-layer'),
                  visible: !_isEditingTitle,
                  maintainState: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.enabled ? _beginTitleEdit : null,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: RichText(
                        key: ValueKey('${widget.paper.id}-title-display'),
                        text: TextSpan(text: _displayTitle, style: titleStyle),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        textScaler: MediaQuery.textScalerOf(context),
                      ),
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                ignoring: !widget.enabled,
                child: Opacity(
                  opacity: _isEditingTitle ? 1 : 0,
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
                    style: titleStyle,
                    onTap: _beginTitleEdit,
                    onChanged: _handleTitleChanged,
                    onFieldSubmitted: (_) =>
                        unawaited(_endTitleEdit(commit: true)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final titleHostContent = Semantics(
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
          onEnter:
              widget.enabled ? (_) => setState(() => _isHovered = true) : null,
          onExit:
              widget.enabled ? (_) => setState(() => _isHovered = false) : null,
          child: field,
        ),
      ),
    );
    if (!widget.compact) {
      return titleHostContent;
    }
    final titleMeasure = TextPainter(
      text: TextSpan(text: _displayTitle, style: titleStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    // WPF's Segoe UI title metrics are narrower than Flutter's fallback at
    // the narrow reference width. Wider paper windows restore the title's
    // natural measured width just like the source title host.
    final metricScale = MediaQuery.sizeOf(context).width <= 280 ? 0.8 : 1.0;
    final compactWidth = (titleMeasure.width * metricScale + 9).clamp(
      41.0,
      86.0,
    );
    return SizedBox(width: compactWidth, child: titleHostContent);
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
    final title = _editableTitle;
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
    final title = _editableTitle;
    if (_controller.text == title) {
      return;
    }
    _controller.value = TextEditingValue(
      text: title,
      selection: TextSelection.collapsed(offset: title.length),
    );
  }

  String get _displayTitle {
    // Keep board paper titles editable/readable in full.  Standalone paper
    // windows use the configurable compact caption limit, matching the native
    // PaperTodo capsule/title surface without truncating the stored value.
    if (!widget.compact) {
      return _editableTitle;
    }
    return PaperTitles.shorten(
      _editableTitle,
      PaperTitles.normalizeMaxTitleLength(widget.maxTitleLength),
    );
  }

  String get _editableTitle {
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
    required this.standaloneSurface,
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
  final bool standaloneSurface;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NotePaperGridPainter extends CustomPainter {
  const _NotePaperGridPainter({required this.color});

  final Color color;
  final double spacing = 24;
  final double verticalLineOffset = 1;
  final double horizontalLineOffset = -1;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..isAntiAlias = false;
    for (var x = verticalLineOffset; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = horizontalLineOffset; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NotePaperGridPainter oldDelegate) {
    return oldDelegate.color != color;
  }
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

  late final PaperTodoMarkdownTextEditingController _contentController;
  late final ScrollController _contentScrollController;
  late final ScrollController _previewScrollController;
  late final FocusNode _contentFocusNode;
  late String _view = _defaultView(widget.markdownRenderMode, widget.paper);
  bool _toolbarInteractionActive = false;
  bool _enteringEditorFromPreview = false;
  bool _previewLinkActivated = false;
  bool _zoomOverlayHovered = false;
  bool _canvasAddButtonHovered = false;
  bool _canvasAddButtonPressed = false;
  String? _selectedCanvasElementId;

  PaperTodoStrings get strings => PaperTodoStringsScope.of(context);

  @override
  void initState() {
    super.initState();
    _contentController = PaperTodoMarkdownTextEditingController(
      text: widget.paper.content,
      markdownEnabled:
          MarkdownRenderModes.normalize(widget.markdownRenderMode) !=
              MarkdownRenderModes.off,
    );
    _contentScrollController = ScrollController();
    _previewScrollController = ScrollController();
    _contentFocusNode = FocusNode();
    _contentFocusNode.addListener(_handleEditorFocusChange);
  }

  @override
  void didUpdateWidget(covariant _NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.textZoom - 1).abs() < 0.001 || widget.paper.isPinnedToDesktop) {
      _zoomOverlayHovered = false;
    }
    if (oldWidget.markdownRenderMode != widget.markdownRenderMode) {
      _contentController.setMarkdownEnabled(
        MarkdownRenderModes.normalize(widget.markdownRenderMode) !=
            MarkdownRenderModes.off,
      );
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
    _previewScrollController.dispose();
    _contentScrollController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = MarkdownRenderModes.normalize(widget.markdownRenderMode);
    final view = mode == MarkdownRenderModes.off ? _viewEdit : _safeView(mode);
    final page = _notePaperSurface(
      view == _viewPreview
          ? _preview(context)
          : _editor(context, minLines: 4, maxLines: 12),
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _noteCanvasToolbar(),
        if (widget.standaloneSurface) Expanded(child: page) else page,
        _noteStatusBar(context, view),
      ],
    );
    if ((widget.textZoom - 1).abs() < 0.001) {
      return body;
    }
    return Stack(
      children: [
        body,
        Positioned(right: 12, bottom: 7, child: _noteTextZoomOverlay()),
      ],
    );
  }

  Widget _noteCanvasToolbar() {
    final colorScheme = Theme.of(context).colorScheme;
    final paperColors = PaperTodoThemeColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: const ValueKey('note-canvas-toolbar'),
      constraints: const BoxConstraints(minHeight: 31),
      padding: const EdgeInsets.fromLTRB(9, 3, 9, 4),
      decoration: BoxDecoration(
        color: paperColors.tint.withValues(alpha: isDark ? 16 / 255 : 10 / 255),
        border: Border(
          bottom: BorderSide(
            color: paperColors.tint.withValues(
              alpha: isDark ? 34 / 255 : 28 / 255,
            ),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            children: [
              _addCanvasButton(),
              const Spacer(),
              Text(
                _noteCanvasElementCountText(),
                key: const ValueKey('note-canvas-element-count'),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _notePaperSurface(Widget child) {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final paperColors = PaperTodoThemeColors.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final minimumPageHeight = widget.standaloneSurface
        ? 0.0
        : math.max(160.0, widget.paper.height - 150);
    return Container(
      key: const ValueKey('note-paper-canvas'),
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      decoration: BoxDecoration(
        color: paperColors.tint.withValues(alpha: isDark ? 0.055 : 0.035),
        border: Border.all(
          color: paperColors.tint.withValues(
            alpha: isDark ? 34 / 255 : 28 / 255,
          ),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: CustomPaint(
          key: const ValueKey('note-paper-grid'),
          painter: _NotePaperGridPainter(
            color: paperColors.tint.withValues(
              alpha: isDark ? 24 / 255 : 18 / 255,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minimumPageHeight),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 14,
                        top: 14,
                        bottom: 14,
                        child: Container(
                          key: const ValueKey('note-paper-binding-line'),
                          width: 2,
                          decoration: BoxDecoration(
                            color: paperColors.tint.withValues(
                              alpha: isDark ? 88 / 255 : 104 / 255,
                            ),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                      if (widget.standaloneSurface)
                        Positioned.fill(
                          child: Padding(
                            key: const ValueKey('note-paper-content-padding'),
                            padding: const EdgeInsets.fromLTRB(26, 12, 14, 12),
                            child: child,
                          ),
                        )
                      else
                        Padding(
                          key: const ValueKey('note-paper-content-padding'),
                          padding: const EdgeInsets.fromLTRB(26, 12, 14, 12),
                          child: child,
                        ),
                      if (widget.paper.noteCanvasElements.isNotEmpty)
                        Positioned.fill(child: _canvasPreview(embedded: true)),
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

  Widget _editor(
    BuildContext context, {
    required int minLines,
    required int maxLines,
  }) {
    final editorStyle = PaperTodoTypography.of(context)
        .contentStyle(
          Theme.of(context).textTheme.bodyMedium ??
              const TextStyle(fontSize: 14),
        )
        .apply(fontSizeFactor: widget.textZoom)
        .copyWith(height: widget.lineSpacing);
    final editor = TextFormField(
      key: ValueKey('${widget.paper.id}-content'),
      controller: _contentController,
      scrollController: _contentScrollController,
      focusNode: _contentFocusNode,
      onTapAlwaysCalled: true,
      onTap: () => _handleEditorTap(context),
      expands: widget.standaloneSurface,
      minLines: widget.standaloneSurface ? null : minLines,
      maxLines: widget.standaloneSurface ? null : maxLines,
      decoration: InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        hintText: widget.standaloneSurface
            ? null
            : strings.get(PaperTodoStringKeys.noteEditorHint),
      ),
      style: editorStyle,
      inputFormatters: const [
        _MarkdownPasteTextInputFormatter(),
        _MarkdownListContinuationTextInputFormatter(),
      ],
      onChanged: _commitContent,
    );
    return Focus(
      onKeyEvent: _handleMarkdownKeyEvent,
      child: Listener(
        onPointerDown: (event) =>
            _handleMarkdownEditorContextMenuPointerDown(context, event),
        child: Scrollbar(
          key: const ValueKey('note-editor-scrollbar'),
          controller: _contentScrollController,
          thumbVisibility: true,
          child: Stack(
            children: [
              if (_contentController.markdownEnabled &&
                  !_contentController.hasActiveComposing)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      key: const ValueKey('markdown-editor-block-background'),
                      painter: PaperTodoMarkdownEditorBackgroundPainter(
                        data: _contentController.text,
                        textSpan: _contentController.buildTextSpan(
                          context: context,
                          style: editorStyle,
                          withComposing: false,
                        ),
                        colors: PaperTodoThemeColors.of(context),
                        scrollController: _contentScrollController,
                        textDirection: Directionality.of(context),
                        textScaler: MediaQuery.textScalerOf(context),
                      ),
                    ),
                  ),
                ),
              editor,
            ],
          ),
        ),
      ),
    );
  }

  /*
   * PaperTodo keeps Markdown formatting in keyboard shortcuts and the editor
   * context menu. The visible row above the page is reserved for canvas tools,
   * so the Flutter port intentionally does not render a second formatting
   * toolbar here.
   */

  PopupMenuItem<String> _markdownMenuItem({
    required String value,
    required IconData icon,
    required String label,
    bool enabled = true,
  }) {
    final compact = widget.standaloneSurface;
    return compact
        ? _PaperTodoPopupMenuItem<String>(
            value: value,
            enabled: enabled,
            height: 21,
            padding: _paperTodoStandalonePopupMenuItemPadding,
            child: Text(label),
          )
        : PopupMenuItem<String>(
            value: value,
            enabled: enabled,
            height: _paperTodoPopupMenuHeight(),
            padding: _paperTodoPopupMenuItemPadding,
            child: Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Flexible(child: Text(label)),
              ],
            ),
          );
  }

  PopupMenuItem<String> _markdownMenuHeader(String label) {
    if (!widget.standaloneSurface) {
      return _paperTodoMenuHeader(label);
    }
    return PopupMenuItem<String>(
      enabled: false,
      height: 17,
      padding: _paperTodoStandalonePopupMenuItemPadding,
      child: _PaperTodoPopupMenuHeaderLabel(label),
    );
  }

  PopupMenuDivider _markdownMenuDivider() {
    return PopupMenuDivider(height: widget.standaloneSurface ? 7 : 16);
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
      final entries = _markdownEditorContextMenuItems();
      final selected = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(globalPosition.dx, globalPosition.dy + 1, 0, 0),
          Offset.zero & overlay.size,
        ),
        items: entries,
        constraints: widget.standaloneSurface
            ? _paperTodoStandaloneMenuConstraints(context, entries)
            : null,
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
      _markdownMenuHeader(strings.get(PaperTodoStringKeys.menuFormat)),
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
      _markdownMenuDivider(),
      _markdownMenuHeader(strings.get(PaperTodoStringKeys.menuText)),
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
      (value) => MarkdownFormatting.wrapSelection(value, '```\n', '\n```'),
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
    final formattedValue = MarkdownPasteText.formatEditUpdate(
      oldValue,
      rawValue,
    );
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
    final editorOffset = _contentScrollController.hasClients
        ? _contentScrollController.offset
        : 0.0;
    setState(() => _view = _viewPreview);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScrollOffset(_previewScrollController, editorOffset);
    });
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
    final paperColors = PaperTodoThemeColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant);
    return DecoratedBox(
      key: const ValueKey('note-status-bar'),
      decoration: BoxDecoration(
        color: paperColors.tint.withValues(alpha: isDark ? 16 / 255 : 10 / 255),
        border: Border(
          top: BorderSide(
            color: paperColors.tint.withValues(
              alpha: isDark ? 34 / 255 : 25 / 255,
            ),
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 26),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 3, 10, 4),
          child: Row(
            children: [
              ConstrainedBox(
                key: const ValueKey('note-status-mode-pill'),
                constraints: const BoxConstraints(minWidth: 42),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: paperColors.tint.withValues(
                      alpha: isDark ? 48 / 255 : 33 / 255,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(7, 1, 7, 2),
                    child: Text(
                      _noteViewLabel(view),
                      key: const ValueKey('note-status-mode'),
                      textAlign: TextAlign.center,
                      style: textStyle?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Transform.translate(
                  key: const ValueKey('note-status-stats-metrics'),
                  offset: const Offset(2, -2),
                  child: Text(
                    _noteStatsText(),
                    key: const ValueKey('note-status-stats'),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle?.copyWith(letterSpacing: 0.05),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _noteZoomStatus(textStyle),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noteZoomStatus(TextStyle? textStyle) {
    return SizedBox(
      key: const ValueKey('note-status-zoom'),
      width: 38,
      child: Transform.translate(
        key: const ValueKey('note-status-zoom-metrics'),
        offset: const Offset(0, -1),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            '${(widget.textZoom * 100).round()}%',
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.right,
            style: textStyle,
          ),
        ),
      ),
    );
  }

  Widget _noteTextZoomOverlay() {
    final colorScheme = Theme.of(context).colorScheme;
    final paperColors = PaperTodoThemeColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = !widget.paper.isPinnedToDesktop;
    return _conditionalTooltip(
      enabled: widget.enableToolTips,
      message: strings.get(PaperTodoStringKeys.actionResetTextZoom),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter:
            enabled ? (_) => setState(() => _zoomOverlayHovered = true) : null,
        onExit:
            enabled ? (_) => setState(() => _zoomOverlayHovered = false) : null,
        child: GestureDetector(
          key: const ValueKey('note-text-zoom-overlay'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? _resetTextZoom : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _zoomOverlayHovered
                  ? paperColors.tint.withValues(
                      alpha: isDark ? 48 / 255 : 32 / 255,
                    )
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              child: Opacity(
                opacity: _zoomOverlayHovered ? 1 : 0.55,
                child: Text(
                  '${(widget.textZoom * 100).round()}%',
                  style: TextStyle(
                    color: _zoomOverlayHovered
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
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
    if (strings.languageCode == 'zh') {
      return '$characterCount 字 | $lineCount 行 | $elementCount 元素';
    }
    return [
      '$characterCount ${characterCount == 1 ? 'char' : 'chars'}',
      '$lineCount ${lineCount == 1 ? 'line' : 'lines'}',
      '$elementCount ${elementCount == 1 ? 'element' : 'elements'}',
    ].join(' | ');
  }

  String _noteCanvasElementCountText() {
    final count = widget.paper.noteCanvasElements.length;
    if (strings.languageCode == 'zh') {
      return '$count 元素';
    }
    return '$count ${count == 1 ? 'element' : 'elements'}';
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
    final mode = MarkdownRenderModes.normalize(widget.markdownRenderMode);
    final data = widget.paper.content;
    return Listener(
      onPointerDown: (event) {
        _previewLinkActivated = false;
        _handlePreviewContextMenuPointerDown(context, event);
      },
      child: GestureDetector(
        key: ValueKey('${widget.paper.id}-preview'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!_previewLinkActivated) {
            _enterEditorFromPreview();
          }
        },
        child: DecoratedBox(
          decoration: const BoxDecoration(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 112),
            child: Scrollbar(
              key: const ValueKey('note-preview-scrollbar'),
              controller: _previewScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: const ValueKey('note-preview-scroll'),
                controller: _previewScrollController,
                padding: EdgeInsets.zero,
                child: PaperTodoMarkdownSourcePreview(
                  key: ValueKey(
                    '${widget.paper.id}-${mode == MarkdownRenderModes.enhanced ? 'enhanced' : 'basic'}-markdown-preview',
                  ),
                  data: data,
                  textZoom: widget.textZoom,
                  lineSpacing: widget.lineSpacing,
                  enhanced: mode == MarkdownRenderModes.enhanced,
                  onTap: () {
                    if (!_previewLinkActivated) {
                      _enterEditorFromPreview();
                    }
                  },
                  onTapLink: (href) {
                    _previewLinkActivated = true;
                    _openMarkdownLink(context, href);
                  },
                ),
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

  void _enterEditorFromPreview() {
    final mode = MarkdownRenderModes.normalize(widget.markdownRenderMode);
    if (mode == MarkdownRenderModes.off) {
      return;
    }
    final previewOffset = _previewScrollController.hasClients
        ? _previewScrollController.offset
        : 0.0;
    _enteringEditorFromPreview = true;
    setState(() => _view = _viewEdit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _contentFocusNode.requestFocus();
      // PaperTodo keeps one text view for preview and editing. Restore the
      // matching viewport after focus has had a chance to reveal the caret so
      // a long note does not jump during the mode switch.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _restoreScrollOffset(_contentScrollController, previewOffset);
        _enteringEditorFromPreview = false;
      });
    });
  }

  void _restoreScrollOffset(ScrollController controller, double offset) {
    if (!mounted || !controller.hasClients) {
      return;
    }
    final position = controller.position;
    final target = offset.clamp(0.0, position.maxScrollExtent).toDouble();
    if ((position.pixels - target).abs() > 0.5) {
      controller.jumpTo(target);
    }
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
              strings.format(PaperTodoStringKeys.openLinkFailed, [
                _readableFailureMessage(error, strings: strings),
              ]),
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
    if (paper.content.isEmpty ||
        ScriptCapsuleSpec.tryParse(paper.content) != null) {
      return _viewEdit;
    }
    return MarkdownRenderModes.normalize(mode) == MarkdownRenderModes.off
        ? _viewEdit
        : _viewPreview;
  }

  Widget _canvasPreview({bool embedded = false}) {
    return _NoteCanvasPreview(
      elements: widget.paper.noteCanvasElements,
      selectedElementId: _selectedCanvasElementId,
      geometryGesturesEnabled: !widget.paper.isPinnedToDesktop,
      enableToolTips: widget.enableToolTips,
      embedded: embedded,
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

  Widget _addCanvasButton() {
    final onPressed = widget.paper.isPinnedToDesktop
        ? null
        : () => _addCanvasElement(NoteCanvasElementTypes.code);
    final enabled = onPressed != null;
    final paperColors = PaperTodoThemeColors.of(context);
    return _conditionalTooltip(
      enabled: widget.enableToolTips,
      message: strings.get(PaperTodoStringKeys.actionAddCanvasBlock),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Opacity(
          opacity: enabled ? (_canvasAddButtonPressed ? 0.7 : 1) : 0.72,
          child: MouseRegion(
            cursor:
                enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            onEnter: enabled
                ? (_) => setState(() => _canvasAddButtonHovered = true)
                : null,
            onExit: enabled
                ? (_) {
                    setState(() {
                      _canvasAddButtonHovered = false;
                      _canvasAddButtonPressed = false;
                    });
                  }
                : null,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: enabled
                  ? (_) => setState(() => _canvasAddButtonPressed = true)
                  : null,
              onPointerUp: enabled
                  ? (_) => setState(() => _canvasAddButtonPressed = false)
                  : null,
              onPointerCancel: enabled
                  ? (_) => setState(() => _canvasAddButtonPressed = false)
                  : null,
              child: DecoratedBox(
                key: const ValueKey('note-add-canvas-block-surface'),
                decoration: BoxDecoration(
                  color: _canvasAddButtonHovered
                      ? paperColors.hover
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  key: const ValueKey('note-add-canvas-block'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 24,
                  ),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(28, 24),
                    maximumSize: const Size(28, 24),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: Colors.transparent,
                    foregroundColor: _canvasAddButtonHovered
                        ? paperColors.text
                        : paperColors.weakText,
                    overlayColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: onPressed,
                  icon: Text(
                    '{}',
                    style: TextStyle(
                      color: _canvasAddButtonHovered
                          ? paperColors.text
                          : paperColors.weakText,
                      fontFamily: 'Segoe UI Symbol',
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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

  void _renumberDuplicateCanvasLayers(List<NoteCanvasElement> orderedElements) {
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
    required this.embedded,
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
  final bool embedded;
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
    return LayoutBuilder(
      key: const ValueKey('note-canvas-preview'),
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : contentWidth;
        final boundedEmbeddedHeight = embedded && constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        final scale = embedded
            ? 1.0
            : (maxWidth / contentWidth).clamp(0.2, 1.0).toDouble();
        final origin = embedded ? const Offset(2, 1) : Offset.zero;
        final visualHeight = boundedEmbeddedHeight ??
            (contentHeight * scale).clamp(120, 640).toDouble();
        final canvasWidth = math.max(0, maxWidth - origin.dx) / scale;
        final canvasHeight = math.max(0, visualHeight - origin.dy) / scale;
        final canvas = SizedBox(
          height: visualHeight,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (!embedded)
                Positioned.fill(
                  child: ColoredBox(color: colorScheme.surfaceContainerLowest),
                ),
              for (var index = 0; index < sortedElements.length; index++)
                Positioned(
                  left: origin.dx + (sortedElements[index].x * scale),
                  top: origin.dy + (sortedElements[index].y * scale),
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
        if (embedded) {
          return canvas;
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: canvas,
        );
      },
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
    final paperColors = PaperTodoThemeColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final element = widget.element;
    final isCode = element.type == NoteCanvasElementTypes.code;
    final baseStyle = Theme.of(context).textTheme.bodyMedium;
    final style = baseStyle == null
        ? null
        : (isCode
                ? baseStyle.copyWith(
                    fontFamily: _paperTodoCodeFontFamily,
                    fontFamilyFallback: _paperTodoCodeFontFamilyFallback,
                  )
                : PaperTodoTypography.of(context).contentStyle(baseStyle))
            .copyWith(fontSize: (isCode ? 13 : 14) * widget.scale);
    final typeLabel = _noteCanvasElementTypeLabel(element.type);
    final layerLabel = _noteCanvasLayerLabel(
      widget.layerRank,
      widget.layerCount,
    );
    final isTopLayer =
        widget.layerCount > 1 && widget.layerRank == widget.layerCount;
    final emphasized = widget.isSelected || isTopLayer;
    final radius = (12 * widget.scale).clamp(6, 12).toDouble();
    final headerHeight = (22 * widget.scale).clamp(18, 22).toDouble();
    final headerLeftPadding = (7 * widget.scale).clamp(4, 7).toDouble();
    final headerRightPadding = (6 * widget.scale).clamp(4, 6).toDouble();
    final layerBadgeMaxWidth = math.min(
      72.0,
      math.max(
        1.0,
        (element.width * widget.scale) - headerLeftPadding - headerRightPadding,
      ),
    );
    final shadowAxis = 2 / math.sqrt(2);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleCanvasContextMenuPointerDown,
      child: DecoratedBox(
        key: ValueKey('note-canvas-element-chrome-${element.id}'),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          border: Border.all(
            color: emphasized
                ? colorScheme.primary
                : paperColors.tint.withValues(
                    alpha: isDark ? 110 / 255 : 96 / 255,
                  ),
            width: emphasized ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(radius),
          // WPF clips the resting DropShadowEffect to the element bounds on
          // PaperTodo's canvas. Flutter's BoxShadow uses a different blur
          // model and otherwise paints a large gray halo outside the block.
          boxShadow: emphasized
              ? [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(
                      alpha: isDark ? 0.22 : 0.13,
                    ),
                    blurRadius: 6,
                    offset: Offset(shadowAxis, shadowAxis),
                  ),
                ]
              : const [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(math.max(0, radius - 1)),
          child: Stack(
            children: [
              Column(
                children: [
                  _conditionalTooltip(
                    enabled: widget.enableToolTips,
                    message: widget.strings.get(
                      PaperTodoStringKeys.canvasDragBlock,
                    ),
                    child: MouseRegion(
                      cursor: widget.geometryGesturesEnabled
                          ? SystemMouseCursors.move
                          : SystemMouseCursors.basic,
                      child: Listener(
                        key: ValueKey('note-canvas-drag-handle-${element.id}'),
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) => _beginGeometryGesture(
                          event,
                          _CanvasGeometryDragMode.move,
                        ),
                        onPointerMove: _updateGeometryGesture,
                        onPointerUp: _endGeometryGesture,
                        onPointerCancel: _endGeometryGesture,
                        child: Container(
                          height: headerHeight,
                          padding: EdgeInsets.fromLTRB(
                            headerLeftPadding,
                            2,
                            headerRightPadding,
                            2,
                          ),
                          color: paperColors.tint.withValues(
                            alpha: emphasized
                                ? (isDark ? 96 / 255 : 76 / 255)
                                : (isDark ? 70 / 255 : 50 / 255),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  typeLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: (10 * widget.scale)
                                            .clamp(8, 10)
                                            .toDouble(),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              Container(
                                key: ValueKey(
                                  'note-canvas-layer-badge-${element.id}',
                                ),
                                constraints: BoxConstraints(
                                  minWidth: math.min(32, layerBadgeMaxWidth),
                                  maxWidth: layerBadgeMaxWidth,
                                ),
                                padding: EdgeInsets.fromLTRB(
                                  (5 * widget.scale).clamp(3, 5).toDouble(),
                                  0,
                                  (5 * widget.scale).clamp(3, 5).toDouble(),
                                  1,
                                ),
                                decoration: BoxDecoration(
                                  color: paperColors.tint.withValues(
                                    alpha: emphasized
                                        ? (isDark ? 118 / 255 : 96 / 255)
                                        : (isDark ? 46 / 255 : 34 / 255),
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    (4 * widget.scale).clamp(3, 4).toDouble(),
                                  ),
                                ),
                                child: Text(
                                  layerLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: isTopLayer
                                            ? colorScheme.onSurface
                                            : colorScheme.onSurfaceVariant,
                                        fontSize: (9.5 * widget.scale)
                                            .clamp(8, 9.5)
                                            .toDouble(),
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
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        (9 * widget.scale).clamp(4, 9).toDouble(),
                        (7 * widget.scale).clamp(4, 7).toDouble(),
                        (9 * widget.scale).clamp(4, 9).toDouble(),
                        (7 * widget.scale).clamp(4, 7).toDouble(),
                      ),
                      child: AbsorbPointer(
                        absorbing: !widget.geometryGesturesEnabled,
                        child: Focus(
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
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            style: style?.copyWith(
                              color: colorScheme.onSurface,
                            ),
                            onTap: () => widget.onSelect(element),
                            onChanged: _commitCanvasText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 2,
                bottom: 2,
                child: _conditionalTooltip(
                  enabled: widget.enableToolTips,
                  message: widget.strings.get(
                    PaperTodoStringKeys.canvasResizeBlock,
                  ),
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
                          color: paperColors.tint.withValues(
                            alpha: isDark ? 72 / 255 : 58 / 255,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: SizedBox.square(
                          dimension:
                              (15 * widget.scale).clamp(12, 15).toDouble(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
    final entries = _canvasElementContextMenuItems();
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy + 1, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: entries,
      constraints: _paperTodoStandaloneMenuConstraints(context, entries),
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
        height: 17,
        padding: _paperTodoStandalonePopupMenuItemPadding,
        child: _PaperTodoPopupMenuHeaderLabel(
          '${_noteCanvasElementTypeLabel(widget.element.type)}'
          ' · 层 ${widget.layerRank}',
        ),
      ),
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
      const PopupMenuDivider(height: 7),
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
    return _PaperTodoPopupMenuItem<String>(
      value: value,
      height: 21,
      padding: _paperTodoStandalonePopupMenuItemPadding,
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
    final maxY = (widget.canvasHeight - element.height).clamp(
      0,
      double.infinity,
    );
    element.x = _roundCanvasValue((element.x + dx).clamp(0, maxX).toDouble());
    element.y = _roundCanvasValue((element.y + dy).clamp(0, maxY).toDouble());
    _geometryChanged = true;
    widget.onGeometryChanging();
  }

  void _resizeElement(Offset delta) {
    final element = widget.element;
    final dx = delta.dx / widget.scale;
    final dy = delta.dy / widget.scale;
    final maxWidth = (widget.canvasWidth - element.x).clamp(
      72,
      double.infinity,
    );
    final maxHeight = (widget.canvasHeight - element.y).clamp(
      48,
      double.infinity,
    );
    element.width = _roundCanvasValue(
      (element.width + dx).clamp(72, maxWidth).toDouble(),
    );
    element.height = _roundCanvasValue(
      (element.height + dy).clamp(48, maxHeight).toDouble(),
    );
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

enum _CanvasGeometryDragMode { move, resize }

String _noteCanvasElementTypeLabel(String type) => 'CODE';

String _noteCanvasLayerLabel(int layerRank, int layerCount) {
  if (layerCount > 1 && layerRank == layerCount) {
    return '顶层 $layerRank';
  }
  return '层 $layerRank';
}

enum _CanvasLayerAction { bringForward, sendBackward, bringToFront, sendToBack }

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
  const _CanvasGeometryDialog({required this.element});

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
    _widthController = TextEditingController(
      text: _format(widget.element.width),
    );
    _heightController = TextEditingController(
      text: _format(widget.element.height),
    );
    _layerController = TextEditingController(
      text: widget.element.zIndex.toString(),
    );
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
    return _PaperDialog(
      width: 452,
      icon: Icons.aspect_ratio_outlined,
      title: strings.get(PaperTodoStringKeys.canvasBlockGeometry),
      content: SizedBox(
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

class _PaperTodoTodoCheckBox extends StatefulWidget {
  const _PaperTodoTodoCheckBox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<_PaperTodoTodoCheckBox> createState() => _PaperTodoTodoCheckBoxState();
}

class _PaperTodoTodoCheckBoxState extends State<_PaperTodoTodoCheckBox> {
  bool _hovered = false;

  @override
  void didUpdateWidget(covariant _PaperTodoTodoCheckBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onChanged == null && _hovered) {
      _hovered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final colors = PaperTodoThemeColors.of(context);
    return Semantics(
      checked: widget.value,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: enabled ? (_) => setState(() => _hovered = false) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
          child: SizedBox.square(
            dimension: 16,
            child: CustomPaint(
              painter: _PaperTodoTodoCheckBoxPainter(
                value: widget.value,
                hovered: _hovered,
                colors: colors,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperTodoTodoCheckBoxPainter extends CustomPainter {
  const _PaperTodoTodoCheckBoxPainter({
    required this.value,
    required this.hovered,
    required this.colors,
  });

  final bool value;
  final bool hovered;
  final PaperTodoThemeColors colors;

  static const double borderWidth = 1.5;
  static const double radius = 4;
  static const double checkStrokeWidth = 2;

  double get effectiveBorderRadius => radius + borderWidth / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 16;
    final scaleY = size.height / 16;
    if (value) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius * math.min(scaleX, scaleY)),
        ),
        Paint()
          ..color = hovered ? colors.checkBoxActiveHover : colors.active
          ..style = PaintingStyle.fill,
      );
      final check = Path()
        ..moveTo(3 * scaleX, 7.5 * scaleY)
        ..lineTo(6.5 * scaleX, 11 * scaleY)
        ..lineTo(13 * scaleX, 4 * scaleY);
      canvas.drawPath(
        check,
        Paint()
          ..color = colors.paper
          ..style = PaintingStyle.stroke
          ..strokeWidth = checkStrokeWidth * math.min(scaleX, scaleY)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      return;
    }

    final inset = borderWidth / 2;
    final borderRect = Rect.fromLTWH(
      inset,
      inset,
      math.max(0.0, size.width - borderWidth),
      math.max(0.0, size.height - borderWidth),
    );
    // WPF applies CornerRadius=4 to the outer bordered element. Flutter draws
    // a centered stroke on the inset path, so add the half-stroke inset back
    // to preserve the same outer radius instead of squaring the corners.
    final borderRadius = radius + inset;
    if (hovered) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(borderRect, Radius.circular(borderRadius)),
        Paint()
          ..color = colors.checkBoxUncheckedHover
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(borderRect, Radius.circular(borderRadius)),
      Paint()
        ..color = hovered ? colors.checkBoxHoverBorder : colors.checkBox
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _PaperTodoTodoCheckBoxPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.hovered != hovered ||
        oldDelegate.colors != colors;
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
    required this.moveCompletedTodosToBottom,
    required this.enableToolTips,
    required this.enableAnimations,
    required this.visualSize,
    required this.lineSpacing,
    required this.textZoom,
    required this.showDueRelativeTime,
    required this.dueYearDisplayMode,
    required this.defaultReminderIntervalValue,
    required this.defaultReminderIntervalUnit,
    required this.nativeDialogFontFamily,
    required this.onOpenLinkedNote,
    required this.onRunScriptCapsule,
    required this.onChanged,
    required this.onPersist,
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
  final bool moveCompletedTodosToBottom;
  final bool enableToolTips;
  final bool enableAnimations;
  final String visualSize;
  final double lineSpacing;
  final double textZoom;
  final bool showDueRelativeTime;
  final String dueYearDisplayMode;
  final int defaultReminderIntervalValue;
  final String defaultReminderIntervalUnit;
  final String nativeDialogFontFamily;
  final Future<void> Function(PaperData paper, PaperData anchorPaper)
      onOpenLinkedNote;
  final Future<void> Function(ScriptCapsuleSpec spec) onRunScriptCapsule;
  final Future<void> Function() onChanged;
  final Future<void> Function() onPersist;
  final void Function(PaperData paper, PaperItem item) onItemDeleted;
  final void Function(PaperData paper, PaperItem item) onItemRestored;
  final void Function(PaperItem item) onReminderReset;
  final bool standaloneSurface;

  @override
  State<_TodoEditor> createState() => _TodoEditorState();
}

enum _TodoFocusPlacement { start, end }

class _DepartingTodoRow {
  const _DepartingTodoRow({
    required this.item,
    required this.originalIndex,
    required this.groupToken,
    required this.delay,
    required this.duration,
    required this.slideDistance,
    required this.completesGroup,
  });

  final PaperItem item;
  final int originalIndex;
  final Object groupToken;
  final Duration delay;
  final Duration duration;
  final double slideDistance;
  final bool completesGroup;
}

class _EnteringTodoRow {
  const _EnteringTodoRow({
    required this.itemId,
    required this.delay,
    required this.opacityDuration,
    required this.slideDuration,
    required this.slideDistance,
    required this.slideCurve,
  });

  final String itemId;
  final Duration delay;
  final Duration opacityDuration;
  final Duration slideDuration;
  final double slideDistance;
  final Curve slideCurve;
}

class _TodoEntranceAnimation extends StatefulWidget {
  const _TodoEntranceAnimation({
    required this.delay,
    required this.opacityDuration,
    required this.slideDuration,
    required this.slideDistance,
    required this.slideCurve,
    required this.onFinished,
    required this.child,
    super.key,
  });

  final Duration delay;
  final Duration opacityDuration;
  final Duration slideDuration;
  final double slideDistance;
  final Curve slideCurve;
  final VoidCallback onFinished;
  final Widget child;

  @override
  State<_TodoEntranceAnimation> createState() => _TodoEntranceAnimationState();
}

class _TodoEntranceAnimationState extends State<_TodoEntranceAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.slideDuration,
    );
    _controller.addStatusListener(_handleAnimationStatus);
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, _controller.forward);
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final slideProgress = widget.slideCurve.transform(_controller.value);
        final opacityScale = widget.slideDuration.inMicroseconds /
            widget.opacityDuration.inMicroseconds;
        final opacityProgress = PaperTodoMotion.quickCurve.transform(
          (_controller.value * opacityScale).clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: opacityProgress,
          child: Transform.translate(
            offset: Offset(0, -widget.slideDistance * (1 - slideProgress)),
            child: child,
          ),
        );
      },
    );
  }
}

class _TodoDepartureAnimation extends StatefulWidget {
  const _TodoDepartureAnimation({
    required this.delay,
    required this.duration,
    required this.slideDistance,
    required this.onFinished,
    required this.child,
    super.key,
  });

  final Duration delay;
  final Duration duration;
  final double slideDistance;
  final VoidCallback onFinished;
  final Widget child;

  @override
  State<_TodoDepartureAnimation> createState() =>
      _TodoDepartureAnimationState();
}

class _TodoDepartureAnimationState extends State<_TodoDepartureAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.addStatusListener(_handleAnimationStatus);
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, _controller.forward);
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final fadeProgress = _controller.value;
          final slideProgress = PaperTodoMotion.quickCurve.transform(
            fadeProgress,
          );
          final sizeProgress = PaperTodoMotion.enterCurve.transform(
            fadeProgress,
          );
          return Opacity(
            opacity: 1 - fadeProgress,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                // Collapse the old slot as it fades.  Rows below it then move
                // into place continuously instead of jumping when the
                // snapshot is finally removed.
                heightFactor: 1 - sizeProgress,
                child: Transform.translate(
                  offset: Offset(widget.slideDistance * slideProgress, 0),
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

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
  final _enteringTodoRows = <String, _EnteringTodoRow>{};
  final _departingTodoRows = <_DepartingTodoRow>[];
  final _multilineTodoItemIds = <String>{};
  final _queuedTodoLineMeasurements = <String>{};
  final _todoLineMeasurementTexts = <String, String>{};
  final _todoLineMeasurementRowWidths = <String, double>{};
  var _textFieldRevision = 0;
  var _suppressTodoBackspaceUntilKeyUp = false;
  var _applyingTodoTextHistory = false;
  var _isDraggingTodoItem = false;
  var _todoAppendHovered = false;
  String? _hoveredTodoItemId;
  String? _hoveredTodoDueItemId;
  String? _pressedTodoDueItemId;
  String? _hoveredTodoDragHandleItemId;
  String? _hoveredTodoLinkedNoteItemId;
  String? _pressedTodoLinkedNoteItemId;
  String? _draggingTodoItemId;
  String? _activeTodoDropTargetId;
  bool _activeTodoDropAfter = false;
  String? _activeOriginalTodoItemId;
  int? _activeOriginalTodoColumnIndex;
  String? _activeOriginalTodoText;

  PaperTodoStrings get strings => PaperTodoStringsScope.of(context);

  @override
  void didUpdateWidget(covariant _TodoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paper.id != widget.paper.id ||
        (oldWidget.enableAnimations && !widget.enableAnimations)) {
      _clearEnteringTodoRows();
      _clearDepartingTodoRows();
    }
  }

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
    final dengXianMetrics =
        theme.textTheme.bodyMedium?.fontFamily == _dengXianFontFamily;
    final textMetricScale =
        dengXianMetrics ? _paperTodoDengXianAdvanceScale : 1.0;
    final itemTextStyle = theme.textTheme.bodyMedium
        ?.apply(
          fontSizeFactor:
              visualSpec.textScale * widget.textZoom * textMetricScale,
        )
        .copyWith(
          height: widget.lineSpacing / textMetricScale,
          letterSpacing: dengXianMetrics ? null : -0.0625,
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
              ..._todoRowsForDisplay(
                context: context,
                itemTextStyle: itemTextStyle,
                visualSpec: visualSpec,
                compactActions: useCompactItemActions,
              ),
              _todoDeleteDropTarget(context, visualSpec),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _todoRowsForDisplay({
    required BuildContext context,
    required TextStyle? itemTextStyle,
    required _TodoVisualSpec visualSpec,
    required bool compactActions,
  }) {
    final rows = <Widget>[];
    // A completed row is moved in the model immediately so persistence and
    // undo observe the final order at once.  During the visual hand-off keep
    // only its departure snapshot at the old slot; rendering the live target
    // row as well creates two editable copies and makes the row appear to
    // flash between positions.
    final departingItemIds =
        _departingTodoRows.map((departure) => departure.item.id).toSet();
    for (final item in widget.paper.items) {
      if (departingItemIds.contains(item.id)) {
        continue;
      }
      Widget row = _todoReorderDropTarget(
        item: item,
        child: _todoRow(
          context: context,
          item: item,
          itemTextStyle: itemTextStyle,
          visualSpec: visualSpec,
          compactActions: compactActions,
        ),
      );
      final entrance = _enteringTodoRows[item.id];
      if (entrance != null) {
        row = _TodoEntranceAnimation(
          key: ValueKey('${widget.paper.id}-${item.id}-entrance'),
          delay: entrance.delay,
          opacityDuration: entrance.opacityDuration,
          slideDuration: entrance.slideDuration,
          slideDistance: entrance.slideDistance,
          slideCurve: entrance.slideCurve,
          onFinished: () => _finishEnteringTodoRow(entrance),
          child: row,
        );
      }
      rows.add(row);
    }
    final departures = [
      ..._departingTodoRows,
    ]..sort((left, right) => left.originalIndex.compareTo(right.originalIndex));
    for (final departure in departures) {
      rows.insert(
        departure.originalIndex.clamp(0, rows.length).toInt(),
        _TodoDepartureAnimation(
          key: ValueKey('${widget.paper.id}-${departure.item.id}-departure'),
          delay: departure.delay,
          duration: departure.duration,
          slideDistance: departure.slideDistance,
          onFinished: () => _finishDepartingTodoGroup(departure),
          child: _todoDepartureSnapshotRow(
            context: context,
            item: departure.item,
            itemTextStyle: itemTextStyle,
            visualSpec: visualSpec,
          ),
        ),
      );
    }
    return rows;
  }

  Widget _todoDepartureSnapshotRow({
    required BuildContext context,
    required PaperItem item,
    required TextStyle? itemTextStyle,
    required _TodoVisualSpec visualSpec,
  }) {
    final mobileBoard = !widget.standaloneSurface &&
        MediaQuery.sizeOf(context).shortestSide < 600;
    final leadingExtent = mobileBoard ? 48.0 : visualSpec.checkColumnWidth;
    final paperColors = PaperTodoThemeColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final texts = <String>[item.text, ...item.todoExtraColumns];
    final textStyle = itemTextStyle?.copyWith(
      color: item.done ? paperColors.brightWeakText : colorScheme.onSurface,
      decoration: item.done ? TextDecoration.lineThrough : null,
      decorationColor: paperColors.brightWeakText.withValues(alpha: 0.8),
    );

    Widget textColumn(int index) {
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: visualSpec.rowMinHeight),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: index == 0
                ? visualSpec.mainContentPadding
                : visualSpec.extraContentPadding,
            child: Text(
              index < texts.length ? texts[index] : '',
              style: textStyle,
              softWrap: true,
            ),
          ),
        ),
      );
    }

    final columns = LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < visualSpec.checkColumnWidth) {
          return SizedBox(height: visualSpec.rowMinHeight);
        }
        if (item.todoColumnCount <= 1) {
          return textColumn(0);
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < item.todoColumnCount; index++) ...[
                if (index > 0)
                  SizedBox(
                    width: _todoColumnSplitterWidth,
                    child: CustomPaint(
                      painter: _TodoColumnSeparatorPainter(
                        paperColors.paperBorder.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                Expanded(
                  flex: _columnFlex(item, index),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: index == 0 ? 0 : 6,
                      right: index == item.todoColumnCount - 1 ? 0 : 3,
                    ),
                    child: textColumn(index),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
    final dueAt = parsePaperTodoDueAtLocal(item.dueAtLocal);

    return Padding(
      key: ValueKey(
        '${widget.paper.id}-${item.id}-departure-snapshot-row',
      ),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border.all(
            color: paperColors.tint.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 18 / 255
                  : 12 / 255,
            ),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: leadingExtent,
                child: Center(
                  child: Transform.scale(
                    scale: 16 / 18,
                    child: Checkbox(value: item.done, onChanged: null),
                  ),
                ),
              ),
              Expanded(child: columns),
              if (dueAt != null) ...[
                const SizedBox(width: 4),
                Text(
                  _formatAbsoluteDueDate(dueAt),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: paperColors.weakText,
                        fontSize: 10,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _finishDepartingTodoGroup(_DepartingTodoRow departure) {
    if (!departure.completesGroup || !mounted) {
      return;
    }
    final focusItemId =
        _todoItemById(departure.item.id) == null ? null : departure.item.id;
    setState(
      () => _departingTodoRows.removeWhere(
        (candidate) => identical(candidate.groupToken, departure.groupToken),
      ),
    );
    if (focusItemId != null) {
      _requestTodoItemFocus(focusItemId);
    }
  }

  void _clearDepartingTodoRows() {
    _departingTodoRows.clear();
  }

  void _finishEnteringTodoRow(_EnteringTodoRow entrance) {
    if (!mounted || !identical(_enteringTodoRows[entrance.itemId], entrance)) {
      return;
    }
    setState(() => _enteringTodoRows.remove(entrance.itemId));
  }

  void _queueTodoEntrance(_EnteringTodoRow entrance) {
    _enteringTodoRows[entrance.itemId] = entrance;
  }

  void _clearEnteringTodoRows() {
    _enteringTodoRows.clear();
  }

  void _clearTodoRowAnimations(String itemId) {
    _enteringTodoRows.remove(itemId);
    final groupTokens = _departingTodoRows
        .where((departure) => departure.item.id == itemId)
        .map((departure) => departure.groupToken)
        .toSet();
    _departingTodoRows.removeWhere(
      (departure) =>
          departure.item.id == itemId ||
          groupTokens.contains(departure.groupToken),
    );
  }

  Widget _todoReorderDropTarget({
    required PaperItem item,
    required Widget child,
  }) {
    final paperColors = PaperTodoThemeColors.of(context);
    final dropTargetKey = _todoDropTargetKey(item);
    return DragTarget<PaperItem>(
      onWillAcceptWithDetails: (details) =>
          _canAcceptTodoItemDrop(details.data, item),
      onMove: (details) {
        if (!_canAcceptTodoItemDrop(details.data, item)) return;
        final after = _dropAfterTodoTarget(item, details.offset);
        if (_activeTodoDropTargetId == item.id &&
            _activeTodoDropAfter == after) {
          return;
        }
        setState(() {
          _activeTodoDropTargetId = item.id;
          _activeTodoDropAfter = after;
        });
      },
      onLeave: (_) {
        if (_activeTodoDropTargetId == item.id) {
          setState(() => _activeTodoDropTargetId = null);
        }
      },
      onAcceptWithDetails: (details) {
        final after = _dropAfterTodoTarget(item, details.offset);
        setState(() => _activeTodoDropTargetId = null);
        _reorderTodoItemToTarget(details.data, item, after: after);
      },
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.whereType<PaperItem>().any(
              (dragged) => _canAcceptTodoItemDrop(dragged, item),
            );
        final showAfter =
            _activeTodoDropTargetId == item.id ? _activeTodoDropAfter : false;
        return Stack(
          key: dropTargetKey,
          clipBehavior: Clip.none,
          children: [
            child,
            if (highlighted)
              Positioned(
                left: 4,
                right: 4,
                top: showAfter ? null : -1.5,
                bottom: showAfter ? -1.5 : null,
                child: IgnorePointer(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: paperColors.tint.withValues(alpha: 180 / 255),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
              ),
          ],
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
    final paperColors = PaperTodoThemeColors.of(context);
    return DragTarget<PaperItem>(
      onWillAcceptWithDetails: (details) => _todoItemIndex(details.data) >= 0,
      onAcceptWithDetails: (details) {
        _setTodoItemDragging(false);
        _deleteItem(context, details.data);
      },
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.whereType<PaperItem>().any(
              (item) => _todoItemIndex(item) >= 0,
            );
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
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return SizedBox(
          key: ValueKey('${widget.paper.id}-todo-delete-drop-target'),
          height: targetHeight,
          child: Container(
            key: ValueKey('${widget.paper.id}-todo-trash-area'),
            margin: const EdgeInsets.only(top: 6, bottom: 2),
            height: visualSpec.controlExtent,
            decoration: BoxDecoration(
              color: paperColors.danger.withValues(
                alpha: highlighted
                    ? (isDark ? 32 / 255 : 26 / 255)
                    : (isDark ? 16 / 255 : 12 / 255),
              ),
              border: Border.all(
                color: highlighted
                    ? paperColors.danger
                    : paperColors.danger.withValues(alpha: 50 / 255),
                width: highlighted ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Opacity(
                opacity: highlighted ? 1 : 0.65,
                child: Text(
                  '\u{1F5D1}',
                  style: TextStyle(
                    fontFamily: 'Segoe UI Symbol',
                    fontFamilyFallback: const <String>['Segoe UI Emoji'],
                    fontSize: visualSpec.trashGlyphSize,
                    color: paperColors.danger,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _todoFooterActions(_TodoVisualSpec visualSpec) {
    final colorScheme = Theme.of(context).colorScheme;
    final paperColors = PaperTodoThemeColors.of(context);
    if (widget.standaloneSurface) {
      const borderAlpha = 45 / 255;
      return Semantics(
        button: true,
        label: strings.get(PaperTodoStringKeys.actionAddItem),
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          onEnter: (_) => setState(() => _todoAppendHovered = true),
          onExit: (_) => setState(() => _todoAppendHovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _addItem,
            child: Container(
              key: ValueKey('${widget.paper.id}-todo-append-area'),
              margin: const EdgeInsets.only(top: 6, bottom: 2),
              height: visualSpec.controlExtent,
              decoration: BoxDecoration(
                color: paperColors.tint.withValues(
                  alpha: _todoAppendHovered ? 26 / 255 : 12 / 255,
                ),
                border: Border.all(
                  color: paperColors.tint.withValues(alpha: borderAlpha),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Opacity(
                opacity: _todoAppendHovered ? 0.7 : 0.42,
                child: Text(
                  '\uFF0B',
                  style: TextStyle(
                    fontFamily: 'Segoe UI Symbol',
                    fontFamilyFallback: const <String>['Segoe UI Emoji'],
                    fontSize: visualSpec.appendGlyphSize,
                    color: paperColors.weakText,
                    height: 1,
                  ),
                ),
              ),
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
                        color: paperColors.tint.withValues(
                          alpha: isDark ? 18 / 255 : 12 / 255,
                        ),
                        border: Border.all(
                          color: paperColors.tint.withValues(alpha: 45 / 255),
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
        color: paperColors.tint.withValues(alpha: 12 / 255),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
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
    final leadingExtent = mobileBoard ? 48.0 : visualSpec.checkColumnWidth;
    final linkedNote = widget.enableTodoNoteLinks ? _linkedNoteFor(item) : null;
    final dueIndicator = _todoDueIndicator(
      context,
      item,
      visualSpec,
      showRelativeBadge: widget.showDueRelativeTime,
    );
    final itemActions = _todoItemActions(
      context: context,
      item: item,
      visualSpec: visualSpec,
      compact: compactActions,
    );
    final dueSlotContent = dueIndicator == null
        ? SizedBox.shrink(
            key: ValueKey('${widget.paper.id}-${item.id}-due-empty'),
          )
        : Padding(
            key: ValueKey('${widget.paper.id}-${item.id}-due-present'),
            padding: const EdgeInsets.only(left: 4),
            child: dueIndicator,
          );
    // A standalone Windows paper is hosted by its own native HWND. A trailing
    // due slot that changes width over several layout frames can make the
    // compositor repaint the whole paper while the row is being edited. Do
    // not create a zero-duration AnimatedSize there: Flutter can restart its
    // controller from performLayout when a completed row is reinserted. The
    // board keeps PaperTodo's compact grow/fade motion.
    final Widget dueSlot;
    if (widget.standaloneSurface || !widget.enableAnimations) {
      dueSlot = KeyedSubtree(
        key: ValueKey('${widget.paper.id}-${item.id}-due-transition'),
        child: dueSlotContent,
      );
    } else {
      dueSlot = AnimatedSize(
        key: ValueKey('${widget.paper.id}-${item.id}-due-transition'),
        duration: PaperTodoMotion.quick,
        reverseDuration: PaperTodoMotion.fadeOut,
        curve: PaperTodoMotion.enterCurve,
        alignment: AlignmentDirectional.centerEnd,
        clipBehavior: Clip.hardEdge,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: dueIndicator == null ? 0 : 1),
          duration: PaperTodoMotion.quick,
          curve: PaperTodoMotion.quickCurve,
          builder: (context, opacity, child) => FadeTransition(
            opacity: AlwaysStoppedAnimation<double>(opacity),
            child: child,
          ),
          child: dueSlotContent,
        ),
      );
    }
    final trailingRow = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        dueSlot,
        if (linkedNote != null) ...[
          const SizedBox(width: 1),
          _linkedNoteButton(linkedNote, item, visualSpec),
        ],
        ...itemActions,
      ],
    );
    // 16px transparent window chrome + 14px Todo body insets + the row's
    // 8px border/padding leave the same clipped trailing viewport as WPF.
    const standaloneTodoHorizontalInsets = 38.0;
    final maximumTrailingWidth = math.max(
      0.0,
      widget.paper.width - standaloneTodoHorizontalInsets - leadingExtent,
    );
    final trailing = widget.standaloneSurface
        ? ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maximumTrailingWidth),
            child: _HorizontalOverflowClip(child: trailingRow),
          )
        : trailingRow;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: leadingExtent,
          child: Center(
            child: widget.standaloneSurface
                ? _PaperTodoTodoCheckBox(
                    key: ValueKey('${widget.paper.id}-${item.id}-checkbox'),
                    value: item.done,
                    onChanged: (value) => _setTodoItemDone(item, value),
                  )
                : Transform.scale(
                    scale: 16 / 18,
                    child: Checkbox(
                      value: item.done,
                      onChanged: (value) =>
                          _setTodoItemDone(item, value ?? false),
                    ),
                  ),
          ),
        ),
        Expanded(
          child: _todoColumnFields(context, item, itemTextStyle, visualSpec),
        ),
        trailing,
      ],
    );
    final rowBody =
        widget.enableTodoNoteLinks ? _noteLinkDropTarget(item, row) : row;
    final dragging = _draggingTodoItemId == item.id;
    final hovered = _hoveredTodoItemId == item.id || dragging;
    // Row hover is an immediate brush change in PaperTodo. Completion and
    // drag opacity still use the source-timed AnimatedOpacity below.
    const hoverDuration = Duration.zero;
    final stateDuration = widget.enableAnimations
        ? dragging
            ? Duration.zero
            : item.done
                ? PaperTodoMotion.fadeIn
                : PaperTodoMotion.quick
        : Duration.zero;
    final paperColors = PaperTodoThemeColors.of(context);
    return Padding(
      key: ValueKey('${widget.paper.id}-${item.id}-row'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        onEnter: (_) {
          if (_hoveredTodoItemId != item.id) {
            setState(() => _hoveredTodoItemId = item.id);
          }
        },
        onExit: (_) {
          if (_hoveredTodoItemId == item.id) {
            setState(() => _hoveredTodoItemId = null);
          }
        },
        child: AnimatedContainer(
          duration: hoverDuration,
          curve: PaperTodoMotion.enterCurve,
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          decoration: BoxDecoration(
            color: hovered
                ? paperColors.tint.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 48 / 255
                        : 32 / 255,
                  )
                : Colors.transparent,
            border: Border.all(
              color: paperColors.tint.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 18 / 255
                    : 12 / 255,
              ),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: AnimatedOpacity(
            duration: stateDuration,
            curve: PaperTodoMotion.enterCurve,
            opacity: dragging ? 0.25 : (item.done ? 0.75 : 1),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) =>
                  _handleTodoContextMenuPointerDown(context, item, event),
              child: rowBody,
            ),
          ),
        ),
      ),
    );
  }

  void _setTodoItemDone(PaperItem item, bool value) {
    final itemIndex = _todoItemIndex(item);
    if (itemIndex < 0 || item.done == value) {
      return;
    }
    final previousItem = PaperItem.fromJson(item.toJson());
    _pushTodoUndoSnapshot();
    var moved = false;
    setState(() {
      // Do not interrupt unrelated row animations. The previous implementation
      // cleared every entrance/departure on each checkbox click, which made
      // simultaneous completions visibly snap and flicker.
      _clearTodoRowAnimations(item.id);
      item.done = value;
      if (value) {
        item.dueAtLocal = null;
      }
      if (widget.moveCompletedTodosToBottom) {
        final ordered = <PaperItem>[
          ...widget.paper.items.where((candidate) => !candidate.done),
          ...widget.paper.items.where((candidate) => candidate.done),
        ];
        final targetIndex = ordered.indexWhere(
          (candidate) => candidate.id == item.id,
        );
        moved = targetIndex >= 0 && targetIndex != itemIndex;
        if (moved) {
          final groupToken = Object();
          if (widget.enableAnimations) {
            _departingTodoRows.add(
              _DepartingTodoRow(
                item: previousItem,
                originalIndex: itemIndex,
                groupToken: groupToken,
                delay: Duration.zero,
                duration: PaperTodoMotion.move,
                slideDistance: 18,
                completesGroup: true,
              ),
            );
            _queueTodoEntrance(
              _EnteringTodoRow(
                itemId: item.id,
                delay: PaperTodoMotion.todoTransitionDelay,
                opacityDuration: PaperTodoMotion.fadeIn,
                slideDuration: PaperTodoMotion.move,
                slideDistance: 18,
                slideCurve: PaperTodoMotion.enterCurve,
              ),
            );
          }
          widget.paper.items = ordered;
        }
      }
      widget.paper.normalize();
    });
    widget.onReminderReset(item);
    if (moved && !widget.enableAnimations) {
      _requestTodoItemFocus(item.id);
    }
    unawaited(widget.onChanged());
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
      _showTodoItemContextMenu(context, item, columnIndex, event.position),
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
    final entries = _todoItemContextMenuItems(item, columnIndex);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy + 1, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: entries,
      constraints: widget.standaloneSurface
          ? _paperTodoStandaloneMenuConstraints(context, entries)
          : null,
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
      _todoItemMenuHeader(strings.get(PaperTodoStringKeys.menuTodoItem)),
      if (widget.enableTodoNoteLinks && hasLinkedNote) ...[
        if (_linkedNoteFor(item) case final PaperData linkedNote)
          _todoActionMenuItem(
            value: _compactTodoActionOpenLinkedNote,
            icon: Icons.open_in_new,
            label: widget.runLinkedScriptCapsulesOnClick &&
                    ScriptCapsuleSpec.tryParse(linkedNote.content) != null
                ? strings.format(
                    PaperTodoStringKeys.menuEditLinkedScriptCapsule,
                    [_displayPaperTitle(linkedNote)],
                  )
                : strings.format(PaperTodoStringKeys.menuOpenLinkedNote, [
                    _displayPaperTitle(linkedNote),
                  ]),
          ),
        _todoActionMenuItem(
          value: _compactTodoActionUnlinkNote,
          icon: Icons.link_off_outlined,
          label: strings.get(PaperTodoStringKeys.actionUnlinkNote),
        ),
        _todoItemMenuDivider(),
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
      if (!widget.standaloneSurface &&
          widget.enableTodoNoteLinks &&
          widget.notePapers.isNotEmpty &&
          !hasLinkedNote) ...[
        _todoItemMenuDivider(),
        for (final note in widget.notePapers)
          _todoActionMenuItem(
            value: '$_compactTodoLinkActionPrefix${note.id}',
            icon: Icons.notes_outlined,
            label: _displayPaperTitle(note),
          ),
      ],
      _todoItemMenuDivider(),
      _todoActionMenuItem(
        value:
            '$_compactTodoColumnActionPrefix$_columnActionInsertBeforePrefix$normalizedColumnIndex',
        icon: Icons.add_box_outlined,
        label: widget.standaloneSurface
            ? strings.get(PaperTodoStringKeys.menuInsertTodoColumnBefore)
            : strings.format(PaperTodoStringKeys.actionInsertBeforeColumn, [
                normalizedColumnIndex + 1,
              ]),
        enabled: item.todoColumnCount < TodoColumnLimits.maxCount,
      ),
      _todoActionMenuItem(
        value:
            '$_compactTodoColumnActionPrefix$_columnActionDeletePrefix$normalizedColumnIndex',
        icon: Icons.delete_sweep_outlined,
        label: widget.standaloneSurface
            ? strings.get(PaperTodoStringKeys.menuDeleteTodoColumn)
            : strings.format(PaperTodoStringKeys.actionDeleteColumn, [
                normalizedColumnIndex + 1,
              ]),
        enabled: item.todoColumnCount > 1,
      ),
      _todoActionMenuItem(
        value: '$_compactTodoColumnActionPrefix$_columnActionAdd',
        icon: Icons.add,
        label: widget.standaloneSurface
            ? strings.get(PaperTodoStringKeys.menuIncreaseTodoColumns)
            : strings.get(PaperTodoStringKeys.actionAddColumn),
        enabled: item.todoColumnCount < TodoColumnLimits.maxCount,
      ),
      _todoActionMenuItem(
        value: '$_compactTodoColumnActionPrefix$_columnActionRemove',
        icon: Icons.remove,
        label: widget.standaloneSurface
            ? strings.get(PaperTodoStringKeys.menuDecreaseTodoColumns)
            : strings.get(PaperTodoStringKeys.actionRemoveLastColumn),
        enabled: item.todoColumnCount > 1,
      ),
      if (!widget.standaloneSurface) ...[
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
        _todoItemMenuDivider(),
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
      ],
      _todoItemMenuDivider(),
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

  PopupMenuItem<String> _todoItemMenuHeader(String label) {
    if (!widget.standaloneSurface) {
      return _paperTodoMenuHeader(label);
    }
    return PopupMenuItem<String>(
      enabled: false,
      height: 17,
      padding: _paperTodoStandalonePopupMenuItemPadding,
      child: _PaperTodoPopupMenuHeaderLabel(label),
    );
  }

  PopupMenuDivider _todoItemMenuDivider() {
    return PopupMenuDivider(height: widget.standaloneSurface ? 7 : 16);
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

  Widget? _todoDueIndicator(
    BuildContext context,
    PaperItem item,
    _TodoVisualSpec visualSpec, {
    required bool showRelativeBadge,
  }) {
    final dueAt = parsePaperTodoDueAtLocal(item.dueAtLocal);
    if (dueAt == null) {
      return null;
    }
    final paperColors = PaperTodoThemeColors.of(context);
    final difference = dueAt.difference(DateTime.now());
    final isPastDue = difference.isNegative;
    final isSoon = !isPastDue && difference <= const Duration(minutes: 10);
    final hovered = _hoveredTodoDueItemId == item.id;
    final pressed = _pressedTodoDueItemId == item.id;
    final statusColor = isPastDue
        ? paperColors.danger
        : isSoon
            ? paperColors.active
            : paperColors.weakText;
    final statusBackground = isPastDue
        ? paperColors.danger.withValues(
            alpha: paperColors.isDark ? 28 / 255 : 18 / 255,
          )
        : isSoon
            ? paperColors.tint.withValues(
                alpha: paperColors.isDark ? 42 / 255 : 28 / 255,
              )
            : paperColors.tint.withValues(
                alpha: paperColors.isDark ? 28 / 255 : 18 / 255,
              );
    final hoveredBackground = isPastDue
        ? paperColors.danger.withValues(
            alpha: paperColors.isDark ? 42 / 255 : 30 / 255,
          )
        : paperColors.hover;
    final badgeMinHeight = math.max(22.0, visualSpec.rowMinHeight - 2);
    final absolute = _formatAbsoluteDueDate(dueAt);
    final relative = _formatRelativeDueDate(dueAt);
    final label = strings.format(PaperTodoStringKeys.dueLabel, [
      widget.showDueRelativeTime ? '$relative, $absolute' : absolute,
    ]);
    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showRelativeBadge) ...[
            Container(
              key: ValueKey(
                '${widget.paper.id}-${item.id}-due-relative-surface',
              ),
              margin: const EdgeInsets.only(left: 1),
              constraints: BoxConstraints(minHeight: badgeMinHeight),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isPastDue
                    ? paperColors.danger.withValues(
                        alpha: paperColors.isDark ? 22 / 255 : 14 / 255,
                      )
                    : paperColors.tint.withValues(
                        alpha: paperColors.isDark ? 24 / 255 : 16 / 255,
                      ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Transform.translate(
                    offset: const Offset(0, 1),
                    child: Text(
                      relative,
                      key: ValueKey(
                        '${widget.paper.id}-${item.id}-due-relative',
                      ),
                      maxLines: 1,
                      softWrap: false,
                      style: _todoChipTextStyle(visualSpec)?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.04,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(left: 1),
            child: Opacity(
              key: ValueKey(
                '${widget.paper.id}-${item.id}-due-absolute-opacity',
              ),
              opacity: pressed ? 0.72 : 1,
              child: Material(
                key: ValueKey(
                  '${widget.paper.id}-${item.id}-due-absolute-surface',
                ),
                color: hovered ? hoveredBackground : statusBackground,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('${widget.paper.id}-${item.id}-due-absolute'),
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  onHover: (value) {
                    setState(() {
                      _hoveredTodoDueItemId = value ? item.id : null;
                      if (!value && _pressedTodoDueItemId == item.id) {
                        _pressedTodoDueItemId = null;
                      }
                    });
                  },
                  onTapDown: (_) =>
                      setState(() => _pressedTodoDueItemId = item.id),
                  onTapCancel: () {
                    if (_pressedTodoDueItemId == item.id) {
                      setState(() => _pressedTodoDueItemId = null);
                    }
                  },
                  onTapUp: (_) {
                    if (_pressedTodoDueItemId == item.id) {
                      setState(() => _pressedTodoDueItemId = null);
                    }
                  },
                  onTap: () => unawaited(_pickDueDate(context, item)),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: math.max(
                        38.0,
                        visualSpec.checkColumnWidth * 1.5,
                      ),
                      minHeight: badgeMinHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            absolute,
                            maxLines: 1,
                            softWrap: false,
                            style: _todoChipTextStyle(visualSpec)?.copyWith(
                              color: hovered ? paperColors.text : statusColor,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.04,
                            ),
                          ),
                        ),
                      ),
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

  Widget _noteLinkDropTarget(PaperItem item, Widget row) {
    final paperColors = PaperTodoThemeColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          _canAcceptNoteLinkDrop(details.data),
      onAcceptWithDetails: (details) => _linkNote(item, details.data),
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.whereType<String>().any(
              _canAcceptNoteLinkDrop,
            );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: highlighted
                ? paperColors.tint.withValues(
                    alpha: isDark ? 36 / 255 : 28 / 255,
                  )
                : Colors.transparent,
            border: Border.all(
              color: highlighted
                  ? paperColors.tint.withValues(alpha: 150 / 255)
                  : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(8),
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
        SizedBox(
          key: ValueKey('${widget.paper.id}-${item.id}-drag-handle-slot'),
          width: visualSpec.dragHandleSlotWidth,
          height: visualSpec.rowMinHeight,
          child: Center(
            child: Draggable<PaperItem>(
              key: ValueKey('${widget.paper.id}-${item.id}-drag-handle'),
              data: item,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: _todoDragFeedback(item, visualSpec),
              childWhenDragging: _standaloneTodoDragHandle(
                item,
                visualSpec,
                dragging: true,
              ),
              onDragStarted: () => _setTodoItemDragging(true, itemId: item.id),
              onDragCompleted: () => _setTodoItemDragging(false),
              onDraggableCanceled: (_, __) => _setTodoItemDragging(false),
              onDragEnd: (_) => _setTodoItemDragging(false),
              child: _standaloneTodoDragHandle(item, visualSpec),
            ),
          ),
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
                        ? strings.format(
                            PaperTodoStringKeys.menuEditLinkedScriptCapsule,
                            [_displayPaperTitle(linkedNote)],
                          )
                        : strings.format(
                            PaperTodoStringKeys.menuOpenLinkedNote,
                            [_displayPaperTitle(linkedNote)],
                          ),
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
        onDragStarted: () => _setTodoItemDragging(true, itemId: item.id),
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
              _todoActionMenuItem(
                value: _columnActionAdd,
                enabled: item.todoColumnCount < TodoColumnLimits.maxCount,
                icon: Icons.add,
                label: strings.get(PaperTodoStringKeys.actionAddColumn),
              ),
              _todoActionMenuItem(
                value: _columnActionRemove,
                enabled: item.todoColumnCount > 1,
                icon: Icons.remove,
                label: strings.get(PaperTodoStringKeys.actionRemoveLastColumn),
              ),
              const PopupMenuDivider(),
              for (var columnIndex = 0;
                  columnIndex < item.todoColumnCount;
                  columnIndex++)
                _todoActionMenuItem(
                  value: '$_columnActionInsertBeforePrefix$columnIndex',
                  enabled: item.todoColumnCount < TodoColumnLimits.maxCount,
                  icon: Icons.add_box_outlined,
                  label: strings.format(
                    PaperTodoStringKeys.actionInsertBeforeColumn,
                    [columnIndex + 1],
                  ),
                ),
              for (var columnIndex = 0;
                  columnIndex < item.todoColumnCount;
                  columnIndex++)
                _todoActionMenuItem(
                  value: '$_columnActionDeletePrefix$columnIndex',
                  enabled: item.todoColumnCount > 1,
                  icon: Icons.delete_sweep_outlined,
                  label: strings.format(
                    PaperTodoStringKeys.actionDeleteColumn,
                    [columnIndex + 1],
                  ),
                ),
              const PopupMenuDivider(),
              _todoActionMenuItem(
                value: _columnActionEqualWidths,
                enabled: item.todoColumnCount > 1,
                icon: Icons.view_column_outlined,
                label: strings.get(PaperTodoStringKeys.actionEqualWidths),
              ),
              _todoActionMenuItem(
                value: _columnActionWideFirst,
                enabled: item.todoColumnCount > 1,
                icon: Icons.view_week_outlined,
                label: strings.get(PaperTodoStringKeys.actionWideFirstColumn),
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
          icon: Icon(
            item.linkedNoteId == null
                ? Icons.note_add_outlined
                : Icons.link_outlined,
          ),
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
    ];
  }

  Widget _standaloneTodoDragHandle(
    PaperItem item,
    _TodoVisualSpec visualSpec, {
    bool dragging = false,
  }) {
    final hovered = _hoveredTodoDragHandleItemId == item.id;
    final paperColors = PaperTodoThemeColors.of(context);
    return _maybeTooltip(
      enabled: widget.enableToolTips,
      message: strings.get(PaperTodoStringKeys.actionDragToReorder),
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        onEnter: (_) {
          if (_hoveredTodoDragHandleItemId != item.id) {
            setState(() => _hoveredTodoDragHandleItemId = item.id);
          }
        },
        onExit: (_) {
          if (_hoveredTodoDragHandleItemId == item.id && !dragging) {
            setState(() => _hoveredTodoDragHandleItemId = null);
          }
        },
        child: SizedBox(
          width: visualSpec.dragHandleWidth,
          height: visualSpec.rowMinHeight,
          child: Center(
            child: Opacity(
              opacity: dragging ? 0.9 : (hovered ? 0.78 : 0.48),
              child: Text(
                '\u2261',
                style: TextStyle(
                  color: paperColors.weakText,
                  fontFamily: 'Segoe UI Symbol',
                  fontFamilyFallback: const <String>['Segoe UI Emoji'],
                  fontSize: visualSpec.dragGlyphSize,
                  height: 1,
                ),
              ),
            ),
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
    if (widget.standaloneSurface) {
      return _PaperTodoPopupMenuItem<String>(
        value: value,
        enabled: enabled,
        height: 21,
        padding: _paperTodoStandalonePopupMenuItemPadding,
        child: Text(label),
      );
    }
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      height: _paperTodoPopupMenuHeight(),
      padding: _paperTodoPopupMenuItemPadding,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
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
      _clearEnteringTodoRows();
      _clearDepartingTodoRows();
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
    final beforeById = {
      for (final item in beforeItems)
        if (item.id.trim().isNotEmpty) item.id: item,
    };
    for (final item in afterItems) {
      final previous = beforeById[item.id];
      if (previous == null || _todoReminderFieldsChanged(previous, item)) {
        widget.onReminderReset(item);
      }
    }
    _requestTodoFocus();
    unawaited(widget.onChanged());
  }

  bool _todoReminderFieldsChanged(PaperItem before, PaperItem after) {
    return before.dueAtLocal != after.dueAtLocal ||
        before.reminderIntervalValue != after.reminderIntervalValue ||
        before.reminderIntervalUnit != after.reminderIntervalUnit;
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
    final focusNode = _todoMainFieldFocusNodes.putIfAbsent(item.id, () {
      final node = FocusNode(debugLabel: 'todo-main-${item.id}');
      node.addListener(() => _handleMainTodoFieldFocusChange(item.id, node));
      return node;
    });
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
    final focusNode = _todoExtraFieldFocusNodes.putIfAbsent(focusKey, () {
      final node = FocusNode(debugLabel: 'todo-extra-$focusKey');
      node.addListener(
        () => _handleExtraTodoFieldFocusChange(item.id, index, node),
      );
      return node;
    });
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < visualSpec.checkColumnWidth) {
          return SizedBox(height: visualSpec.rowMinHeight);
        }
        if (item.todoColumnCount <= 1) {
          return fields.first;
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: _columnFlex(item, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: SizedBox(
                      width: double.infinity,
                      child: fields.first,
                    ),
                  ),
                ),
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
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 6,
                        right: index == fields.length - 1 ? 0 : 3,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: fields[index],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _todoColumnSplitter({
    required BuildContext context,
    required PaperItem item,
    required int leftColumnIndex,
    required double availableWidth,
  }) {
    final paperColors = PaperTodoThemeColors.of(context);
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
          child: CustomPaint(
            painter: _TodoColumnSeparatorPainter(
              paperColors.paperBorder.withValues(alpha: 0.9),
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

    widths[leftColumnIndex] = _roundTodoColumnWidth(
      widths[leftColumnIndex] + appliedDelta,
    );
    widths[leftColumnIndex + 1] = _roundTodoColumnWidth(
      widths[leftColumnIndex + 1] - appliedDelta,
    );
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

  Widget _todoTextContextMenuBuilder(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    if (Platform.isWindows) {
      // Todo rows already expose the PaperTodo item menu on secondary click.
      // Suppress Flutter's overlapping Cut/Copy/Paste/Select-all toolbar so
      // the user sees only actions that belong to the todo item itself.
      return const SizedBox.shrink(
        key: ValueKey('todo-text-context-menu-suppressed'),
      );
    }
    final buttonItems = editableTextState.contextMenuButtonItems
        .where(
          (item) =>
              item.type != ContextMenuButtonType.paste &&
              item.type != ContextMenuButtonType.selectAll,
        )
        .toList();
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  Widget _mainColumnField(
    BuildContext context,
    PaperItem item,
    TextStyle? itemTextStyle,
    _TodoVisualSpec visualSpec,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final paperColors = PaperTodoThemeColors.of(context);
    _queueTodoLineMeasurement(item);
    return KeyedSubtree(
      key: ValueKey('${widget.paper.id}-${item.id}-text'),
      child: KeyedSubtree(
        key: _todoColumnHitTestKey(item, 0),
        child: _todoItemKeyboardScope(
          item,
          NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (_) {
              _queueTodoLineMeasurement(item);
              return false;
            },
            child: SizeChangedLayoutNotifier(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: visualSpec.rowMinHeight),
                child: Stack(
                  children: [
                    TextFormField(
                      key: ValueKey(
                        '${widget.paper.id}-${item.id}-text-field-$_textFieldRevision',
                      ),
                      focusNode: _mainTodoFieldFocusNode(item),
                      initialValue: item.text,
                      keyboardType: TextInputType.multiline,
                      minLines: 1,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.center,
                      textInputAction: TextInputAction.next,
                      contextMenuBuilder: _todoTextContextMenuBuilder,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        hintText: strings.get(
                          PaperTodoStringKeys.todoNewItemHint,
                        ),
                        isDense: true,
                        isCollapsed: true,
                        contentPadding: visualSpec.mainContentPadding,
                      ),
                      style: itemTextStyle?.copyWith(
                        color: item.done
                            ? paperColors.brightWeakText
                            : colorScheme.onSurface,
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
                        LengthLimitingTextInputFormatter(
                          TodoPasteItems.maxLineLength,
                        ),
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
                    if (item.done)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            key: ValueKey(
                              '${widget.paper.id}-${item.id}-completion-line-main',
                            ),
                            painter: _TodoCompletionLinePainter(
                              paperColors.brightWeakText.withValues(
                                alpha: 205 / 255,
                              ),
                            ),
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
    );
  }

  void _queueTodoLineMeasurement(PaperItem item) {
    if (!_queuedTodoLineMeasurements.add(item.id)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queuedTodoLineMeasurements.remove(item.id);
      if (!mounted ||
          _todoItemById(item.id) == null ||
          _departingTodoRows.any(
            (departure) => departure.item.id == item.id,
          )) {
        return;
      }
      final editableState = _editableTextStateFor(
        _todoMainFieldFocusNodes[item.id]?.context,
      );
      final renderEditable = editableState?.renderEditable;
      if (renderEditable == null || !renderEditable.attached) {
        return;
      }
      final firstLine = renderEditable.getLineAtOffset(
        const TextPosition(offset: 0, affinity: TextAffinity.downstream),
      );
      final rowRenderObject =
          _todoDropTargetKeys[item.id]?.currentContext?.findRenderObject();
      final rowWidth = rowRenderObject is RenderBox && rowRenderObject.hasSize
          ? rowRenderObject.size.width
          : null;
      final previousText = _todoLineMeasurementTexts[item.id];
      final previousRowWidth = _todoLineMeasurementRowWidths[item.id];
      final textChanged = previousText != null && previousText != item.text;
      final rowWidthChanged = rowWidth != null &&
          previousRowWidth != null &&
          (rowWidth - previousRowWidth).abs() > 0.5;
      var multiline = item.text.contains('\n') ||
          item.text.contains('\r') ||
          firstLine.end < item.text.length;
      if (!multiline &&
          _multilineTodoItemIds.contains(item.id) &&
          !textChanged &&
          !rowWidthChanged) {
        multiline = true;
      }
      _todoLineMeasurementTexts[item.id] = item.text;
      if (rowWidth != null) {
        _todoLineMeasurementRowWidths[item.id] = rowWidth;
      }
      if (_multilineTodoItemIds.contains(item.id) == multiline) {
        return;
      }
      setState(() {
        if (multiline) {
          _multilineTodoItemIds.add(item.id);
        } else {
          _multilineTodoItemIds.remove(item.id);
        }
      });
    });
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
      if (widget.enableAnimations && newItems.length > 1) {
        for (var index = 0; index < math.min(newItems.length, 15); index++) {
          _queueTodoEntrance(
            _EnteringTodoRow(
              itemId: newItems[index].id,
              delay: PaperTodoMotion.stagger(
                PaperTodoMotion.todoPasteDelayUnit,
                index,
              ),
              opacityDuration: PaperTodoMotion.fadeIn,
              slideDuration: PaperTodoMotion.moveLong,
              slideDistance: 15,
              slideCurve: PaperTodoMotion.quickCurve,
            ),
          );
        }
      }
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
    final paperColors = PaperTodoThemeColors.of(context);
    return KeyedSubtree(
      key: _todoColumnHitTestKey(item, index + 1),
      child: _todoItemKeyboardScope(
        item,
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: visualSpec.rowMinHeight),
          child: Stack(
            children: [
              TextFormField(
                key: ValueKey(
                  '${widget.paper.id}-${item.id}-column-${index + 2}',
                ),
                focusNode: _extraTodoFieldFocusNode(item, index),
                initialValue: item.todoExtraColumns[index],
                keyboardType: TextInputType.multiline,
                minLines: 1,
                maxLines: null,
                textAlignVertical: TextAlignVertical.center,
                textInputAction: TextInputAction.next,
                contextMenuBuilder: _todoTextContextMenuBuilder,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  isCollapsed: true,
                  contentPadding: visualSpec.extraContentPadding,
                ),
                style: itemTextStyle?.copyWith(
                  color: item.done
                      ? paperColors.brightWeakText
                      : colorScheme.onSurface,
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
                  LengthLimitingTextInputFormatter(
                    TodoPasteItems.maxLineLength,
                  ),
                ],
                onChanged: (value) {
                  if (_handleMultiLinePaste(
                    item,
                    value,
                    extraColumnIndex: index,
                  )) {
                    return;
                  }
                  _recordTodoTextInput(item, index, value);
                  unawaited(widget.onChanged());
                },
                onFieldSubmitted: (_) => _insertItemAfter(item),
              ),
              if (item.done)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      key: ValueKey(
                        '${widget.paper.id}-${item.id}-completion-line-${index + 2}',
                      ),
                      painter: _TodoCompletionLinePainter(
                        paperColors.brightWeakText.withValues(alpha: 205 / 255),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _setTodoColumnText(PaperItem item, int? extraColumnIndex, String value) {
    if (extraColumnIndex == null) {
      item.text = value;
      return;
    }
    item.todoExtraColumns[extraColumnIndex] = value;
  }

  void _recordTodoTextInput(PaperItem item, int? columnIndex, String value) {
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

  void _setTodoItemDragging(bool value, {String? itemId}) {
    final nextItemId = value ? itemId : null;
    if (!mounted ||
        (_isDraggingTodoItem == value && _draggingTodoItemId == nextItemId)) {
      return;
    }
    setState(() {
      _isDraggingTodoItem = value;
      _draggingTodoItemId = nextItemId;
    });
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
      if (widget.enableAnimations) {
        _queueTodoEntrance(
          _EnteringTodoRow(
            itemId: newItem.id,
            delay: Duration.zero,
            opacityDuration: PaperTodoMotion.rowEntrance,
            slideDuration: PaperTodoMotion.rowEntrance,
            slideDistance: 20,
            slideCurve: PaperTodoMotion.enterCurve,
          ),
        );
      }
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
        PaperItem(id: '$idSeed-${lineIndex++}', text: line),
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
      _enteringTodoRows.remove(item.id);
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
    final animatedCompletedItems = widget.enableAnimations
        ? completedItems.take(15).toList(growable: false)
        : const <PaperItem>[];
    final departureGroup = Object();
    final originalIndexes = <String, int>{
      for (var index = 0; index < widget.paper.items.length; index++)
        widget.paper.items[index].id: index,
    };

    _pushTodoUndoSnapshot();
    for (final item in completedItems) {
      _unfocusTodoItem(item);
    }
    String? focusTargetId;
    setState(() {
      _clearEnteringTodoRows();
      _clearDepartingTodoRows();
      for (var index = 0; index < animatedCompletedItems.length; index++) {
        final item = animatedCompletedItems[index];
        _departingTodoRows.add(
          _DepartingTodoRow(
            item: item,
            originalIndex: originalIndexes[item.id] ?? index,
            groupToken: departureGroup,
            delay: PaperTodoMotion.stagger(
              PaperTodoMotion.todoCompletionDelayUnit,
              index,
            ),
            duration: PaperTodoMotion.fadeOut,
            slideDistance: 20,
            completesGroup: index == animatedCompletedItems.length - 1,
          ),
        );
      }
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
      _enteringTodoRows.remove(item.id);
      _clearDepartingTodoRows();
      if (widget.enableAnimations) {
        final departureGroup = Object();
        _departingTodoRows.add(
          _DepartingTodoRow(
            item: item,
            originalIndex: removedIndex,
            groupToken: departureGroup,
            delay: Duration.zero,
            duration: PaperTodoMotion.move,
            slideDistance: 30,
            completesGroup: true,
          ),
        );
      }
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
        duration: const Duration(seconds: 10),
        content: Text(
          strings.format(PaperTodoStringKeys.todoItemDeleted, [
            _displayItemText(item),
          ]),
        ),
        action: SnackBarAction(
          label: strings.get(PaperTodoStringKeys.actionUndo),
          onPressed: () {
            setState(() {
              _clearEnteringTodoRows();
              _clearDepartingTodoRows();
              if (fallbackItemId != null) {
                widget.paper.items.removeWhere(
                  (candidate) => candidate.id == fallbackItemId,
                );
              }
              final targetIndex =
                  removedIndex.clamp(0, widget.paper.items.length).toInt();
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
    final existingDueDate = parsePaperTodoDueAtLocal(item.dueAtLocal);
    final initialDate = existingDueDate ?? now.add(const Duration(hours: 1));
    if (widget.standaloneSurface && Platform.isWindows) {
      // A null native result means the user cancelled. Falling through to the
      // Flutter dialog would show a second picker for the same action.
      final result = await _pickNativeWindowsDueDate(
        initialDate,
        openCalendar: existingDueDate == null,
      );
      if (result == null) {
        return;
      }
      _applyDueSelection(item, result, initialDate);
      return;
    }
    final result = await showDialog<_TodoDueSelection>(
      context: context,
      builder: (context) => _TodoDueSelectionDialog(initialDate: initialDate),
    );
    if (result == null) {
      return;
    }
    _applyDueSelection(item, result, initialDate);
  }

  void _applyDueSelection(
    PaperItem item,
    _TodoDueSelection selection,
    DateTime initialDate,
  ) {
    _pushTodoUndoSnapshot();
    setState(() {
      item.dueAtLocal = selection.clear
          ? null
          : _formatDueAtLocalValue(selection.dueAt ?? initialDate);
    });
    widget.onReminderReset(item);
    unawaited(widget.onPersist());
  }

  Future<_TodoDueSelection?> _pickNativeWindowsDueDate(
    DateTime initialDate, {
    required bool openCalendar,
  }) async {
    try {
      final colorScheme = Theme.of(context).colorScheme;
      final paperColors = PaperTodoThemeColors.of(context);
      final result = await _paperWindowMethodChannel
          .invokeMapMethod<String, Object?>('pickDateTime', <String, Object?>{
        'year': initialDate.year,
        'month': initialDate.month,
        'day': initialDate.day,
        'hour': initialDate.hour,
        'minute': initialDate.minute,
        'openCalendar': openCalendar,
        'title': strings.get(PaperTodoStringKeys.dialogDueDate),
        'message': strings.get(PaperTodoStringKeys.dialogDueDateMessage),
        'clearLabel': strings.get(PaperTodoStringKeys.actionClear),
        'cancelLabel': strings.get(PaperTodoStringKeys.actionCancel),
        'okLabel': strings.get(PaperTodoStringKeys.dialogDueDateConfirm),
        'fontFamily': widget.nativeDialogFontFamily,
        'backgroundColor': colorScheme.surface.toARGB32(),
        'borderColor': colorScheme.outlineVariant.toARGB32(),
        'accentColor': colorScheme.primary.toARGB32(),
        'primaryTextColor': colorScheme.onPrimary.toARGB32(),
        'textColor': colorScheme.onSurface.toARGB32(),
        'weakTextColor': colorScheme.onSurfaceVariant.toARGB32(),
        'inputBackgroundColor': _paperTodoBlend(
          paperColors.paper,
          paperColors.tint,
          paperColors.isDark ? 22 : 12,
        ).toARGB32(),
        'secondaryButtonColor': _paperTodoBlend(
          paperColors.paper,
          paperColors.tint,
          paperColors.isDark ? 48 : 32,
        ).toARGB32(),
      });
      if (result == null) return null;
      if (result['clear'] == true) return const _TodoDueSelection.clear();
      final year = result['year'];
      final month = result['month'];
      final day = result['day'];
      final hour = result['hour'];
      final minute = result['minute'];
      if ([year, month, day, hour, minute].any((value) => value is! num)) {
        return null;
      }
      return _TodoDueSelection.set(
        DateTime(
          (year as num).toInt(),
          (month as num).toInt(),
          (day as num).toInt(),
          (hour as num).toInt(),
          (minute as num).toInt(),
        ),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  void _clearDueDate(PaperItem item) {
    if (!_hasDueDate(item)) {
      return;
    }
    _pushTodoUndoSnapshot();
    setState(() => item.dueAtLocal = null);
    widget.onReminderReset(item);
    unawaited(widget.onPersist());
  }

  Future<void> _pickReminderInterval(
    BuildContext context,
    PaperItem item,
  ) async {
    final initialValue =
        item.reminderIntervalValue ?? widget.defaultReminderIntervalValue;
    final initialUnit =
        item.reminderIntervalUnit ?? widget.defaultReminderIntervalUnit;
    final _ReminderIntervalSelection? result;
    if (widget.standaloneSurface && Platform.isWindows) {
      result = await _pickNativeWindowsReminderInterval(
        initialValue,
        initialUnit,
      );
    } else {
      result = await showDialog<_ReminderIntervalSelection>(
        context: context,
        builder: (context) => _ReminderIntervalDialog(
          initialValue: initialValue,
          initialUnit: initialUnit,
        ),
      );
    }
    final selection = result;
    if (selection == null) {
      return;
    }
    _pushTodoUndoSnapshot();
    setState(() {
      if (selection.clear) {
        item.reminderIntervalValue = null;
        item.reminderIntervalUnit = null;
      } else {
        item.reminderIntervalValue = selection.value;
        item.reminderIntervalUnit = selection.unit;
      }
    });
    widget.onReminderReset(item);
    unawaited(widget.onPersist());
  }

  Future<_ReminderIntervalSelection?> _pickNativeWindowsReminderInterval(
    int initialValue,
    String initialUnit,
  ) async {
    try {
      final colorScheme = Theme.of(context).colorScheme;
      final paperColors = PaperTodoThemeColors.of(context);
      final result = await _paperWindowMethodChannel
          .invokeMapMethod<String, Object?>(
              'pickReminderInterval', <String, Object?>{
        'value': initialValue.clamp(1, 240),
        'unit': TodoReminderIntervalUnits.normalize(initialUnit),
        'title': strings.get(PaperTodoStringKeys.reminderInterval),
        'message': strings.get(PaperTodoStringKeys.reminderIntervalMessage),
        'globalLabel': strings.get(
          PaperTodoStringKeys.reminderIntervalGlobal,
        ),
        'cancelLabel': strings.get(PaperTodoStringKeys.actionCancel),
        'okLabel': strings.get(PaperTodoStringKeys.dialogDueDateConfirm),
        'minutesLabel': strings.get(PaperTodoStringKeys.minutes),
        'hoursLabel': strings.get(PaperTodoStringKeys.hours),
        'fontFamily': widget.nativeDialogFontFamily,
        'backgroundColor': colorScheme.surface.toARGB32(),
        'borderColor': colorScheme.outlineVariant.toARGB32(),
        'accentColor': colorScheme.primary.toARGB32(),
        'primaryTextColor': colorScheme.onPrimary.toARGB32(),
        'textColor': colorScheme.onSurface.toARGB32(),
        'weakTextColor': colorScheme.onSurfaceVariant.toARGB32(),
        'inputBackgroundColor': _paperTodoBlend(
          paperColors.paper,
          paperColors.tint,
          paperColors.isDark ? 22 : 12,
        ).toARGB32(),
        'secondaryButtonColor': _paperTodoBlend(
          paperColors.paper,
          paperColors.tint,
          paperColors.isDark ? 48 : 32,
        ).toARGB32(),
      });
      if (result == null) return null;
      if (result['clear'] == true) {
        return const _ReminderIntervalSelection.clear();
      }
      final value = result['value'];
      final unit = result['unit'];
      if (value is! num || unit is! String) {
        return null;
      }
      return _ReminderIntervalSelection.set(
        value.toInt().clamp(1, 240),
        TodoReminderIntervalUnits.normalize(unit),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
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
    unawaited(widget.onPersist());
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

  Widget _linkedNoteButton(
    PaperData linkedNote,
    PaperItem item,
    _TodoVisualSpec visualSpec,
  ) {
    final paperColors = PaperTodoThemeColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hovered = _hoveredTodoLinkedNoteItemId == item.id;
    final pressed = _pressedTodoLinkedNoteItemId == item.id;
    final scriptSpec = widget.runLinkedScriptCapsulesOnClick
        ? ScriptCapsuleSpec.tryParse(linkedNote.content)
        : null;
    final isScriptCapsule = scriptSpec != null;
    final multiline = _multilineTodoItemIds.contains(item.id) ||
        item.text.contains('\n') ||
        item.text.contains('\r');
    final showName = widget.showLinkedNoteName;
    final compactTitle = _compactLinkedNoteTitle(
      _displayPaperTitle(linkedNote),
      multiline: multiline,
    );
    final label = isScriptCapsule && widget.standaloneSurface
        ? '⚡ $compactTitle'
        : isScriptCapsule
            ? '⚡$compactTitle'
            : compactTitle;
    final minWidth = math.max(23.0, visualSpec.checkColumnWidth);
    final legacyWidth = multiline
        ? math.max(
            isScriptCapsule ? 52.0 : 44.0,
            visualSpec.checkColumnWidth * (isScriptCapsule ? 2.35 : 2),
          )
        : math.max(
            isScriptCapsule ? 58.0 : 50.0,
            visualSpec.checkColumnWidth * (isScriptCapsule ? 2.55 : 2.2),
          );
    final labelStyle = _todoChipTextStyle(visualSpec)?.copyWith(height: 1.05);
    final measuredLabelWidth = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: Directionality.of(context),
      maxLines: multiline ? 2 : 1,
    )..layout();
    final buttonWidth = showName
        ? (widget.allowLongLinkedNoteTitles
            ? math.max(
                legacyWidth,
                (measuredLabelWidth.width.ceil() + 10).toDouble(),
              )
            : legacyWidth)
        : minWidth;
    final tooltip = isScriptCapsule
        ? strings.get(PaperTodoStringKeys.actionRunLinkedScriptCapsule)
        : strings.get(PaperTodoStringKeys.actionOpenLinkedNote);
    final button = Opacity(
      opacity: pressed ? 0.72 : 1,
      child: Material(
        key: ValueKey('${widget.paper.id}-${item.id}-linked-note-button'),
        color: paperColors.tint.withValues(
          alpha: hovered
              ? (isDark ? 48 / 255 : 34 / 255)
              : (isDark ? 28 / 255 : 18 / 255),
        ),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          onHover: (value) {
            setState(() {
              _hoveredTodoLinkedNoteItemId = value ? item.id : null;
              if (!value && _pressedTodoLinkedNoteItemId == item.id) {
                _pressedTodoLinkedNoteItemId = null;
              }
            });
          },
          onTapDown: (_) =>
              setState(() => _pressedTodoLinkedNoteItemId = item.id),
          onTapCancel: () {
            if (_pressedTodoLinkedNoteItemId == item.id) {
              setState(() => _pressedTodoLinkedNoteItemId = null);
            }
          },
          onTapUp: (_) {
            if (_pressedTodoLinkedNoteItemId == item.id) {
              setState(() => _pressedTodoLinkedNoteItemId = null);
            }
          },
          onTap: () {
            if (scriptSpec != null) {
              unawaited(widget.onRunScriptCapsule(scriptSpec));
              return;
            }
            unawaited(widget.onOpenLinkedNote(linkedNote, widget.paper));
          },
          child: SizedBox(
            width: buttonWidth,
            height: math.max(22, visualSpec.rowMinHeight - 2),
            child: Center(
              child: showName
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 1,
                      ),
                      child: Text(
                        label,
                        maxLines: multiline ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: labelStyle?.copyWith(
                          color: hovered
                              ? paperColors.text
                              : paperColors.weakText.withValues(alpha: 0.72),
                        ),
                      ),
                    )
                  : widget.standaloneSurface
                      ? Text(
                          isScriptCapsule ? '⚡' : '\uE71B',
                          style: TextStyle(
                            fontFamily: isScriptCapsule
                                ? 'Segoe UI Symbol'
                                : 'Segoe MDL2 Assets',
                            fontFamilyFallback: const <String>[
                              'Segoe UI Emoji'
                            ],
                            fontSize: visualSpec.chipIconSize +
                                (isScriptCapsule ? 1 : 0),
                            fontWeight: FontWeight.w600,
                            color: hovered
                                ? paperColors.text
                                : paperColors.weakText.withValues(alpha: 0.72),
                            height: 1,
                          ),
                        )
                      : Icon(
                          isScriptCapsule ? Icons.bolt : Icons.notes_outlined,
                          size: visualSpec.chipIconSize +
                              (isScriptCapsule ? 1 : 0),
                          color: hovered
                              ? paperColors.text
                              : paperColors.weakText.withValues(alpha: 0.72),
                        ),
            ),
          ),
        ),
      ),
    );
    return _conditionalTooltip(
      enabled: widget.enableToolTips,
      message: tooltip,
      child: button,
    );
  }

  TextStyle? _todoChipTextStyle(_TodoVisualSpec visualSpec) {
    return Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: visualSpec.chipFontSize,
          fontWeight: FontWeight.w600,
        );
  }

  String _compactLinkedNoteTitle(String title, {required bool multiline}) {
    final text = title.trim();
    if (text.isEmpty) return '';
    final runes = text.runes.toList(growable: false);
    if (!widget.allowLongLinkedNoteTitles) {
      final fullLimit = multiline ? 6 : 3;
      final keep = multiline ? 5 : 3;
      if (runes.length <= fullLimit) return text;
      return '${String.fromCharCodes(runes.take(keep))}…';
    }
    final fullWidthLimit = multiline ? 20 : 10;
    var width = 0;
    var keepCount = 0;
    for (final rune in runes) {
      final runeWidth = _isWideLinkedNoteRune(rune) ? 2 : 1;
      if (width > 0 && width + runeWidth > fullWidthLimit) break;
      width += runeWidth;
      keepCount += 1;
    }
    if (keepCount >= runes.length) return text;
    return '${String.fromCharCodes(runes.take(keepCount))}…';
  }

  bool _isWideLinkedNoteRune(int rune) {
    return (rune >= 0x1100 && rune <= 0x115F) ||
        (rune >= 0x2E80 && rune <= 0x303E) ||
        (rune >= 0x3041 && rune <= 0x33FF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0xA000 && rune <= 0xA4CF) ||
        (rune >= 0xAC00 && rune <= 0xD7A3) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0xFF00 && rune <= 0xFF60) ||
        (rune >= 0xFFE0 && rune <= 0xFFE6);
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
    final month = date.month.toString();
    final day = date.day.toString();
    final time = _formatDueTime(date);
    final yearDisplayMode = TodoDueYearDisplayModes.normalize(
      widget.dueYearDisplayMode,
    );
    return switch (yearDisplayMode) {
      TodoDueYearDisplayModes.short =>
        '${(date.year % 100).toString().padLeft(2, '0')}年$month/$day $time',
      TodoDueYearDisplayModes.full => '${date.year}年$month/$day $time',
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
    return '$month/$day $time';
  }

  String _formatDueTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDueAtLocalValue(DateTime date) {
    return formatPaperTodoDueAtLocal(date);
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
      if (days > 0)
        strings.format(PaperTodoStringKeys.relativeDueDayUnit, [days]),
      if (hours > 0)
        strings.format(PaperTodoStringKeys.relativeDueHourUnit, [hours]),
      if (minutes > 0 || (days == 0 && hours == 0))
        strings.format(PaperTodoStringKeys.relativeDueMinuteUnit, [
          minutes <= 0 ? 1 : minutes,
        ]),
    ];
    final text = parts.join();
    if (isPast) {
      return strings.format(PaperTodoStringKeys.relativeDueOverdue, [text]);
    }
    return strings.format(PaperTodoStringKeys.relativeDueFuture, [text]);
  }
}

class _HorizontalOverflowClip extends SingleChildRenderObjectWidget {
  const _HorizontalOverflowClip({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderHorizontalOverflowClip();
  }
}

class _RenderHorizontalOverflowClip extends RenderProxyBox {
  BoxConstraints _childConstraints(BoxConstraints parentConstraints) {
    return BoxConstraints(
      minWidth: 0,
      maxWidth: double.infinity,
      minHeight: parentConstraints.minHeight,
      maxHeight: parentConstraints.maxHeight,
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) {
      return constraints.smallest;
    }
    return constraints.constrain(
      child.getDryLayout(_childConstraints(constraints)),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      return;
    }
    if (child.size.width <= size.width && child.size.height <= size.height) {
      super.paint(context, offset);
      return;
    }
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (clipContext, clipOffset) => super.paint(clipContext, clipOffset),
    );
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
    final colors = PaperTodoThemeColors.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _handleDialogKeyEvent,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): _save,
          const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        },
        child: _PaperDialog(
          surfaceKey: const ValueKey('todo-due-dialog-surface'),
          width: 354,
          height: 242,
          radius: 12,
          padding: const EdgeInsets.all(16),
          contentSpacing: 8,
          actionSpacing: 16,
          actionsGap: 6,
          title: strings.get(PaperTodoStringKeys.dialogDueDate),
          content: SizedBox(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.get(PaperTodoStringKeys.dialogDueDateMessage),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          key: const ValueKey('todo-due-date'),
                          borderRadius: BorderRadius.circular(4),
                          onTap: _pickDate,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.tint.withValues(
                                alpha: colors.isDark ? 22 / 255 : 12 / 255,
                              ),
                              border: Border.all(
                                color: colors.tint.withValues(alpha: 80 / 255),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _formatDate(_selectedDate),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: colors.text,
                                        fontSize: 13,
                                        height: 1.15,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.calendar_month_outlined,
                                    size: 16,
                                    color: colors.weakText,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 74,
                        child: _TodoDialogDropdown<int>(
                          dropdownKey: const ValueKey('todo-due-hour'),
                          value: _hour,
                          items: _timeItems(24),
                          onChanged: (value) => setState(() => _hour = value),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 74,
                        child: _TodoDialogDropdown<int>(
                          dropdownKey: const ValueKey('todo-due-minute'),
                          value: _minute,
                          items: _timeItems(60),
                          onChanged: (value) => setState(() => _minute = value),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _cancel,
              style: _todoDialogActionStyle(context),
              child: Text(strings.get(PaperTodoStringKeys.actionCancel)),
            ),
            TextButton(
              onPressed: _clear,
              style: _todoDialogActionStyle(context),
              child: Text(strings.get(PaperTodoStringKeys.actionClear)),
            ),
            FilledButton(
              onPressed: _save,
              style: _todoDialogActionStyle(context, primary: true),
              child: Text(
                strings.get(PaperTodoStringKeys.dialogDueDateConfirm),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<DropdownMenuItem<int>> _timeItems(int count) {
    return [
      for (var value = 0; value < count; value++)
        DropdownMenuItem(
          value: value,
          child: Center(child: Text(value.toString().padLeft(2, '0'))),
        ),
    ];
  }

  String _formatDate(DateTime date) {
    final languageCode = Localizations.localeOf(context).languageCode;
    if (languageCode == 'zh') {
      return '${date.year}/${date.month}/${date.day}';
    }
    return '${date.month}/${date.day}/${date.year}';
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: PaperTodoStringsScope.of(
        context,
      ).get(PaperTodoStringKeys.dialogDueDate),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (selected != null && mounted) {
      setState(() => _selectedDate = selected);
    }
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

class _TodoCompletionLinePainter extends CustomPainter {
  const _TodoCompletionLinePainter(this.color);

  final Color color;
  final double strokeWidth = 1.35;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final y = math.max(size.height / 2, 10.0);
    canvas.drawLine(
      Offset(3, y),
      Offset(math.max(3.0, size.width - 3), y),
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _TodoCompletionLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _TodoColumnSeparatorPainter extends CustomPainter {
  const _TodoColumnSeparatorPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 1 || size.height <= 8) {
      return;
    }
    final left = (size.width - 1) / 2;
    canvas.drawRect(
      Rect.fromLTWH(left, 4, 1, size.height - 8),
      Paint()
        ..color = color
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(covariant _TodoColumnSeparatorPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _PaperResizeGripPainter extends CustomPainter {
  const _PaperResizeGripPainter();

  final Color topLeftColor = const Color(0xFFFAFBFB);
  final Color topRightColor = const Color(0xFFC7CFDE);
  final Color bottomLeftColor = const Color(0xFFE4E8EF);
  final Color bottomRightColor = const Color(0xFFAAB7CD);
  final List<int> dotCountsByBottomRow = const [4, 3, 2, 1];

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    final origin = Offset(size.width - 4, size.height - 4);
    final paint = Paint()..isAntiAlias = false;
    for (var row = 0; row < dotCountsByBottomRow.length; row++) {
      for (var column = 0; column < dotCountsByBottomRow[row]; column++) {
        final topLeft = origin - Offset(column * gap, row * gap);
        canvas
          ..drawRect(
            Rect.fromLTWH(topLeft.dx, topLeft.dy, 1, 1),
            paint..color = topLeftColor,
          )
          ..drawRect(
            Rect.fromLTWH(topLeft.dx + 1, topLeft.dy, 1, 1),
            paint..color = topRightColor,
          )
          ..drawRect(
            Rect.fromLTWH(topLeft.dx, topLeft.dy + 1, 1, 1),
            paint..color = bottomLeftColor,
          )
          ..drawRect(
            Rect.fromLTWH(topLeft.dx + 1, topLeft.dy + 1, 1, 1),
            paint..color = bottomRightColor,
          );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PaperResizeGripPainter oldDelegate) {
    return oldDelegate.topLeftColor != topLeftColor ||
        oldDelegate.topRightColor != topRightColor ||
        oldDelegate.bottomLeftColor != bottomLeftColor ||
        oldDelegate.bottomRightColor != bottomRightColor ||
        !listEquals(oldDelegate.dotCountsByBottomRow, dotCountsByBottomRow);
  }
}

class _TodoVisualSpec {
  const _TodoVisualSpec({
    required this.textScale,
    required this.iconSize,
    required this.chipIconSize,
    required this.chipFontSize,
    required this.controlExtent,
    required this.itemGap,
    required this.rowMinHeight,
    required this.textVerticalPadding,
  });

  final double textScale;
  final double iconSize;
  final double chipIconSize;
  final double chipFontSize;
  final double controlExtent;
  final double itemGap;
  final double rowMinHeight;
  final double textVerticalPadding;

  double get checkColumnWidth => switch (controlExtent) {
        28 => 21,
        30 => 22,
        32 => 24,
        36 => 27,
        _ => math.max(21, controlExtent - 8),
      };

  double get dragHandleWidth => math.max(14, checkColumnWidth - 8);

  double get dragHandleSlotWidth => math.max(18, checkColumnWidth - 4);

  double get dragGlyphSize => switch (controlExtent) {
        28 => 11,
        30 => 12,
        32 => 13,
        36 => 14.5,
        _ => math.max(11, controlExtent - 18),
      };

  double get appendGlyphSize => switch (controlExtent) {
        28 => 13,
        30 => 14,
        32 => 15,
        36 => 16.5,
        _ => math.max(13, controlExtent - 16),
      };

  double get trashGlyphSize => switch (controlExtent) {
        28 => 12,
        30 => 13,
        32 => 14,
        36 => 15.5,
        _ => math.max(12, controlExtent - 17),
      };

  EdgeInsets get mainContentPadding => EdgeInsets.fromLTRB(
        4,
        textVerticalPadding + 1,
        0,
        math.max(0, textVerticalPadding - 1),
      );

  EdgeInsets get extraContentPadding => EdgeInsets.fromLTRB(
        10,
        textVerticalPadding + 1,
        2,
        math.max(0, textVerticalPadding - 1),
      );

  static _TodoVisualSpec from(String value) {
    return switch (TodoVisualSizes.normalize(value)) {
      TodoVisualSizes.small => const _TodoVisualSpec(
          textScale: 12 / 14,
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
