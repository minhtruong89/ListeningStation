# ML Kit Text Recognition optional languages (dontwarn rules to ignore missing dependencies)
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Keep Vapi SDK and its models for Gson deserialization
-keep class ai.vapi.** { *; }
-keepclassmembers class ai.vapi.** { *; }
-dontwarn ai.vapi.**

# Keep Daily.co WebRTC (used internally by Vapi SDK)
-keep class co.daily.** { *; }
-keepclassmembers class co.daily.** { *; }
-dontwarn co.daily.**

# Keep Gson models and annotations
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keepclassmembers class com.google.gson.** { *; }
-keepclassmembers enum * { *; }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
