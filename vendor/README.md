# Vendor — Offline Dependencies

Pre-packaged dependencies for fully airgap deployment. No internet required during installation.

## Files

| File | Size | Purpose |
|------|------|---------|
| `ansible-collections-2025.1.tar.gz` | ~15MB | All Ansible collections needed by Kolla-Ansible |
| `requirements-kolla-venv.txt` | ~2KB | Pinned pip requirements for Kolla venv reproducibility |

## Why Vendor?

The production environment and lab operate under sanctions restrictions. Key registries are blocked or unreliable from Iran:
- `galaxy.ansible.com` — intermittent
- `opendev.org` — intermittent
- `pypi.org` — accessible but slow

Vendoring ensures deployment works with zero internet dependency.

## How It's Used

The `host-prepare.yml` playbook auto-detects these files:
- If `ansible-collections-2025.1.tar.gz` exists → installs from tarball (offline)
- If absent → falls back to online install from opendev.org

## Updating

To refresh vendored collections:
```bash
# On a machine with internet access
ansible-galaxy collection download -r requirements.yml -p /tmp/collections/
tar czf ansible-collections-2025.1.tar.gz -C /tmp/collections/ .
```

To update pip requirements:
```bash
pip freeze --path /opt/kolla-venv/lib/python3.12/site-packages > requirements-kolla-venv.txt
```
