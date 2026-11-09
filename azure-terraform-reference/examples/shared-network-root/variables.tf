variable "subscription_id" {
  type        = string
  description = "Target Azure subscription ID."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group that owns the VNet and its subnets."
}

variable "vnet_name" {
  type        = string
  description = "VNet name."
}

variable "address_space" {
  type        = list(string)
  description = "VNet address spaces."
}

variable "subnets" {
  type = map(object({
    address_prefixes = list(string)
  }))
  description = "Subnets owned by this network state."
}
