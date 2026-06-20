/// Scanner operating modes.
///
/// Each mode drives a different [ScanHandler] strategy that determines
/// what happens when a barcode is detected by the camera.
enum ScanMode {
  /// POS billing — continuous scan, auto-adds items to the active cart.
  billing,

  /// Inventory management — opens stock-edit modal or quick-add product flow.
  inventory,
}
