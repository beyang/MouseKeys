# MouseKeys Agent Notes

## Build And Launch

- Build a Release app bundle, install it to `/Applications/MouseKeys.app`, and launch the `.app` (not the raw binary).
- Do not run `/Applications/MouseKeys` directly. Launch with `open /Applications/MouseKeys.app`.
- Running `/Applications/MouseKeys.app/Contents/MacOS/MouseKeys` is for debugging only; normal usage should launch the app bundle.

## Code Signing And Accessibility Trust

- Accessibility permission is sensitive to app identity. Ad-hoc signatures can change across rebuilds and break trust.
- After copying a rebuilt app to `/Applications`, re-sign it with the stable local cert (`FocusDev`) so the identity remains consistent.
- After signing, verify the designated requirement includes the bundle identifier and `FocusDev` certificate leaf.
- Recommended install command:

```bash
xcodebuild -project MouseKeys.xcodeproj -scheme MouseKeys -configuration Release -derivedDataPath .DerivedData -quiet build && \
pkill -x MouseKeys || true && \
rm -rf /Applications/MouseKeys.app && \
cp -R .DerivedData/Build/Products/Release/MouseKeys.app /Applications/ && \
codesign --force --deep --sign "FocusDev" /Applications/MouseKeys.app && \
open /Applications/MouseKeys.app
```

- Deploy-only command (rebuild + install + sign, without launching):

```bash
xcodebuild -project MouseKeys.xcodeproj -scheme MouseKeys -configuration Release -derivedDataPath .DerivedData -quiet build && \
pkill -x MouseKeys || true && \
rm -rf /Applications/MouseKeys.app && \
cp -R .DerivedData/Build/Products/Release/MouseKeys.app /Applications/ && \
codesign --force --deep --sign "FocusDev" /Applications/MouseKeys.app
```

- Signature verification command:

```bash
codesign -d -r- /Applications/MouseKeys.app
```

## If Mappings Suddenly Stop Working

- First verify Accessibility permission for `/Applications/MouseKeys.app` in `System Settings -> Privacy & Security -> Accessibility`.
- Remove stale MouseKeys entries pointing to other paths and keep only `/Applications/MouseKeys.app` enabled.
- If needed, toggle permission off/on and relaunch the app.
