# Pigeon 的 Java 端方法通过 JNI 按原始签名查找。
# R8 会改写/移除 Kotlin 运行时类型（Continuation、Result 等），
# 导致 SharedPreferencesApiRegistrar.getAll(...) 在运行时找不到方法或类。
# 保留整个 Kotlin 标准库，避免 JNI 签名被优化。
-keep class kotlin.** { *; }
