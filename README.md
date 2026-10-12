# PortMenu

A tiny macOS app that shows every TCP port listening on your Mac and lets you stop the process behind it.

- Dock app with a resizable window, plus a menu bar shortcut
- Filter by port or process name
- Open `http://localhost:<port>` in your browser
- ✕ sends SIGTERM; ⌥-click ✕ force-kills (SIGKILL)

## Build

```bash
./build.sh
cp -R PortMenu.app /Applications/
```

Requires macOS 13+ and the Xcode command line tools. Ports are read with `lsof`, so only processes you own can be stopped.
