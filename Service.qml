import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property bool lockRequested: false
  property bool pendingSessionLock: false
  property bool authenticatingPassword: false
  property bool fingerprintAuthenticating: false
  property bool passwordPamConfigured: false
  property bool fingerprintConfigured: false

  // Gaze (GunduLabs/gaze) face unlock. gazeState is the one-line verdict from
  // gazeCheckProc: missing (no gaze binary), daemon-stopped (gazed down),
  // no-face (installed but nothing enrolled), ready, or unknown (not checked yet).
  property string gazeState: "unknown"
  property bool gazeAuthenticating: false
  property int gazeAttempts: 0
  property double gazeBurstEndedAt: 0
  property bool gazeSetupRequested: false
  property bool gazeSetupIgnored: false
  property bool gazeSetupRunning: false
  property bool gazeEnabled: true
  property string gazeToggleRequest: "disable"
  property bool previewVisible: false
  property string enteredPassword: ""
  property string pendingPassword: ""
  property string failureMessage: ""
  property int failedAttempts: 0
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property string lastEvent: "init"
  property string lastEventAt: ""
  property bool strandedLock: false
  property bool strandedLockResolved: false

  readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure
  readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating

  readonly property bool gazeConfigured: gazeEnabled && gazeState === "ready"

  // A burst of quick scans when the lock screen appears, then it goes quiet so
  // typing is never fought over; any wake interaction rearms it (Windows Hello).
  readonly property int gazeMaxAttempts: 3
  readonly property int gazeRearmDelay: 5000

  // The plugin ships its own PAM service next to Service.qml, so nothing in
  // /etc/pam.d is needed or edited -- mirroring how Quickshell resolves configDirectory.
  readonly property string pluginDirectory: {
    var path = String(Qt.resolvedUrl("."))
    if (path.indexOf("file://") === 0) path = path.substring(7)
    return decodeURIComponent(path).replace(/\/+$/, "")
  }

  // Cards the setup guide on first run; persisted vs session-dismissed lives in
  // ~/.local/state/omarchy/dsns.lock-gaze-*. Files written by the IPC toggles below.
  readonly property string gazeDisabledFile: stateHome + "/omarchy/dsns.lock-gaze-disabled"
  readonly property string gazeDismissedFile: stateHome + "/omarchy/dsns.lock-gaze-dismissed"

  // Auto-appears whenever gaze is not ready and wasn't told to shut up. Never
  // over the lock; the user (or IPC with gazeSetup) can always bring it back.
  readonly property bool gazeSetupCardVisible:
    !root.locked &&
    (gazeSetupRequested ||
       (gazeEnabled && gazeState !== "unknown" && gazeState !== "ready" && !gazeSetupIgnored))

  function realScreenCount() {
    var screens = Quickshell.screens || []
    var count = 0

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (screen && screen.name && screen.width > 0 && screen.height > 0) count += 1
    }

    return count
  }

  function hasRealScreen() {
    return realScreenCount() > 0
  }

  function queueSessionLock() {
    pendingSessionLock = true
    if (!sessionLockStabilizeTimer.running) logEvent("lock-pending: screen-stabilizing")
    sessionLockStabilizeTimer.restart()
    if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
  }

  function requestSessionLock() {
    if (!lockRequested || sessionLock.locked || sessionLock.secure) return
    if (sessionLockStabilizeTimer.running) return

    if (!hasRealScreen()) {
      if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen") logEvent("lock-pending: no-real-screen")
      pendingSessionLock = true
      if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
      return
    }

    pendingSessionLock = false
    pendingSessionLockTimer.stop()
    sessionLock.locked = true
  }

  // ext-session-lock outlives its client, and a restart carries no lock over, so
  // a session locked this early is an orphan behind Hyprland's failsafe. Outputs
  // are often still absent here, so ask until the answer means something.
  function checkStrandedLock() {
    if (strandedLockResolved || strandedLockCheckProc.running) return

    // A lock this shell took is nobody's orphan.
    if (locked || lockRequested) {
      strandedLockResolved = true
      return
    }

    strandedLockCheckProc.running = true
  }

  function recoverStrandedLock() {
    if (!strandedLock || locked || !passwordPamConfigured) return

    strandedLock = false
    logEvent("lock-stranded: recovering")
    beginLock()
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function refreshFingerprintStatus() {
    if (!fingerprintCheckProc.running) fingerprintCheckProc.running = true
  }

  function refreshGazeStatus() {
    if (!gazeCheckProc.running) gazeCheckProc.running = true
  }

  function showGazeSetupCard() {
    gazeSetupRequested = true
  }

  function hideGazeSetupCard() {
    gazeSetupRequested = false
  }

  function dismissGazeSetupCard() {
    hideGazeSetupCard()
    gazeSetupIgnored = true
    if (!gazeDismissProc.running) gazeDismissProc.running = true
  }

  function launchGazeSetup() {
    showGazeSetupCard()
    if (!gazeSetupRunner.running) {
      gazeSetupRunning = true
      gazeSetupRunner.running = true
    }
  }

  function toggleGaze(enable) {
    gazeToggleRequest = enable ? "enable" : "disable"
    if (!gazeToggleProc.running) gazeToggleProc.running = true
  }

  function logEvent(event) {
    lastEvent = event
    lastEventAt = new Date().toISOString()
    console.log("omarchy lock " + lastEventAt + " " + event)
  }

  function resetAuthenticationState() {
    enteredPassword = ""
    pendingPassword = ""
    failureMessage = ""
    failedAttempts = 0
    authenticatingPassword = false
    fingerprintAuthenticating = false
    fingerprintRetryTimer.stop()
    if (passwordPam.active) passwordPam.abort()
    if (fingerprintPam.active) fingerprintPam.abort()
    stopGaze()
    gazeAttempts = 0
    gazeBurstEndedAt = 0
  }

  function beginLock() {
    if (!passwordPamConfigured) {
      logEvent("lock-denied: missing-pam")
      return false
    }

    resetAuthenticationState()
    lockRequested = true
    logEvent("lock-requested")
    queueSessionLock()

    Qt.callLater(function() {
      root.refreshBackground()
      root.refreshFingerprintStatus()
      root.refreshGazeStatus()
    })

    return true
  }

  function finishUnlock() {
    if (!root.locked && !lockRequested) return

    lockRequested = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    sessionLock.locked = false
    logEvent("unlocked")
    runWake()
  }

  function runWake() {
    if (!wakeProcess.running) wakeProcess.running = true
    // Keystrokes and mouse moves on the lock surface wake it up; a burst that
    // spent its scans waiting for the user to show up gets another chance.
    if (lockRequested) rearmGaze()
  }

  function submitPassword(value) {
    var password = String(value || "")
    if (!lockRequested || authenticatingPassword || password.length === 0) return

    runWake()
    stopGaze()
    pendingPassword = password
    failureMessage = ""
    authenticatingPassword = true

    if (!passwordPam.start()) {
      handlePasswordFailure()
      return
    }

    Qt.callLater(respondToPasswordPrompt)
  }

  function respondToPasswordPrompt() {
    if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired) return
    passwordPam.respond(pendingPassword)
  }

  function handlePasswordFailure() {
    if (!lockRequested) return

    authenticatingPassword = false
    enteredPassword = ""
    pendingPassword = ""
    failedAttempts += 1
    failureMessage = "Authentication failed (" + failedAttempts + ")"
    gazeAttempts = 0
    gazeBurstEndedAt = 0
    runWake()
    // The camera is pointed at the user who just failed their password;
    // a failed password is a perfect moment for another face scan.
    startGaze()
  }

  function startFingerprint() {
    if (!lockRequested || !sessionLock.secure || !fingerprintConfigured) return
    if (fingerprintPam.active || fingerprintAuthenticating) return

    fingerprintAuthenticating = true
    if (!fingerprintPam.start()) {
      fingerprintAuthenticating = false
    }
  }

  function startGaze() {
    if (!gazeConfigured) return
    if (!lockRequested || !sessionLock.secure) return
    if (gazePam.active || gazeAuthenticating) return
    if (authenticatingPassword) return
    if (gazeAttempts >= gazeMaxAttempts) return

    gazeAttempts += 1
    gazeAuthenticating = true
    logEvent("gaze-scan: attempt " + gazeAttempts + "/" + gazeMaxAttempts)

    if (!gazePam.start()) {
      gazeAuthenticating = false
      endGazeBurst("start-failed")
    }
  }

  function stopGaze() {
    gazeRetryTimer.stop()
    gazeAuthenticating = false
    if (gazePam.active) gazePam.abort()
  }

  function endGazeBurst(reason) {
    gazeRetryTimer.stop()
    gazeAttempts = gazeMaxAttempts
    gazeBurstEndedAt = Date.now()
    logEvent("gaze-idle: " + reason)
  }

  function rearmGaze() {
    if (!gazeConfigured || !lockRequested) return
    if (gazePam.active || gazeAuthenticating) return
    if (gazeAttempts < gazeMaxAttempts) return
    if (Date.now() - gazeBurstEndedAt < gazeRearmDelay) return

    gazeAttempts = 0
    startGaze()
  }

  function handleGazeFinished(result) {
    gazeAuthenticating = false

    if (!lockRequested) return
    if (result === PamResult.Success) {
      logEvent("gaze-success")
      finishUnlock()
      return
    }

    if (gazeAttempts >= gazeMaxAttempts) {
      endGazeBurst("no match")
      return
    }

    gazeRetryTimer.restart()
  }

  function handleFingerprintFinished(result) {
    fingerprintAuthenticating = false

    if (!lockRequested) return
    if (result === PamResult.Success) {
      finishUnlock()
    } else if (fingerprintConfigured) {
      fingerprintRetryTimer.restart()
    }
  }

  WlSessionLock {
    id: sessionLock

    locked: false

    onSecureStateChanged: {
      root.logEvent("secure=" + secure)
      if (secure) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.startFingerprint()
        root.startGaze()
      }
    }

    onLockStateChanged: {
      root.logEvent("session-locked=" + locked)

      if (locked) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
      }

      if (!locked && root.lockRequested) {
        root.lockRequested = false
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.resetAuthenticationState()
        root.runWake()
      }
    }

    WlSessionLockSurface {
      id: lockSurface
      color: Color.background

      LockView {
        id: lockView
        anchors.fill: parent
        backgroundPath: root.backgroundPath
        backgroundVersion: root.backgroundVersion
        fingerprintConfigured: root.fingerprintConfigured
        gazeConfigured: root.gazeConfigured
        gazeScanning: root.gazeAuthenticating
        authenticatingPassword: root.authenticatingPassword
        failureMessage: root.failureMessage
        failedAttempts: root.failedAttempts
        inputEnabled: root.lockRequested
        loadBackground: root.locked
        passwordText: root.enteredPassword
        onPasswordTextEdited: function(password) { root.enteredPassword = password }
        onSubmitPassword: function(password) { root.submitPassword(password) }
        onClearFailureRequested: root.failureMessage = ""
        onWakeRequested: root.runWake()
      }

    }
  }

  PanelWindow {
    id: previewWindow
    visible: root.previewVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-lock-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    LockView {
      anchors.fill: parent
      backgroundPath: root.backgroundPath
      backgroundVersion: root.backgroundVersion
      fingerprintConfigured: root.fingerprintConfigured
      gazeConfigured: root.gazeConfigured
      gazeScanning: false
      authenticatingPassword: false
      failureMessage: ""
      failedAttempts: 0
      inputEnabled: false
      loadBackground: root.previewVisible
      passwordText: ""
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.previewVisible = false
    }
  }

  PamContext {
    id: passwordPam
    config: "omarchy-lock-password"
    user: root.userName

    onResponseRequiredChanged: root.respondToPasswordPrompt()
    onPamMessage: root.respondToPasswordPrompt()

    onCompleted: function(result) {
      root.authenticatingPassword = false
      root.pendingPassword = ""

      if (!root.lockRequested) return
      if (result === PamResult.Success) root.finishUnlock()
      else root.handlePasswordFailure()
    }

    onError: function(error) {
      root.handlePasswordFailure()
    }
  }

  PamContext {
    id: fingerprintPam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    onCompleted: function(result) {
      root.handleFingerprintFinished(result)
    }

    onError: function(error) {
      root.fingerprintAuthenticating = false
      if (root.lockRequested && root.fingerprintConfigured) fingerprintRetryTimer.restart()
    }
  }

  Timer {
    id: fingerprintRetryTimer
    interval: 250
    repeat: false
    onTriggered: root.startFingerprint()
  }

  // Face unlock runs against the plugin's own PAM service (omarchy-lock-gaze,
  // found in pluginDirectory), which stacks pam_gaze.so alone: face pass or
  // nothing, password fallback stays under the passwordPam context here.
  PamContext {
    id: gazePam
    config: "omarchy-lock-gaze"
    configDirectory: root.pluginDirectory
    user: root.userName

    onResponseRequiredChanged: {
      if (!responseRequired) return
      // pam_gaze never converses; a prompt means the service file changed
      // under us. Abort rather than feed it typed secrets.
      root.logEvent("gaze-abort: unexpected prompt")
      root.stopGaze()
      root.endGazeBurst("unexpected prompt")
    }

    onCompleted: function(result) {
      root.handleGazeFinished(result)
    }

    onError: function(error) {
      root.gazeAuthenticating = false
      root.endGazeBurst("pam error " + error)
    }
  }

  Timer {
    id: gazeRetryTimer
    interval: 400
    repeat: false
    onTriggered: root.startGaze()
  }

  // One bash probe answers everything about the local gaze install. Requires
  // the daemon up, so a stopped gazed reports as daemon-stopped, not no-face.
  Process {
    id: gazeCheckProc
    command: ["bash", "-c", "if ! command -v gaze >/dev/null 2>&1; then echo missing; elif ! systemctl is-active --quiet gazed.service 2>/dev/null; then echo daemon-stopped; else faces=$(gaze list-faces 2>/dev/null || true); if [[ -z $faces || $faces == *'No faces found'* ]]; then echo no-face; else echo ready; fi; fi"]
    stdout: StdioCollector { id: gazeCheckStdout; waitForEnd: true }
    onExited: {
      var answer = String(gazeCheckStdout.text || "").trim()
      root.gazeState = answer.length > 0 ? answer : "unknown"
      root.logEvent("gaze-state: " + root.gazeState)

      if (root.gazeConfigured) {
        if (root.lockRequested && sessionLock.secure) root.startGaze()
        else if (gazePam.active) gazePam.abort()
      } else if (gazePam.active) {
        gazePam.abort()
      }
    }
  }

  // Runs the plugin's installer/enroller in a user-visible terminal: AUR build
  // and sudo for the daemon both want one.
  Process {
    id: gazeSetupRunner
    command: {
      var bin = root.pluginDirectory + "/gaze-setup.sh"
      var launcher =
        "if command -v omarchy-launch-tui >/dev/null 2>&1; then" +
        " exec omarchy-launch-tui bash \"$1\"" +
        " elif command -v xdg-terminal-exec >/dev/null 2>&1; then" +
        " exec xdg-terminal-exec -e bash \"$1\"" +
        " elif command -v kitty >/dev/null 2>&1; then" +
        " exec kitty bash \"$1\"" +
        " elif command -v alacritty >/dev/null 2>&1; then" +
        " exec alacritty -e bash \"$1\"" +
        " elif command -v foot >/dev/null 2>&1; then" +
        " exec foot bash \"$1\"" +
        " else exec bash \"$1\"; fi"
      return ["bash", "-c", launcher, "gaze-setup", bin]
    }
    onExited: {
      root.gazeSetupRunning = false
      // Enrollment lands before exit, but give the daemon a beat, then let
      // gazeRescanTimer keep the card honest while it stays open.
      Qt.callLater(root.refreshGazeStatus)
    }
  }

  Process {
    id: gazeDismissProc
    command: ["bash", "-c", 'd="$HOME/.local/state/omarchy"; mkdir -p "$d"; touch "$d/dsns.lock-gaze-dismissed"']
    onExited: root.gazeSetupIgnored = true
  }

  Process {
    id: gazeToggleProc
    command: ["bash", "-c", 'd="$HOME/.local/state/omarchy"; mkdir -p "$d"; if [[ $1 == enable ]]; then rm -f "$d/dsns.lock-gaze-disabled"; else touch "$d/dsns.lock-gaze-disabled"; fi; rm -f "$d/dsns.lock-gaze-dismissed"', "gaze-toggle", root.gazeToggleRequest]
    onExited: {
      if (root.gazeToggleRequest === "disable") {
        root.gazeEnabled = false
        root.hideGazeSetupCard()
        // A mid-scan disable must not let the result still unlock the session.
        stopGaze()
        gazeAttempts = 0
      } else {
        root.gazeEnabled = true
        root.refreshGazeStatus()
      }
    }
  }

  Timer {
    id: gazeRescanTimer
    interval: 4000
    repeat: true
    running: root.gazeSetupCardVisible
    onTriggered: root.refreshGazeStatus()
  }

  FileView {
    path: root.gazeDismissedFile
    watchChanges: true
    printErrors: false
    onLoaded: root.gazeSetupIgnored = true
    onLoadFailed: root.gazeSetupIgnored = false
    onFileChanged: reload()
  }

  FileView {
    path: root.gazeDisabledFile
    watchChanges: true
    printErrors: false
    onLoaded: root.gazeEnabled = false
    onLoadFailed: root.gazeEnabled = true
    onFileChanged: reload()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (next !== root.backgroundPath) {
          root.backgroundPath = next
          root.backgroundVersion += 1
        }
      }
    }
  }

  Process {
    id: fingerprintCheckProc
    command: ["bash", "-c", "if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]] && command -v fprintd-list >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -qi finger; then echo yes; else echo no; fi"]
    stdout: StdioCollector { id: fingerprintCheckStdout; waitForEnd: true }
    onExited: {
      root.fingerprintConfigured = String(fingerprintCheckStdout.text || "").trim() === "yes"
      if (root.lockRequested && root.fingerprintConfigured) root.startFingerprint()
      else if (!root.fingerprintConfigured && fingerprintPam.active) fingerprintPam.abort()
    }
  }

  Process {
    id: strandedLockCheckProc
    command: ["bash", "-c", "omarchy-hyprland-session-locked"]
    onExited: function(exitCode) {
      // No output to read the lock off yet.
      if (exitCode === 2) return

      root.strandedLockResolved = true

      // A lock taken while this was in flight is this shell's own.
      root.strandedLock = exitCode === 0 && !root.locked && !root.lockRequested
      root.recoverStrandedLock()
    }
  }

  Process {
    id: wakeProcess
    command: ["bash", "-c", "omarchy-system-wake"]
  }

  Timer {
    id: sessionLockStabilizeTimer
    interval: 500
    repeat: false
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: pendingSessionLockTimer
    interval: 100
    repeat: true
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: strandedLockRetryTimer
    interval: 500
    repeat: true
    // Covers the compositor settling; screens coming back re-arm it.
    readonly property int budget: 20
    property int remaining: 20
    running: !root.strandedLockResolved && remaining > 0

    function rearm() {
      if (!root.strandedLockResolved) remaining = budget
    }

    onTriggered: {
      remaining -= 1
      root.checkStrandedLock()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.requestSessionLock()

      // A monitor still coming up has no workspace, so cannot answer yet.
      strandedLockRetryTimer.rearm()
      root.checkStrandedLock()
    }
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-password"
    watchChanges: true
    printErrors: false
    onLoaded: root.passwordPamConfigured = true
    onLoadFailed: root.passwordPamConfigured = false
    onFileChanged: reload()
  }

  // No lock before PAM is known good. An answer from before then may be stale --
  // the failsafe can be cleared from a TTY -- so re-ask rather than act on it.
  onPasswordPamConfiguredChanged: {
    if (!passwordPamConfigured) return

    strandedLock = false
    strandedLockResolved = false
    strandedLockRetryTimer.rearm()
    checkStrandedLock()
  }

  Component.onCompleted: {
    refreshBackground()
    refreshFingerprintStatus()
    refreshGazeStatus()
    checkStrandedLock()
  }

  IpcHandler {
    target: "lock"

    function lock(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      if (!root.locked && !root.beginLock()) return "failed"
      return "ok"
    }

    function isLocked(): string {
      return root.locked ? "true" : "false"
    }

    function status(): string {
      return JSON.stringify({
        locked: root.locked,
        requested: root.lockRequested,
        pending: root.pendingSessionLock,
        sessionLocked: sessionLock.locked,
        secure: sessionLock.secure,
        realScreens: root.realScreenCount(),
        passwordPam: root.passwordPamConfigured,
        fingerprint: root.fingerprintConfigured,
        gaze: root.gazeConfigured,
        gazeState: root.gazeState,
        gazeScanning: root.gazeAuthenticating,
        gazeAttempts: root.gazeAttempts,
        authenticating: root.authenticating,
        lastEvent: root.lastEvent,
        lastEventAt: root.lastEventAt
      })
    }

    function preview(): string {
      root.refreshBackground()
      root.refreshFingerprintStatus()
      root.previewVisible = true
      return "ok"
    }

    function hidePreview(): string {
      root.previewVisible = false
      return "ok"
    }

    function gazeStatus(): string {
      return JSON.stringify({
        state: root.gazeState,
        configured: root.gazeConfigured,
        enabled: root.gazeEnabled,
        scanning: root.gazeAuthenticating
      })
    }

    function gazeSetup(): string {
      root.showGazeSetupCard()
      return "ok"
    }

    function gazeSetupRun(): string {
      root.launchGazeSetup()
      return "ok"
    }

    function gazeSetupHide(): string {
      root.hideGazeSetupCard()
      return "ok"
    }

    function gazeEnable(): string {
      root.toggleGaze(true)
      return "ok"
    }

    function gazeDisable(): string {
      root.toggleGaze(false)
      return "ok"
    }
  }

  // First-run guide: appears (never over the lock) whenever gaze is missing,
  // daemon down or face-less, until setup succeeds or it is dismissed.
  PanelWindow {
    id: gazeSetupWindow
    visible: root.gazeSetupCardVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-gaze-setup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    MouseArea {
      anchors.fill: parent
      // Clicks anywhere but the card count as "not now" (the card's buttons
      // take their clicks first), so the guide never traps the pointer.
      onClicked: root.hideGazeSetupCard()
    }

    GazeSetupCard {
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      anchors.margins: 44

      gazeState: root.gazeState
      setupRunning: root.gazeSetupRunning
      onSetupRequested: root.launchGazeSetup()
      onDismissRequested: root.hideGazeSetupCard()
      onDismissForeverRequested: root.dismissGazeSetupCard()
    }
  }
}
