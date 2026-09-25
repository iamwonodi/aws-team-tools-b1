locals {
  platform = jsondecode(var.platform_json)

  tag       = "team-tools"
  name      = "${var.project_name}-${var.environment}-${local.tag}"
  asg_name  = "${local.name}-asg" # the name core's tools-role scopes
  iam_path  = "/services/${local.tag}/"
  env_label = title(var.environment)

  vpc_id          = local.platform.vpc_id
  subnet_ids      = local.platform.tools.subnet_ids
  tools_sg_id     = local.platform.tools.security_group_id
  ami_parameter   = local.platform.compute.ami_parameter
  boundary_arn    = local.platform.service_boundary_arn
  domain_name     = local.platform.domain_name
  dedicated       = local.platform.hosting_model == "dedicated"
  front_door_conf = try(local.platform.team_front_door, null)

  # The tools have web addresses only where core runs a front door (development,
  # staging). Production's are reached through a private tunnel.
  front_door = local.front_door_conf != null

  # The tools and their ports; each has the web address <tool>.<domain> where
  # there is a front door.
  tools = {
    dbgate      = { port = 3000, name_prefix = "tdbg-" }
    cloudbeaver = { port = 8978, name_prefix = "tcbv-" }
  }

  # ---- the databases -----------------------------------------------------------
  #
  # Managed (staging, production): every engine core's contract lists, over TLS
  # verified against AWS's RDS bundle. Development: the engines on the database
  # host, on their native ports, without TLS.

  native_ports = { postgres = 5432, mysql = 3306, mongodb = 27017 }
  engine_names = { postgres = "PostgreSQL", mysql = "MySQL", mongodb = "MongoDB" }

  managed_engines = try(local.platform.database.engines, {})

  connections = local.dedicated ? {
    for engine, config in local.managed_engines : engine => {
      host = config.host
      port = tonumber(config.port)
      tls  = true
    }
    } : {
    for engine in var.development_engines : engine => {
      host = local.platform.database.host
      port = local.native_ports[engine]
      tls  = false
    }
  }

  uses_tls  = anytrue([for c in values(local.connections) : c.tls])
  tls_mysql = try(local.connections.mysql.tls, false)

  # ---- DbGate: connections from environment variables --------------------------
  # (DbGate's packages/api/src/utility/envtools.js). askUser: every person types
  # their own username and password each time; nothing is stored.

  dbgate_engines = {
    postgres = "postgres@dbgate-plugin-postgres"
    mysql    = "mysql@dbgate-plugin-mysql"
    mongodb  = "mongo@dbgate-plugin-mongo"
  }

  dbgate_env = merge(
    { CONNECTIONS = join(",", sort(keys(local.connections))) },
    merge([
      for engine, c in local.connections : merge(
        {
          "LABEL_${engine}"         = "${local.env_label} ${local.engine_names[engine]}"
          "ENGINE_${engine}"        = local.dbgate_engines[engine]
          "SERVER_${engine}"        = c.host
          "PASSWORD_MODE_${engine}" = "askUser"
          # DocumentDB refuses retryable writes, the MongoDB driver's default.
          # DbGate passes no driver options, but pastes the port straight into
          # mongodb://user:password@<server>:<port>, so the option rides in the
          # port. authSource is already admin: with no database in the URL the
          # driver authenticates against admin.
          "PORT_${engine}" = engine == "mongodb" && c.tls ? "${c.port}/?retryWrites=false" : tostring(c.port)
        },
        c.tls ? {
          "USE_SSL_${engine}"                 = "1"
          "SSL_CA_FILE_${engine}"             = "/certs/rds-global-bundle.pem"
          "SSL_REJECT_UNAUTHORIZED_${engine}" = "1"
        } : {},
      )
    ]...),
  )

  # ---- CloudBeaver: pre-filled connections (its workspace's data-sources.json) --
  # CloudBeaver Community has no MongoDB, so PostgreSQL and MySQL only. Nobody
  # saves a password; everyone signs in to the database as themselves.

  cloudbeaver_certs = "/opt/cloudbeaver/certs"

  cloudbeaver_connections = {
    for engine, c in local.connections : engine => {
      provider        = engine == "postgres" ? "postgresql" : "mysql"
      driver          = engine == "postgres" ? "postgres-jdbc" : "mysql8"
      name            = "${local.env_label} ${local.engine_names[engine]}"
      "save-password" = false
      configuration = {
        host              = c.host
        port              = tostring(c.port)
        database          = engine == "postgres" ? "postgres" : ""
        url               = engine == "postgres" ? "jdbc:postgresql://${c.host}:${c.port}/postgres" : "jdbc:mysql://${c.host}:${c.port}/"
        configurationType = "MANUAL"
        type              = "dev"
        "auth-model"      = "native"
        # Every service's database, not only the one named above.
        "provider-properties" = engine == "postgres" ? { "@dbeaver-show-non-default-db@" = "true" } : {}
        properties = !c.tls ? {} : engine == "postgres" ? {
          sslmode     = "verify-full"
          sslrootcert = "${local.cloudbeaver_certs}/rds-global-bundle.pem"
          } : {
          sslMode                          = "VERIFY_IDENTITY"
          trustCertificateKeyStoreUrl      = "file:${local.cloudbeaver_certs}/rds-truststore.p12"
          trustCertificateKeyStoreType     = "PKCS12"
          trustCertificateKeyStorePassword = "rds-public-certificates"
        }
      }
    } if engine != "mongodb"
  }

  cloudbeaver_data_sources = jsonencode({ folders = {}, connections = local.cloudbeaver_connections })

  # ---- the servers' Compose file ------------------------------------------------

  compose = yamlencode({
    services = {
      dbgate = {
        image    = var.images.dbgate
        restart  = "unless-stopped"
        ports    = ["3000:3000"]
        env_file = ["dbgate.env"]
        volumes  = ["./certs:/certs:ro"]
      }
      cloudbeaver = {
        image    = var.images.cloudbeaver
        restart  = "unless-stopped"
        ports    = ["8978:8978"]
        env_file = ["cloudbeaver.env"]
        environment = {
          # Anyone through the front door (or the tunnel) is a user; connections
          # are the prepared ones, credentials are never saved, and nobody adds
          # connections of their own.
          CLOUDBEAVER_APP_ANONYMOUS_ACCESS_ENABLED                   = "true"
          CLOUDBEAVER_APP_GRANT_CONNECTIONS_ACCESS_TO_ANONYMOUS_TEAM = "true"
          CLOUDBEAVER_APP_PUBLIC_CREDENTIALS_SAVE_ENABLED            = "false"
          CLOUDBEAVER_APP_ADMIN_CREDENTIALS_SAVE_ENABLED             = "false"
          CLOUDBEAVER_APP_SUPPORTS_CUSTOM_CONNECTIONS                = "false"
        }
        volumes = [
          "./certs:${local.cloudbeaver_certs}:ro",
          "./cloudbeaver/data-sources.json:/opt/cloudbeaver/workspace/GlobalConfiguration/.dbeaver/data-sources.json",
        ]
      }
    }
  })

  user_data = templatefile("${path.module}/templates/start-tools.sh.tftpl", {
    compose_b64         = base64encode(local.compose)
    dbgate_env_b64      = base64encode(join("\n", [for k in sort(keys(local.dbgate_env)) : "${k}=${local.dbgate_env[k]}"]))
    data_sources_b64    = base64encode(local.cloudbeaver_data_sources)
    uses_tls            = local.uses_tls
    tls_mysql           = local.tls_mysql
    rds_bundle_sha256   = var.rds_bundle_sha256
    cloudbeaver_image   = var.images.cloudbeaver
    server_name         = "${local.env_label} team tools"
    truststore_password = "rds-public-certificates"
  })
}
