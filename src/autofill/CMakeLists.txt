cmake_minimum_required(VERSION 3.10)

project(SwiftClangExample)

# Specify the Swift source
set(SWIFT_SOURCE "${CMAKE_SOURCE_DIR}/src/autofill/CredentialProviderViewController.swift")

# Create an object file from the Swift source
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/test.o
    COMMAND swiftc -c ${SWIFT_SOURCE} -o ${CMAKE_BINARY_DIR}/test.o
    DEPENDS ${SWIFT_SOURCE}
    COMMENT "Compiling Swift source file to object file"
)

# Create a custom executable target to package the Swift code
add_executable(KeePassXCAutofillExtension
    ${CMAKE_BINARY_DIR}/test.o
)

# Add the linker flag for _NSExtensionMain
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -e _NSExtensionMain")

# Set properties for KeePassXCAutofillExtension
set_target_properties(KeePassXCAutofillExtension PROPERTIES
    MACOSX_BUNDLE ON
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/src/autofill/Info.plist
    BUNDLE_EXTENSION appex
    CPACK_BUNDLE_APPLE_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/src/autofill/autofill.entitlements"
)

# Install the target as an app bundle
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
