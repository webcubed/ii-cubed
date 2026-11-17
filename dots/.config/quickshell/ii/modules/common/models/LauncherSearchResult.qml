import QtQuick
import Quickshell

QtObject {
    enum IconType { Material, Text, System, None }
    enum FontType { Normal, Monospace }

    // General stuff
    property string type: ""
    property var fontType: LauncherSearchResult.FontType.Normal
    property string name: ""
    property string rawValue: ""
    property string iconName: ""
    property var iconType: LauncherSearchResult.IconType.None
    property string verb: ""
    // When set, the delegate renders that authenticator's live TOTP code and
    // countdown next to the entry (see Authenticator.qml).
    property string liveAuthenticatorId: ""
    // Upcoming code rows: -1 shows the live code chip, >= 0 renders the nth
    // upcoming code (and its countdown) inside the delegate.
    property int liveUpcomingIndex: -1
    // When set, activating the entry navigates to this query instead of
    // executing it (Flow Launcher style submenus).
    property string drillQuery: ""
    // Lines the name may wrap to; definitions need more than one.
    property int maxLines: 1
    property bool blurImage: false
    property var execute: () => {
        print("Not implemented");
    }
    property var actions: []
    
    // Stuff needed for DesktopEntry 
    property string id: ""
    property bool shown: true
    property string comment: ""
    property bool runInTerminal: false
    property string genericName: ""
    property list<string> keywords: []

    // Extra stuff to allow for more flexibility
    property string category: type
}
