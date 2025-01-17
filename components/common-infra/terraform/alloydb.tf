# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

data "google_project" "eks_project" {
  project_id = var.project_id
}

module "docs_results" {
  source = "github.com/GoogleCloudPlatform/terraform-google-alloy-db?ref=eda758770239cd3dd1122834ef0c0429659a0234" #commit hash for version 3.2.1

  project_id = module.project_services.project_id

  cluster_id        = var.alloy_db_cluster_id
  cluster_location  = var.region
  cluster_labels    = {}

  psc_enabled       = true
  psc_allowed_consumer_projects = [data.google_project.eks_project.number]


  primary_instance = {
    instance_id       = "${var.alloy_db_cluster_id}-primary"
    instance_type     = "PRIMARY"
    machine_cpu_count = 2
    database_flags = {
      "alloydb.iam_authentication"  = "true",
      "alloydb.enable_pgaudit"      = "on",
      "password.enforce_complexity" = "on"
    }
  }

  #depends_on = [google_service_networking_connection.default]
}

resource "google_compute_address" "eks_alloydb_psc_endpoint" {
  project = var.project_id
  region  = var.region
  name    = "eks-alloydb-psc-endpoint"

  subnetwork   = data.google_compute_subnetwork.provided_subnetwork[0].self_link
  address_type = "INTERNAL"
}

resource "google_compute_forwarding_rule" "eks_alloydb_psc_fwd_rule" {
  project = var.project_id
  region  = var.region
  name    = "eks-alloydb-psc-fwd-rule"

  target                  = module.docs_results.primary_psc_attachment_link
  load_balancing_scheme   = "" # need to override EXTERNAL default when target is a service attachment
  network                 = local.vpc_network_id
  ip_address              = google_compute_address.eks_alloydb_psc_endpoint.id
  allow_psc_global_access = true
}

resource "google_dns_managed_zone" "alloy_psc" {
  project     =  var.vpc_project_id
  name        = "eks-alloydb-psc"
  dns_name    = module.docs_results.primary_psc_dns_name
  description = "DNS Zone for EKS AlloyDB instance"
  visibility = "private"

  private_visibility_config {
    networks {
      network_url = local.vpc_network_id
    }
  }
}

resource "google_dns_record_set" "alloy_psc" {
  project = var.vpc_project_id
  name = module.docs_results.primary_psc_dns_name
  type = "A"
  ttl  = 300

  managed_zone = google_dns_managed_zone.alloy_psc.name

  rrdatas = [google_compute_address.eks_alloydb_psc_endpoint.address]

  depends_on = [ google_dns_managed_zone.alloy_psc ]
}

resource "time_sleep" "wait_for_alloydb_ready_state" {
  create_duration = "600s"
  depends_on = [
    module.docs_results
  ]
}
