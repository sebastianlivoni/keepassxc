set(SOURCES
    CredentialProviderViewController.mm
    ExtensionConfigurationWidget.mm
    PasskeyRegistrationWidget.mm
    CredentialListWidget.mm
    AutoFillService.mm
    AutoFillViewController.mm
    ../browser/BrowserMessageBuilder.cpp
    ../browser/BrowserPasskeysClient.cpp
    ../browser/BrowserPasskeys.cpp
    ../browser/BrowserCbor.cpp
    ../browser/PasskeyUtils.cpp
    ../gui/UrlTools.cpp
    ../quickunlock/TouchID.mm
)

add_executable(KeePassXCAutoFillExtension ${SOURCES})

target_link_libraries(KeePassXCAutoFillExtension Qt5::Core Qt5::Network Qt5::Widgets keepassxc_core "-framework Foundation -framework AppKit -framework AuthenticationServices -framework LocalAuthentication -framework Security")

# Add the linker flag for _NSExtensionMain
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -e _NSExtensionMain")

set_target_properties(KeePassXCAutoFillExtension PROPERTIES
    MACOSX_BUNDLE ON
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/src/autofill/Info.plist
    BUNDLE_EXTENSION appex
    CPACK_BUNDLE_APPLE_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/src/autofill/autofill.entitlements"
)

install(TARGETS KeePassXCAutoFillExtension
        BUNDLE DESTINATION ${PLUGIN_INSTALL_DIR} COMPONENT Runtime)

#install(FILES ${CMAKE_SOURCE_DIR}/src/autofill/embedded.provisionprofile DESTINATION ${PLUGIN_INSTALL_DIR}/KeePassXCAutoFillExtension.appex/Contents/)

if(WITH_APP_BUNDLE)
    add_custom_command(TARGET KeePassXCAutoFillExtension
            POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_BINARY_DIR}/KeePassXCAutoFillExtension.appex ${PLUGIN_INSTALL_DIR}/KeePassXCAutoFillExtension.appex
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/src
            COMMENT "Copying autofill into plugins")

    set_property(GLOBAL APPEND PROPERTY _MACDEPLOYQT_EXTRA_BINARIES "${PLUGIN_INSTALL_DIR}/KeePassXCAutoFillExtension.appex/Contents/MacOS/KeePassXCAutoFillExtension")
endif()
