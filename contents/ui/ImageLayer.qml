/*
    One of main.qml's two crossfading picture layers: the picture, where it
    goes on this screen (`geom`, from main.qml's computeGeomFor()), an
    invisible probe that measures a spanned picture's shape, and, behind an
    individual picture that doesn't cover the screen, a backdrop.
*/
import QtQuick
import QtQuick.Effects

Image {
    id: layer

    // The picture this layer is for. `source` is set to it by main.qml
    // once the picture can be placed (see `placed`), so it is decoded once,
    // at its final size: decoding a spanned picture before its shape was
    // known decoded it a second time whenever the shape turned out to be
    // full-width.
    property string picture: ""
    // Whether the picture is spanned across all screens.
    property bool span: false
    // A spanned picture's natural size; (0, 0) until measured, (-1, -1) if
    // it couldn't be.
    property size probeSize: Qt.size(0, 0)
    // Whether `geom` can be final: a spanned picture is placed by its shape.
    readonly property bool placed: !span || probeSize.width !== 0
    property var geom: ({ w: 1, h: 1, x: 0, y: 0, stretch: false })
    // How an individual picture fills the screen, an Image.fillMode value:
    // PreserveAspectCrop, Stretch, PreserveAspectFit, Pad or Tile (the
    // SingleFillMode setting). A spanned picture is placed by `geom` alone.
    property int singleFillMode: Image.PreserveAspectCrop
    // What shows where a fitted or centered individual picture leaves the
    // screen free: a blurred copy of the picture, or the color alone.
    property bool blurBackdrop: true
    property color backdropColor: "black"
    readonly property bool hasBackdrop: !span && (singleFillMode === Image.PreserveAspectFit
                                                  || singleFillMode === Image.Pad)
    // The blurred copy is decoded (or can't be): main.qml fades the layer
    // in only then, so the backdrop doesn't appear after the picture.
    readonly property bool backdropReady: !(hasBackdrop && blurBackdrop)
        || backdrop.status === Image.Ready || backdrop.status === Image.Error
    // Whether this is the opaque layer; the other one fades out.
    property bool shown: false
    property int fadeDuration: 900

    // probeSize has just been measured (or failed to be).
    signal measured()

    x: geom.x
    y: geom.y
    width: geom.w
    height: geom.h
    // Stretch for the full-width branch of computeGeomFor() (see its
    // "stretch: true" comment) - PreserveAspectCrop there would silently
    // re-crop around this box's own center, which isn't this screen's own
    // display window whenever it's non-zero.
    fillMode: span ? (geom.stretch ? Image.Stretch : Image.PreserveAspectCrop) : singleFillMode
    asynchronous: true
    cache: false
    // With Pad and Tile this also keeps a picture larger than the screen
    // inside it: it is scaled down to fit, never up.
    sourceSize: Qt.size(width, height)
    opacity: shown ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: layer.fadeDuration; easing.type: Easing.InOutQuad }
    }

    // The backdrop. Children with a negative z are drawn under the picture.
    Rectangle {
        z: -2
        anchors.fill: parent
        visible: layer.hasBackdrop
        color: layer.backdropColor
    }
    // The picture again, covering the screen, at a quarter of the size: it
    // is only seen blurred. As a layer, so the effect gets it cropped (an
    // Image's own texture is the whole picture).
    Image {
        id: backdrop
        anchors.fill: parent
        visible: false
        asynchronous: true
        cache: false
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(Math.ceil(layer.width / 4), Math.ceil(layer.height / 4))
        source: layer.hasBackdrop && layer.blurBackdrop ? layer.source : ""
        layer.enabled: true
        layer.textureSize: Qt.size(Math.ceil(width / 4), Math.ceil(height / 4))
    }
    MultiEffect {
        z: -1
        anchors.fill: parent
        visible: layer.hasBackdrop && layer.blurBackdrop && backdrop.status === Image.Ready
        source: backdrop
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: 64
    }

    // Loads a spanned picture on its own, to learn its true shape (needed
    // to tell a full-width picture apart from a panorama; see
    // computeGeomFor()). Only the width/height ratio is ever used, so a
    // thumbnail is enough: decoding at native resolution cost up to
    // hundreds of MB of RGBA for a large panorama, once per screen, to read
    // two integers. libjpeg does scaled DCT decode, so for JPEG the full
    // bitmap never exists. Height 0 means "preserve aspect ratio".
    // sourceSize reads back as the *requested* size (1024x0), so the
    // natural size is read from implicitWidth/implicitHeight, which reflect
    // the loaded pixmap. Skipped when probeSize is already known (main.qml
    // caches it per picture).
    Image {
        visible: false
        asynchronous: true
        cache: false
        sourceSize: Qt.size(1024, 0)
        source: layer.span && layer.probeSize.width === 0 ? layer.picture : ""
        onStatusChanged: {
            if (status === Image.Ready) {
                layer.probeSize = Qt.size(implicitWidth, implicitHeight);
                layer.measured();
            } else if (status === Image.Error) {
                layer.probeSize = Qt.size(-1, -1);
                layer.measured();
            }
        }
    }
}
