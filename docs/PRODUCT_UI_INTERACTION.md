# RePaperTodo product interaction baseline

This document records the product decisions used by the Flutter client. The
reference behavior is PaperTodo, adapted only where Android and Windows have
different platform expectations.

## Product model

- A paper is the primary object. On Windows, the paper itself is the window;
  there must not be a visible outer window containing an inset card.
- Todo and Note share one paper shell. Their content tools differ, but title,
  movement, sizing, pinning, synchronization, and responsive chrome stay
  consistent.
- A capsule is a Windows-only projection of a paper. It is navigation, not a
  second copy of paper state.
- The master capsule controls only the visibility of a capsule queue. It never
  changes a paper's content, expanded geometry, desktop-pin state, or Z order.

## Windows paper interaction

- The whole quiet header area moves the paper. Interactive controls consume
  their own pointer events.
- Native window edges and corners resize the paper. No visible resize handles
  or outer frame are required.
- At the minimum width, only the title, always-on-top state, and collapse
  control remain. Pin, sync, file, and creation actions appear progressively
  as usable width becomes available.
- Pin to desktop locks geometry and interaction except for the explicit unpin
  control. Activating its capsule unpins it and brings it to the foreground.
- Paper content never fades through a blank frame during native window state
  changes.

## Windows capsule interaction

- A collapsed paper owns one real capsule. An expanded paper may expose one
  proxy capsule when that option is enabled. A paper must never have two
  clickable capsules in the same queue slot.
- Clicking a collapsed-paper capsule expands that paper.
- Clicking an expanded, unpinned paper's proxy collapses that paper.
- Clicking a desktop-pinned paper's proxy immediately unpins and foregrounds
  the paper. A stale native proxy flag may never override authoritative paper
  state.
- Dragging the master moves its entire queue vertically. Dragging an ordinary
  capsule reorders it or moves it to another edge queue. Neither action writes
  capsule geometry into normal paper geometry.
- Hover and pointer capture take precedence over fullscreen/occlusion hiding,
  so a capsule cannot disappear from under the pointer.

## Android boundary

- Android contains Todo, Note, search/navigation, settings relevant to those
  objects, and WebDAV synchronization.
- Android exposes no capsule buttons, collapse-all actions, capsule settings,
  capsule gestures, or collapsed paper presentation.
- WebDAV does not transfer capsule enablement, queue state, monitor/edge
  placement, or per-paper capsule collapse state. Historical capsule-only
  operations are consumed as compatible no-ops so they cannot block later
  synchronization.

## Visual language

- Paper surfaces use one continuous warm/ink/forest/rose sheet with a subtle
  tonal gradient, a fine edge, and restrained depth.
- Header and body are regions of the same sheet, not separate stacked panels.
- Todo rows use quiet ruled separation; borders appear as feedback for drag
  targets, not as permanent cards inside the paper.
- Controls use a consistent rounded radius and compact spacing. Color denotes
  state or urgency; it is not decorative chrome.
- Capsules are full pills with paper colors, one clear glyph, and one label.
