# DiaTweaks

Small tweaks for the [Dia](https://www.diabrowser.com) browser, kept in place when Dia updates. Turn them on and off in **Dia → Settings → Patches**:

- Edge-to-edge web content
- Square corners by the sidebar
- Hide toolbar, optionally shown over the page while the pointer is at its top edge
- Hide sidebar button
- Hide Chat button
- Hide Chats button
- Hide downloads button
- Hide recent tabs button
- Hide pinned tabs background
- Hide window controls
- Hide pinned tab border
- Liquid Glass background
- Larger window corners
- Extensions button beside the pinned extensions, opening the Extensions menu
- Peek on Shift-click: preview a link over the current page, like Arc

Unofficial and not affiliated with The Browser Company. Apple Silicon, macOS 14 or later.

## Install

1. Install Dia into Applications, if it isn't there already.
2. Install Apple's developer tools: `xcode-select --install`
3. Run:

   ```sh
   git clone https://github.com/JaceThings/DiaTweaks.git
   cd DiaTweaks
   ./install.sh
   ```

Dia quits and reopens. When macOS asks to access "Dia Safe Storage", enter your password and click **Always Allow**.

## How it works

- Everything is built on your Mac from this source. The only download is Dia itself, from The Browser Company's own update feed, and it's used only if it's signed by The Browser Company and passes Gatekeeper.
- An untouched copy of the official Dia is kept in `~/Library/Application Support/DiaPatches/pristine`. Restoring puts it back.
- The patched Dia gets one extra line that loads the add-on, its built-in updater is switched off (DiaTweaks updates it instead, keeping the patches), and it's re-signed with a certificate created on your Mac, in your login keychain, called "DiaPatches Local Signing". Nothing is signed with anyone else's certificate.
- The add-on only rearranges Dia's own interface. It doesn't read your pages, history or passwords, and its only network use is checking Dia's update feed.
- Nothing runs in the background. Updates are checked when Dia opens and installed when you quit it.
- Because the app is now signed by you, macOS asks once per Dia update before Dia can read "Dia Safe Storage". Dia's built-in passkey support is off, since only The Browser Company can sign for it; signing in with a password works.

## Uninstall

In Dia, open **Settings → Patches** and click **Restore…**. Dia reopens as the original app with its own updates.

Or from Terminal:

```sh
~/Library/Application\ Support/DiaPatches/bin/diapatch uninstall --relaunch --purge
```
