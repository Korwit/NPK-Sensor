buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // ต้องกำหนดเวอร์ชัน Kotlin ให้เป็น 1.9.0 ขึ้นไป (แนะนำ 1.9.22)
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.22")
        
        // **สำคัญ**: เช็กเวอร์ชัน AGP (Android Gradle Plugin) ของคุณด้วย 
        // ถ้าบรรทัดนี้ทำให้ error ให้ลองลบออก หรือปรับเวอร์ชันให้ตรงกับที่โปรเจกต์คุณใช้อยู่ (เช่น 8.1.0, 8.2.0)
        classpath("com.android.tools.build:gradle:8.11.1") 
    }
}

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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
