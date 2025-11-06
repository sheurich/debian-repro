// Dashboard JavaScript for Debian Reproducibility Verification

const DATA_URL = './data/latest.json';
const HISTORY_URL = './data/history.json';

// State
let latestReport = null;
let history = [];

/**
 * Initialize dashboard
 */
async function init() {
  try {
    await loadData();
    renderOverview();
    renderMatrix();
    renderArchitectureDetails();
    renderTrendChart();
    hideLoading();
  } catch (error) {
    showError('Failed to load verification data: ' + error.message);
  }
}

/**
 * Load latest report and history
 */
async function loadData() {
  try {
    const response = await fetch(DATA_URL);
    if (!response.ok) throw new Error('Latest report not available');
    latestReport = await response.json();
  } catch (error) {
    console.warn('Latest report not available, using placeholder data');
    latestReport = createPlaceholderData();
  }

  try {
    const response = await fetch(HISTORY_URL);
    if (response.ok) {
      history = await response.json();
    }
  } catch (error) {
    console.warn('History not available');
    history = [];
  }
}

/**
 * Create placeholder data for initial setup
 */
function createPlaceholderData() {
  return {
    timestamp: new Date().toISOString(),
    run_id: 'placeholder',
    serial: 'YYYYMMDD',
    epoch: 0,
    architectures: {
      amd64: {
        status: 'success',
        suites: {
          bookworm: { reproducible: true, sha256: 'pending...', build_time_seconds: 0 },
          trixie: { reproducible: true, sha256: 'pending...', build_time_seconds: 0 }
        }
      }
    }
  };
}

/**
 * Hide loading indicator
 */
function hideLoading() {
  document.getElementById('loading').style.display = 'none';
  document.getElementById('overview-cards').style.display = 'grid';
}

/**
 * Show error message
 */
function showError(message) {
  const loading = document.getElementById('loading');
  loading.textContent = '⚠️ ' + message;
  loading.style.color = '#e74c3c';
}

/**
 * Render overview cards
 */
function renderOverview() {
  const stats = calculateStats();
  const container = document.getElementById('overview-cards');

  container.innerHTML = `
    <div class="card ${stats.allReproducible ? 'success' : 'warning'}">
      <div class="card-title">Reproducibility Rate</div>
      <div class="card-value">${stats.rate}%</div>
      <div class="card-subtitle">${stats.reproducible}/${stats.total} suites</div>
    </div>

    <div class="card">
      <div class="card-title">Architectures</div>
      <div class="card-value">${stats.architectures}</div>
      <div class="card-subtitle">${stats.successfulArchs} passing</div>
    </div>

    <div class="card">
      <div class="card-title">Last Verified</div>
      <div class="card-value">${formatDate(latestReport.timestamp)}</div>
      <div class="card-subtitle">Serial: ${latestReport.serial}</div>
    </div>

    <div class="card">
      <div class="card-title">Build Time</div>
      <div class="card-value">${stats.avgBuildTime}s</div>
      <div class="card-subtitle">Average per suite</div>
    </div>
  `;
}

/**
 * Calculate statistics from latest report
 */
function calculateStats() {
  const archs = latestReport.architectures;
  const archKeys = Object.keys(archs);

  let totalSuites = 0;
  let reproducibleSuites = 0;
  let totalBuildTime = 0;
  let successfulArchs = 0;

  archKeys.forEach(arch => {
    const archData = archs[arch];
    if (archData.status === 'success') successfulArchs++;

    Object.values(archData.suites).forEach(suite => {
      totalSuites++;
      if (suite.reproducible) reproducibleSuites++;
      totalBuildTime += suite.build_time_seconds || 0;
    });
  });

  const rate = totalSuites > 0 ? Math.round((reproducibleSuites / totalSuites) * 100) : 0;
  const avgBuildTime = totalSuites > 0 ? Math.round(totalBuildTime / totalSuites) : 0;

  return {
    total: totalSuites,
    reproducible: reproducibleSuites,
    rate,
    architectures: archKeys.length,
    successfulArchs,
    avgBuildTime,
    allReproducible: reproducibleSuites === totalSuites && totalSuites > 0
  };
}

/**
 * Render verification matrix table
 */
function renderMatrix() {
  const archs = latestReport.architectures;
  const archKeys = Object.keys(archs);

  // Get all unique suites
  const allSuites = new Set();
  archKeys.forEach(arch => {
    Object.keys(archs[arch].suites).forEach(suite => allSuites.add(suite));
  });
  const suites = Array.from(allSuites).sort();

  // Build table
  let html = '<table><thead><tr><th>Architecture</th>';
  suites.forEach(suite => {
    html += `<th>${suite}</th>`;
  });
  html += '</tr></thead><tbody>';

  archKeys.forEach(arch => {
    html += `<tr><td><strong>${arch}</strong></td>`;
    suites.forEach(suite => {
      const suiteData = archs[arch].suites[suite];
      if (suiteData) {
        const status = suiteData.reproducible ? 'success' : 'failed';
        const label = suiteData.reproducible ? '✅ Pass' : '❌ Fail';
        html += `<td><span class="status-badge status-${status}">${label}</span></td>`;
      } else {
        html += '<td><span class="status-badge status-unknown">N/A</span></td>';
      }
    });
    html += '</tr>';
  });

  html += '</tbody></table>';
  document.getElementById('verification-matrix').innerHTML = html;
}

/**
 * Render architecture details accordion
 */
function renderArchitectureDetails() {
  const archs = latestReport.architectures;
  const container = document.getElementById('arch-accordion');
  let html = '';

  Object.keys(archs).forEach((arch, index) => {
    const archData = archs[arch];
    const statusClass = archData.status === 'success' ? 'success' : 'danger';
    const statusIcon = archData.status === 'success' ? '✅' : '❌';

    html += `
      <div class="accordion-item">
        <div class="accordion-header" onclick="toggleAccordion(${index})">
          <span>${statusIcon} <strong>${arch}</strong></span>
          <span>${Object.keys(archData.suites).length} suites</span>
        </div>
        <div class="accordion-body" id="accordion-${index}">
          <ul class="suite-list">
    `;

    Object.entries(archData.suites).forEach(([suite, data]) => {
      const reproClass = data.reproducible ? 'reproducible' : 'not-reproducible';
      const reproIcon = data.reproducible ? '✅' : '❌';
      html += `
        <li class="suite-item ${reproClass}">
          <div class="suite-name">${reproIcon} ${suite}</div>
          <div class="suite-details">
            SHA256: ${data.sha256 || data.our_sha256 || 'N/A'}<br>
            Build time: ${data.build_time_seconds || 0}s
          </div>
        </li>
      `;
    });

    html += `
          </ul>
        </div>
      </div>
    `;
  });

  container.innerHTML = html;
}

/**
 * Toggle accordion item
 */
function toggleAccordion(index) {
  const body = document.getElementById(`accordion-${index}`);
  body.classList.toggle('active');
}

/**
 * Render 30-day trend chart
 */
function renderTrendChart() {
  const ctx = document.getElementById('trend-chart');

  // If no history, show placeholder
  if (history.length === 0) {
    ctx.parentElement.innerHTML = '<p style="text-align: center; color: #6c757d; padding: 2rem;">No historical data available yet. Check back after a few builds!</p>';
    return;
  }

  // Prepare data (last 30 days)
  const last30Days = history.slice(-30);
  const labels = last30Days.map(r => formatDate(r.timestamp));
  const rates = last30Days.map(r => {
    const stats = calculateStatsForReport(r);
    return stats.rate;
  });

  new Chart(ctx, {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: 'Reproducibility Rate (%)',
        data: rates,
        borderColor: '#d70a53',
        backgroundColor: 'rgba(215, 10, 83, 0.1)',
        tension: 0.4,
        fill: true
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: true,
      plugins: {
        legend: {
          display: false
        },
        tooltip: {
          callbacks: {
            label: (context) => `${context.parsed.y}% reproducible`
          }
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          max: 100,
          ticks: {
            callback: (value) => value + '%'
          }
        }
      }
    }
  });
}

/**
 * Calculate stats for a specific report
 */
function calculateStatsForReport(report) {
  const archs = report.architectures;
  let totalSuites = 0;
  let reproducibleSuites = 0;

  Object.values(archs).forEach(archData => {
    Object.values(archData.suites).forEach(suite => {
      totalSuites++;
      if (suite.reproducible) reproducibleSuites++;
    });
  });

  const rate = totalSuites > 0 ? Math.round((reproducibleSuites / totalSuites) * 100) : 0;
  return { total: totalSuites, reproducible: reproducibleSuites, rate };
}

/**
 * Format ISO date to readable format
 */
function formatDate(isoString) {
  const date = new Date(isoString);
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', init);
