import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "ImagePickerModel.js" as ImagePickerModel

PanelWindow {
  id: root

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  visible: root.opened
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "image-picker"
  WlrLayershell.keyboardFocus: root.imagesLoaded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (homeDir + "/.config")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (homeDir + "/.local/state")
  readonly property string imagePickerHome: Quickshell.env("IMAGE_PICKER_HOME") || (configHome + "/quickshell/image-picker")
  readonly property string directoriesConfigPath: configHome + "/image-picker/directories"
  readonly property string wallpaperPathConfig: stateHome + "/caelestia/wallpaper/path.txt"
  property string imageDirs: Quickshell.env("IMAGE_PICKER_DIRS") || (homeDir + "/Pictures/Wallpapers\n" + homeDir + "/wallpapers")
  property string currentWallpaperPath: ""
  property string loadedImageDirs: ""
  property int selectedIndex: 0
  property bool imagesLoaded: false
  property bool opened: false
  property bool showLabels: false
  property bool filterable: false
  property bool layoutSettled: false
  property bool neighborImagesEnabled: false
  property int renderedFrames: 0
  property string filterText: ""
  property bool startupHandled: false
  property bool scanPendingOpen: false
  property string applyError: ""
  property color dimColor: "#101010"
  property color foreground: "#ffffff"
  property color selectedBorder: "#ffffff"
  property color unselectedBorder: "#b0ffffff"
  property int expandedWidth: 768
  property int expandedHeight: 475
  property int sliceWidth: 108
  property int sliceHeight: 432
  property int sliceSpacing: -30
  property int skewOffset: 28
  property int bottomChromeHeight: showLabels ? (filterable ? 104 : 74) : (filterable ? 60 : 30)
  // Render only what fits on this display, plus one prefetch slice per side.
  readonly property int previewRadius: Math.max(1, Math.min(16, Math.ceil((root.width - expandedWidth) / (2 * (sliceWidth + sliceSpacing))) + 1))
  onPreviewRadiusChanged: updateVisibleItems()

  onOpenedChanged: if (!opened) { layoutSettled = false; renderedFrames = 0 }

  function focusPicker() {
    if (root.opened && root.imagesLoaded && root.layoutSettled)
      carousel.forceActiveFocus()
  }

  function revealWhenSettled() {
    Qt.callLater(function() {
      root.maybeReveal()
    })
  }

  // The card renders at opacity 0 until every visible preview has decoded
  // and its masked layers have presented, so the picker lands in one
  // complete frame instead of flashing its images in as each asynchronous
  // decode and layer upload finishes.
  function allPreviewsSettled() {
    if (!opened || !imagesLoaded || layoutSettled || imageArray.length === 0 || imageCards.count === 0) return false
    for (var i = 0; i < imageCards.count; i++) {
      var item = imageCards.itemAt(i)
      if (!item || !item.previewSettled) return false
    }
    return true
  }

  function settleReveal() {
    if (!opened || !imagesLoaded || layoutSettled || imageArray.length === 0) return
    layoutSettled = true
    focusPicker()
  }

  function maybeReveal() {
    if (!allPreviewsSettled() || renderedFrames < 2) return
    // Confirm on the next tick: delegates inserted later in the same window
    // sync must not pop in after an early all-ready reading.
    Qt.callLater(function() {
      if (root.allPreviewsSettled() && root.renderedFrames >= 2) root.settleReveal()
    })
  }

  function currentPath() {
    if (imageArray.length === 0 || !itemMatches(selectedIndex)) return ""
    return imageArray[selectedIndex].filePath
  }

  function nameForPath(path) {
    return ImagePickerModel.nameForPath(path)
  }

  function labelForPath(path) {
    return ImagePickerModel.labelForPath(path)
  }

  function currentLabel() {
    var path = currentPath()
    if (!path) return filterText ? "No matches" : ""

    return labelForPath(path)
  }

  function itemMatches(index) {
    return ImagePickerModel.itemMatches(imageArray, index, filterText)
  }

  function currentWallpaperIndex() {
    for (var i = 0; i < imageArray.length; i++) {
      if (imageArray[i].filePath === currentWallpaperPath) return i
    }
    return -1
  }

  function selectCurrentWallpaper() {
    var index = currentWallpaperIndex()
    if (index >= 0 && itemMatches(index)) selectedIndex = index
  }

  function select(index) {
    if (imageArray.length === 0) return
    if (index < 0) index = 0
    else if (index >= imageArray.length) index = imageArray.length - 1
    if (!itemMatches(index)) return
    if (index === selectedIndex) return

    selectedIndex = index
  }

  function selectAdjacent(direction) {
    var count = imageArray.length
    if (count === 0) return

    var index = selectedIndex
    for (var i = 0; i < count; i++) {
      index = (index + direction + count) % count
      if (itemMatches(index)) {
        select(index)
        return
      }
    }
  }

  function updateFilter(nextFilterText) {
    filterText = nextFilterText

    if (!itemMatches(selectedIndex)) {
      var first = ImagePickerModel.nextSelectedIndexForFilter(imageArray, selectedIndex, filterText)
      if (first >= 0) select(first)
    }
  }

  function applySelected() {
    var path = currentPath()
    if (!path) {
      cancel()
      return
    }

    applyError = ""
    applyProc.command = [imagePickerHome + "/apply-wallpaper.sh", path]
    root.opened = false
    applyProc.running = true
  }

  function cancel() {
    scanPendingOpen = false
    root.opened = false
  }

  function fileUrl(path) {
    return "file:///" + String(path).split("/").filter(function(part) { return part.length > 0 }).map(encodeURIComponent).join("/")
  }

  function alpha(color, opacity) {
    return Qt.rgba(color.r, color.g, color.b, opacity)
  }

  function editsFilter(event) {
    return event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete
  }

  function editedFilter(event) {
    if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete)
      return filterText.slice(0, -1)
    return filterText
  }

  function loadRows(rows, reveal) {
    var newImages = ImagePickerModel.loadRows(rows)

    var currentIndex = ImagePickerModel.indexForSelectedImage(newImages, root.currentWallpaperPath)
    root.selectedIndex = ImagePickerModel.nextSelectedIndexForFilter(newImages, currentIndex, root.filterText)
    root.neighborImagesEnabled = false
    root.imageArray = newImages
    root.imagesLoaded = true
    Qt.callLater(root.enableNeighborsWhenReady)

    if (reveal !== false) {
      root.opened = true
      root.revealWhenSettled()
      if (newImages.length === 0)
        root.applyError = "No images found. Check ~/.config/image-picker/directories."
    }
    scanPendingOpen = false
  }

  function openSelector() {
    showLabels = true
    filterable = true
    filterText = ""
    applyError = ""
    layoutSettled = false
    imageArray = []
    selectedIndex = 0
    imagesLoaded = false
    opened = false
    scanPendingOpen = true
    startImageScan(imageDirs)
  }

  function toggle() {
    if (opened || (loadImagesProc.running && scanPendingOpen)) {
      cancel()
    } else if (imagesLoaded && imageArray.length > 0 && imageDirs === loadedImageDirs) {
      filterText = ""
      applyError = ""
      selectedIndex = ImagePickerModel.indexForSelectedImage(imageArray, currentWallpaperPath)
      layoutSettled = false
      opened = true
      revealWhenSettled()
    } else {
      openSelector()
    }
  }

  function setConfiguredDirectories(directories) {
    if (!Quickshell.env("IMAGE_PICKER_DIRS") && String(directories || "").trim())
      imageDirs = String(directories).trim()
    if (!startupHandled) {
      startupHandled = true
      openSelector()
    }
  }

  function startImageScan(dirs) {
    if (loadImagesProc.running) return
    loadedImageDirs = dirs
    loadImagesProc.command = [imagePickerHome + "/list.sh", dirs]
    loadImagesProc.running = true
  }

  property var imageArray: []
  readonly property var matchingImageIndices: ImagePickerModel.matchingIndices(imageArray, filterText)
  onMatchingImageIndicesChanged: updateVisibleItems()
  onSelectedIndexChanged: {
    updateVisibleItems()
  }
  onCurrentWallpaperPathChanged: {
    if (imagesLoaded && !layoutSettled) selectCurrentWallpaper()
  }

  function updateVisibleItems() {
    ImagePickerModel.syncWindow(visibleImages, ImagePickerModel.visibleWindow(matchingImageIndices, selectedIndex, previewRadius))
  }

  function enableNeighborsWhenReady() {
    for (var i = 0; i < imageCards.count; i++) {
      var item = imageCards.itemAt(i)
      if (item && item.selected && item.previewReady) neighborImagesEnabled = true
    }
  }

  ListModel { id: visibleImages }

  Process {
    id: loadImagesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadRows(String(text || ""), root.scanPendingOpen)
    }
    stderr: StdioCollector {
      onStreamFinished: if (String(text || "").trim()) console.warn("Image scan failed:", String(text).trim())
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.imageArray.length === 0) {
        root.applyError = "Could not scan the configured wallpaper directories (exit code " + exitCode + ")."
        root.imagesLoaded = true
        root.opened = root.scanPendingOpen
        root.scanPendingOpen = false
      }
    }
  }

  IpcHandler {
    target: "image-picker"
    function toggle() { root.toggle() }
  }

  Process {
    id: applyProc
    stderr: StdioCollector {
      onStreamFinished: root.applyError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.opened = false
      } else {
        if (!root.applyError) root.applyError = "Wallpaper backend failed (exit code " + exitCode + ")."
        root.opened = true
        root.layoutSettled = true
        Qt.callLater(root.focusPicker)
      }
    }
  }

  FileView {
    id: directoriesConfigWatcher
    path: root.directoriesConfigPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoadFailed: function(error) {
      console.warn("Could not read wallpaper directory configuration:", root.directoriesConfigPath, error)
      root.setConfiguredDirectories("")
    }
    onLoaded: {
      if (!Quickshell.env("IMAGE_PICKER_DIRS") && String(text() || "").trim())
        root.imageDirs = String(text()).trim()
      if (!root.startupHandled) {
        root.startupHandled = true
        root.openSelector()
      }
    }
    Component.onCompleted: reload()
  }

  FileView {
    path: root.wallpaperPathConfig
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.currentWallpaperPath = String(text() || "").trim()
    onLoadFailed: root.currentWallpaperPath = ""
    Component.onCompleted: reload()
  }

  Component.onCompleted: {
    if (Quickshell.env("IMAGE_PICKER_DIRS")) root.setConfiguredDirectories("")
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.opened && root.imagesLoaded
    onClicked: root.cancel()
  }

  // Count presented frames while the card pre-renders below; two frames
  // prove its masked layers uploaded on this fresh surface.
  FrameAnimation {
    running: root.opened && !root.layoutSettled && root.renderedFrames < 2
    onTriggered: {
      root.renderedFrames += 1
      root.maybeReveal()
    }
  }

  // A preview stuck decoding (slow disk, huge original) must not hold an
  // invisible picker with the keyboard grabbed: reveal anyway shortly.
  Timer {
    interval: 400
    running: root.opened && root.imagesLoaded && !root.layoutSettled && root.imageArray.length > 0
    onTriggered: root.settleReveal()
  }

  Text {
    id: emptyState
    anchors.centerIn: parent
    visible: root.opened && root.imageArray.length === 0 && !!root.applyError
    focus: visible
    text: root.applyError
    color: root.foreground
    style: Text.Outline
    styleColor: root.alpha(root.dimColor, 0.7)
    font.pixelSize: 18
    horizontalAlignment: Text.AlignHCenter
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        root.cancel()
        event.accepted = true
      }
    }
  }

  Item {
      id: card
      visible: root.opened && root.imagesLoaded && root.imageArray.length > 0
      opacity: root.layoutSettled ? 1 : 0
      width: Math.min(parent.width - 80, root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing) + 40)
      height: root.expandedHeight + 30 + root.bottomChromeHeight
      anchors.centerIn: parent

        MouseArea { anchors.fill: parent; enabled: root.layoutSettled; onClicked: {} }

        Item {
          id: carousel
          anchors.top: parent.top
          anchors.topMargin: 30
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.bottomChromeHeight
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing)
          clip: false
          focus: true

          readonly property real itemStep: root.sliceWidth + root.sliceSpacing
          readonly property real previewX: (width - root.expandedWidth) / 2

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            // Nothing is visible before the reveal: only let the user back
            // out, never filter into a dead end or apply an unseen pick.
            if (!root.layoutSettled) {
              if (event.key === Qt.Key_Escape) {
                root.cancel()
                event.accepted = true
              }
              return
            }
            if (event.key === Qt.Key_Escape) {
              if (root.filterText) {
                root.updateFilter("")
              } else {
                root.cancel()
              }
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.applySelected()
              event.accepted = true
            } else if (root.filterable && root.editsFilter(event)) {
              root.updateFilter(root.editedFilter(event))
              event.accepted = true
            } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab) {
              root.selectAdjacent(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
              root.selectAdjacent(1)
              event.accepted = true
            } else if (root.filterable && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
              root.updateFilter(root.filterText + event.text)
              event.accepted = true
            }
          }

          Component.onCompleted: forceActiveFocus()

          Repeater {
            id: imageCards
            model: visibleImages
            onCountChanged: root.maybeReveal()

            delegate: Item {
              id: item
              required property int imageIndex
              required property int relativeIndex

              readonly property var imageData: root.imageArray[imageIndex]
              readonly property string filePath: imageData ? imageData.filePath : ""
              readonly property string fileName: imageData ? imageData.fileName : ""
              readonly property string thumbnailPath: imageData ? imageData.thumbnailPath : ""

              readonly property bool selected: imageIndex === root.selectedIndex
              readonly property bool previewReady: image.status === Image.Ready || image.status === Image.Error
              readonly property bool previewSettled: !thumbnailPath || previewReady
              onPreviewSettledChanged: if (previewSettled) root.maybeReveal()
              onSelectedChanged: if (selected && previewReady) root.neighborImagesEnabled = true

              x: selected ? carousel.previewX : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep : carousel.previewX + root.expandedWidth + root.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
              width: selected ? root.expandedWidth : root.sliceWidth
              height: selected ? root.expandedHeight : root.sliceHeight
              y: selected ? 0 : (root.expandedHeight - root.sliceHeight) / 2
              z: selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40)

              readonly property real skAbs: Math.abs(root.skewOffset)
              readonly property real topLeft: root.skewOffset >= 0 ? skAbs : 0
              readonly property real topRight: root.skewOffset >= 0 ? width : width - skAbs
              readonly property real bottomRight: root.skewOffset >= 0 ? width - skAbs : width
              readonly property real bottomLeft: root.skewOffset >= 0 ? 0 : skAbs

              Item {
                id: maskShape
                anchors.fill: parent
                visible: false
                layer.enabled: true

                Shape {
                  anchors.fill: parent
                  antialiasing: true
                  preferredRendererType: Shape.CurveRenderer
                  ShapePath {
                    fillColor: "white"
                    strokeColor: "transparent"
                    startX: item.topLeft; startY: 0
                    PathLine { x: item.topRight; y: 0 }
                    PathLine { x: item.bottomRight; y: item.height }
                    PathLine { x: item.bottomLeft; y: item.height }
                    PathLine { x: item.topLeft; y: 0 }
                  }
                }
              }

              Item {
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect {
                  maskEnabled: true
                  maskSource: maskShape
                  maskThresholdMin: 0.3
                  maskSpreadAtMin: 0.3
                }

                Rectangle { anchors.fill: parent; color: root.dimColor }

                Image {
                  id: image
                  anchors.fill: parent
                  // Decode at the expanded card's physical size, off the GUI
                  // thread. Keep that size during navigation to avoid reloads.
                  // Departing cards release their images instead of retaining
                  // every preview visited in a large collection.
                  // Queue the selected preview first; neighbors must not delay
                  // the image the user opened the picker to see.
                  source: (item.selected || root.neighborImagesEnabled) && item.thumbnailPath ? root.fileUrl(item.thumbnailPath) : ""
                  sourceSize.width: Math.ceil(root.expandedWidth * Screen.devicePixelRatio)
                  sourceSize.height: Math.ceil(root.expandedHeight * Screen.devicePixelRatio)
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: false
                  smooth: true
                  opacity: status === Image.Ready ? 1 : 0
                  onStatusChanged: if (item.selected && (status === Image.Ready || status === Image.Error)) root.neighborImagesEnabled = true
                }

                Rectangle {
                  anchors.fill: parent
                  color: root.alpha(root.dimColor, item.selected ? 0 : 0.42)
                }
              }

              Shape {
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                  fillColor: "transparent"
                  strokeColor: item.selected ? root.selectedBorder : root.unselectedBorder
                  strokeWidth: item.selected ? 3 : 1
                  startX: item.topLeft; startY: 0
                  PathLine { x: item.topRight; y: 0 }
                  PathLine { x: item.bottomRight; y: item.height }
                  PathLine { x: item.bottomLeft; y: item.height }
                  PathLine { x: item.topLeft; y: 0 }
                }
              }

              MouseArea {
                anchors.fill: parent
                enabled: root.layoutSettled
                cursorShape: Qt.PointingHandCursor
                onClicked: item.selected ? root.applySelected() : root.select(item.imageIndex)
              }
            }
          }

        }

        Text {
          id: selectedLabel
          textFormat: Text.PlainText
          visible: root.showLabels
          anchors.top: carousel.bottom
          anchors.topMargin: 16
          anchors.horizontalCenter: carousel.horizontalCenter
          width: root.expandedWidth
          text: root.currentLabel()
          color: root.foreground
          style: Text.Outline
          styleColor: root.alpha(root.dimColor, 0.7)
          font.pixelSize: 24
          font.weight: Font.DemiBold
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }

        Text {
          id: filterLabel
          textFormat: Text.PlainText
          visible: root.filterable && root.filterText
          anchors.top: selectedLabel.bottom
          anchors.topMargin: 8
          anchors.horizontalCenter: carousel.horizontalCenter
          width: root.expandedWidth
          text: root.filterText
          color: root.foreground
          opacity: 0.85
          style: Text.Outline
          styleColor: root.alpha(root.dimColor, 0.7)
          font.pixelSize: 18
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }

        Text {
          visible: !!root.applyError && root.imageArray.length > 0
          anchors.top: filterLabel.bottom
          anchors.topMargin: 6
          anchors.horizontalCenter: carousel.horizontalCenter
          width: root.expandedWidth
          text: root.applyError
          color: root.foreground
          style: Text.Outline
          styleColor: root.alpha(root.dimColor, 0.7)
          font.pixelSize: 14
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
  }
}
