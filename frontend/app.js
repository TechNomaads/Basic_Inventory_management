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
    socket: null
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
                        <button class="action-btn action-btn-primary" onclick="openProductModal('${p.id}')" title="Edit">
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
    document.getElementById('adj-form').reset();
    
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

// Bind to window for HTML onclick handlers
window.viewInvoiceDetails = viewInvoiceDetails;
window.loadSalesData = loadSalesData;
window.printActiveReceipt = printActiveReceipt;
