pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Simple Pomodoro time manager.
 */
Singleton {
    id: root

    property int focusTime: Config.options.time.pomodoro.focus
    property int breakTime: Config.options.time.pomodoro.breakTime
    property int longBreakTime: Config.options.time.pomodoro.longBreak
    property int cyclesBeforeLongBreak: Config.options.time.pomodoro.cyclesBeforeLongBreak

    property bool pomodoroRunning: Persistent.states.timer.pomodoro.running
    property bool pomodoroBreak: Persistent.states.timer.pomodoro.isBreak
    property bool pomodoroLongBreak: Persistent.states.timer.pomodoro.isBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak);
    property int pomodoroLapDuration: pomodoroLongBreak ? longBreakTime : pomodoroBreak ? breakTime : focusTime // This is a binding that's to be kept
    property int pomodoroSecondsLeft: pomodoroLapDuration // Reasonable init value, to be changed
    property int pomodoroCycle: Persistent.states.timer.pomodoro.cycle

    property bool stopwatchRunning: Persistent.states.timer.stopwatch.running
    property int stopwatchTime: 0
    property int stopwatchStart: Persistent.states.timer.stopwatch.start
    property var stopwatchLaps: Persistent.states.timer.stopwatch.laps

    // General
    Component.onCompleted: {
        if (!stopwatchRunning)
            stopwatchReset();
    }

    function getCurrentTimeInSeconds() {  // Pomodoro uses Seconds
        return Math.floor(Date.now() / 1000);
    }

    function getCurrentTimeIn10ms() {  // Stopwatch uses 10ms
        return Math.floor(Date.now() / 10);
    }

    // Pomodoro
    function refreshPomodoro() {
        // Work <-> break ?
        if (getCurrentTimeInSeconds() >= Persistent.states.timer.pomodoro.start + pomodoroLapDuration) {
            // Reset counts
            Persistent.states.timer.pomodoro.isBreak = !Persistent.states.timer.pomodoro.isBreak;
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();

            // Send notification
            let notificationMessage;
            if (Persistent.states.timer.pomodoro.isBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak)) {
                notificationMessage = Translation.tr(`🌿 Long break: %1 minutes`).arg(Math.floor(longBreakTime / 60));
            } else if (Persistent.states.timer.pomodoro.isBreak) {
                notificationMessage = Translation.tr(`☕ Break: %1 minutes`).arg(Math.floor(breakTime / 60));
            } else {
                notificationMessage = Translation.tr(`🔴 Focus: %1 minutes`).arg(Math.floor(focusTime / 60));
            }

            Quickshell.execDetached(["notify-send", "Pomodoro", notificationMessage, "-a", "Shell"]);
            if (Config.options.sounds.pomodoro) {
                Audio.playSystemSound("alarm-clock-elapsed")
            }

            if (!pomodoroBreak) {
                Persistent.states.timer.pomodoro.cycle = (Persistent.states.timer.pomodoro.cycle + 1) % root.cyclesBeforeLongBreak;
            }
        }

        pomodoroSecondsLeft = pomodoroLapDuration - (getCurrentTimeInSeconds() - Persistent.states.timer.pomodoro.start);
    }

    Timer {
        id: pomodoroTimer
        interval: 200
        running: root.pomodoroRunning
        repeat: true
        onTriggered: refreshPomodoro()
    }

    function togglePomodoro() {
        Persistent.states.timer.pomodoro.running = !pomodoroRunning;
        if (Persistent.states.timer.pomodoro.running) {
            // Start/Resume
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds() + pomodoroSecondsLeft - pomodoroLapDuration;
        }
    }

    function resetPomodoro() {
        Persistent.states.timer.pomodoro.running = false;
        Persistent.states.timer.pomodoro.isBreak = false;
        Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();
        Persistent.states.timer.pomodoro.cycle = 0;
        refreshPomodoro();
    }

    // Scroll-to-set on the desktop tile: a wheel notch moves the current phase (focus,
    // break or long break) by a minute and saves it, so the next cycle uses it too.
    // Refused while the timer runs — shortening a phase mid-cycle would jump the
    // readout and could end the phase outright.
    function pomodoroAdjustPhaseMinutes(minutes) {
        const delta = Math.round(minutes * 60);
        if (root.pomodoroRunning || delta === 0) return;
        if (root.pomodoroBreak) {
            if (root.pomodoroLongBreak) Config.options.time.pomodoro.longBreak = Math.max(60, longBreakTime + delta);
            else Config.options.time.pomodoro.breakTime = Math.max(60, breakTime + delta);
        } else {
            Config.options.time.pomodoro.focus = Math.max(60, focusTime + delta);
        }
        root.pomodoroSecondsLeft = root.pomodoroLapDuration;
    }

    // Stopwatch
    function refreshStopwatch() {  // Stopwatch stores time in 10ms
        stopwatchTime = getCurrentTimeIn10ms() - stopwatchStart;
    }

    Timer {
        id: stopwatchTimer
        interval: 10
        running: root.stopwatchRunning
        repeat: true
        onTriggered: refreshStopwatch()
    }

    function toggleStopwatch() {
        if (root.stopwatchRunning)
            stopwatchPause();
        else
            stopwatchResume();
    }

    function stopwatchPause() {
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchResume() {
        if (stopwatchTime === 0) Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = true;
        Persistent.states.timer.stopwatch.start = getCurrentTimeIn10ms() - stopwatchTime;
    }

    function stopwatchReset() {
        stopwatchTime = 0;
        Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchRecordLap() {
        Persistent.states.timer.stopwatch.laps.push(stopwatchTime);
    }

    // Countdown timer
    property bool countdownRunning: Persistent.states.timer.countdown.running
    property int countdownDuration: Persistent.states.timer.countdown.duration
    property int countdownLeft: Persistent.states.timer.countdown.left

    function refreshCountdown() {
        if (!countdownRunning) return;
        let elapsed = getCurrentTimeInSeconds() - Persistent.states.timer.countdown.start;
        let remaining = countdownDuration - elapsed;
        if (remaining <= 0) {
            Persistent.states.timer.countdown.running = false;
            root.countdownRunning = false;
            Persistent.states.timer.countdown.left = 0;
            root.countdownLeft = 0;
            Quickshell.execDetached(["notify-send", "Timer", "Countdown finished!", "-a", "Shell"]);
            if (Config.options.sounds.timer) {
                Audio.playSystemSound("alarm-clock-elapsed");
            }
        } else {
            Persistent.states.timer.countdown.left = remaining;
            root.countdownLeft = remaining;
        }
    }

    Timer {
        id: countdownTimer
        interval: 200
        running: root.countdownRunning
        repeat: true
        onTriggered: refreshCountdown()
    }

    function countdownSet(minutes) {
        countdownSetSeconds(minutes * 60);
    }

    // Wheel adjustment for the countdown tile. A running timer moves its remaining time
    // with the target (the elapsed part stays elapsed) and can't be scrolled down past
    // the moment it would finish, so a stray scroll never fires the alarm; a paused one
    // moves its saved remaining time by the same amount instead.
    function countdownAdjustMinutes(minutes) {
        const delta = Math.round(minutes * 60);
        if (delta === 0) return;
        const st = Persistent.states.timer.countdown;
        const current = st.duration ?? 0;
        let duration = current + delta;
        if (root.countdownRunning) {
            if (st.start <= 0) return;
            duration = Math.max(getCurrentTimeInSeconds() - st.start + 1, duration);
        } else {
            duration = Math.max(60, duration);
        }
        const applied = duration - current;
        if (applied === 0) return;
        st.duration = duration;
        root.countdownDuration = duration;
        if (root.countdownRunning) {
            refreshCountdown();
        } else {
            const left = Math.max(1, Math.min(duration, (st.left ?? duration) + applied));
            st.left = left;
            root.countdownLeft = left;
        }
    }

    // Same as countdownSet but keeps sub-minute precision, for durations typed into the
    // countdown panel ("1:30", "90s") that would otherwise be rounded to whole minutes.
    function countdownSetSeconds(seconds) {
        const total = Math.max(1, Math.round(seconds));
        countdownStop();
        Persistent.states.timer.countdown.duration = total;
        Persistent.states.timer.countdown.left = total;
        Persistent.states.timer.countdown.start = 0;
        root.countdownDuration = total;
        root.countdownLeft = total;
    }

    function countdownToggle() {
        if (root.countdownRunning) {
            // Pause: save how much is left
            refreshCountdown();
            Persistent.states.timer.countdown.running = false;
        } else {
            if (Persistent.states.timer.countdown.left <= 0) {
                let dur = Persistent.states.timer.countdown.duration > 0 ? Persistent.states.timer.countdown.duration : 1500;
                Persistent.states.timer.countdown.left = dur;
                root.countdownLeft = dur;
                root.countdownDuration = dur;
            }
            // Resume: record start time accounting for time already elapsed
            Persistent.states.timer.countdown.start = getCurrentTimeInSeconds() + Persistent.states.timer.countdown.left - Persistent.states.timer.countdown.duration;
            Persistent.states.timer.countdown.running = true;
        }
        root.countdownRunning = Persistent.states.timer.countdown.running;
    }

    function countdownStop() {
        Persistent.states.timer.countdown.running = false;
        root.countdownRunning = false;
    }

    function countdownReset() {
        countdownStop();
        let dur = Persistent.states.timer.countdown.duration > 0 ? Persistent.states.timer.countdown.duration : 1500;
        Persistent.states.timer.countdown.left = dur;
        Persistent.states.timer.countdown.start = 0;
        root.countdownLeft = dur;
    }

    // --- end4-pC compatibility API (for the imported timers widget) ---
    readonly property int countdownSecondsLeft: countdownLeft
    function formatSeconds(totalSeconds) {
        const s = Math.max(0, Math.round(totalSeconds));
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const sec = s % 60;
        // Hours only appear once they matter, so short timers stay "4:59" and hour-long
        // ones don't read as "90:00".
        if (h > 0) return `${h}:${m.toString().padStart(2, "0")}:${sec.toString().padStart(2, "0")}`;
        return `${m}:${sec.toString().padStart(2, "0")}`;
    }
    function addCountdownMinutes(minutes) {
        const addSeconds = minutes * 60;
        const dur = (Persistent.states.timer.countdown.duration ?? 0) + addSeconds;
        Persistent.states.timer.countdown.duration = dur;
        root.countdownDuration = dur;
        if (!root.countdownRunning) {
            Persistent.states.timer.countdown.left = dur;
            root.countdownLeft = dur;
        }
    }
    function toggleCountdown() { countdownToggle(); }
    function resetCountdown() { countdownReset(); }
}
