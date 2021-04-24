import QtQuick 2.9
import QtLocation 5.9
import QtPositioning 5.9
import "cheap-ruler.js" as CheapRuler

Item {
  id: app
  width: 640
  height: 640

  property bool initialized: false
  property variant gpsLocation
  property variant carPosition: QtPositioning.coordinate()
  property variant routeStart: QtPositioning.coordinate()
  property variant routeDestination: QtPositioning.coordinate()
  property variant lastRecalculationPosition: QtPositioning.coordinate()
  property real recalculationThreshold: 50 // meters
  property real carBearing: 0
  property bool nightMode: mapPlugin.name != "osm"
  property bool satelliteMode: false
  property bool mapFollowsCar: true
  property bool lockedToNorth: false
  property variant ruler: CheapRuler.cheapRuler(raleigh.coordinate.latitude, "meters")

  Location {
    id: spartanburg
    coordinate: QtPositioning.coordinate(34.9495979, -81.9321125)
  }

  Location {
    id: raleigh
    coordinate: QtPositioning.coordinate(35.7796662, -78.6386822)
  }

  Location {
    id: dostaquitos
    coordinate: QtPositioning.coordinate(35.8549825,-78.7021428)
  }

  function coordinateToPoint(coordinate) {
    return [coordinate.longitude, coordinate.latitude]
  }

  // animation durations for continuously updated values shouldn't be much greater than updateInterval
  // ...otherwise, animations are always trying to catch up as their target values change
  property real updateInterval: 100

  Plugin {
    id: mapPlugin

    name: "osm"
    PluginParameter { name: "osm.mapping.cache.directory"; value: "/tmp/tile_cache" }
    PluginParameter { name: "osm.mapping.host"; value: "https://c.tile.openstreetmap.org" }
    PluginParameter { name: "osm.mapping.highdpi_tiles"; value: "true" }

    // TODO not availble on NEOS yet
    // name: "mapboxgl"
    // PluginParameter { name: "mapboxgl.access_token"; value: mapboxAccessToken }
    // PluginParameter { name: "mapboxgl.mapping.use_fbo"; value: "false" }
    // PluginParameter { name: "mapboxgl.mapping.cache.directory"; value: "/tmp/tile_cache" }
    // // necessary to draw route paths underneath road labels 
    // PluginParameter { name: "mapboxgl.mapping.items.insert_before"; value: "road-label-small" }
  }

  Plugin {
    id: routePlugin
    name: "mapbox"
    // routing requires valid access_token
    PluginParameter { name: "mapbox.access_token"; value: mapboxAccessToken }
    PluginParameter { name: "mapbox.useragent"; value: "openpilot" }
    PluginParameter { name: "mapbox.routing.traffic_side"; value: isRHD ? "right" : "left" }
  }

  // TODO figure out coordinating things starting up
  function initializeIfReady() {
    if (gpsLocation.accuracy < 1000) {
      initialized = true
    }
  }

  onGpsLocationChanged: {
    // console.log(JSON.stringify(gpsLocation))
    if (gpsLocation.accuracy < 1000) {
      carPosition = QtPositioning.coordinate(gpsLocation.latitude, gpsLocation.longitude, gpsLocation.altitude)
    }

    if (gpsLocation.bearingAccuracyDeg < 50) {
      carBearing = gpsLocation.bearingDeg
    }

    initializeIfReady()
    if (initialized) {
      updateRouteProgress()
    }
  }

  onCarPositionChanged: {
    if (mapFollowsCar) {
      map.center = carPosition
    }
  }

  onCarBearingChanged: {
    if (mapFollowsCar && !lockedToNorth) {
      map.bearing = carBearing
    }
  }

  Map {
    id: map
    plugin: mapPlugin

    // TODO is there a better way to make map text bigger?
    width: parent.width / scale
    height: parent.height / scale
    scale: 2.5
    x: width * (scale - 1)
    y: height * (scale - 1)
    transformOrigin: Item.BottomRight

    gesture.enabled: true
    center: QtPositioning.coordinate()
    bearing: 0
    zoomLevel: 16
    copyrightsVisible: false // TODO re-enable

    // keep in sync with car indicator
    // TODO commonize with car indicator
    Behavior on center {
      CoordinateAnimation {
        easing.type: Easing.Linear;
        duration: updateInterval;
      }
    }

    Behavior on bearing {
      RotationAnimation {
        direction: RotationAnimation.Shortest
        easing.type: Easing.InOutQuad
        duration: updateInterval
      }
    }

    // TODO combine with center animation
    Behavior on zoomLevel {
      SmoothedAnimation {
        velocity: 2;
      }
    }

    onSupportedMapTypesChanged: {
      function score(mapType) {
        // prioritize satelliteMode over nightMode
        return (mapType.style === (satelliteMode ? MapType.HybridMap : MapType.CarNavigationMap)) << 1
            + (mapType.night === nightMode) << 0
      }
      activeMapType = Array.from(supportedMapTypes).sort((a, b) => score(b)-score(a))[0]
    }

    onBearingChanged: {
    }

    gesture.onPanStarted: {
      mapFollowsCar = false
    }

    gesture.onPinchStarted: {
      mapFollowsCar = false
    }

    MapItemView {
      id: route
      model: routeModel

      delegate: MapRoute {
        route: routeData
        line.color: "#ec0f73"
        line.width: map.zoomLevel - 5
        opacity: (index == 0) ? 0.8 : 0.3

        onRouteChanged: {
          // console.log("route changed:", JSON.stringify(routeData.segments, null, 2))
        }
      }
    }

    MapQuickItem {
      id: car
      visible: carPosition.isValid //&& map.zoomLevel > 10
      anchorPoint.x: icon.width / 2
      anchorPoint.y: icon.height / 2

      opacity: 0.8
      coordinate: carPosition
      rotation: carBearing - map.bearing

      Behavior on coordinate {
        CoordinateAnimation {
          easing.type: Easing.Linear;
          duration: updateInterval;
        }
      }

      sourceItem: Image {
        id: icon
        source: `arrow-${nightMode ? "night" : "day"}.svg`
        width: 60 / map.scale
        height: 60 / map.scale
      }
    }
  }

  Column {
    id: buttons
    anchors.left: parent.left
    anchors.bottom: parent.bottom

    MouseArea {
      id: compass
      visible: mapFollowsCar || !lockedToNorth
      width: 125
      height: 113
      onClicked: {
        updateRouteProgress()
        lockedToNorth = !lockedToNorth
        map.bearing = lockedToNorth || !mapFollowsCar ? 0 : carBearing
      }
      // Rectangle { anchors.fill: parent; color: 'transparent'; border.color: 'red'; border.width: 1; } // DEBUG
      Image {
        source: "compass.png"
        rotation: map.bearing
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 5
        width: 75
        height: 75

        scale: compass.pressed ? 0.85 : 1.0
        Behavior on scale { NumberAnimation { duration: 100 } }
      }
    }

    MouseArea {
      id: location
      width: 125
      height: 113
      onClicked: {
        if (carPosition.isValid) {
          mapFollowsCar = !mapFollowsCar
          if (mapFollowsCar) {
            lockedToNorth = false
            map.zoomLevel = 16
            map.center = carPosition
            map.bearing = carBearing
          }
        }
      }
      // Rectangle { anchors.fill: parent; color: 'transparent'; border.color: 'yellow'; border.width: 1; } // DEBUG
      Image {
        source: mapFollowsCar && carPosition.isValid ? "location-active.png" : `location-${nightMode ? "night" : "day"}.png`
        opacity: mapFollowsCar && carPosition.isValid ? 0.5 : 1.0
        width: 63
        height: 63
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -5

        scale: location.pressed ? 0.85 : 1.0
        Behavior on scale { NumberAnimation { duration: 100 } }
      }
    }
  }

  Text {
    id: instructions
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.margins: 20
    width: parent.width

    font.family: "Inter"
    font.pixelSize: 40
    color: nightMode ? "white" : "black"
    wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignHCenter
  }

  function updateRoute(start, destination) {
    console.log("Updating route")
    if (start) routeStart = start
    if (destination) routeDestination = destination

    console.log("Start", routeStart)
    console.log("Destination", routeDestination)
    if (!routeStart.isValid || !routeDestination.isValid)
      return

    routeQuery.clearWaypoints();
    routeQuery.addWaypoint(routeStart);
    routeQuery.addWaypoint(routeDestination);
    routeQuery.travelModes = RouteQuery.CarTravel
    routeQuery.routeOptimizations = RouteQuery.FastestRoute
    routeQuery.setFeatureWeight(RouteQuery.TrafficFeature, RouteQuery.AvoidFeatureWeight)
    routeModel.update()
  }

  function clearRoute() {
      console.log("Clearing route")
      routeStart = QtPositioning.coordinate()
      routeDestination = QtPositioning.coordinate()
      routeQuery.clearWaypoints();
      routeModel.reset();
  }

  RouteModel {
    id: routeModel
    plugin: routePlugin
    query: RouteQuery {
      id: routeQuery
    }

    Component.onCompleted: {
      updateRoute(raleigh.coordinate, dostaquitos.coordinate)
    }

    onErrorChanged: {
      console.log("RouteModel error: " + errorString)
    }

    onStatusChanged: {
      console.log("RouteModel status: " + ["Null", "Ready", "Loading", "Error"][status])

      var dumpRoute = false
      if (!dumpRoute)
        return

      if (!routeModel.count)
        return

      var route = routeModel.get(0)
      if (!route)
        return

      for (var i in route){
        console.log("route", i, route[i])
      }
      for (var i in route.legs){
        for (var j in route.legs[i]){
          console.log("leg", i, j, route.legs[i][j])
        }
      }
      for (var i in route.segments){
        var segment = route.segments[i]
        for (var j in segment){
          console.log("segment", i, j, segment[j])
        }
        console.log("segment", i, "maneuver", JSON.stringify(segment.maneuver, null, 2))
      }
    }
  }

  function updateRouteProgress() {
    if (routeModel.status !== RouteModel.Ready || routeModel.count !== 1) {
      console.log("route not ready")
      if (routeModel.status !== RouteModel.Loading) {
        updateRoute()
      }
      return
    }

    var route = routeModel.get(0)
    if (route.segments.count === 0) {
      console.log("route contains no segments")
      return
    }

    // console.log("Updating route progress")

    // TODO optimization: don't look at every segment unless about to recalculate
    var match = { distance: Infinity }
    var current = coordinateToPoint(carPosition)
    for (var i = 0; i < route.segments.length; i++) {
      var segment = route.segments[i]
      var segmentPath = segment.path.map(coordinateToPoint)
      var bannerInstructions = segment.maneuver.extendedAttributes["mapbox.banner_instructions"]
      for (var j = 0; j < bannerInstructions.length; j++) {
        var subSegment = bannerInstructions[j]
        var nextSubSegment = bannerInstructions[j+1]
        var subSegmentDistance = segment.distance - subSegment["distance_along_geometry"]
        var nextSubSegmentDistance = nextSubSegment ? segment.distance - nextSubSegment["distance_along_geometry"] : Infinity
        var subSegmentPath = ruler.lineSliceAlong(subSegmentDistance, nextSubSegmentDistance, segmentPath)

        var best = ruler.pointOnLine(subSegmentPath, current)
        var point = best.point
        var distance = ruler.distance(current, point)
        if (distance < match.distance) {
          match = { segment, subSegment, distance, point }
        }

        // console.log(i, j, distance, subSegment.primary.text, subSegmentDistance, nextSubSegmentDistance, segmentPath.length, subSegmentPath.length)
      }
    }

    instructions.text = `\
${(match.distance).toFixed(1)}m off-course
${match.segment.maneuver.instructionText}
${match.segment.maneuver.extendedAttributes.type} ${match.segment.maneuver.extendedAttributes.modifier || ""}
${match.subSegment.primary.text}
${match.subSegment.secondary ? match.subSegment.secondary.text : undefined}
`
    // console.log(`distance: ${match.distance} | point: ${match.point}`)
    // console.log(JSON.stringify(match.segment.maneuver, null, 2))

    recalculateIfNeeded(match)
  }

  function recalculateIfNeeded(match) {
    // TODO more sophisticated checks
    // TODO going wrong way on correct road can be detected by slicing route path based on previous position match
    if (match.distance < recalculationThreshold) {
      return
    }

    // TODO split out threshold / change logic?
    // TODO use map matching to determine "Proceed to highlighted route"?
    // prevent continuous recalculation if car hasn't moved much since last recalculation
    if (lastRecalculationPosition.isValid && ruler.distance(coordinateToPoint(carPosition), coordinateToPoint(lastRecalculationPosition)) < recalculationThreshold) {
      return
    }

    console.log("RECALCULATING...")
    lastRecalculationPosition = carPosition
    updateRoute(carPosition)
  }
}