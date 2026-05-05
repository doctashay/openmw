#ifndef OPENMW_GLWARNINGDIALOG_H
#define OPENMW_GLWARNINGDIALOG_H

namespace OMW
{
    struct LegacyOpenGLWarningResult
    {
        bool mContinue = false;
        bool mDontRemindAgain = false;
    };

    LegacyOpenGLWarningResult showLegacyOpenGLWarningDialog();
}

#endif
