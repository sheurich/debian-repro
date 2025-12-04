# Security Model

Threat model, trust dependencies, and detection methods.

## What We Detect

### Supply Chain Attacks

| Attack | Detected | How |
|--------|----------|-----|
| **Build process tampering** | Yes | Checksum mismatch reveals Debuerreotype modifications |
| **Artifacts repository changes** | Yes | Unauthorized checksum changes detected |
| **CI platform compromise** | Yes | Consensus failure reveals malicious platform |
| **Package substitution** | Yes | Version changes break reproducibility |

### What We Don't Detect

| Attack | Why |
|--------|-----|
| ~~Docker Hub tampering~~ | Now detected via registry verification |
| **Upstream package backdoors** | We verify assembly, not compilation |
| **Compiler backdoors** | Debian's build infrastructure is trusted |
| **Hardware tampering** | Out of scope |

### Registry Verification

`docker-debian-artifacts` serves as the source of truth. The registry verification workflow compares Docker Hub image layer diff_ids against official checksums daily, detecting tampering between artifact publication and registry distribution.

## Detection Methods

**Checksum mismatch**: SHA256 verification fails when artifacts differ from official.

**Cross-platform divergence**: Platforms disagree, revealing compromised CI or non-deterministic builds.

**Consensus failure**: Full agreement required. Any disagreement triggers investigation.

### Response to Detection

1. CI/CD build fails with error logs
2. Dashboard shows failed verification
3. Forensic data available (checksums, logs, parameters)
4. Investigation across platforms and architectures

## Trust Dependencies

### Infrastructure

| Component | Trust | Mitigation |
|-----------|-------|------------|
| **GitHub Actions** | Microsoft infrastructure | Cross-validated with GCP |
| **Google Cloud Build** | Google infrastructure | Cross-validated with GitHub |

Consensus detects single-platform compromise.

### Build Tools

| Component | Trust | Mitigation |
|-----------|-------|------------|
| **Debuerreotype v0.16** | Official Debian image builder | Pinned version, tag verification |

### Data Sources

| Component | Trust | Mitigation |
|-----------|-------|------------|
| **snapshot.debian.org** | Time-locked package archive | APT secure signing, GPG verification |
| **docker-debian-artifacts** | Official build parameters | Single trust point (see limitation above) |

### Container Images

| Image | Risk | Mitigation |
|-------|------|------------|
| **tonistiigi/binfmt** | Privileged QEMU setup | Digest-pinned, user confirmation, exits immediately |
| **multiarch/qemu-user-static** | Privileged QEMU fallback | Digest-pinned, exits immediately |

### Privileged Operations

**SYS_ADMIN capability**: Debuerreotype requires chroot/mount/namespace operations. Container isolation mitigates risk. No alternatives exist.

**Privileged containers**: Used only for binfmt setup. Brief execution, exits immediately, requires user confirmation in local builds.

## Trust Reduction

**Multi-platform consensus**: All platforms must agree. Detects single-platform compromise.

**Digest pinning**: Immutable SHA256 references prevent image substitution.

**Transparent operation**: Results and logs published in real-time.

**Community validation**: Anyone can verify locally with `./verify-local.sh`.

## Irreducible Trust

These cannot be eliminated:

1. **Debian packages** — we verify assembly, not compilation
2. **SHA256** — cryptographic function security
3. **Linux kernel** — isolation correctness
4. **CPU** — faithful instruction execution
5. **Verification scripts** — open source, auditable

## Investigated Alternatives

### Dual-Toolchain Verification (mmdebstrap)

We investigated mmdebstrap as a second toolchain to detect Debuerreotype-specific backdoors.

**Finding**: Not viable. mmdebstrap cannot produce outputs matching Debuerreotype checksums. The tools make incompatible decisions about filesystem ordering and metadata.

**Alternative approach**: Platform diversity (additional CI systems, community validators) rather than toolchain diversity.

## Why Reproducibility Matters

Reproducible builds shift security from "trust the builder" to "verify the build."

Bit-for-bit reproduction proves:
- **Assembly integrity** — no tampering in image creation
- **Distributed verification** — multiple independent verifiers must agree
- **Auditability** — anyone can reproduce and verify results

We verify the assembly process but trust Debian's package compilation. This protects against Docker image tampering while relying on Debian's compiler security.
