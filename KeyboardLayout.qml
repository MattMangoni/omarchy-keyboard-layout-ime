import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "KeyboardLayoutModel.js" as KeyboardLayoutModel

BarWidget {
  id: root
  moduleName: "matteo.keyboard-layout"

  // Japanese rides fcitx5's Mozc engine rather than xkb, so the click cycle
  // appends it after the last xkb layout: us(intl) -> mozc -> us(intl).
  // fcitx5-remote drives and reads that leg; Ctrl+Space still works beside it.
  // Without Mozc in the fcitx5 profile the leg is skipped and the widget
  // behaves exactly like the stock one, so a missing install degrades quietly.
  property bool imeAvailable: false
  property bool imeActive: false
  property int layoutTotal: 0
  property int layoutIndex: 0

  property string layoutFull: ""
  // The keyboard the last reading spoke for, which is the one a click switches,
  // and separately the one activelayout named as being typed on. A reading
  // confirms the first is really there, so the click has a keyboard to reach
  // from the first reading onwards rather than only after a switch, and stops
  // naming one that has been unplugged.
  property string keyboardName: ""
  property string typedKeyboardName: ""
  // Keyboards on the seat, buttons and virtual ones excluded, and whether the
  // last reading left that shape in doubt.
  property int keyboardCount: 0
  property bool keyboardUnresolved: false
  // Multiple xkb layouts make the stock layout cycle useful. A configured IME
  // also makes a single-layout cycle useful, so that case remains visible.
  // An older Hyprland that doesn't report the list keeps showing the label.
  property bool multipleLayouts: true
  // Short language code per layout description ("English (US)": "en"), read from
  // xkb's own table rather than maintained by hand.
  property var layoutBriefs: ({})
  readonly property string layoutLabel: imeActive ? "JA" : KeyboardLayoutModel.shortLabel(layoutFull, layoutBriefs)

  // A query already in flight was started before this event, so it may read the
  // layout the switch replaced. Remember the request and re-run once it lands
  // rather than dropping it; nothing else would correct the label afterwards.
  property bool refreshPending: false

  function refresh() {
    if (queryProc.running) {
      refreshPending = true
      return
    }

    refreshPending = false
    queryProc.running = true
  }

  // Keyboards someone can actually type on, which is not everything Hyprland
  // calls a keyboard.
  function typedKeyboards(keyboards) {
    return keyboards.filter(k => KeyboardLayoutModel.isTypedKeyboard(k.name))
  }

  // The main flag names no keyboard for long: fcitx5 takes it with the virtual
  // keyboard it binds to inject, which leaves no typed keyboard holding it and
  // nothing to read at all, and once that unbinds it lands on whichever device
  // Hyprland saw last, a power button included. Go by layout progress instead,
  // and by the keyboard activelayout named.
  function selectKeyboard(typed) {
    return KeyboardLayoutModel.selectKeyboard(typed, root.typedKeyboardName)
  }

  // switchxkblayout is a hyprctl command rather than a dispatcher, so it has to
  // be run rather than sent over the dispatch socket. It switches the keyboard
  // the last reading spoke for, so a click always advances the device the label
  // is describing. Switching the seat together would reach the typed keyboard
  // without having to name it, but it would also carry the buttons along, and
  // the whole read depends on those staying where they started: once a button
  // has been advanced too, a toggle that wraps the keyboard back to the first
  // layout leaves the button reading as the furthest along, and the label
  // follows the button.
  function cycleLayout() {
    if (!root.bar) return

    if (root.imeActive) {
      // Leaving Japanese wraps the cycle: fcitx5 back to plain passthrough,
      // xkb back to its first layout.
      root.bar.run("fcitx5-remote -s keyboard-us")
      if (root.keyboardName) root.bar.run("hyprctl switchxkblayout " + Util.shellQuote(root.keyboardName) + " 0")
      root.imeActive = false
    } else if (root.imeAvailable && root.layoutTotal > 0 && root.layoutIndex >= root.layoutTotal - 1) {
      // Past the last xkb layout the next stop is Japanese. The xkb layer is
      // left alone; Mozc's virtual keyboard speaks over it.
      root.bar.run("fcitx5-remote -s mozc")
      root.imeActive = true
    } else if (root.keyboardName) {
      root.bar.run("hyprctl switchxkblayout " + Util.shellQuote(root.keyboardName) + " next")
    }

    imeProbeTimer.restart()
    refreshTimer.restart()
  }

  Component.onCompleted: {
    briefsProc.running = true
    imeCheckProc.running = true
    refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      // The event names the keyboard that switched ahead of the layout it moved
      // to, and that is the keyboard being typed on whatever holds the main flag.
      if (name === "activelayout") {
        const named = KeyboardLayoutModel.eventKeyboardName(event)
        if (named) root.typedKeyboardName = named
      }

      // A reload that adds a layout to kb_layout decides whether the widget
      // shows at all, and leaves every keyboard on the layout it was already
      // reading, so it raises no activelayout to notice it by.
      if (name.indexOf("activelayout") !== -1 || name === "configreloaded") root.refresh()
    }
  }

  Process {
    id: queryProc
    command: ["hyprctl", "-j", "devices"]
    onRunningChanged: {
      if (running) {
        stallTimer.restart()
        return
      }

      stallTimer.stop()
      if (root.refreshPending) root.refresh()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        let listed
        try {
          listed = JSON.parse(text || "{}").keyboards
        } catch (e) {
          return
        }

        // A query the watchdog killed reports nothing at all, and an empty
        // string parses into the same shape a seat with no keyboards would.
        // Tell them apart by the list itself, so only a reading that reached
        // hyprctl gets to speak for the seat.
        if (!Array.isArray(listed)) return

        const typed = root.typedKeyboards(listed)
        const kb = root.selectKeyboard(typed)
        if (!kb || !kb.active_keymap) {
          // Either the last keyboard has been unplugged, which the label has to
          // stop describing and the click has to stop naming, or keyboards are
          // there and none of them reports a keymap. Both leave the shape in
          // doubt, so keep asking rather than letting a count from before it
          // changed settle the poll.
          root.keyboardUnresolved = true
          if (typed.length === 0) {
            root.layoutFull = ""
            root.keyboardName = ""
          }
          return
        }

        root.keyboardUnresolved = false
        root.keyboardCount = typed.length
        root.keyboardName = String(kb.name || "")
        root.multipleLayouts = kb.layout === undefined || String(kb.layout).indexOf(",") !== -1
        root.layoutTotal = kb.layout === undefined ? 0 : String(kb.layout).split(",").length
        root.layoutIndex = kb.active_layout_index || 0
        root.layoutFull = kb.active_keymap
      }
    }
  }

  // The table only changes when xkb data is upgraded, so read it at startup and
  // leave it alone. The bar is built per monitor, so this runs once per widget.
  // The exotic rulesets cover layouts like trans (IPA) that ship in the same xkb
  // package and set just as well, so load them or those labels lose their code.
  Process {
    id: briefsProc
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.layoutBriefs = KeyboardLayoutModel.layoutBriefs(text)
    }
  }

  Timer {
    id: refreshTimer
    interval: 600
    onTriggered: root.refresh()
  }

  // Whether Mozc is in the fcitx5 profile decides whether the Japanese leg
  // exists at all. fcitx5-remote -s on an engine the profile lacks is a silent
  // no-op, so without this check a click past the last layout would flash JA
  // and snap back once the poll reads the truth. The periodic timer keeps
  // re-checking while unavailable, so installing Mozc mid-session is picked up
  // without a shell restart.
  Process {
    id: imeCheckProc
    command: ["sh", "-c", "grep -qx 'Name=mozc' \"${XDG_CONFIG_HOME:-$HOME/.config}/fcitx5/profile\""]
    onExited: function(exitCode) { root.imeAvailable = exitCode === 0 }
  }

  // Ctrl+Space toggles Mozc behind the widget's back, so ask fcitx5 which
  // engine holds the seat. fcitx5-remote is one cheap dbus round trip, so a
  // steady poll costs little; the probe timer confirms a click's optimistic
  // label shortly after it runs.
  Process {
    id: imeProc
    command: ["fcitx5-remote", "-n"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.imeActive = text.trim() === "mozc"
    }
  }

  Timer {
    id: imeProbeTimer
    interval: 700
    onTriggered: if (root.imeAvailable && !imeProc.running) imeProc.running = true
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: {
      if (!root.imeAvailable) {
        if (!imeCheckProc.running) imeCheckProc.running = true
      } else if (!imeProc.running) {
        imeProc.running = true
      }
    }
  }

  // A query that never returns would freeze the label until the shell restarts,
  // since a Process that is already running can't be re-run. Give up on one that
  // overstays so the next refresh gets through, and ask again: the reading it
  // never delivered may have been the only one due on a settled seat, and
  // nothing else would come back for it.
  Timer {
    id: stallTimer
    interval: 5000
    onTriggered: {
      queryProc.running = false
      refreshTimer.restart()
    }
  }

  // Which keyboard on a crowded seat the label is describing can change without
  // Hyprland announcing it, since a device arriving or leaving raises no event
  // of its own, and that can only be learned by asking. Poll while there is that
  // ambiguity, until a first reading lands so a query that failed at login still
  // recovers, and while a reading has left the seat's shape in doubt. The
  // one-keyboard install has none of those, and is left alone rather than
  // spawning hyprctl forever for an answer that cannot change.
  Timer {
    interval: 10000
    running: !root.keyboardName || root.keyboardUnresolved || root.keyboardCount > 1
    repeat: true
    onTriggered: root.refresh()
  }

  visible: (layoutLabel !== "" && (multipleLayouts || imeAvailable)) || imeActive
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.layoutLabel
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: root.imeActive ? "Japanese (Mozc)" : root.layoutFull
    onPressed: function() { root.cycleLayout() }
  }
}
