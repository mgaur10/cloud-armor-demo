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




output "_01_iap_ssh_load_test_server_base_region" {
  value = module.cloud_armor._01_iap_ssh_load_test_server_base_region
}

output "_02_iap_ssh_load_test_server_region_a" {
  value = module.cloud_armor._02_iap_ssh_load_test_server_region_a
}


output "_03_iap_ssh_load_test_server_region_b" {
  value = module.cloud_armor._03_iap_ssh_load_test_server_region_b
}


output "_4_siege_load_test_command" {
  value = module.cloud_armor._4_siege_load_test_command
}


output "_5_juice_shop_application_address" {
  value = module.cloud_armor._5_juice_shop_application_address
}

output "_6_owasp_path_traversal_command" {
  value = module.cloud_armor._6_owasp_path_traversal_command
}


output "_7_owasp_rce__command" {
  value = module.cloud_armor._7_owasp_rce__command
}


output "_8_owasp_http_splitting__command" {
  value = module.cloud_armor._8_owasp_http_splitting__command
}

  ## To troubleshoot session fixation
  /*
output "_9_owasp_session_fixation__command" {
  value = module.cloud_armor._9_owasp_session_fixation__command
}
  */
