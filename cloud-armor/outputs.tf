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
  value = "gcloud compute ssh --zone ${var.base_network_zone} ${google_compute_instance.base_region_test_machine.name}  --tunnel-through-iap --project ${var.demo_project_id}"
}

output "_02_iap_ssh_load_test_server_region_a" {
  value = "gcloud compute ssh --zone ${var.network_zone_a} ${google_compute_instance.region_a_test_machine.name}  --tunnel-through-iap --project ${var.demo_project_id}"
}


output "_03_iap_ssh_load_test_server_region_b" {
  value = "gcloud compute ssh --zone ${var.network_zone_b} ${google_compute_instance.region_b_test_machine.name}  --tunnel-through-iap --project ${var.demo_project_id}"
}


output "_4_siege_load_test_command" {
  value = "siege -c 250 http://${google_compute_global_address.default.address}"
}

output "_5_juice_shop_application_address" {
  value = "http://${google_compute_global_address.juice_shop.address}"
}

output "_6_owasp_path_traversal_command" {
  value = "curl -Ii http://${google_compute_global_address.juice_shop.address}/ftp"
}


output "_7_owasp_rce__command" {
  value = "curl -Ii http://${google_compute_global_address.juice_shop.address}/ftp?doc=/bin/ls"
}


output "_8_owasp_http_splitting__command" {
  value = "curl -Ii 'http://${google_compute_global_address.juice_shop.address}/index.html?foo=advanced%0d%0aContent-Length:%200%0d%0a%0d%0aHTTP/1.1%20200%20OK%0d%0aContent-Type:%20text/html%0d%0aContent-Length:%2035%0d%0a%0d%0a<html>Sorry,%20System%20Down</html>'"
}

output "_9_owasp_session_fixation__command" {
  value = "curl -Ii http://${google_compute_global_address.juice_shop.address} -H session_id=X"
}


