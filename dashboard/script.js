/**
 * Debian Reproducibility Verification Dashboard
 *
 * Design philosophy: Edward Tufte principles
 * - Minimal chartjunk, maximum data-ink ratio
 * - Dense information display with micro/macro reading
 * - Typography-first, static pre-rendering where possible
 * - Progressive enhancement for optional features
 *
 * @author sheurich@fastly.com
 * @version 2.0.0
 */

'use strict';

// =============================================================================
// Configuration & Constants
// =============================================================================

/** @const {string} URL for latest verification report */
const DATA_URL_LATEST = './data/latest.json';

/** @const {string} URL for historical verification reports */
const DATA_URL_HISTORY = './data/history.json';

/** @const {string} URL for latest consensus report */
const DATA_URL_CONSENSUS = './data/consensus/latest.json';

/** @const {number} Number of days to show in sparklines */
const SPARKLINE_DAYS = 7;

// =============================================================================
// State Management
// =============================================================================

/**
 * Global state object
 * @type {{
 *   latest: Object|null,
 *   history: Array<Object>,
 *   consensus: Object|null,
 *   loaded: boolean
 * }}
 */
const state = {
  latest: null,
  history: [],
  consensus: null,
  loaded: false
};

// =============================================================================
// Data Loading
// =============================================================================

/**
 * Initialize dashboard by loading data and rendering all sections
 * @returns {Promise<void>}
 */
async function init() {
  try {
    await loadData();
    renderAll();
    generateJSONLD();
    state.loaded = true;
  } catch (error) {
    handleError(error);
  }
}

/**
 * Load both latest report and historical data
 * Falls back to placeholder data if latest report unavailable
 * @returns {Promise<void>}
 */
async function loadData() {
  // Load latest report
  try {
    const response = await fetch(DATA_URL_LATEST);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    state.latest = await response.json();
  } catch (error) {
    console.warn('Latest report unavailable, using placeholder:', error.message);
    state.latest = createPlaceholderData();
  }

  // Load historical data (optional)
  try {
    const response = await fetch(DATA_URL_HISTORY);
    if (response.ok) {
      state.history = await response.json();
    }
  } catch (error) {
    console.warn('History unavailable:', error.message);
    state.history = [];
  }

  // Load consensus data (optional)
  try {
    const response = await fetch(DATA_URL_CONSENSUS);
    if (response.ok) {
      state.consensus = await response.json();
    }
  } catch (error) {
    console.warn('Consensus data unavailable:', error.message);
    state.consensus = null;
  }
}

/**
 * Create placeholder data for initial display
 * @returns {Object} Placeholder verification report
 */
function createPlaceholderData() {
  return {
    timestamp: new Date().toISOString(),
    run_id: 'pending',
    serial: 'YYYYMMDD',
    epoch: 0,
    environment: { platform: 'pending', runner: 'pending' },
    architectures: {}
  };
}

// =============================================================================
// Rendering Functions
// =============================================================================

/**
 * Render all dashboard sections
 */
function renderAll() {
  renderSummaryBar();
  renderStatusMatrix();
  renderDetailsTable();
  renderHistorySparklines();
  updateLastUpdate();
}

/**
 * Render summary statistics bar (single line of key metrics)
 * Format: "X% reproducible | N/M architectures | Xs avg build | Serial YYYYMMDD"
 */
function renderSummaryBar() {
  const container = document.getElementById('summary-bar');
  const stats = calculateStats(state.latest);

  // Build consensus stat if available
  let consensusStat = '';
  if (state.consensus) {
    const consensusAchieved = state.consensus.consensus?.achieved || false;
    const consensusRate = state.consensus.summary?.consensus_rate || 0;
    const platforms = state.consensus.platforms?.length || 0;

    const consensusClass = consensusAchieved ? 'consensus-pass' : 'consensus-fail';
    const consensusIcon = consensusAchieved ? '✓' : '✗';
    const consensusLabel = consensusAchieved ? 'consensus' : `${(consensusRate * 100).toFixed(0)}% agree`;

    consensusStat = `
      <span class="stat ${consensusClass}" title="Multi-platform consensus: ${platforms} platforms compared">
        <span class="stat-value">${consensusIcon} ${platforms}</span>
        <span class="stat-label">${consensusLabel}</span>
      </span>
    `;
  }

  container.innerHTML = `
    <div class="summary-stats">
      <span class="stat">
        <span class="stat-value">${stats.rate}%</span>
        <span class="stat-label">reproducible</span>
      </span>
      <span class="stat">
        <span class="stat-value">${stats.successfulArchs}/${stats.totalArchs}</span>
        <span class="stat-label">architectures</span>
      </span>
      <span class="stat">
        <span class="stat-value">${stats.totalSuites}</span>
        <span class="stat-label">suites</span>
      </span>
      ${consensusStat}
      <span class="stat">
        <span class="stat-value">${stats.avgBuildTime}s</span>
        <span class="stat-label">avg build</span>
      </span>
      <span class="stat">
        <span class="stat-value">Serial ${state.latest.serial}</span>
        <span class="stat-label">${formatDateShort(state.latest.timestamp)}</span>
      </span>
    </div>
  `;
}

/**
 * Render status matrix table (primary data display)
 * Shows architecture × suite grid with status, build time, and sparklines
 */
function renderStatusMatrix() {
  const container = document.getElementById('matrix-table');
  const archs = state.latest.architectures;
  const archKeys = Object.keys(archs).sort();

  if (archKeys.length === 0) {
    container.innerHTML = '<p>No verification data available yet.</p>';
    return;
  }

  // Get all unique suites across architectures
  const allSuites = new Set();
  archKeys.forEach(arch => {
    Object.keys(archs[arch].suites || {}).forEach(suite => allSuites.add(suite));
  });
  const suites = Array.from(allSuites).sort();

  // Build table header
  let html = '<table class="matrix"><thead><tr>';
  html += '<th scope="col">Architecture</th>';
  suites.forEach(suite => {
    html += `<th scope="col">${suite}</th>`;
  });
  html += '<th scope="col">Success Rate</th>';
  html += '</tr></thead><tbody>';

  // Build table rows (one per architecture)
  archKeys.forEach(arch => {
    const archData = archs[arch];
    const archSuites = archData.suites || {};

    html += `<tr><th scope="row">${arch}</th>`;

    // Suite cells
    suites.forEach(suite => {
      const suiteData = archSuites[suite];
      if (suiteData) {
        const cellClass = suiteData.reproducible ? 'cell-pass' : 'cell-fail';
        const status = suiteData.reproducible ? '✓' : '✗';
        const time = suiteData.build_time_seconds || 0;
        const sparkline = renderInlineSparkline(arch, suite);

        html += `<td class="${cellClass}">
          <div class="cell-content">
            <span class="cell-status">${status}</span>
            ${time > 0 ? `<span class="cell-time">${time}s</span>` : ''}
            ${sparkline}
          </div>
        </td>`;
      } else {
        html += '<td class="cell-na">—</td>';
      }
    });

    // Architecture success rate
    const archStats = calculateArchStats(archData);
    html += `<td>${archStats.rate}%</td>`;
    html += '</tr>';
  });

  // Summary footer row
  html += '</tbody><tfoot><tr>';
  html += '<td>Overall</td>';
  suites.forEach(suite => {
    const suiteStats = calculateSuiteStats(suite, archs);
    html += `<td>${suiteStats.rate}%</td>`;
  });
  const overallStats = calculateStats(state.latest);
  html += `<td>${overallStats.rate}%</td>`;
  html += '</tr></tfoot></table>';

  container.innerHTML = html;
}

/**
 * Render details table showing SHA256 checksums and build times
 * with inline bar charts for build duration comparison
 */
function renderDetailsTable() {
  const container = document.getElementById('details-content');
  const archs = state.latest.architectures;
  const archKeys = Object.keys(archs).sort();

  if (archKeys.length === 0) {
    container.innerHTML = '<p>No details available.</p>';
    return;
  }

  // Find max build time for bar chart scaling
  let maxBuildTime = 0;
  archKeys.forEach(arch => {
    Object.values(archs[arch].suites || {}).forEach(suite => {
      maxBuildTime = Math.max(maxBuildTime, suite.build_time_seconds || 0);
    });
  });

  // Build table
  let html = '<table><thead><tr>';
  html += '<th scope="col">Architecture</th>';
  html += '<th scope="col">Suite</th>';
  html += '<th scope="col">Status</th>';
  html += '<th scope="col">SHA256</th>';
  html += '<th scope="col">Build Time</th>';
  html += '</tr></thead><tbody>';

  archKeys.forEach(arch => {
    const archData = archs[arch];
    const suiteEntries = Object.entries(archData.suites || {}).sort((a, b) =>
      a[0].localeCompare(b[0])
    );

    suiteEntries.forEach(([suite, data], idx) => {
      const status = data.reproducible ? '✓ Reproducible' : '✗ Not Reproducible';
      const statusClass = data.reproducible ? 'cell-pass' : 'cell-fail';
      const sha = data.sha256 || data.our_sha256 || 'N/A';
      const shaShort = sha.substring(0, 8);
      const buildTime = data.build_time_seconds || 0;
      const barWidth = maxBuildTime > 0 ? (buildTime / maxBuildTime) * 100 : 0;

      html += '<tr>';
      html += `<td>${idx === 0 ? arch : ''}</td>`;
      html += `<td>${suite}</td>`;
      html += `<td class="${statusClass}">${status}</td>`;
      html += `<td><span class="sha256" data-full="${sha}" title="${sha}">${shaShort}…</span></td>`;
      html += `<td>
        <div class="build-time">
          <span class="time-value">${buildTime}s</span>
          <div class="time-bar" style="width: ${barWidth}%"></div>
        </div>
      </td>`;
      html += '</tr>';
    });
  });

  html += '</tbody></table>';
  container.innerHTML = html;
}

/**
 * Render 7-day history sparklines for each architecture
 * Shows trend of reproducibility rate over time
 */
function renderHistorySparklines() {
  const container = document.getElementById('history-sparklines');

  if (state.history.length < 2) {
    container.innerHTML = '<p>Historical data will appear after multiple builds.</p>';
    return;
  }

  const archs = Object.keys(state.latest.architectures).sort();
  const recentHistory = state.history.slice(-SPARKLINE_DAYS);

  let html = '<div class="history-sparklines">';

  archs.forEach(arch => {
    // Calculate rates for this architecture across history
    const rates = recentHistory.map(report => {
      const archData = report.architectures[arch];
      if (!archData) return null;
      const stats = calculateArchStats(archData);
      return stats.rate;
    });

    const currentRate = rates[rates.length - 1] || 0;
    const svg = generateSparklineSVG(rates);

    html += `
      <div class="sparkline-item">
        <span class="sparkline-label">${arch}</span>
        ${svg}
        <span class="sparkline-value">${currentRate}%</span>
      </div>
    `;
  });

  html += '</div>';
  container.innerHTML = html;
}

/**
 * Update "last updated" timestamp in footer
 */
function updateLastUpdate() {
  const el = document.getElementById('last-update');
  if (el && state.latest) {
    el.textContent = formatDateLong(state.latest.timestamp);
  }
}

// =============================================================================
// Statistics Calculations
// =============================================================================

/**
 * Calculate overall statistics from a verification report
 * @param {Object} report - Verification report object
 * @returns {{
 *   totalArchs: number,
 *   successfulArchs: number,
 *   totalSuites: number,
 *   reproducibleSuites: number,
 *   rate: number,
 *   avgBuildTime: number
 * }}
 */
function calculateStats(report) {
  const archs = report.architectures || {};
  const archKeys = Object.keys(archs);

  let totalSuites = 0;
  let reproducibleSuites = 0;
  let totalBuildTime = 0;
  let successfulArchs = 0;

  archKeys.forEach(arch => {
    const archData = archs[arch];
    if (archData.status === 'success') successfulArchs++;

    Object.values(archData.suites || {}).forEach(suite => {
      totalSuites++;
      if (suite.reproducible) reproducibleSuites++;
      totalBuildTime += suite.build_time_seconds || 0;
    });
  });

  const rate = totalSuites > 0
    ? Math.round((reproducibleSuites / totalSuites) * 100)
    : 0;

  const avgBuildTime = totalSuites > 0
    ? Math.round(totalBuildTime / totalSuites)
    : 0;

  return {
    totalArchs: archKeys.length,
    successfulArchs,
    totalSuites,
    reproducibleSuites,
    rate,
    avgBuildTime
  };
}

/**
 * Calculate statistics for a single architecture
 * @param {Object} archData - Architecture data from report
 * @returns {{total: number, reproducible: number, rate: number}}
 */
function calculateArchStats(archData) {
  const suites = Object.values(archData.suites || {});
  const total = suites.length;
  const reproducible = suites.filter(s => s.reproducible).length;
  const rate = total > 0 ? Math.round((reproducible / total) * 100) : 0;

  return { total, reproducible, rate };
}

/**
 * Calculate statistics for a single suite across all architectures
 * @param {string} suite - Suite name
 * @param {Object} archs - All architectures from report
 * @returns {{total: number, reproducible: number, rate: number}}
 */
function calculateSuiteStats(suite, archs) {
  let total = 0;
  let reproducible = 0;

  Object.values(archs).forEach(archData => {
    const suiteData = (archData.suites || {})[suite];
    if (suiteData) {
      total++;
      if (suiteData.reproducible) reproducible++;
    }
  });

  const rate = total > 0 ? Math.round((reproducible / total) * 100) : 0;
  return { total, reproducible, rate };
}

// =============================================================================
// Sparkline Generation
// =============================================================================

/**
 * Render inline sparkline SVG for a specific architecture/suite combo
 * Shows last 7 data points as a tiny line chart
 * @param {string} arch - Architecture name
 * @param {string} suite - Suite name
 * @returns {string} SVG HTML string or empty string
 */
function renderInlineSparkline(arch, suite) {
  if (state.history.length < 2) return '';

  const recent = state.history.slice(-SPARKLINE_DAYS);
  const values = recent.map(report => {
    const archData = report.architectures[arch];
    const suiteData = (archData?.suites || {})[suite];
    return suiteData ? (suiteData.reproducible ? 1 : 0) : null;
  }).filter(v => v !== null);

  if (values.length < 2) return '';

  return generateSparklineSVG(values, 40, 16);
}

/**
 * Generate sparkline SVG from array of values
 * @param {Array<number>} values - Data points to plot
 * @param {number} [width=100] - SVG width in pixels
 * @param {number} [height=24] - SVG height in pixels
 * @returns {string} SVG HTML string
 */
function generateSparklineSVG(values, width = 100, height = 24) {
  if (!values || values.length < 2) return '';

  const filteredValues = values.filter(v => v !== null);
  if (filteredValues.length < 2) return '';

  const min = Math.min(...filteredValues);
  const max = Math.max(...filteredValues);
  const range = max - min || 1;

  const points = filteredValues.map((val, idx) => {
    const x = (idx / (filteredValues.length - 1)) * width;
    const y = height - ((val - min) / range) * height;
    return `${x},${y}`;
  }).join(' ');

  return `
    <svg class="sparkline"
         width="${width}"
         height="${height}"
         viewBox="0 0 ${width} ${height}"
         aria-hidden="true">
      <polyline
        points="${points}"
        fill="none"
        stroke="currentColor"
        stroke-width="1.5"
        vector-effect="non-scaling-stroke" />
    </svg>
  `;
}

// =============================================================================
// JSON-LD Structured Data
// =============================================================================

/**
 * Generate and inject JSON-LD structured data for search engines
 * Uses Schema.org vocabulary for Dataset and SoftwareApplication types
 */
function generateJSONLD() {
  const stats = calculateStats(state.latest);

  const structuredData = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Dataset",
        "name": "Debian Reproducibility Verification Data",
        "description": "Bit-for-bit verification results of official Debian Docker images",
        "url": "https://sheurich.github.io/debian-repro/",
        "license": "https://opensource.org/licenses/MIT",
        "creator": {
          "@type": "Person",
          "name": "Shiloh Heurich",
          "email": "sheurich@fastly.com"
        },
        "distribution": [
          {
            "@type": "DataDownload",
            "encodingFormat": "application/json",
            "contentUrl": "https://sheurich.github.io/debian-repro/data/latest.json"
          },
          {
            "@type": "DataDownload",
            "encodingFormat": "text/csv",
            "contentUrl": "https://sheurich.github.io/debian-repro/data/latest.csv"
          },
          {
            "@type": "DataDownload",
            "encodingFormat": "application/ld+json",
            "contentUrl": "https://sheurich.github.io/debian-repro/data/latest.jsonld"
          }
        ],
        "temporalCoverage": state.latest.timestamp,
        "variableMeasured": [
          {
            "@type": "PropertyValue",
            "name": "reproducibility_rate",
            "value": stats.rate,
            "unitText": "percent"
          },
          {
            "@type": "PropertyValue",
            "name": "verified_architectures",
            "value": stats.totalArchs
          },
          {
            "@type": "PropertyValue",
            "name": "verified_suites",
            "value": stats.totalSuites
          }
        ]
      },
      {
        "@type": "SoftwareApplication",
        "name": "Debian Reproducibility Verification Dashboard",
        "applicationCategory": "DeveloperApplication",
        "operatingSystem": "Any",
        "offers": {
          "@type": "Offer",
          "price": "0",
          "priceCurrency": "USD"
        },
        "codeRepository": "https://github.com/sheurich/debian-repro"
      }
    ]
  };

  const script = document.getElementById('structured-data');
  if (script) {
    script.textContent = JSON.stringify(structuredData, null, 2);
  }
}

// =============================================================================
// Utility Functions
// =============================================================================

/**
 * Format ISO date to short format (MMM DD, YYYY)
 * @param {string} isoString - ISO 8601 date string
 * @returns {string} Formatted date
 */
function formatDateShort(isoString) {
  const date = new Date(isoString);
  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric'
  });
}

/**
 * Format ISO date to long format (Month DD, YYYY at HH:MM UTC)
 * @param {string} isoString - ISO 8601 date string
 * @returns {string} Formatted date
 */
function formatDateLong(isoString) {
  const date = new Date(isoString);
  return date.toLocaleString('en-US', {
    month: 'long',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'UTC',
    timeZoneName: 'short'
  });
}

/**
 * Handle and display errors
 * @param {Error} error - Error object
 */
function handleError(error) {
  console.error('Dashboard error:', error);
  const loading = document.getElementById('loading');
  if (loading) {
    loading.textContent = `Error loading data: ${error.message}`;
    loading.style.color = '#8b0000';
  }
}

// =============================================================================
// Initialization
// =============================================================================

// Initialize dashboard when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}

// Expose state for debugging in development
if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
  window.dashboardState = state;
}
