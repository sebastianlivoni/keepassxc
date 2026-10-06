include_directories(${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR})

set(autofill_LIB_SOURCES
  app/AutoFillXPCListener.mm
  app/AutoFillService.mm
  app/CredentialExchange.mm
  common/AutoFillCredentials.mm
)

# Credential Exchange is Swift only and needs the macOS 26 SDK; swiftc builds it into a
# plain object file, so no CMake Swift support (and thus no particular generator) is needed
execute_process(COMMAND xcrun --find swiftc OUTPUT_VARIABLE SWIFTC OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
execute_process(COMMAND xcrun --show-sdk-path OUTPUT_VARIABLE MACOS_SDK_PATH OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
execute_process(COMMAND xcrun --show-sdk-version OUTPUT_VARIABLE MACOS_SDK_VERSION OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
if(SWIFTC AND MACOS_SDK_VERSION VERSION_GREATER_EQUAL 26.0)
  set(SWIFT_DEPLOYMENT_TARGET "${CMAKE_OSX_DEPLOYMENT_TARGET}")
  if(NOT SWIFT_DEPLOYMENT_TARGET)
    set(SWIFT_DEPLOYMENT_TARGET 12.0)
  endif()
  set(CREDENTIAL_EXCHANGE_OBJECT ${CMAKE_CURRENT_BINARY_DIR}/CredentialExchangeBridge.o)
  add_custom_command(
    OUTPUT ${CREDENTIAL_EXCHANGE_OBJECT}
    COMMAND ${SWIFTC} -parse-as-library -O -module-name KeePassXCCredentialExchange
            -sdk ${MACOS_SDK_PATH} -target ${CMAKE_SYSTEM_PROCESSOR}-apple-macos${SWIFT_DEPLOYMENT_TARGET}
            -c ${CMAKE_CURRENT_SOURCE_DIR}/app/CredentialExchangeBridge.swift -o ${CREDENTIAL_EXCHANGE_OBJECT}
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/app/CredentialExchangeBridge.swift
    COMMENT "Compiling CredentialExchangeBridge.swift")
  list(APPEND autofill_LIB_SOURCES ${CREDENTIAL_EXCHANGE_OBJECT})
  set(WITH_XC_CREDENTIAL_EXCHANGE ON)
else()
  message(STATUS "Credential Exchange import disabled: needs swiftc and the macOS 26 SDK")
endif()

add_library(autofill STATIC ${autofill_LIB_SOURCES})

if(WITH_XC_CREDENTIAL_EXCHANGE)
  target_compile_definitions(autofill PRIVATE WITH_XC_CREDENTIAL_EXCHANGE)
  # The Swift object autolinks the Swift runtime, found in the SDK and the toolchain
  get_filename_component(SWIFT_TOOLCHAIN_DIR ${SWIFTC} DIRECTORY)
  target_link_directories(autofill PUBLIC
    ${MACOS_SDK_PATH}/usr/lib/swift
    ${SWIFT_TOOLCHAIN_DIR}/../lib/swift/macosx)
endif()

target_compile_options(autofill PRIVATE "-fobjc-arc")

target_compile_definitions(autofill PRIVATE
  APPLE_APP_IDENTIFIER="${APPLE_APP_IDENTIFIER}"
  HELPER_XPC_SERVICE_NAME="${HELPER_XPC_SERVICE_NAME}"
  HELPER_APP_IDENTIFIER="${HELPER_APP_IDENTIFIER}"
  DESIGNATED_REQUIREMENT="${DESIGNATED_REQUIREMENT}"
  AUTOFILL_EXTENSION_IDENTIFIER="${AUTOFILL_EXTENSION_IDENTIFIER}"
  APP_GROUP_IDENTIFIER="${APPLE_TEAM_ID}.${APPLE_APP_IDENTIFIER}"
)

target_link_libraries(autofill Qt6::Core Qt6::Concurrent Qt6::Widgets Qt6::Network ${BOTAN_LIBRARIES})

set(SOURCES
    extension/AutoFillExtensionApplication.cpp
    extension/CredentialProviderViewController.mm
    extension/AutoFillXPCClient.m
    extension/widgets/ConfirmationWidget.mm
    extension/widgets/PasskeyConfirmationWidget.mm
    extension/widgets/PasswordConfirmationWidget.mm
    extension/widgets/OneTimeCodeConfirmationWidget.mm
    extension/widgets/CredentialListWidget.mm
    extension/widgets/DatabaseUnlockWidget.mm
    extension/widgets/DatabasePickerWidget.mm
    extension/widgets/ConfigurationWidget.mm
)

add_executable(KeePassXCAutoFillExtension ${SOURCES})

target_link_libraries(KeePassXCAutoFillExtension Qt6::Core Qt6::Network Qt6::Widgets keepassxc_gui "-framework Foundation -framework AppKit -framework AuthenticationServices -framework LocalAuthentication -framework Security -framework LocalAuthenticationEmbeddedUI -framework ServiceManagement -framework AppKit -framework Carbon -framework ScreenCaptureKit")

target_compile_definitions(KeePassXCAutoFillExtension PRIVATE
  APPLE_APP_IDENTIFIER="${APPLE_APP_IDENTIFIER}"
  APP_GROUP_IDENTIFIER="${APPLE_TEAM_ID}.${APPLE_APP_IDENTIFIER}"
  HELPER_XPC_SERVICE_NAME="${HELPER_XPC_SERVICE_NAME}"
  HELPER_APP_IDENTIFIER="${HELPER_APP_IDENTIFIER}"
  DESIGNATED_REQUIREMENT="${DESIGNATED_REQUIREMENT}"
)

target_compile_options(KeePassXCAutoFillExtension PRIVATE "-fobjc-arc")

# Add the linker flag for _NSExtensionMain
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -e _NSExtensionMain")

configure_file(${CMAKE_SOURCE_DIR}/share/macosx/autofill/autofill.entitlements ${CMAKE_CURRENT_BINARY_DIR}/autofill.entitlements)

set_target_properties(KeePassXCAutoFillExtension PROPERTIES
    MACOSX_BUNDLE ON
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/share/macosx/autofill/Info.plist
    BUNDLE_EXTENSION appex
    CPACK_BUNDLE_APPLE_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/share/macosx/autofill/autofill.entitlements"
)

install(TARGETS KeePassXCAutoFillExtension
        BUNDLE DESTINATION ${PLUGIN_INSTALL_DIR} COMPONENT Runtime)

# The extension's restricted entitlements need its own provisioning profile in
# Developer ID builds; pass the path to embed one (not part of the repository)
set(AUTOFILL_PROVISIONING_PROFILE "" CACHE FILEPATH "Provisioning profile embedded in the AutoFill extension")
if(AUTOFILL_PROVISIONING_PROFILE)
  install(FILES "${AUTOFILL_PROVISIONING_PROFILE}"
          DESTINATION ${PLUGIN_INSTALL_DIR}/KeePassXCAutoFillExtension.appex/Contents
          RENAME embedded.provisionprofile COMPONENT Runtime)
endif()

if(WITH_APP_BUNDLE)
  add_custom_command(TARGET KeePassXCAutoFillExtension
        POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory ${PLUGIN_INSTALL_DIR}/KeePassXCAutoFillExtension.appex
        COMMAND ${CMAKE_COMMAND} -E copy_directory
                ${CMAKE_CURRENT_BINARY_DIR}/KeePassXCAutoFillExtension.appex
                ${PLUGIN_INSTALL_DIR}/KeePassXCAutoFillExtension.appex
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/src
        COMMENT "Copying autofill appex into plugins")

  set_property(GLOBAL APPEND PROPERTY _MACDEPLOYQT_EXTRA_BINARIES "${PLUGIN_INSTALL_DIR}/KeePassXCAutoFillExtension.appex/Contents/MacOS/KeePassXCAutoFillExtension")
endif()
