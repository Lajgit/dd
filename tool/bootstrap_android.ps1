$ErrorActionPreference = "Stop"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "未找到 Flutter。请先安装 Flutter stable，并确保 flutter 已加入 PATH。"
}

flutter create . `
    --platforms=android `
    --project-name=diandi_memory `
    --org=com.lajgit

flutter pub get
flutter analyze
flutter test
flutter build apk --debug
