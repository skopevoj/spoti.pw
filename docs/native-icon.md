# Native cyan icon source

`assets/Spotify Liquid Glass.icon` is the editable Icon Composer source: a cyan #01C7FC Spotify mark on system-light/system-dark Liquid Glass backgrounds. Open the directory in Icon Composer to inspect or edit it.

The standard build pipeline still accepts its existing PNG `--icon` option. It does not compile or merge this native icon automatically. Do not pass the `.icon` directory to that PNG option.

Native integration requires compiling the source with a compatible Xcode/Icon Composer toolchain, adding the resulting icon renditions to the app's original `Assets.car` without replacing its other assets, applying the generated icon plist keys and fallback images, then signing the app with your own identity. Do not replace Spotify's complete asset catalog with an icon-only catalog.

A local experimental merge preserved every original rendition and validated light/dark/tinted icon variants, but used private Xcode CoreUI APIs. That environment-specific tool is not a supported general build step and is not distributed here. No original or merged Spotify asset catalog, signed app or signing material is included.
