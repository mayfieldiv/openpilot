#include <cassert>

#include <QDateTime>
#include <QGeoCoordinate>
#include <QQmlContext>
#include <QQmlProperty>
#include <QQuickWidget>
#include <QQuickView>
#include <QStackedLayout>
#include <QVariant>

#include "common/params.h"
#include "common/util.h"
#include "map.hpp"
// #include "mapManager.hpp"

#if defined(QCOM) || defined(QCOM2)
const std::string mapbox_access_token_path = "/persist/mapbox/access_token";
#else
const std::string mapbox_access_token_path = util::getenv_default("HOME", "/.comma/persist/mapbox/access_token", "/persist/mapbox/access_token");
#endif

QtMap::QtMap(QWidget *parent) : QFrame(parent) {
  QStackedLayout* layout = new QStackedLayout();

  auto file = QFile(mapbox_access_token_path.c_str());
  assert(file.open(QIODevice::ReadOnly));
  auto mapboxAccessToken = file.readAll();
  qDebug() << "Mapbox access token:" << mapboxAccessToken;

  // might have to use QQuickWidget for proper stacking?
  QQuickWidget *map = new QQuickWidget();
  map->rootContext()->setContextProperty("mapboxAccessToken", mapboxAccessToken);
  map->rootContext()->setContextProperty("isRHD", Params().getBool("IsRHD"));
  map->setSource(QUrl::fromLocalFile("qt/widgets/map.qml"));
  mapObject = map->rootObject();
  QSize size = map->size();

  // using QQuickView seems to make other ui drawing break (eg. video is all black) - maybe need resetOpenGLState()?
  // QQuickView *mapView = new QQuickView();
  // mapView->setSource(QUrl::fromLocalFile("qt/widgets/map.qml"));
  // QSize size = mapView->size();
  // map = QWidget::createWindowContainer(mapView, this);
  // mapObject = mapView->rootObject();

  // TODO focus stuff needed? https://www.qtdeveloperdays.com/sites/default/files/Adding%20QtQuick%20base%20windows%20to%20an%20existing%20QWidgets%20Application-dark.pdf
  // setFocusProxy(map); // focus container widget when top level widget is focused
  // setFocusPolicy(Qt::NoFocus); // work around QML activation issue

  QSizeF scaledSize = mapObject->size() * mapObject->scale();
  qDebug() << "size" << size;
  qDebug() << "scaledSize" << scaledSize;
  qDebug() << "mapObject->scale()" << mapObject->scale();
  map->setFixedSize(scaledSize.toSize());
  setFixedSize(scaledSize.toSize());

  layout->addWidget(map);
  setLayout(layout);

  // TODO retrieve from persistent storage
  QVariantMap previousGpsLocation;
  previousGpsLocation["latitude"] = 35.7796662;
  previousGpsLocation["longitude"] = -78.6386822;
  previousGpsLocation["altitude"] = 0.0;
  previousGpsLocation["speed"] = 0.0;
  previousGpsLocation["bearingDeg"] = 270.0;
  previousGpsLocation["accuracy"] = 0.0;
  previousGpsLocation["timestamp"] = 0;
  previousGpsLocation["verticalAccuracy"] = 0.0;
  previousGpsLocation["bearingAccuracyDeg"] = 0.0;
  previousGpsLocation["speedAccuracy"] = 0.0;

  QQmlProperty::write(mapObject, "gpsLocation", QVariant::fromValue(previousGpsLocation));

  // Start polling loop
  sm = new SubMaster({"gpsLocationExternal"});
  timer.start(100, this); // 10Hz

  // QObject::connect(map, SIGNAL(), parent, SLOT());
}

void QtMap::timerEvent(QTimerEvent *event) {
  if (!event)
    return;

  if (event->timerId() == timer.timerId()) {
    if (isVisible())
      updatePosition();
  }
  else
    QObject::timerEvent(event);
}

void QtMap::updatePosition() {
  sm->update(0);
  if (sm->updated("gpsLocationExternal")) {
    cereal::GpsLocationData::Reader gps = (*sm)["gpsLocationExternal"].getGpsLocationExternal();

    QVariantMap gpsLocation;
    gpsLocation["latitude"] = gps.getLatitude();
    gpsLocation["longitude"] = gps.getLongitude();
    gpsLocation["altitude"] = gps.getAltitude();
    gpsLocation["speed"] = gps.getSpeed();
    gpsLocation["bearingDeg"] = gps.getBearingDeg();
    gpsLocation["accuracy"] = gps.getAccuracy();
    QDateTime timestamp;
    timestamp.setMSecsSinceEpoch(gps.getTimestamp());
    gpsLocation["timestamp"] = timestamp;
    gpsLocation["verticalAccuracy"] = gps.getVerticalAccuracy();
    gpsLocation["bearingAccuracyDeg"] = gps.getBearingAccuracyDeg();
    gpsLocation["speedAccuracy"] = gps.getSpeedAccuracy();

    QQmlProperty::write(mapObject, "gpsLocation", QVariant::fromValue(gpsLocation));
  }
  // qDebug()
  //  << "Bearing:" << QQmlProperty::read(mapObject, "carBearing").toFloat()
  //  << "| Position:" << posLong << posLat;
}
