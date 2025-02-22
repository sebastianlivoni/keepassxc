set(SOURCES
    CredentialProviderViewController.mm
    AutoFillService.mm
    ../browser/BrowserMessageBuilder.cpp
    ../browser/BrowserPasskeysClient.cpp
    ../browser/BrowserPasskeys.cpp
    ../browser/BrowserCbor.cpp
    ../browser/PasskeyUtils.cpp
    ../gui/UrlTools.cpp
)

add_executable(KeePassXCAutofillExtension ${SOURCES})

target_link_libraries(KeePassXCAutofillExtension Qt5::Core Qt5::Network Qt5::Widgets keepassxc_core)
target_link_libraries(KeePassXCAutofillExtension "-framework Foundation -framework SwiftUI -framework AuthenticationServices")

# Add the linker flag for _NSExtensionMain
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -e _NSExtensionMain")

set_target_properties(KeePassXCAutofillExtension PROPERTIES
    MACOSX_BUNDLE ON
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/src/autofill/Info.plist
    BUNDLE_EXTENSION appex
    CPACK_BUNDLE_APPLE_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/src/autofill/autofill.entitlements"
)

install(TARGETS KeePassXCAutofillExtension
        BUNDLE DESTINATION ${PLUGIN_INSTALL_DIR} COMPONENT Runtime)

install(FILES ${CMAKE_SOURCE_DIR}/src/autofill/embedded.provisionprofile DESTINATION ${PLUGIN_INSTALL_DIR}/KeePassXCAutofillExtension.appex/Contents/)

if(WITH_APP_BUNDLE)
    add_custom_command(TARGET KeePassXCAutofillExtension
            POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_BINARY_DIR}/KeePassXCAutofillExtension.appex ${PLUGIN_INSTALL_DIR}/KeePassXCAutofillExtension.appex
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/src
            COMMENT "Copying autofill into plugins")

    #set_property(GLOBAL APPEND PROPERTY _MACDEPLOYQT_EXTRA_BINARIES "${PLUGIN_INSTALL_DIR}/autofill.appex/Contents/MacOS/autofill")
endif()
