allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
// Use the default build directories to avoid cross-drive path issues
// and let Gradle manage per-project build/ directories.

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
