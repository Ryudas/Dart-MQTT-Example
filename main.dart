/*
 * Package : mqtt_client
 * Author : S. Hamblett <steve.hamblett@linux.com>
 * Date   : 31/05/2017
 * Copyright :  S.Hamblett
 */

import 'dart:async';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';

/// An annotated simple subscribe/publish usage example for mqtt_client. Please read in with reference
/// to the MQTT specification. The example is runnable, also refer to test/mqtt_client_broker_test...dart
/// files for separate subscribe/publish tests.

/// First create a mqtt_client, the mqtt_client is constructed with a broker name, mqtt_client identifier
/// and port if needed. The mqtt_client identifier (short ClientId) is an identifier of each MQTT
/// mqtt_client connecting to a MQTT broker. As the word identifier already suggests, it should be unique per broker.
/// The broker uses it for identifying the mqtt_client and the current state of the mqtt_client. If you don’t need a state
/// to be hold by the broker, in MQTT 3.1.1 you can set an empty ClientId, which results in a connection without any state.
/// A condition is that clean session connect flag is true, otherwise the connection will be rejected.
/// The mqtt_client identifier can be a maximum length of 23 characters. If a port is not specified the standard port
/// of 1883 is used.
/// If you want to use websockets rather than TCP see below.
final MqttClient mqtt_client = MqttClient.withPort('dwd.tudelft.nl', '', 8883);

Future<int> main() async {
  /// A websocket URL must start with ws:// or wss:// or Dart will throw an exception, consult your websocket MQTT broker
  /// for details.
  /// To use websockets add the following lines -:
  /// mqtt_client.useWebSocket = true;
  /// mqtt_client.port = 80;  ( or whatever your WS port is)
  /// There is also an alternate websocket implementation for specialist use, see useAlternateWebSocketImplementation
  /// Note do not set the secure flag if you are using wss, the secure flags is for TCP sockets only.
  /// You can also supply your own websocket protocol list or disable this feature using the websocketProtocols
  /// setter, read the API docs for further details here, the vast majority of brokers will support the mqtt_client default
  /// list so in most cases you can ignore this.

  /// Set logging on if needed, defaults to off
  mqtt_client.logging(on: true);

  /// If you intend to use a keep alive value in your connect message that is not the default(60s)
  /// you must set it here
  mqtt_client.keepAlivePeriod = 20;
  mqtt_client.secure = true;

  /// Add the unsolicited disconnection callback
  mqtt_client.onDisconnected = onDisconnected;

  /// Add the successful connection callback
  mqtt_client.onConnected = onConnected;

  /// Add a subscribed callback, there is also an unsubscribed callback if you need it.
  /// You can add these before connection or change them dynamically after connection if
  /// you wish. There is also an onSubscribeFail callback for failed subscriptions, these
  /// can fail either because you have tried to subscribe to an invalid topic or the broker
  /// rejects the subscribe request.
  mqtt_client.onSubscribed = onSubscribed;

  /// Set a ping received callback if needed, called whenever a ping response(pong) is received
  /// from the broker.
  mqtt_client.pongCallback = pong;
  String authenticate_as = "MY THING TOKEN";

  /// Create a connection message to use or use the default one. The default one sets the
  /// mqtt_client identifier, any supplied username/password, the default keepalive interval(60s)
  /// and clean session, an example of a specific one below.
  final MqttConnectMessage connMess = MqttConnectMessage()
      .withClientIdentifier('dcd:things:myphonedevice-8f1c')
      .keepAliveFor(60) // Must agree with the keep alive set above or not set
    .withWillQos(MqttQos.atLeastOnce)
  .startClean()
     .authenticateAs('MY THING ID',authenticate_as);
  print('EXAMPLE::dwd mqtt_client connecting....');
  mqtt_client.connectionMessage = connMess;

  /// Connect the mqtt_client, any errors here are communicated by raising of the appropriate exception. Note
  /// in some circumstances the broker will just disconnect us, see the spec about this, we however eill
  /// never send malformed messages.
  try {
    await mqtt_client.connect();
  } on Exception catch (e) {
    print('EXAMPLE::mqtt_client exception - $e');
    mqtt_client.disconnect();
  }

  /// Check we are connected
  if (mqtt_client.connectionStatus.state == MqttConnectionState.connected) {
    print('EXAMPLE::Mosquitto mqtt_client connected');
  } else {
    /// Use status here rather than state if you also want the broker return code.
    print(
        'EXAMPLE::ERROR Mosquitto mqtt_client connection failed - disconnecting, status is ${mqtt_client.connectionStatus}');
    mqtt_client.disconnect();
    exit(-1);
  }

  /// Ok, lets try a subscription
  print('EXAMPLE::Subscribing to the test/lol topic');
  const String topic = 'test/lol'; // Not a wildcard topic
  mqtt_client.subscribe(topic, MqttQos.atMostOnce);

  /// The mqtt_client has a change notifier object(see the Observable class) which we then listen to to get
  /// notifications of published updates to each subscribed topic.
  mqtt_client.updates.listen((List<MqttReceivedMessage<MqttMessage>> c) {
    final MqttPublishMessage recMess = c[0].payload;
    final String pt =
        MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

    /// The above may seem a little convoluted for users only interested in the
    /// payload, some users however may be interested in the received publish message,
    /// lets not constrain ourselves yet until the package has been in the wild
    /// for a while.
    /// The payload is a byte buffer, this will be specific to the topic
    print(
        'EXAMPLE::Change notification:: topic is <${c[0].topic}>, payload is <-- $pt -->');
    print('');
  });

  /// If needed you can listen for published messages that have completed the publishing
  /// handshake which is Qos dependant. Any message received on this stream has completed its
  /// publishing handshake with the broker.
  mqtt_client.published.listen((MqttPublishMessage message) {
    print(
        'EXAMPLE::Published notification:: topic is ${message.variableHeader.topicName}, with Qos ${message.header.qos}');
  });

  /// Lets publish to our topic
  /// Use the payload builder rather than a raw buffer
  /// Our known topic to publish to
  const String pubTopic = 'Dart/Mqtt_client/testtopic';
  final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
  builder.addString('Hello from mqtt_client');

  /// Subscribe to it
  print('EXAMPLE::Subscribing to the Dart/Mqtt_client/testtopic topic');
  mqtt_client.subscribe(pubTopic, MqttQos.exactlyOnce);

  /// Publish it
  print('EXAMPLE::Publishing our topic');
  mqtt_client.publishMessage(pubTopic, MqttQos.exactlyOnce, builder.payload);

  /// Ok, we will now sleep a while, in this gap you will see ping request/response
  /// messages being exchanged by the keep alive mechanism.
  print('EXAMPLE::Sleeping....');
  await MqttUtilities.asyncSleep(120);

  /// Finally, unsubscribe and exit gracefully
  print('EXAMPLE::Unsubscribing');
  mqtt_client.unsubscribe(topic);

  /// Wait for the unsubscribe message from the broker if you wish.
  await MqttUtilities.asyncSleep(2);
  print('EXAMPLE::Disconnecting');
  mqtt_client.disconnect();
  return 0;
}

/// The subscribed callback
void onSubscribed(String topic) {
  print('EXAMPLE::Subscription confirmed for topic $topic');
}

/// The unsolicited disconnect callback
void onDisconnected() {
  print('EXAMPLE::OnDisconnected mqtt_client callback - mqtt_client disconnection');
  if (mqtt_client.connectionStatus.returnCode == MqttConnectReturnCode.solicited) {
    print('EXAMPLE::OnDisconnected callback is solicited, this is correct');
  }
  exit(-1);
}

/// The successful connect callback
void onConnected() {
  print(
      'EXAMPLE::OnConnected mqtt_client callback - mqtt_client connection was sucessful');
}

/// Pong callback
void pong() {
  print('EXAMPLE::Ping response mqtt_client callback invoked');
}
