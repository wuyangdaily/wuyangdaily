// ==================== 基础配置 ====================
function getAdminPass() {
  if (typeof ADMIN_PASS !== "string" || !ADMIN_PASS.trim()) {
    throw new Error("ADMIN_PASS 未设置");
  }
  return ADMIN_PASS.trim();
}

// ==================== 1. 后台管理页面模板 ====================
const htmlAdmin = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>短链接管理后台</title>
    <meta name="viewport" content="width=device-width,initial-scale=1.0">
    <style>
      :root {
        --bg-color: #f3f4f6;
        --bg-gradient: radial-gradient(circle at top left, #e0f2fe 0, #f3f4f6 35%, #e5e7eb 100%);
        --card-bg: rgba(255, 255, 255, 0.82);
        --card-border: rgba(148, 163, 184, 0.45);
        --card-shadow: 0 18px 45px rgba(15, 23, 42, 0.12);
        --radius-xl: 26px;
        --radius-lg: 18px;
        --radius-md: 12px;

        --text-main: #0f172a;
        --text-sub: #6b7280;
        --text-muted: #9ca3af;

        --primary: #2563eb;
        --primary-soft: rgba(37, 99, 235, 0.12);
        --primary-border: rgba(37, 99, 235, 0.4);
        --danger: #ef4444;

        --input-bg: rgba(255, 255, 255, 0.98);
        --input-border: rgba(148, 163, 184, 0.7);
        --input-focus-ring: rgba(59, 130, 246, 0.55);

        --button-primary-from: #2563eb;
        --button-primary-to: #4f46e5;
        --button-primary-shadow: 0 14px 30px rgba(37, 99, 235, 0.35);
      }

      @media (prefers-color-scheme: dark) {
        :root {
          --bg-color: #020617;
          --bg-gradient: radial-gradient(circle at top left, #0f172a 0, #020617 40%, #020617 100%);
          --card-bg: rgba(15, 23, 42, 0.88);
          --card-border: rgba(51, 65, 85, 0.9);
          --card-shadow: 0 22px 60px rgba(15, 23, 42, 0.9);
          --text-main: #e5e7eb;
          --text-sub: #9ca3af;
          --text-muted: #6b7280;
          --input-bg: rgba(15, 23, 42, 0.96);
          --input-border: rgba(75, 85, 99, 0.9);
        }
      }

      * { box-sizing: border-box; }

      body {
        margin: 0;
        padding: 0;
        min-height: 100vh;
        background: var(--bg-gradient), var(--bg-color);
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
        color: var(--text-main);
        -webkit-font-smoothing: antialiased;
      }

      /* 登录覆盖层 */
      .login-overlay {
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background: transparent;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        z-index: 1000;
      }
      .login-overlay .brand {
        display: flex;
        align-items: center;
        gap: 10px;
        padding-left: 4px;
        margin-bottom: 18px;
        user-select: none;
        max-width: 520px;
        width: 90%;
        margin-left: auto;
        margin-right: auto;
      }
      .login-overlay .brand-dot {
        width: 10px;
        height: 10px;
        border-radius: 999px;
        background: radial-gradient(circle at 30% 20%, #38bdf8 0, #2563eb 35%, #4f46e5 100%);
        box-shadow: 0 0 18px rgba(56, 189, 248, 0.8);
      }
      .login-overlay .brand-title {
        font-size: 13px;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--text-muted);
      }
      .login-card {
        max-width: 520px;
        width: 90%;
        margin: 0 auto;
        text-align: center;
      }
      .login-card .field {
        margin-bottom: 20px;
        text-align: left;
      }
      .login-card label {
        display: block;
        margin-bottom: 6px;
        font-size: 13px;
        font-weight: 500;
        color: var(--text-sub);
      }
      .login-card input.login-password-input,
      .login-card input.login-password-input:hover,
      .login-card input.login-password-input:focus,
      .login-card input.login-password-input:active {
        width: 100% !important;
        min-width: 100% !important;
        max-width: 100% !important;
        box-sizing: border-box !important;
        padding: 12px 14px !important;
        border-radius: var(--radius-md);
        border: 1px solid var(--input-border);
        background: var(--input-bg);
        color: var(--text-main);
        font-size: 14px;
        outline: none;
        transition: none !important;
        box-shadow: none !important;
      }
      .login-card input.login-password-input:focus {
        border-color: var(--primary);
        box-shadow: 0 0 0 1px var(--primary-border), 0 0 0 4px var(--input-focus-ring) !important;
      }
      .error-msg {
        color: #ef4444;
        font-size: 13px;
        margin-top: 12px;
      }

      /* 管理界面样式 */
      .page {
        max-width: 1100px;
        margin: 0 auto;
        padding: 26px 18px 36px;
      }

      .brand {
        display: flex;
        align-items: center;
        gap: 10px;
        padding-left: 4px;
        margin-bottom: 18px;
        user-select: none;
      }

      .brand-dot {
        width: 10px;
        height: 10px;
        border-radius: 999px;
        background: radial-gradient(circle at 30% 20%, #38bdf8 0, #2563eb 35%, #4f46e5 100%);
        box-shadow: 0 0 18px rgba(56, 189, 248, 0.8);
      }

      .brand-title {
        font-size: 13px;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--text-muted);
      }

      .card {
        background: var(--card-bg);
        border-radius: var(--radius-xl);
        border: 1px solid var(--card-border);
        box-shadow: var(--card-shadow);
        padding: 26px 22px 22px;
        backdrop-filter: blur(20px) saturate(140%);
        -webkit-backdrop-filter: blur(20px) saturate(140%);
      }

      .card-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 12px;
      }

      h2 {
        margin: 0;
        font-size: 22px;
        letter-spacing: 0.02em;
      }

      .subtitle {
        margin: 4px 0 0;
        color: var(--text-sub);
        font-size: 13px;
      }

      .section-title {
        margin: 0 0 12px;
        font-size: 16px;
        font-weight: 600;
      }

      .badge {
        font-size: 11px;
        padding: 4px 10px;
        border-radius: 999px;
        background: var(--primary-soft);
        color: #1d4ed8;
        border: 1px solid rgba(129, 140, 248, 0.35);
        letter-spacing: 0.08em;
        text-transform: uppercase;
        white-space: nowrap;
      }

      .btn {
        padding: 10px 14px;
        border-radius: 12px;
        border: none;
        cursor: pointer;
        font-size: 14px;
        font-weight: 600;
        transition: transform 0.16s ease, box-shadow 0.18s ease, filter 0.16s ease;
      }

      .btn-primary {
        background-image: linear-gradient(90deg, var(--button-primary-from), var(--button-primary-to));
        color: #fff;
        box-shadow: var(--button-primary-shadow);
      }

      .btn-primary:hover { transform: translateY(-1px); filter: brightness(1.03); }
      .btn-primary:active { transform: translateY(0); box-shadow: 0 8px 18px rgba(30,64,175,0.5); }

      .btn-ghost {
        background: rgba(255,255,255,0.6);
        color: var(--text-main);
        border: 1px solid var(--card-border);
      }

      .btn-red {
        background: rgba(248, 113, 113, 0.14);
        color: var(--danger);
        border: 1px solid rgba(248, 113, 113, 0.35);
      }

      .btn-sm {
        padding: 4px 10px;
        font-size: 12px;
      }

      .action-group {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
      }

      .toolbar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
        margin-top: 10px;
        padding: 12px;
        border-radius: var(--radius-lg);
        border: 1px solid rgba(148,163,184,0.22);
        background: rgba(255,255,255,0.35);
      }

      .tool-group {
        display: flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
      }

      .tool-label {
        font-size: 13px;
        color: var(--text-sub);
        user-select: none;
      }

      select, input[type="number"], input[type="text"] {
        padding: 9px 10px;
        border-radius: 12px;
        border: 1px solid var(--card-border);
        background: rgba(255,255,255,0.78);
        color: var(--text-main);
        outline: none;
      }

      input[type="number"] { width: 110px; }
      input[type="text"] { width: 260px; }

      .pager-info {
        font-size: 13px;
        color: var(--text-sub);
        white-space: nowrap;
      }

      table {
        width: 100%;
        border-collapse: collapse;
        margin-top: 10px;
      }

      thead th {
        text-align: left;
        padding: 12px;
        font-size: 13px;
        color: var(--text-sub);
        border-bottom: 1px solid var(--card-border);
      }

      tbody td {
        padding: 14px 12px;
        border-bottom: 1px solid rgba(148,163,184,0.25);
        word-break: break-all;
      }

      .empty {
        text-align: center;
        color: var(--text-sub);
        padding: 18px 0;
      }

      /* 模态框样式 */
      .modal-mask {
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background: rgba(0,0,0,0.6);
        backdrop-filter: blur(6px);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 2000;
        visibility: hidden;
        opacity: 0;
        transition: visibility 0.2s, opacity 0.2s;
      }
      .modal-mask.active {
        visibility: visible;
        opacity: 1;
      }
      .modal-container {
        background: var(--card-bg);
        border: 1px solid var(--card-border);
        border-radius: var(--radius-xl);
        box-shadow: var(--card-shadow);
        max-width: 520px;
        width: 90%;
        padding: 20px;
        backdrop-filter: blur(24px);
      }
      .modal-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 18px;
      }
      .modal-header h3 {
        margin: 0;
        font-size: 20px;
      }
      .modal-close {
        background: none;
        border: none;
        font-size: 26px;
        cursor: pointer;
        color: var(--text-sub);
      }
      .modal-field {
        margin-bottom: 16px;
      }
      .modal-field label {
        display: block;
        margin-bottom: 6px;
        font-size: 13px;
        font-weight: 500;
        color: var(--text-sub);
      }
      .modal-field input {
        width: 100%;
        padding: 10px 12px;
        border-radius: var(--radius-md);
        border: 1px solid var(--input-border);
        background: var(--input-bg);
        color: var(--text-main);
      }
      .modal-buttons {
        display: flex;
        justify-content: flex-end;
        gap: 12px;
        margin-top: 20px;
      }

      @media (max-width: 720px) {
        thead { display: none; }
        tbody tr { display: block; margin-bottom: 14px; border: 1px solid var(--card-border); border-radius: 14px; background: rgba(255,255,255,0.78); }
        tbody td { display: flex; justify-content: space-between; align-items: center; gap: 10px; border-bottom: 1px solid rgba(148,163,184,0.18); }
        tbody td:last-child { border-bottom: none; }
        tbody td::before { content: attr(data-label); font-size: 12px; color: var(--text-sub); }
      }
    </style>
</head>
<body>
  <!-- 登录覆盖层 -->
  <div id="loginOverlay" class="login-overlay">
    <div class="brand">
      <div class="brand-dot"></div>
      <span class="brand-title">SHORT URL SERVICE</span>
    </div>
    <div class="card login-card">
      <div class="card-header">
        <h2>管理后台登录</h2>
        <span class="badge">SECURE</span>
      </div>
      <div class="field">
        <input type="password" id="adminPassword" class="login-password-input" placeholder="请输入管理密码" autocomplete="off" />
      </div>
      <button class="btn btn-primary" id="loginBtn" style="width: 100%;">登录</button>
      <div id="loginError" class="error-msg"></div>
    </div>
  </div>

  <!-- 管理界面（登录后显示） -->
  <div id="adminContent" style="display: none;">
    <div class="page">
      <header class="brand">
        <div class="brand-dot"></div>
        <span class="brand-title">SHORT URL SERVICE</span>
      </header>

      <section class="card">
        <div class="card-header">
          <div>
            <h2>短链接管理后台</h2>
            <p class="subtitle">管理短链接：查看后缀、原始链接与创建时间（精确到秒）。删除会同时清理哈希索引（不改变原有核心逻辑）。</p>
          </div>
          <span class="badge">ADMIN PANEL</span>
        </div>
        <div style="margin-top: 16px; display: flex; gap: 10px; justify-content: flex-end;">
          <button class="btn btn-ghost" onclick="reload()">刷新数据</button>
          <button class="btn btn-ghost" onclick="logout()">退出登录</button>
        </div>
      </section>

      <section class="card">
        <h3 class="section-title">链接列表</h3>
        <div class="toolbar">
          <div class="tool-group">
            <span class="tool-label">排序</span>
            <select id="sortSelect" onchange="onSortChange()">
              <option value="name">按后缀（A → Z）</option>
              <option value="time">按创建时间（新 → 旧）</option>
            </select>
            <span class="pager-info" id="totalInfo"></span>
          </div>
          <div class="tool-group tool-search">
            <span class="tool-label">搜索</span>
            <input id="searchInput" type="text" placeholder="搜索后缀或长链接" onkeydown="onSearchKey(event)" />
            <button class="btn btn-ghost" onclick="applySearch()">搜索</button>
            <button class="btn btn-ghost" onclick="clearSearch()">清除</button>
          </div>
          <div class="tool-group">
            <button class="btn btn-ghost" onclick="prevPage()">上一页</button>
            <button class="btn btn-ghost" onclick="nextPage()">下一页</button>
            <span class="pager-info" id="pageInfo"></span>
            <input id="jumpInput" type="number" min="1" placeholder="页码" />
            <button class="btn btn-primary" onclick="jumpPage()">跳转</button>
          </div>
        </div>
        <div id="linkContent" style="margin-top: 4px;"></div>
      </section>
    </div>
  </div>

  <!-- 编辑模态框 -->
  <div id="editModal" class="modal-mask">
    <div class="modal-container">
      <div class="modal-header">
        <h3>编辑短链接</h3>
        <button class="modal-close" onclick="closeEditModal()">&times;</button>
      </div>
      <div class="modal-field">
        <label>短链接后缀</label>
        <input type="text" id="editKey" placeholder="" autocomplete="off" />
      </div>
      <div class="modal-field">
        <label>原始链接</label>
        <input type="url" id="editUrl" placeholder="" autocomplete="off" />
      </div>
      <div class="modal-buttons">
        <button class="btn btn-ghost" onclick="closeEditModal()">取消</button>
        <button class="btn btn-primary" id="saveEditBtn">保存修改</button>
      </div>
    </div>
  </div>

  <script>
    // 后台入口路径由 Worker 环境变量控制，API 路径使用当前页面路径推导
    let base = location.pathname || "";
    while (base.length > 1 && base.endsWith("/")) base = base.slice(0, -1);
    const apiBase = base + "/api";
    let adminPass = null;
    let editingItem = null;

    const state = {
      page: 1,
      size: 10,
      sort: 'name',
      q: '',
      total: 0,
      totalPages: 1,
      loading: false,
    };

    function escapeHtml(input) {
      const s = String(input ?? '');
      return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    }

    function escapeAttr(str) {
      return String(str ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function pad2(n) { return String(n).padStart(2, '0'); }

    function formatTime(createdAtMs) {
      const ms = Number.isFinite(createdAtMs) ? createdAtMs : 0;
      if (ms === 0) return '1970-01-01 00:00:00';
      const d = new Date(ms);
      return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate())
        + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes()) + ':' + pad2(d.getSeconds());
    }

    function setPagerInfo() {
      const pageInfo = document.getElementById('pageInfo');
      const totalInfo = document.getElementById('totalInfo');
      if (pageInfo) pageInfo.textContent = '第 ' + state.page + ' / ' + state.totalPages + ' 页';
      if (totalInfo) totalInfo.textContent = '共 ' + state.total + ' 条';
    }

    function renderEmpty(msg) {
      document.getElementById('linkContent').innerHTML = '<div class="empty">' + (msg || '暂无数据') + '</div>';
      setPagerInfo();
    }

    function renderTable(items) {
      let html = '';
      html += '<table>';
      html += '<thead><tr>'
        + '<th style="width:16%">后缀</th>'
        + '<th>原始链接</th>'
        + '<th style="width:20%">创建时间</th>'
        + '<th style="width:12%">操作</th>'
        + '</tr></thead>';
      html += '<tbody>';
      items.forEach(item => {
        const name = escapeHtml(item.name);
        const url = escapeHtml(item.value || '');
        const created = formatTime(Number(item.createdAt));
        const dataNameAttr = escapeAttr(item.name);
        const dataUrlAttr = escapeAttr(item.value || '');
        html += '<tr>'
          + '<td data-label="后缀"><strong>/' + name + '</strong></td>'
          + '<td data-label="原始链接">'
          +   (url ? '<a href="' + url + '" target="_blank" rel="noopener noreferrer">' + url + '</a>' : '<span style="color: var(--text-muted);">（空）</span>')
          + '</td>'
          + '<td data-label="创建时间">' + escapeHtml(created) + '</td>'
          + '<td data-label="操作"><div class="action-group">'
          +   '<button class="btn btn-ghost btn-sm edit-link-btn" data-name="' + dataNameAttr + '" data-url="' + dataUrlAttr + '">编辑</button>'
          +   '<button class="btn btn-red btn-sm" data-key="' + dataNameAttr + '" onclick="delLink(this.dataset.key, this)">删除</button>'
          + '</div></td>'
          + '</tr>';
      });
      html += '</tbody></table>';
      document.getElementById('linkContent').innerHTML = html;
      setPagerInfo();
    }

    function openEditModal(oldKey, oldUrl) {
      editingItem = { oldKey, oldUrl };
      document.getElementById('editKey').value = oldKey;
      document.getElementById('editUrl').value = oldUrl;
      document.getElementById('editModal').classList.add('active');
    }

    function closeEditModal() {
      document.getElementById('editModal').classList.remove('active');
      editingItem = null;
    }

    async function saveEdit() {
      if (!editingItem) return;
      const newKey = document.getElementById('editKey').value.trim();
      const newUrl = document.getElementById('editUrl').value.trim();
      if (!newKey) {
        alert('后缀不能为空');
        return;
      }
      if (!newUrl || !newUrl.startsWith('http')) {
        alert('请输入正确的原始链接（http/https）');
        return;
      }
      const saveBtn = document.getElementById('saveEditBtn');
      saveBtn.disabled = true;
      saveBtn.textContent = '保存中...';
      try {
        const resp = await fetch(apiBase + '/edit/' + encodeURIComponent(editingItem.oldKey), {
          method: 'POST',
          headers: { 'Authorization': adminPass, 'Content-Type': 'application/json' },
          body: JSON.stringify({ newKey, newUrl })
        });
        const data = await resp.json();
        if (!resp.ok) {
          alert('编辑失败: ' + (data.error || '未知错误'));
        } else {
          alert('修改成功');
          closeEditModal();
          loadPage(state.page);
        }
      } catch (err) {
        alert('网络错误: ' + err.message);
      } finally {
        saveBtn.disabled = false;
        saveBtn.textContent = '保存修改';
      }
    }

    async function loadPage(page) {
      if (state.loading) return;
      state.loading = true;
      const p = Math.max(1, Math.floor(Number(page) || 1));
      renderEmpty('加载中...');
      const sortSelect = document.getElementById('sortSelect');
      if (sortSelect && sortSelect.value !== state.sort) sortSelect.value = state.sort;
      try {
        const qs = new URLSearchParams({ page: String(p), size: String(state.size), sort: state.sort });
        if (state.q) qs.set('q', String(state.q));
        const res = await fetch(apiBase + '/all?' + qs.toString(), { headers: { 'Authorization': adminPass }, cache: 'no-store' });
        if (res.status === 401) { logout(); return; }
        if (!res.ok) { alert('加载失败'); renderEmpty(); return; }
        const data = await res.json();
        state.page = Number(data.page) || p;
        state.total = Number(data.total) || 0;
        state.totalPages = Math.max(1, Number(data.totalPages) || 1);
        const items = Array.isArray(data.links) ? data.links : [];
        if (!items.length) { renderEmpty(); return; }
        renderTable(items);
      } catch (e) { renderEmpty('加载失败'); }
      finally { state.loading = false; }
    }

    function reload() { loadPage(state.page); }
    function onSortChange() {
      const sel = document.getElementById('sortSelect');
      state.sort = (sel && sel.value === 'time') ? 'time' : 'name';
      state.page = 1;
      loadPage(1);
    }
    function normalizeSearchQuery(raw) {
      let q = String(raw ?? '').trim();
      if (!q) return '';
      try {
        if (q.includes('://')) {
          const u = new URL(q);
          if (u.host === location.host) {
            const seg = decodeURIComponent((u.pathname || '').split('/')[1] || '');
            if (seg) q = seg;
          }
        }
      } catch(e) {}
      while (q.startsWith('/')) q = q.slice(1);
      return q.trim();
    }
    function applySearch() {
      const input = document.getElementById('searchInput');
      state.q = normalizeSearchQuery(input ? input.value : '');
      state.page = 1;
      if (input) input.value = state.q;
      loadPage(1);
    }
    function clearSearch() {
      const input = document.getElementById('searchInput');
      if (input) input.value = '';
      state.q = '';
      state.page = 1;
      loadPage(1);
    }
    function onSearchKey(ev) { if (ev && ev.key === 'Enter') applySearch(); }
    function prevPage() { if (state.page > 1) loadPage(state.page - 1); }
    function nextPage() { if (state.page < state.totalPages) loadPage(state.page + 1); }
    function jumpPage() {
      const input = document.getElementById('jumpInput');
      const v = input ? Number(input.value) : NaN;
      if (Number.isFinite(v) && v >= 1) loadPage(Math.floor(v));
    }
    async function delLink(name, btn) {
      if (!name || !confirm('确定删除 /' + name + ' 吗？')) return;
      if (btn) { btn.disabled = true; btn.textContent = '删除中...'; }
      try {
        const res = await fetch(apiBase + '/delete/' + encodeURIComponent(name), { headers: { 'Authorization': adminPass }, cache: 'no-store' });
        if (!res.ok) { alert('删除失败'); if(btn){btn.disabled=false;btn.textContent='删除';} return; }
        loadPage(state.page);
      } catch(e) { alert('请求失败'); if(btn){btn.disabled=false;btn.textContent='删除';} }
    }

    function showAdminPanel() {
      document.getElementById('loginOverlay').style.display = 'none';
      document.getElementById('adminContent').style.display = 'block';
      loadPage(1);
    }

    function logout() {
      sessionStorage.removeItem('admin_pass');
      // 跳转到首页（短链接生成页面）
      window.location.href = '/';
    }

    async function verifyPassword(pwd) {
      try {
        const res = await fetch(apiBase + '/all?page=1&size=1', { headers: { 'Authorization': pwd }, cache: 'no-store' });
        return res.status !== 401;
      } catch { return false; }
    }
    async function attemptLogin() {
      const pwdInput = document.getElementById('adminPassword');
      const pwd = pwdInput.value.trim();
      if (!pwd) { document.getElementById('loginError').innerText = '请输入密码'; return; }
      const btn = document.getElementById('loginBtn');
      btn.disabled = true;
      btn.textContent = '验证中...';
      const ok = await verifyPassword(pwd);
      if (ok) {
        adminPass = pwd;
        sessionStorage.setItem('admin_pass', pwd);
        showAdminPanel();
      } else {
        document.getElementById('loginError').innerText = '密码错误';
        pwdInput.value = '';
        pwdInput.focus();
      }
      btn.disabled = false;
      btn.textContent = '登录';
    }

    document.addEventListener('click', function(e) {
      const editBtn = e.target.closest('.edit-link-btn');
      if (editBtn) {
        const oldKey = editBtn.getAttribute('data-name');
        const oldUrl = editBtn.getAttribute('data-url');
        if (oldKey !== null && oldUrl !== null) {
          openEditModal(oldKey, oldUrl);
        }
      }
    });

    (async function init() {
      const stored = sessionStorage.getItem('admin_pass');
      if (stored && await verifyPassword(stored)) {
        adminPass = stored;
        showAdminPanel();
      } else {
        sessionStorage.removeItem('admin_pass');
        document.getElementById('loginOverlay').style.display = 'flex';
        document.getElementById('adminContent').style.display = 'none';
        document.getElementById('loginBtn').addEventListener('click', attemptLogin);
        document.getElementById('adminPassword').addEventListener('keypress', (e) => { if (e.key === 'Enter') attemptLogin(); });
      }
      const saveBtn = document.getElementById('saveEditBtn');
      if (saveBtn) saveBtn.addEventListener('click', saveEdit);
    })();

    const jumpInput = document.getElementById('jumpInput');
    if (jumpInput) jumpInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') jumpPage(); });
  </script>
</body>
</html>`;

// ==================== 2. 首页模板 (生成页) ====================
const htmlIndex = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <title>短链接生成</title>
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <style>
    :root {
      --bg-color: #f3f4f6;
      --bg-gradient: radial-gradient(circle at top left, #e0f2fe 0, #f3f4f6 35%, #e5e7eb 100%);
      --card-bg: rgba(255, 255, 255, 0.82);
      --card-border: rgba(148, 163, 184, 0.45);
      --card-shadow: 0 18px 45px rgba(15, 23, 42, 0.12);
      --radius-xl: 24px;
      --radius-lg: 18px;
      --radius-md: 12px;

      --text-main: #0f172a;
      --text-sub: #6b7280;
      --text-muted: #9ca3af;

      --primary: #2563eb;
      --primary-soft: rgba(37, 99, 235, 0.12);
      --primary-border: rgba(37, 99, 235, 0.4);

      --accent: #22c55e;
      --accent-soft: rgba(34, 197, 94, 0.12);

      --input-bg: rgba(255, 255, 255, 0.98);
      --input-border: rgba(148, 163, 184, 0.7);
      --input-focus-ring: rgba(59, 130, 246, 0.55);

      --button-primary-from: #2563eb;
      --button-primary-to: #4f46e5;
      --button-primary-shadow: 0 14px 30px rgba(37, 99, 235, 0.35);

      --button-accent-from: #16a34a;
      --button-accent-to: #22c55e;
      --button-accent-shadow: 0 12px 26px rgba(34, 197, 94, 0.32);

      --result-bg: rgba(248, 250, 252, 0.92);
      --result-border: rgba(148, 163, 184, 0.4);
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --bg-color: #020617;
        --bg-gradient: radial-gradient(circle at top left, #0f172a 0, #020617 40%, #020617 100%);
        --card-bg: rgba(15, 23, 42, 0.88);
        --card-border: rgba(51, 65, 85, 0.9);
        --card-shadow: 0 22px 60px rgba(15, 23, 42, 0.9);

        --text-main: #e5e7eb;
        --text-sub: #9ca3af;
        --text-muted: #6b7280;

        --input-bg: rgba(15, 23, 42, 0.96);
        --input-border: rgba(75, 85, 99, 0.9);

        --result-bg: rgba(15, 23, 42, 0.96);
        --result-border: rgba(55, 65, 81, 0.9);
      }
    }

    * { box-sizing: border-box; }

    html, body {
      margin: 0;
      padding: 0;
      height: 100%;
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
      background: var(--bg-gradient), var(--bg-color);
      color: var(--text-main);
      min-height: 100vh;
      margin: 0;
      -webkit-font-smoothing: antialiased;
    }
    .page {
      width: 100%;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      padding: 26px 18px 36px;
    }

    .brand {
      display: flex;
      align-items: center;
      gap: 8px;
      margin-bottom: 16px;
      padding-left: 4px;
      user-select: none;
    }

    .brand-dot {
      width: 9px;
      height: 9px;
      border-radius: 999px;
      background: radial-gradient(circle at 30% 20%, #38bdf8 0, #2563eb 35%, #4f46e5 100%);
      box-shadow: 0 0 18px rgba(56, 189, 248, 0.8);
    }

    .brand-title {
      font-size: 13px;
      letter-spacing: 0.14em;
      text-transform: uppercase;
      color: var(--text-muted);
    }
    .shell {
      position: relative;
      flex: 1;
      display: flex;
      align-items: center;
      justify-content: center;
      width: 100%;
    }

    .shell::before {
      content: "";
      position: absolute;
      inset: -80px;
      background:
        radial-gradient(circle at 10% 0, rgba(59,130,246,0.16) 0, transparent 55%),
        radial-gradient(circle at 120% 120%, rgba(129,140,248,0.18) 0, transparent 55%);
      opacity: 0.9;
      pointer-events: none;
      z-index: -1;
    }
    .card {
      background: var(--card-bg);
      border-radius: var(--radius-xl);
      border: 1px solid var(--card-border);
      box-shadow: var(--card-shadow);
      padding: 26px 22px 22px;
      width: 100%;
      max-width: 520px;
      backdrop-filter: blur(20px) saturate(140%);
      -webkit-backdrop-filter: blur(20px) saturate(140%);
    }
    @media (min-width: 640px) {
      .card {
        padding: 30px 28px 26px;
      }
    }

    .card-header {
      margin-bottom: 18px;
    }

    .title-row {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 12px;
    }

    h1 {
      margin: 0;
      font-size: 22px;
      font-weight: 650;
      letter-spacing: 0.03em;
    }

    .badge {
      font-size: 10px;
      padding: 3px 8px;
      border-radius: 999px;
      background: var(--primary-soft);
      color: #1d4ed8;
      border: 1px solid rgba(129, 140, 248, 0.35);
      text-transform: uppercase;
      letter-spacing: 0.12em;
      white-space: nowrap;
    }

    .subtitle {
      margin: 6px 0 0;
      font-size: 13px;
      color: var(--text-sub);
    }

    .form {
      margin-top: 16px;
      display: flex;
      flex-direction: column;
      gap: 14px;
    }

    .field {
      display: flex;
      flex-direction: column;
      gap: 6px;
    }

    label {
      font-size: 12px;
      font-weight: 500;
      color: var(--text-sub);
    }

    input[type="url"],
    input[type="text"] {
      width: 100%;
      padding: 11px 12px;
      font-size: 14px;
      border-radius: var(--radius-md);
      border: 1px solid var(--input-border);
      background: var(--input-bg);
      color: var(--text-main);
      outline: none;
      transition: border-color 0.16s ease, box-shadow 0.16s ease, background-color 0.16s ease, transform 0.06s ease;
    }

    input::placeholder {
      color: var(--text-muted);
    }

    input:focus {
      border-color: var(--primary);
      box-shadow:
        0 0 0 1px var(--primary-border),
        0 0 0 6px var(--input-focus-ring);
      transform: translateY(-0.5px);
    }

    .inline-row { display: flex; gap: 10px; flex-wrap: wrap; }
    .inline-row > .field { flex: 1; min-width: 0; }

    .captcha-wrapper {
      min-height: 58px;
      display: flex;
      align-items: center;
      justify-content: flex-start;
      margin: 0;
      padding: 0;
    }

    .captcha-tip {
      font-size: 11px;
      color: var(--text-muted);
      margin-top: 4px;
    }

    .primary-btn {
      margin-top: 0;
      width: 100%;
      padding: 13px 14px;
      border-radius: var(--radius-lg);
      border: none;
      cursor: pointer;
      font-size: 15px;
      font-weight: 600;
      letter-spacing: 0.04em;
      text-align: center;
      color: #ffffff;
      background-image: linear-gradient(90deg, var(--button-primary-from), var(--button-primary-to));
      box-shadow: var(--button-primary-shadow);
      transform: translateY(0);
      transition:
        box-shadow 0.18s ease,
        transform 0.18s ease,
        filter 0.18s ease,
        opacity 0.18s ease;
    }

    .primary-btn:hover {
      transform: translateY(-1px);
      filter: brightness(1.04);
      box-shadow: 0 18px 38px rgba(37, 99, 235, 0.45);
    }

    .primary-btn:active {
      transform: translateY(0);
      box-shadow: 0 10px 24px rgba(30, 64, 175, 0.6);
      filter: brightness(0.97);
    }

    .primary-btn:disabled {
      cursor: default;
      opacity: 0.65;
      box-shadow: none;
      filter: grayscale(0.1);
    }

    .result {
      margin-top: 18px;
      padding: 14px 12px 12px;
      border-radius: var(--radius-lg);
      background: var(--result-bg);
      border: 1px solid var(--result-border);
      display: none;
    }

    .result-label {
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.14em;
      color: var(--text-muted);
      margin-bottom: 6px;
    }

    .result-link {
      font-weight: 650;
      font-size: 14px;
      color: var(--primary);
      word-break: break-all;
      margin-bottom: 10px;
    }

    .copy-btn {
      width: 100%;
      padding: 10px 12px;
      border-radius: var(--radius-md);
      border: none;
      cursor: pointer;
      font-size: 14px;
      font-weight: 550;
      color: #ffffff;
      background-image: linear-gradient(90deg, var(--button-accent-from), var(--button-accent-to));
      box-shadow: var(--button-accent-shadow);
      transition: box-shadow 0.18s ease, transform 0.18s ease, filter 0.18s ease;
    }

    .copy-btn:hover {
      transform: translateY(-0.5px);
      filter: brightness(1.03);
      box-shadow: 0 16px 34px rgba(34, 197, 94, 0.45);
    }

    .copy-btn:active {
      transform: translateY(0);
      box-shadow: 0 10px 22px rgba(22, 163, 74, 0.65);
      filter: brightness(0.98);
    }

    .footnote {
      margin-top: 12px;
      font-size: 11px;
      color: var(--text-muted);
      text-align: center;
      user-select: none;
    }

    @media (max-width: 480px) {
      .card { border-radius: 20px; }
      h1 { font-size: 20px; }
    }
  </style>
</head>
<body>
  <div class="page">
    <header class="brand">
      <div class="brand-dot"></div>
      <span class="brand-title">SHORT URL SERVICE</span>
    </header>

    <main class="shell">
      <section class="card">
        <div class="card-header">
          <div class="title-row">
            <h1>短链接生成</h1>
            <span class="badge">LIQUID GLASS UI</span>
          </div>
        </div>

        <div class="form">
          <div class="field">
            <label for="u">长链接</label>
            <input
              type="url"
              id="u"
              placeholder=""
              autocomplete="off"
            />
          </div>

          <div class="inline-row">
            <div class="field">
              <label for="k">自定义后缀（可选）</label>
              <input
                type="text"
                id="k"
                placeholder=""
                autocomplete="off"
              />
            </div>
          </div>

          <div class="field">
            <div id="captcha-container" class="captcha-wrapper"></div>
          </div>

          <button id="btn" class="primary-btn" onclick="s()">立即生成</button>
        </div>

        <div id="res" class="result">
          <div class="result-label">SHORT LINK</div>
          <div id="link" class="result-link"></div>
          <button class="copy-btn" onclick="cp(this)">点击复制</button>
        </div>
      </section>
    </main>
  </div>

  <script>
    let tk = "";
    let isVerified = false;

    async function init() {
      try {
        const res = await fetch('/api/get-ui-config');
        const cfg = await res.json();

        const btn = document.getElementById('btn');
        const tip = document.getElementById('captcha-tip');

        if (cfg.captchaEnabled === 'true' && cfg.siteKey) {
          btn.disabled = true;

          const script = document.createElement('script');
          script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js";
          script.async = true;
          document.head.appendChild(script);

          const div = document.createElement('div');
          div.className = "cf-turnstile";
          div.setAttribute('data-sitekey', cfg.siteKey);
          div.setAttribute('data-callback', 'onTs');
          document.getElementById('captcha-container').appendChild(div);

        } else {
          btn.disabled = false;
        }
      } catch (e) {
        const btn = document.getElementById('btn');
        if (btn) btn.disabled = false;
      }
    }

    window.onTs = function (t) {
      tk = t;
      isVerified = true;
      const btn = document.getElementById('btn');
      if (btn) btn.disabled = false;
    };

    async function s() {
      const u = document.getElementById('u').value.trim();
      const k = document.getElementById('k').value.trim();

      if (!u || !u.startsWith('http')) {
        alert('请输入以 http 或 https 开头的完整链接');
        return;
      }

      const btn = document.getElementById('btn');
      if (btn) btn.disabled = true;

      try {
        const res = await fetch('/', {
          method: 'POST',
          body: JSON.stringify({ url: u, key: k, cf_token: tk })
        });
        const d = await res.json();

        if (d.key) {
          const full = window.location.origin + d.key;
          const linkEl = document.getElementById('link');
          const resBox = document.getElementById('res');
          if (linkEl) linkEl.textContent = full;
          if (resBox) resBox.style.display = 'block';
        } else {
          alert('错误：' + (d.error || '生成失败'));
        }
      } catch (e) {
        alert('请求失败，请稍后重试。');
      } finally {
        if (btn) btn.disabled = false;
      }
    }

    function cp(b) {
      const text = document.getElementById('link').textContent;
      if (!text) return;
      navigator.clipboard.writeText(text).then(function () {
        const old = b.innerText;
        b.innerText = '✅ 已复制';
        setTimeout(function () {
          b.innerText = old;
        }, 2000);
      });
    }

    init();
  </script>
</body>
</html>`;

// ==================== 3. 后端核心逻辑 ====================
// - KV 命名空间绑定为 LINKS
// - Worker 环境变量：TURNSTILE_SITE_KEY（文本）、TURNSTILE_SECRET_KEY（机密）

async function sha512(url) {
  const url_digest = await crypto.subtle.digest(
    "SHA-512",
    new TextEncoder().encode(url)
  );
  return Array.from(new Uint8Array(url_digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ==================== 3.1 管理后台列表缓存 & 创建时间辅助 ====================
const ADMIN_LIST_CACHE_TTL_MS = 4000;
const __adminListCache = {
  at: 0,
  items: null,
};

function invalidateAdminListCache() {
  __adminListCache.at = 0;
  __adminListCache.items = null;
}

function readCreatedAt(meta) {
  if (!meta || typeof meta !== "object") return 0;
  const v = meta.createdAt;
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
}

async function buildAdminIndex() {
  const out = [];
  let cursor = undefined;
  while (true) {
    const list = await LINKS.list({ cursor, limit: 1000 });
    for (const k of list.keys) {
      if (k.name.length !== 128 && !k.name.startsWith("SYS_CONFIG_")) {
        out.push({ name: k.name, createdAt: readCreatedAt(k.metadata) });
      }
    }
    if (list.list_complete || !list.cursor) break;
    cursor = list.cursor;
  }
  return out;
}

async function getAdminIndexCached() {
  const now = Date.now();
  if (__adminListCache.items && (now - __adminListCache.at) < ADMIN_LIST_CACHE_TTL_MS) {
    return __adminListCache.items.slice();
  }
  const items = await buildAdminIndex();
  __adminListCache.items = items;
  __adminListCache.at = now;
  return items.slice();
}

async function handleRequest(request) {
  const url = new URL(request.url);
  const pathname = url.pathname;
  const path = decodeURIComponent(pathname.split("/")[1]);
  const auth = request.headers.get("Authorization");

  function normalizeAdminPath(p) {
    let v = (typeof p === "string" ? p : "").trim();
    if (!v) v = "/admin";
    if (!v.startsWith("/")) v = "/" + v;
    while (v.length > 1 && v.endsWith("/")) v = v.slice(0, -1);
    if (v === "/") v = "/admin";
    return v;
  }

  function isTruthyEnv(v) {
    if (typeof v !== "string") return false;
    const s = v.trim().toLowerCase();
    return s === "true" || s === "1" || s === "yes" || s === "y" || s === "on";
  }

  function splitEnvList(raw) {
    return String(raw || "")
      .split(/\r?\n|,/)
      .map((l) => String(l || "").split("#")[0].trim())
      .filter((l) => l.length > 0);
  }

  function normalizeHostRule(rule) {
    let r = String(rule || "").trim().toLowerCase();
    if (!r) return "";
    r = r.replace(/^https?:\/\//, "");
    r = r.split("/")[0];
    r = r.split(":")[0];
    r = r.replace(/^\*\./, "").replace(/^\./, "");
    return r;
  }

  function buildDomainRules(raw) {
    const out = [];
    for (const line of splitEnvList(raw)) {
      const r = normalizeHostRule(line);
      if (r) out.push(r);
    }
    return out;
  }

  function isHostBlocked(host, rules) {
    const h = String(host || "").toLowerCase().replace(/\.$/, "");
    if (!h) return false;
    for (const r of rules) {
      if (!r) continue;
      if (h === r) return true;
      if (h.endsWith("." + r)) return true;
    }
    return false;
  }

  function normalizeSuffixRule(rule) {
    let r = String(rule || "").trim();
    if (!r) return "";
    while (r.startsWith("/")) r = r.slice(1);
    return r.toLowerCase();
  }

  function buildSuffixSet(raw) {
    const set = new Set();
    for (const line of splitEnvList(raw)) {
      const r = normalizeSuffixRule(line);
      if (r) set.add(r);
    }
    return set;
  }

  function isSuffixBlocked(key, set) {
    const k = normalizeSuffixRule(key);
    return k ? set.has(k) : false;
  }

  // 环境变量配置
  const adminBase = normalizeAdminPath(typeof ADMIN_PATH === "string" ? ADMIN_PATH : "");
  const adminApiBase = adminBase + "/api";
  const captchaEnabled = isTruthyEnv(typeof CAPTCHA_ENABLED === "string" ? CAPTCHA_ENABLED : "") ? "true" : "false";

  const rawDomainBlacklist =
    (typeof LONG_DOMAIN_BLACKLIST === "string" ? LONG_DOMAIN_BLACKLIST : "") ||
    (typeof DOMAIN_BLACKLIST === "string" ? DOMAIN_BLACKLIST : "") ||
    (typeof LONG_URL_DOMAIN_BLACKLIST === "string" ? LONG_URL_DOMAIN_BLACKLIST : "");

  const rawSuffixBlacklist =
    (typeof SUFFIX_BLACKLIST === "string" ? SUFFIX_BLACKLIST : "") ||
    (typeof SHORT_SUFFIX_BLACKLIST === "string" ? SHORT_SUFFIX_BLACKLIST : "") ||
    (typeof SHORT_LINK_SUFFIX_BLACKLIST === "string" ? SHORT_LINK_SUFFIX_BLACKLIST : "");

  const domainBlacklist = buildDomainRules(rawDomainBlacklist);
  const suffixBlacklist = buildSuffixSet(rawSuffixBlacklist);

  const htmlHeaders = {
    "content-type": "text/html;charset=UTF-8",
    "Access-Control-Allow-Origin": "*",
    "cache-control": "no-store",
  };

  const jsonHeaders = {
    "content-type": "application/json;charset=UTF-8",
    "Access-Control-Allow-Origin": "*",
    "cache-control": "no-store",
  };

  // 后台页面
  if (pathname === adminBase || pathname === adminBase + "/") {
    return new Response(htmlAdmin, { headers: htmlHeaders });
  }

  // 后台：获取短链接列表
  if (pathname === adminApiBase + "/all") {
    if (auth !== getAdminPass()) {
      return new Response("Unauthorized", { status: 401 });
    }

    const pageRaw = Number(url.searchParams.get("page") || "1");
    const sizeRaw = Number(url.searchParams.get("size") || "10");
    const sortRaw = String(url.searchParams.get("sort") || "name").toLowerCase();
    const qRaw0 = String(url.searchParams.get("q") || "").trim();
    const qRaw = qRaw0.replace(/^\/+/, "");
    const q = qRaw.toLowerCase();

    const size = Math.min(10, Math.max(1, Math.floor(Number.isFinite(sizeRaw) ? sizeRaw : 10)));
    const sort = sortRaw === "time" ? "time" : "name";

    const index = await getAdminIndexCached();

    if (q) {
      const matched = [];
      const missingKeys = [];

      let ptr = 0;
      const concurrency = Math.min(30, Math.max(1, index.length));

      async function worker() {
        while (true) {
          const i = ptr++;
          if (i >= index.length) break;

          const it = index[i];
          const val = await LINKS.get(it.name);
          if (typeof val !== "string" || !val.length) {
            missingKeys.push(it.name);
            continue;
          }

          const nameMatch = it.name.toLowerCase().includes(q);
          const valMatch = val.toLowerCase().includes(q);
          if (nameMatch || valMatch) {
            matched.push({ name: it.name, value: val, createdAt: it.createdAt || 0 });
          }
        }
      }

      await Promise.all(new Array(concurrency).fill(0).map(() => worker()));

      if (missingKeys.length) {
        await Promise.all(missingKeys.map((k) => LINKS.delete(k)));
        invalidateAdminListCache();
      }

      if (sort === "time") {
        matched.sort((a, b) => {
          const dt = (b.createdAt || 0) - (a.createdAt || 0);
          if (dt !== 0) return dt;
          return a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" });
        });
      } else {
        matched.sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" }));
      }

      const total = matched.length;
      const totalPages = Math.max(1, Math.ceil(total / size));
      const page = Math.min(totalPages, Math.max(1, Math.floor(Number.isFinite(pageRaw) ? pageRaw : 1)));

      const start = (page - 1) * size;
      const pageItems = matched.slice(start, start + size);

      const links = pageItems.map((it) => ({ name: it.name, value: it.value, createdAt: it.createdAt || 0 }));

      return new Response(
        JSON.stringify({ page, size, sort, q: qRaw, total, totalPages, links }),
        { headers: jsonHeaders }
      );
    }

    if (sort === "time") {
      index.sort((a, b) => {
        const dt = (b.createdAt || 0) - (a.createdAt || 0);
        if (dt !== 0) return dt;
        return a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" });
      });
    } else {
      index.sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" }));
    }

    const total = index.length;
    const totalPages = Math.max(1, Math.ceil(total / size));
    const page = Math.min(totalPages, Math.max(1, Math.floor(Number.isFinite(pageRaw) ? pageRaw : 1)));

    const start = (page - 1) * size;
    const pageItems = index.slice(start, start + size);

    const values = await Promise.all(pageItems.map((it) => LINKS.get(it.name)));

    const links = [];
    const missingKeys = [];
    for (let i = 0; i < pageItems.length; i++) {
      const it = pageItems[i];
      const val = values[i];
      if (typeof val === "string" && val.length) {
        links.push({ name: it.name, value: val, createdAt: it.createdAt || 0 });
      } else {
        missingKeys.push(it.name);
      }
    }

    if (missingKeys.length) {
      await Promise.all(missingKeys.map((k) => LINKS.delete(k)));
      invalidateAdminListCache();
    }

    return new Response(
      JSON.stringify({ page, size, sort, total, totalPages, links }),
      { headers: jsonHeaders }
    );
  }

  // 后台：删除指定后缀短链（包括哈希索引）
  if (pathname.startsWith(adminApiBase + "/delete/")) {
    if (auth !== getAdminPass()) {
      return new Response("Unauthorized", { status: 401 });
    }

    const prefix = adminApiBase + "/delete/";
    const keyDel = decodeURIComponent(pathname.slice(prefix.length) || "");
    if (!keyDel) return new Response("Bad Request", { status: 400 });

    const longUrl = await LINKS.get(keyDel);
    if (longUrl) {
      const hash = await sha512(longUrl);
      await Promise.all([LINKS.delete(hash), LINKS.delete(keyDel)]);
    } else {
      await LINKS.delete(keyDel);
    }

    invalidateAdminListCache();
    return new Response("OK", { headers: { "cache-control": "no-store" } });
  }

  // ========== 编辑短链接（不写入任何哈希索引） ==========
  if (pathname.startsWith(adminApiBase + "/edit/")) {
    if (auth !== getAdminPass()) {
      return new Response("Unauthorized", { status: 401 });
    }

    const prefix = adminApiBase + "/edit/";
    const oldKeyRaw = decodeURIComponent(pathname.slice(prefix.length) || "");
    if (!oldKeyRaw) return new Response("Bad Request", { status: 400 });

    let body;
    try {
      body = await request.json();
    } catch {
      return new Response(JSON.stringify({ error: "无效的请求体" }), { status: 400, headers: jsonHeaders });
    }
    const newKeyRaw = (body.newKey || "").trim();
    const newUrl = (body.newUrl || "").trim();

    if (!newKeyRaw || !newUrl) {
      return new Response(JSON.stringify({ error: "新后缀和新链接不能为空" }), { status: 400, headers: jsonHeaders });
    }

    const newKey = newKeyRaw.replace(/^\/+|\/+$/g, "");
    const oldKey = oldKeyRaw.replace(/^\/+|\/+$/g, "");
    if (!newKey) {
      return new Response(JSON.stringify({ error: "后缀不能为空" }), { status: 400, headers: jsonHeaders });
    }

    const oldLongUrl = await LINKS.get(oldKey);
    if (oldLongUrl === null) {
      return new Response(JSON.stringify({ error: "原短链接不存在" }), { status: 404, headers: jsonHeaders });
    }

    // 如果新后缀与旧后缀不同，检查是否被占用或黑名单
    if (newKey !== oldKey) {
      const existing = await LINKS.get(newKey);
      if (existing !== null) {
        return new Response(JSON.stringify({ error: "新后缀已被占用" }), { status: 409, headers: jsonHeaders });
      }
      if (isSuffixBlocked(newKey, suffixBlacklist)) {
        return new Response(JSON.stringify({ error: "该后缀不可用（黑名单）" }), { status: 403, headers: jsonHeaders });
      }
    }

    // 新链接合法性校验
    let newUrlObj;
    try {
      newUrlObj = new URL(newUrl);
      if (newUrlObj.protocol !== "http:" && newUrlObj.protocol !== "https:") {
        throw new Error();
      }
    } catch {
      return new Response(JSON.stringify({ error: "新链接格式错误，仅支持 http/https" }), { status: 400, headers: jsonHeaders });
    }
    const newHost = newUrlObj.hostname.toLowerCase();
    if (domainBlacklist.length && isHostBlocked(newHost, domainBlacklist)) {
      return new Response(JSON.stringify({ error: "此长链接域名无法使用" }), { status: 403, headers: jsonHeaders });
    }

    // 保留原创建时间
    let originalCreatedAt = Date.now();
    const oldWithMeta = await LINKS.getWithMetadata(oldKey);
    if (oldWithMeta && oldWithMeta.metadata && typeof oldWithMeta.metadata.createdAt === "number") {
      originalCreatedAt = oldWithMeta.metadata.createdAt;
    }

    // 删除旧的哈希索引（如果存在且指向当前 oldKey）
    const oldHash = await sha512(oldLongUrl);
    const hashValue = await LINKS.get(oldHash);
    if (hashValue === oldKey) {
      await LINKS.delete(oldHash);
    }

    // 写入新记录（保留原创建时间，不写入新哈希索引）
    await LINKS.put(newKey, newUrl, { metadata: { createdAt: originalCreatedAt } });

    // 如果新旧后缀不同，删除旧 key；如果相同，则只更新值（上面 put 已覆盖，无需删除）
    if (newKey !== oldKey) {
      await LINKS.delete(oldKey);
    }

    // 刷新后台列表缓存
    invalidateAdminListCache();

    return new Response(JSON.stringify({ success: true }), { headers: jsonHeaders });
  }

  // 前端：获取 UI 配置
  if (pathname === "/api/get-ui-config") {
    return new Response(
      JSON.stringify({
        captchaEnabled,
        siteKey: typeof TURNSTILE_SITE_KEY === "string" ? TURNSTILE_SITE_KEY : "",
      }),
      { headers: jsonHeaders }
    );
  }

  // 生成短链
  if (request.method === "POST") {
    const req = await request.json();

    const ERR_SUFFIX_TAKEN = "该后缀已被占用";
    const ERR_DOMAIN_BLOCKED = "此长链接域名无法使用";

    const reqUrl = typeof req.url === "string" ? req.url.trim() : "";
    if (!reqUrl) {
      return new Response(JSON.stringify({ error: "链接不能为空" }), {
        status: 400,
        headers: jsonHeaders,
      });
    }

    let urlObj;
    try {
      urlObj = new URL(reqUrl);
    } catch (e) {
      return new Response(JSON.stringify({ error: "链接格式错误" }), {
        status: 400,
        headers: jsonHeaders,
      });
    }

    if (urlObj.protocol !== "http:" && urlObj.protocol !== "https:") {
      return new Response(JSON.stringify({ error: "仅支持 http/https 链接" }), {
        status: 400,
        headers: jsonHeaders,
      });
    }

    const host = String(urlObj.hostname || "").toLowerCase();
    if (domainBlacklist.length && isHostBlocked(host, domainBlacklist)) {
      return new Response(JSON.stringify({ error: ERR_DOMAIN_BLOCKED }), {
        status: 403,
        headers: jsonHeaders,
      });
    }

    const customKey = typeof req.key === "string" ? req.key : "";
    if (customKey && isSuffixBlocked(customKey, suffixBlacklist)) {
      return new Response(JSON.stringify({ error: ERR_SUFFIX_TAKEN }), {
        status: 409,
        headers: jsonHeaders,
      });
    }

    if (customKey && (await LINKS.get(customKey))) {
      return new Response(JSON.stringify({ error: ERR_SUFFIX_TAKEN }), {
        status: 409,
        headers: jsonHeaders,
      });
    }

    if (captchaEnabled === "true" && req.cf_token) {
      const secret = typeof TURNSTILE_SECRET_KEY === "string" ? TURNSTILE_SECRET_KEY : "";
      const f = new FormData();
      f.append("secret", secret);
      f.append("response", req.cf_token);
      try {
        const vr = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
          method: "POST",
          body: f,
        });
        await vr.json();
      } catch (e) {}
    }

    let key = customKey || Math.random().toString(36).substring(2, 8);
    if (!customKey && suffixBlacklist.size) {
      let guard = 0;
      while (isSuffixBlocked(key, suffixBlacklist) && guard < 200) {
        key = Math.random().toString(36).substring(2, 8);
        guard++;
      }
      if (isSuffixBlocked(key, suffixBlacklist)) {
        return new Response(JSON.stringify({ error: "生成失败，请稍后重试" }), {
          status: 500,
          headers: jsonHeaders,
        });
      }
    }

    const hash = await sha512(reqUrl);
    const existKey = await LINKS.get(hash);

    if (!customKey && existKey && !isSuffixBlocked(existKey, suffixBlacklist)) {
      key = existKey;
    } else {
      await LINKS.put(key, reqUrl, { metadata: { createdAt: Date.now() } });
      if (!customKey) await LINKS.put(hash, key);
      invalidateAdminListCache();
    }

    return new Response(JSON.stringify({ key: "/" + key }), {
      headers: jsonHeaders,
    });
  }

  // 首页 or 重定向
  if (!path) return new Response(htmlIndex, { headers: htmlHeaders });

  if (isSuffixBlocked(path, suffixBlacklist)) {
    return new Response("封禁后缀", { status: 302 });
  }

  const target = await LINKS.get(path);
  if (target) return Response.redirect(target + url.search, 302);

  return new Response("短链不存在", { status: 404 });
}

addEventListener("fetch", (e) => e.respondWith(handleRequest(e.request)));
