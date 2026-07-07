# Development

## Flutter Toolchain

This repository is configured as a Flutter project for Windows and Android.

During initial setup, Puro was used to install Flutter stable:

```powershell
winget install pingbird.Puro --accept-source-agreements --accept-package-agreements --silent
puro create stable
puro use stable
```

If the local shell has a malformed proxy value such as `<http://127.0.0.1:7897>`, override it for Flutter/GitHub commands:

```powershell
$env:HTTPS_PROXY = "http://127.0.0.1:7897"
$env:HTTP_PROXY = "http://127.0.0.1:7897"
```

## Checks

```powershell
puro flutter pub get
puro flutter analyze
puro flutter test
puro flutter build windows
puro flutter build apk --debug
```

## Local State Safety

`StateStore` writes `data.json.tmp` before replacing `data.json`, rotates the
previous primary file to `data.backup.json`, and loads a valid temp file if an
interrupted save leaves the primary missing. A corrupt temp file must not block
fallback to the stable backup. Save calls are serialized inside `StateStore`
itself, and each call encodes its JSON snapshot before entering the write queue
so an older asynchronous save cannot overwrite a newer state.

`AppStateCodec` treats PaperTodo `data.json` as a compatibility boundary. Before
decoding, it migrates known legacy PaperTodo model keys to the current camelCase
RePaperTodo schema with case-insensitive matching, while modern camelCase keys
win if both versions are present. User-data map keys, such as capsule queue
names, must not be rewritten by this migration pass.
Sync provider values are normalized case-insensitively so legacy or hand-edited
`webDav` settings do not silently fall back to disabled sync.
Model enum-like values such as theme, paper type, markdown mode, visual size,
capsule side, queue side, and reminder units are also normalized
case-insensitively, then written back as canonical RePaperTodo values.
Hand-edited primitive values are tolerated when unambiguous: `true`/`false`,
integer strings, and finite decimal strings decode like their JSON primitive
counterparts before normal model clamping is applied.

## Current Build Outputs

Build outputs are ignored by Git:

- `build/windows/x64/runner/Release/repapertodo.exe`
- `build/app/outputs/flutter-apk/app-debug.apk`
