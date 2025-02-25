cmake_minimum_required(VERSION 3.10)

# Specify the Swift source
set(SWIFT_SOURCE "${CMAKE_SOURCE_DIR}/src/safariwebextension/SafariWebExtensionHandler.swift")

# Create an object file from the Swift source
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/test.o
    COMMAND swiftc -c ${SWIFT_SOURCE} -o ${CMAKE_BINARY_DIR}/test.o
    DEPENDS ${SWIFT_SOURCE}
    COMMENT "Compiling Swift source file to object file"
)

# Create a custom executable target to package the Swift code
add_executable(KeePassXCSafariWebExtension
    ${CMAKE_BINARY_DIR}/test.o
)

# Add the linker flag for _NSExtensionMain
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -e _NSExtensionMain")

# Set properties for KeePassXCSafariWebExtension
set_target_properties(KeePassXCSafariWebExtension PROPERTIES
    MACOSX_BUNDLE ON
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/src/safariwebextension/Info.plist
    BUNDLE_EXTENSION appex
    CPACK_BUNDLE_APPLE_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/src/safariwebextension/safariwebextension.entitlements"
)

# Install the target as an app bundle
install(TARGETS KeePassXCSafariWebExtension
        BUNDLE DESTINATION ${PLUGIN_INSTALL_DIR} COMPONENT Runtime)

# Compile browser extension and copy into Resources
set(WEB_EXTENSION_SOURCE_DIR "${CMAKE_SOURCE_DIR}/src/safariwebextension/keepassxc-browser")
set(BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/KeePassXCSafariWebExtension.appex/Contents/Resources")

execute_process(
    COMMAND npm ci
    WORKING_DIRECTORY ${WEB_EXTENSION_SOURCE_DIR}
    RESULT_VARIABLE result
    ERROR_QUIET
    OUTPUT_QUIET
)

if (NOT result EQUAL 0)
    message(FATAL_ERROR "npm ci failed with error code ${result}")
endif()

execute_process(
    COMMAND node build.js --skip-translations
    WORKING_DIRECTORY ${WEB_EXTENSION_SOURCE_DIR}
    RESULT_VARIABLE result
    ERROR_QUIET
    OUTPUT_QUIET
)

if (NOT result EQUAL 0)
    message(FATAL_ERROR "Node.js build script failed with error code ${result}")
endif()

set(ZIP_FILE "${WEB_EXTENSION_SOURCE_DIR}/keepassxc-browser_1.9.7_safari.zip")

# Make sure the destination directory exists
file(MAKE_DIRECTORY ${BINARY_DIR})

# Unzip the ZIP file to the destination directory
execute_process(
    COMMAND unzip -o ${ZIP_FILE} -d ${BINARY_DIR}
    RESULT_VARIABLE result
    ERROR_QUIET
    OUTPUT_QUIET
)

# Check if unzip command ran successfully
if (NOT result EQUAL 0)
    message(FATAL_ERROR "Failed to unzip ${ZIP_FILE} to ${BINARY_DIR}")
endif()

if(WITH_APP_BUNDLE)
    add_custom_command(TARGET KeePassXCSafariWebExtension
            POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_BINARY_DIR}/KeePassXCSafariWebExtension.appex ${PLUGIN_INSTALL_DIR}/KeePassXCSafariWebExtension.appex
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/src
            COMMENT "Copying safariwebextension into plugins")
endif()
