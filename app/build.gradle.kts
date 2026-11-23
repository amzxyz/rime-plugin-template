import org.gradle.api.tasks.Delete
import org.gradle.process.ExecOperations
import javax.inject.Inject
import java.util.Properties

plugins {
    id("com.android.application")
}

val pluginVersionName = providers.gradleProperty("pluginVersionName").getOrElse("1.0.0")
val pluginVersionCode = providers.gradleProperty("pluginVersionCode").map(String::toInt).getOrElse(1)
val nativeAbi = "arm64-v8a"
val minSdkVersion = 23

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val ndkVersionName = localProperties.getProperty("rime.ndkVersion", "28.2.13676358")
val cmakeVersion = localProperties.getProperty("rime.cmakeVersion", "3.31.6")
val buildToolsVersionName = localProperties.getProperty("rime.buildToolsVersion", "36.0.0")

// Standard Android signing setup. Local builds can copy
// keystore.properties.example to keystore.properties; CI should inject the
// keystore through environment variables instead. Neither the real properties
// file nor the keystore is committed.
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val storeFilePath = providers.environmentVariable("KEYSTORE_FILE").orNull
    ?: keystoreProperties.getProperty("storeFile")
val storePasswordValue = providers.environmentVariable("KEYSTORE_PASSWORD").orNull
    ?: keystoreProperties.getProperty("storePassword")
val keyAliasValue = providers.environmentVariable("KEY_ALIAS").orNull
    ?: keystoreProperties.getProperty("keyAlias")
val keyPasswordValue = providers.environmentVariable("KEY_PASSWORD").orNull
    ?: keystoreProperties.getProperty("keyPassword")
val storeFileResolved = storeFilePath?.takeIf { it.isNotBlank() }?.let { rootProject.file(it) }
val hasReleaseSigning = storeFileResolved?.isFile == true &&
    !storePasswordValue.isNullOrBlank() &&
    !keyAliasValue.isNullOrBlank() &&
    !keyPasswordValue.isNullOrBlank()

// Plugin-local build cache. Pass -PrimeBuildRoot=... to use another directory.
val rimeBuildRoot = providers.gradleProperty("rimeBuildRoot")
    .map { rootProject.file(it).absolutePath }
    .getOrElse(rootProject.layout.projectDirectory.dir(".cxx/rime").asFile.absolutePath)

abstract class BuildRimeNative @Inject constructor(
    private val execOperations: ExecOperations,
) : DefaultTask() {
    @get:Internal
    abstract val sdkDirectory: DirectoryProperty

    @get:Input
    abstract val buildArguments: ListProperty<String>

    @get:InputFile
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val buildScript: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun build() {
        val output = outputDirectory.get().asFile
        output.deleteRecursively()
        execOperations.exec {
            commandLine(
                listOf(
                    "bash",
                    buildScript.get().asFile.absolutePath,
                    sdkDirectory.get().asFile.absolutePath,
                    output.absolutePath,
                ) + buildArguments.get(),
            )
        }
    }
}

val buildRimeNative = tasks.register<BuildRimeNative>("buildRimeNative") {
    // SDK and NDK contents are supplied by the selected toolchain installation.
    sdkDirectory.set(androidComponents.sdkComponents.sdkDirectory)
    buildScript.set(rootProject.layout.projectDirectory.file("lib/build-android.sh"))
    buildArguments.set(listOf(ndkVersionName, cmakeVersion, minSdkVersion.toString(), rimeBuildRoot, nativeAbi))
    outputDirectory.set(layout.buildDirectory.dir("generated/rimeJniLibs"))
    inputs.files(rootProject.fileTree("lib") { exclude("**/.git") })
        .withPathSensitivity(PathSensitivity.RELATIVE)
}

android {
    namespace = "org.rime.plugin.evo"
    compileSdk = 36
    this.buildToolsVersion = buildToolsVersionName
    ndkVersion = ndkVersionName

    defaultConfig {
        applicationId = "org.rime.plugin.evo"
        minSdk = minSdkVersion
        targetSdk = 36
        versionCode = pluginVersionCode
        ndk.abiFilters.add(nativeAbi)
        versionName = pluginVersionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = storeFileResolved
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            manifestPlaceholders["pluginChannel"] = "release"
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    packaging {
        jniLibs {
            // Extract librime.so into this plugin's nativeLibraryDir so a
            // frontend can dlopen it without copying it into its data directory.
            useLegacyPackaging = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

tasks.register<Delete>("rimeClean") {
    group = "rime"
    description = "Delete the plugin-local librime build cache"
    delete(rimeBuildRoot, buildRimeNative.flatMap { it.outputDirectory })
}

androidComponents {
    beforeVariants(selector().withBuildType("debug")) { it.enable = false }
    onVariants { variant ->
        variant.sources.jniLibs?.addGeneratedSourceDirectory(
            buildRimeNative,
            BuildRimeNative::outputDirectory,
        )
    }
}

base {
    archivesName.set("librime-evo-$pluginVersionName")
}
