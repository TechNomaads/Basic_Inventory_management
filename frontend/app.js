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

    // Pagination for customers
    customerPage: 1,
    customerSize: 20,
    
    // Active inventory location
    selectedLocationId: null,
    
    // Socket.IO instance
    socket: null,

    // Billing/POS Cart State
    cart: {
        items: [],
        customer_name: '',
        customer_phone: '',
        customer_credit_limit: null,
        customer_overdue_amount: null,
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
    document.getElementById('customer-form').addEventListener('submit', handleCustomerSubmit);

    // Customer Tab Bindings
    const customersSearch = document.getElementById('customers-search');
    if (customersSearch) {
        customersSearch.addEventListener('input', debounce(() => {
            state.customerPage = 1;
            loadCustomersData();
        }, 300));
    }
    const btnCustomersPrev = document.getElementById('btn-customers-prev');
    if (btnCustomersPrev) {
        btnCustomersPrev.addEventListener('click', () => changeCustomerPage(-1));
    }
    const btnCustomersNext = document.getElementById('btn-customers-next');
    if (btnCustomersNext) {
        btnCustomersNext.addEventListener('click', () => changeCustomerPage(1));
    }
    const btnAddCustomer = document.getElementById('btn-add-customer');
    if (btnAddCustomer) {
        btnAddCustomer.addEventListener('click', () => openCustomerModal());
    }

    // POS Amount Paid listener
    const posAmountPaid = document.getElementById('pos-amount-paid');
    if (posAmountPaid) {
        posAmountPaid.addEventListener('input', handlePosAmountPaidInput);
    }

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

    // Dashboard interactive cards
    const cardTotalProducts = document.getElementById('card-total-products');
    if (cardTotalProducts) cardTotalProducts.addEventListener('click', () => showMetricDetails('total-products'));

    const cardLowStock = document.getElementById('card-low-stock');
    if (cardLowStock) cardLowStock.addEventListener('click', () => showMetricDetails('low-stock'));

    const cardOutOfStock = document.getElementById('card-out-of-stock');
    if (cardOutOfStock) cardOutOfStock.addEventListener('click', () => showMetricDetails('out-of-stock'));

    const cardTodaysSales = document.getElementById('card-todays-sales');
    if (cardTodaysSales) cardTodaysSales.addEventListener('click', () => showMetricDetails('todays-sales'));

    const cardTodaysRevenue = document.getElementById('card-todays-revenue');
    if (cardTodaysRevenue) cardTodaysRevenue.addEventListener('click', () => showMetricDetails('todays-revenue'));
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
        'sales': 'Sales Invoice History',
        'customers': 'Customer Directory'
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
    } else if (tabName === 'customers') {
        loadCustomersData();
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

// ── CUSTOMERS CONTROLLER ──
async function loadCustomersData() {
    const search = document.getElementById('customers-search').value.trim();
    let url = `${API_URL}/api/v1/customers?page=${state.customerPage}&size=${state.customerSize}`;
    if (search) url += `&search=${encodeURIComponent(search)}`;

    const tbody = document.querySelector('#customers-table tbody');
    tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">Loading customer records...</td></tr>';

    try {
        const [kpis, data] = await Promise.all([
            fetchWithAuth(`${API_URL}/api/v1/customers/kpis`),
            fetchWithAuth(url)
        ]);

        document.getElementById('kpi-customers-count').textContent = kpis.total_count;
        document.getElementById('kpi-customers-overdue').textContent = `₹${kpis.total_overdue.toFixed(2)}`;
        document.getElementById('kpi-customers-credit').textContent = `₹${kpis.total_credit.toFixed(2)}`;

        if (!data.items || data.items.length === 0) {
            tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">No customer records found.</td></tr>';
            document.getElementById('btn-customers-prev').disabled = true;
            document.getElementById('btn-customers-next').disabled = true;
            document.getElementById('customers-pagination-info').textContent = 'Showing 0-0 of 0';
            return;
        }

        tbody.innerHTML = data.items.map(c => {
            const dateStr = new Date(c.created_at).toLocaleDateString([], { dateStyle: 'medium' });
            return `
                <tr>
                    <td><strong>${escapeHtml(c.name)}</strong></td>
                    <td><code>${escapeHtml(c.phone || '—')}</code></td>
                    <td>${c.credit_limit.toFixed(2)}</td>
                    <td class="${c.overdue_amount > 0 ? 'text-danger font-semibold' : 'text-success'}">
                        ₹${c.overdue_amount.toFixed(2)}
                    </td>
                    <td>${dateStr}</td>
                    <td class="text-right">
                        <div style="display: flex; gap: 8px; justify-content: flex-end;">
                            <button class="action-btn action-btn-primary" onclick="window.editCustomer('${c.id}')" title="Edit Profile">
                                <i data-lucide="edit-2" style="width: 16px; height: 16px;"></i>
                            </button>
                            <button class="action-btn" style="color: var(--color-primary);" onclick="window.showCustomerHistory('${c.id}')" title="Purchase History">
                                <i data-lucide="history" style="width: 16px; height: 16px;"></i>
                            </button>
                        </div>
                    </td>
                </tr>
            `;
        }).join('');

        lucide.createIcons();

        const start = (data.page - 1) * data.size + 1;
        const end = Math.min(data.page * data.size, data.total);
        document.getElementById('customers-pagination-info').textContent = `Showing ${start}-${end} of ${data.total}`;
        document.getElementById('btn-customers-prev').disabled = data.page <= 1;
        document.getElementById('btn-customers-next').disabled = data.page >= data.pages;

    } catch (err) {
        tbody.innerHTML = `<tr><td colspan="6" class="text-center text-danger">Error: ${err.message}</td></tr>`;
    }
}

function changeCustomerPage(delta) {
    state.customerPage += delta;
    loadCustomersData();
}

function openCustomerModal(customerId = null) {
    const errorEl = document.getElementById('customer-error');
    errorEl.classList.add('hidden');
    
    const form = document.getElementById('customer-form');
    form.reset();
    
    if (customerId) {
        document.getElementById('customer-modal-title').textContent = 'Edit Customer Profile';
        fetchWithAuth(`${API_URL}/api/v1/customers/${customerId}`)
            .then(c => {
                document.getElementById('customer-id').value = c.id;
                document.getElementById('customer-name').value = c.name;
                document.getElementById('customer-phone').value = c.phone || '';
                document.getElementById('customer-credit-limit').value = c.credit_limit.toFixed(2);
                document.getElementById('customer-overdue').value = c.overdue_amount.toFixed(2);
                
                openModal('customer-modal');
                lucide.createIcons();
            })
            .catch(err => {
                alert(`Error loading customer: ${err.message}`);
            });
    } else {
        document.getElementById('customer-modal-title').textContent = 'Add New Customer';
        document.getElementById('customer-id').value = '';
        document.getElementById('customer-credit-limit').value = '10000.00';
        document.getElementById('customer-overdue').value = '0.00';
        openModal('customer-modal');
        lucide.createIcons();
    }
}

async function handleCustomerSubmit(e) {
    e.preventDefault();
    const errorEl = document.getElementById('customer-error');
    const errorText = document.getElementById('customer-error-text');
    errorEl.classList.add('hidden');

    const customerId = document.getElementById('customer-id').value;
    const payload = {
        name: document.getElementById('customer-name').value.trim(),
        phone: document.getElementById('customer-phone').value.trim() || null,
        credit_limit: parseFloat(document.getElementById('customer-credit-limit').value) || 0.0,
        overdue_amount: parseFloat(document.getElementById('customer-overdue').value) || 0.0
    };

    try {
        let url = `${API_URL}/api/v1/customers`;
        let method = 'POST';
        
        if (customerId) {
            url += `/${customerId}`;
            method = 'PUT';
        }

        await fetchWithAuth(url, {
            method: method,
            body: JSON.stringify(payload)
        });

        closeModal('customer-modal');
        loadCustomersData();
    } catch (err) {
        errorText.textContent = err.message || 'An error occurred while saving customer profile.';
        errorEl.classList.remove('hidden');
    }
}

async function showCustomerHistory(id) {
    try {
        const c = await fetchWithAuth(`${API_URL}/api/v1/customers/${id}`);
        
        document.getElementById('customer-history-title').textContent = `${escapeHtml(c.name)} - Purchase History`;
        document.getElementById('hist-customer-phone').textContent = escapeHtml(c.phone || '—');
        document.getElementById('hist-customer-limit').textContent = `₹${c.credit_limit.toFixed(2)}`;
        document.getElementById('hist-customer-overdue').textContent = `₹${c.overdue_amount.toFixed(2)}`;

        const tbody = document.getElementById('customer-history-table-body');
        if (!c.invoices || c.invoices.length === 0) {
            tbody.innerHTML = '<tr><td colspan="11" class="text-center text-muted">No invoices found for this customer.</td></tr>';
        } else {
            tbody.innerHTML = c.invoices.map(inv => {
                const dateStr = new Date(inv.created_at).toLocaleString([], { dateStyle: 'short', timeStyle: 'short' });
                const dueAmount = inv.total_amount - inv.amount_paid;
                const statusTag = dueAmount <= 0.01 
                    ? `<span class="badge badge-green">Fully Paid</span>` 
                    : `<span class="badge badge-amber">Credit Due</span>`;
                
                return `
                    <tr>
                        <td><strong>${escapeHtml(inv.invoice_no)}</strong></td>
                        <td>${dateStr}</td>
                        <td>${escapeHtml(inv.location_name || 'N/A')}</td>
                        <td>${inv.subtotal.toFixed(2)}</td>
                        <td>${inv.tax_amount.toFixed(2)}</td>
                        <td>${inv.discount_amount.toFixed(2)}</td>
                        <td class="font-semibold">₹${inv.total_amount.toFixed(2)}</td>
                        <td class="text-success font-semibold">₹${inv.amount_paid.toFixed(2)}</td>
                        <td class="text-danger font-semibold">₹${dueAmount.toFixed(2)}</td>
                        <td>${statusTag}</td>
                        <td class="text-right">
                            <button class="action-btn" onclick="window.viewInvoiceDetails('${inv.id}')" title="View Details">
                                <i data-lucide="eye" style="width: 16px; height: 16px;"></i>
                            </button>
                        </td>
                    </tr>
                `;
            }).join('');
        }

        lucide.createIcons();
        openModal('customer-history-modal');
    } catch (err) {
        alert(`Error fetching history: ${err.message}`);
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

        const amountPaid = invoice.amount_paid || 0.0;
        const amountDue = Math.max(0.0, invoice.total_amount - amountPaid);
        document.getElementById('inv-detail-paid').textContent = `₹${amountPaid.toFixed(2)}`;
        document.getElementById('inv-detail-due').textContent = `₹${amountDue.toFixed(2)}`;

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
        customer_credit_limit: null,
        customer_overdue_amount: null,
        amount_paid_edited: false,
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
    document.getElementById('pos-amount-paid').value = '0.00';
    document.getElementById('pos-search-clear').classList.add('hidden');
    document.getElementById('pos-search-results').classList.add('hidden');
    document.getElementById('pos-error').classList.add('hidden');
    document.getElementById('pos-customer-credit-info').classList.add('hidden');
    document.getElementById('pos-credit-warning').classList.add('hidden');
    document.getElementById('pos-amount-due-row').style.display = 'none';
    document.getElementById('pos-checkout-btn').disabled = false;

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

    // Set default amount paid if user hasn't edited it manually
    const paidInput = document.getElementById('pos-amount-paid');
    if (paidInput && !state.cart.amount_paid_edited) {
        paidInput.value = netTotal.toFixed(2);
    }
    recalculateAmountPaidAndValidate();
}

async function handleCustomerPhoneLookup(e) {
    const phone = e.target.value.trim();
    
    if (phone.length === 0) {
        state.cart.customer_name = '';
        state.cart.customer_phone = '';
        state.cart.customer_credit_limit = null;
        state.cart.customer_overdue_amount = null;
        document.getElementById('pos-customer-name').value = '';
        document.getElementById('pos-customer-credit-info').classList.add('hidden');
        document.getElementById('pos-credit-warning').classList.add('hidden');
        recalculateAmountPaidAndValidate();
        return;
    }

    if (phone.length < 10) return;

    try {
        const customer = await fetchWithAuth(`${API_URL}/api/v1/billing/customers/lookup?phone=${phone}`);
        document.getElementById('pos-customer-name').value = customer.name;
        state.cart.customer_name = customer.name;
        state.cart.customer_phone = customer.phone;
        state.cart.customer_credit_limit = customer.credit_limit;
        state.cart.customer_overdue_amount = customer.overdue_amount;
        
        document.getElementById('pos-credit-overdue').textContent = `₹${customer.overdue_amount.toFixed(2)}`;
        document.getElementById('pos-credit-limit').textContent = `₹${customer.credit_limit.toFixed(2)}`;
        document.getElementById('pos-customer-credit-info').classList.remove('hidden');
        
        // Default amount paid to net total
        const totalText = document.getElementById('pos-summary-total').textContent.replace('₹', '');
        const netTotal = parseFloat(totalText) || 0.0;
        document.getElementById('pos-amount-paid').value = netTotal.toFixed(2);
        
        recalculateAmountPaidAndValidate();
    } catch (err) {
        console.log('Customer phone lookup: not found or error', err);
        state.cart.customer_credit_limit = null;
        state.cart.customer_overdue_amount = null;
        document.getElementById('pos-customer-credit-info').classList.add('hidden');
        document.getElementById('pos-credit-warning').classList.add('hidden');
        recalculateAmountPaidAndValidate();
    }
}

function handlePosAmountPaidInput(e) {
    state.cart.amount_paid_edited = true;
    recalculateAmountPaidAndValidate();
}

function recalculateAmountPaidAndValidate() {
    const paidInput = document.getElementById('pos-amount-paid');
    if (!paidInput) return;

    const totalText = document.getElementById('pos-summary-total').textContent.replace('₹', '');
    const netTotal = parseFloat(totalText) || 0.0;
    
    let paidVal = parseFloat(paidInput.value);
    if (isNaN(paidVal) || paidVal < 0) {
        paidVal = 0.0;
    }

    const remaining = netTotal - paidVal;
    
    const amountDueRow = document.getElementById('pos-amount-due-row');
    const amountDueLabel = document.getElementById('pos-amount-due-label');
    const amountDueVal = document.getElementById('pos-amount-due-val');
    const creditWarning = document.getElementById('pos-credit-warning');
    const checkoutBtn = document.getElementById('pos-checkout-btn');
    
    // Reset state
    amountDueRow.style.display = 'none';
    creditWarning.classList.add('hidden');
    checkoutBtn.disabled = false;
    
    const hasCustomer = !!state.cart.customer_phone;
    
    if (Math.abs(remaining) > 0.005) {
        amountDueRow.style.display = 'flex';
        amountDueVal.textContent = `₹${Math.abs(remaining).toFixed(2)}`;
        
        if (remaining > 0) {
            amountDueLabel.textContent = 'Remaining Balance (Due):';
            amountDueVal.style.color = 'var(--color-danger)';
        } else {
            amountDueLabel.textContent = 'Excess Payment (Credit):';
            amountDueVal.style.color = 'var(--color-success)';
        }
    }
    
    if (!hasCustomer) {
        if (Math.abs(remaining) > 0.01) {
            checkoutBtn.disabled = true;
            const errorEl = document.getElementById('pos-error');
            const errorText = document.getElementById('pos-error-text');
            errorText.textContent = 'Walk-in customer must pay the net total amount in full.';
            errorEl.classList.remove('hidden');
        } else {
            document.getElementById('pos-error').classList.add('hidden');
        }
    } else {
        document.getElementById('pos-error').classList.add('hidden');
        const currentOverdue = state.cart.customer_overdue_amount || 0.0;
        const creditLimit = state.cart.customer_credit_limit || 0.0;
        
        const nextOverdue = currentOverdue + remaining;
        if (nextOverdue > creditLimit) {
            creditWarning.classList.remove('hidden');
            checkoutBtn.disabled = true;
        }
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

    const amountPaidVal = parseFloat(document.getElementById('pos-amount-paid').value);

    const payload = {
        location_id: state.selectedLocationId,
        payment_mode: state.cart.payment_mode || 'cash',
        amount_paid: isNaN(amountPaidVal) ? null : amountPaidVal,
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

window.editCustomer = editCustomer;
window.showCustomerHistory = showCustomerHistory;
window.loadCustomersData = loadCustomersData;
window.openCustomerModal = openCustomerModal;

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

// ── INTERACTIVE DASHBOARD METRICS DETAIL MODAL ──
async function showMetricDetails(metricType) {
    openModal('metric-detail-modal');

    const titleEl = document.getElementById('metric-detail-title');
    const summaryContainer = document.getElementById('metric-summary-container');
    const chartContainer = document.getElementById('metric-chart-container');
    const tableHeader = document.getElementById('metric-detail-table-header');
    const tableBody = document.getElementById('metric-detail-table-body');

    // Loading states
    summaryContainer.innerHTML = '<div class="text-muted">Loading metrics...</div>';
    chartContainer.innerHTML = `
        <div style="display: flex; flex-direction: column; align-items: center; gap: 12px; color: var(--text-muted);">
            <div class="spinner"></div>
            <span>Generating visualization...</span>
        </div>
    `;
    tableHeader.innerHTML = '';
    tableBody.innerHTML = '<tr><td class="text-center text-muted">Loading data...</td></tr>';

    try {
        if (metricType === 'total-products') {
            titleEl.textContent = 'Total Unique Products Details';

            // Fetch products
            const response = await fetchWithAuth(`${API_URL}/api/v1/products?page=1&size=100`);
            const products = response.items || [];

            // Category breakdown
            const catMap = {};
            products.forEach(p => {
                const cat = p.category_name || 'Uncategorized';
                catMap[cat] = (catMap[cat] || 0) + 1;
            });

            // Summary
            summaryContainer.innerHTML = `
                <div class="metric-kpi-card" style="flex: 1; min-width: 140px; padding: 15px; border: 1px solid var(--border-color); border-radius: var(--radius-md); background: var(--bg-card);">
                    <div class="text-hint text-xs font-semibold">TOTAL UNIQUE</div>
                    <div class="text-primary text-2xl font-bold" style="font-family: var(--font-display);">${products.length}</div>
                </div>
                <div class="metric-kpi-card" style="flex: 1; min-width: 140px; padding: 15px; border: 1px solid var(--border-color); border-radius: var(--radius-md); background: var(--bg-card);">
                    <div class="text-hint text-xs font-semibold">CATEGORIES</div>
                    <div class="text-secondary text-2xl font-bold" style="font-family: var(--font-display); color: var(--color-secondary);">${Object.keys(catMap).length}</div>
                </div>
                <div class="metric-kpi-card" style="flex: 1; min-width: 140px; padding: 15px; border: 1px solid var(--border-color); border-radius: var(--radius-md); background: var(--bg-card);">
                    <div class="text-hint text-xs font-semibold">AVG BASE PRICE</div>
                    <div class="text-success text-2xl font-bold" style="font-family: var(--font-display);">₹${(products.reduce((acc, p) => acc + (p.sell_price || 0), 0) / (products.length || 1)).toFixed(2)}</div>
                </div>
            `;

            // Chart
            chartContainer.innerHTML = drawCategoryBreakdownChart(catMap);

            // Table
            tableHeader.innerHTML = `
                <th>Product Name</th>
                <th>SKU</th>
                <th>Category</th>
                <th>Price</th>
                <th>Barcode</th>
            `;
            tableBody.innerHTML = products.map(p => `
                <tr>
                    <td><strong>${escapeHtml(p.name)}</strong></td>
                    <td>${escapeHtml(p.sku)}</td>
                    <td><span class="badge" style="background: var(--bg-base); color: var(--text-primary); font-size: 11px;">${escapeHtml(p.category_name || 'N/A')}</span></td>
                    <td>₹${(p.sell_price || 0).toFixed(2)}</td>
                    <td><code style="font-size: 12px; color: var(--text-muted);">${escapeHtml(p.barcode)}</code></td>
                </tr>
            `).join('');

        } else if (metricType === 'low-stock' || metricType === 'out-of-stock') {
            const isOutOfStock = metricType === 'out-of-stock';
            titleEl.textContent = isOutOfStock ? 'Out of Stock Items Details' : 'Low Stock Items Details';

            // Fetch inventory across all locations
            let locations = state.locations;
            if (!locations || locations.length === 0) {
                locations = await fetchWithAuth(`${API_URL}/api/v1/inventory/meta/locations`);
            }
            
            let items = [];
            for (const loc of locations) {
                try {
                    const locItems = await fetchWithAuth(`${API_URL}/api/v1/inventory/${loc.id}`);
                    items = items.concat(locItems);
                } catch (e) {
                    console.error(`Error loading inventory for location ${loc.name}:`, e);
                }
            }
            
            // Filter
            const filtered = items.filter(item => {
                if (isOutOfStock) {
                    return item.quantity <= 0;
                } else {
                    return item.quantity < item.min_quantity && item.min_quantity > 0;
                }
            });

            // Summary
            summaryContainer.innerHTML = `
                <div class="metric-kpi-card" style="flex: 1; min-width: 140px; padding: 15px; border: 1px solid var(--border-color); border-radius: var(--radius-md); background: var(--bg-card);">
                    <div class="text-hint text-xs font-semibold">${isOutOfStock ? 'TOTAL OUT OF STOCK' : 'TOTAL LOW STOCK'}</div>
                    <div class="text-danger text-2xl font-bold" style="font-family: var(--font-display);">${filtered.length}</div>
                </div>
                <div class="metric-kpi-card" style="flex: 1; min-width: 140px; padding: 15px; border: 1px solid var(--border-color); border-radius: var(--radius-md); background: var(--bg-card);">
                    <div class="text-hint text-xs font-semibold">AFFECTED LOCATIONS</div>
                    <div class="text-muted text-lg font-bold" style="padding-top: 4px; font-family: var(--font-display);">
                        ${new Set(filtered.map(i => i.location_name)).size} Locations
                    </div>
                </div>
            `;

            if (filtered.length === 0) {
                chartContainer.innerHTML = `<div class="text-muted">No items to visualize. All stocks healthy!</div>`;
                tableBody.innerHTML = `<tr><td colspan="6" class="text-center text-muted">No items in this category.</td></tr>`;
                tableHeader.innerHTML = `<th>Product</th><th>Location</th><th>Barcode</th><th>Stock Level</th><th>Min Stock</th>`;
                return;
            }

            // Chart
            chartContainer.innerHTML = drawStockComparisonChart(filtered);

            // Table
            tableHeader.innerHTML = `
                <th>Product Name</th>
                <th>Location</th>
                <th>Category</th>
                <th>Stock Level</th>
                <th>Min Stock</th>
                <th>Status</th>
            `;
            tableBody.innerHTML = filtered.map(item => `
                <tr class="${item.quantity === 0 ? 'bg-danger-soft' : ''}">
                    <td><strong>${escapeHtml(item.product_name || 'N/A')}</strong></td>
                    <td><span class="badge" style="background: var(--bg-base); color: var(--text-primary); font-size: 11px;">${escapeHtml(item.location_name)}</span></td>
                    <td>${escapeHtml(item.product_category || 'N/A')}</td>
                    <td class="font-semibold ${item.quantity === 0 ? 'text-danger' : 'text-warning'}">${item.quantity}</td>
                    <td>${item.min_quantity}</td>
                    <td>
                        <span class="badge ${item.stock_status === 'red' ? 'text-danger bg-danger-soft' : 'text-warning bg-warning-soft'}" style="font-size: 11px; padding: 4px 8px; border-radius: var(--radius-full);">
                            ${item.stock_status === 'red' ? 'CRITICAL' : 'WARNING'}
                        </span>
                    </td>
                </tr>
            `).join('');

        } else if (metricType === 'todays-sales' || metricType === 'todays-revenue') {
            const isRevenue = metricType === 'todays-revenue';
            titleEl.textContent = isRevenue ? "Today's Revenue Breakdown" : "Today's Sales Breakdown";

            // Fetch invoices
            const invoices = await fetchWithAuth(`${API_URL}/api/v1/billing/invoices?skip=0&limit=100`);
            
            // Filter today's invoices
            const todayStr = new Date().toDateString();
            const todayInvoices = invoices.filter(inv => new Date(inv.created_at).toDateString() === todayStr);

            // Totals
            const salesCount = todayInvoices.length;
            const totalRevenue = todayInvoices.reduce((acc, inv) => acc + inv.total_amount, 0);
            const averageValue = salesCount > 0 ? totalRevenue / salesCount : 0;

            const modeMap = { cash: 0, card: 0, upi: 0 };
            todayInvoices.forEach(inv => {
                const mode = inv.payment_mode ? inv.payment_mode.toLowerCase() : 'cash';
                modeMap[mode] = (modeMap[mode] || 0) + inv.total_amount;
            });

            // Summary
            summaryContainer.innerHTML = `
                <div class="metric-kpi-card" style="flex: 1; min-width: 140px; padding: 15px; border: 1px solid var(--border-color); border-radius: var(--radius-md); background: var(--bg-card);">
                    <div class="text-hint text-xs font-semibold">TODAY'S SALES COUNT</div>
                    <div class="text-accent text-2xl font-bold" style="font-family: var(--font-display); color: var(--color-secondary);">${salesCount}</div>
                </div>
                <div class="metric-kpi-card" style="flex: 1; min-width: 140px; padding: 15px; border: 1px solid var(--border-color); border-radius: var(--radius-md); background: var(--bg-card);">
                    <div class="text-hint text-xs font-semibold">TODAY'S REVENUE</div>
                    <div class="text-success text-2xl font-bold" style="font-family: var(--font-display);">₹${totalRevenue.toFixed(2)}</div>
                </div>
                <div class="metric-kpi-card" style="flex: 1; min-width: 140px; padding: 15px; border: 1px solid var(--border-color); border-radius: var(--radius-md); background: var(--bg-card);">
                    <div class="text-hint text-xs font-semibold">AVERAGE ORDER VALUE</div>
                    <div class="text-primary text-2xl font-bold" style="font-family: var(--font-display);">₹${averageValue.toFixed(2)}</div>
                </div>
            `;

            if (salesCount === 0) {
                chartContainer.innerHTML = `<div class="text-muted">No sales processed today yet.</div>`;
                tableBody.innerHTML = `<tr><td colspan="7" class="text-center text-muted">No invoices found for today.</td></tr>`;
                tableHeader.innerHTML = `<th>Invoice #</th><th>Customer</th><th>Total Amount</th><th>Payment Mode</th>`;
                return;
            }

            // Chart
            if (isRevenue) {
                chartContainer.innerHTML = drawRevenueDonutChart(modeMap);
            } else {
                chartContainer.innerHTML = drawHourlySalesChart(todayInvoices);
            }

            // Table
            tableHeader.innerHTML = `
                <th>Invoice No.</th>
                <th>Time</th>
                <th>Customer</th>
                <th>Subtotal</th>
                <th>Discount</th>
                <th>Total Paid</th>
                <th>Payment Mode</th>
            `;
            tableBody.innerHTML = todayInvoices.map(inv => {
                const timeStr = new Date(inv.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
                return `
                    <tr>
                        <td><strong>${escapeHtml(inv.invoice_number)}</strong></td>
                        <td>${timeStr}</td>
                        <td>${escapeHtml(inv.customer_name || 'Walk-in Customer')}<br><span class="text-hint text-xs">${inv.customer_phone || '—'}</span></td>
                        <td>₹${inv.subtotal.toFixed(2)}</td>
                        <td class="text-danger">-₹${inv.discount_amount.toFixed(2)}</td>
                        <td class="font-semibold text-success">₹${inv.total_amount.toFixed(2)}</td>
                        <td>
                            <span class="badge" style="font-size: 11px; font-weight:600; padding: 3px 8px; border-radius:var(--radius-full);
                                background: ${inv.payment_mode === 'upi' ? '#eff6ff' : inv.payment_mode === 'card' ? '#f0f9ff' : '#f0fdf4'};
                                color: ${inv.payment_mode === 'upi' ? '#2563eb' : inv.payment_mode === 'card' ? '#0284c7' : '#16a34a'};">
                                ${inv.payment_mode.toUpperCase()}
                            </span>
                        </td>
                    </tr>
                `;
            }).join('');
        }

        // Initialize Lucide icons in the dynamically loaded elements
        lucide.createIcons();

    } catch (err) {
        console.error('Error fetching metric details:', err);
        tableBody.innerHTML = `<tr><td colspan="7" class="text-center text-danger">Failed to load detailed data: ${err.message}</td></tr>`;
    }
}

// ── SVG CHART GENERATORS ──
function drawCategoryBreakdownChart(catMap) {
    const categories = Object.keys(catMap);
    const counts = Object.values(catMap);
    const maxCount = Math.max(...counts, 1);

    const svgWidth = 650;
    const svgHeight = 220;
    const barWidth = 40;
    const spacing = 35;
    const startX = 60;
    const chartBottom = 170;

    let barsHTML = '';
    categories.forEach((cat, index) => {
        const count = catMap[cat];
        const barHeight = (count / maxCount) * 120;
        const x = startX + index * (barWidth + spacing);
        const y = chartBottom - barHeight;

        // Clean label
        const truncatedLabel = cat.length > 10 ? cat.substring(0, 9) + '..' : cat;

        barsHTML += `
            <!-- Grid value text -->
            <text x="${x + barWidth / 2}" y="${y - 8}" text-anchor="middle" font-size="12" font-weight="bold" fill="var(--text-primary)">${count}</text>
            <!-- Animated Bar -->
            <rect x="${x}" y="${y}" width="${barWidth}" height="${barHeight}" fill="url(#blueGradient)" rx="4" ry="4">
                <animate attributeName="height" from="0" to="${barHeight}" dur="0.6s" fill="freeze" />
                <animate attributeName="y" from="${chartBottom}" to="${y}" dur="0.6s" fill="freeze" />
            </rect>
            <!-- Label -->
            <text x="${x + barWidth / 2}" y="${chartBottom + 20}" text-anchor="middle" font-size="11" fill="var(--text-muted)">${escapeHtml(truncatedLabel)}</text>
        `;
    });

    return `
        <svg viewBox="0 0 ${svgWidth} ${svgHeight}" width="100%" height="220" style="font-family: var(--font-body);">
            <defs>
                <linearGradient id="blueGradient" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stop-color="#2563eb" />
                    <stop offset="100%" stop-color="#3b82f6" stop-opacity="0.8" />
                </linearGradient>
            </defs>
            <!-- Gridlines -->
            <line x1="40" y1="50" x2="${svgWidth - 20}" y2="50" stroke="var(--border-color)" stroke-dasharray="3,3" />
            <line x1="40" y1="110" x2="${svgWidth - 20}" y2="110" stroke="var(--border-color)" stroke-dasharray="3,3" />
            <line x1="40" y1="${chartBottom}" x2="${svgWidth - 20}" y2="${chartBottom}" stroke="var(--border-color)" />
            
            ${barsHTML}
        </svg>
    `;
}

function drawStockComparisonChart(items) {
    // Show top 7 critical products
    const limitItems = items.slice(0, 7);
    const svgWidth = 650;
    const svgHeight = 220;
    
    const chartLeft = 200; // wider to fit "Product (Location)"
    const chartWidth = 410;
    const barHeight = 16;
    const rowHeight = 24;
    const startY = 20;

    let rowsHTML = '';
    limitItems.forEach((item, index) => {
        const y = startY + index * rowHeight;
        const maxVal = Math.max(item.min_quantity * 1.5, 10);
        
        const minValX = chartLeft + (item.min_quantity / maxVal) * chartWidth;
        const qtyX = (item.quantity / maxVal) * chartWidth;

        // Color class
        const barColor = item.quantity === 0 ? '#ef4444' : '#f59e0b';
        const fullLabel = `${item.product_name || 'N/A'} (${item.location_name})`;
        const label = fullLabel.length > 25 ? fullLabel.substring(0, 24) + '..' : fullLabel;

        rowsHTML += `
            <text x="${chartLeft - 10}" y="${y + 12}" text-anchor="end" font-size="10" fill="var(--text-muted)">${escapeHtml(label)}</text>
            
            <!-- Min stock indicator (gray background wedge) -->
            <rect x="${chartLeft}" y="${y}" width="${(item.min_quantity / maxVal) * chartWidth}" height="${barHeight}" fill="#f1f5f9" rx="2" stroke="#cbd5e1" stroke-dasharray="2,2"/>
            
            <!-- Current Stock (colored) -->
            <rect x="${chartLeft}" y="${y}" width="0" height="${barHeight}" fill="${barColor}" rx="2">
                <animate attributeName="width" from="0" to="${qtyX}" dur="0.6s" fill="freeze" />
            </rect>
            
            <!-- Target line indicator -->
            <line x1="${minValX}" y1="${y - 2}" x2="${minValX}" y2="${y + barHeight + 2}" stroke="#dc2626" stroke-width="1.5" />
            
            <text x="${chartLeft + Math.max(qtyX, 10) + 6}" y="${y + 12}" font-size="11" font-weight="bold" fill="var(--text-primary)">
                ${item.quantity} / ${item.min_quantity}
            </text>
        `;
    });

    return `
        <svg viewBox="0 0 ${svgWidth} ${svgHeight}" width="100%" height="220" style="font-family: var(--font-body);">
            ${rowsHTML}
            <!-- X-axis baseline -->
            <line x1="${chartLeft}" y1="10" x2="${chartLeft}" y2="${startY + limitItems.length * rowHeight}" stroke="var(--border-color)" />
            <!-- Legend -->
            <g transform="translate(${chartLeft}, ${startY + limitItems.length * rowHeight + 15})">
                <rect x="0" y="0" width="10" height="10" fill="#f1f5f9" stroke="#cbd5e1" stroke-dasharray="2,2" />
                <text x="15" y="9" font-size="10" fill="var(--text-muted)">Min Level</text>
                
                <rect x="80" y="0" width="10" height="10" fill="#ef4444" />
                <text x="95" y="9" font-size="10" fill="var(--text-muted)">Out of Stock</text>

                <rect x="170" y="0" width="10" height="10" fill="#f59e0b" />
                <text x="185" y="9" font-size="10" fill="var(--text-muted)">Low Stock</text>
            </g>
        </svg>
    `;
}

function drawRevenueDonutChart(modeMap) {
    const total = modeMap.cash + modeMap.card + modeMap.upi;
    const upiPercent = total > 0 ? (modeMap.upi / total) * 100 : 0;
    const cardPercent = total > 0 ? (modeMap.card / total) * 100 : 0;
    const cashPercent = total > 0 ? (modeMap.cash / total) * 100 : 0;

    const r = 55;
    const cx = 110;
    const cy = 110;
    const C = 2 * Math.PI * r; // ~345.57

    // Percentages to strokes
    const upiStroke = (upiPercent / 100) * C;
    const cardStroke = (cardPercent / 100) * C;
    const cashStroke = (cashPercent / 100) * C;

    // Offsets
    const upiOffset = C;
    const cardOffset = C - upiStroke;
    const cashOffset = C - upiStroke - cardStroke;

    return `
        <div style="display: flex; align-items: center; justify-content: center; gap: 40px; flex-wrap: wrap; width: 100%; padding: 10px;">
            <svg width="220" height="220" viewBox="0 0 220 220" style="transform: rotate(-90deg);">
                <!-- Background Circle -->
                <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="var(--border-color)" stroke-width="20" />
                
                <!-- UPI Segment (Cobalt Blue) -->
                ${upiStroke > 0 ? `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="#2563eb" stroke-width="20"
                    stroke-dasharray="${upiStroke} ${C - upiStroke}" 
                    stroke-dashoffset="${upiOffset}" 
                    style="transition: stroke-dashoffset 0.6s ease;"/>` : ''}
                
                <!-- Card Segment (Sky Blue) -->
                ${cardStroke > 0 ? `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="#0284c7" stroke-width="20"
                    stroke-dasharray="${cardStroke} ${C - cardStroke}" 
                    stroke-dashoffset="${cardOffset}"
                    style="transition: stroke-dashoffset 0.6s ease;"/>` : ''}
                
                <!-- Cash Segment (Emerald Green) -->
                ${cashStroke > 0 ? `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="#16a34a" stroke-width="20"
                    stroke-dasharray="${cashStroke} ${C - cashStroke}" 
                    stroke-dashoffset="${cashOffset}"
                    style="transition: stroke-dashoffset 0.6s ease;"/>` : ''}

                <!-- Center Hole Text (Needs rotation back to display properly) -->
                <g transform="rotate(90, ${cx}, ${cy})">
                    <text x="${cx}" y="${cy - 4}" text-anchor="middle" font-size="11" font-weight="bold" fill="var(--text-hint)">TOTAL</text>
                    <text x="${cx}" y="${cy + 14}" text-anchor="middle" font-size="14" font-weight="800" fill="var(--text-primary)" style="font-family: var(--font-display);">₹${total.toFixed(0)}</text>
                </g>
            </svg>
            
            <div style="display: flex; flex-direction: column; gap: 15px; min-width: 180px;">
                <div style="display: flex; align-items: center; gap: 10px;">
                    <span style="width: 12px; height: 12px; border-radius: 4px; background: #2563eb;"></span>
                    <span style="flex: 1; font-size: 13px; color: var(--text-muted);">UPI Payments</span>
                    <strong style="font-size: 13px; fill: var(--text-primary);">₹${modeMap.upi.toFixed(2)} (${upiPercent.toFixed(0)}%)</strong>
                </div>
                <div style="display: flex; align-items: center; gap: 10px;">
                    <span style="width: 12px; height: 12px; border-radius: 4px; background: #0284c7;"></span>
                    <span style="flex: 1; font-size: 13px; color: var(--text-muted);">Card Payments</span>
                    <strong style="font-size: 13px; fill: var(--text-primary);">₹${modeMap.card.toFixed(2)} (${cardPercent.toFixed(0)}%)</strong>
                </div>
                <div style="display: flex; align-items: center; gap: 10px;">
                    <span style="width: 12px; height: 12px; border-radius: 4px; background: #16a34a;"></span>
                    <span style="flex: 1; font-size: 13px; color: var(--text-muted);">Cash Payments</span>
                    <strong style="font-size: 13px; fill: var(--text-primary);">₹${modeMap.cash.toFixed(2)} (${cashPercent.toFixed(0)}%)</strong>
                </div>
            </div>
        </div>
    `;
}

function drawHourlySalesChart(invoices) {
    // Hour buckets from 00 to 23
    const hours = Array(24).fill(0);
    invoices.forEach(inv => {
        const hour = new Date(inv.created_at).getHours();
        hours[hour] += 1;
    });

    // Find first and last hour with sales to crop empty timeline ends
    let startHour = 8;
    let endHour = 20;

    for (let h = 0; h < 24; h++) {
        if (hours[h] > 0) {
            startHour = Math.min(startHour, h);
            endHour = Math.max(endHour, h);
        }
    }
    
    // Add margin
    startHour = Math.max(0, startHour - 1);
    endHour = Math.min(23, endHour + 1);
    const range = endHour - startHour + 1;

    const svgWidth = 650;
    const svgHeight = 220;
    const paddingLeft = 40;
    const paddingRight = 30;
    const paddingTop = 30;
    const paddingBottom = 40;

    const chartWidth = svgWidth - paddingLeft - paddingRight;
    const chartHeight = svgHeight - paddingTop - paddingBottom;

    const activeHours = [];
    for (let h = startHour; h <= endHour; h++) {
        activeHours.push(h);
    }

    const maxCount = Math.max(...activeHours.map(h => hours[h]), 1);

    // Build line coordinates
    const points = [];
    activeHours.forEach((hour, i) => {
        const val = hours[hour];
        const x = paddingLeft + (i / (range - 1)) * chartWidth;
        const y = paddingTop + chartHeight - (val / maxCount) * chartHeight;
        points.push({ x, y, hour, val });
    });

    let pathD = `M ${points[0].x} ${points[0].y}`;
    for (let i = 1; i < points.length; i++) {
        pathD += ` L ${points[i].x} ${points[i].y}`;
    }
    
    // Create closed path for area gradient fill
    const areaD = `${pathD} L ${points[points.length - 1].x} ${paddingTop + chartHeight} L ${points[0].x} ${paddingTop + chartHeight} Z`;

    let markersHTML = '';
    points.forEach(pt => {
        const label = `${pt.hour.toString().padStart(2, '0')}:00`;
        markersHTML += `
            <circle cx="${pt.x}" cy="${pt.y}" r="4" fill="var(--color-primary)" stroke="#ffffff" stroke-width="1.5" />
            ${pt.val > 0 ? `<text x="${pt.x}" y="${pt.y - 8}" text-anchor="middle" font-size="11" font-weight="bold" fill="var(--text-primary)">${pt.val}</text>` : ''}
            <text x="${pt.x}" y="${paddingTop + chartHeight + 18}" text-anchor="middle" font-size="10" fill="var(--text-muted)">${label}</text>
        `;
    });

    return `
        <svg viewBox="0 0 ${svgWidth} ${svgHeight}" width="100%" height="220" style="font-family: var(--font-body);">
            <defs>
                <linearGradient id="areaGradient" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stop-color="#2563eb" stop-opacity="0.3" />
                    <stop offset="100%" stop-color="#2563eb" stop-opacity="0.0" />
                </linearGradient>
            </defs>
            <!-- Y Gridlines -->
            <line x1="${paddingLeft}" y1="${paddingTop}" x2="${svgWidth - paddingRight}" y2="${paddingTop}" stroke="var(--border-color)" stroke-dasharray="3,3" />
            <line x1="${paddingLeft}" y1="${paddingTop + chartHeight / 2}" x2="${svgWidth - paddingRight}" y2="${paddingTop + chartHeight / 2}" stroke="var(--border-color)" stroke-dasharray="3,3" />
            <line x1="${paddingLeft}" y1="${paddingTop + chartHeight}" x2="${svgWidth - paddingRight}" y2="${paddingTop + chartHeight}" stroke="var(--border-color)" />

            <!-- Area Path with Gradient -->
            <path d="${areaD}" fill="url(#areaGradient)">
                <animate attributeName="opacity" from="0" to="1" dur="0.8s" />
            </path>

            <!-- Line Path -->
            <path d="${pathD}" fill="none" stroke="#2563eb" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                <animate attributeName="stroke-dashoffset" from="1000" to="0" dur="1s" />
            </path>

            ${markersHTML}
        </svg>
    `;
}


