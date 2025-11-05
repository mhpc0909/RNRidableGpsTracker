#!/usr/bin/env ruby

# Xcode 프로젝트 생성 스크립트
# 이 스크립트는 기본적인 Xcode 프로젝트 파일을 생성합니다.

require 'fileutils'

PROJECT_NAME = "GPSTrackerExample"
BUNDLE_ID = "com.rnridablegpstracker.example"
PROJECT_DIR = File.dirname(__FILE__)
XCODEPROJ_DIR = File.join(PROJECT_DIR, "#{PROJECT_NAME}.xcodeproj")
APP_DIR = File.join(PROJECT_DIR, PROJECT_NAME)

# UUID 생성 헬퍼
def generate_uuid
  "#{rand(8)}#{rand(4)}#{rand(4)}#{rand(4)}#{rand(12)}".tr('0123456789', '0123456789ABCDEF')
end

# 프로젝트 UUID들 생성
project_uuid = generate_uuid
target_uuid = generate_uuid
app_delegate_file_ref_uuid = generate_uuid
app_delegate_build_file_uuid = generate_uuid
scene_delegate_file_ref_uuid = generate_uuid
scene_delegate_build_file_uuid = generate_uuid
view_controller_file_ref_uuid = generate_uuid
view_controller_build_file_uuid = generate_uuid
info_plist_uuid = generate_uuid
build_config_uuid = generate_uuid
build_config_debug_uuid = generate_uuid
build_config_release_uuid = generate_uuid
group_uuid = generate_uuid
products_group_uuid = generate_uuid
frameworks_group_uuid = generate_uuid
sources_phase_uuid = generate_uuid

# .xcodeproj 디렉토리 생성
FileUtils.mkdir_p(XCODEPROJ_DIR)

# project.pbxproj 파일 생성
pbxproj_content = <<~PBXPROJ
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {
/* Begin PBXBuildFile section */
		#{app_delegate_build_file_uuid} /* AppDelegate.swift in Sources */ = {isa = PBXBuildFile; fileRef = #{app_delegate_file_ref_uuid} /* AppDelegate.swift */; };
		#{scene_delegate_build_file_uuid} /* SceneDelegate.swift in Sources */ = {isa = PBXBuildFile; fileRef = #{scene_delegate_file_ref_uuid} /* SceneDelegate.swift */; };
		#{view_controller_build_file_uuid} /* ViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = #{view_controller_file_ref_uuid} /* ViewController.swift */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		#{app_delegate_file_ref_uuid} /* AppDelegate.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppDelegate.swift; sourceTree = "<group>"; };
		#{scene_delegate_file_ref_uuid} /* SceneDelegate.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SceneDelegate.swift; sourceTree = "<group>"; };
		#{view_controller_file_ref_uuid} /* ViewController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ViewController.swift; sourceTree = "<group>"; };
		#{info_plist_uuid} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		PRODUCT_BUNDLE_IDENTIFIER /* #{PROJECT_NAME}.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "#{PROJECT_NAME}.app"; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		#{frameworks_group_uuid} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		#{group_uuid} /* #{PROJECT_NAME} */ = {
			isa = PBXGroup;
			children = (
				#{app_delegate_file_ref_uuid} /* AppDelegate.swift */,
				#{scene_delegate_file_ref_uuid} /* SceneDelegate.swift */,
				#{view_controller_file_ref_uuid} /* ViewController.swift */,
				#{info_plist_uuid} /* Info.plist */,
				#{products_group_uuid} /* Products */,
			);
			path = #{PROJECT_NAME};
			sourceTree = "<group>";
		};
		#{products_group_uuid} /* Products */ = {
			isa = PBXGroup;
			children = (
				PRODUCT_BUNDLE_IDENTIFIER /* #{PROJECT_NAME}.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
		ROOT_GROUP = {
			isa = PBXGroup;
			children = (
				#{group_uuid} /* #{PROJECT_NAME} */,
			);
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		#{target_uuid} /* #{PROJECT_NAME} */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = #{build_config_uuid} /* Build configuration list for PBXNativeTarget "#{PROJECT_NAME}" */;
			buildPhases = (
				#{sources_phase_uuid} /* Sources */,
				#{frameworks_group_uuid} /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = #{PROJECT_NAME};
			productName = #{PROJECT_NAME};
			productReference = PRODUCT_BUNDLE_IDENTIFIER /* #{PROJECT_NAME}.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		#{project_uuid} /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {
					#{target_uuid} = {
						CreatedOnToolsVersion = 15.0;
					};
				};
			};
			buildConfigurationList = ROOT_CONFIGURATION_LIST /* Build configuration list for PBXProject "#{PROJECT_NAME}" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = ROOT_GROUP;
			productRefGroup = #{products_group_uuid} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				#{target_uuid} /* #{PROJECT_NAME} */,
			);
		};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
		#{sources_phase_uuid} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				#{app_delegate_build_file_uuid} /* AppDelegate.swift in Sources */,
				#{scene_delegate_build_file_uuid} /* SceneDelegate.swift in Sources */,
				#{view_controller_build_file_uuid} /* ViewController.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		#{build_config_debug_uuid} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				INFOPLIST_FILE = #{PROJECT_NAME}/Info.plist;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchStoryboardName = "";
				INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				IPHONEOS_DEPLOYMENT_TARGET = 13.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				PRODUCT_BUNDLE_IDENTIFIER = #{BUNDLE_ID};
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		#{build_config_release_uuid} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				INFOPLIST_FILE = #{PROJECT_NAME}/Info.plist;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchStoryboardName = "";
				INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				IPHONEOS_DEPLOYMENT_TARGET = 13.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				PRODUCT_BUNDLE_IDENTIFIER = #{BUNDLE_ID};
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_VERSION = 5.0;
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		ROOT_CONFIGURATION_LIST /* Build configuration list for PBXProject "#{PROJECT_NAME}" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				#{build_config_debug_uuid} /* Debug */,
				#{build_config_release_uuid} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		#{build_config_uuid} /* Build configuration list for PBXNativeTarget "#{PROJECT_NAME}" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				#{build_config_debug_uuid} /* Debug */,
				#{build_config_release_uuid} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCBuildConfiguration section */
	};
	rootObject = #{project_uuid} /* Project object */;
}
PBXPROJ

File.write(File.join(XCODEPROJ_DIR, "project.pbxproj"), pbxproj_content)

puts "✅ Xcode 프로젝트 파일이 생성되었습니다!"
puts "   #{XCODEPROJ_DIR}/project.pbxproj"

