# flutter_gemma (MediaPipe LLM Inference) 用。
# R8 が参照だけ存在する optional クラスで失敗するのを抑止し、
# JNI から参照される MediaPipe のクラスは削らない。
-dontwarn com.google.auto.value.extension.memoized.Memoized
-dontwarn com.google.mediapipe.proto.**
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
