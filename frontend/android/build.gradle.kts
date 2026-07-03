allprojects {
    repositories {
        google()
        mavenCentral()
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
subprojects {
    afterEvaluate {
        // AGP 9.x requires namespace in every module. Inject one for
        // third-party libraries (e.g. isar_flutter_libs) that omit it.
        if (extensions.findByName("android") is com.android.build.gradle.LibraryExtension) {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                namespace.set(namespace.orNull ?: "com.example.${project.name}")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
