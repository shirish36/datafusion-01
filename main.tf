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

resource "google_project_service" "compute_api" {
  service = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "dataproc_api" {
  service = "dataproc.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicenetworking_api" {
  service = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

# VPC and Subnet for Data Fusion
resource "google_compute_network" "datafusion_vpc" {
  name                    = "datafusion-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute_api]
}

resource "google_compute_subnetwork" "datafusion_subnet" {
  name          = "datafusion-subnet"
  network       = google_compute_network.datafusion_vpc.self_link
  ip_cidr_range = "10.0.0.0/26"  # /26 CIDR as requested
  region        = var.region
}

# Private service connection for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.datafusion_vpc.self_link
  depends_on    = [google_project_service.servicenetworking_api]
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.datafusion_vpc.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
  depends_on              = [google_project_service.servicenetworking_api]
}

# Source MSSQL Cloud SQL instance with private IP
resource "google_sql_database_instance" "source_mssql" {
  name             = "source-mssql-instance"
  database_version = "SQLSERVER_2019_STANDARD"
  region           = var.region

  settings {
    tier = var.sql_instance_tier
    disk_size = 10
    disk_type = "PD_SSD"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.datafusion_vpc.self_link
    }
  }

  depends_on = [google_project_service.sqladmin_api, google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "source_db" {
  name     = var.source_db_name
  instance = google_sql_database_instance.source_mssql.name
}

# EDW MSSQL Cloud SQL instance with private IP
resource "google_sql_database_instance" "edw_mssql" {
  name             = "edw-mssql-instance"
  database_version = "SQLSERVER_2019_STANDARD"
  region           = var.region

  settings {
    tier = var.sql_instance_tier
    disk_size = 10
    disk_type = "PD_SSD"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.datafusion_vpc.self_link
    }
  }

  depends_on = [google_project_service.sqladmin_api, google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "edw_db" {
  name     = var.edw_db_name
  instance = google_sql_database_instance.edw_mssql.name
}

# DataProc cluster for Data Fusion
resource "google_dataproc_cluster" "datafusion_dataproc" {
  name   = "datafusion-dataproc-cluster"
  region = var.region

  cluster_config {
    master_config {
      num_instances = 1
      machine_type  = "n1-standard-2"
      disk_config {
        boot_disk_type    = "pd-ssd"
        boot_disk_size_gb = 30
      }
    }

    worker_config {
      num_instances = 2
      machine_type  = "n1-standard-2"
      disk_config {
        boot_disk_type    = "pd-ssd"
        boot_disk_size_gb = 30
      }
    }

    gce_cluster_config {
      network = google_compute_network.datafusion_vpc.self_link
      subnetwork = google_compute_subnetwork.datafusion_subnet.self_link
    }
  }

  depends_on = [google_project_service.dataproc_api]
}

# Data Fusion instance
resource "google_data_fusion_instance" "datafusion_instance" {
  name     = "datafusion-poc-instance"
  region   = var.region
  type     = var.datafusion_type
  version  = "6.7.2"

  network_config {
    network = google_compute_network.datafusion_vpc.self_link
    ip_allocation = "10.0.0.0/26"
  }

  dataproc_service_account = google_service_account.datafusion_sa.email

  depends_on = [google_project_service.datafusion_api, google_dataproc_cluster.datafusion_dataproc]
}

# Service account for Data Fusion
resource "google_service_account" "datafusion_sa" {
  account_id   = "datafusion-sa"
  display_name = "Data Fusion Service Account"
}

# IAM roles for Data Fusion SA
resource "google_project_iam_member" "datafusion_sa_dataproc" {
  project = var.project_id
  role    = "roles/dataproc.worker"
  member  = "serviceAccount:${google_service_account.datafusion_sa.email}"
}

resource "google_project_iam_member" "datafusion_sa_storage" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.datafusion_sa.email}"
}

# Outputs
output "datafusion_instance_name" {
  value = google_data_fusion_instance.datafusion_instance.name
}

output "datafusion_instance_url" {
  value = google_data_fusion_instance.datafusion_instance.service_endpoint
}

output "vpc_name" {
  value = google_compute_network.datafusion_vpc.name
}

output "subnet_name" {
  value = google_compute_subnetwork.datafusion_subnet.name
}

output "dataproc_cluster_name" {
  value = google_dataproc_cluster.datafusion_dataproc.name
}

output "source_mssql_private_ip" {
  value = google_sql_database_instance.source_mssql.private_ip_address
}

output "edw_mssql_private_ip" {
  value = google_sql_database_instance.edw_mssql.private_ip_address
}
