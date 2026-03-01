# ============================================================
# ProGuard rules for AI Friend
# ============================================================

# flutter_local_notifications uses GSON for serializing
# scheduled notification data to SharedPreferences.
# Without these rules, R8 strips type parameters causing
# "RuntimeException: Missing type parameter" on zonedSchedule().
# See: https://github.com/MaikuB/flutter_local_notifications/issues/2573

-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**

# Keep GSON classes
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# Keep flutter_local_notifications model classes
-keep class com.dexterous.flutterlocalnotifications.** { *; }
