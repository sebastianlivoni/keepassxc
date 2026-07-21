set(autotype_mac_SOURCES AutoTypeMac.cpp)

add_library(keepassxc-autotype-cocoa MODULE ${autotype_mac_SOURCES})

# Loaded via QPluginLoader into the already-running KeePassXC process (see
# AutoType::loadPlugin() in src/autotype/AutoType.cpp), not spawned separately,
# so symbols it needs from the host app (macUtils(), MessageBox, Tools, ...)
# are resolved against that process at load time via -bundle_loader. Linking
# ${PROGNAME} in directly (as a regular target_link_libraries dependency)
# instead statically re-links the whole keepassxc_gui/keepassxc_core/autofill
# archive graph into this plugin image too, duplicating every Objective-C
# class it contains in both the host executable and this plugin - which the
# objc runtime flags at startup ("Class X is implemented in both...") and can
# cause spurious casting failures/crashes from mismatched method dispatch.
set_target_properties(keepassxc-autotype-cocoa PROPERTIES LINK_FLAGS "-framework Foundation -framework AppKit -framework Carbon -framework ScreenCaptureKit")
# LINK_FLAGS above is a raw string and does not expand generator expressions,
# so the bundle loader path is passed via target_link_options instead.
target_link_options(keepassxc-autotype-cocoa PRIVATE "-Wl,-bundle_loader,$<TARGET_FILE:${PROGNAME}>")
target_link_libraries(keepassxc-autotype-cocoa Qt5::Core Qt5::Widgets)
add_dependencies(keepassxc-autotype-cocoa ${PROGNAME})

install(TARGETS keepassxc-autotype-cocoa
        LIBRARY DESTINATION ${PLUGIN_INSTALL_DIR} COMPONENT Runtime)

if(WITH_APP_BUNDLE)
    add_custom_command(TARGET keepassxc-autotype-cocoa
            POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_BINARY_DIR}/libkeepassxc-autotype-cocoa.so ${PLUGIN_INSTALL_DIR}/libkeepassxc-autotype-cocoa.so
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/src
            COMMENT "Copying autotype plugin into app bundle")

    set_property(GLOBAL APPEND PROPERTY
        _MACDEPLOYQT_EXTRA_BINARIES "${PLUGIN_INSTALL_DIR}/libkeepassxc-autotype-cocoa.so")
endif()
