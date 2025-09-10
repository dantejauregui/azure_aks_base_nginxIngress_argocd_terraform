# --------- Static Public IP in the AKS node resource group ----------
# AKS creates a separate "node resource group". Use it for the ingress PIP.
resource "azurerm_public_ip" "ingress_nginx" {
  count               = var.install_helmcharts ? 1 : 0
  name                = "ingress-nginx-pip"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_kubernetes_cluster.example.node_resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
}

# --------- NGINX Ingress Controller via Helm ----------
resource "helm_release" "ingress_nginx" {
  count            = var.install_helmcharts ? 1 : 0
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  # Key: attach the static PIP + add the Azure HTTP probe path
  values = [yamlencode({
    controller = {
      service = {
        annotations = {
          # attach the specific Public IP you created above
          "service.beta.kubernetes.io/azure-pip-name" = azurerm_public_ip.ingress_nginx[0].name

          # make Azure LB use an HTTP probe on /healthz (on port 80)
          "service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path" = "/healthz"
        }
        # optional: keep externalTrafficPolicy default (Cluster)
        type = "LoadBalancer"
      }
    }
  })]

  depends_on = [azurerm_kubernetes_cluster.example, azurerm_public_ip.ingress_nginx]
}

# Discover the LB IP (now it should be the static PIP you created)
data "kubernetes_service_v1" "ingress_svc" {
  count = var.install_helmcharts ? 1 : 0
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
  depends_on = [helm_release.ingress_nginx]
}

output "ingress_nginx_external_ip" {
  value = (var.install_helmcharts && length(data.kubernetes_service_v1.ingress_svc) > 0) ? try(data.kubernetes_service_v1.ingress_svc[0].status[0].load_balancer[0].ingress[0].ip, null) : null
}
