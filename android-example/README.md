# Android Example 프로젝트 설정 가이드

이 프로젝트는 GPS 위치 추적 기능을 테스트하기 위한 순수 Android 예제 앱입니다. Google Play Services Location API를 직접 사용하여 GPS 추적 기능을 시연합니다.

## 빠른 시작

### 방법 1: Android Studio 사용 (권장)

1. **Android Studio에서 프로젝트 열기**

   - Android Studio를 실행합니다
   - `File > Open`을 선택합니다
   - `android-example` 폴더를 선택합니다
   - Android Studio가 자동으로 Gradle을 동기화합니다

2. **빌드 및 실행**
   - Android Studio에서 `Run > Run 'app'`을 선택하거나 `Shift + F10`을 누릅니다
   - 시뮬레이터나 실제 디바이스를 선택합니다

### 방법 2: 명령줄 사용

1. **Gradle Wrapper 설정** (처음 한 번만)

   ```bash
   cd android-example
   # Android Studio에서 프로젝트를 한 번 열면 자동으로 생성됩니다
   # 또는 다음 명령으로 직접 생성:
   # gradle wrapper --gradle-version 8.2
   ```

2. **빌드**

   ```bash
   ./gradlew build
   ```

3. **실행**
   ```bash
   ./gradlew installDebug
   ```

## 프로젝트 구조

프로젝트는 이미 설정되어 있으며 다음과 같은 파일들이 포함되어 있습니다:

- `MainActivity.kt`: GPS 추적 기능을 구현한 메인 액티비티
- `activity_main.xml`: UI 레이아웃
- `AndroidManifest.xml`: 위치 권한 및 앱 설정

## 주요 기능

- GPS 위치 추적 시작/중지
- 현재 위치 가져오기
- 위치 권한 요청
- 위치 히스토리 표시

## 권한 설정

앱은 다음 위치 권한을 사용합니다:

- `ACCESS_FINE_LOCATION`: 정확한 위치 정보
- `ACCESS_COARSE_LOCATION`: 대략적인 위치 정보
- `ACCESS_BACKGROUND_LOCATION`: 백그라운드 위치 추적 (Android 10+)
- `FOREGROUND_SERVICE`: 포그라운드 서비스
- `FOREGROUND_SERVICE_LOCATION`: 위치 추적 포그라운드 서비스
- `POST_NOTIFICATIONS`: 알림 권한 (Android 13+)

모든 권한은 `AndroidManifest.xml`에 이미 설정되어 있습니다.

## 의존성

이 프로젝트는 다음 라이브러리를 사용합니다:

- Kotlin Standard Library
- AndroidX Core KTX
- AndroidX AppCompat
- Google Material Design
- AndroidX ConstraintLayout
- Google Play Services Location API
- AndroidX CardView

모든 의존성은 `app/build.gradle`에 정의되어 있습니다.

## 문제 해결

### Gradle 동기화 실패

- Android Studio에서 `File > Sync Project with Gradle Files`를 실행하세요
- `File > Invalidate Caches / Restart`를 시도하세요

### 빌드 오류

- `./gradlew clean`을 실행한 후 다시 빌드하세요
- Android Studio의 `Build > Clean Project`를 실행하세요

### 위치 권한 문제

- 앱 설정에서 위치 권한이 허용되어 있는지 확인하세요
- Android 10 이상에서는 백그라운드 위치 권한을 별도로 요청해야 합니다
