# Besser-Bahn

Premium Deutsche-Bahn companion app. Flutter app in `flutter-app/`, self-hosted
delay-prediction API in `prediction-service/`, API probes in `api-tests/`.

## Workflow — ALWAYS commit & push after changes

After every change that leaves the working tree in a good state (code compiles /
`flutter analyze` clean), **commit and push immediately**:

```
git add -A && git commit -m "<conventional message>" && git push
```

- Use Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`…).
- Don't wait to batch unrelated work — commit each logical change as it lands.
- **Never commit secrets**: Android signing keys / upload key
  (`android/*.jks`, `*.keystore`, `encrypted_upload_key.zip`,
  `upload_certificate.pem`, `pepk.jar`), `key.properties`. These are gitignored —
  keep them that way.

## Architecture notes

- Data layer prefers the **DB Vendo backend** (`app.services-bahn.de/mob`, the
  DB Navigator app's API) over the bahn.de website (Akamai-blocked) and the
  public HAFAS mirror (`v6.db.transport.rest`, unreliable/down).
- Route map geometry comes from `GET /mob/zuglauf/{id}` (`zuglauf.v2+json`) —
  the exact track polyline DB draws on its own map. Cached per physical route in
  `lib/core/polyline_cache.dart`.
- New app structure lives under `flutter-app/lib/screens/`,
  `providers/` (Riverpod), `router/` (GoRouter), `services/`.
