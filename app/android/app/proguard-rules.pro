-keep class net.sqlcipher.** { *; }

# flutter_blue_plus uses reflection over its generated wire models. Keep both
# namespaces because 2.3.9 moved the Android package while older model names
# remain referenced by upstream release guidance.
-keep class com.jmx.flutter_blue_plus.** { *; }
-keep class com.lib.flutter_blue_plus.** { *; }
