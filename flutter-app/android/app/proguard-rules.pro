# R8 full-mode keeps. The Flutter Gradle plugin already supplies the core
# Flutter/embedding keeps; these cover reflection-based bits in our plugins
# that full mode would otherwise strip.

# Flutter embedding (defensive — usually covered, but full mode is aggressive).
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }

# Play Core (deferred components / split install) — referenced by Flutter but
# not always present; don't fail on missing symbols.
-dontwarn com.google.android.play.core.**

# geolocator / url_launcher / shared_preferences etc. use standard Android
# APIs and AndroidX — no extra keeps needed beyond AndroidX's consumer rules.

# Keep annotations (used by several AndroidX libs at runtime via reflection).
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
