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

// Kotlin IC stores source paths relative to android/. Flutter plugins live in
// the pub cache (often C:\...) while this project is on D:\ — Windows cannot
// relativize across drive roots (KT-63983). Disable IC for those subprojects
// only; :app stays incremental.
subprojects {
    if (!projectDir.canonicalPath.startsWith(rootDir.canonicalPath)) {
        extra["kotlin.incremental"] = "false"
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
