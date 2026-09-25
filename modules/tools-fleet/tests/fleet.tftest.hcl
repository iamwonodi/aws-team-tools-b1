# Run with: terraform init -backend=false && terraform test   (no AWS access needed)
#
# Three contracts, shaped as core publishes them: development (shared, the
# database host, a front door), staging (dedicated, managed databases, a front
# door) and production (dedicated, managed databases, no front door).
# Assertions use only values known at plan time.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = { arn = "arn:aws:iam::123456789012:instance-profile/services/team-tools/core-development-team-tools-hosts" }
  }

  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:af-south-1:123456789012:targetgroup/tdbg-1/abc" }
  }
}

variables {
  project_name      = "core"
  environment       = "development"
  schedule_days     = "MON-FRI"
  rds_bundle_sha256 = "e5bb2084ccf45087bda1c9bffdea0eb15ee67f0b91646106e466714f9de3c7e3"

  images = {
    dbgate      = "dbgate/dbgate:7.3.1"
    cloudbeaver = "dbeaver/cloudbeaver:25.3.5"
  }

  platform_json = <<-JSON
    {
      "schema_version": 1,
      "domain_name": "dev.example.org",
      "vpc_id": "vpc-0abc",
      "hosting_model": "shared",
      "compute": { "ami_parameter": "/core/platform/ami/ubuntu" },
      "service_boundary_arn": "arn:aws:iam::123456789012:policy/platform/core-service-boundary",
      "tools": { "security_group_id": "sg-0tools", "subnet_ids": ["subnet-0p1", "subnet-0p2"] },
      "team_front_door": { "user_pool_id": "af-south-1_Abc", "user_pool_arn": "arn:aws:cognito-idp:af-south-1:123456789012:userpool/af-south-1_Abc", "domain": "core-development-team-123456789012", "declaration_prefix": "front-door/" },
      "database": { "host": "db.dev.example.org", "engines": {} },
      "tiers": { "private": { "security_group_id": "sg-0priv", "alb_security_group_id": "sg-0alb", "listener_arn": "arn:aws:elasticloadbalancing:af-south-1:123456789012:listener/app/core-private/abc/def" } }
    }
  JSON
}

run "development_the_database_host_without_tls" {
  command = plan

  assert {
    condition     = output.connections.postgres.host == "db.dev.example.org" && output.connections.postgres.port == 5432 && output.connections.mongodb.port == 27017 && !output.connections.mysql.tls
    error_message = "development: the database host, each engine on its native port, no TLS"
  }

  assert {
    condition     = local.dbgate_env.CONNECTIONS == "mongodb,mysql,postgres" && local.dbgate_env.ENGINE_mongodb == "mongo@dbgate-plugin-mongo" && local.dbgate_env.PASSWORD_MODE_postgres == "askUser"
    error_message = "DbGate: every engine, each person typing their own login"
  }

  assert {
    condition     = local.dbgate_env.PORT_mongodb == "27017" && !contains(keys(local.dbgate_env), "USE_SSL_postgres")
    error_message = "no TLS options, and no DocumentDB workaround, on the database host"
  }

  assert {
    condition     = sort(keys(jsondecode(local.cloudbeaver_data_sources).connections)) == tolist(["mysql", "postgres"])
    error_message = "CloudBeaver: PostgreSQL and MySQL (Community has no MongoDB)"
  }

  assert {
    condition     = !strcontains(local.user_data, "truststore.pki.rds.amazonaws.com")
    error_message = "no certificate bundle to fetch without TLS"
  }
}

run "the_servers_are_spot_on_a_schedule_and_wear_core_s_group" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.this.name == "core-development-team-tools-asg" && aws_autoscaling_group.this.max_size == 1 && aws_autoscaling_group.this.desired_capacity == 0
    error_message = "the group core's role scopes, one server at most, off until started"
  }

  assert {
    condition     = aws_autoscaling_group.this.mixed_instances_policy[0].instances_distribution[0].on_demand_percentage_above_base_capacity == 0 && aws_autoscaling_group.this.mixed_instances_policy[0].instances_distribution[0].on_demand_base_capacity == 0
    error_message = "spot only"
  }

  assert {
    condition     = aws_autoscaling_schedule.start.recurrence == "0 8 * * MON-FRI" && aws_autoscaling_schedule.stop.recurrence == "0 19 * * MON-FRI" && aws_autoscaling_schedule.start.time_zone == "Africa/Lagos"
    error_message = "weekdays 08:00-19:00, Lagos time"
  }

  assert {
    condition     = contains(aws_launch_template.this.vpc_security_group_ids, "sg-0tools") && aws_launch_template.this.image_id == "resolve:ssm:/core/platform/ami/ubuntu"
    error_message = "core's team-tools group, and the golden image read at launch"
  }

  assert {
    condition     = aws_iam_role.hosts.path == "/services/team-tools/" && aws_iam_role.hosts.permissions_boundary == "arn:aws:iam::123456789012:policy/platform/core-service-boundary"
    error_message = "the servers' role under core's boundary, where core's role allows it"
  }

  assert {
    condition     = aws_launch_template.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 only"
  }
}

run "development_has_web_addresses_behind_the_front_door" {
  command = plan

  assert {
    condition     = length(aws_lb_listener_rule.tool) == 2 && one(one(aws_lb_listener_rule.tool["dbgate"].condition).host_header).values == toset(["dbgate.dev.example.org"])
    error_message = "one rule per tool, by host"
  }

  assert {
    condition     = aws_lb_listener_rule.tool["cloudbeaver"].action[0].type == "authenticate-cognito" && aws_lb_listener_rule.tool["cloudbeaver"].action[0].authenticate_cognito[0].user_pool_domain == "core-development-team-123456789012"
    error_message = "the sign-in comes first"
  }

  assert {
    condition     = toset(aws_cognito_user_pool_client.tools[0].callback_urls) == toset(["https://dbgate.dev.example.org/oauth2/idpresponse", "https://cloudbeaver.dev.example.org/oauth2/idpresponse"])
    error_message = "the app client returns to the tools' own addresses"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_load_balancer) == 2 && aws_vpc_security_group_ingress_rule.from_load_balancer["dbgate"].referenced_security_group_id == "sg-0alb"
    error_message = "the servers admit the private load balancer, on the tools' ports only"
  }
}

run "staging_managed_databases_over_verified_tls" {
  command = plan

  variables {
    environment   = "staging"
    schedule_days = "SAT,SUN"
    platform_json = <<-JSON
      {
        "schema_version": 1,
        "domain_name": "staging.example.org",
        "vpc_id": "vpc-0abc",
        "hosting_model": "dedicated",
        "compute": { "ami_parameter": "/core/platform/ami/ubuntu" },
        "service_boundary_arn": "arn:aws:iam::123456789012:policy/platform/core-service-boundary",
        "tools": { "security_group_id": "sg-0tools", "subnet_ids": ["subnet-0p1"] },
        "team_front_door": { "user_pool_id": "af-south-1_Abc", "user_pool_arn": "arn:aws:cognito-idp:af-south-1:123456789012:userpool/af-south-1_Abc", "domain": "core-staging-team-123456789012", "declaration_prefix": "front-door/" },
        "database": { "host": null, "engines": {
          "postgres": { "host": "core-staging-postgres.abc.af-south-1.rds.amazonaws.com", "port": 5432 },
          "mysql":    { "host": "core-staging-mysql.abc.af-south-1.rds.amazonaws.com", "port": 3306 },
          "mongodb":  { "host": "core-staging-mongodb.cluster-abc.af-south-1.docdb.amazonaws.com", "port": 27017 }
        } },
        "tiers": { "private": { "security_group_id": "sg-0priv", "alb_security_group_id": "sg-0alb", "listener_arn": "arn:aws:elasticloadbalancing:af-south-1:123456789012:listener/app/core-private/abc/def" } }
      }
    JSON
  }

  assert {
    condition     = local.dbgate_env.USE_SSL_postgres == "1" && local.dbgate_env.SSL_REJECT_UNAUTHORIZED_mysql == "1" && local.dbgate_env.SSL_CA_FILE_mongodb == "/certs/rds-global-bundle.pem"
    error_message = "DbGate verifies every managed database against the RDS bundle"
  }

  assert {
    condition     = local.dbgate_env.PORT_mongodb == "27017/?retryWrites=false"
    error_message = "DocumentDB: retryable writes off, through the only field DbGate passes on"
  }

  assert {
    condition     = jsondecode(local.cloudbeaver_data_sources).connections.postgres.configuration.properties.sslmode == "verify-full" && jsondecode(local.cloudbeaver_data_sources).connections.mysql.configuration.properties.sslMode == "VERIFY_IDENTITY"
    error_message = "CloudBeaver verifies the certificate and the host name"
  }

  assert {
    condition     = strcontains(local.user_data, "e5bb2084ccf45087bda1c9bffdea0eb15ee67f0b91646106e466714f9de3c7e3") && strcontains(local.user_data, "sha256sum -c") && strcontains(local.user_data, "rds-truststore.p12")
    error_message = "the bundle is fetched and refused unless it is the pinned one; MySQL's truststore is built"
  }

  assert {
    condition     = aws_autoscaling_schedule.start.recurrence == "0 8 * * SAT,SUN"
    error_message = "staging: weekends"
  }
}

run "production_has_no_web_address" {
  command = plan

  variables {
    environment   = "production"
    platform_json = <<-JSON
      {
        "schema_version": 1,
        "domain_name": "example.org",
        "vpc_id": "vpc-0abc",
        "hosting_model": "dedicated",
        "compute": { "ami_parameter": "/core/platform/ami/ubuntu" },
        "service_boundary_arn": "arn:aws:iam::123456789012:policy/platform/core-service-boundary",
        "tools": { "security_group_id": "sg-0tools", "subnet_ids": ["subnet-0p1"] },
        "team_front_door": null,
        "database": { "host": null, "engines": { "postgres": { "host": "core-production-postgres.abc.af-south-1.rds.amazonaws.com", "port": 5432 } } },
        "tiers": { "private": { "security_group_id": "sg-0priv", "alb_security_group_id": "sg-0alb", "listener_arn": "arn:aws:elasticloadbalancing:af-south-1:123456789012:listener/app/core-private/abc/def" } }
      }
    JSON
  }

  assert {
    condition     = length(aws_lb_listener_rule.tool) == 0 && length(aws_lb_target_group.tool) == 0 && length(aws_cognito_user_pool_client.tools) == 0 && length(aws_vpc_security_group_ingress_rule.from_load_balancer) == 0
    error_message = "no rules, no target groups, no app client, nothing admitted: the tunnel only"
  }

  assert {
    condition     = aws_autoscaling_group.this.health_check_type == "EC2" && length(output.addresses) == 0
    error_message = "health from EC2 alone, and no address"
  }

  assert {
    condition     = keys(output.connections) == tolist(["postgres"])
    error_message = "only the engines production runs"
  }
}

run "an_image_on_latest_is_refused" {
  command = plan

  variables {
    images = { dbgate = "dbgate/dbgate:latest", cloudbeaver = "dbeaver/cloudbeaver:25.3.5" }
  }

  expect_failures = [var.images]
}

run "an_unknown_schedule_is_refused" {
  command = plan

  variables {
    schedule_days = "MON"
  }

  expect_failures = [var.schedule_days]
}
