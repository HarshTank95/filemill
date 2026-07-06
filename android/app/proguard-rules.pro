# FileMill ships only the Latin ML Kit text-recognition model. The Flutter
# plugin still references the other script options classes; they are absent
# by design, so tell R8 not to fail on them.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
