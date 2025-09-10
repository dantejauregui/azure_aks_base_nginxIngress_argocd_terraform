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

# ---------- locals reused from your file ----------
locals {
  azure_region_dns = lower(replace(azurerm_resource_group.example.location, " ", ""))
  argocd_host      = "argocd.${var.dns_prefix}.${local.azure_region_dns}.cloudapp.azure.com"

  lb_ip = (var.install_helmcharts && length(data.kubernetes_service_v1.ingress_svc) > 0) ? try(data.kubernetes_service_v1.ingress_svc[0].status[0].load_balancer[0].ingress[0].ip, "") : ""

  hosts_line = local.lb_ip != "" ? "${local.lb_ip} ${local.argocd_host}" : ""
}

# ---------- Argo CD via Helm (disable chart's ingress) ----------
resource "helm_release" "argocd" {
  count      = var.install_helmcharts ? 1 : 0
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  # version        = "8.3.5"   # optional pin
  namespace        = var.argocd_namespace
  create_namespace = true

  values = [yamlencode({
    server = {
      service   = { type = "ClusterIP" }
      ingress   = { enabled = false } # <-- we'll create our own below
      extraArgs = ["--insecure"]      # HTTP between NGINX and argocd-server
    }
  })]

  depends_on = [helm_release.ingress_nginx]
}

# ---------- Our explicit Ingress (host + port 80) ----------
resource "kubernetes_ingress_v1" "argocd" {
  count = var.install_helmcharts ? 1 : 0

  metadata {
    name      = "argocd"
    namespace = var.argocd_namespace
    annotations = {
      "kubernetes.io/ingress.class"              = "nginx"
      "nginx.ingress.kubernetes.io/ssl-redirect" = var.argocd_enable_tls ? "true" : "false"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = local.argocd_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port { number = 80 } # <-- force HTTP (matches --insecure)
            }
          }
        }
      }
    }

    dynamic "tls" {
      for_each = var.argocd_enable_tls ? [1] : []
      content {
        secret_name = var.argocd_tls_secret_name
        hosts       = [local.argocd_host]
      }
    }
  }

  depends_on = [helm_release.argocd]
}

output "argocd_url" {
  value = var.install_helmcharts ? format("%s://%s", var.argocd_enable_tls ? "https" : "http", local.argocd_host) : null
}

output "argocd_hosts_entry" {
  value = var.install_helmcharts ? (
    local.hosts_line != ""
    ? "Add to /etc/hosts:\n${local.hosts_line}"
    : "LB IP not ready yet. Then run:\n  kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
  ) : null
}
