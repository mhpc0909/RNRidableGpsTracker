#!/bin/bash

# iOS Example 프로젝트 설정 스크립트
# 이 스크립트는 Xcode 프로젝트를 생성하고 설정합니다.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="GPSTrackerExample"
PROJECT_DIR="$SCRIPT_DIR"
APP_DIR="$PROJECT_DIR/$PROJECT_NAME"

echo "🚀 iOS Example 프로젝트 설정을 시작합니다..."

# Xcode가 설치되어 있는지 확인
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode가 설치되어 있지 않습니다. Xcode를 설치해주세요."
    exit 1
fi

# 기존 프로젝트 파일이 있으면 백업
if [ -d "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" ]; then
    echo "⚠️  기존 프로젝트 파일을 백업합니다..."
    mv "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" "$PROJECT_DIR/$PROJECT_NAME.xcodeproj.backup"
fi

echo "📱 Xcode에서 새 프로젝트를 생성해야 합니다."
echo ""
echo "다음 단계를 따라주세요:"
echo ""
echo "1. Xcode를 엽니다"
echo "2. File > New > Project를 선택합니다"
echo "3. iOS > App을 선택하고 Next를 클릭합니다"
echo "4. 다음 정보를 입력합니다:"
echo "   - Product Name: $PROJECT_NAME"
echo "   - Team: (선택 사항)"
echo "   - Organization Identifier: com.rnridablegpstracker"
echo "   - Interface: Storyboard (선택 후 나중에 제거)"
echo "   - Language: Swift"
echo "   - Storage: (선택 사항)"
echo "5. 저장 위치를 다음으로 설정합니다:"
echo "   $PROJECT_DIR"
echo "6. 프로젝트를 생성한 후 Xcode를 닫습니다"
echo ""
echo "프로젝트를 생성하셨나요? (y/n)"
read -r response

if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "프로젝트 생성 후 이 스크립트를 다시 실행해주세요."
    exit 0
fi

# 프로젝트 파일 확인
if [ ! -f "$PROJECT_DIR/$PROJECT_NAME.xcodeproj/project.pbxproj" ]; then
    echo "❌ 프로젝트 파일을 찾을 수 없습니다."
    echo "   $PROJECT_DIR/$PROJECT_NAME.xcodeproj/project.pbxproj"
    exit 1
fi

echo "✅ 프로젝트 파일을 찾았습니다."

# CocoaPods 설치 확인
if ! command -v pod &> /dev/null; then
    echo "⚠️  CocoaPods가 설치되어 있지 않습니다."
    echo "   다음 명령어로 설치할 수 있습니다:"
    echo "   sudo gem install cocoapods"
    exit 1
fi

echo "📦 CocoaPods 의존성을 설치합니다..."
cd "$PROJECT_DIR"
pod install

echo ""
echo "✅ 설정이 완료되었습니다!"
echo ""
echo "다음 명령어로 프로젝트를 열 수 있습니다:"
echo "   open $PROJECT_NAME.xcworkspace"
echo ""
echo "또는 Xcode에서 직접 .xcworkspace 파일을 열어주세요."


