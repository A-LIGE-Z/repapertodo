# WorkManager opens its generated Room database implementation by reflection.
# R8 full-mode constructor optimization can otherwise remove the no-argument
# constructor and crash the release APK before Flutter starts.
-keep class androidx.work.impl.WorkDatabase_Impl {
    <init>();
}
