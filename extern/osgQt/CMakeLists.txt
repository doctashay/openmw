set(OSGQT_LIBRARY "osgQt")

# Sources

set(SOURCE_H
    include/osgQt/osgQOpenGLWidget.hpp
    include/osgQt/CompositeOsgRenderer.hpp
)

if(USE_QT4)
    QT4_WRAP_CPP(SOURCES_H_MOC ${SOURCE_H})
else()
    qt_wrap_cpp(SOURCES_H_MOC ${SOURCE_H})
endif()

set(OSGQT_SOURCE_FILES
    osgQOpenGLWidget.cpp
    CompositeOsgRenderer.cpp
    ${SOURCES_H_MOC}
)

add_library(${OSGQT_LIBRARY} STATIC ${OSGQT_SOURCE_FILES})
target_include_directories(${OSGQT_LIBRARY} SYSTEM PUBLIC include)
target_include_directories(${OSGQT_LIBRARY} PRIVATE include/osgQt)

if(USE_QT4)
    target_link_libraries(${OSGQT_LIBRARY} ${QT_QTCORE_LIBRARY} ${QT_QTOPENGL_LIBRARY})
else()
    target_link_libraries(${OSGQT_LIBRARY} Qt::Core Qt::OpenGL Qt::OpenGLWidgets)
endif()

set(EXTERN_OSGQT_LIBRARY ${OSGQT_LIBRARY} PARENT_SCOPE)
