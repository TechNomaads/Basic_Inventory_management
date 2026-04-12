/// User-facing strings — no hardcoded strings in widgets.
///
/// All text displayed in the UI lives here for easy
/// localisation and consistency.

class AppStrings {
  AppStrings._();

  // ── App ────────────────────────────────────────────────────────
  static const String appName = 'Inventory Manager';
  static const String appVersion = '1.0.0';

  // ── Auth ───────────────────────────────────────────────────────
  static const String loginTitle = 'Welcome Back';
  static const String loginSubtitle = 'Sign in to manage your inventory';
  static const String emailLabel = 'Email';
  static const String passwordLabel = 'Password';
  static const String loginButton = 'Sign In';
  static const String loggingIn = 'Signing in...';
  static const String logoutButton = 'Sign Out';
  static const String invalidCredentials = 'Invalid email or password';

  // ── Scanner ────────────────────────────────────────────────────
  static const String scannerTitle = 'Barcode Scanner';
  static const String stockIn = 'STOCK IN';
  static const String stockOut = 'STOCK OUT';
  static const String manualEntry = 'Enter barcode manually';
  static const String manualEntryHint = 'Type or paste barcode...';
  static const String scanSuccess = 'Barcode scanned!';
  static const String torchToggle = 'Toggle flashlight';

  // ── Dashboard ──────────────────────────────────────────────────
  static const String dashboardTitle = 'Dashboard';
  static const String totalProducts = 'Total Products';
  static const String lowStock = 'Low Stock';
  static const String todaysScans = 'Today\'s Scans';
  static const String pendingApprovals = 'Pending Approvals';
  static const String recentActivity = 'Recent Activity';
  static const String lowStockAlerts = 'Low Stock Alerts';

  // ── Product ────────────────────────────────────────────────────
  static const String productDetail = 'Product Detail';
  static const String sku = 'SKU';
  static const String barcode = 'Barcode';
  static const String category = 'Category';
  static const String shelf = 'Shelf Location';
  static const String quantity = 'Quantity';
  static const String confirm = 'Confirm';
  static const String cancel = 'Cancel';
  static const String recentTransactions = 'Recent Transactions';

  // ── Adjustment ─────────────────────────────────────────────────
  static const String adjustmentNotes = 'Notes (optional)';
  static const String adjustmentThresholdMsg =
      'This adjustment exceeds the threshold and will require manager approval.';
  static const String adjustmentSubmitted = 'Adjustment submitted';
  static const String adjustmentPending = 'Sent for approval';

  // ── Reports ────────────────────────────────────────────────────
  static const String reportsTitle = 'Reports';
  static const String dispatched = 'Dispatched';
  static const String received = 'Received';
  static const String outOfStock = 'Out of Stock';
  static const String activeUsers = 'Active Users';

  // ── Admin ──────────────────────────────────────────────────────
  static const String productsManagement = 'Products';
  static const String usersManagement = 'Users';
  static const String auditLog = 'Audit Log';
  static const String addProduct = 'Add Product';
  static const String editProduct = 'Edit Product';
  static const String addUser = 'Add User';
  static const String approve = 'Approve';
  static const String reject = 'Reject';

  // ── Errors ─────────────────────────────────────────────────────
  static const String genericError = 'Something went wrong. Please try again.';
  static const String networkError = 'Network error. Check your connection.';
  static const String sessionExpired = 'Session expired. Please sign in again.';
  static const String versionConflict =
      'This item was updated by another user. Please refresh.';

  // ── Empty states ───────────────────────────────────────────────
  static const String noProducts = 'No products found';
  static const String noTransactions = 'No transactions yet';
  static const String noAlerts = 'All stock levels are healthy';
  static const String noPending = 'No pending adjustments';

  // ── Search ─────────────────────────────────────────────────────
  static const String searchHint = 'Search by name, SKU, or barcode...';
  static const String recentSearches = 'Recent Searches';
}
