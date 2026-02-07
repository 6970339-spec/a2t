allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val fallbackFlutterConfig =
    mapOf(
        "compileSdkVersion" to 34,
        "minSdkVersion" to 21,
        "targetSdkVersion" to 34,
    )

subprojects {
    if (!extensions.extraProperties.has("flutter")) {
        extensions.extraProperties["flutter"] = fallbackFlutterConfig
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
