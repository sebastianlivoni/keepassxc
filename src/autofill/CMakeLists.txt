set(SOURCES
    CredentialProviderViewController.m
)

add_executable(autofill ${SOURCES})

target_link_libraries(autofill "-framework Foundation -framework SwiftUI -framework AuthenticationServices")

# Add the linker flag for _NSExtensionMain
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -e _NSExtensionMain")

set_target_properties(autofill PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/src/autofill/Info.plist
    BUNDLE_EXTENSION appex
    CPACK_BUNDLE_APPLE_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/src/autofill/autofill.entitlements"
)

install(TARGETS autofill
        BUNDLE DESTINATION ${PLUGIN_INSTALL_DIR} COMPONENT Runtime)

install(FILES ${CMAKE_SOURCE_DIR}/src/autofill/embedded.provisionprofile DESTINATION ${PLUGIN_INSTALL_DIR}/autofill.appex/Contents/)

if(WITH_APP_BUNDLE)
    add_custom_command(TARGET autofill
            POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_BINARY_DIR}/autofill.appex ${PLUGIN_INSTALL_DIR}/autofill.appex
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/src
            COMMENT "Copying autofill into plugins")

    set_property(GLOBAL APPEND PROPERTY
        _MACDEPLOYQT_EXTRA_BINARIES "${PLUGIN_INSTALL_DIR}/autofill.appex/Contents/MacOS/autofill")
endif()
