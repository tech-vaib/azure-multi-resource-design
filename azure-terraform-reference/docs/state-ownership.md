# State ownership rules

1. A physical Azure resource is managed by exactly one Terraform state.
2. Shared VNet/subnets/NAT are owned by the shared network state.
3. Environment states consume shared resource IDs; they do not redeclare shared resources as managed resources.
4. A resource managed by a different state should be consumed through remote-state outputs or an Azure data source.
5. Import is for adopting an unmanaged resource, not for reusing a resource.
6. Moving ownership requires a reviewed state migration, backup, and plans from both source and destination.
7. Keep shared states out of routine environment destroy workflows.
8. Never delete a state file to resolve an ownership conflict.
