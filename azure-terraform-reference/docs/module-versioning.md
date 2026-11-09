# Module versioning

- Keep modules focused and reusable.
- Each live root pins a released module version or immutable Git ref.
- Do not use an unpinned main branch for production.
- Use semantic versioning: patch fixes, minor backward-compatible features, major breaking changes.
- Test module releases in Dev, then promote to Stage and Prod.
- Maintain provider/module compatibility records and commit .terraform.lock.hcl in each root where appropriate.
