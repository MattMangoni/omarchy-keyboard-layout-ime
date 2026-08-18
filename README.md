# Keyboard layout + IME — Omarchy bar widget

A fork of Omarchy's stock `omarchy.keyboard-layout` bar widget. The stock
widget cycles through your xkb layouts on click. This fork appends one more
stop to the cycle: **Japanese via fcitx5/Mozc**.

```
EN (us intl) → JA (Mozc) → EN → …
```

- The label shows the short code of the active layout (`EN`, `IT`, …) or
  `JA` while Mozc holds the input.
- One click advances the cycle. Leaving `JA` wraps back to the first
  xkb layout.
- Ctrl+Space (the fcitx5 default trigger) still toggles Japanese directly;
  the widget notices and follows.
- The xkb part of the cycle is not hardcoded. Add or remove layouts in
  your Hyprland config and the cycle adapts.

## Requirements

- Omarchy 4.x (the Quickshell `omarchy-shell` bar)
- `fcitx5-mozc` (fcitx5 itself ships with Omarchy)

## Install

One command, run from a terminal (it may ask for your password):

```bash
git clone https://github.com/MattMangoni/omarchy-keyboard-layout-ime \
  ~/.config/omarchy/plugins/matteo.keyboard-layout \
  && bash ~/.config/omarchy/plugins/matteo.keyboard-layout/install.sh
```

The script is idempotent — re-run it any time; it skips what is already
done. It installs `fcitx5-mozc`, adds Mozc to the fcitx5 profile,
routes D-Bus activation through Omarchy's managed Fcitx5 service, registers
the widget on the bar, and sets the Chromium IME flags. It does not touch your
Hyprland layout list.

## Manual install

1. Install the Mozc engine:

   ```bash
   omarchy pkg add fcitx5-mozc
   ```

2. Add Mozc to the fcitx5 profile. Stop fcitx5 first — it overwrites the
   file on exit:

   ```bash
   systemctl --user stop omarchy-fcitx5.service
   ```

   In `~/.config/fcitx5/profile`, add a Mozc item to the default group and
   fix the item numbering, for example:

   ```ini
   [Groups/0/Items/1]
   # Name
   Name=mozc
   # Layout
   Layout=
   ```

   Then start it again:

   ```bash
   systemctl --user start omarchy-fcitx5.service
   ```

3. Clone this repository into your Omarchy plugin directory:

   ```bash
   git clone https://github.com/MattMangoni/omarchy-keyboard-layout-ime \
     ~/.config/omarchy/plugins/matteo.keyboard-layout
   ```

4. Register and place the widget:

   ```bash
   omarchy-shell shell rescanPlugins
   omarchy plugin enable matteo.keyboard-layout
   omarchy plugin disable omarchy.keyboard-layout
   omarchy bar move matteo.keyboard-layout --section right
   ```

5. Keep one or more xkb layouts in Hyprland. With one layout, the widget
   cycles directly between that layout and Japanese.

## Missing Mozc?

The widget probes the fcitx5 profile for Mozc. Without it, the Japanese
stop is skipped and the widget behaves exactly like the stock one — no
errors, no dead clicks. Add Mozc to the profile (step 2) and the widget
picks it up within seconds, no restart needed.

## Chromium and Electron apps

Wayland IME needs a flag there. Add to `~/.config/chromium-flags.conf`
(and the equivalent `*-flags.conf` of Electron apps):

```
--enable-wayland-ime
--wayland-text-input-version=3
```

## Other input methods

Mozc is hardcoded in two small places in `KeyboardLayout.qml`: the
`cycleLayout()` function and the `JA` label. Swap `mozc` for another
fcitx5 engine (for example `pinyin`) and adjust the label to taste.

## Caveat

This fork does not track upstream. When Omarchy improves the stock
widget, port the changes here by hand (`git diff` against
`/usr/share/omarchy/shell/plugins/bar/widgets/KeyboardLayout.qml` helps).

## License

MIT. Based on the `omarchy.keyboard-layout` widget from
[Omarchy](https://omarchy.org/), also MIT. See [LICENSE](LICENSE).
