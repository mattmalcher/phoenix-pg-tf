variable "db_name" {
  type        = string
  description = "Name of the logical database to create."
}

variable "phoenix_role" {
  type        = string
  description = "Name of the Phoenix owner role (DDL + DML)."
}

variable "app_role" {
  type        = string
  description = "Name of the DML role for other services writing to Phoenix tables."
}

variable "readonly_role" {
  type        = string
  description = "Name of the read-only role for dashboards/analytics."
}

variable "db_schema" {
  type        = string
  default     = "public"
  description = "Schema name. Defaults to \"public\"."
}

variable "vault_mount" {
  type        = string
  description = "Vault KV v2 mount path (e.g. \"secret\")."
}

variable "vault_path_prefix" {
  type        = string
  description = "Vault path prefix for credentials (e.g. \"postgres/phoenix\")."
}

variable "password_length" {
  type        = number
  default     = 32
  description = "Length of generated passwords. Defaults to 32."
}

variable "connection_limit" {
  type        = number
  default     = -1
  description = "Max connections per role. Defaults to -1 (unlimited)."
}

variable "revoke_public_schema" {
  type        = bool
  default     = true
  description = "Revoke default CREATE rights on the public schema from the public role."
}
