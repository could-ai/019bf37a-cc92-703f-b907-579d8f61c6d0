import java.io.File
import java.io.FileInputStream
import java.util.Locale
import java.util.Properties
import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.couldai_user_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.couldai_user_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

abstract class GenerateMainActivityTask : DefaultTask() {
    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @get:Input
    abstract val packageName: Property<String>

    @TaskAction
    fun generate() {
        val resolvedPackageName = packageName.get()
        val outputDirectory = outputDir.get().asFile
        val packagePath = resolvedPackageName.replace('.', '/')
        val destinationDir = File(outputDirectory, packagePath)
        if (!destinationDir.exists()) {
            destinationDir.mkdirs()
        }
        val outputFile = File(destinationDir, "MainActivity.kt")
        val fileContents = """
            package $resolvedPackageName

            import io.flutter.embedding.android.FlutterActivity

            class MainActivity : FlutterActivity()
        """.trimIndent()

        if (!outputFile.exists() || outputFile.readText() != fileContents) {
            outputFile.writeText(fileContents)
        }
    }
}

val generatedMainActivityBaseDir = layout.buildDirectory.dir("generated/source/mainActivity")

androidComponents {
    onVariants { variant ->
        val capitalizedVariantName = variant.name.replaceFirstChar { current ->
            if (current.isLowerCase()) {
                current.titlecase(Locale.ROOT)
            } else {
                current.toString()
            }
        }

        val variantOutputDir = generatedMainActivityBaseDir.map { baseDir ->
            baseDir.dir(variant.name)
        }

        val generateVariantMainActivity = tasks.register<GenerateMainActivityTask>(
            "generate" + capitalizedVariantName + "MainActivity",
        ) {
            packageName.set(variant.applicationId)
            outputDir.set(variantOutputDir)
        }

        variant.sources.java?.addGeneratedSourceDirectory(
            generateVariantMainActivity,
            GenerateMainActivityTask::getOutputDir,
        )
        variant.sources.kotlin?.addGeneratedSourceDirectory(
            generateVariantMainActivity,
            GenerateMainActivityTask::getOutputDir,
        )
    }
}
