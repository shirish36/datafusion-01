variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "source_db_name" {
  description = "Name of the source MSSQL database"
  type        = string
  default     = "source_db"
}

variable "edw_db_name" {
  description = "Name of the EDW MSSQL database"
  type        = string
  default     = "edw_db"
}

variable "sql_instance_tier" {
  description = "Tier for SQL instances"
  type        = string
  default     = "db-f1-micro"
}

variable "datafusion_type" {
  description = "Type of Data Fusion instance"
  type        = string
  default     = "BASIC"
}
