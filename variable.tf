##  Copyright 2023 Google LLC
##  
##  Licensed under the Apache License, Version 2.0 (the "License");
##  you may not use this file except in compliance with the License.
##  You may obtain a copy of the License at
##  
##      https://www.apache.org/licenses/LICENSE-2.0
##  
##  Unless required by applicable law or agreed to in writing, software
##  distributed under the License is distributed on an "AS IS" BASIS,
##  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##  See the License for the specific language governing permissions and
##  limitations under the License.


##  This code creates PoC demo environment for Cloud Armor
##  This demo code is not built for production workload ##


variable "demo_project_id" {
  type        = string
  description = "Project ID to deploy resources"
  

}

variable "vpc_network_name" {
  type        = string
  description = "VPC network name"
  default     = "demo-vpc"
}

variable "base_network_region" {
  type        = string
  description = "Base network region for Cloud Armor"
  default     = "us-east1"
}

variable "base_network_zone" {
  type        = string
  description = "Base network zone"
  default     = "us-east1-c"
}

variable "network_region_a" {
  type        = string
  description = "Network region A"
  default     = "europe-west1"
}

variable "network_zone_a" {
  type        = string
  description = "Network zone A"
  default     = "europe-west1-c"
}

variable "network_region_b" {
  type        = string
  description = "Network region B"
  default     = "asia-east1"
}

variable "network_zone_b" {
  type        = string
  description = "Network zone B"
  default     = "asia-east1-c"
}