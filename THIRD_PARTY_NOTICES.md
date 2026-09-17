# Third-party notices

## MIDI2LR (PanaLux Bridge)

`Packaging/PanaLux Bridge.lrplugin` is a modified copy of the Lightroom Classic plugin from
[MIDI2LR](https://github.com/rsjaffe/MIDI2LR), copyright 2015 Rory Jaffe and contributors,
licensed under the GNU General Public License v3 (`LICENSE.txt` inside the plugin).

The changes are listed in the plugin's `NOTICE.txt`. The `.lua` files are the plugin's complete
source, and `Scripts/make_bridge_plugin.sh` rebuilds it from an official MIDI2LR release.

The PanaLux app is a separate program. It talks to the plugin over a local network connection and
is licensed under the MIT License. The command names in `Sources/PanaLux/Resources/commands.json`
are the plugin's command identifiers, which PanaLux needs in order to talk to it.

## Apple frameworks

PanaLux uses only frameworks that ship with macOS (SwiftUI, AppKit, IOKit, Network, WebKit,
ServiceManagement). It has no other third-party code or packages.
