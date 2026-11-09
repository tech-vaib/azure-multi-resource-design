variable "subscription_id" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "aks_name" { type = string }
variable "kubernetes_version" { type = string }
variable "subnet_id" {
  type        = string
  description = "Subnet ID exported by the shared network state. This root does not own the subnet."
}
