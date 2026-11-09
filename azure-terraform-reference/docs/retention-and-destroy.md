# Retention and destroy policy

Classify each resource as shared, environment, critical, retained, or disposable.

- shared: owned by a shared state and excluded from environment teardown.
- environment: may be destroyed with that environment after approval.
- critical: use static Terraform prevent_destroy where appropriate and Azure CanNotDelete locks.
- retained: detach or transfer ownership without deleting the Azure resource, using reviewed removed blocks or state migration.
- disposable: eligible for approved destruction.

Important:
- prevent_destroy is static and must remain in configuration.
- A lock can block Terraform deletion until deliberately removed.
- Setting count to zero or enabled=false on a previously managed resource usually plans deletion.
- Always review destroy plans, back up state, and check dependencies before decommissioning.
