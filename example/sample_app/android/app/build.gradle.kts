plugins {
    id("com.android.application")
}

android {
    namespace = "dev.example.sample_app"
    compileSdk = flutter.compileSdkVersion

    defaultConfig {
        applicationId = "dev.example.sample_app"
        minSdk = 21
        targetSdk = 35
    }
}
