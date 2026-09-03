import QtQuick
import qs.Commons

// First-run guide for gaze face unlock. Shown by Service.qml whenever its
// checks say gaze is missing, its daemon is stopped, or no face is enrolled.
// The only interactive job it has is launching gaze-setup.sh in a terminal:
// package builds and `gaze add-face` are interactive, so they must not run
// quietly behind the shell.
Rectangle {
  id: card

  // One of: missing, daemon-stopped, no-face, ready, unknown
  property string gazeState: "unknown"
  property bool setupRunning: false

  signal setupRequested()
  signal dismissRequested()
  signal dismissForeverRequested()

  readonly property bool actionable:
    gazeState === "missing" || gazeState === "daemon-stopped" || gazeState === "no-face"

  readonly property string statusText: {
    if (gazeState === "missing") return "Gaze is not installed. Install it once and enroll your face, and the lock screen will recognize you like Windows Hello - no password typing."
    if (gazeState === "daemon-stopped") return "Gaze is installed, but its daemon (gazed) is not running. Setup will enable and start it, then enroll your face."
    if (gazeState === "no-face") return "Gaze is installed, but you have no face enrolled yet. Setup opens the camera in a terminal and walks you through it."
    if (gazeState === "unknown") return "Checking whether Gaze is installed..."
    return "Face unlock is ready. The lock screen scans your face when it appears and falls back to your password."
  }
  readonly property string actionText: {
    if (gazeState === "missing") return "Install Gaze"
    if (gazeState === "daemon-stopped") return "Fix and enroll"
    if (gazeState === "no-face") return "Add my face"
    if (gazeState === "unknown") return "..."
    return "Run setup again"
  }

  implicitWidth: 460
  implicitHeight: contentColumn.implicitHeight + 48

  radius: Style.cornerRadius
  color: Color.lock.background
  border.width: 1
  border.color: Color.lock.borderActive

  MouseArea {
    // Absorb clicks on the card body so the window-level "not now" dismiss
    // only fires on clicks outside the card.
    anchors.fill: parent
  }

  Column {
    id: contentColumn

    x: 24
    y: 24
    width: parent.width - 48
    spacing: 14

    Row {
      spacing: 10

      Text {
        text: "󰟿"
        color: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.heading * 1.35)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: "Face unlock"
        color: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.heading * 1.35)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Text {
      width: parent.width
      text: card.setupRunning
        ? "Running gaze-setup in a terminal - follow it there. This card closes when everything checks out."
        : card.statusText
      color: card.setupRunning ? Color.lock.text : Color.lock.placeholder
      wrapMode: Text.Wrap
      font.family: Style.font.family
      font.pixelSize: Math.round(Style.font.heading * 0.95)
      lineHeight: 1.4
      lineHeightMode: Text.ProportionalHeight
    }

    Row {
      spacing: 10

      Rectangle {
        id: primaryButton

        readonly property string label: card.actionText
        readonly property bool clickable: card.actionable && !card.setupRunning

        implicitWidth: primaryButtonMetrics.implicitWidth + 32
        implicitHeight: primaryButtonMetrics.implicitHeight + 18
        radius: Style.cornerRadius
        color: clickable
          ? (primaryButtonArea.containsMouse ? Color.lock.text : Color.lock.borderActive)
          : Color.lock.placeholder
        opacity: clickable ? 1 : 0.45

        TextMetrics {
          id: primaryButtonMetrics
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.heading * 1.0)
          text: primaryButton.label
        }

        Text {
          anchors.centerIn: parent
          text: primaryButton.label
          color: Color.lock.background
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.heading * 1.0)
        }

        MouseArea {
          id: primaryButtonArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          enabled: primaryButton.clickable
          onClicked: card.setupRequested()
        }
      }

      Rectangle {
        id: notNowButton

        readonly property string label: "Not now"

        implicitWidth: notNowButtonMetrics.implicitWidth + 28
        implicitHeight: notNowButtonMetrics.implicitHeight + 18
        radius: Style.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: notNowArea.containsMouse ? Color.lock.text : Color.lock.placeholder

        TextMetrics {
          id: notNowButtonMetrics
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.heading * 1.0)
          text: notNowButton.label
        }

        Text {
          anchors.centerIn: parent
          text: notNowButton.label
          color: Color.lock.text
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.heading * 1.0)
        }

        MouseArea {
          id: notNowArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: card.dismissRequested()
        }
      }
    }

    Text {
      text: "Don't ask again (bring the card back with: omarchy-shell ipc call lock gazeSetup)"
      color: Color.lock.placeholder
      opacity: neverAskArea.containsMouse ? 1 : 0.7
      wrapMode: Text.Wrap
      width: parent.width
      font.family: Style.font.family
      font.pixelSize: Math.round(Style.font.heading * 0.75)

      MouseArea {
        id: neverAskArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.dismissForeverRequested()
      }
    }
  }
}
