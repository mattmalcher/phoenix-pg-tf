# Terraform Module: PostgreSQL Logical Database with Least-Privilege Accounts

## Overview

Create a reusable Terraform module that provisions a logical PostgreSQL database,
three roles (Phoenix owner, app DML, read-only), and stores all credentials in Vault.
Passwords are generated via the `random` provider and never appear in plaintext in
state after being written to Vault.

### Why only one role for Phoenix?

Phoenix runs Alembic migrations automatically on every startup via a single database
connection — there is no separate migration URL or flag to disable auto-migration.
Because DDL (CREATE TABLE, ALTER TABLE, CREATE INDEX) and DML (SELECT, INSERT, etc.)
share the same connection, Phoenix must connect as a role that can do both. Splitting
into a migration role vs. a runtime role is not possible without modifying Phoenix.

The practical least-privilege posture for Phoenix is therefore a single **owner role**
that:
- Owns the database and all objects in it
- Has `LOGIN`
- Has `CREATEDB = false`, `CREATEROLE = false`, `SUPERUSER = false`
- Is scoped to only the Phoenix database (no cross-database grants)

The **app** and **readonly** roles are for other services consuming Phoenix's data
(dashboards, analytics pipelines, data exports). Phoenix itself does not use them.

---

## Providers Required

```hcl
terraform {
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
```

The `postgresql` provider is configured by the **caller** (not inside the module).
The caller must connect as a superuser or RDS master user to be able to create roles
and databases. Set `superuser = false` on the provider block when using RDS/Aurora.

---

## Module Inputs

| Variable | Type | Required | Description |
|---|---|---|---|
| `db_name` | `string` | yes | Name of the logical database to create |
| `phoenix_role` | `string` | yes | Name of the Phoenix owner role (DDL + DML) |
| `app_role` | `string` | yes | Name of the DML role for other services writing to Phoenix tables |
| `readonly_role` | `string` | yes | Name of the read-only role for dashboards/analytics |
| `db_schema` | `string` | no | Schema name, defaults to `"public"` |
| `vault_mount` | `string` | yes | Vault KV v2 mount path (e.g. `"secret"`) |
| `vault_path_prefix` | `string` | yes | Vault path prefix (e.g. `"postgres/phoenix"`) |
| `password_length` | `number` | no | Password length, defaults to `32` |
| `connection_limit` | `number` | no | Max connections per role, defaults to `-1` (unlimited) |
| `revoke_public_schema` | `bool` | no | Revoke default public schema CREATE rights, defaults to `true` |

## Module Outputs

| Output | Description |
|---|---|
| `database_name` | The created database name |
| `phoenix_role_name` | The Phoenix owner role name |
| `app_role_name` | The DML app role name |
| `readonly_role_name` | The read-only role name |
| `vault_phoenix_path` | Full Vault path for Phoenix credentials |
| `vault_app_path` | Full Vault path for app credentials |
| `vault_readonly_path` | Full Vault path for readonly credentials |

---

## Resources to Create

### 1. Passwords (`random_password`)

One per role. Use `lifecycle { ignore_changes = [result] }` so Terraform doesn't
regenerate on every plan. Increment `password_wo_version` to trigger intentional rotation.

```
random_password.phoenix
random_password.app
random_password.readonly
```

### 2. Roles (`postgresql_role`)

**Phoenix role** — DDL + DML, owns all objects:

```hcl
resource "postgresql_role" "phoenix" {
  name                = var.phoenix_role
  login               = true
  superuser           = false
  create_database     = false
  create_role         = false
  inherit             = true
  connection_limit    = var.connection_limit
  password_wo         = random_password.phoenix.result
  password_wo_version = 1
}
```

**App role** — DML only, for other services writing to Phoenix's tables:
- `login = true`, `superuser = false`, `create_database = false`, `create_role = false`

**Readonly role** — SELECT only, for dashboards, analytics, data exports:
- `login = true`, `superuser = false`, `create_database = false`, `create_role = false`

### 3. Database (`postgresql_database`)

```hcl
resource "postgresql_database" "this" {
  name              = var.db_name
  owner             = postgresql_role.phoenix.name
  connection_limit  = -1
  allow_connections = true
}
```

### 4. Schema permissions (`postgresql_schema`)

Phoenix gets create + usage. App and readonly get usage only (no DDL).

```hcl
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
```

If `var.revoke_public_schema` is true, also revoke CREATE from the `public` role via
a `postgresql_grant` with `privileges = []` and `object_type = "schema"`.

### 5. Grants on existing objects (`postgresql_grant`)

**Phoenix role** — full ownership privileges:
- Tables: `["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER"]`
- Sequences: `["USAGE", "SELECT", "UPDATE"]`

**App role** — DML only:
- Tables: `["SELECT", "INSERT", "UPDATE", "DELETE"]`
- Sequences: `["USAGE", "SELECT"]`

**Readonly role**:
- Tables: `["SELECT"]`
- Sequences: `["SELECT"]`

### 6. Default privileges (`postgresql_default_privileges`)

Ensures tables and sequences created by **future** Phoenix migrations are automatically
accessible to consumer roles. The `owner` arg must be the Phoenix role — this is
critical because Phoenix owns everything it creates.

```hcl
resource "postgresql_default_privileges" "app_tables" {
  database    = postgresql_database.this.name
  schema      = var.db_schema
  role        = postgresql_role.app.name
  owner       = postgresql_role.phoenix.name
  object_type = "table"
  privileges  = ["SELECT", "INSERT", "UPDATE", "DELETE"]
}

resource "postgresql_default_privileges" "readonly_tables" {
  database    = postgresql_database.this.name
  schema      = var.db_schema
  role        = postgresql_role.readonly.name
  owner       = postgresql_role.phoenix.name
  object_type = "table"
  privileges  = ["SELECT"]
}

# Repeat pattern for sequences (object_type = "sequence")
```

### 7. Vault secrets (`vault_kv_secret_v2`)

One secret per role:

```
vault_kv_secret_v2.phoenix  → "${var.vault_path_prefix}/phoenix"
vault_kv_secret_v2.app      → "${var.vault_path_prefix}/app"
vault_kv_secret_v2.readonly → "${var.vault_path_prefix}/readonly"
```

Each secret's `data_json`:
```json
{
  "username": "<role_name>",
  "password": "<generated_password>",
  "database": "<db_name>",
  "host":     ""
}
```

Leave `host` blank — it should be populated by the caller or fetched separately,
since the module doesn't know the cluster endpoint.

---

## Dependency Order

1. `random_password` — no dependencies
2. `postgresql_role` — depends on passwords (implicit via `password_wo`)
3. `postgresql_database` — depends on Phoenix role
4. `postgresql_schema` — depends on database + all three roles
5. `postgresql_grant` — depends on schema + respective role
6. `postgresql_default_privileges` — depends on grants + Phoenix role (as `owner`)
7. `vault_kv_secret_v2` — depends on respective role + password

---

## Known Gotchas

- **Phoenix needs DDL at boot** — there is no env var or flag to disable auto-migration.
  Do not give Phoenix a role that can only do DML; it will fail on startup.
- **`password_wo` vs `password`** — use `password_wo` to keep plaintext out of
  Terraform state. Pair with `password_wo_version` and increment to rotate.
- **`superuser = false` on provider** — required when connecting to RDS/Aurora.
- **Default privileges vs existing grants** — `postgresql_default_privileges` only
  covers *future* objects. `postgresql_grant` covers objects that already exist.
  Both are needed because Phoenix creates new tables on every migration run.
- **Phoenix owns its objects** — consumer role default privileges must set
  `owner = phoenix_role`. Grants referencing a different owner won't apply to
  tables Phoenix creates.
- **Schema drift on `postgresql_grant`** — the provider uses REVOKE-then-GRANT
  internally. If grants are modified outside Terraform, plans will show replacements.
  This is expected and safe to apply.

---

## Example Caller Usage

```hcl
provider "postgresql" {
  host      = var.pg_host
  port      = 5432
  database  = "postgres"
  username  = var.pg_admin_user
  password  = var.pg_admin_password
  sslmode   = "require"
  superuser = false
}

provider "vault" {
  address = var.vault_address
}

module "phoenix_db" {
  source = "./modules/pg-logical-database"

  db_name       = "phoenix"
  phoenix_role  = "phoenix"
  app_role      = "phoenix_app"
  readonly_role = "phoenix_readonly"

  vault_mount       = "secret"
  vault_path_prefix = "postgres/phoenix"
}
```
