variable "egress_cidr_block" {
  description = "CIDR block load generator tasks may send traffic to."
  type        = string
  default     = "0.0.0.0/0"
}

variable "existing_subnet_ids" {
  description = "Two existing subnet IDs in this region. Required with existing_vpc_id."
  type        = list(string)
  default     = []
}

variable "existing_vpc_id" {
  description = "Existing VPC in this region. Null creates a dedicated VPC."
  type        = string
  default     = null
}

variable "hub" {
  description = "Hub connection details, normally module.hub.regional_inputs."
  type = object({
    iot_endpoint          = string
    region                = string
    scenarios_bucket_name = string
    scenarios_table_name  = string
    task_runner_role_name = string
  })
}

variable "log_retention_in_days" {
  description = "Retention for regional log groups."
  type        = number
  default     = 3653
}

variable "name" {
  description = "Deployment name. Use the hub's name so the console groups regions together."
  type        = string
}

variable "real_time_data_publisher_zip" {
  description = "Path to the real-time-data-publisher Lambda zip."
  type        = string
}

variable "solution_id" {
  description = "Solution ID tag value."
  type        = string
  default     = "SO0062"
}

variable "solution_version" {
  description = "Solution version. Must match the hub."
  type        = string
  default     = "v4.3.5"
}

variable "subnet_cidr_blocks" {
  description = "Two subnet CIDRs for the created VPC."
  type        = list(string)
  default     = ["192.168.0.0/20", "192.168.16.0/20"]
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr_block" {
  description = "CIDR for the created VPC."
  type        = string
  default     = "192.168.0.0/16"
}
