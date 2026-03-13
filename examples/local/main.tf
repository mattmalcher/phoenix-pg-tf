terraform {
  required_version = ">= 1.5"

  required_providers {
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.22"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "postgresql" {
  host      = "localhost"
  port      = 5432
  database  = "postgres"
  username  = "postgres"
  password  = "postgres"
  sslmode   = "disable"
  superuser = false
}

provider "vault" {
  address = "http://localhost:8200"
  token   = "root"
}

module "phoenix_db" {
  source = "../../modules/pg-logical-database"

  db_name       = var.db_name
  phoenix_role  = var.phoenix_role
  app_role      = var.app_role
  readonly_role = var.readonly_role

  vault_mount       = var.vault_mount
  vault_path_prefix = var.vault_path_prefix
}

output "database_name"       { value = module.phoenix_db.database_name }
output "phoenix_role_name"   { value = module.phoenix_db.phoenix_role_name }
output "app_role_name"       { value = module.phoenix_db.app_role_name }
output "readonly_role_name"  { value = module.phoenix_db.readonly_role_name }
output "vault_phoenix_path"  { value = module.phoenix_db.vault_phoenix_path }
output "vault_app_path"      { value = module.phoenix_db.vault_app_path }
output "vault_readonly_path" { value = module.phoenix_db.vault_readonly_path }
