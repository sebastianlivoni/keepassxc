include_directories(${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR})

set(autofill_LIB_SOURCES
  AutoFillXPCService.mm
  AutoFillService.mm
  AutoFillServiceV2.mm
)

add_library(autofill STATIC ${autofill_LIB_SOURCES})

target_compile_options(autofill PRIVATE "-fobjc-arc")

target_compile_definitions(autofill PRIVATE
  APPLE_APP_IDENTIFIER="${APPLE_APP_IDENTIFIER}"
  RENDEZVOUS_XPC_SERVICE_NAME="${RENDEZVOUS_XPC_SERVICE_NAME}"
  RENDEZVOUS_APP_IDENTIFIER="${RENDEZVOUS_APP_IDENTIFIER}"
  DESIGNATED_REQUIREMENT="${DESIGNATED_REQUIREMENT}"
  AUTOFILL_EXTENSION_IDENTIFIER="${AUTOFILL_EXTENSION_IDENTIFIER}"
)

target_link_libraries(autofill Qt5::Core Qt5::Concurrent Qt5::Widgets Qt5::Network ${BOTAN_LIBRARIES})

set(SOURCES
    AutoFillExtensionApplication.cpp
    CredentialProviderViewController.mm
    ExtensionConfigurationWidget.mm
    ConfirmationWidget.mm
    PasskeyConfirmationWidget.mm
    PasskeyRegistrationWidget.mm
    PasswordConfirmationWidget.mm
    OneTimeCodeConfirmationWidget.mm
    CredentialListWidget.mm
    DatabaseUnlockWidget.mm
    DatabasePickerWidget.mm
    BrowserPasskeysConfirmationDialogV2.mm
    AutoFillXPCServiceClient.m
    AutoFillService.mm
)

add_executable(KeePassXCAutoFillExtension ${SOURCES})

target_link_libraries(KeePassXCAutoFillExtension Qt5::Core Qt5::Network Qt5::Widgets keepassxc_gui "-framework Foundation -framework AppKit -framework AuthenticationServices -framework LocalAuthentication -framework Security -framework LocalAuthenticationEmbeddedUI -framework ServiceManagement -framework AppKit -framework Carbon -framework ScreenCaptureKit")

target_compile_definitions(KeePassXCAutoFillExtension PRIVATE
  APPLE_APP_IDENTIFIER="${APPLE_APP_IDENTIFIER}"
  RENDEZVOUS_XPC_SERVICE_NAME="${RENDEZVOUS_XPC_SERVICE_NAME}"
  RENDEZVOUS_APP_IDENTIFIER="${RENDEZVOUS_APP_IDENTIFIER}"
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
    CPACK_BUNDLE_APPLE_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/share/macosx/autofill.entitlements"
)

install(TARGETS KeePassXCAutoFillExtension
        BUNDLE DESTINATION ${PLUGIN_INSTALL_DIR} COMPONENT Runtime)

#install(FILES ${CMAKE_SOURCE_DIR}/src/autofill/embedded.provisionprofile DESTINATION ${PLUGIN_INSTALL_DIR}/KeePassXCAutoFillExtension.appex/Contents/)

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
