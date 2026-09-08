variable "name" {
  description = "Lowercase name prefix for networking resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be 3-63 lowercase alphanumeric or hyphen characters and start/end alphanumeric."
  }
}

variable "vpc_cidr" {
  description = "RFC1918 IPv4 CIDR for the VPC."
  type        = string

  validation {
    condition = can(cidrhost(var.vpc_cidr, 0)) && can(regex(
      "^(10\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.|192\\.168\\.)",
      var.vpc_cidr,
    ))
    error_message = "vpc_cidr must be a valid RFC1918 IPv4 CIDR."
  }
}

variable "private_subnet_newbits" {
  description = "Additional prefix bits used by cidrsubnet to derive the two private subnets."
  type        = number

  validation {
    condition     = var.private_subnet_newbits >= 1 && var.private_subnet_newbits <= 8 && floor(var.private_subnet_newbits) == var.private_subnet_newbits
    error_message = "private_subnet_newbits must be an integer between 1 and 8."
  }
}

variable "private_subnet_netnums" {
  description = "Exactly two distinct non-negative subnet numbers within the newbits address space."
  type        = list(number)

  validation {
    condition = length(var.private_subnet_netnums) == 2 && alltrue([
      for netnum in var.private_subnet_netnums :
      netnum >= 0 &&
      floor(netnum) == netnum &&
      netnum < pow(2, var.private_subnet_newbits) &&
      can(cidrsubnet(var.vpc_cidr, var.private_subnet_newbits, netnum))
    ]) && var.private_subnet_netnums[0] != var.private_subnet_netnums[1]
    error_message = "private_subnet_netnums must contain two distinct non-negative integers below 2^private_subnet_newbits."
  }
}

variable "availability_zones" {
  description = "Exactly two distinct availability zones in ap-southeast-2."
  type        = list(string)

  validation {
    condition = length(var.availability_zones) == 2 &&
      var.availability_zones[0] != var.availability_zones[1] &&
      alltrue([
        for availability_zone in var.availability_zones : can(regex(
          "^ap-southeast-2[a-z]$",
          availability_zone,
        ))
      ])
    error_message = "availability_zones must contain two distinct ap-southeast-2 availability-zone names."
  }
}

variable "tags" {
  description = "Complete project tag contract; no defaults are supplied."
  type        = map(string)

  validation {
    condition = alltrue([
      for key in [
        "Project",
        "Environment",
        "Owner",
        "ManagedBy",
        "CostCenter",
        "DataClassification",
      ] : trimspace(lookup(var.tags, key, "")) != ""
      ]) && lookup(var.tags, "ManagedBy", "") == "terraform" &&
      contains(["dev", "prod"], lookup(var.tags, "Environment", "")) &&
      contains(
        ["public", "internal", "confidential", "restricted"],
        lookup(var.tags, "DataClassification", ""),
      )
    error_message = "tags must include non-empty Project, Environment, Owner, ManagedBy, CostCenter, and DataClassification; ManagedBy must be terraform and values must be approved."
  }
}
