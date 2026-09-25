variable "project_name" {
  type        = string
  description = "Project name, as core was set up with."
}

variable "environment" {
  type        = string
  description = "Environment name."
}

variable "platform_json" {
  type        = string
  description = "Core's platform contract (/<project>/platform/config), JSON."
}

variable "images" {
  type = object({
    dbgate      = string
    cloudbeaver = string
  })
  description = "The tools' images, pinned (tools/images.json)."

  validation {
    condition     = alltrue([for image in values(var.images) : can(regex("^[a-z0-9./_-]+:[A-Za-z0-9._-]+$", image)) && !endswith(image, ":latest")])
    error_message = "Each image must be pinned to a version: <repository>:<tag>, never :latest."
  }
}

variable "schedule_days" {
  type        = string
  description = "Days the tools run on their schedule, in cron's day-of-week field: \"MON-FRI\" or \"SAT,SUN\"."

  validation {
    condition     = contains(["MON-FRI", "SAT,SUN"], var.schedule_days)
    error_message = "schedule_days must be \"MON-FRI\" (weekdays) or \"SAT,SUN\" (weekends)."
  }
}

variable "schedule_start_hour" {
  type        = number
  default     = 8
  description = "Hour the tools start, Lagos time."
}

variable "schedule_stop_hour" {
  type        = number
  default     = 19
  description = "Hour the tools stop, Lagos time."

  validation {
    condition     = var.schedule_stop_hour > 0 && var.schedule_stop_hour <= 23
    error_message = "schedule_stop_hour must be 1-23."
  }
}

variable "development_engines" {
  type        = list(string)
  default     = ["postgres", "mysql", "mongodb"]
  description = "Development only: the engines on the database host to show. The contract does not list them; each runs on its native port."

  validation {
    condition     = alltrue([for engine in var.development_engines : contains(["postgres", "mysql", "mongodb"], engine)])
    error_message = "development_engines may list postgres, mysql and mongodb."
  }
}

variable "instance_types" {
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
  description = "Spot instance types, 4 GB each (both programs together need about that). Two types give spot more capacity to choose from."
}

variable "rds_bundle_sha256" {
  type        = string
  description = "SHA-256 of AWS's RDS certificate bundle, which a server downloads at start and refuses unless it matches."

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.rds_bundle_sha256))
    error_message = "rds_bundle_sha256 must be a SHA-256, 64 lowercase hex characters."
  }
}
