# Google Play Billing Library (R8 / ProGuard)
-keep class com.android.vending.billing.** { *; }
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**

# Flutter in_app_purchase Android glue
-keep class io.flutter.plugins.inapppurchase.** { *; }
