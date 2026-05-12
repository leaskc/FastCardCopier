FastCard Copier — AppIcon
=========================

Drop this entire `AppIcon.appiconset` folder into your Xcode project's
`Assets.xcassets` (right-click → Show in Finder, then drag the folder
in). Xcode will pick it up as the app icon set automatically.

If you need a .icns instead (e.g. for a non-Xcode build), from Terminal:

    iconutil -c icns AppIcon.appiconset

`source.svg` is the master vector — re-rasterize from it if you ever
need different sizes.
