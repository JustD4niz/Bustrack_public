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

// Algunos plugins (p. ej. file_picker) fijan compileSdk propio (34) en vez de
// usar flutter.compileSdkVersion, lo que rompe el check de AAR metadata cuando
// flutter_plugin_android_lifecycle exige compilar contra API 36+. Se fuerza
// compileSdk 36 en todos los subproyectos Android por reflexión, porque cada
// subproyecto de plugin carga su propia versión de AGP (para file_picker es 7.4.2).
fun Project.forceCompileSdk36() {
    val android = extensions.findByName("android") ?: return
    try {
        val clazz = android.javaClass
        val setCompileSdk = clazz.methods.firstOrNull {
            it.name == "setCompileSdk" && it.parameterCount == 1 &&
                (it.parameterTypes[0] == Integer.TYPE || it.parameterTypes[0] == Integer::class.java)
        }
        if (setCompileSdk != null) {
            setCompileSdk.invoke(android, 36)
        } else {
            clazz.methods.firstOrNull {
                it.name == "compileSdkVersion" && it.parameterCount == 1 &&
                    it.parameterTypes[0] == String::class.java
            }?.invoke(android, "android-36")
        }
    } catch (e: Exception) {
        logger.warn("No se pudo forzar compileSdk 36 en $path: ${e.message}")
    }
}

subprojects {
    if (project.state.executed) {
        project.forceCompileSdk36()
    } else {
        project.afterEvaluate { forceCompileSdk36() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
