cmake_minimum_required(VERSION 3.13)
set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_CXX_STANDARD 17)

project(RNRidableGpsTracker)

# React Native 경로 설정
set(RN_DIR ${CMAKE_SOURCE_DIR}/../../../node_modules/react-native)

# C++ 소스 파일 (Codegen이 생성함)
file(GLOB LIBRN_SOURCES CONFIGURE_DEPENDS
  "build/generated/source/codegen/jni/*.cpp"
)

add_library(
  ${CMAKE_PROJECT_NAME}
  SHARED
  ${LIBRN_SOURCES}
)

# React Native 헤더 경로
target_include_directories(
  ${CMAKE_PROJECT_NAME}
  PRIVATE
  "${RN_DIR}/ReactCommon"
  "${RN_DIR}/ReactCommon/callinvoker"
  "${RN_DIR}/ReactCommon/jsi"
  "${RN_DIR}/ReactAndroid/src/main/jni"
  "build/generated/source/codegen/jni"
)

# React Native 라이브러리 링크
target_link_libraries(
  ${CMAKE_PROJECT_NAME}
  ReactAndroid::jsi
  ReactAndroid::reactnativejni
  android
  log
)
