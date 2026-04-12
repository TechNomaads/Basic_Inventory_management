/// Socket.IO service for real-time stock updates.
///
/// Responsibilities:
///   - Connect to the Socket.IO server
///   - Join/leave location rooms
///   - Listen for stock_updated events
///   - Expose a stream for Riverpod providers
///
/// Dependencies: socket_io_client

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../constants/api_endpoints.dart';

/// Event payload from stock_updated Socket.IO event
class StockUpdateEvent {
  final String productId;
  final int newQuantity;
  final String updatedBy;

  const StockUpdateEvent({
    required this.productId,
    required this.newQuantity,
    required this.updatedBy,
  });

  factory StockUpdateEvent.fromJson(Map<String, dynamic> json) {
    return StockUpdateEvent(
      productId: json['productId'] as String,
      newQuantity: json['newQuantity'] as int,
      updatedBy: json['updatedBy'] as String,
    );
  }
}

/// Provider for the SocketService singleton
final socketServiceProvider = Provider<SocketService>((ref) {
  return SocketService();
});

class SocketService {
  io.Socket? _socket;
  final _stockUpdateController = StreamController<StockUpdateEvent>.broadcast();

  /// Stream of real-time stock updates
  Stream<StockUpdateEvent> get stockUpdates => _stockUpdateController.stream;

  /// Connect to the Socket.IO server
  void connect({String? locationId}) {
    String url = ApiEndpoints.wsUrl;
    if (locationId != null) {
      url += '?location_id=$locationId';
    }

    _socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .build(),
    );

    _socket!.onConnect((_) {
      // Connected to Socket.IO server
    });

    _socket!.on('stock_updated', (data) {
      if (data is Map<String, dynamic>) {
        _stockUpdateController.add(StockUpdateEvent.fromJson(data));
      }
    });

    _socket!.onDisconnect((_) {
      // Disconnected from Socket.IO server
    });
  }

  /// Switch to a different location room
  void joinLocation(String locationId) {
    _socket?.emit('join_location', {'location_id': locationId});
  }

  /// Disconnect from the server
  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  /// Clean up resources
  void dispose() {
    disconnect();
    _stockUpdateController.close();
  }
}
