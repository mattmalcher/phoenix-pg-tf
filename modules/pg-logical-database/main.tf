# ──────────────────────────────────────────────
# 1. Passwords
# ──────────────────────────────────────────────

resource "random_password" "phoenix" {
  length  = var.password_length
  special = true

  lifecycle {
    ignore_changes = [result]
  }
}

resource "random_password" "app" {
  length  = var.password_length
  special = true

  lifecycle {
    ignore_changes = [result]
  }
}

resource "random_password" "readonly" {
  length  = var.password_length
  special = true

  lifecycle {
    ignore_changes = [result]
  }
}

# ──────────────────────────────────────────────
# 2. Roles
# ──────────────────────────────────────────────

resource "postgresql_role" "phoenix" {
  name             = var.phoenix_role
  login            = true
  superuser        = false
  create_database  = false
  create_role      = false
  inherit          = true
  connection_limit = var.connection_limit

  password_wo         = random_password.phoenix.result
  password_wo_version = 1
}

resource "postgresql_role" "app" {
  name             = var.app_role
  login            = true
  superuser        = false
  create_database  = false
  create_role      = false
  inherit          = true
  connection_limit = var.connection_limit

  password_wo         = random_password.app.result
  password_wo_version = 1
}

resource "postgresql_role" "readonly" {
  name             = var.readonly_role
  login            = true
  superuser        = false
  create_database  = false
  create_role      = false
  inherit          = true
  connection_limit = var.connection_limit

  password_wo         = random_password.readonly.result
  password_wo_version = 1
}

# ──────────────────────────────────────────────
# 3. Database
# ──────────────────────────────────────────────

resource "postgresql_database" "this" {
  name              = var.db_name
  owner             = postgresql_role.phoenix.name
  connection_limit  = -1
  allow_connections = true
}

# ──────────────────────────────────────────────
# 4. Schema permissions
# ──────────────────────────────────────────────

resource "postgresql_schema" "this" {
  name     = var.db_schema
  database = postgresql_database.this.name
  owner    = postgresql_role.phoenix.name

  policy {
    create = true
    usage  = true
    role   = postgresql_role.phoenix.name
  }

  policy {
    usage = true
    role  = postgresql_role.app.name
  }

  policy {
    usage = true
    role  = postgresql_role.readonly.name
  }
}

# Revoke CREATE on the public schema from the public role (hardening).
resource "postgresql_grant" "revoke_public_schema" {
  count = var.revoke_public_schema ? 1 : 0

  database    = postgresql_database.this.name
  schema      = var.db_schema
  role        = "public"
  object_type = "schema"
  privileges  = []

  depends_on = [postgresql_schema.this]
}

# ──────────────────────────────────────────────
# 5. Grants on existing objects
# ──────────────────────────────────────────────

resource "postgresql_grant" "phoenix_tables" {
  database    = postgresql_database.this.name
  schema      = var.db_schema
  role        = postgresql_role.phoenix.name
  object_type = "table"
  privileges  = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER"]

  depends_on = [postgresql_schema.this]
}

resource "postgresql_grant" "phoenix_sequences" {
  database    = postgresql_database.this.name
  schema      = var.db_schema
  role        = postgresql_role.phoenix.name
  object_type = "sequence"
  privileges  = ["USAGE", "SELECT", "UPDATE"]

  depends_on = [postgresql_schema.this]
}

resource "postgresql_grant" "app_tables" {
  database    = postgresql_database.this.name
  schema      = var.db_schema
  role        = postgresql_role.app.name
  object_type = "table"
  privileges  = ["SELECT", "INSERT", "UPDATE", "DELETE"]

  depends_on = [postgresql_schema.this]
}

resource "postgresql_grant" "app_sequences" {
  database    = postgresql_database.this.name
  schema      = var.db_schema
  role        = postgresql_role.app.name
  object_type = "sequence"
  privileges  = ["USAGE", "SELECT"]

  depends_on = [postgresql_schema.this]
}

resource "postgresql_grant" "readonly_tables" {
  database    = postgresql_database.this.name
  schema      = var.db_schema
  role        = postgresql_role.readonly.name
  object_type = "table"
  privileges  = ["SELECT"]

  depends_on = [postgresql_schema.this]
}

resource "postgresql_grant" "readonly_sequences" {
  database    = postgresql_database.this.name
  schema      = var.db_schema
  role        = postgresql_role.readonly.name
  object_type = "sequence"
  privileges  = ["SELECT"]

  depends_on = [postgresql_schema.this]
}

# ──────────────────────────────────────────────
# 6. Default privileges (future objects)
# ──────────────────────────────────────────────

resource "postgresql_default_privileges" "app_tables" {
  database    = postgresql_database.this.name
  schema      = var.db_schema
  role        = postgresql_role.app.name
  owner       = postgresql_role.phoenix.name
  object_type = "table"
  privileges  = ["SELECT", "INSERT", "UPDATE", "DELETE"]

  depends_on = [
    postgresql_grant.app_tables,
    postgresql_grant.phoenix_tables,
  ]
}

resource "postgresql_default_privileges" "app_sequences" {
  database    = postgresql_database.this.name
  schema      = var.db_schema
  role        = postgresql_role.app.name
  owner       = postgresql_role.phoenix.name
  object_type = "sequence"
  privileges  = ["USAGE", "SELECT"]

  depends_on = [
    postgresql_grant.app_sequences,
    postgresql_grant.phoenix_sequences,
  ]
}

resource "postgresql_default_privileges" "readonly_tables" {
  database    = postgresql_database.this.name
  schema      = var.db_schema
  role        = postgresql_role.readonly.name
  owner       = postgresql_role.phoenix.name
  object_type = "table"
  privileges  = ["SELECT"]

  depends_on = [
    postgresql_grant.readonly_tables,
    postgresql_grant.phoenix_tables,
  ]
}

resource "postgresql_default_privileges" "readonly_sequences" {
  database    = postgresql_database.this.name
  schema      = var.db_schema
  role        = postgresql_role.readonly.name
  owner       = postgresql_role.phoenix.name
  object_type = "sequence"
  privileges  = ["SELECT"]

  depends_on = [
    postgresql_grant.readonly_sequences,
    postgresql_grant.phoenix_sequences,
  ]
}

# ──────────────────────────────────────────────
# 7. Vault secrets
# ──────────────────────────────────────────────

resource "vault_kv_secret_v2" "phoenix" {
  mount = var.vault_mount
  name  = "${var.vault_path_prefix}/phoenix"

  data_json = jsonencode({
    username = postgresql_role.phoenix.name
    password = random_password.phoenix.result
    database = postgresql_database.this.name
    host     = ""
  })
}

resource "vault_kv_secret_v2" "app" {
  mount = var.vault_mount
  name  = "${var.vault_path_prefix}/app"

  data_json = jsonencode({
    username = postgresql_role.app.name
    password = random_password.app.result
    database = postgresql_database.this.name
    host     = ""
  })
}

resource "vault_kv_secret_v2" "readonly" {
  mount = var.vault_mount
  name  = "${var.vault_path_prefix}/readonly"

  data_json = jsonencode({
    username = postgresql_role.readonly.name
    password = random_password.readonly.result
    database = postgresql_database.this.name
    host     = ""
  })
}
