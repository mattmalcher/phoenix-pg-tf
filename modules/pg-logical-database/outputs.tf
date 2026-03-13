output "database_name" {
  description = "The created database name."
  value       = postgresql_database.this.name
}

output "phoenix_role_name" {
  description = "The Phoenix owner role name."
  value       = postgresql_role.phoenix.name
}

output "app_role_name" {
  description = "The DML app role name."
  value       = postgresql_role.app.name
}

output "readonly_role_name" {
  description = "The read-only role name."
  value       = postgresql_role.readonly.name
}

output "vault_phoenix_path" {
  description = "Full Vault path for Phoenix credentials."
  value       = vault_kv_secret_v2.phoenix.path
}

output "vault_app_path" {
  description = "Full Vault path for app credentials."
  value       = vault_kv_secret_v2.app.path
}

output "vault_readonly_path" {
  description = "Full Vault path for readonly credentials."
  value       = vault_kv_secret_v2.readonly.path
}
