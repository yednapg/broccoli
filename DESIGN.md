# How Broccoli should feel

Broccoli should feel like it belongs on the Mac: quick, quiet, precise, and familiar. It is a utility, not somewhere the user should have to spend time. It should appear, make the next action obvious, and get out of the way.

When a design choice is uncertain, start with the normal macOS answer. Use system controls, SF Pro, SF Symbols, semantic colors, familiar keyboard behavior, and Apple's wording. Custom work is welcome when Broccoli needs it, but it should still feel native rather than like a small website inside a Mac window.

Restraint matters. Good spacing and hierarchy are usually enough. Avoid decorative gradients, piles of cards, heavy borders, large shadows, and animation whose only job is to attract attention.

Broccoli supports macOS 26 and later. The visual treatment may adapt as macOS evolves, but the hierarchy, interaction, accessibility, and core character of the app should remain the same.

The current macOS 26 interface is the baseline. Preserve it unless the request is specifically about changing the design. Fixing a bug, adding backend behavior, changing the build, or adding an update mechanism does not permit an incidental redesign. When a task touches user-visible code, look at the existing interface before editing and compare the installed result with it afterward.

Broccoli intentionally uses both AppKit and SwiftUI. AppKit is the right owner for the launcher panel and its precise keyboard and window behavior. SwiftUI is the right owner for Settings. Do not rewrite either side merely to make the technology uniform.

## The launcher

The launcher is the heart of the app. It is keyboard-first and intentionally compact. Opening it should feel immediate. Results should not make the window twitch, jump, or leave awkward empty space.

Keep its measurements in `LauncherThemeController.swift` instead of fixing spacing locally in several views. The real launcher and the preview in Settings should use the same measurements and rendering decisions. If one changes, check the other. Appearance shows production mini-previews of each launcher design.

The search field should stay optically aligned when the user starts typing. Result growth should happen in complete rows. Selection, focus, and inactive states should remain easy to read in Light and Dark appearances. Position the live launcher by clicking and holding its chrome, then dragging; release to place it anywhere on the display. Opening from the keyboard restores the stored origin. Height changes keep that top edge and grow downward.

Typing should focus search. Arrow keys should move through results. Return should do the obvious thing. Escape should back out or close the launcher predictably. Do not add permanent buttons or labels for actions that are already clear from the keyboard or selected result.

Result rows, selection, and text commit immediately and nonanimated. While the panel is visible, height changes run as one short interruptible animation of the window frame and its content in a single transaction, keeping the top edge fixed (growth is downward only). First presentation (hotkey) and dismissal remain nonanimated. Reduce Motion collapses every transition to the instant commit. Input and result delivery never wait for motion; a new query interrupts and retargets the transition instantly. Commit result rows, surface geometry, and the window size as one update before drawing when motion is disabled or interrupted. The launcher must not inherit animations from unrelated view updates. All result kinds, including “No results,” use the theme's standard row height and result-container insets. Liquid Glass search and result rows share the same height. Center status symbols and text within that shared row; do not introduce status-specific heights or adjust them independently. Replacing one result with “No results” must not resize the window beyond the transition. The appearance-toggle action describes the opposite of the current system appearance, independently of a launcher appearance override; update its wording even when search work began before the system changed.

### Liquid Glass

Liquid Glass is the more expressive launcher style, but the material should never become the point of the design. The compact search capsule and expanded launcher use the same corner radius, derived from half the shared search-row height. Expansion changes the surface's height, not its corner curvature or material configuration. Selection uses the macOS accent color in both appearances, with semantic selected text and the existing inset geometry.

Use one behind-window `NSVisualEffectView` with the `hudWindow` material as the whole surface, in both appearances. Configure that treatment once on the persistent surface; appearance is inherited from its panel or preview, and AppKit owns the backdrop blur and the adaptation to Reduce Transparency and Increase Contrast. Round it with a stretchable mask, not by layer-backing the effect view. Liquid Glass query text, placeholder, magnifier, and cancel control share the magnifier's device black/white. The header rule uses that same ink at 25% opacity. Draw `xmark.circle.fill` as a template so the X stays knocked out; a palette fill turns that control into a solid disc. Catalog colors over HUD wallpaper read brown. Do not stack a second backdrop, tint, opacity, or blur layer to adjust the material.

Do not reintroduce `NSGlassEffectView` here without measuring it again. It was tried and removed: at the capsule's 58-point height its lens contributes almost no readable blur, and because Liquid Glass samples in-window content as well as the desktop, placing any material beneath it destroys the lens and leaves a flat slab with a hard bright rim. A material layered under glass is not a fix for thin glass.

The borderless window must fit the surface exactly: do not inset it inside a larger transparent window, because the native window shadow then has a second boundary. Clip the outer window content to the same shared corner geometry as the surface, updating bounds without animation so rectangular corner pixels cannot extend beyond it. Enable the floating panel's native window shadow and invalidate its shape after the capsule expands or collapses. Do not overlay a custom stroke on the material's edge. Use the same surface and selection in production and Settings previews. Do not substitute a separate Light material or a custom opaque Liquid Glass surface. Detached previews cannot reproduce the native window shadow or desktop blur.

### Minimal

Minimal should feel tighter and calmer, not like a scaled-down Liquid Glass theme. Its rows run edge to edge, selection may use a full-width accent, and the content should keep a steady leading edge. It does not need a window shadow.

Do not shrink type, icons, or controls simply because the shell is narrower. Share behavior between the two modes, but keep their visual differences deliberate. Do not create an accidental third theme from pieces of both.

## Settings

Settings should be quieter than the launcher. A person should be able to scan a pane, understand the groups, and change something without decoding a custom interface.

The approved Settings shell is the native SwiftUI `Settings` scene already in the app. It uses a balanced `NavigationSplitView`, a permanently visible source-list sidebar, and SwiftUI's sidebar search placement. Keep the normal macOS title bar and selection behavior. Do not replace the native search field with a handmade field, switch the shell to a different `TabView`, add a sidebar toggle, or rebuild Settings in AppKit without explicit approval.

`SettingsShellLayout` is the geometry source of truth. The content is 980 points wide and 680 points high; the declared sidebar width is 209 points and the remaining detail width is 771 points. Those values describe the source contract. Let the native macOS Settings scene perform its normal window and sidebar presentation rather than forcing saved divider frames with private defaults or delayed layout corrections.

Keep the sidebar in this order: General, Appearance, Search, Files, Calculator, Clipboard, Window Management, Actions, Permissions, About. Preserve the existing titles and SF Symbols unless the task calls for changing one of them. Search should find both sections and the focused destinations already listed in `SettingsSearch.swift`. Back and forward history should continue to work for those destinations.

Use the existing `SpotlightSettingsPane`, `SpotlightSettingsCard`, `SpotlightSettingsRow`, `SpotlightSettingsDivider`, and `SpotlightSettingsSearchField` components and the existing button styles. If a layout decision belongs everywhere, fix the shared component instead of nudging one pane until it looks right.

Group controls that belong together. Do not put every option in its own card. Keep borders and corner treatments subtle, align titles and trailing controls, and leave enough room for explanations to read naturally. Most rows do not need a leading icon; the card, typography, and sidebar already provide structure.

Prefer the native toggle, picker, slider, button, stepper, or text field unless it genuinely cannot express the interaction.

Each pane has a clear job:

- General owns the launcher shortcut, launch-at-login behavior, and shortcut recovery.
- Appearance owns launcher design, color mode, display, position, result presentation, and the launcher preview. Position is set by dragging the live launcher, not a slider.
- Search owns result sources and adaptive ranking.
- Files owns explicit file search, its scope, and excluded locations.
- Calculator owns offline calculator and formatting preferences.
- Clipboard owns encrypted history, retention, capture types, and ignored applications.
- Window Management owns its enablement, shortcuts, and Accessibility status.
- Actions owns the searchable built-in commands.
- Permissions owns privacy status, Automation, local-data actions, and diagnostics.
- About owns identity, version, privacy summary, update controls, support, and license information.

Do not move a control to another pane as cleanup. New controls should join the pane and card that already own the behavior. If no pane clearly owns it, decide the information architecture before writing UI code.

General presents one Global Shortcut row; clicking the displayed shortcut starts recording, and registration status is that row’s subtitle. Shortcut troubleshooting is an error-only path. The Calculator Supported card keeps capabilities and the example in one padded child. Grouped Settings surfaces clip to the 12-point rounded rect. The Clipboard History off banner is notice-only; enabling still uses the existing toggle and consent sheet. Power actions describe a second return in sentence case, and that warning is a footnote under the Power card. About shows identity, version, Local Only, diagnostics, and the copyright line without promotional taglines.

## Interaction and motion

Everything important should work without a pointer. Keep normal macOS focus behavior and normal Return and Escape semantics. Hover may help, but it cannot be the only way to discover or use something.

Motion should explain continuity or a change of state. Keep it short and interruptible, and never make input or action execution wait for it. Respect Reduce Motion.

For destructive or disruptive actions, explain what will happen before asking for confirmation. Do not rely on red alone to communicate danger.

## Accessibility

Accessibility is part of the interface, not a separate pass. Give controls useful labels and values, hide decorative symbols from VoiceOver, and keep traversal order sensible. State cannot depend only on color, blur, transparency, or motion.

Do not make controls too small in the name of density. When material or hierarchy changes, inspect Light, Dark, Reduce Transparency, and Increase Contrast. Use Accessibility Inspector for new interaction patterns when it is available.

## Privacy and permissions

Ask only for access Broccoli needs, at the moment the related feature is used. Explain why before or alongside the system prompt. Keep Not Requested, Allowed, Denied, and Unavailable states visibly distinct, and give denied states a clear route to the correct System Settings pane.

Do not design as though Broccoli can grant itself access. macOS keeps that decision with the user. Development machines may already have permissions for the installed app, but first-run and denied experiences still need to be coherent.

Be exact when talking about local data. Clipboard history is encrypted and stored only on this Mac. Explain retention clearly, and keep concealed data and password apps excluded.

Use short, direct language throughout the app. Avoid promotional copy and technical terms the user should not need to know.

## Before calling a UI change done

Look at the states that matter for the change, not only the best-looking state. That normally includes empty and populated content, selection, focus, disabled controls, errors, permission denial, resizing, and long text. Check the keyboard path and accessibility labels.

Compare the launcher with its Settings preview whenever either one changes. Add tests for geometry, presentation state, and regressions where they are useful. Record what you inspected and say plainly if visual inspection was not possible.

Apple's guidance is the reference when the project does not already have a clear answer:

- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
- [Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles)
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/)

### Dock artwork

The adaptive `Support/Broccoli.icon` bundle asset owns the Dock icon in Light and Dark
appearances, whether the app is running or stopped. Do not override it with a flattened
`applicationIconImage`. The existing source PNGs include a 64-point export margin; the
Icon Composer layer transform removes that margin so the artwork fills the system mask
instead of sitting inside a second light/dark frame. Preserve the original brand PNGs.
