# Debian Reproducibility Verification System — Design Document

## Executive Summary

A verification system that confirms official Debian Docker images are
bit-for-bit reproducible from their published build parameters. The system
rebuilds images using infrastructure and tooling independent of the official
build pipeline, compares rootfs tarball checksums against official artifacts,
and publishes results to a public dashboard. Verification runs automatically
when upstream images change. The system distinguishes five verification states,
ensuring failures are surfaced with actionable metadata rather than silently
absorbed.

## System Goals

### Mission

Verify that official Debian Docker images are bit-for-bit reproducible from
their published build parameters, using infrastructure and tooling independent
of the official build pipeline. Make verification results publicly accessible.

### Primary Audience

Users of official Debian Docker images who want independent assurance that
published images match their declared source. The dashboard and badges are their
primary interface. Secondary audiences include Debian reproducibility
researchers and security auditors performing independent verification.

### Core Claim

For every supported architecture and active Debian suite: rebuilding from the
published serial, epoch, and snapshot URL produces rootfs tarballs whose SHA256
checksums are identical to the official artifacts.

### Primary Goals

1. **Verify official images on upstream change.** When the
   docker-debian-artifacts repository updates, rebuild affected architectures
   and suites and compare checksums against official output. Detect changes
   within 4 hours.

2. **Publish results publicly.** Maintain a dashboard showing current
   verification status per architecture and suite, with 30-day historical
   trends and embeddable status badges.

3. **Define and respond to failures.** Distinguish verification outcomes by type
   and ensure non-reproducible results are surfaced, not silently absorbed.

### Secondary Goals

4. **Enable local verification.** The project maintainer or any third party with
   macOS/arm64 or Linux can run a single command to verify their host
   architecture. Local results support development and independent spot-checks
   but are not authoritative.

5. **Support cross-platform spot-checks.** An optional second build platform
   (Google Cloud Build) can be invoked on demand to confirm platform
   independence. This is a self-check on the verification system, not a routine
   operation.

### Non-Functional Requirements

6. Zero long-lived credentials. All CI authentication uses OIDC/keyless
   mechanisms.
7. Local verification of a single suite on the host architecture completes in
   under 10 minutes with a warm Docker cache.
8. CI operating cost stays within GitHub Actions free tier for public
   repositories. Cloud Build costs are incurred only on manual invocation.

### Explicit Non-Goals

- **Root-cause diagnosis of non-reproducible builds.** The system reports
  mismatches with sufficient metadata to investigate. Diagnosis is a human
  activity.
- **Package-level reproducibility tracking.** Scope is Docker image rootfs
  tarball checksums, not individual .deb files.
- **Non-Debian distributions.** No abstraction layers for Ubuntu, Alpine, etc.
  If added later, it's a new project decision.
- **SLSA compliance or provenance attestation.** Potentially valuable but
  distinct from verification. Deferred.
- **Portability across Docker runtimes.** Developed on macOS with
  OrbStack/Colima, verified on Linux with Docker Engine. Other runtimes are not
  tested or supported.

### Design Principles

- **Deterministic.** Identical inputs produce bit-identical outputs.
- **Transparent.** All results, methodology, and build parameters are public.
- **Precise about failure.** Every verification run produces one of five defined
  states. No ambiguous results.
- **Minimal.** Verification runs only when upstream changes. Infrastructure
  exists only where it serves a stated goal.

## Verification States

Every suite/architecture result is one of:

| State | Meaning | Dashboard | Automated Response |
|---|---|---|---|
| `verified` | Rebuilt successfully, checksums match | Green | Update history and badges |
| `not-reproducible` | Rebuilt successfully, checksums differ | Red | Open GitHub Issue with diagnostics |
| `error` | Build did not complete | Yellow | Retry up to 3×, then open Issue |
| `blocked` | Upstream unavailable | Grey | Retry with backoff for 24h; transition to `error` if unresolved |
| `skipped` | Excluded from this run | Dimmed | None |

A `not-reproducible` result is the critical event. The auto-created issue
includes: suite, architecture, serial, epoch, expected and actual SHA256, build
log excerpt, link to official build parameters, and whether other
suite/architecture combinations for the same serial also failed.

## Architecture Support

| Architecture | Local (macOS arm64) | GitHub Actions | Role |
|---|---|---|---|
| arm64 | Native | Native (arm64 runner) | Primary local development target |
| amd64 | Rosetta/QEMU | Native | Primary CI target |
| armhf | CI only | QEMU or arm64 runner | CI verified |
| i386 | CI only | QEMU | CI verified |
| ppc64el | CI only | QEMU | CI verified |
| s390x | CI only | QEMU | Future |

Default local invocation detects host architecture and builds that. Explicit
`--arch` flag selects specific targets. Full multi-architecture verification
requires CI.

## Verification Triggers

| Trigger | What Runs | Platform | Frequency |
|---|---|---|---|
| Upstream change detected | Full verification of affected architectures | GitHub Actions | On change (checked hourly) |
| Weekly smoke test | Single suite, amd64 | GitHub Actions | Weekly |
| Manual invocation | Any combination of arch/suite | Local or Cloud Build | On demand |

Weekly smoke test uses amd64: it is the highest-traffic architecture and the
primary CI runner type, making it the best canary for infrastructure drift.

## Local Development Model

Scripts separate into two layers:

- **Orchestration**: parameter extraction, change detection, report generation,
  dashboard updates, badge creation. Fully functional on macOS.
- **Build execution**: Debuerreotype invocation with privileged Docker
  capabilities. Functional on macOS for host architecture via Colima/OrbStack's
  Linux VM. Authoritative only on CI.

This separation keeps the development loop fast: edit scripts locally, test
orchestration and reporting against fixture data, push to CI for authoritative
multi-architecture builds.

## Core Components

### Verification Engine

Two script layers with distinct responsibilities:

**Orchestration layer** (runs anywhere: macOS, Linux, CI):

- Fetch official build parameters from upstream sources
- Detect upstream changes via git commit comparison
- Select architectures and suites for verification
- Generate structured reports, dashboard data, and status badges
- Coordinate parallel execution across suites

**Build layer** (requires Linux Docker with privileged capabilities):

- Invoke Debuerreotype with exact official configuration
- Produce rootfs tarballs and compute SHA256 checksums
- Compare against official checksums
- Report one of five verification states per suite/architecture

### Build Platforms

**GitHub Actions (authoritative)**

- Triggered by upstream change detection and weekly smoke test
- Matrix builds across all supported architectures
- Native runners for amd64 and arm64; QEMU emulation for others
- Docker layer caching via GitHub Container Registry
- Publishes results to dashboard and generates status badges

**Local (development and spot-checks)**

- Single command: `./verify-local.sh` builds host architecture, all active
  suites
- `./verify-local.sh --arch arm64 --suite bookworm` for targeted runs
- Requires Docker with privileged container support (Colima or OrbStack on
  macOS, Docker Engine on Linux)
- Results are informational, not published to the dashboard

**Google Cloud Build (optional, on-demand)**

- Independent platform for cross-validating the verification system
- Invoked manually via `gcloud builds submit` or a dispatch workflow
- Keyless authentication via Workload Identity Federation
- Not part of automated verification; infrastructure is provisioned but not
  scheduled

### Public Dashboard

Static site hosted via GitHub Pages, updated by CI on each verification run.

- **Status matrix**: current state per architecture × suite, using all five
  verification states with color coding
- **Historical trends**: 30-day rolling view of verification results per
  architecture and suite
- **Detail view**: per-run metadata including serial, epoch, build duration, and
  checksum comparison
- **Badges**: Shields.io-compatible JSON endpoints for embedding in READMEs and
  external sites
- **Data format**: all dashboard state stored as static JSON files, consumable
  as a read-only API

## Verification Workflow

### Change Detection

1. Hourly scheduled workflow checks docker-debian-artifacts for new commits
2. Compares latest commit SHA against stored state
3. Identifies which architectures were updated
4. Triggers verification only for changed architectures
5. Updates stored commit SHA after successful verification

### Build and Compare

For each architecture/suite:

1. Fetch exact build parameters: serial, epoch, snapshot URL
2. Build using Debuerreotype with identical configuration
3. Compute SHA256 of output rootfs tarballs
4. Compare against official checksums
5. Assign verification state: `verified`, `not-reproducible`, `error`, or
   `blocked`
6. On `error`: retry up to 3 times before reporting
7. Record result with full metadata

### On-Demand Cross-Platform Spot-Check

Manually triggered to validate the verification system itself:

1. Select a specific serial/architecture/suite
2. Build on both GitHub Actions and Cloud Build
3. Compare output checksums between platforms
4. If platforms disagree, investigate the verification system — not Debian

## Data Architecture

### Report Schema

```json
{
  "timestamp": "ISO 8601",
  "verification_type": "official|smoke|manual",
  "serial": "YYYYMMDD",
  "epoch": "unix_timestamp",
  "trigger": "upstream_change|scheduled|manual",
  "architectures": {
    "<arch>": {
      "state": "verified|not-reproducible|error|blocked|skipped",
      "suites": {
        "<suite>": {
          "state": "verified|not-reproducible|error|blocked|skipped",
          "official_sha256": "hash or null",
          "local_sha256": "hash or null",
          "build_time_seconds": "number or null",
          "error_message": "string or null",
          "retries": "number"
        }
      }
    }
  },
  "platform": "github|cloudbuild|local"
}
```

Architecture-level `state` is derived: `not-reproducible` if any suite is
`not-reproducible`, `error` if any suite is `error` and none are
`not-reproducible`, `verified` if all suites are `verified`.

### Storage Strategy

- **Current state**: `dashboard/data/latest.json` — most recent official
  verification result
- **Historical data**: `dashboard/data/history.json` — rolling 30-day window of
  official verification results
- **Badge endpoints**: `dashboard/badges/*.json` — Shields.io format, one per
  architecture and one aggregate
- **Cloud artifacts**: GCS bucket with 30-day lifecycle policy (only populated
  on manual Cloud Build runs)

## Infrastructure

### Repository Layout

```
/
├── .github/workflows/
│   ├── check-updates.yml            # Hourly: detect upstream changes
│   ├── verify.yml                   # Main: full verification of changed architectures
│   ├── smoke.yml                    # Weekly: single-suite amd64 infrastructure health
│   ├── pages.yml                    # Dashboard deployment
│   ├── lint.yml                     # Shellcheck, yamllint
│   └── test.yml                     # BATS test suite
├── scripts/
│   ├── orchestration/               # Parameter extraction, reporting, change detection
│   └── build/                       # Debuerreotype invocation, checksum comparison
├── tests/
│   ├── fixtures/                    # Sample data for orchestration layer testing
│   └── ...
├── dashboard/                       # GitHub Pages: status, badges, data
├── docs/                            # Project documentation
│   └── plans/                       # Design documents (this file)
├── cloudbuild.yaml                  # Optional: on-demand spot-check configuration
└── verify-local.sh                  # Local entry point
```

### Google Cloud Platform (Optional)

Required only for on-demand cross-platform spot-checks:

- Service account with Cloud Build and GCS access
- Workload Identity Federation pool for keyless GitHub-to-GCP authentication
- GCS bucket for build artifacts (30-day lifecycle policy)

Not provisioned or incurring cost unless manually invoked.

## Security

### Principles

- Keyless authentication via OIDC tokens for all CI-to-cloud interactions
- Least-privilege IAM permissions scoped to Cloud Build and GCS only
- No long-lived credentials in repository secrets or environment
- Input validation and sanitization on all upstream-fetched parameters

### Trust Boundary

The system trusts build parameters published in the docker-debian-artifacts
repository. If that repository is compromised, verification will confirm
checksums against compromised parameters. This is an inherent limitation: the
system verifies reproducibility, not provenance.

Existing mitigations (implemented in `scripts/validate-artifacts-repo.sh`):

- Serial format validation (YYYYMMDD with valid ranges)
- Epoch bounds checking (rejects future timestamps or pre-2015 dates)
- Serial/epoch consistency verification
- Snapshot.debian.org availability confirmation

These detect fabricated or corrupted parameters but not legitimate-looking
malicious changes.

### Docker Configuration

Required capabilities for Debuerreotype:

- `SYS_ADMIN`: mount operations in chroot
- Drop `SETFCAP`: prevent capability modifications
- Unconfined seccomp/AppArmor: legacy compatibility
- Tmpfs with specific flags: deterministic builds

### Critical Parameters

- `SOURCE_DATE_EPOCH`: must match official timestamp exactly
- `snapshot.debian.org`: time-locked package repository
- Architecture naming: mapping between Debian and Docker conventions
- Output structure: nested directories by serial/arch/suite

## Quality

### Success Criteria

- 100% `verified` state for all supported suite/architecture combinations on
  official verification runs
- Upstream changes detected within 4 hours (hourly polling with retry headroom)
- Local single-suite host-architecture verification under 10 minutes (warm
  cache)
- Dashboard updated within 30 minutes of verification completion

### Monitoring

- Verification state distribution over time (trend toward 100% `verified`)
- Build duration per architecture and suite (detect performance regressions)
- Upstream change detection latency (polling health)
- `error` and `blocked` frequency (infrastructure reliability)
- GitHub Issues opened by automation (failure rate)

## Extensibility

### Adding Architectures

1. Architecture mapping configuration (Debian name ↔ Docker platform)
2. Runner or emulation setup in CI matrix
3. Documentation update to architecture support table

### Adding Suites

1. No code changes (configuration only)
2. Verification that snapshot.debian.org serves the new suite
3. Update to default suite list

### Integration Points

- **JSON data files** in `dashboard/data/` for programmatic access
- **Shields.io badges** for status display in external READMEs
- **GitHub Actions outputs** for workflow composition and downstream automation

## Performance

### Optimization Strategies

- Docker layer caching via GitHub Container Registry
- Parallel suite builds within each architecture (limited by CPU count)
- Shallow git clones for upstream parameter fetching
- Conditional architecture selection (build only what changed)
- Tmpfs for build operations where supported

### Resource Allocation

- **Local**: auto-detect CPU count for parallelism; arm64 native, amd64 via
  Rosetta/QEMU
- **GitHub Actions**: architecture-specific runners (amd64 native, arm64 native,
  QEMU for others)
- **Cloud Build** (when invoked): high-CPU machine type with sufficient disk for
  multi-suite builds
- **Storage**: 30-day retention on all historical data and cloud artifacts

## Future Enhancements

The following are explicitly deferred (see Non-Goals) but may be revisited:

- **Build provenance attestation and SLSA compliance.** Complementary to
  reproducibility verification but a distinct scope.
- **Package-level reproducibility tracking.** Finer-grained verification of
  individual .deb files within the rootfs.
- **Multi-distribution support.** Extending the methodology to Ubuntu, Alpine,
  or other distributions. Would require abstraction of the build parameter
  extraction and build tool layers.

Removed from consideration:

- ~~Federated verification network~~ — overengineered for the project's scale
- ~~CDN distribution for dashboard~~ — GitHub Pages is sufficient
- ~~Horizontal scaling via additional build platforms~~ — one authoritative
  platform plus optional spot-checks is the design

## Migration from Current Design

This document supersedes the current architecture where Cloud Build and
consensus validation are required components. Key changes:

| Area | Current | Revised |
|---|---|---|
| Cloud Build | Required, scheduled | Optional, on-demand |
| Consensus | Required (all platforms agree) | Spot-check only |
| Verification trigger | Weekly schedule | Event-driven (upstream change) |
| Failure model | Binary pass/fail | Five states with defined responses |
| Script architecture | Flat `scripts/` directory | Two-layer orchestration/build split |
| Dashboard data | 7-day history | 30-day history |
| Report schema | `success/failed/skipped` | Five states + error metadata |

Implementation should proceed incrementally:

1. **Orchestration layer**: extract parameter fetching, report generation, and
   change detection into `scripts/orchestration/`
2. **Build layer**: extract Debuerreotype invocation and checksum comparison
   into `scripts/build/`
3. **Five-state model**: update report schema and dashboard
4. **Change detection workflow**: implement `check-updates.yml`
5. **Simplify CI**: replace scheduled full builds with event-driven verification
6. **Demote Cloud Build**: move from required to optional
