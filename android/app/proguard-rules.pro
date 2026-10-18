# Suppress warnings for missing Java SE classes on Android (Rhino / NewPipeExtractor)
-dontwarn java.beans.**
-dontwarn javax.annotation.**
-dontwarn org.mozilla.javascript.**

# Keep NewPipeExtractor classes and models
-keep class org.schabi.newpipe.extractor.** { *; }
-dontwarn org.schabi.newpipe.extractor.**

# Keep Rhino JavaScript engine classes
-keep class org.mozilla.javascript.** { *; }

# Keep AudioService and MediaKit
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.audioservice.AudioService { *; }
-keep class com.ryanheise.audioservice.MediaButtonReceiver { *; }
-dontwarn com.ryanheise.audioservice.**

# Keep OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**

