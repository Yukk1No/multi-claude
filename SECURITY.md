# Security

multi-claude only creates launchers and icons for your user. It never reads, copies or sends
credentials, and it never modifies Claude Desktop. Each profile's sign-in lives in its own data
folder, managed by Claude itself.

The install commands download a versioned release and refuse to install unless its SHA-256 matches
the value written into the installer at release time. Releases carry GitHub build provenance
attestations (`gh attestation verify <file> --repo thomasog/multi-claude`). You can also read the
scripts first or install from a clone.

To report a vulnerability, use GitHub's **private vulnerability reporting** (Security tab, then
"Report a vulnerability") rather than a public issue.
