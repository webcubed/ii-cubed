import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true
    bottomContentPadding: 15
    
    ColumnLayout {
        id: mainLayout 
        Layout.fillWidth: true   
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "neurology"
            shape: MaterialShape.Shape.Ghostish
            title: Translation.tr("AI")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("System prompt")
                text: Config.options.ai.systemPrompt
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Qt.callLater(() => {
                        Config.options.ai.systemPrompt = text;
                    });
                }
            }
        }

        ContentSection {
            icon: "cell_tower"
            shape: MaterialShape.Shape.PixelCircle
            title: Translation.tr("Networking")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("User agent (for services that require it)")
                text: Config.options.networking.userAgent
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.networking.userAgent = text;
                }
            }
        }

        ContentSection {
            icon: "music_cast"
            shape: MaterialShape.Shape.Oval
            title: Translation.tr("Music Recognition")

            GroupedList {
                ConfigSpinBox {
                    icon: "timer_off"
                    text: Translation.tr("Total duration timeout (s)")
                    value: Config.options.musicRecognition.timeout
                    from: 10
                    to: 100
                    stepSize: 2
                    onValueChanged: {
                        Config.options.musicRecognition.timeout = value;
                    }
                }
                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Polling interval (s)")
                    value: Config.options.musicRecognition.interval
                    from: 2
                    to: 10
                    stepSize: 1
                    onValueChanged: {
                        Config.options.musicRecognition.interval = value;
                    }
                }
            }
        }

        ContentSection {
            icon: "file_open"
            shape: MaterialShape.Shape.Slanted
            title: Translation.tr("Save paths")

            GroupedList {
                ConfigTextArea {
                    id: videoRecordPathField
                    Layout.fillWidth: true
                    fieldWidth: 250
                    buttonIcon: "video_file"
                    text: Translation.tr("Video Recording Path")
                    value: Config.options.screenRecord.savePath
                    onValueChanged: {
                        videoRecordPathDebounceTimer.restart();
                    }

                    Timer {
                        id: videoRecordPathDebounceTimer
                        interval: 600
                        repeat: false
                        onTriggered: {
                            Config.options.screenRecord.savePath = videoRecordPathField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: screenshotPathField
                    Layout.fillWidth: true
                    fieldWidth: 250
                    buttonIcon: "screenshot_monitor"
                    text: Translation.tr("Screenshot Path (leave empty to just copy)")
                    value: Config.options.screenSnip.savePath
                    onValueChanged: {
                        screenshotPathDebounceTimer.restart();
                    }

                    Timer {
                        id: screenshotPathDebounceTimer
                        interval: 600
                        repeat: false
                        onTriggered: {
                            Config.options.screenSnip.savePath = screenshotPathField.value;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "search"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Search")

            GroupedList {
                ConfigSwitch {
                    text: Translation.tr("Use Levenshtein distance-based algorithm instead of fuzzy")
                    checked: Config.options.search.sloppy
                    onCheckedChanged: {
                        Config.options.search.sloppy = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "preview"
                    text: Translation.tr("Show clipboard preview popups")
                    checked: Config.options.search.clipboardPreviewPopup
                    onCheckedChanged: {
                        Config.options.search.clipboardPreviewPopup = checked;
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Prefixes")

                GroupedList {
                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "bolt"
                            fieldWidth: 100
                            text: Translation.tr("Action")
                            value: Config.options.search.prefix.action
                            onValueChanged: {
                                Config.options.search.prefix.action = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "content_paste"
                            fieldWidth: 100
                            text: Translation.tr("Clipboard")
                            value: Config.options.search.prefix.clipboard
                            onValueChanged: {
                                Config.options.search.prefix.clipboard = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "mood"
                            fieldWidth: 100
                            text: Translation.tr("Emojis")
                            value: Config.options.search.prefix.emojis
                            onValueChanged: {
                                Config.options.search.prefix.emojis = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "emoji_symbols"
                            fieldWidth: 100
                            text: Translation.tr("Icons")
                            value: Config.options.search.prefix.symbols
                            onValueChanged: {
                                Config.options.search.prefix.symbols = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "terminal"
                            fieldWidth: 100
                            text: Translation.tr("Shell command")
                            value: Config.options.search.prefix.shellCommand
                            onValueChanged: {
                                Config.options.search.prefix.shellCommand = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            fieldWidth: 100
                            buttonIcon: "travel_explore"
                            text: Translation.tr("Web search")
                            value: Config.options.search.prefix.webSearch
                            onValueChanged: {
                                Config.options.search.prefix.webSearch = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "apps"
                            fieldWidth: 100
                            text: Translation.tr("Apps")
                            value: Config.options.search.prefix.app
                            onValueChanged: {
                                Config.options.search.prefix.app = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "keyboard_command_key"
                            fieldWidth: 100
                            text: Translation.tr("Keybinds")
                            value: Config.options.search.prefix.keybinds
                            onValueChanged: {
                                Config.options.search.prefix.keybinds = value;
                            }
                        }
                    }
                }
            }
            ContentSubsection {
                title: Translation.tr("Web search")

                GroupedList {
                    ConfigTextArea {
                        id: baseUrlField
                        Layout.fillWidth: true
                        fieldWidth: 320
                        buttonIcon: "travel_explore"
                        text: Translation.tr("Base URL")
                        value: Config.options.search.engineBaseUrl
                        onValueChanged: {
                            baseUrlDebounceTimer.restart();
                        }

                        Timer {
                            id: baseUrlDebounceTimer
                            interval: 600
                            repeat: false
                            onTriggered: {
                                Config.options.search.engineBaseUrl = baseUrlField.value;
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "web_asset"
            title: Translation.tr("Webapps")

            GroupedList {
                ConfigTextArea {
                    id: webappUrlField
                    Layout.fillWidth: true
                    fieldWidth: 320
                    fieldHeight: 64
                    multiline: true
                    buttonIcon: "language"
                    text: Translation.tr("Website URL")
                    placeholderText: Translation.tr("example.com (one per line)")
                    confirmButtonVisible: webappUrlField.value.trim() !== "" && !Webapps.busy
                    confirmButtonIcon: "add"
                    onConfirmClicked: {
                        Webapps.create(webappUrlField.value);
                        webappUrlField.value = "";
                    }
                }
            }

            StyledText {
                visible: Webapps.error !== ""
                Layout.fillWidth: true
                Layout.leftMargin: 8
                text: Translation.tr("Could not create: %1").arg(Webapps.error)
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            ContentSubsection {
                title: Translation.tr("Your webapps")
                visible: Webapps.items.length > 0

                GroupedList {
                    ColumnLayout {
                        spacing: 10

                        Repeater {
                            model: Webapps.items

                            delegate: RowLayout {
                                id: webappRow
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.leftMargin: 8
                                Layout.rightMargin: 8
                                spacing: 12

                                Image {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    source: webappRow.modelData.icon.startsWith("/") ? "file://" + webappRow.modelData.icon : ""
                                    sourceSize: Qt.size(56, 56)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: webappRow.modelData.name
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: webappRow.modelData.url
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }

                                RippleButtonWithIcon {
                                    materialIcon: "open_in_new"
                                    mainText: Translation.tr("Open")
                                    onClicked: Webapps.open(webappRow.modelData.id)
                                }
                                RippleButtonWithIcon {
                                    materialIcon: "delete"
                                    mainText: Translation.tr("Remove")
                                    onClicked: Webapps.remove(webappRow.modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "deployed_code_update"
            title: Translation.tr("System updates (Arch only)")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "update"
                    text: Translation.tr("Enable update checks")
                    checked: Config.options.updates.enableCheck
                    onCheckedChanged: {
                        Config.options.updates.enableCheck = checked;
                    }
                }

                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Check interval (mins)")
                    value: Config.options.updates.checkInterval
                    from: 60
                    to: 1440
                    stepSize: 60
                    onValueChanged: {
                        Config.options.updates.checkInterval = value;
                    }
                }
            }
        }

        ContentSection {
            icon: "weather_mix"
            shape: MaterialShape.Shape.Pill
            title: Translation.tr("Weather")
            GroupedList {
                ConfigSwitch {
                    buttonIcon: "assistant_navigation"
                    text: Translation.tr("Enable GPS based location")
                    checked: Config.options.bar.weather.enableGPS
                    onCheckedChanged: {
                        Config.options.bar.weather.enableGPS = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "thermometer"
                    text: Translation.tr("Fahrenheit unit")
                    checked: Config.options.bar.weather.useUSCS
                    onCheckedChanged: {
                        Config.options.bar.weather.useUSCS = checked;
                    }
                }
                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Polling interval (m)")
                    value: Config.options.bar.weather.fetchInterval
                    from: 5
                    to: 50
                    stepSize: 5
                    onValueChanged: {
                        Config.options.bar.weather.fetchInterval = value;
                    }
                }
                ConfigTextArea {
                    id: cityField
                    Layout.fillWidth: true
                    buttonIcon: "location_city"
                    text: Translation.tr("City name")
                    value: Config.options.bar.weather.city
                    onValueChanged: cityDebounceTimer.restart()

                    Timer {
                        id: cityDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: Config.options.bar.weather.city = cityField.value
                    }
                }
            }
        }
        WorldMap {
            Layout.fillWidth: true
            Layout.preferredHeight: 300
        }

        ContentSection {
            icon: "calendar_month"
            title: Translation.tr("Calendar (Google)")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "sync"
                    text: Translation.tr("Keep calendars synced")
                    checked: Config.options.calendar.sync.enable
                    onCheckedChanged: {
                        Config.options.calendar.sync.enable = checked;
                    }
                }
                ConfigSwitch {
                    enabled: Config.options.calendar.sync.enable
                    buttonIcon: "login"
                    text: Translation.tr("Sync on startup")
                    checked: Config.options.calendar.sync.onStartup
                    onCheckedChanged: {
                        Config.options.calendar.sync.onStartup = checked;
                    }
                }
                ConfigSpinBox {
                    enabled: Config.options.calendar.sync.enable
                    icon: "av_timer"
                    text: Translation.tr("Sync interval (minutes, 0 = never)")
                    value: Config.options.calendar.sync.intervalMinutes
                    from: 0
                    to: 240
                    stepSize: 15
                    onValueChanged: {
                        Config.options.calendar.sync.intervalMinutes = value;
                    }
                }
                ConfigTextArea {
                    Layout.fillWidth: true
                    buttonIcon: "terminal"
                    text: Translation.tr("khal executable")
                    description: CalendarService.khalAvailable
                        ? Translation.tr("Found at %1").arg(CalendarService.khalPath)
                        : Translation.tr("Not found at %1").arg(CalendarService.khalPath)
                    placeholderText: Translation.tr("Empty: look it up on PATH")
                    value: Config.options.calendar.khalPath
                    onValueChanged: {
                        Config.options.calendar.khalPath = value;
                    }
                }
                ConfigTextArea {
                    Layout.fillWidth: true
                    buttonIcon: "sync"
                    text: Translation.tr("Sync command")
                    description: Translation.tr("Run through bash -lc")
                    placeholderText: "vdirsyncer sync"
                    value: Config.options.calendar.sync.command
                    onValueChanged: {
                        Config.options.calendar.sync.command = value;
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                RippleButtonWithIcon {
                    materialIcon: "sync"
                    enabled: Config.options.calendar.sync.command.trim().length > 0
                        && !CalendarService.syncing
                    mainText: CalendarService.syncing
                        ? Translation.tr("Syncing…")
                        : Translation.tr("Sync now")
                    onClicked: CalendarService.syncNow()
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: CalendarService.lastSyncError.length > 0
                        ? Appearance.colors.colError
                        : Appearance.colors.colSubtext
                    text: {
                        if (CalendarService.syncing)
                            return Translation.tr("Syncing…");
                        if (!CalendarService.syncAvailable)
                            return Translation.tr("Sync command not found. Use the full path, for example ~/.local/bin/vdirsyncer sync.");
                        if (CalendarService.lastSyncError.length > 0)
                            return Translation.tr("Last sync failed: %1").arg(CalendarService.lastSyncError);
                        if (CalendarService.lastSyncTime.length > 0)
                            return Translation.tr("Last synced at %1.").arg(CalendarService.lastSyncTime);
                        if (!Config.options.calendar.sync.enable)
                            return Translation.tr("Automatic sync is off. Sync now still works.");
                        return Translation.tr("Not synced yet this session.");
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Calendars")
                tooltip: Translation.tr("Turn a calendar off to leave its events out of the bar, dashboard widget, timetable and AI answers.")
                visible: CalendarService.calendars.length > 0

                GroupedList {
                    ColumnLayout {
                        spacing: 2

                        Repeater {
                            model: CalendarService.calendars

                            delegate: ConfigSwitch {
                                required property string modelData
                                Layout.fillWidth: true
                                buttonIcon: "calendar_month"
                                text: modelData
                                checked: !(Config.options.calendar.disabledCalendars || []).includes(modelData)
                                onCheckedChanged: {
                                    CalendarService.setCalendarEnabled(modelData, checked);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
