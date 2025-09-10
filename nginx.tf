# Only created when var.install_helmcharts = true
resource "helm_release" "ingress_nginx" {
  count            = var.install_helmcharts ? 1 : 0
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  # For a PRIVATE (internal) LB on Azure, uncomment:
  # values = [yamlencode({
  #   controller = {
  #     service = {
  #       annotations = {
  #         "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
  #       }
  #     }
  #   }
  # })]

  depends_on = [azurerm_kubernetes_cluster.example]
}


# Discover the LB IP (only when ingress is installed). You’ll use that IP to:

## Point DNS (create an A record for app.company.com → LB IP).
## Smoke-test before DNS (curl the IP with a Host: header).
## Firewall/allow-list sources (e.g., partners probing a health URL).
## Monitor (synthetics/uptime checks hit the LB IP/hostname).
## Stability planning (if the Service is recreated, the IP can change unless you reserve a static one).
data "kubernetes_service_v1" "ingress_svc" {
  count = var.install_helmcharts ? 1 : 0
  metadata {
    name      = "ingress-nginx-controller" # common default service name
    namespace = "ingress-nginx"
  }
  depends_on = [helm_release.ingress_nginx]
}
output "ingress_nginx_external_ip" {
  value = (var.install_helmcharts && length(data.kubernetes_service_v1.ingress_svc) > 0) ? try(data.kubernetes_service_v1.ingress_svc[0].status[0].load_balancer[0].ingress[0].ip, null) : null
}

