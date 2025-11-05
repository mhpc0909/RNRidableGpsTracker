# iOS Example 프로젝트 설정 가이드

이 프로젝트는 GPS 위치 추적 기능을 테스트하기 위한 순수 iOS 예제 앱입니다. CoreLocation을 직접 사용하여 GPS 추적 기능을 시연합니다.

## 빠른 시작

### 1. 의존성 설치

```bash
cd ios-example
pod install
```

### 2. Xcode 프로젝트 열기

```bash
open GPSTrackerExample.xcworkspace
```

**중요**: 반드시 `.xcworkspace` 파일을 열어야 합니다. `.xcodeproj` 파일이 아닙니다.

### 3. 빌드 및 실행

1. Xcode에서 타겟을 `GPSTrackerExample`로 선택
2. 시뮬레이터나 실제 디바이스를 선택
3. `Cmd + R` 또는 Run 버튼을 클릭하여 빌드 및 실행

## 프로젝트 구조

프로젝트는 이미 설정되어 있으며 다음과 같은 파일들이 포함되어 있습니다:

- `AppDelegate.swift`: 앱의 생명주기 관리
- `SceneDelegate.swift`: Scene 기반 UI 관리 (window 설정 포함)
- `ViewController.swift`: GPS 추적 기능을 구현한 메인 뷰 컨트롤러
- `Info.plist`: 위치 권한 및 앱 설정

## 프로젝트 파일 재생성

만약 프로젝트 파일이 손상되었거나 문제가 발생하는 경우:

```bash
# 프로젝트 파일 재생성
ruby create_project.rb

# 의존성 재설치
pod install
```

## 문제 해결

### 빌드 오류가 발생하는 경우

- `pod install`을 다시 실행해보세요
- Xcode를 종료하고 `.xcworkspace` 파일을 다시 여세요
- Derived Data를 삭제하고 다시 빌드해보세요:
  ```bash
  rm -rf ~/Library/Developer/Xcode/DerivedData
  ```

### 프로젝트 파일이 없는 경우

`create_project.rb` 스크립트를 실행하여 프로젝트 파일을 생성할 수 있습니다:

```bash
ruby create_project.rb
pod install
```

## 앱 기능

- GPS 위치 추적 시작/중지
- 현재 위치 가져오기
- 위치 권한 요청
- 위치 히스토리 표시

## 권한 설정

앱은 다음 위치 권한을 사용합니다:

- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `NSLocationAlwaysUsageDescription`
- 백그라운드 위치 업데이트 (`UIBackgroundModes`)

모든 권한은 `Info.plist`에 이미 설정되어 있습니다.
