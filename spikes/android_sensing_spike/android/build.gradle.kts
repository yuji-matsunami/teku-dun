allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // flutter_background_geolocation と tracelet が同じ play-services-location を
    // 参照する。版を1か所で揃え、解決時の食い違いを避ける。
    extra["playServicesLocationVersion"] = "21.3.0"
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
