# -------------------------------
# Argo CD behind NGINX Ingress
# -------------------------------

# Where to install Argo CD
variable "argocd_namespace" {
  description = "Namespace to install Argo CD"
  type        = string
  default     = "argocd"
}

# Used to build: argocd.<dns_prefix>.<region>.cloudapp.azure.com
variable "dns_prefix" {
  description = "Prefix for the host used in /etc/hosts"
  type        = string
  default     = "aks-terraform"
}

# Optional TLS at the NGINX Ingress (provide a pre-created secret if you flip this on)
variable "argocd_enable_tls" {
  description = "Enable TLS termination at NGINX for Argo CD"
  type        = bool
  default     = false
}
variable "argocd_tls_secret_name" {
  description = "TLS secret name when argocd_enable_tls = true"
  type        = string
  default     = ""
}

# Region part for cloudapp FQDN, e.g. "West Europe" -> "westeurope"
locals {
  azure_region_dns = lower(replace(azurerm_resource_group.example.location, " ", ""))
  argocd_host      = "argocd.${var.dns_prefix}.${local.azure_region_dns}.cloudapp.azure.com"

  # Reuse the NGINX Service IP discovered in nginx.tf
  lb_ip = (var.install_helmcharts && length(data.kubernetes_service_v1.ingress_svc) > 0) ? try(data.kubernetes_service_v1.ingress_svc[0].status[0].load_balancer[0].ingress[0].ip, "") : ""

  hosts_line = local.lb_ip != "" ? "${local.lb_ip} ${local.argocd_host}" : ""
}

# Install Argo CD via Helm (Ingress managed via chart values)
resource "helm_release" "argocd" {
  count = var.install_helmcharts ? 1 : 0

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  # version        = "6.x.x"  # optionally pin a version
  namespace        = var.argocd_namespace
  create_namespace = true

  values = [yamlencode({
    server = {
      service = { type = "ClusterIP" }
      ingress = {
        enabled          = true
        ingressClassName = "nginx"
        annotations = {
          "kubernetes.io/ingress.class"              = "nginx"
          "nginx.ingress.kubernetes.io/ssl-redirect" = var.argocd_enable_tls ? "true" : "false"
        }
        hosts = [local.argocd_host]
        tls = var.argocd_enable_tls ? [{
          secretName = var.argocd_tls_secret_name
          hosts      = [local.argocd_host]
        }] : []
      }
      # allow HTTP between NGINX and argocd-server when TLS is off
      extraArgs = var.argocd_enable_tls ? [] : ["--insecure"]
    }
    # (optional) scale components or enable redis if you want:
    # controller = { replicas = 2 }
    # repoServer = { replicas = 2 }
    # redis      = { enabled  = true }
  })]

  # Make sure NGINX is installed before we create Argo CD's Ingress
  depends_on = [helm_release.ingress_nginx]
}

# Helpful outputs
output "argocd_url" {
  value = var.install_helmcharts ? format("%s://%s", var.argocd_enable_tls ? "https" : "http", local.argocd_host) : null
}

output "argocd_hosts_entry" {
  value = var.install_helmcharts ? (
    local.hosts_line != ""
    ? "Add this to /etc/hosts:\n${local.hosts_line}"
    : "NGINX LB IP not ready yet. Once ready, run:\n  kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
  ) : null
}
