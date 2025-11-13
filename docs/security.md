# Security Model

Security analysis, threat model, and trust dependencies for debian-repro.

## Threat Model

### What This System Defends Against

#### Supply Chain Attacks We Detect

*Current:*
- **Build Process Tampering**: Detects modifications in Debuerreotype build process
- **Artifacts Repository Changes**: Identifies checksum changes in `docker-debian-artifacts`
- **Single-CI Compromise**: Consensus failure reveals malicious CI platform
- **Package Substitution**: Version changes break reproducibility

*Planned:*
- **Registry Tampering**: Direct Docker Hub verification (closes artifacts-to-registry gap)
- **Toolchain Compromise**: mmdebstrap cross-validation detects Debuerreotype backdoors

**Current Limitation**: `docker-debian-artifacts` repository is our single trust point. We verify builds but miss tampering between repository and Docker Hub.

#### Attack Scenarios

*Detected:*
1. **Build Process Compromise**: Toolchain or parameter changes
2. **CI Platform Compromise**: Consensus failure reveals malicious platform

*Not Detected (Planned):*
1. **Docker Hub Compromise**: Post-publication tampering
2. **Artifacts Repository Compromise**: Needs independent Docker Hub verification
3. **Toolchain Backdoors**: Needs mmdebstrap cross-validation

### Out of Scope

- **Upstream Source Compromise**: Malicious code in legitimate packages
- **Package Compiler Backdoors**: Ken Thompson-style attacks in compilers that built Debian packages
  - **Why**: We download pre-compiled .deb packages, not source code
  - **Trust Required**: Debian's build infrastructure and compiler toolchains
- **Hardware Tampering**: CPU or firmware modifications
- **Zero-Day Vulnerabilities**: Unpatched flaws in legitimate software

### Partial Protection: Build Tool Backdoors

Multi-platform consensus and dual-toolchain verification detect backdoors in assembly tools (Debuerreotype, mmdebstrap):

*Current:*
- **Multi-Platform Consensus**: GitHub Actions and Google Cloud Build must agree
- **Detection**: Platform-dependent tool backdoors cause checksum disagreements

*Planned:*
- **Dual-Toolchain**: Debuerreotype and mmdebstrap must produce identical output
- **Detection**: Tool-specific backdoors cause output disagreements

**Limitation**: Cannot detect backdoors in Debian's package compilers or platform-independent tool backdoors.

### Detection Methods

*Current:*
- **Checksum Mismatch**: SHA256 verification fails on artifacts repository modifications
- **Cross-Platform Divergence**: Platforms disagree, revealing compromised CI
- **Temporal Anomalies**: Unexpected checksum changes between verifications
- **Consensus Failure**: All CI systems must agree

*Planned:*
- **Registry Tampering**: Direct Docker Hub verification catches post-publication modifications
- **Toolchain Disagreement**: Debuerreotype and mmdebstrap diverge, indicating compromise
- **Pattern Disruption**: Selective tampering across architectures or suites

*Response:*
1. Fail CI/CD build with error logs
2. Update dashboard showing failed images
3. Provide forensic data (checksums, logs, parameters)
4. Enable triage across platforms and architectures

### Trust Requirements

*Required:*
- **Debian Packages**: We verify assembly, not package compilation
- **Debian Build Infrastructure**: Compilers (GCC, Clang) that built packages
- **Cryptographic Functions**: SHA256 remains secure
- **Build Environment**: Verification infrastructure remains secure
- **Artifacts Repository**: `docker-debian-artifacts` (single trust point until Docker Hub verification)

*Trust Reduction:*
- **Multi-Perspective Consensus**: All CI platforms must agree
- **Planned: Dual-Toolchain**: Debuerreotype and mmdebstrap must match
- **Planned: Independent Validators**: Community verification distributes trust
- **Planned: Registry Verification**: Docker Hub checks eliminate artifacts repository dependency

### Why Reproducibility Matters

Reproducible builds shift security from "trust the builder" to "verify the build." Bit-for-bit recreation proves:
- **Assembly integrity**: No tampering in image creation process
- **Distributed trust**: Multiple independent verifiers must agree
- **Independent verification**: Anyone can reproduce results
- **Audit trails**: Historical verification data

**Trust Boundary**: We verify the assembly process (debootstrap, Debuerreotype) but trust Debian's package compilation. This protects against Docker image tampering while relying on Debian's compiler security.

## Trust Dependencies

This verification system requires trust in several components. Understanding these dependencies helps assess the security model and identify potential compromise vectors.

### Infrastructure Dependencies

**GitHub Actions**: Primary CI/CD platform. Trusts GitHub infrastructure, runner images, actions. Mitigated by cross-validation with Google Cloud Build. Consensus detects single-platform tampering.

**Google Cloud Build**: Independent verification platform. Trusts GCP infrastructure, build environments, artifact storage. Mitigated by checksum comparison with GitHub Actions.

### Build Tool Dependencies

**Debuerreotype**: Official Debian image builder (v0.16). Trusts maintainers and repository integrity. Pinned version with Git tag/SHA verification. Dual-toolchain verification (planned) detects tool-specific tampering.

**mmdebstrap** (Planned): Independent debootstrap alternative. Must produce bit-identical output to Debuerreotype. Dual compromise less likely than single tool.

### Data Source Dependencies

**snapshot.debian.org**: Time-locked package archive. Trusts Debian infrastructure and archive integrity. Cryptographic verification via APT secure signing and GPG. Multiple verifiers detect inconsistencies.

**docker-debian-artifacts**: Official build parameters and checksums. Trusts Debian Docker team and repository integrity. Read-only access; tampering fails verification. Historical tracking detects unexpected changes.

### Container Image Dependencies

**tonistiigi/binfmt**: QEMU registration for cross-architecture emulation. Digest-pinned (`@sha256:e06789...`). Runs with `--privileged` flag (user confirmation required, exits immediately). Only for setup, not verification.

**multiarch/qemu-user-static**: Fallback QEMU for Linux. Digest-pinned (`@sha256:7ebfd8...`). Same security concerns as tonistiigi/binfmt.

### Registry Dependencies

**Docker Hub**: Official Debian distribution. Trusts Docker Inc. and registry infrastructure. Verification system proves images match source. Checksum mismatches reveal compromise.

**GHCR** (Planned): Daily build storage. Trusts GitHub infrastructure and attestation signing. Signed attestations and consensus required before publishing.

### Privileged Capabilities

**SYS_ADMIN Required**: Debuerreotype needs chroot/mount/namespace operations. Container isolation mitigates risks. No alternatives exist.

**Privileged Containers** (`--privileged`): Used only for binfmt/QEMU setup. Modifies kernel settings briefly, exits immediately, requires user confirmation.

**Build Containers** (`--cap-add SYS_ADMIN`): Limited capabilities, drops SETFCAP, isolated within namespace.

### Trust Reduction

- **Multi-Perspective Consensus**: All platforms must agree. Detects single-platform compromise.
- **Dual-Toolchain** (Planned): Debuerreotype and mmdebstrap must match. Dual compromise harder than single.
- **Digest Pinning**: Immutable SHA256 references prevent substitution.
- **Transparent Operation**: Results and logs published in real-time.
- **Community Validation**: Anyone can verify locally.

### Irreducible Trust

Fundamental requirements:

1. **Debian Packages**: We verify assembly, not package compilation
2. **Cryptographic Functions**: SHA256 security
3. **Linux Kernel**: Isolation correctness
4. **CPU Architecture**: Faithful instruction execution
5. **Our Scripts**: Open source, requires review or trust

Reproducible builds shift trust from builder to verification.
