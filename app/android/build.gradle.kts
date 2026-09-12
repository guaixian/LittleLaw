allprojects {
    repositories {
        // 国内镜像优先,官方源兜底(直连 google 超时环境)
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
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

// nfc_manager 3.5.x 插件自身 compileSdk=31,但其 androidx 依赖要求 34+。
// 通过 Groovy 脚本在插件应用 AGP 的当刻(DSL 未锁)动态改 compileSdk,
// 规避 AGP 9 的 DSL 锁定与根脚本无 AGP 类路径的双重限制。
apply(from = "nfc-fix.gradle")

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
