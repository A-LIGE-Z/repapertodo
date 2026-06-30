# RePaperTodo Design Baseline

RePaperTodo is a quiet productivity utility, not a marketing app.

The interface should stay close to PaperTodo's "sheets of paper" metaphor:

- Calm, compact, and direct.
- No dashboard-first experience on Windows.
- No decorative hero screens.
- No heavy card nesting.
- No visual noise that competes with the user's notes.
- Touch targets on Android must meet platform minimums.
- Desktop controls should remain precise and keyboard-friendly.
- Light and dark mode must be designed together.
- Motion must explain state changes such as collapse, expand, dock, and restore.

## Flutter UI Rules

- Use semantic theme tokens rather than raw colors in widgets.
- Keep paper surfaces visually quiet, with restrained shadows and borders.
- Prefer platform-appropriate controls over custom controls unless PaperTodo parity requires custom behavior.
- Preserve visible focus states and screen-reader labels for every interactive control.
- Respect reduced motion.
- Avoid emoji as structural icons.
- Make compact desktop UI and touch-friendly Android UI from the same design language, not the same exact density.

## Windows Priority

Windows is not a scaled-up mobile app. The first Windows milestone must feel like independent desktop papers, not a single Flutter dashboard pretending to contain papers.

## Android Priority

Android may use a mobile-native navigation model, but the data concepts must remain identical: papers, todo items, notes, linked notes, settings, sync, and conflict recovery.

