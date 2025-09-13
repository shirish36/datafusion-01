terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  credentials = file("gha-sa-key-0831.json")
  project     = var.project_id
  region      = var.region
}

# Enable required APIs
resource "google_project_service" "datafusion_api" {
  service = "datafusion.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sqladmin_api" {
  service = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

# Source MSSQL Cloud SQL instance
resource "google_sql_database_instance" "source_mssql" {
  name             = "source-mssql-instance"
  database_version = "SQLSERVER_2019_STANDARD"
  region           = var.region

  settings {
    tier = var.sql_instance_tier
    disk_size = 10
    disk_type = "PD_SSD"

    ip_configuration {
      ipv4_enabled = true
    }
  }

  depends_on = [google_project_service.sqladmin_api]
}

resource "google_sql_database" "source_db" {
  name     = var.source_db_name
  instance = google_sql_database_instance.source_mssql.name
}

# EDW MSSQL Cloud SQL instance
resource "google_sql_database_instance" "edw_mssql" {
  name             = "edw-mssql-instance"
  database_version = "SQLSERVER_2019_STANDARD"
  region           = var.region

  settings {
    tier = var.sql_instance_tier
    disk_size = 10
    disk_type = "PD_SSD"

    ip_configuration {
      ipv4_enabled = true
    }
  }

  depends_on = [google_project_service.sqladmin_api]
}

resource "google_sql_database" "edw_db" {
  name     = var.edw_db_name
  instance = google_sql_database_instance.edw_mssql.name
}

# Data Fusion instance
resource "google_data_fusion_instance" "datafusion_instance" {
  name     = "datafusion-poc-instance"
  region   = var.region
  type     = var.datafusion_type
  version  = "6.7.2"  # Latest stable version

  depends_on = [google_project_service.datafusion_api]
}

# Outputs
output "datafusion_instance_name" {
  value = google_data_fusion_instance.datafusion_instance.name
}

output "datafusion_instance_url" {
  value = google_data_fusion_instance.datafusion_instance.service_endpoint
}

output "source_mssql_connection_name" {
  value = google_sql_database_instance.source_mssql.connection_name
}

output "edw_mssql_connection_name" {
  value = google_sql_database_instance.edw_mssql.connection_name
}
