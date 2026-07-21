# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

/* Variables */

variable "project_id" {
  description = "Project id (also used for the Apigee Organization)."
  type        = string
}

variable "region" {
  description = "GCP region for the Apigee runtime & analytics data."
  type        = string
}

variable "network" {
  description = "VPC network name, default is created if empty."
  type        = string
  default     = ""
}

variable "subnet" {
  description = "VPC subnetwork name, default is created if empty."
  type        = string
  default     = null
}

variable "drz_location" {
  description = "The DRZ location to use for deploying Apigee, either US (United States), EU (Europeean Union) or IN (India), or empty for global."
  type        = string
  default     = null
}

variable "apigee_type" {
  description = "The Apigee billing type, either EVALUATION, PAYG or SUBSCRIPTION."
  type        = string
  default     = "EVALUATION"
}

locals {
  gcp_services = [
    "apigee.googleapis.com",
    "apihub.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudkms.googleapis.com",
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudaicompanion.googleapis.com",
    "modelarmor.googleapis.com",
    "dlp.googleapis.com"
  ]

  network_id = (
    length(google_compute_network.auto_vpc) > 0
    ? google_compute_network.auto_vpc[0].id
    : data.google_compute_network.existing_network[0].id
  )

  subnet_id = (
    length(google_compute_network.auto_vpc) == 0
    ? data.google_compute_subnetwork.existing_subnet[0].id
    : null
  )

  data_collectors = {
    dc_ai_model = {
      description = "Model name"
      type        = "STRING"
    }
    dc_ai_cost_center = {
      description = "Model cost center"
      type        = "STRING"
    }
    dc_ai_total_token_count = {
      description = "Total token count"
      type        = "INTEGER"
    }
    dc_ai_prompt_token_count = {
      description = "Prompt token count"
      type        = "INTEGER"
    }
    dc_ai_response_token_count = {
      description = "Response token count"
      type        = "INTEGER"
    }
    dc_ai_response_type = {
      description = "Model response type"
      type        = "STRING"
    }
    dc_ai_time_first_token = {
      description = "Time to first token (ms)"
      type        = "INTEGER"
    }
  }
}

data "external" "collector_check" {
  for_each = local.data_collectors

  program = ["bash", "-c", <<EOT
    ACCESS_TOKEN=$(gcloud auth application-default print-access-token 2>/dev/null)
    if [ -z "$ACCESS_TOKEN" ]; then
      # If no token, return false to prevent blocking plan phase in headless/CI environments
      echo '{"exists": "false"}'
      exit 0
    fi
    HTTP_STATUS=$(curl -s -o /dev/null -w "%%{http_code}" -X GET \
      "https://apigee.googleapis.com/v1/organizations/${var.project_id}/datacollectors/${each.key}" \
      -H "Authorization: Bearer $ACCESS_TOKEN")
    if [ "$HTTP_STATUS" -eq 200 ]; then
      echo '{"exists": "true"}'
    else
      echo '{"exists": "false"}'
    fi
  EOT
  ]
}

locals {
  # Filter map to exclude collectors that already exist on Apigee
  collectors_to_create = {
    for k, v in local.data_collectors : k => v
    if data.external.collector_check[k].result["exists"] == "false"
  }
}

provider "google" {
  apigee_custom_endpoint = var.drz_location != "" && var.drz_location != null ? "https://${var.drz_location}-apigee.googleapis.com/v1/" : "https://apigee.googleapis.com/v1/"
}

/* Project */

resource "google_project_service" "enabled_apis" {
  for_each           = toset(local.gcp_services)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "auto_vpc" {
  name                    = "default"
  project            = var.project_id
  count                   = var.network == "" ? 1 : 0
  auto_create_subnetworks = true
  routing_mode            = "REGIONAL"
  depends_on              = [google_project_service.enabled_apis]
}

data "google_compute_network" "existing_network" {
  count      = (var.network != "") ? 1 : 0
  name       = var.network
  project            = var.project_id
  depends_on = [google_project_service.enabled_apis]
}

data "google_compute_subnetwork" "existing_subnet" {
  count      = (var.subnet != null) ? 1 : 0
  name       = var.subnet
  project    = var.project_id
  region     = var.region
  depends_on = [google_project_service.enabled_apis]
}

resource "google_compute_global_address" "external_vip" {
  name         = "apigee-external-vip"
  project            = var.project_id
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  depends_on   = [google_project_service.enabled_apis]
}

resource "google_compute_managed_ssl_certificate" "nip_io_cert" {
  name = "apigee-nip-io-cert"
  project = var.project_id
  managed {
    domains = ["${google_compute_global_address.external_vip.address}.nip.io"]
  }
}

/* Apigee */

resource "google_apigee_organization" "apigee_org" {
  project_id                 = var.project_id
  analytics_region           = var.region
  api_consumer_data_location = var.region
  disable_vpc_peering        = true
  runtime_type               = "CLOUD"
  billing_type               = var.apigee_type
  depends_on                 = [google_project_service.enabled_apis]
  lifecycle {
    precondition {
      condition     = !((var.drz_location != null && var.drz_location != "") && var.apigee_type == "EVALUATION")
      error_message = "Apigee EVALUATION type cannot be used when a DRZ location (drz_location) is specified. Please use PAYG or SUBSCRIPTION instead."
    }
    ignore_changes = [analytics_region]
  }
}

resource "google_apigee_instance" "apigee" {
  name                 = "apigee-psc-instance"
  location             = var.region
  org_id               = google_apigee_organization.apigee_org.id
  consumer_accept_list = [var.project_id]
}

resource "google_compute_region_network_endpoint_group" "apigee_psc_neg" {
  name                  = "apigee-psc-neg"
  region                = var.region
  project               = var.project_id
  network_endpoint_type = "PRIVATE_SERVICE_CONNECT"
  psc_target_service    = google_apigee_instance.apigee.service_attachment
  network               = local.network_id
}

resource "google_compute_backend_service" "apigee_backend" {
  name                  = "apigee-psc-backend"
  project            = var.project_id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTPS"
  timeout_sec           = 600

  backend {
    group = google_compute_region_network_endpoint_group.apigee_psc_neg.id
  }
}

resource "google_compute_url_map" "url_map" {
  name            = "apigee-psc-url-map"
  default_service = google_compute_backend_service.apigee_backend.id
}

resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "apigee-psc-https-proxy"
  url_map          = google_compute_url_map.url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.nip_io_cert.id]
}

resource "google_compute_global_forwarding_rule" "https_forwarding_rule" {
  name                  = "apigee-psc-forwarding-rule"
  ip_address            = google_compute_global_address.external_vip.address
  target                = google_compute_target_https_proxy.https_proxy.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_apigee_environment" "dev_env" {
  name         = "dev"
  org_id       = google_apigee_organization.apigee_org.id
  display_name = "Development Environment"
  description  = "Development environment for API proxy deployments"
}

resource "google_apigee_envgroup" "dev_envgroup" {
  name      = "dev"
  org_id    = google_apigee_organization.apigee_org.id
  hostnames = ["${google_compute_global_address.external_vip.address}.nip.io"]
}

resource "google_apigee_envgroup_attachment" "dev_envgroup_attachment" {
  envgroup_id = google_apigee_envgroup.dev_envgroup.id
  environment = google_apigee_environment.dev_env.name
}

resource "google_apigee_instance_attachment" "dev_instance_attachment" {
  instance_id = google_apigee_instance.apigee.id
  environment = google_apigee_environment.dev_env.name
}

resource "google_apigee_data_collector" "collectors" {
  for_each = local.collectors_to_create

  org_id            = google_apigee_organization.apigee_org.id
  data_collector_id = each.key
  description       = each.value.description
  type              = each.value.type
}

resource "terraform_data" "custom_reports" {
  # Depend on collectors so they exist before we create reports referencing them
  depends_on = [google_apigee_data_collector.collectors]

  input = {
    org_name = var.project_id
  }

  provisioner "local-exec" {
    command = <<EOT
      ACCESS_TOKEN=$(gcloud auth application-default print-access-token 2>/dev/null)
      if [ -z "$ACCESS_TOKEN" ]; then
        echo "Error: Failed to obtain access token."
        exit 1
      fi

      # Report 1: AI Model Usage and Latency Report
      HTTP_STATUS_1=$(curl -s -o /dev/null -w "%%{http_code}" -X GET \
        "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports/ai_model_usage_latency" \
        -H "Authorization: Bearer $ACCESS_TOKEN")

      PAYLOAD_1='{
        "name": "ai_model_usage_latency",
        "displayName": "AI Model Usage and Latency",
        "chartType": "col",
        "timeUnit": "hour",
        "metrics": [
          {"name": "dc_ai_total_token_count", "function": "sum"},
          {"name": "dc_ai_time_first_token", "function": "avg"},
          {"name": "message_count", "function": "sum"}
        ],
        "dimensions": ["apiproxy", "dc_ai_model", "dc_ai_response_type"]
      }'

      if [ "$HTTP_STATUS_1" -eq 200 ]; then
        echo "Report ai_model_usage_latency already exists. Updating..."
        curl -s -X PUT "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports/ai_model_usage_latency" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json; charset=utf-8" \
          -d "$PAYLOAD_1"
      else
        echo "Report ai_model_usage_latency not found. Creating..."
        curl -s -X POST "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json; charset=utf-8" \
          -d "$PAYLOAD_1"
      fi

      # Report 2: AI Cost Center Allocation Report
      HTTP_STATUS_2=$(curl -s -o /dev/null -w "%%{http_code}" -X GET \
        "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports/ai_cost_center_allocation" \
        -H "Authorization: Bearer $ACCESS_TOKEN")

      PAYLOAD_2='{
        "name": "ai_cost_center_allocation",
        "displayName": "AI Cost Center Allocation",
        "chartType": "col",
        "timeUnit": "day",
        "metrics": [
          {"name": "dc_ai_total_token_count", "function": "sum"},
          {"name": "dc_ai_prompt_token_count", "function": "sum"},
          {"name": "dc_ai_response_token_count", "function": "sum"}
        ],
        "dimensions": ["dc_ai_cost_center", "dc_ai_model"]
      }'

      if [ "$HTTP_STATUS_2" -eq 200 ]; then
        echo "Report ai_cost_center_allocation already exists. Updating..."
        curl -s -X PUT "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports/ai_cost_center_allocation" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json; charset=utf-8" \
          -d "$PAYLOAD_2"
      else
        echo "Report ai_cost_center_allocation not found. Creating..."
        curl -s -X POST "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json; charset=utf-8" \
          -d "$PAYLOAD_2"
      fi

      # Report 3: AI Token Counts by Model and User Report
      HTTP_STATUS_3=$(curl -s -o /dev/null -w "%%{http_code}" -X GET \
        "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports/ai_token_counts_by_model_user" \
        -H "Authorization: Bearer $ACCESS_TOKEN")

      PAYLOAD_3='{
        "name": "ai_token_counts_by_model_user",
        "displayName": "AI Token Counts by Model and User",
        "chartType": "col",
        "timeUnit": "day",
        "metrics": [
          {"name": "dc_ai_total_token_count", "function": "sum"},
          {"name": "dc_ai_prompt_token_count", "function": "sum"},
          {"name": "dc_ai_response_token_count", "function": "sum"}
        ],
        "dimensions": ["dc_ai_model", "developer_email"]
      }'

      if [ "$HTTP_STATUS_3" -eq 200 ]; then
        echo "Report ai_token_counts_by_model_user already exists. Updating..."
        curl -s -X PUT "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports/ai_token_counts_by_model_user" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json; charset=utf-8" \
          -d "$PAYLOAD_3"
      else
        echo "Report ai_token_counts_by_model_user not found. Creating..."
        curl -s -X POST "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json; charset=utf-8" \
          -d "$PAYLOAD_3"
      fi

      # Report 4: AI Time to First Token by Model Report
      HTTP_STATUS_4=$(curl -s -o /dev/null -w "%%{http_code}" -X GET \
        "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports/ai_time_to_first_token_by_model" \
        -H "Authorization: Bearer $ACCESS_TOKEN")

      PAYLOAD_4='{
        "name": "ai_time_to_first_token_by_model",
        "displayName": "AI Time to First Token by Model",
        "chartType": "line",
        "timeUnit": "hour",
        "metrics": [
          {"name": "dc_ai_time_first_token", "function": "avg"}
        ],
        "dimensions": ["dc_ai_model"]
      }'

      if [ "$HTTP_STATUS_4" -eq 200 ]; then
        echo "Report ai_time_to_first_token_by_model already exists. Updating..."
        curl -s -X PUT "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports/ai_time_to_first_token_by_model" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json; charset=utf-8" \
          -d "$PAYLOAD_4"
      else
        echo "Report ai_time_to_first_token_by_model not found. Creating..."
        curl -s -X POST "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json; charset=utf-8" \
          -d "$PAYLOAD_4"
      fi
    EOT
  }

  # Clean up report definitions upon destroying the Terraform state
  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      ACCESS_TOKEN=$(gcloud auth application-default print-access-token 2>/dev/null)
      if [ -n "$ACCESS_TOKEN" ]; then
        echo "Deleting custom report definitions..."
        curl -s -X DELETE "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports/ai_model_usage_latency" \
          -H "Authorization: Bearer $ACCESS_TOKEN"
        curl -s -X DELETE "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports/ai_cost_center_allocation" \
          -H "Authorization: Bearer $ACCESS_TOKEN"
        curl -s -X DELETE "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports/ai_token_counts_by_model_user" \
          -H "Authorization: Bearer $ACCESS_TOKEN"
        curl -s -X DELETE "https://apigee.googleapis.com/v1/organizations/${self.input.org_name}/reports/ai_time_to_first_token_by_model" \
          -H "Authorization: Bearer $ACCESS_TOKEN"
      fi
    EOT
  }
}

output "data_collectors" {
  description = "The newly created Apigee Data Collectors (excludes already existing ones)."
  value = {
    for k, v in google_apigee_data_collector.collectors : k => {
      id                = v.id
      data_collector_id = v.data_collector_id
      name              = v.name
      description       = v.description
      type              = v.type
    }
  }
}

output "apigee_endpoint_url" {
  value       = "https://${google_compute_global_address.external_vip.address}.nip.io"
  description = "Your public secure Apigee API endpoint."
}
