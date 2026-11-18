import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import Qt.labs.platform
import qs.modules.common.functions

Singleton {
    id: root

    // --- Setup ------------------------------------------------------------
    // Empty means "find it": the login shell's PATH first, then the uv tool
    // location where `uv tool install khal` puts the binary.
    readonly property string configuredKhalPath: String(Config.options.calendar.khalPath ?? "").trim()
    property string resolvedKhalPath: ""
    readonly property string khalPath: root.configuredKhalPath.length > 0
        ? root.configuredKhalPath
        : (root.resolvedKhalPath.length > 0
            ? root.resolvedKhalPath
            : Quickshell.env("HOME") + "/.local/bin/khal")

    readonly property bool syncEnabled: Config.options.calendar.sync?.enable ?? false
    readonly property string syncCommand: String(Config.options.calendar.sync?.command ?? "").trim()
    readonly property int syncIntervalMinutes: Number(Config.options.calendar.sync?.intervalMinutes ?? 0)

    // --- Status -----------------------------------------------------------
    property bool khalAvailable: false
    property bool syncAvailable: true
    property bool syncing: false
    property string lastSyncTime: ""
    property string lastSyncError: ""
    property string _syncErrorOutput: ""
    property bool _started: false
    property var calendars: []

    property var events: []
    property var weekdays: [
          Translation.tr("Sunday"),
          Translation.tr("Monday"),
          Translation.tr("Tuesday"),
          Translation.tr("Wednesday"),
          Translation.tr("Thursday"),
          Translation.tr("Friday"),
          Translation.tr("Saturday"),
        ];
    property var sortedWeekdays: root.weekdays.map((_, i) => weekdays[(i+Config.options.time.firstDayOfWeek+1)%7]);
    property var eventsInWeek: root.buildEventsInWeek()

    readonly property var disabledCalendars: Config.options.calendar.disabledCalendars ?? []

    onKhalPathChanged: {
        if (root._started)
            root.checkKhal();
    }

    onDisabledCalendarsChanged: {
        if (root.khalAvailable)
            root.refresh();
    }

    function setCalendarEnabled(name, enabled) {
        const current = Array.from(root.disabledCalendars);
        const next = enabled
            ? current.filter(n => n !== name)
            : (current.includes(name) ? current : current.concat([name]));
        if (next.join("\n") !== current.join("\n"))
            Config.options.calendar.disabledCalendars = next;
    }

    function start() {
        if (root._started)
            return;
        root._started = true;
        if (root.configuredKhalPath.length === 0)
            khalResolveProcess.running = true;
        else
            root.checkKhal();
        if (root.syncEnabled && (Config.options.calendar.sync?.onStartup ?? false))
            root.syncNow();
    }

    function checkKhal() {
        khalCheckProcess.running = true;
    }

    // Switched-off calendars are excluded in the query itself: the school-calendar
    // copies hold thousands of periods each, and parsing them only to drop them again
    // is the difference between a fast refresh and a two-second one.
    function refresh() {
        if (!root.khalAvailable || getEventsProcess.running)
            return;
        const start = new Date();
        start.setMonth(start.getMonth() - 3);
        const end = new Date();
        end.setMonth(end.getMonth() + 3);
        const args = [
            root.khalPath, "list",
            "--json", "title", "--json", "calendar", "--json", "start-date",
            "--json", "start-time", "--json", "end-time", "--json", "description"
        ];
        for (const name of root.disabledCalendars)
            args.push("--exclude-calendar", name);
        args.push(Qt.formatDate(start, "dd.MM.yyyy"), Qt.formatDate(end, "dd.MM.yyyy"));
        getEventsProcess.command = args;
        getEventsProcess.running = true;
    }

    // Calendars first, then their events: refresh needs to know which ones to ask for.
    function loadCalendars() {
        calendarsProcess.running = true;
    }

    // Manual sync works even when the repeating sync is off.
    function syncNow() {
        if (root.syncing || root.syncCommand.length === 0)
            return;
        root.syncAvailable = true;
        root.syncing = true;
        root.lastSyncError = "";
        root._syncErrorOutput = "";
        syncProcess.running = true;
    }

    function buildEventsInWeek() {
        var result = [];
        var d = new Date();
        var currentDay = d.getDay();
        var mondayOffset = currentDay === 0 ? -6 : 1 - currentDay;
        d.setDate(d.getDate() + mondayOffset);
        d.setHours(0, 0, 0, 0);

        for (var i = 0; i < 7; i++) {
            var dayDate = new Date(d);
            dayDate.setDate(d.getDate() + i);
            var dayEvents = root.getTasksByDate(dayDate);
            var weekdayName = root.weekdays[dayDate.getDay()];
            var formattedEvents = [];
            for (var j = 0; j < dayEvents.length; j++) {
                var evt = dayEvents[j];
                var startTime = evt['startDate'] ? Qt.formatDateTime(evt['startDate'], "HH:mm") : "00:00";
                var endTime = evt['endDate'] ? Qt.formatDateTime(evt['endDate'], "HH:mm") : "23:59";
                formattedEvents.push({
                    "title": evt['content'],
                    "start": startTime,
                    "end": endTime,
                    "color": evt['color'],
                    "description": evt['description'] ?? ""
                });
            }
            result.push({
                "name": weekdayName,
                "events": formattedEvents
            });
        }
        return result;
    }

    function getTasksByDate(currentDate) {
        if(!khalAvailable){
          return []
        }
        const res = [];

        const currentDay = currentDate.getDate();
        const currentMonth = currentDate.getMonth();
        const currentYear = currentDate.getFullYear();

        for (let i = 0; i < root.events.length; i++) {
            const taskDate = new Date(root.events[i]['startDate']);
            if (
                taskDate.getDate() === currentDay &&
                taskDate.getMonth() === currentMonth &&
                taskDate.getFullYear() === currentYear
              ) {
                res.push(root.events[i]);
              }
        }

        return res;
    }

    function addItem(item){
        let title =  item['content']
        let formattedDate = Qt.formatDate(item['date'], "dd.MM.yyyy")
        khalAddTaskProcess.command = [root.khalPath, "new", formattedDate, title]
        khalAddTaskProcess.running = true
    }

    function removeItem(item){
        let taskToDelete =  item['content']

        khalRemoveProcess.command = [
          "sqlite3",
          String(StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]).replace("file://", "") + "/.local/share/khal/khal.db",
          "DELETE FROM events WHERE item LIKE '%SUMMARY:" + taskToDelete + "%';"
          ]

          khalRemoveProcess.running = true
          console.log(khalRemoveProcess.command)
    }

    // Find khal when the option leaves it unset.
    Process {
        id: khalResolveProcess
        command: ["bash", "-lc", "command -v khal | tail -n 1"]
        stdout: StdioCollector {
            id: khalResolveOutput
            onStreamFinished: root.resolvedKhalPath = this.text.trim()
        }
        onExited: {
            const detected = khalResolveOutput.text.trim();
            if (detected.length > 0 && detected !== root.resolvedKhalPath)
                root.resolvedKhalPath = detected;
            root.checkKhal();
        }
    }

    // Process for checking khal configuration
    Process {
        id: khalCheckProcess
        running: false
        command: [root.khalPath, "list", "today"]
        onExited: (exitCode) => {
            root.khalAvailable = (exitCode === 0);
            console.log("[CalendarService] khal available:", root.khalAvailable, "at", root.khalPath)
            if (root.khalAvailable)
                root.loadCalendars()
        }
    }

    // Calendar names, so each one can be switched off in Settings.
    Process {
        id: calendarsProcess
        command: [root.khalPath, "printcalendars"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.calendars = this.text.split("\n")
                    .map(line => line.trim())
                    .filter(line => line.length > 0)
                console.log("[CalendarService] Calendars:", root.calendars.join(", "))
            }
        }
        onExited: root.refresh()
    }

    // Process for pulling Google Calendar changes down to the local calendars
    Process {
        id: syncProcess
        command: ["bash", "-lc", root.syncCommand]
        stderr: StdioCollector {
            id: syncStderr
            onStreamFinished: root._syncErrorOutput = this.text
        }
        onExited: (exitCode) => {
            root.syncing = false;
            if (exitCode === 0) {
                root.lastSyncTime = Qt.formatDateTime(new Date(), "HH:mm");
                root.lastSyncError = "";
                root.loadCalendars();
                console.log("[CalendarService] sync finished")
            } else {
                root.lastSyncError = (root._syncErrorOutput.trim()
                    || Translation.tr("Exit code %1").arg(exitCode));
                if (exitCode === 127) // command not found: stop retrying until asked again
                    root.syncAvailable = false;
                console.warn("[CalendarService] sync failed:", root.lastSyncError)
            }
        }
    }

    Timer {
        id: syncTimer
        running: root.syncEnabled && root.syncAvailable && root.syncIntervalMinutes > 0
        interval: Math.max(1, root.syncIntervalMinutes) * 60000
        repeat: true
        onTriggered: root.syncNow()
    }

    // A sync waiting on the network or an auth prompt must not block the timer
    // forever; losing one run is better than never syncing again.
    Timer {
        id: syncWatchdog
        running: root.syncing
        interval: 3 * 60000
        repeat: false
        onTriggered: {
            if (!root.syncing)
                return;
            syncProcess.running = false;
            root.syncing = false;
            root.lastSyncError = Translation.tr("Sync timed out.");
        }
    }

    // Process for loading events
    Process {
      id: getEventsProcess
      running: false
        stdout: StdioCollector {

          onStreamFinished:{
            let events = []
            let lines = this.text.split('\n')
             for(let line of lines){
               line = line.trim()
               if (!line || line === "[]")
                    continue
               let dayEvents
               try {
                 dayEvents = JSON.parse(line)
               } catch(e) {
                 continue
               }
               for(let event of dayEvents){
                 let dateParts = event['start-date'].split('.')
                 let day = parseInt(dateParts[0])
                 let month = parseInt(dateParts[1]) - 1
                 let year = (dateParts.length > 2 && dateParts[2] !== "") ? parseInt(dateParts[2]) : new Date().getFullYear()

                 let startTimeParts = event['start-time']
                     ? event['start-time'].split(':').map(Number)
                     : [0, 0];

                 let endTimeParts = event['end-time']
                     ? event['end-time'].split(':').map(Number)
                     : [23, 59];


                 let startDate = new Date(year, month, day,
                                          parseInt(startTimeParts[0]),
                                          parseInt(startTimeParts[1]))

                 let endDate = new Date(year, month, day,
                                        parseInt(endTimeParts[0]),
                                        parseInt(endTimeParts[1]))

                 events.push({
                     "content": event['title'],
                     "calendar": event['calendar'] ?? "",
                     "startDate": startDate,
                     "endDate": endDate,
                     "color": ColorUtils.stringToColor(event['title']),
                     "description": event['description'] ?? ""
                 })
                 }
               }
               root.events = events
               console.log("[CalendarService] Loaded", events.length, "events")
               root.eventsInWeek = root.buildEventsInWeek()
          }

        }
      }

      Timer {
        id: refreshTimer
        running: root.khalAvailable
        interval: 30000
        repeat: true
        onTriggered: root.refresh()
    }

      Process {
        id: khalAddTaskProcess
        running: false
      }

    Process {
        id: khalRemoveProcess
        running: false
      }

    Component.onCompleted: {
        // Wait for the saved config so a disabled sync is not started with defaults.
        if (Config.ready)
            root.start();
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                root.start();
        }
    }
}
