variable "create_task_definitions" {
  description = "Create the four framework task definitions (hub only). Regional runners get task definitions registered at test time by the hub's task-runner Lambda."
  type        = bool
  default     = false
}

variable "egress_cidr_block" {
  description = "CIDR block load generator tasks may send traffic to. Narrow this to the system under test where possible."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.egress_cidr_block, 0))
    error_message = "egress_cidr_block must be a valid IPv4 CIDR."
  }
}

variable "existing_subnet_ids" {
  description = "Two existing subnet IDs for the Fargate tasks. Required when existing_vpc_id is set."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.existing_subnet_ids) == 0 || length(var.existing_subnet_ids) == 2
    error_message = "existing_subnet_ids must contain exactly two subnet IDs, or be empty."
  }
}

variable "existing_vpc_id" {
  description = "Existing VPC to run load generators in. When null the module creates a dedicated VPC with two public subnets."
  type        = string
  default     = null

  validation {
    condition     = var.existing_vpc_id == null || can(regex("^vpc-[a-zA-Z0-9-]+$", var.existing_vpc_id))
    error_message = "existing_vpc_id must look like vpc-xxxxxxxx."
  }
}

variable "iot_endpoint" {
  description = "IoT Data-ATS endpoint hostname in the hub region. The real-time data publisher pushes live metrics there."
  type        = string
}

variable "load_tester_images" {
  description = "Container image per framework. Keys: taurus, jmeter, k6, locust. Used only when create_task_definitions is true."
  type        = map(string)
  default     = {}
}

variable "log_retention_in_days" {
  description = "Retention for the ECS task and real-time publisher log groups."
  type        = number
  default     = 3653
}

variable "main_region" {
  description = "Hub (main) region. The real-time publisher publishes to IoT in this region."
  type        = string
}

variable "name" {
  description = "Deployment name. Used as the ECS cluster name and resource name prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,31}$", var.name))
    error_message = "name must start with a letter, contain only letters, digits and hyphens, and be at most 32 characters (Lambda names cap at 64)."
  }
}

variable "real_time_data_publisher_zip" {
  description = "Path to the real-time-data-publisher Lambda zip."
  type        = string
}

variable "scenarios_bucket_name" {
  description = "Hub scenarios bucket name. Tasks read test scripts and write results here."
  type        = string
}

variable "solution_id" {
  description = "Solution ID tag value. The DLT Lambdas scope ECS and Logs permissions on aws:ResourceTag/SolutionId, so this must match their policies."
  type        = string
  default     = "SO0062"
}

variable "solution_version" {
  description = "Solution version reported to the Lambdas."
  type        = string
}

variable "subnet_cidr_blocks" {
  description = "Two subnet CIDR blocks for the module-created VPC."
  type        = list(string)
  default     = ["192.168.0.0/20", "192.168.16.0/20"]

  validation {
    condition     = length(var.subnet_cidr_blocks) == 2 && alltrue([for c in var.subnet_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "subnet_cidr_blocks must contain exactly two valid IPv4 CIDRs."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr_block" {
  description = "CIDR block for the module-created VPC."
  type        = string
  default     = "192.168.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR."
  }
}
