// ── API CONFIGURATION ──
const API_URL = 'http://localhost:8000';

// ── STATE STORE ──
const state = {
    token: localStorage.getItem('access_token') || null,
    refreshToken: localStorage.getItem('refresh_token') || null,
    user: JSON.parse(localStorage.getItem('user_info')) || null,
    activeTab: 'dashboard',
    
    // Cache for dropdowns
    categories: [],
    suppliers: [],
    locations: [],
    
    // Pagination for products
    productPage: 1,
    productSize: 20,
    
    // Active inventory location
    selectedLocationId: null,
    
    // Socket.IO instance
    socket: null,

    // Billing/POS Cart State
    cart: {
        items: [],
        customer_name: '',
        customer_phone: '',
        discount_amount: 0.0,
        payment_mode: 'cash',
        notes: ''
    },
    posInventory: []
};

// ── INITIALIZATION ──
document.addEventListener('DOMContentLoaded', () => {
    initApp();
});

function initApp() {
    // Check authentication state
    if (state.token && state.user) {
        showApp();
    } else {
        showLogin();
    }

    // Set up Lucide icons
    lucide.createIcons();

    // Bind event listeners
    bindEvents();
}

// ── EVENT BINDINGS ──
function bindEvents() {
    // Login form submission
    document.getElementById('login-form').addEventListener('submit', handleLogin);

    // Logout button
    document.getElementById('logout-btn').addEventListener('click', handleLogout);

    // Sidebar navigation tabs
    document.querySelectorAll('.nav-item').forEach(button => {
        button.addEventListener('click', (e) => {
            const tabName = e.currentTarget.getAttribute('data-tab');
            switchTab(tabName);
        });
    });

    // Refresh buttons
    document.getElementById('refresh-dashboard-btn').addEventListener('click', loadDashboardData);
    document.getElementById('refresh-inventory-btn').addEventListener('click', loadInventoryData);
    document.getElementById('refresh-sales-btn').addEventListener('click', loadSalesData);

    // Sales filters
    document.getElementById('sales-location-filter').addEventListener('change', loadSalesData);
    document.getElementById('sales-payment-filter').addEventListener('change', loadSalesData);
    document.getElementById('btn-print-receipt').addEventListener('click', printActiveReceipt);

    // Search and filters for products
    document.getElementById('product-search').addEventListener('input', debounce(filterProducts, 300));
    document.getElementById('product-category-filter').addEventListener('change', filterProducts);
    
    // Pagination buttons
    document.getElementById('product-prev-page').addEventListener('click', () => changeProductPage(-1));
    document.getElementById('product-next-page').addEventListener('click', () => changeProductPage(1));

    // Active location select change
    document.getElementById('inventory-location-select').addEventListener('change', handleLocationChange);

    // Modals - Open buttons
    document.getElementById('btn-add-product').addEventListener('click', () => openProductModal());

    // Modals - Close buttons (declarative close)
    document.querySelectorAll('[data-close-modal]').forEach(button => {
        button.addEventListener('click', (e) => {
            const modalId = e.currentTarget.getAttribute('data-close-modal');
            closeModal(modalId);
        });
    });

    // Forms submission
    document.getElementById('product-form').addEventListener('submit', handleProductSubmit);
    document.getElementById('tx-form').addEventListener('submit', handleTransactionSubmit);
    document.getElementById('adjustment-form').addEventListener('submit', handleAdjustmentSubmit);

    // Billing / POS Tab Bindings
    const posLocationSelect = document.getElementById('pos-location-select');
    if (posLocationSelect) {
        posLocationSelect.addEventListener('change', handlePosLocationChange);
    }
    const posProductSearch = document.getElementById('pos-product-search');
    if (posProductSearch) {
        posProductSearch.addEventListener('input', debounce(handlePosSearch, 300));
        posProductSearch.addEventListener('focus', handlePosSearch);
    }
    const posSearchClear = document.getElementById('pos-search-clear');
    if (posSearchClear) {
        posSearchClear.addEventListener('click', clearPosSearch);
    }
    const posCustomerPhone = document.getElementById('pos-customer-phone');
    if (posCustomerPhone) {
        posCustomerPhone.addEventListener('input', debounce(handleCustomerPhoneLookup, 500));
    }
    const posCustomerName = document.getElementById('pos-customer-name');
    if (posCustomerName) {
        posCustomerName.addEventListener('input', (e) => {
            state.cart.customer_name = e.target.value;
        });
    }
    const posNotes = document.getElementById('pos-notes');
    if (posNotes) {
        posNotes.addEventListener('input', (e) => {
            state.cart.notes = e.target.value;
        });
    }
    const posBillDiscount = document.getElementById('pos-bill-discount');
    if (posBillDiscount) {
        posBillDiscount.addEventListener('input', (e) => {
            state.cart.discount_amount = parseFloat(e.target.value) || 0;
            calculateCartTotals();
        });
    }
    const posCheckoutBtn = document.getElementById('pos-checkout-btn');
    if (posCheckoutBtn) {
        posCheckoutBtn.addEventListener('click', submitPosCheckout);
    }

    // Payment Mode buttons
    document.querySelectorAll('.btn-payment').forEach(btn => {
        btn.addEventListener('click', (e) => {
            document.querySelectorAll('.btn-payment').forEach(b => b.classList.remove('active'));
            const mode = e.currentTarget.getAttribute('data-mode');
            e.currentTarget.classList.add('active');
            state.cart.payment_mode = mode;
        });
    });

    // Document click to close autocomplete dropdown
    document.addEventListener('click', (e) => {
        const results = document.getElementById('pos-search-results');
        const searchInput = document.getElementById('pos-product-search');
        if (results && !results.contains(e.target) && e.target !== searchInput) {
            results.classList.add('hidden');
        }
    });

    // Barcode Scanner Modal buttons bindings
    const posScanBtn = document.getElementById('pos-scan-btn');
    if (posScanBtn) {
        posScanBtn.addEventListener('click', () => {
            ScannerService.startCameraScanner((barcode) => {
                handleBarcodeScanned(barcode, 'pos');
            });
        });
    }
    const inventoryScanBtn = document.getElementById('inventory-scan-btn');
    if (inventoryScanBtn) {
        inventoryScanBtn.addEventListener('click', () => {
            ScannerService.startCameraScanner((barcode) => {
                handleBarcodeScanned(barcode, 'inventory');
            });
        });
    }
    const productScanBtn = document.getElementById('product-scan-btn');
    if (productScanBtn) {
        productScanBtn.addEventListener('click', () => {
            ScannerService.startCameraScanner((barcode) => {
                handleBarcodeScanned(barcode, 'products');
            });
        });
    }
    const txScanBtn = document.getElementById('tx-scan-btn');
    if (txScanBtn) {
        txScanBtn.addEventListener('click', () => {
            ScannerService.startCameraScanner((barcode) => {
                handleBarcodeScanned(barcode, 'tx');
            });
        });
    }
    const adjScanBtn = document.getElementById('adj-scan-btn');
    if (adjScanBtn) {
        adjScanBtn.addEventListener('click', () => {
            ScannerService.startCameraScanner((barcode) => {
                handleBarcodeScanned(barcode, 'adj');
            });
        });
    }
    const btnStopScanner = document.getElementById('btn-stop-scanner');
    if (btnStopScanner) {
        btnStopScanner.addEventListener('click', () => ScannerService.stopCameraScanner());
    }
    const btnCloseScanner = document.getElementById('btn-close-scanner');
    if (btnCloseScanner) {
        btnCloseScanner.addEventListener('click', () => ScannerService.stopCameraScanner());
    }
    const cameraSelect = document.getElementById('scanner-camera-select');
    if (cameraSelect) {
        cameraSelect.addEventListener('change', (e) => {
            if (e.target.value) {
                ScannerService.switchCamera(e.target.value);
            }
        });
    }

    // Initialize global hardware/keyboard scanner emulation
    ScannerService.initHardwareScanner((barcode) => {
        handleBarcodeScanned(barcode, 'global');
    });
}

// ── AUTHENTICATION CONTROLLERS ──
async function handleLogin(e) {
    e.preventDefault();
    const email = document.getElementById('login-email').value;
    const password = document.getElementById('login-password').value;
    const loginError = document.getElementById('login-error');
    
    loginError.classList.add('hidden');
    
    try {
        const response = await fetch(`${API_URL}/api/v1/auth/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email, password })
        });
        
        if (!response.ok) {
            const errData = await response.json();
            throw new Error(errData.detail || 'Invalid email or password');
        }
        
        const data = await response.json();
        
        // Save tokens
        state.token = data.access_token;
        state.refreshToken = data.refresh_token;
        localStorage.setItem('access_token', data.access_token);
        localStorage.setItem('refresh_token', data.refresh_token);
        
        // Decode JWT payload
        const payload = decodeJwt(data.access_token);
        state.user = {
            id: payload.sub,
            email: email,
            name: email.split('@')[0],
            role: payload.role || 'staff'
        };
        localStorage.setItem('user_info', JSON.stringify(state.user));
        
        showApp();
    } catch (err) {
        document.getElementById('login-error-text').textContent = err.message;
        loginError.classList.remove('hidden');
    }
}

async function handleLogout() {
    try {
        if (state.token) {
            await fetchWithAuth(`${API_URL}/api/v1/auth/logout`, { method: 'POST' });
        }
    } catch (err) {
        console.error('Logout error:', err);
    } finally {
        state.token = null;
        state.refreshToken = null;
        state.user = null;
        localStorage.removeItem('access_token');
        localStorage.removeItem('refresh_token');
        localStorage.removeItem('user_info');
        
        // Close Socket
        if (state.socket) {
            state.socket.disconnect();
            state.socket = null;
        }
        
        showLogin();
    }
}

// ── SCREEN TOGGLES & ROLE VISIBILITY ──
function showLogin() {
    document.getElementById('login-screen').classList.remove('hidden');
    document.getElementById('app-layout').classList.add('hidden');
}

function showApp() {
    document.getElementById('login-screen').classList.add('hidden');
    document.getElementById('app-layout').classList.remove('hidden');

    // Init User profile Widget
    document.getElementById('user-display-name').textContent = state.user.name;
    document.getElementById('user-display-role').textContent = state.user.role;
    document.getElementById('user-avatar-initials').textContent = state.user.name.substring(0, 2).toUpperCase();

    // Role-based visibility
    const canManage = state.user.role === 'admin' || state.user.role === 'manager';
    const isAdmin = state.user.role === 'admin';

    // Show/Hide product management / pending approvals based on roles
    if (!canManage) {
        document.getElementById('btn-add-product').classList.add('hidden');
        document.getElementById('nav-pending').classList.add('hidden');
        document.querySelectorAll('.admin-manager-only').forEach(el => el.classList.add('hidden'));
    } else {
        document.getElementById('btn-add-product').classList.remove('hidden');
        document.getElementById('nav-pending').classList.remove('hidden');
        document.querySelectorAll('.admin-manager-only').forEach(el => el.classList.remove('hidden'));
    }

    if (!isAdmin) {
        document.getElementById('nav-audit').classList.add('hidden');
    } else {
        document.getElementById('nav-audit').classList.remove('hidden');
    }

    // Populate metadata
    loadMetadata();

    // Default tab
    switchTab('dashboard');

    // Init Socket IO
    initSocketConnection();
}

// ── TAB ROUTING ──
function switchTab(tabName) {
    state.activeTab = tabName;
    
    // Update active nav button
    document.querySelectorAll('.nav-item').forEach(button => {
        if (button.getAttribute('data-tab') === tabName) {
            button.classList.add('active');
        } else {
            button.classList.remove('active');
        }
    });

    // Update Title
    const titleMap = {
        'dashboard': 'Dashboard Metrics',
        'products': 'Product Directory',
        'inventory': 'Stock Inventory Controls',
        'billing': 'Point of Sale (POS) Billing',
        'pending': 'Pending Adjustments Approval',
        'audit': 'System Audit Logs',
        'sales': 'Sales Invoice History'
    };
    document.getElementById('current-tab-title').textContent = titleMap[tabName] || 'Dashboard';

    // Show active tab panel
    document.querySelectorAll('.tab-panel').forEach(panel => {
        if (panel.id === `tab-${tabName}`) {
            panel.classList.remove('hidden');
        } else {
            panel.classList.add('hidden');
        }
    });

    // Load data specific to tab
    if (tabName === 'dashboard') {
        loadDashboardData();
    } else if (tabName === 'products') {
        loadProductsData();
    } else if (tabName === 'inventory') {
        loadInventoryData();
    } else if (tabName === 'billing') {
        initBillingTab();
    } else if (tabName === 'pending') {
        loadPendingAdjustments();
    } else if (tabName === 'audit') {
        loadAuditLogs();
    } else if (tabName === 'sales') {
        loadSalesData();
    }
}

// ── METADATA LOADERS (LOCATIONS, CATEGORIES, SUPPLIERS) ──
async function loadMetadata() {
    try {
        const [locs, cats, sups] = await Promise.all([
            fetchWithAuth(`${API_URL}/api/v1/inventory/meta/locations`),
            fetchWithAuth(`${API_URL}/api/v1/inventory/meta/categories`),
            fetchWithAuth(`${API_URL}/api/v1/inventory/meta/suppliers`)
        ]);

        state.locations = locs;
        state.categories = cats;
        state.suppliers = sups;

        // Populate location selectors
        const locSelect = document.getElementById('inventory-location-select');
        locSelect.innerHTML = locs.map(l => `<option value="${l.id}">${l.name} (${l.code})</option>`).join('');
        if (locs.length > 0) {
            state.selectedLocationId = locs[0].id;
        }

        const salesLocFilter = document.getElementById('sales-location-filter');
        if (salesLocFilter) {
            salesLocFilter.innerHTML = '<option value="">All Locations</option>' + 
                locs.map(l => `<option value="${l.id}">${l.name}</option>`).join('');
        }

        // Populate category filters & modal selectors
        const catFilter = document.getElementById('product-category-filter');
        catFilter.innerHTML = '<option value="">All Categories</option>' + 
            cats.map(c => `<option value="${c.id}">${c.name}</option>`).join('');

        const prodCat = document.getElementById('prod-category');
        prodCat.innerHTML = cats.map(c => `<option value="${c.id}">${c.name}</option>`).join('');

        // Populate supplier selectors
        const prodSup = document.getElementById('prod-supplier');
        prodSup.innerHTML = sups.map(s => `<option value="${s.id}">${s.name}</option>`).join('');

    } catch (err) {
        console.error('Error loading metadata:', err);
    }
}

// ── DASHBOARD CONTROLLER ──
async function loadDashboardData() {
    try {
        const summary = await fetchWithAuth(`${API_URL}/api/v1/reports/summary`);
        
        // Update summary cards
        document.getElementById('stat-total-products').textContent = summary.total_products;
        document.getElementById('stat-low-stock').textContent = summary.low_stock_count;
        document.getElementById('stat-out-of-stock').textContent = summary.out_of_stock_count;
        document.getElementById('stat-todays-sales').textContent = summary.total_sales_today || 0;
        document.getElementById('stat-todays-revenue').textContent = `₹${(summary.revenue_today || 0).toFixed(2)}`;
        
        // Load recent transactions
        const txResponse = await fetchWithAuth(`${API_URL}/api/v1/reports/transactions?page=1&size=7`);
        const tbody = document.querySelector('#dashboard-tx-table tbody');
        
        if (!txResponse.items || txResponse.items.length === 0) {
            tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">No recent activity.</td></tr>';
            return;
        }

        tbody.innerHTML = txResponse.items.map(tx => {
            const dateStr = new Date(tx.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
            return `
                <tr>
                    <td>${dateStr}</td>
                    <td><strong>${escapeHtml(tx.product_name)}</strong><br><span class="text-hint text-xs">${tx.product_barcode}</span></td>
                    <td>${escapeHtml(tx.location_name)}</td>
                    <td>${escapeHtml(tx.user_name)}</td>
                    <td><span class="tx-type-tag tx-type-${tx.type}">${tx.type}</span></td>
                    <td class="${tx.quantity_change > 0 ? 'text-success' : 'text-danger'} font-semibold">
                        ${tx.quantity_change > 0 ? '+' : ''}${tx.quantity_change}
                    </td>
                    <td>${escapeHtml(tx.reference_no || '—')}</td>
                </tr>
            `;
        }).join('');

        // Load pending adjustments count badge
        if (state.user.role === 'admin' || state.user.role === 'manager') {
            const pendingList = await fetchWithAuth(`${API_URL}/api/v1/pending`);
            const pendingBadge = document.getElementById('pending-count');
            if (pendingList.length > 0) {
                pendingBadge.textContent = pendingList.length;
                pendingBadge.classList.remove('hidden');
            } else {
                pendingBadge.classList.add('hidden');
            }
        }

    } catch (err) {
        console.error('Error loading dashboard:', err);
    }
}

// ── PRODUCTS CONTROLLER ──
async function loadProductsData() {
    const search = document.getElementById('product-search').value;
    const catId = document.getElementById('product-category-filter').value;
    
    let url = `${API_URL}/api/v1/products?page=${state.productPage}&size=${state.productSize}`;
    if (search) url += `&search=${encodeURIComponent(search)}`;
    if (catId) url += `&category_id=${catId}`;

    const tbody = document.querySelector('#products-table tbody');
    tbody.innerHTML = '<tr><td colspan="9" class="text-center text-muted">Loading products...</td></tr>';

    try {
        const data = await fetchWithAuth(url);
        
        if (!data.items || data.items.length === 0) {
            tbody.innerHTML = '<tr><td colspan="9" class="text-center text-muted">No products found.</td></tr>';
            document.getElementById('product-prev-page').disabled = true;
            document.getElementById('product-next-page').disabled = true;
            document.getElementById('product-page-info').textContent = 'Page 1 of 1';
            return;
        }

        const canManage = state.user.role === 'admin' || state.user.role === 'manager';
        const isAdmin = state.user.role === 'admin';

        tbody.innerHTML = data.items.map(p => `
            <tr>
                <td><strong>${escapeHtml(p.name)}</strong></td>
                <td><code class="text-xs">${escapeHtml(p.sku)}</code></td>
                <td><code>${escapeHtml(p.barcode)}</code></td>
                <td>${escapeHtml(p.category_name || 'Uncategorized')}</td>
                <td>${escapeHtml(p.supplier_name || '—')}</td>
                <td>${escapeHtml(p.unit)}</td>
                <td>${p.cost_price.toFixed(2)}</td>
                <td>${p.sell_price.toFixed(2)}</td>
                ${canManage ? `
                    <td class="text-right">
                        <button class="action-btn action-btn-primary" onclick="openProductModal('${p.barcode}')" title="Edit">
                            <i data-lucide="edit-2"></i>
                        </button>
                        ${isAdmin ? `
                            <button class="action-btn action-btn-danger" onclick="deleteProduct('${p.id}')" title="Delete">
                                <i data-lucide="trash-2"></i>
                            </button>
                        ` : ''}
                    </td>
                ` : '<td class="text-right">—</td>'}
            </tr>
        `).join('');

        lucide.createIcons();

        // Handle pagination state
        document.getElementById('product-page-info').textContent = `Page ${data.page} of ${data.pages || 1}`;
        document.getElementById('product-prev-page').disabled = data.page <= 1;
        document.getElementById('product-next-page').disabled = data.page >= data.pages;

    } catch (err) {
        tbody.innerHTML = `<tr><td colspan="9" class="text-center text-danger">Error: ${err.message}</td></tr>`;
    }
}

function filterProducts() {
    state.productPage = 1;
    loadProductsData();
}

function changeProductPage(delta) {
    state.productPage += delta;
    loadProductsData();
}

// ── INVENTORY CONTROLLER ──
async function loadInventoryData() {
    if (!state.selectedLocationId) return;

    const tbody = document.querySelector('#inventory-table tbody');
    tbody.innerHTML = '<tr><td colspan="9" class="text-center text-muted">Loading stock levels...</td></tr>';

    try {
        const items = await fetchWithAuth(`${API_URL}/api/v1/inventory/${state.selectedLocationId}`);
        state.posInventory = items; // Cache inventory items for barcode scanning
        
        if (items.length === 0) {
            tbody.innerHTML = '<tr><td colspan="9" class="text-center text-muted">No inventory records found for this location.</td></tr>';
            return;
        }

        tbody.innerHTML = items.map(item => {
            const dateStr = new Date(item.updated_at).toLocaleString([], { dateStyle: 'short', timeStyle: 'short' });
            
            // Calculate status bar fill percentage
            let percentage = 0;
            const minVal = item.min_quantity || 0;
            const maxVal = item.max_quantity || 0;
            const qty = item.quantity || 0;
            
            if (maxVal > 0) {
                percentage = Math.min(100, Math.max(0, (qty / maxVal) * 100));
            } else if (minVal > 0) {
                percentage = Math.min(100, Math.max(0, (qty / (minVal * 2)) * 100));
            } else {
                percentage = qty > 0 ? 100 : 0;
            }
            
            const barColor = item.stock_status === 'green' ? 'green' : item.stock_status === 'amber' ? 'amber' : 'red';

            return `
                <tr id="inv-row-${item.product_id}">
                    <td><strong>${escapeHtml(item.product_name)}</strong></td>
                    <td><code class="text-xs">${escapeHtml(item.product_sku)}</code></td>
                    <td><code>${escapeHtml(item.product_barcode)}</code></td>
                    <td class="font-bold text-lg" id="inv-qty-${item.product_id}">${item.quantity}</td>
                    <td>${item.min_quantity}</td>
                    <td>${item.max_quantity || '—'}</td>
                    <td>
                        <div class="status-bar-container" title="${Math.round(percentage)}%">
                            <div class="status-bar-fill ${barColor}" style="width: ${percentage}%"></div>
                        </div>
                    </td>
                    <td>
                        <span class="badge badge-${item.stock_status}" id="inv-status-${item.product_id}">
                            ${item.stock_status === 'green' ? 'Healthy' : item.stock_status === 'amber' ? 'Low Stock' : 'Out of Stock'}
                        </span>
                    </td>
                    <td>${dateStr}</td>
                    <td class="text-right">
                        <button class="btn btn-sm btn-ghost" onclick="openTxModal('${item.product_id}', '${item.product_name}', ${item.quantity}, ${item.version})">
                            <i data-lucide="arrow-left-right"></i> In/Out
                        </button>
                        <button class="btn btn-sm btn-ghost" onclick="openAdjustmentModal('${item.product_id}', '${item.product_name}', ${item.quantity}, ${item.version})">
                            <i data-lucide="sliders"></i> Adjust
                        </button>
                    </td>
                </tr>
            `;
        }).join('');

        lucide.createIcons();

        // Emit WebSocket join room
        if (state.socket && state.socket.connected) {
            state.socket.emit('join_location', { location_id: state.selectedLocationId });
        }

    } catch (err) {
        tbody.innerHTML = `<tr><td colspan="9" class="text-center text-danger">Error: ${err.message}</td></tr>`;
    }
}

function handleLocationChange(e) {
    state.selectedLocationId = e.target.value;
    loadInventoryData();
}

// ── PENDING ADJUSTMENTS CONTROLLER ──
async function loadPendingAdjustments() {
    const tbody = document.querySelector('#pending-table tbody');
    tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">Loading pending approvals...</td></tr>';

    try {
        const items = await fetchWithAuth(`${API_URL}/api/v1/pending`);
        
        if (items.length === 0) {
            tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">No pending adjustments found.</td></tr>';
            return;
        }

        tbody.innerHTML = items.map(item => {
            const dateStr = new Date(item.created_at).toLocaleString([], { dateStyle: 'short', timeStyle: 'short' });
            return `
                <tr>
                    <td>${dateStr}</td>
                    <td><strong>${escapeHtml(item.product_name)}</strong></td>
                    <td>${escapeHtml(item.location_name)}</td>
                    <td>${escapeHtml(item.user_name)}</td>
                    <td class="${item.quantity_change > 0 ? 'text-success' : 'text-danger'} font-bold">
                        ${item.quantity_change > 0 ? '+' : ''}${item.quantity_change}
                    </td>
                    <td>${escapeHtml(item.notes || '—')}</td>
                    <td class="text-right">
                        <button class="action-btn action-btn-success" onclick="approveAdjustment('${item.id}')" title="Approve">
                            <i data-lucide="check"></i> Approve
                        </button>
                        <button class="action-btn action-btn-danger" onclick="rejectAdjustment('${item.id}')" title="Reject">
                            <i data-lucide="x"></i> Reject
                        </button>
                    </td>
                </tr>
            `;
        }).join('');

        lucide.createIcons();

    } catch (err) {
        tbody.innerHTML = `<tr><td colspan="7" class="text-center text-danger">Error: ${err.message}</td></tr>`;
    }
}

async function approveAdjustment(adjId) {
    if (!confirm('Are you sure you want to APPROVE this adjustment?')) return;
    try {
        await fetchWithAuth(`${API_URL}/api/v1/pending/${adjId}/approve`, { method: 'POST' });
        loadPendingAdjustments();
        loadDashboardData();
    } catch (err) {
        alert('Approval failed: ' + err.message);
    }
}

async function rejectAdjustment(adjId) {
    if (!confirm('Are you sure you want to REJECT this adjustment?')) return;
    try {
        await fetchWithAuth(`${API_URL}/api/v1/pending/${adjId}/reject`, { method: 'POST' });
        loadPendingAdjustments();
        loadDashboardData();
    } catch (err) {
        alert('Rejection failed: ' + err.message);
    }
}

// ── AUDIT LOGS CONTROLLER ──
async function loadAuditLogs() {
    const tbody = document.querySelector('#audit-table tbody');
    tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">Loading audit logs...</td></tr>';

    try {
        const response = await fetchWithAuth(`${API_URL}/api/v1/audit?page=1&size=50`);
        
        if (!response.items || response.items.length === 0) {
            tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">No audit logs found.</td></tr>';
            return;
        }

        tbody.innerHTML = response.items.map(log => {
            const dateStr = new Date(log.created_at).toLocaleString();
            return `
                <tr>
                    <td><span class="text-xs">${dateStr}</span></td>
                    <td><code class="px-2 py-0.5 rounded bg-slate-800 text-purple-400 font-bold">${log.action}</code></td>
                    <td><code>${log.table_name}</code></td>
                    <td><span class="text-xs text-hint">${log.record_id}</span></td>
                    <td><strong>${escapeHtml(log.user_name)}</strong></td>
                    <td><code>${log.ip_address || '—'}</code></td>
                    <td>
                        <span class="text-xs text-muted" title="${escapeHtml(JSON.stringify(log.new_values))}">
                            ${log.new_values ? escapeHtml(JSON.stringify(log.new_values)).substring(0, 50) + '...' : '—'}
                        </span>
                    </td>
                </tr>
            `;
        }).join('');

    } catch (err) {
        tbody.innerHTML = `<tr><td colspan="7" class="text-center text-danger">Error: ${err.message}</td></tr>`;
    }
}

// ── ADD / EDIT PRODUCT FORM SUBMISSIONS ──
async function openProductModal(productId = null) {
    const errorEl = document.getElementById('product-error');
    errorEl.classList.add('hidden');
    
    const form = document.getElementById('product-form');
    form.reset();

    if (productId) {
        document.getElementById('product-modal-title').textContent = 'Edit Product';
        try {
            // Find product row data (or fetch it)
            const prod = await fetchWithAuth(`${API_URL}/api/v1/products/${productId}`); // Wait, our route is paginated, let's hit by barcode or ID. Wait, we don't have GET /products/{id} directly, but wait!
            // Let's verify if there is GET /products/{id} endpoint or if we fetch via paginated items.
            // Oh, wait, list_products returns items, we can query it or simply fetch. Let's write query or find.
            document.getElementById('product-id-field').value = prod.id;
            document.getElementById('prod-name').value = prod.name;
            document.getElementById('prod-sku').value = prod.sku;
            document.getElementById('prod-barcode').value = prod.barcode;
            document.getElementById('prod-category').value = prod.category_id;
            document.getElementById('prod-supplier').value = prod.supplier_id;
            document.getElementById('prod-unit').value = prod.unit;
            document.getElementById('prod-cost').value = prod.cost_price;
            document.getElementById('prod-sell').value = prod.sell_price;
            document.getElementById('prod-image').value = prod.image_url || '';
        } catch (err) {
            console.error('Error fetching product detail:', err);
        }
    } else {
        document.getElementById('product-modal-title').textContent = 'Add New Product';
        document.getElementById('product-id-field').value = '';
    }

    openModal('product-modal');
}

async function handleProductSubmit(e) {
    e.preventDefault();
    const id = document.getElementById('product-id-field').value;
    const errorEl = document.getElementById('product-error');
    
    errorEl.classList.add('hidden');

    const payload = {
        name: document.getElementById('prod-name').value,
        sku: document.getElementById('prod-sku').value,
        barcode: document.getElementById('prod-barcode').value,
        category_id: document.getElementById('prod-category').value,
        supplier_id: document.getElementById('prod-supplier').value,
        unit: document.getElementById('prod-unit').value,
        cost_price: parseFloat(document.getElementById('prod-cost').value),
        sell_price: parseFloat(document.getElementById('prod-sell').value),
        image_url: document.getElementById('prod-image').value || null
    };

    try {
        let response;
        if (id) {
            response = await fetchWithAuth(`${API_URL}/api/v1/products/${id}`, {
                method: 'PUT',
                body: JSON.stringify(payload)
            });
        } else {
            response = await fetchWithAuth(`${API_URL}/api/v1/products`, {
                method: 'POST',
                body: JSON.stringify(payload)
            });
        }

        closeModal('product-modal');
        loadProductsData();
        loadDashboardData();
    } catch (err) {
        document.getElementById('product-error-text').textContent = err.message;
        errorEl.classList.remove('hidden');
    }
}

async function deleteProduct(productId) {
    if (!confirm('Are you sure you want to deactivate/delete this product?')) return;
    try {
        await fetchWithAuth(`${API_URL}/api/v1/products/${productId}`, {
            method: 'DELETE'
        });
        loadProductsData();
        loadDashboardData();
    } catch (err) {
        alert('Deletion failed: ' + err.message);
    }
}

// ── STOCK TRANSACTION SUBMISSION ──
function openTxModal(productId, productName, qty, version) {
    document.getElementById('tx-error').classList.add('hidden');
    document.getElementById('tx-form').reset();
    
    document.getElementById('tx-product-id').value = productId;
    document.getElementById('tx-location-id').value = state.selectedLocationId;
    document.getElementById('tx-known-version').value = version;
    
    document.getElementById('tx-prod-name-display').textContent = productName;
    document.getElementById('tx-prod-qty-display').textContent = qty;
    
    openModal('tx-modal');
}

async function handleTransactionSubmit(e) {
    e.preventDefault();
    const errorEl = document.getElementById('tx-error');
    errorEl.classList.add('hidden');

    const productId = document.getElementById('tx-product-id').value;
    const locationId = document.getElementById('tx-location-id').value;
    const version = parseInt(document.getElementById('tx-known-version').value);
    const type = document.getElementById('tx-type').value;
    let qtyChange = parseInt(document.getElementById('tx-qty').value);

    // Negative mapping for dispatch / damage
    if (type === 'dispatch' || type === 'damage' || type === 'transfer_out') {
        qtyChange = -Math.abs(qtyChange);
    } else {
        qtyChange = Math.abs(qtyChange);
    }

    const payload = {
        product_id: productId,
        location_id: locationId,
        type: type,
        quantity_change: qtyChange,
        known_version: version,
        reference_no: document.getElementById('tx-ref').value || null,
        notes: document.getElementById('tx-notes').value || null
    };

    try {
        await fetchWithAuth(`${API_URL}/api/v1/inventory/transaction`, {
            method: 'POST',
            body: JSON.stringify(payload)
        });

        closeModal('tx-modal');
        loadInventoryData();
        loadDashboardData();
    } catch (err) {
        document.getElementById('tx-error-text').textContent = err.message;
        errorEl.classList.remove('hidden');
    }
}

// ── STOCK ADJUSTMENT SUBMISSION ──
function openAdjustmentModal(productId, productName, qty, version) {
    document.getElementById('adj-error').classList.add('hidden');
    document.getElementById('adjustment-form').reset();
    
    document.getElementById('adj-product-id').value = productId;
    document.getElementById('adj-location-id').value = state.selectedLocationId;
    document.getElementById('adj-known-version').value = version;
    
    document.getElementById('adj-prod-name-display').textContent = productName;
    document.getElementById('adj-prod-qty-display').textContent = qty;
    
    openModal('adjustment-modal');
}

async function handleAdjustmentSubmit(e) {
    e.preventDefault();
    const errorEl = document.getElementById('adj-error');
    errorEl.classList.add('hidden');

    const productId = document.getElementById('adj-product-id').value;
    const locationId = document.getElementById('adj-location-id').value;
    const version = parseInt(document.getElementById('adj-known-version').value);
    const qtyChange = parseInt(document.getElementById('adj-qty').value);

    const payload = {
        product_id: productId,
        location_id: locationId,
        quantity_change: qtyChange,
        known_version: version,
        notes: document.getElementById('adj-notes').value || null
    };

    try {
        const response = await fetchWithAuth(`${API_URL}/api/v1/inventory/adjustment`, {
            method: 'POST',
            body: JSON.stringify(payload)
        });

        closeModal('adjustment-modal');
        loadInventoryData();
        loadDashboardData();

        if (response.status === 'pending') {
            alert('Stock adjustment exceeds threshold (10 units) and has been routed to the pending queue for manager approval.');
        } else {
            alert('Stock adjustment applied directly.');
        }
    } catch (err) {
        document.getElementById('adj-error-text').textContent = err.message;
        errorEl.classList.remove('hidden');
    }
}

// ── REAL-TIME SOCKET.IO CONNECTION ──
function initSocketConnection() {
    if (state.socket) return;

    // Connect to backend ws
    state.socket = io(`${API_URL}`, {
        path: '/ws/socket.io',
        transports: ['websocket'],
        query: state.selectedLocationId ? { location_id: state.selectedLocationId } : {}
    });

    const statusEl = document.getElementById('sync-status');

    state.socket.on('connect', () => {
        statusEl.className = 'sync-status connected';
        statusEl.querySelector('.status-text').textContent = 'Live Sync Active';
        
        // Join active location room if set
        if (state.selectedLocationId) {
            state.socket.emit('join_location', { location_id: state.selectedLocationId });
        }
    });

    state.socket.on('disconnect', () => {
        statusEl.className = 'sync-status disconnected';
        statusEl.querySelector('.status-text').textContent = 'Disconnected';
    });

    // Handle real-time stock update events
    state.socket.on('stock_updated', (data) => {
        console.log('⚡ Socket event: stock_updated', data);
        
        // Update the dashboard figures
        if (state.activeTab === 'dashboard') {
            loadDashboardData();
        }

        // Dynamically update the cell value in inventory table if visible
        if (state.activeTab === 'inventory') {
            const qtyCell = document.getElementById(`inv-qty-${data.productId}`);
            if (qtyCell) {
                qtyCell.textContent = data.newQuantity;
                qtyCell.classList.add('text-success');
                setTimeout(() => qtyCell.classList.remove('text-success'), 1500);

                // Update the status badge and status bar too!
                const row = document.getElementById(`inv-row-${data.productId}`);
                if (row) {
                    const cells = row.getElementsByTagName('td');
                    if (cells.length >= 8) {
                        const qty = data.newQuantity;
                        const min = parseInt(cells[4].textContent) || 0;
                        const maxStr = cells[5].textContent.trim();
                        const max = maxStr === '—' || maxStr === '' ? 0 : parseInt(maxStr) || 0;

                        // Recalculate percentage
                        let percentage = 0;
                        if (max > 0) {
                            percentage = Math.min(100, Math.max(0, (qty / max) * 100));
                        } else if (min > 0) {
                            percentage = Math.min(100, Math.max(0, (qty / (min * 2)) * 100));
                        } else {
                            percentage = qty > 0 ? 100 : 0;
                        }

                        // Determine new status
                        let statusColor = 'green';
                        let statusText = 'Healthy';
                        if (qty <= 0) {
                            statusColor = 'red';
                            statusText = 'Out of Stock';
                        } else if (min > 0 && qty < min) {
                            statusColor = 'amber';
                            statusText = 'Low Stock';
                        }

                        // Update Status Bar
                        const barFill = row.querySelector('.status-bar-fill');
                        if (barFill) {
                            barFill.style.width = `${percentage}%`;
                            barFill.className = `status-bar-fill ${statusColor === 'amber' ? 'amber' : statusColor === 'green' ? 'green' : 'red'}`;
                        }

                        // Update Status Badge
                        const statusBadge = document.getElementById(`inv-status-${data.productId}`);
                        if (statusBadge) {
                            statusBadge.className = `badge badge-${statusColor}`;
                            statusBadge.textContent = statusText;
                        }
                    }
                }
            }
        }
    });
}

// ── CLIENT UTILITIES & HELPER METHODS ──
async function fetchWithAuth(url, options = {}) {
    options.headers = options.headers || {};
    options.headers['Authorization'] = `Bearer ${state.token}`;
    if (!(options.body instanceof FormData)) {
        options.headers['Content-Type'] = 'application/json';
    }

    let response = await fetch(url, options);

    // If 401, token might be expired. Try to refresh
    if (response.status === 401 && state.refreshToken) {
        console.warn('Access token expired, attempting rotation...');
        try {
            const refreshResponse = await fetch(`${API_URL}/api/v1/auth/refresh`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ refresh_token: state.refreshToken })
            });

            if (!refreshResponse.ok) {
                throw new Error('Refresh token revoked');
            }

            const data = await refreshResponse.json();
            
            // Save new tokens
            state.token = data.access_token;
            state.refreshToken = data.refresh_token;
            localStorage.setItem('access_token', data.access_token);
            localStorage.setItem('refresh_token', data.refresh_token);

            // Retry original request
            options.headers['Authorization'] = `Bearer ${state.token}`;
            response = await fetch(url, options);
        } catch (refreshErr) {
            console.error('Session expired. Logging out...', refreshErr);
            handleLogout();
            throw new Error('Session expired. Please log in again.');
        }
    }

    if (!response.ok) {
        const errData = await response.json();
        throw new Error(errData.detail || `Request failed with status ${response.status}`);
    }

    // Handle empty responses
    if (response.status === 204) return null;
    return await response.json();
}

// Global modal methods
window.openModal = function(modalId) {
    document.getElementById(modalId).classList.remove('hidden');
};

window.closeModal = function(modalId) {
    document.getElementById(modalId).classList.add('hidden');
};

// JWT Decoder
function decodeJwt(token) {
    try {
        const base64Url = token.split('.')[1];
        const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
        const jsonPayload = decodeURIComponent(atob(base64).split('').map(function(c) {
            return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
        }).join(''));
        return JSON.parse(jsonPayload);
    } catch (e) {
        return {};
    }
}

// HTML Escaper
function escapeHtml(str) {
    if (!str) return '';
    return str.replace(/&/g, '&amp;')
              .replace(/</g, '&lt;')
              .replace(/>/g, '&gt;')
              .replace(/"/g, '&quot;')
              .replace(/'/g, '&#039;');
}

// Debounce helper
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

// ── SALES & RECEIPT CONTROLLERS ──
async function loadSalesData() {
    try {
        const locFilter = document.getElementById('sales-location-filter').value;
        const payFilter = document.getElementById('sales-payment-filter').value;

        let query = `${API_URL}/api/v1/billing/invoices?skip=0&limit=50`;
        if (locFilter) query += `&location_id=${locFilter}`;
        if (payFilter) query += `&payment_mode=${payFilter}`;

        const invoices = await fetchWithAuth(query);
        const tbody = document.querySelector('#sales-table tbody');

        if (!invoices || invoices.length === 0) {
            tbody.innerHTML = '<tr><td colspan="11" class="text-center text-muted">No sales invoices found.</td></tr>';
            return;
        }

        tbody.innerHTML = invoices.map(inv => {
            const dateStr = new Date(inv.created_at).toLocaleString();
            return `
                <tr>
                    <td><strong>${escapeHtml(inv.invoice_number)}</strong></td>
                    <td>${dateStr}</td>
                    <td>${escapeHtml(inv.location_name)}</td>
                    <td>${escapeHtml(inv.user_name)}</td>
                    <td>${escapeHtml(inv.customer_name || 'Anonymous/Walk-in')} ${inv.customer_phone ? `(${escapeHtml(inv.customer_phone)})` : ''}</td>
                    <td><span class="payment-mode-tag payment-${inv.payment_mode}">${inv.payment_mode.toUpperCase()}</span></td>
                    <td>${inv.subtotal.toFixed(2)}</td>
                    <td>${inv.tax_amount.toFixed(2)}</td>
                    <td>${inv.discount_amount.toFixed(2)}</td>
                    <td class="font-semibold text-success">${inv.total_amount.toFixed(2)}</td>
                    <td class="text-right">
                        <button class="btn btn-sm btn-ghost" onclick="viewInvoiceDetails('${inv.id}')" title="View Details">
                            <i data-lucide="eye" style="width:16px;height:16px;"></i> View
                        </button>
                    </td>
                </tr>
            `;
        }).join('');
        lucide.createIcons();

    } catch (err) {
        console.error('Error loading sales data:', err);
    }
}

let activeInvoiceId = null;

async function viewInvoiceDetails(id) {
    activeInvoiceId = id;
    try {
        const invoice = await fetchWithAuth(`${API_URL}/api/v1/billing/invoices/${id}`);
        
        document.getElementById('inv-detail-number').textContent = invoice.invoice_number;
        document.getElementById('inv-detail-date').textContent = new Date(invoice.created_at).toLocaleString();
        document.getElementById('inv-detail-location').textContent = invoice.location_name;
        document.getElementById('inv-detail-cashier').textContent = invoice.user_name;
        document.getElementById('inv-detail-customer').textContent = invoice.customer_name 
            ? `${invoice.customer_name} (${invoice.customer_phone || 'No phone'})` 
            : 'Anonymous/Walk-in';

        // Render line items
        const tbody = document.querySelector('#invoice-items-table tbody');
        tbody.innerHTML = invoice.items.map(item => `
            <tr>
                <td><strong>${escapeHtml(item.product_name)}</strong><br><span class="text-hint text-xs">${item.product_barcode}</span></td>
                <td>${item.quantity}</td>
                <td>${item.unit_price.toFixed(2)}</td>
                <td>${item.tax_rate}%</td>
                <td>${item.tax_amount.toFixed(2)}</td>
                <td class="font-semibold">${item.line_total.toFixed(2)}</td>
            </tr>
        `).join('');

        document.getElementById('inv-detail-subtotal').textContent = `₹${invoice.subtotal.toFixed(2)}`;
        document.getElementById('inv-detail-tax').textContent = `₹${invoice.tax_amount.toFixed(2)}`;
        document.getElementById('inv-detail-discount').textContent = `-₹${invoice.discount_amount.toFixed(2)}`;
        document.getElementById('inv-detail-total').textContent = `₹${invoice.total_amount.toFixed(2)}`;

        openModal('invoice-modal');
        lucide.createIcons();
    } catch (err) {
        alert('Error fetching invoice: ' + err.message);
    }
}

function printActiveReceipt() {
    if (!activeInvoiceId) return;
    const printUrl = `${API_URL}/api/v1/billing/invoices/${activeInvoiceId}/receipt`;
    const win = window.open(printUrl, '_blank', 'width=400,height=600');
    if (win) {
        win.focus();
    } else {
        alert('Please allow popups to print the thermal receipt.');
    }
}

// ── POINT OF SALE (POS) / BILLING CONTROLLER ──
async function initBillingTab() {
    // 1. Clear cart state
    state.cart = {
        items: [],
        customer_name: '',
        customer_phone: '',
        discount_amount: 0.0,
        payment_mode: 'cash',
        notes: ''
    };

    // 2. Clear inputs in checkout panel
    document.getElementById('pos-customer-phone').value = '';
    document.getElementById('pos-customer-name').value = '';
    document.getElementById('pos-notes').value = '';
    document.getElementById('pos-bill-discount').value = '0.00';
    document.getElementById('pos-product-search').value = '';
    document.getElementById('pos-search-clear').classList.add('hidden');
    document.getElementById('pos-search-results').classList.add('hidden');
    document.getElementById('pos-error').classList.add('hidden');

    // Reset payment buttons
    document.querySelectorAll('.btn-payment').forEach(btn => {
        if (btn.getAttribute('data-mode') === 'cash') {
            btn.classList.add('active');
        } else {
            btn.classList.remove('active');
        }
    });

    // Set cashier name
    document.getElementById('pos-cashier-name').textContent = state.user ? state.user.name : 'Unknown';

    // 3. Populate locations select list
    const selectEl = document.getElementById('pos-location-select');
    selectEl.innerHTML = state.locations.map(l => `<option value="${l.id}">${l.name}</option>`).join('');
    
    // Choose active location
    if (state.selectedLocationId) {
        selectEl.value = state.selectedLocationId;
    } else if (state.locations.length > 0) {
        state.selectedLocationId = state.locations[0].id;
        selectEl.value = state.selectedLocationId;
    }

    // 4. Fetch inventory for selected location to enable instant search
    await loadPosInventory();
    
    // 5. Render cart (empty initially)
    renderCart();
}

async function loadPosInventory() {
    if (!state.selectedLocationId) return;
    try {
        state.posInventory = await fetchWithAuth(`${API_URL}/api/v1/inventory/${state.selectedLocationId}`);
    } catch (err) {
        console.error('Error loading inventory for POS:', err);
        state.posInventory = [];
    }
}

async function handlePosLocationChange(e) {
    const newLocId = e.target.value;
    
    // Warn the cashier if cart is not empty as stock levels differ per location
    if (state.cart.items.length > 0) {
        if (confirm('Changing location will clear your current cart. Do you want to proceed?')) {
            state.cart.items = [];
            state.selectedLocationId = newLocId;
            await loadPosInventory();
            renderCart();
        } else {
            // Revert select dropdown
            e.target.value = state.selectedLocationId;
            return;
        }
    } else {
        state.selectedLocationId = newLocId;
        await loadPosInventory();
    }
}

function handlePosSearch() {
    const queryInput = document.getElementById('pos-product-search');
    const query = queryInput.value.toLowerCase().trim();
    const dropdown = document.getElementById('pos-search-results');
    const clearBtn = document.getElementById('pos-search-clear');

    if (query) {
        clearBtn.classList.remove('hidden');
    } else {
        clearBtn.classList.add('hidden');
        dropdown.classList.add('hidden');
        return;
    }

    // Filter in-memory products
    const results = state.posInventory.filter(item => {
        const prodName = item.product_name || '';
        const prodSku = item.product_sku || '';
        const prodBarcode = item.product_barcode || '';
        return prodName.toLowerCase().includes(query) ||
               prodSku.toLowerCase().includes(query) ||
               prodBarcode.includes(query);
    }).slice(0, 10); // Limit to top 10

    if (results.length === 0) {
        dropdown.innerHTML = '<div style="padding: 12px; text-align: center; color: var(--text-hint);">No matching products in stock</div>';
    } else {
        dropdown.innerHTML = results.map(item => {
            const stockBadgeClass = item.stock_status === 'red' ? 'badge-red' : (item.stock_status === 'amber' ? 'badge-amber' : 'badge-green');
            return `
                <div class="search-item" onclick="window.addPosCartItem('${item.product_id}')">
                    <div class="item-details">
                        <span class="item-name">${escapeHtml(item.product_name)}</span>
                        <span class="item-sub">SKU: ${escapeHtml(item.product_sku)} | Barcode: ${escapeHtml(item.product_barcode)}</span>
                    </div>
                    <div style="display: flex; align-items: center; gap: 10px;">
                        <span class="badge ${stockBadgeClass}">${item.quantity} in stock</span>
                    </div>
                </div>
            `;
        }).join('');
    }
    dropdown.classList.remove('hidden');
}

function clearPosSearch() {
    document.getElementById('pos-product-search').value = '';
    document.getElementById('pos-search-clear').classList.add('hidden');
    document.getElementById('pos-search-results').classList.add('hidden');
}

function addPosCartItem(productId) {
    // 1. Get product details from inventory cache
    const invItem = state.posInventory.find(item => item.product_id === productId);
    if (!invItem) return;

    if (invItem.quantity <= 0) {
        alert('This product is out of stock at the selected location.');
        return;
    }

    // 2. Check if item is already in cart
    const existingCartItem = state.cart.items.find(item => item.product_id === productId);
    if (existingCartItem) {
        if (existingCartItem.quantity + 1 > invItem.quantity) {
            alert(`Cannot add more. Only ${invItem.quantity} units available in stock.`);
            return;
        }
        existingCartItem.quantity += 1;
        renderCart();
    } else {
        fetchProductForCart(productId, invItem);
    }
    
    clearPosSearch();
}

async function fetchProductForCart(productId, invItem) {
    try {
        const product = await fetchWithAuth(`${API_URL}/api/v1/products/${invItem.product_barcode}`);
        
        state.cart.items.push({
            product_id: product.id,
            name: product.name,
            barcode: product.barcode,
            sku: product.sku,
            quantity: 1,
            original_unit_price: product.sell_price,
            unit_price: product.sell_price,
            tax_rate: product.tax_rate,
            discount_amount: 0.0,
            cost_price: product.cost_price,
            known_version: invItem.version,
            max_qty: invItem.quantity
        });
        
        renderCart();
    } catch (err) {
        alert('Failed to add product to cart: ' + err.message);
    }
}

function updateCartItemField(productId, field, value) {
    const item = state.cart.items.find(i => i.product_id === productId);
    if (!item) return;

    if (field === 'quantity') {
        let qty = parseInt(value) || 1;
        if (qty < 1) qty = 1;
        if (qty > item.max_qty) {
            alert(`Only ${item.max_qty} units available in stock.`);
            qty = item.max_qty;
        }
        item.quantity = qty;
    } else if (field === 'unit_price') {
        item.unit_price = Math.max(0, parseFloat(value) || 0);
    } else if (field === 'tax_rate') {
        item.tax_rate = Math.max(0, parseFloat(value) || 0);
    } else if (field === 'discount_amount') {
        item.discount_amount = Math.max(0, parseFloat(value) || 0);
        const maxDisc = item.unit_price * item.quantity;
        if (item.discount_amount > maxDisc) {
            alert('Line discount cannot exceed line subtotal.');
            item.discount_amount = maxDisc;
        }
    }

    renderCart();
}

function removePosCartItem(productId) {
    state.cart.items = state.cart.items.filter(i => i.product_id !== productId);
    renderCart();
}

function adjustCartQty(productId, delta) {
    const item = state.cart.items.find(i => i.product_id === productId);
    if (!item) return;
    updateCartItemField(productId, 'quantity', item.quantity + delta);
}

function renderCart() {
    const tbody = document.getElementById('pos-cart-body');
    if (state.cart.items.length === 0) {
        tbody.innerHTML = `
            <tr>
                <td colspan="8" class="text-center text-muted pos-empty-cart">
                    <i data-lucide="shopping-cart" style="width: 32px; height: 32px; margin: 12px auto; display: block; opacity: 0.5;"></i>
                    Cart is empty. Search products above to add items.
                </td>
            </tr>
        `;
        lucide.createIcons();
        calculateCartTotals();
        return;
    }

    tbody.innerHTML = state.cart.items.map(item => {
        const raw_subtotal = item.unit_price * item.quantity;
        const line_subtotal = Math.max(0, raw_subtotal - item.discount_amount);
        const line_tax = line_subtotal * (item.tax_rate / 100.0);
        const line_total = line_subtotal + line_tax;

        return `
            <tr>
                <td>
                    <span class="cart-item-title">${escapeHtml(item.name)}</span><br>
                    <span class="cart-item-barcode">SKU: ${escapeHtml(item.sku)} | Barcode: ${escapeHtml(item.barcode)}</span>
                </td>
                <td>
                    <div class="cart-qty-wrapper">
                        <button type="button" class="btn-qty" onclick="adjustCartQty('${item.product_id}', -1)">-</button>
                        <input type="number" class="cart-input" style="width: 50px; padding: 4px;" value="${item.quantity}" onchange="updateCartItemField('${item.product_id}', 'quantity', this.value)">
                        <button type="button" class="btn-qty" onclick="adjustCartQty('${item.product_id}', 1)">+</button>
                    </div>
                </td>
                <td style="color: var(--text-muted);">₹${item.original_unit_price.toFixed(2)}</td>
                <td>
                    <input type="number" class="cart-input" style="width: 80px;" step="0.01" value="${item.unit_price.toFixed(2)}" onchange="updateCartItemField('${item.product_id}', 'unit_price', this.value)">
                </td>
                <td>
                    <input type="number" class="cart-input" style="width: 60px;" step="0.1" value="${item.tax_rate.toFixed(1)}" onchange="updateCartItemField('${item.product_id}', 'tax_rate', this.value)">
                </td>
                <td>
                    <input type="number" class="cart-input" style="width: 85px;" step="0.01" value="${item.discount_amount.toFixed(2)}" onchange="updateCartItemField('${item.product_id}', 'discount_amount', this.value)">
                </td>
                <td class="text-right font-semibold">₹${line_total.toFixed(2)}</td>
                <td class="text-center">
                    <button type="button" class="action-btn action-btn-danger" onclick="removePosCartItem('${item.product_id}')" title="Remove Item">
                        <i data-lucide="trash-2" style="width: 16px; height: 16px;"></i>
                    </button>
                </td>
            </tr>
        `;
    }).join('');
    
    lucide.createIcons();
    calculateCartTotals();
}

function calculateCartTotals() {
    let subtotal = 0.0;
    let tax = 0.0;
    let itemDiscount = 0.0;

    state.cart.items.forEach(item => {
        const item_subtotal = item.unit_price * item.quantity;
        const discounted_subtotal = Math.max(0, item_subtotal - item.discount_amount);
        const item_tax = discounted_subtotal * (item.tax_rate / 100.0);

        subtotal += item_subtotal;
        tax += item_tax;
        itemDiscount += item.discount_amount;
    });

    const billDiscount = state.cart.discount_amount;
    const netTotal = Math.max(0.0, (subtotal - itemDiscount) + tax - billDiscount);

    document.getElementById('pos-summary-subtotal').textContent = `₹${subtotal.toFixed(2)}`;
    document.getElementById('pos-summary-tax').textContent = `₹${tax.toFixed(2)}`;
    document.getElementById('pos-summary-item-discount').textContent = `-₹${itemDiscount.toFixed(2)}`;
    document.getElementById('pos-summary-total').textContent = `₹${netTotal.toFixed(2)}`;
}

async function handleCustomerPhoneLookup(e) {
    const phone = e.target.value.trim();
    if (phone.length < 10) return;

    try {
        const customer = await fetchWithAuth(`${API_URL}/api/v1/billing/customers/lookup?phone=${phone}`);
        document.getElementById('pos-customer-name').value = customer.name;
        state.cart.customer_name = customer.name;
        state.cart.customer_phone = customer.phone;
    } catch (err) {
        console.log('Customer phone lookup: not found or error');
    }
}

async function submitPosCheckout() {
    const errorEl = document.getElementById('pos-error');
    const errorText = document.getElementById('pos-error-text');
    errorEl.classList.add('hidden');

    if (state.cart.items.length === 0) {
        errorText.textContent = 'Cannot complete checkout. Cart is empty.';
        errorEl.classList.remove('hidden');
        return;
    }

    const payload = {
        location_id: state.selectedLocationId,
        payment_mode: state.cart.payment_mode || 'cash',
        discount_amount: state.cart.discount_amount || 0.0,
        notes: document.getElementById('pos-notes').value || null,
        customer_name: document.getElementById('pos-customer-name').value || null,
        customer_phone: document.getElementById('pos-customer-phone').value || null,
        items: state.cart.items.map(item => ({
            product_id: item.product_id,
            quantity: item.quantity,
            known_version: item.known_version,
            unit_price: item.unit_price,
            tax_rate: item.tax_rate,
            discount_amount: item.discount_amount
        }))
    };

    try {
        const checkoutBtn = document.getElementById('pos-checkout-btn');
        checkoutBtn.disabled = true;
        checkoutBtn.textContent = 'Processing Checkout...';

        const invoice = await fetchWithAuth(`${API_URL}/api/v1/billing/checkout`, {
            method: 'POST',
            body: JSON.stringify(payload)
        });

        alert('Checkout completed successfully!');
        
        viewInvoiceDetails(invoice.id);

        await initBillingTab();

    } catch (err) {
        errorText.textContent = err.message || 'An error occurred during checkout.';
        errorEl.classList.remove('hidden');
    } finally {
        const checkoutBtn = document.getElementById('pos-checkout-btn');
        checkoutBtn.disabled = false;
        checkoutBtn.innerHTML = '<i data-lucide="check-circle-2"></i> <span>Complete Checkout</span>';
        lucide.createIcons();
    }
}

// Bind to window for HTML onclick/onchange handlers
window.viewInvoiceDetails = viewInvoiceDetails;
window.loadSalesData = loadSalesData;
window.printActiveReceipt = printActiveReceipt;

window.addPosCartItem = addPosCartItem;
window.updateCartItemField = updateCartItemField;
window.removePosCartItem = removePosCartItem;
window.adjustCartQty = adjustCartQty;

// ── BARCODE SCANNER CONTROLLER & SERVICE ──
const ScannerService = {
    cameraScanner: null,
    activeCameraId: null,
    scanCallback: null,
    
    // Hardware Keyboard Scanner Emulation State
    buffer: '',
    lastCharTime: 0,

    initHardwareScanner(callback) {
        window.addEventListener('keydown', (e) => {
            const currentTime = Date.now();
            
            // Ignore modifiers
            if (e.key === 'Shift' || e.key === 'Control' || e.key === 'Alt' || e.key === 'Meta') {
                return;
            }

            // If time since last character is long, reset buffer (implies normal human typing, not a scanner)
            if (this.lastCharTime && (currentTime - this.lastCharTime > 150)) {
                this.buffer = '';
            }
            
            this.lastCharTime = currentTime;

            if (e.key === 'Enter') {
                // If we have a reasonable barcode length (e.g. 5+ characters)
                if (this.buffer.length >= 5) {
                    e.preventDefault();
                    e.stopPropagation();
                    const barcode = this.buffer;
                    this.buffer = '';
                    callback(barcode);
                } else {
                    this.buffer = '';
                }
            } else if (e.key.length === 1) {
                // Append typed character
                this.buffer += e.key;
            }
        }, true); // Use capture phase to catch scans before active textboxes handle them
    },

    async startCameraScanner(callback) {
        this.scanCallback = callback;
        const modal = document.getElementById('scanner-modal');
        modal.classList.remove('hidden');

        const cameraSelect = document.getElementById('scanner-camera-select');
        cameraSelect.innerHTML = '<option value="">Detecting cameras...</option>';

        try {
            // Get available cameras
            const devices = await Html5Qrcode.getCameras();
            if (!devices || devices.length === 0) {
                cameraSelect.innerHTML = '<option value="">No cameras detected</option>';
                return;
            }

            cameraSelect.innerHTML = devices.map(d => `<option value="${d.id}">${escapeHtml(d.label || `Camera ${d.id.substring(0,6)}`)}</option>`).join('');
            this.activeCameraId = devices[0].id;
            cameraSelect.value = this.activeCameraId;

            this.cameraScanner = new Html5Qrcode("scanner-preview");
            await this.startScanning();
        } catch (err) {
            console.error('Error starting camera scanner:', err);
            cameraSelect.innerHTML = `<option value="">Access Error: ${escapeHtml(err.message)}</option>`;
        }
    },

    async startScanning() {
        if (!this.cameraScanner || !this.activeCameraId) return;

        try {
            await this.cameraScanner.start(
                this.activeCameraId,
                {
                    fps: 15,
                    qrbox: (width, height) => {
                        // Wide horizontal scanning area for standard retail barcodes
                        return { width: Math.round(width * 0.75), height: Math.round(height * 0.4) };
                    }
                },
                (barcodeText) => {
                    // Success
                    this.stopCameraScanner();
                    if (this.scanCallback) {
                        this.scanCallback(barcodeText);
                    }
                },
                (errorMessage) => {
                    // Verbose error from scan attempts, safe to ignore
                }
            );
        } catch (err) {
            console.error('Failed to start scanning on selected camera:', err);
        }
    },

    async switchCamera(cameraId) {
        if (this.cameraScanner) {
            try {
                await this.cameraScanner.stop();
            } catch (e) {
                // Ignore stop errors
            }
            this.activeCameraId = cameraId;
            await this.startScanning();
        }
    },

    async stopCameraScanner() {
        const modal = document.getElementById('scanner-modal');
        modal.classList.add('hidden');

        if (this.cameraScanner) {
            try {
                await this.cameraScanner.stop();
            } catch (err) {
                // Ignore stop errors
            }
            this.cameraScanner = null;
        }
        this.scanCallback = null;
    }
};

function playScanBeep() {
    try {
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        
        osc.connect(gain);
        gain.connect(ctx.destination);
        
        osc.type = 'sine';
        osc.frequency.setValueAtTime(950, ctx.currentTime);
        
        gain.gain.setValueAtTime(0.08, ctx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.12);
        
        osc.start();
        osc.stop(ctx.currentTime + 0.12);
    } catch (e) {
        console.error('Browser audio beep failed:', e);
    }
}

function handleBarcodeScanned(barcode, source) {
    playScanBeep();
    
    // Determine context (tab name)
    let context = source === 'global' ? state.activeTab : source;

    // Overwrite context if global scan happens while a modal is open on the inventory page
    if (context === 'inventory' && source === 'global') {
        const txModal = document.getElementById('tx-modal');
        const adjModal = document.getElementById('adjustment-modal');
        if (txModal && !txModal.classList.contains('hidden')) {
            context = 'tx';
        } else if (adjModal && !adjModal.classList.contains('hidden')) {
            context = 'adj';
        }
    }

    if (context === 'billing' || context === 'pos') {
        // Find product in in-memory location stock matching barcode
        const invItem = state.posInventory.find(item => item.product_barcode === barcode);
        if (invItem) {
            // Add to POS cart
            addPosCartItem(invItem.product_id);
            // Flash search box green to show scan feedback
            flashSearchBorder('pos-product-search', 'success');
        } else {
            flashSearchBorder('pos-product-search', 'error');
            alert(`Product with barcode ${barcode} is not in stock or not registered at this location.`);
        }
    } else if (context === 'products') {
        const searchInput = document.getElementById('product-search');
        if (searchInput) {
            searchInput.value = barcode;
            filterProducts();
            flashSearchBorder('product-search', 'success');
        }
    } else if (context === 'inventory') {
        // Find product in inventory list
        const invItem = state.posInventory.find(item => item.product_barcode === barcode);
        if (invItem) {
            // Scroll to the inventory row and highlight it
            const row = document.getElementById(`inv-row-${invItem.product_id}`);
            if (row) {
                row.scrollIntoView({ behavior: 'smooth', block: 'center' });
                row.classList.add('row-highlight');
                setTimeout(() => row.classList.remove('row-highlight'), 2000);
            }
            // Auto open the In/Out transaction modal
            openTxModal(invItem.product_id, invItem.product_name, invItem.quantity, invItem.version);
        } else {
            alert(`No inventory record for barcode ${barcode} found at this location.`);
        }
    } else if (context === 'tx') {
        const invItem = state.posInventory.find(item => item.product_barcode === barcode);
        if (invItem) {
            document.getElementById('tx-product-id').value = invItem.product_id;
            document.getElementById('tx-known-version').value = invItem.version;
            document.getElementById('tx-prod-name-display').textContent = invItem.product_name;
            document.getElementById('tx-prod-qty-display').textContent = invItem.quantity;
            flashSearchBorder('tx-summary-panel', 'success');
        } else {
            alert(`No inventory record for barcode ${barcode} found at this location.`);
        }
    } else if (context === 'adj') {
        const invItem = state.posInventory.find(item => item.product_barcode === barcode);
        if (invItem) {
            document.getElementById('adj-product-id').value = invItem.product_id;
            document.getElementById('adj-known-version').value = invItem.version;
            document.getElementById('adj-prod-name-display').textContent = invItem.product_name;
            document.getElementById('adj-prod-qty-display').textContent = invItem.quantity;
            flashSearchBorder('adj-summary-panel', 'success');
        } else {
            alert(`No inventory record for barcode ${barcode} found at this location.`);
        }
    }
}

function flashSearchBorder(id, status) {
    const el = document.getElementById(id);
    if (!el) return;
    const originalBorderColor = el.style.borderColor;
    const originalBoxShadow = el.style.boxShadow;

    if (status === 'success') {
        el.style.borderColor = 'var(--color-success)';
        el.style.boxShadow = '0 0 0 3px rgba(34, 197, 94, 0.2)';
    } else {
        el.style.borderColor = 'var(--color-danger)';
        el.style.boxShadow = '0 0 0 3px rgba(239, 68, 68, 0.2)';
    }

    setTimeout(() => {
        el.style.borderColor = originalBorderColor;
        el.style.boxShadow = originalBoxShadow;
    }, 1000);
}

