# Shipping updates

PanaLux 1.2.0 embeds Sparkle 2.10.0. The menu bar and Settings offer **Check for Updates…**. Automatic checks are enabled; installing an update remains the user's choice. System profiling is disabled.

The feed is `https://github.com/AnotherMeatsack/panalux/releases/latest/download/appcast.xml`. Each new GitHub release must include both the signed ZIP and `appcast.xml`. Version 1.1 and earlier do not contain Sparkle and need one manual upgrade.

The public Ed25519 key is in `Packaging/SparklePublicKey.txt` and the built app's `SUPublicEDKey`. The private key stays in the macOS login Keychain, under Sparkle account `panalux`. Do not commit or export it into the repository. Protect and back up the signing Keychain through the normal secure process.

1. Run the Swift tests in safe render mode and the Lua bridge tests.
2. Increase `VERSION`. Build into a staging directory, keeping the live app intact:
   ```sh
   PANALUX_APP_BUNDLE=/tmp/panalux-release/PanaLux.app Scripts/build_app.sh
   ```
3. Verify the app's Developer ID signature and both architectures. Notarize and staple when the Apple account is available. Developer ID signing alone is not notarization.
4. Prepare a new output folder:
   ```sh
   Scripts/prepare_update.sh /tmp/panalux-release/PanaLux.app /tmp/panalux-update
   ```
   The script verifies the app and matching public key, archives the app with symlinks intact, and uses Sparkle's `generate_appcast` to sign the update. It refuses to replace an existing archive/feed and does not publish anything.
5. Commit and push the reviewed source. Create a new GitHub release/tag from that commit, attaching the ZIP and appcast together. Include the DMG for first-time installs if generated. Never replace an existing release's signed archive with different bytes.
6. Download the public feed and archive, verify the Ed25519 signature, and exercise Check for Updates. Test installation from the preceding Sparkle-enabled version when available.

A feed check, signature validation, and a real installation are distinct checks. Record which ones passed. Notarization/account work must not be silently bypassed or described as complete.
