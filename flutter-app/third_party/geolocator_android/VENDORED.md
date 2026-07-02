# Vendored: geolocator_android (FLOSS, GMS-free)

Source: https://github.com/Zverik/flutter-geolocator (branch `floss`)
Commit: e3991f9e63514933e96b57a8f839ad6511c4afc2
Version: 4.6.2

Vendored into this repo so builds never depend on an external GitHub repo
staying online (issue #10). This is the Google-Play-Services-free
implementation of `geolocator_android` — it uses the plain Android
LocationManager instead of the fused-location provider (no GMS).

Wired in via `dependency_overrides.geolocator_android` (path:) in
../pubspec.yaml. `example/` and `test/` were removed; LICENSE (MIT) kept.

To update: re-copy from the upstream branch and update commit hash above.
